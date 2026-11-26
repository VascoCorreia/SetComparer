-- SetComparer: Equipment-set comparison tooltips
-- When the default item comparison is shown (shift-hover), adds one extra tooltip per
-- saved Equipment Manager set, showing that set's item for the same slot.

local ADDON_NAME, SetComparer = ...

local band, rshift, lshift = bit.band, bit.rshift, bit.lshift

---------------------------------------------------------------------------
-- Static data
---------------------------------------------------------------------------

local SLOTS_BY_EQUIPLOC = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_BODY = { 4 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_WEAPON = { 16, 17 },
	INVTYPE_2HWEAPON = { 16 },
	INVTYPE_WEAPONMAINHAND = { 16 },
	INVTYPE_WEAPONOFFHAND = { 17 },
	INVTYPE_SHIELD = { 17 },
	INVTYPE_HOLDABLE = { 17 },
	INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 },
	INVTYPE_RELIC = { 18 },
	INVTYPE_TABARD = { 19 },
}

local SLOT_LABELS = {
	[11] = "Ring 1", [12] = "Ring 2",
	[13] = "Trinket 1", [14] = "Trinket 2",
	[16] = "Main Hand", [17] = "Off Hand",
}

-- Equipment set location encoding (see Blizzard EquipmentManager)
local LOC_PLAYER = ITEM_INVENTORY_LOCATION_PLAYER or 0x00100000
local LOC_BAGS = ITEM_INVENTORY_LOCATION_BAGS or 0x00200000
local LOC_BANK = ITEM_INVENTORY_LOCATION_BANK or 0x00400000
-- Fallbacks match the live retail client (bank tabs hold 98 slots, so the slot
-- part needs 8 bits; containers 0-5 are bags + reagent bag, so bank tabs start at 6).
local BAG_BIT_OFFSET = ITEM_INVENTORY_BAG_BIT_OFFSET or 8
local BANK_BAG_OFFSET = ITEM_INVENTORY_BANK_BAG_OFFSET or 5
local LOC_MASK = 0x000FFFFF

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function GetInstantInfo(item)
	if C_Item and C_Item.GetItemInfoInstant then
		return C_Item.GetItemInfoInstant(item)
	end
	return GetItemInfoInstant(item)
end

local function LinkItemID(link)
	if not link then return nil end
	return tonumber(link:match("item:(%d+)"))
end

local function GetContainerLink(bag, slot)
	if C_Container and C_Container.GetContainerItemLink then
		return C_Container.GetContainerItemLink(bag, slot)
	elseif GetContainerItemLink then
		return GetContainerItemLink(bag, slot)
	end
end

-- Returns isPlayer, isBank, isBags, slot, bag
local function DecodeLocation(loc)
	local isPlayer = band(loc, LOC_PLAYER) ~= 0
	local isBank = band(loc, LOC_BANK) ~= 0
	local isBags = band(loc, LOC_BAGS) ~= 0
	local rest = band(loc, LOC_MASK)
	if isBags then
		local bag = rshift(rest, BAG_BIT_OFFSET)
		local slot = rest - lshift(bag, BAG_BIT_OFFSET)
		if isBank then bag = bag + BANK_BAG_OFFSET end
		return isPlayer, isBank, true, slot, bag
	end
	return isPlayer, isBank, false, rest, nil
end

-- Shared with the addon's other files (SetBank.lua)
SetComparer.DecodeLocation = DecodeLocation
SetComparer.GetContainerLink = GetContainerLink
SetComparer.LinkItemID = LinkItemID

-- Work out where a set's item for an inventory slot lives.
-- Returns nil when the set has nothing (or ignores) that slot, else a table:
--   { kind = "inv"|"bag"|"saved"|"id", itemID, link, slot, bag, worn, seen }
-- "saved": not readable right now, but we saved its exact link earlier (see SnapshotSets)
-- "id": not readable and never seen, only the generic item ID is known
local function ResolveSetItem(setID, invSlot)
	local ids = C_EquipmentSet.GetItemIDs(setID)
	local locs = C_EquipmentSet.GetItemLocations(setID)
	local itemID = ids and ids[invSlot]
	local loc = locs and locs[invSlot]

	if loc == 0 or loc == 1 then return nil end -- empty / ignored slot
	if (not itemID or itemID == 0) and (not loc or loc <= 1) then return nil end
	if itemID == 0 then itemID = nil end

	if loc and loc > 1 then
		local isPlayer, isBank, isBags, slot, bag = DecodeLocation(loc)
		if isBags then
			local link = GetContainerLink(bag, slot)
			if link and (not itemID or LinkItemID(link) == itemID) then
				return { kind = "bag", bag = bag, slot = slot, link = link, itemID = LinkItemID(link) }
			end
		elseif isPlayer or isBank then
			local link = GetInventoryItemLink("player", slot)
			if link and (not itemID or LinkItemID(link) == itemID) then
				return {
					kind = "inv", slot = slot, link = link, itemID = LinkItemID(link),
					worn = isPlayer and not isBank and slot >= 1 and slot <= 19,
				}
			end
		end
	end

	if itemID then
		local saved = SetComparerCharDB and SetComparerCharDB.savedItems
		saved = saved and saved[setID] and saved[setID][invSlot]
		if saved and LinkItemID(saved.link) == itemID then
			return { kind = "saved", itemID = itemID, link = saved.link, seen = saved.seen }
		end
		return { kind = "id", itemID = itemID }
	end
	return nil
end

---------------------------------------------------------------------------
-- Tooltip pool
---------------------------------------------------------------------------

local pool = {}       -- our tooltips, in creation order
local isOurs = {}     -- [frame] = true
local hookedFrames = {}
local activeOwner     -- tooltip the set frames are currently attached to
local activeKey       -- cache key of what is currently displayed
local needsInfoRefresh -- displayed an item that may not be cached yet (redraw on GET_ITEM_INFO_RECEIVED)

local function CreateHeader(tt)
	local h = CreateFrame("Frame", nil, tt, BackdropTemplateMixin and "BackdropTemplate" or nil)
	if h.SetBackdrop then
		h:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		h:SetBackdropColor(0, 0, 0, 0.9)
		h:SetBackdropBorderColor(1, 0.82, 0, 1)
	end
	h.text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	h.text:SetPoint("CENTER", 0, 0)
	h:SetPoint("BOTTOMLEFT", tt, "TOPLEFT", 0, -1)
	h:SetHeight(20)
	tt.scHeader = h
end

local function GetTooltip(i)
	local tt = pool[i]
	if not tt then
		local name = "SetComparerTooltip" .. i
		tt = CreateFrame("GameTooltip", name, UIParent, "GameTooltipTemplate")
		tt:SetFrameStrata("TOOLTIP")
		CreateHeader(tt)
		pool[i] = tt
		isOurs[tt] = true
	end
	return tt
end

local function HideAll()
	for _, tt in ipairs(pool) do
		tt:Hide()
	end
	activeOwner = nil
	activeKey = nil
	needsInfoRefresh = nil
end

---------------------------------------------------------------------------
-- Layout: chain set tooltips beside the existing compare tooltips
---------------------------------------------------------------------------

local function ScreenLeft(f) return f:GetLeft() * f:GetEffectiveScale() end
local function ScreenRight(f) return f:GetRight() * f:GetEffectiveScale() end
local function ScreenCenterX(f) return (f:GetCenter()) * f:GetEffectiveScale() end

local function Layout(owner, tooltips)
	if not owner:GetLeft() then return end
	local screenW = UIParent:GetRight() * UIParent:GetEffectiveScale()

	-- Outermost frames on each side, starting from the main tooltip
	local leftFrame, rightFrame = owner, owner
	local leftEdge, rightEdge = ScreenLeft(owner), ScreenRight(owner)
	local compareSide
	local ownerCenter = ScreenCenterX(owner)

	for _, st in ipairs(owner.shoppingTooltips or {}) do
		if st:IsShown() and st:GetLeft() then
			local l, r = ScreenLeft(st), ScreenRight(st)
			if l < leftEdge then leftFrame, leftEdge = st, l end
			if r > rightEdge then rightFrame, rightEdge = st, r end
			if not compareSide then
				compareSide = (ScreenCenterX(st) < ownerCenter) and "left" or "right"
			end
		end
	end

	local side = compareSide
	local switched = false
	for _, tt in ipairs(tooltips) do
		local w = tt:GetWidth() * tt:GetEffectiveScale()
		if not side then
			side = (rightEdge + w <= screenW) and "right" or "left"
		end
		if not switched then
			if side == "left" and leftEdge - w < 0 then
				side, switched = "right", true
			elseif side == "right" and rightEdge + w > screenW then
				side, switched = "left", true
			end
		end

		tt:ClearAllPoints()
		if side == "left" then
			tt:SetPoint("TOPRIGHT", leftFrame, "TOPLEFT", 0, 0)
			leftFrame, leftEdge = tt, leftEdge - w
		else
			tt:SetPoint("TOPLEFT", rightFrame, "TOPRIGHT", 0, 0)
			rightFrame, rightEdge = tt, rightEdge + w
		end
	end
end

---------------------------------------------------------------------------
-- Main update
---------------------------------------------------------------------------

local dataVersion = 0

-- Settings helpers (used by Options.lua and SetBank.lua)
function SetComparer.IsSetCompared(setID)
	local hidden = SetComparerCharDB and SetComparerCharDB.hiddenSets
	return not (hidden and hidden[setID])
end

function SetComparer.SetSetCompared(setID, compared)
	SetComparerCharDB.hiddenSets[setID] = (not compared) or nil
	SetComparer.RefreshCompare()
end

function SetComparer.SetCompareEnabled(enabled)
	SetComparerDB.enabled = enabled and true or false
	SetComparer.RefreshCompare()
end

-- Forget what is displayed so the next shift-hover rebuilds with the current settings
function SetComparer.RefreshCompare()
	dataVersion = dataVersion + 1
	HideAll()
end

function SetComparer.SetStatChangesEnabled(enabled)
	SetComparerDB.showStatChanges = enabled and true or false
	SetComparer.RefreshCompare()
end

---------------------------------------------------------------------------
-- Saved item links: remember each set item's exact copy (enchant, suffix, gems)
-- while it is readable, so it can still be shown once it is out of reach (bank closed)
---------------------------------------------------------------------------

-- SetComparerCharDB.savedItems[setID][invSlot] = { link = "<item link>", seen = time() }
local function SnapshotSets()
	local db = SetComparerCharDB and SetComparerCharDB.savedItems
	if not db or not C_EquipmentSet then return false end
	local changed = false
	local exists = {}
	local now = time()
	for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
		exists[setID] = true
		local ids = C_EquipmentSet.GetItemIDs(setID) or {}
		local saved = db[setID] or {}
		for slot = 1, 19 do
			local expected = ids[slot]
			if expected == 0 then expected = nil end
			local entry = saved[slot]
			-- Slot emptied, or the set now uses a different item: forget the old copy
			if entry and LinkItemID(entry.link) ~= expected then
				saved[slot], entry, changed = nil, nil, true
			end
			if expected then
				local item = ResolveSetItem(setID, slot)
				if item and (item.kind == "inv" or item.kind == "bag") and item.link then
					if not entry or entry.link ~= item.link then changed = true end
					saved[slot] = { link = item.link, seen = now }
				end
			end
		end
		db[setID] = next(saved) and saved or nil
	end
	for setID in pairs(db) do
		if not exists[setID] then
			db[setID], changed = nil, true
		end
	end
	if changed then SetComparer.RefreshCompare() end
	return changed
end
SetComparer.SnapshotSets = SnapshotSets

-- Several triggering events fire in bursts: run the snapshot once, on the next frame
local snapshotPending
local function RunSnapshot()
	snapshotPending = nil
	SnapshotSets()
end
local function ScheduleSnapshot()
	if snapshotPending then return end
	if C_Timer and C_Timer.After then
		snapshotPending = true
		C_Timer.After(0, RunSnapshot)
	else
		SnapshotSets()
	end
end


---------------------------------------------------------------------------
-- Stat changes ("If you replace this item, ...") for set frames
---------------------------------------------------------------------------

-- Same order as the default compare tooltip; anything else follows alphabetically
local STAT_ORDER = {
	"RESISTANCE0_NAME",
	"ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_INTELLECT_SHORT",
	"ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_STAMINA_SHORT",
	"ITEM_MOD_SPELL_POWER_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT",
	"ITEM_MOD_HIT_RATING_SHORT", "ITEM_MOD_CRIT_RATING_SHORT",
	"ITEM_MOD_DAMAGE_PER_SECOND_SHORT",
}
local STAT_RANK = {}
for i, key in ipairs(STAT_ORDER) do STAT_RANK[key] = i end

local function GetStats(link)
	if not link then return {} end
	local stats
	if C_Item and C_Item.GetItemStats then
		stats = C_Item.GetItemStats(link)
	elseif GetItemStats then
		stats = GetItemStats(link)
	end
	return stats or {}
end

local function FormatDelta(v)
	if v == math.floor(v) then return string.format("%+d", v) end
	return string.format("%+.1f", v)
end

-- Appends the stat difference of wearing hoveredLink instead of setLink
local function AddStatDelta(tt, hoveredLink, setLink)
	local new, old = GetStats(hoveredLink), GetStats(setLink)
	local deltas = {}
	local seen = {}
	for _, t in ipairs({ new, old }) do
		for key in pairs(t) do
			if not seen[key] then
				seen[key] = true
				local d = (tonumber(new[key]) or 0) - (tonumber(old[key]) or 0)
				local name = _G[key]
				if d ~= 0 and type(name) == "string" then
					deltas[#deltas + 1] = { key = key, name = name, value = d }
				end
			end
		end
	end
	if #deltas == 0 then return end

	table.sort(deltas, function(a, b)
		local ra, rb = STAT_RANK[a.key], STAT_RANK[b.key]
		if ra and rb then return ra < rb end
		if ra or rb then return ra ~= nil end
		return a.name < b.name
	end)

	tt:AddLine(" ")
	tt:AddLine(ITEM_DELTA_DESCRIPTION or "If you replace this item, the following stat changes will occur:", 1, 0.82, 0, true)
	for _, d in ipairs(deltas) do
		if d.value > 0 then
			tt:AddLine(FormatDelta(d.value) .. " " .. d.name, 0, 1, 0)
		else
			tt:AddLine(FormatDelta(d.value) .. " " .. d.name, 1, 0, 0)
		end
	end
end

local function Update(owner)
	if not (SetComparerDB and SetComparerDB.enabled) then return end
	if not owner or isOurs[owner] or not owner.GetItem then return end
	if not C_EquipmentSet or C_EquipmentSet.GetNumEquipmentSets() == 0 then
		HideAll()
		return
	end

	local _, link = owner:GetItem()
	if not link then HideAll() return end

	local _, _, _, equipLoc = GetInstantInfo(link)
	local slots = equipLoc and SLOTS_BY_EQUIPLOC[equipLoc]
	if not slots then HideAll() return end

	local key = tostring(owner) .. link .. "#" .. dataVersion
	if key == activeKey and activeOwner == owner and pool[1] and pool[1]:IsShown() then
		return
	end

	-- Collect set items, merging identical items from different sets
	local entries, byItem = {}, {}
	for _, setID in ipairs(C_EquipmentSet.GetEquipmentSetIDs() or {}) do
		local setName = C_EquipmentSet.GetEquipmentSetInfo(setID)
		for _, slot in ipairs(SetComparer.IsSetCompared(setID) and slots or {}) do
			local item = ResolveSetItem(setID, slot)
			local skip = not item
			if item then
				-- Same item you're wearing in a compared slot: already shown by default compare
				if item.worn then
					for _, s in ipairs(slots) do
						if item.slot == s then skip = true end
					end
				elseif item.kind == "id" or item.kind == "saved" then
					for _, s in ipairs(slots) do
						if GetInventoryItemID("player", s) == item.itemID then skip = true end
					end
				end
				-- The exact item you're hovering
				if item.link and item.link == link then skip = true end
			end

			if not skip then
				local itemKey = item.link or ("id:" .. item.itemID)
				local entry = byItem[itemKey]
				if not entry then
					entry = { item = item, names = {}, slot = slot }
					byItem[itemKey] = entry
					entries[#entries + 1] = entry
				elseif entry.item.kind == "saved" and item.kind ~= "saved" then
					entry.item = item -- same copy is readable via another set: show it live
				end
				local label = setName or "?"
				if #slots > 1 and SLOT_LABELS[slot] then
					label = label .. " (" .. SLOT_LABELS[slot] .. ")"
				end
				entry.names[#entry.names + 1] = label
			end
		end
	end

	-- Hide stale
	for i = #entries + 1, #pool do pool[i]:Hide() end
	if #entries == 0 then
		activeKey, activeOwner = key, owner
		return
	end

	local shown = {}
	needsInfoRefresh = nil
	local scale = owner:GetScale()
	local showStats = SetComparerDB.showStatChanges ~= false
	for i, entry in ipairs(entries) do
		local tt = GetTooltip(i)
		tt:SetScale(scale)
		tt:SetOwner(owner, "ANCHOR_NONE")
		tt:ClearLines()
		local item = entry.item
		if item.kind == "inv" then
			tt:SetInventoryItem("player", item.slot)
			if showStats then AddStatDelta(tt, link, item.link) end
		elseif item.kind == "bag" then
			tt:SetBagItem(item.bag, item.slot)
			if showStats then AddStatDelta(tt, link, item.link) end
		elseif item.kind == "saved" then
			tt:SetHyperlink(item.link)
			needsInfoRefresh = true
			if showStats then AddStatDelta(tt, link, item.link) end		else
			tt:SetItemByID(item.itemID)
			needsInfoRefresh = true
			if showStats then
				local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
				local setLink = getInfo and select(2, getInfo(item.itemID))
				-- Not cached yet: GET_ITEM_INFO_RECEIVED redraws once it is
				if setLink then AddStatDelta(tt, link, setLink) end
			end
			tt:AddLine("(item never seen - base stats shown)", 0.6, 0.6, 0.6)
		end
		tt.scHeader.text:SetText("Set: " .. table.concat(entry.names, ", "))
		tt.scHeader:SetWidth(tt.scHeader.text:GetStringWidth() + 20)
		tt:Show()
		shown[#shown + 1] = tt
	end

	Layout(owner, shown)
	activeKey, activeOwner = key, owner
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

local function HookHide(frame)
	if not frame or hookedFrames[frame] or isOurs[frame] then return end
	hookedFrames[frame] = true
	frame:HookScript("OnHide", HideAll)
end

local function OnShowCompare(tooltip)
	tooltip = tooltip or GameTooltip
	if isOurs[tooltip] then return end
	HookHide(tooltip)
	if tooltip.shoppingTooltips then
		HookHide(tooltip.shoppingTooltips[1])
	end
	Update(tooltip)
end

if GameTooltip_ShowCompareItem then
	hooksecurefunc("GameTooltip_ShowCompareItem", OnShowCompare)
elseif TooltipComparisonManager and TooltipComparisonManager.CompareItem then
	hooksecurefunc(TooltipComparisonManager, "CompareItem", function(_, _, tooltip)
		OnShowCompare(tooltip)
	end)
end

if GameTooltip_HideShoppingTooltips then
	hooksecurefunc("GameTooltip_HideShoppingTooltips", function(tooltip)
		if not isOurs[tooltip] and (not activeOwner or tooltip == activeOwner) then
			HideAll()
		end
	end)
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("MODIFIER_STATE_CHANGED")
events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
events:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("PLAYER_LOGIN")
for _, ev in ipairs({ "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do
	pcall(events.RegisterEvent, events, ev) -- not every client has every event
end

-- Events after which a set's items may be readable (or different): re-save their links
local SNAPSHOT_EVENTS = {
	PLAYER_LOGIN = true, -- sets and items are loaded by now (ADDON_LOADED is too early)
	EQUIPMENT_SETS_CHANGED = true,
	PLAYER_EQUIPMENT_CHANGED = true,
	BAG_UPDATE_DELAYED = true,
	BANKFRAME_OPENED = true,
	PLAYERBANKSLOTS_CHANGED = true,
}

events:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 == ADDON_NAME then
			SetComparerDB = SetComparerDB or {}
			if SetComparerDB.enabled == nil then SetComparerDB.enabled = true end
			if SetComparerDB.showBankButtons == nil then SetComparerDB.showBankButtons = true end
			if SetComparerDB.showStatChanges == nil then SetComparerDB.showStatChanges = true end
			-- Per character: set IDs are per character. Sets not listed here are compared.
			SetComparerCharDB = SetComparerCharDB or {}
			SetComparerCharDB.hiddenSets = SetComparerCharDB.hiddenSets or {}
			SetComparerCharDB.savedItems = SetComparerCharDB.savedItems or {}
		end
	elseif event == "MODIFIER_STATE_CHANGED" then
		if pool[1] and pool[1]:IsShown() and not IsModifiedClick("COMPAREITEMS")
			and not (GetCVarBool and GetCVarBool("alwaysCompareItems")) then
			HideAll()
		end
	elseif event == "GET_ITEM_INFO_RECEIVED" then
		if needsInfoRefresh and activeOwner and activeOwner:IsShown() then
			local owner = activeOwner
			activeKey = nil
			Update(owner)
		end
	elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
		local banker = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker
		if banker and arg1 == banker then
			dataVersion = dataVersion + 1
			ScheduleSnapshot()
		end
	else
		dataVersion = dataVersion + 1
		if SNAPSHOT_EVENTS[event] then ScheduleSnapshot() end
	end
end)

---------------------------------------------------------------------------
-- Slash command
---------------------------------------------------------------------------

SLASH_SETCOMPARER1 = "/setcompare"
SlashCmdList.SETCOMPARER = function(msg)
	msg = (msg or ""):lower()
	if msg:match("^%s*toggle") then
		-- Quick on/off without opening the panel
		SetComparer.SetCompareEnabled(not SetComparerDB.enabled)
		if SetComparer.RefreshOptions then SetComparer.RefreshOptions() end
		print("|cffffd100SetComparer|r set comparison " .. (SetComparerDB.enabled and "|cff00ff00enabled|r" or "|cffff0000disabled|r"))
		return
	end
	-- /setcompare (and anything else) opens the options panel
	if SetComparer.OpenOptions then
		SetComparer.OpenOptions()
	end
end
