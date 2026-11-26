-- SetComparer: bank buttons for each set in the Equipment Manager.
--   Bag icon:   take the set's items from the bank into your bags.
--   Chest icon: put the set's items from your bags into the bank.

local _, SetComparer = ...

local DecodeLocation = SetComparer.DecodeLocation
local GetContainerLink = SetComparer.GetContainerLink
local LinkItemID = SetComparer.LinkItemID

local LOC_EMPTY, LOC_IGNORED, LOC_MISSING = 0, 1, -1
local NUM_CHARACTER_BANK_TABS = 6

---------------------------------------------------------------------------
-- Container helpers (C_Container with fallbacks to the old globals)
---------------------------------------------------------------------------

local function NumSlots(bag)
	if C_Container and C_Container.GetContainerNumSlots then
		return C_Container.GetContainerNumSlots(bag) or 0
	end
	return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function NumFreeSlots(bag)
	if C_Container and C_Container.GetContainerNumFreeSlots then
		return C_Container.GetContainerNumFreeSlots(bag)
	end
	return GetContainerNumFreeSlots(bag)
end

local function UseItem(bag, slot)
	if C_Container and C_Container.UseContainerItem then
		C_Container.UseContainerItem(bag, slot)
	else
		UseContainerItem(bag, slot)
	end
end

-- Your bags: backpack + 4 bags. The reagent bag (5) can't hold gear.
local function GetBagContainers()
	local list = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		if NumSlots(bag) > 0 then list[#list + 1] = bag end
	end
	return list
end

-- Character bank tabs (containers 6-11 on this client), plus the old-style
-- main bank container if it has any slots. Unbought tabs have 0 slots.
local function GetBankContainers()
	local list, seen = {}, {}
	local function add(bag)
		if bag and not seen[bag] and NumSlots(bag) > 0 then
			seen[bag] = true
			list[#list + 1] = bag
		end
	end
	local BagIndex = Enum and Enum.BagIndex
	if BagIndex and BagIndex.CharacterBankTab_1 then
		for i = 1, NUM_CHARACTER_BANK_TABS do add(BagIndex["CharacterBankTab_" .. i]) end
	else
		local first = (NUM_BAG_SLOTS or 4) + 2 -- bags 0-4, reagent bag 5
		for bag = first, first + NUM_CHARACTER_BANK_TABS - 1 do add(bag) end
	end
	add(BANK_CONTAINER)
	return list
end

-- Free slots that can hold gear (bag family 0 = ordinary bag / bank tab)
local function FreeSlots(containers)
	local free = 0
	for _, bag in ipairs(containers) do
		local n, family = NumFreeSlots(bag)
		if n and (family == nil or family == 0) then
			free = free + n
		end
	end
	return free
end

---------------------------------------------------------------------------
-- Finding a set's items in the bank or in your bags
---------------------------------------------------------------------------

-- source is "bank" or "bags". Returns a list of { bag, slot, itemID } for every
-- item of the set found there. Each container position is used at most once.
local function FindSetItems(setID, source)
	local ids = C_EquipmentSet.GetItemIDs(setID) or {}
	local locs = C_EquipmentSet.GetItemLocations(setID) or {}
	local wantBank = (source == "bank")
	local containers = wantBank and GetBankContainers() or GetBagContainers()
	local taken, found = {}, {}

	local function scanFor(itemID)
		for _, bag in ipairs(containers) do
			for slot = 1, NumSlots(bag) do
				if not taken[bag .. ":" .. slot] and LinkItemID(GetContainerLink(bag, slot)) == itemID then
					return bag, slot
				end
			end
		end
	end

	for invSlot = 1, 19 do
		local itemID, loc = ids[invSlot], locs[invSlot]
		if itemID and itemID ~= 0 and loc and loc ~= LOC_EMPTY and loc ~= LOC_IGNORED then
			-- Missing items are only looked for in the bank (the game would know if they were in your bags)
			local inSource, bag, slot = (loc == LOC_MISSING and wantBank), nil, nil
			if loc > LOC_IGNORED then
				local _, isBank, isBags, s, b = DecodeLocation(loc)
				if wantBank then
					inSource = isBank
				else
					inSource = isBags and not isBank
				end
				-- Trust the decoded position only if it really holds this item
				if inSource and isBags and not taken[b .. ":" .. s]
					and LinkItemID(GetContainerLink(b, s)) == itemID then
					bag, slot = b, s
				end
			end
			if inSource then
				if not bag then bag, slot = scanFor(itemID) end
				if bag then
					taken[bag .. ":" .. slot] = true
					found[#found + 1] = { bag = bag, slot = slot, itemID = itemID }
				end
			end
		end
	end
	return found
end

function SetComparer.FindSetItemsInBank(setID) return FindSetItems(setID, "bank") end
function SetComparer.FindSetItemsInBags(setID) return FindSetItems(setID, "bags") end

---------------------------------------------------------------------------
-- Moving items
---------------------------------------------------------------------------

local bankOpen = false

function SetComparer.IsBankOpen() return bankOpen end

local function ErrorText(msg, r, g, b)
	UIErrorsFrame:AddMessage(msg, r or 1.0, g or 0.1, b or 0.1, 1.0)
end

-- source "bank": bank -> bags. source "bags": bags -> bank.
-- With the bank open, "using" an item moves it to the other side.
local function MoveSet(setID, source)
	if not bankOpen then
		ErrorText("Bank not open")
		return 0
	end

	local toBags = (source == "bank")
	local setName = C_EquipmentSet.GetEquipmentSetInfo(setID) or "?"
	local items = FindSetItems(setID, source)
	if #items == 0 then
		ErrorText(("No items from %s in %s"):format(setName, toBags and "bank" or "bags"), 1.0, 0.82, 0)
		return 0
	end

	local free = FreeSlots(toBags and GetBagContainers() or GetBankContainers())
	local moved = 0
	for _, item in ipairs(items) do
		if moved >= free then break end
		UseItem(item.bag, item.slot)
		moved = moved + 1
	end

	if moved < #items then
		ErrorText(("Not enough %s space (moved %d of %d)"):format(toBags and "bag" or "bank", moved, #items))
	end
	if moved > 0 then
		print(("|cffffd100SetComparer|r: moved %d item%s of %s %s bank."):format(
			moved, moved == 1 and "" or "s", setName, toBags and "from" or "to"))
	end
	return moved
end

function SetComparer.TakeSetFromBank(setID) return MoveSet(setID, "bank") end
function SetComparer.PutSetInBank(setID) return MoveSet(setID, "bags") end

---------------------------------------------------------------------------
-- Equipment Manager row buttons
---------------------------------------------------------------------------

-- Listed right to left: the first button sits just left of the equipped checkmark,
-- each following button sits left of the previous one.
local BUTTONS = {
	{ key = "scBankBtn", source = "bank", icon = "Interface\\Icons\\INV_Misc_Bag_10",
		title = "Take items from bank", where = "bank" },
	{ key = "scDepositBtn", source = "bags", icon = "Interface\\Icons\\INV_Box_02",
		title = "Put items in bank", where = "bags" },
}
local BUTTON_SIZE, BUTTON_GAP = 16, 2
local CHECK_FALLBACK_OFFSET = -32 -- from the row's right edge, when the row has no .Check

local function IsFrame(x)
	return type(x) == "table" and type(x.GetObjectType) == "function"
end

-- The data a scroll-box row currently shows (a plain table), if the client provides it
local function RowElementData(row)
	if type(row.GetElementData) == "function" then
		local ok, data = pcall(row.GetElementData, row)
		if ok and type(data) == "table" and not IsFrame(data) then return data end
	end
end

-- The set a row currently shows. Rows are recycled, so this is read at click time.
local function RowSetID(row)
	local data = RowElementData(row)
	if data then
		if data.setID then return data.setID end
		if data.addSetButton then return nil end -- the "New Set" row
	end
	if row.setID then return row.setID end
	if row.name and row.name ~= "" and C_EquipmentSet.GetEquipmentSetID then
		return C_EquipmentSet.GetEquipmentSetID(row.name)
	end
end

local function Button_OnClick(self)
	local setID = RowSetID(self:GetParent())
	if setID then MoveSet(setID, self.scDef.source) end
end

local function Button_OnEnter(self)
	local def = self.scDef
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip:SetText(def.title)
	local setID = RowSetID(self:GetParent())
	if not bankOpen then
		GameTooltip:AddLine("Open your bank first", 1, 0.1, 0.1)
	elseif setID then
		local n = #FindSetItems(setID, def.source)
		GameTooltip:AddLine(("%d item%s of this set %s in your %s"):format(
			n, n == 1 and "" or "s", n == 1 and "is" or "are", def.where), 1, 1, 1)
	end
	GameTooltip:Show()
end

local function Button_OnLeave()
	GameTooltip:Hide()
end

local function DecorateRow(row)
	if not IsFrame(row) then return end
	local showButtons = not (SetComparerDB and SetComparerDB.showBankButtons == false)
	local hasSet = showButtons and RowSetID(row) ~= nil
	local prev
	for _, def in ipairs(BUTTONS) do
		local btn = row[def.key]
		if not btn then
			btn = CreateFrame("Button", nil, row)
			btn.scDef = def
			btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
			if prev then
				btn:SetPoint("RIGHT", prev, "LEFT", -BUTTON_GAP, 0)
			elseif row.Check then
				-- Keep clear of the green "equipped" checkmark
				btn:SetPoint("RIGHT", row.Check, "LEFT", -BUTTON_GAP, 0)
			else
				btn:SetPoint("RIGHT", row, "RIGHT", CHECK_FALLBACK_OFFSET, 0)
			end
			btn:SetFrameLevel(row:GetFrameLevel() + 5)
			btn:SetNormalTexture(def.icon)
			btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
			btn:SetScript("OnClick", Button_OnClick)
			btn:SetScript("OnEnter", Button_OnEnter)
			btn:SetScript("OnLeave", Button_OnLeave)
			row[def.key] = btn
		end
		btn:SetShown(hasSet)
		prev = btn
	end
end

local function GetPane()
	return PaperDollEquipmentManagerPane or (PaperDollFrame and PaperDollFrame.EquipmentManagerPane)
end

-- All row frames currently in the set list. Asks the list for its rows instead of
-- relying on the argument order of the row-init callback (which differs between clients).
local function GetRows(pane)
	local box = pane.ScrollBox
	if box then
		if type(box.GetFrames) == "function" then
			local ok, frames = pcall(box.GetFrames, box)
			if ok and type(frames) == "table" and #frames > 0 then return frames end
		end
		if box.ScrollTarget and box.ScrollTarget.GetChildren then
			return { box.ScrollTarget:GetChildren() }
		end
		return {}
	end
	return pane.buttons or {} -- older hybrid scroll frame
end

local function DecorateAllRows()
	local pane = GetPane()
	if not pane then return end
	for _, row in ipairs(GetRows(pane)) do DecorateRow(row) end
end

SetComparer.DecorateAllRows = DecorateAllRows

local paneHooked = false
local function HookEquipmentManager()
	if paneHooked then return end
	local pane = GetPane()
	if not pane then return end
	paneHooked = true

	if pane.ScrollBox and ScrollUtil and ScrollUtil.AddInitializedFrameCallback then
		-- Called whenever a row is (re)assigned to a set; arguments are ignored on purpose
		ScrollUtil.AddInitializedFrameCallback(pane.ScrollBox, DecorateAllRows, pane, true)
	end
	if PaperDollEquipmentManagerPane_Update then
		hooksecurefunc("PaperDollEquipmentManagerPane_Update", DecorateAllRows)
	end
	pane:HookScript("OnShow", DecorateAllRows)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
for _, ev in ipairs({
	"PLAYER_LOGIN", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
	"PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
}) do
	pcall(events.RegisterEvent, events, ev) -- not every client has every event
end

local function IsBankerInteraction(kind)
	local types = Enum and Enum.PlayerInteractionType
	return types and types.Banker and kind == types.Banker
end

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "PLAYER_LOGIN" then
		HookEquipmentManager()
	elseif event == "BANKFRAME_OPENED" then
		bankOpen = true
	elseif event == "BANKFRAME_CLOSED" then
		bankOpen = false
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
		if IsBankerInteraction(arg1) then bankOpen = true end
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
		if IsBankerInteraction(arg1) then bankOpen = false end
	end
end)

HookEquipmentManager()
