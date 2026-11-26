-- Mock WoW environment test harness for SetComparer.lua
-- Usage: lua test_setcomparer.lua SetComparer.lua SetBank.lua   (files in .toc order)
assert(arg[1], "pass addon file paths in .toc order")

---------------------------------------------------------------------------
-- Mock API
---------------------------------------------------------------------------
bit = {
	band = function(a, b) return a & b end,
	rshift = function(a, n) return a >> n end,
	lshift = function(a, n) return a << n end,
}

SCREEN_W = 1920
local calls = { SetBagItem = 0, SetInventoryItem = 0, SetItemByID = 0 }

local FrameMT = {}
FrameMT.__index = FrameMT
local function newFrame(kind, name)
	local f = setmetatable({ kind = kind, name = name, shown = false, width = 200, height = 150,
		scale = 1, scripts = {}, hooks = {}, lines = {}, points = {} }, FrameMT)
	if name then _G[name] = f end
	return f
end
function FrameMT:Show() local was = self.shown; self.shown = true end
function FrameMT:Hide()
	local was = self.shown
	self.shown = false
	if was then for _, h in ipairs(self.hooks.OnHide or {}) do h(self) end end
end
function FrameMT:IsShown() return self.shown end
function FrameMT:SetScript(s, fn) self.scripts[s] = fn end
function FrameMT:HookScript(s, fn) self.hooks[s] = self.hooks[s] or {}; table.insert(self.hooks[s], fn) end
function FrameMT:RegisterEvent(e) end
function FrameMT:SetFrameStrata() end
function FrameMT:SetScale(s) self.scale = s end
function FrameMT:GetScale() return self.scale end
function FrameMT:GetEffectiveScale() return self.scale end
function FrameMT:SetWidth(w) self.width = w end
function FrameMT:SetHeight(h) self.height = h end
function FrameMT:GetWidth() return self.width end
function FrameMT:SetBackdrop() end
function FrameMT:SetBackdropColor() end
function FrameMT:SetBackdropBorderColor() end
function FrameMT:ClearAllPoints() self.points = {}; self.x = nil end
function FrameMT:SetPoint(p, rel, rp, x, y) table.insert(self.points, { p, rel, rp, x or 0, y or 0 }) end
function FrameMT:GetLeft()
	if self.x then return self.x end
	local pt = self.points[1]
	if not pt then return nil end
	local p, rel, rp = pt[1], pt[2], pt[3]
	if p == "TOPRIGHT" and rp == "TOPLEFT" then return rel:GetLeft() - self.width end
	if p == "TOPLEFT" and rp == "TOPRIGHT" then return rel:GetRight() end
	if p == "BOTTOMLEFT" then return rel:GetLeft() end
	error("unsupported anchor " .. p .. "/" .. rp)
end
function FrameMT:GetRight() local l = self:GetLeft(); return l and (l + self.width) end
function FrameMT:GetCenter() local l = self:GetLeft(); return l + self.width / 2, 0 end
function FrameMT:CreateFontString()
	return { text = "", SetPoint = function() end,
		SetText = function(fs, t) fs.text = t end,
		GetText = function(fs) return fs.text end,
		SetJustifyH = function() end,
		SetTextColor = function(fs, r, g, b) fs.color = { r, g, b } end,
		GetStringWidth = function(fs) return #fs.text * 7 end }
end
-- check button methods
function FrameMT:SetChecked(c) self.checked = c and true or false end
function FrameMT:GetChecked() return self.checked end
function FrameMT:SetEnabled(e) self.enabled = e and true or false end
function FrameMT:IsEnabled() return self.enabled ~= false end
-- simulate a user click on a check button: toggle, then run OnClick
function FrameMT:ToggleClick() self.checked = not self.checked; self.scripts.OnClick(self) end
-- tooltip methods
function FrameMT:SetOwner(o) self.owner = o end
function FrameMT:ClearLines() self.lines = {}; self.content = nil end
function FrameMT:AddLine(t) table.insert(self.lines, t) end
function FrameMT:SetInventoryItem(u, slot) calls.SetInventoryItem = calls.SetInventoryItem + 1; self.content = "inv:" .. slot end
function FrameMT:SetBagItem(b, s) calls.SetBagItem = calls.SetBagItem + 1; self.content = "bag:" .. b .. ":" .. s end
function FrameMT:SetItemByID(id) calls.SetItemByID = calls.SetItemByID + 1; self.content = "id:" .. id end
function FrameMT:GetItem() return self.itemName, self.itemLink end
function FrameMT:SetText(t) self.lines = { t } end
-- button / generic frame methods
function FrameMT:SetSize(w, h) self.width, self.height = w, h end
function FrameMT:SetFrameLevel(l) self.level = l end
function FrameMT:GetFrameLevel() return self.level or 1 end
function FrameMT:SetNormalTexture(t) self.normalTexture = t end
function FrameMT:SetHighlightTexture() end
function FrameMT:SetShown(s) if s then self:Show() else self:Hide() end end
function FrameMT:GetParent() return self.parent end
function FrameMT:Click() self.scripts.OnClick(self, "LeftButton") end

function CreateFrame(kind, name, parent, template)
	local f = newFrame(kind, name)
	f.parent = parent
	return f
end

UIParent = newFrame("Frame", "UIParent")
UIParent.x = 0; UIParent.width = SCREEN_W

GameTooltip = newFrame("GameTooltip", "GameTooltip")
ShoppingTooltip1 = newFrame("GameTooltip", "ShoppingTooltip1")
ShoppingTooltip2 = newFrame("GameTooltip", "ShoppingTooltip2")
GameTooltip.shoppingTooltips = { ShoppingTooltip1, ShoppingTooltip2 }

-- Item database: id -> equipLoc
local ITEMS = {
	[100] = "INVTYPE_CHEST", [200] = "INVTYPE_CHEST", [300] = "INVTYPE_CHEST", [400] = "INVTYPE_CHEST",
	[500] = "INVTYPE_FINGER", [501] = "INVTYPE_FINGER", [502] = "INVTYPE_FINGER", [600] = "INVTYPE_FINGER",
	[900] = "INVTYPE_NON_EQUIP",
}
local function link(id) return "|cffffffff|Hitem:" .. id .. "::::|h[Item " .. id .. "]|h|r" end
C_Item = { GetItemInfoInstant = function(l)
	local id = tonumber(l:match("item:(%d+)"))
	return id, "Armor", "Mail", ITEMS[id]
end }

-- World state
local equipped, bags = {}, {}
function GetInventoryItemLink(u, slot) return equipped[slot] and link(equipped[slot]) end
function GetInventoryItemID(u, slot) return equipped[slot] end
-- Container sizes: bags 0-4, reagent bag 5 (family 1, gear can't go there), bank tabs 6-11
local bagSize = {}
local function defaultBagSizes()
	bagSize = { [0] = 16, [1] = 4, [2] = 4, [3] = 0, [4] = 0, [5] = 8, [6] = 98, [7] = 98, [8] = 0, [9] = 0, [10] = 0, [11] = 0 }
end
defaultBagSizes()
local used = { UseContainerItem = {} }
C_Container = {
	GetContainerItemLink = function(b, s) local id = bags[b .. ":" .. s]; return id and link(id) end,
	GetContainerNumSlots = function(b) return bagSize[b] or 0 end,
	GetContainerNumFreeSlots = function(b)
		local free = 0
		for s = 1, bagSize[b] or 0 do if not bags[b .. ":" .. s] then free = free + 1 end end
		return free, (b == 5) and 1024 or 0
	end,
	-- With the bank open, "using" an item moves it to the first free slot on the other side
	-- (bank tab -> bags 0-4, bag -> bank tabs 6-11)
	UseContainerItem = function(b, s)
		table.insert(used.UseContainerItem, b .. ":" .. s)
		local id = bags[b .. ":" .. s]
		if not id then return end
		local first, last = 0, 4
		if b >= 0 and b <= 4 then first, last = 6, 11 end
		for bag = first, last do
			for slot = 1, bagSize[bag] or 0 do
				if not bags[bag .. ":" .. slot] then
					bags[bag .. ":" .. slot] = id
					bags[b .. ":" .. s] = nil
					return
				end
			end
		end
	end,
}
Enum = {
	BagIndex = { CharacterBankTab_1 = 6, CharacterBankTab_2 = 7, CharacterBankTab_3 = 8,
		CharacterBankTab_4 = 9, CharacterBankTab_5 = 10, CharacterBankTab_6 = 11 },
	PlayerInteractionType = { Banker = 8 },
}
local errors = {}
UIErrorsFrame = { AddMessage = function(_, msg, r, g, b) table.insert(errors, { msg = msg, r = r, g = g, b = b }) end }

-- Equipment Manager pane with a modern scroll box
local initCallbacks = {}
-- How the client calls the row-init callback. "plain": (row, data); "owner": (pane, row, data);
-- "box": (scrollBox, row, data). The addon must work with all of them.
local callMode = "plain"
ScrollUtil = { AddInitializedFrameCallback = function(box, cb, owner, iterateExisting)
	table.insert(initCallbacks, cb)
end }
PaperDollEquipmentManagerPane = newFrame("Frame", "PaperDollEquipmentManagerPane")
local scrollBox = newFrame("Frame")
PaperDollEquipmentManagerPane.ScrollBox = scrollBox
local boxRows = {}
function scrollBox:GetFrames() return boxRows end
function FrameMT:GetObjectType() return self.kind end
function FrameMT:GetName() return self.name end
function FrameMT:GetElementData() return self.elementData end
local function initRow(row, elementData)
	local known = false
	for _, r in ipairs(boxRows) do if r == row then known = true end end
	if not known then boxRows[#boxRows + 1] = row end
	row.elementData = elementData
	row.setID = elementData and elementData.setID
	for _, cb in ipairs(initCallbacks) do
		if callMode == "owner" then cb(PaperDollEquipmentManagerPane, row, elementData)
		elseif callMode == "box" then cb(scrollBox, row, elementData)
		else cb(row, elementData) end
	end
end

local sets = {} -- { id, name, ids = {}, locs = {} }
C_EquipmentSet = {
	GetNumEquipmentSets = function() return #sets end,
	GetEquipmentSetIDs = function() local t = {}; for _, s in ipairs(sets) do t[#t + 1] = s.id end; return t end,
	GetEquipmentSetInfo = function(id) for _, s in ipairs(sets) do if s.id == id then return s.name, 0, id end end end,
	GetItemIDs = function(id) for _, s in ipairs(sets) do if s.id == id then return s.ids end end end,
	GetItemLocations = function(id) for _, s in ipairs(sets) do if s.id == id then return s.locs end end end,
	GetEquipmentSetID = function(name) for _, s in ipairs(sets) do if s.name == name then return s.id end end end,
}
local function LOC_WORN(slot) return 0x100000 + slot end
local function LOC_BAG(b, s) return 0x100000 + 0x200000 + (b << 8) + s end
local function LOC_BANK_TAB(tab, s) return 0x400000 + 0x200000 + (tab << 8) + s end

local shiftDown = true
function IsModifiedClick() return shiftDown end
function GetCVarBool() return false end
SlashCmdList = {}
-- Modern options window
local settingsLog = {}
Settings = {
	RegisterCanvasLayoutCategory = function(frame, name)
		local cat = { frame = frame, name = name, ID = 42 }
		function cat:GetID() return self.ID end
		settingsLog.category = cat
		return cat
	end,
	RegisterAddOnCategory = function(cat) settingsLog.registered = cat end,
	OpenToCategory = function(id) settingsLog.opened = id end,
}
NUM_BAG_SLOTS = 4
local printed = {}
function print(...) table.insert(printed, table.concat({ ... }, " ")) end

-- Default compare: shows shopping tooltips on the given side of GameTooltip
local compareSide = "left"
function GameTooltip_ShowCompareItem(tooltip)
	tooltip = tooltip or GameTooltip
	local _, l = tooltip:GetItem()
	local id = tonumber(l:match("item:(%d+)"))
	local loc = ITEMS[id]
	local slots = ({ INVTYPE_CHEST = { 5 }, INVTYPE_FINGER = { 11, 12 } })[loc] or {}
	local prev = tooltip
	for i, slot in ipairs(slots) do
		local st = tooltip.shoppingTooltips[i]
		if equipped[slot] then
			st:ClearAllPoints()
			if compareSide == "left" then st:SetPoint("TOPRIGHT", prev, "TOPLEFT") else st:SetPoint("TOPLEFT", prev, "TOPRIGHT") end
			st:Show()
			prev = st
		end
	end
end
function GameTooltip_HideShoppingTooltips(tooltip)
	for _, st in ipairs(tooltip.shoppingTooltips) do st:Hide() end
end
function hooksecurefunc(a, b, c)
	if type(a) == "string" then
		local orig = _G[a]
		_G[a] = function(...) local r = { orig(...) }; b(...); return table.unpack(r) end
	else
		local orig = a[b]
		a[b] = function(...) local r = { orig(...) }; c(...); return table.unpack(r) end
	end
end

---------------------------------------------------------------------------
-- Load addon
---------------------------------------------------------------------------
local created = {}
local baseCreate = CreateFrame
function CreateFrame(...) local f = baseCreate(...); created[#created + 1] = f; return f end

local addonTable = {} -- WoW passes the same table to every file of an addon
for i = 1, #arg do
	local chunk = assert(loadfile(arg[i]))
	chunk("SetComparer", addonTable)
end
local eventFrames = {}
for _, f in ipairs(created) do if f.scripts.OnEvent then eventFrames[#eventFrames + 1] = f end end
assert(#eventFrames > 0, "no event frame")
local function fire(ev, ...)
	for _, f in ipairs(eventFrames) do f.scripts.OnEvent(f, ev, ...) end
end
fire("ADDON_LOADED", "SetComparer")
fire("PLAYER_LOGIN")
assert(SetComparerDB and SetComparerDB.enabled == true, "DB init")

---------------------------------------------------------------------------
-- Test utilities
---------------------------------------------------------------------------
local passed, failed = 0, 0
local function check(name, cond, detail)
	if cond then passed = passed + 1; print_ok = true; io.write("PASS  ", name, "\n")
	else failed = failed + 1; io.write("FAIL  ", name, detail and ("  -- " .. tostring(detail)) or "", "\n") end
end

local function setTooltipFrames()
	local out = {}
	local i = 1
	while _G["SetComparerTooltip" .. i] do
		local tt = _G["SetComparerTooltip" .. i]
		if tt:IsShown() then out[#out + 1] = tt end
		i = i + 1
	end
	return out
end
local function describe(list)
	local t = {}
	for _, tt in ipairs(list) do t[#t + 1] = tt.scHeader.text.text .. "=" .. tostring(tt.content) end
	return table.concat(t, " | ")
end

local function reset()
	GameTooltip_HideShoppingTooltips(GameTooltip)
	GameTooltip:Hide()
	equipped, bags, sets = {}, {}, {}
	shiftDown = true
	compareSide = "left"
	GameTooltip.x = 800
	fire("EQUIPMENT_SETS_CHANGED")
end

local function hover(id)
	GameTooltip.itemLink = link(id)
	GameTooltip.itemName = "Item " .. id
	GameTooltip:Show()
	GameTooltip_ShowCompareItem(GameTooltip)
end

---------------------------------------------------------------------------
-- Scenarios
---------------------------------------------------------------------------

-- 1. Worn set skipped, bag set shown, positioned left of the Equipped frame
reset()
equipped[5] = 100
bags["0:3"] = 200
sets = {
	{ id = 1, name = "Healer", ids = { [5] = 100 }, locs = { [5] = LOC_WORN(5) } },
	{ id = 2, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } },
}
hover(300)
local s = setTooltipFrames()
check("1 one set frame shown (worn set skipped)", #s == 1, describe(s))
check("1 frame is Tank from bag 0 slot 3", s[1] and s[1].scHeader.text.text == "Set: Tank" and s[1].content == "bag:0:3", describe(s))
check("1 chained left of ShoppingTooltip1", s[1] and s[1]:GetRight() == ShoppingTooltip1:GetLeft(),
	s[1] and (s[1]:GetRight() .. " vs " .. ShoppingTooltip1:GetLeft()))

-- 2. Missing item falls back to item ID
reset()
equipped[5] = 100
sets = { { id = 1, name = "PvP", ids = { [5] = 400 }, locs = { [5] = -1 } } }
hover(300)
s = setTooltipFrames()
check("2 missing item uses ID fallback", #s == 1 and s[1].content == "id:400", describe(s))
check("2 fallback note added", s[1] and s[1].lines[1] and s[1].lines[1]:find("base stats") ~= nil)

-- 3. Empty / ignored slots produce nothing
reset()
equipped[5] = 100
sets = {
	{ id = 1, name = "Empty", ids = { [5] = 0 }, locs = { [5] = 0 } },
	{ id = 2, name = "Ignored", ids = {}, locs = { [5] = 1 } },
}
hover(300)
s = setTooltipFrames()
check("3 empty/ignored slots show nothing", #s == 0, describe(s))

-- 4. Rings: worn ring 1 skipped, bag ring 2 shown with slot label
reset()
equipped[11] = 500; equipped[12] = 501
bags["1:7"] = 502
sets = { { id = 1, name = "Tank", ids = { [11] = 500, [12] = 502 }, locs = { [11] = LOC_WORN(11), [12] = LOC_BAG(1, 7) } } }
hover(600)
s = setTooltipFrames()
check("4 only ring 2 shown", #s == 1 and s[1].scHeader.text.text == "Set: Tank (Ring 2)" and s[1].content == "bag:1:7", describe(s))
check("4 chained beyond ShoppingTooltip2", s[1] and s[1]:GetRight() == ShoppingTooltip2:GetLeft())

-- 4b. Set ring worn in the *other* ring slot is also skipped
reset()
equipped[11] = 500; equipped[12] = 501
sets = { { id = 1, name = "Swap", ids = { [11] = 501, [12] = 500 }, locs = { [11] = LOC_WORN(12), [12] = LOC_WORN(11) } } }
hover(600)
s = setTooltipFrames()
check("4b rings worn in swapped slots skipped", #s == 0, describe(s))

-- 5. Same item in two sets merges into one frame
reset()
equipped[5] = 100
bags["0:3"] = 200
sets = {
	{ id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } },
	{ id = 2, name = "PvP", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } },
}
hover(300)
s = setTooltipFrames()
check("5 merged frame for shared item", #s == 1 and s[1].scHeader.text.text == "Set: Tank, PvP", describe(s))

-- 6. Hovering the set's own item: skipped
reset()
equipped[5] = 100
bags["0:3"] = 200
sets = { { id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } } }
hover(200)
s = setTooltipFrames()
check("6 hovered item itself not duplicated", #s == 0, describe(s))

-- 7. Off-screen on the left: switches to the right of the main tooltip
reset()
equipped[5] = 100
bags["0:3"] = 200; bags["0:4"] = 400
GameTooltip.x = 250  -- compare frame at 50..250, no room for another on the left
sets = {
	{ id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } },
	{ id = 2, name = "PvP", ids = { [5] = 400 }, locs = { [5] = LOC_BAG(0, 4) } },
}
hover(300)
s = setTooltipFrames()
check("7 two frames shown", #s == 2, describe(s))
check("7 first frame to right of main tooltip", s[1] and s[1]:GetLeft() == GameTooltip:GetRight(), s[1] and s[1]:GetLeft())
check("7 second frame chained further right", s[2] and s[2]:GetLeft() == s[1]:GetRight())
for _, tt in ipairs(s) do check("7 frame on screen", tt:GetLeft() >= 0 and tt:GetRight() <= SCREEN_W) end

-- 8. Nothing equipped in slot: frames anchored to main tooltip
reset()
bags["0:3"] = 200
GameTooltip.x = 800
sets = { { id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } } }
hover(300)
s = setTooltipFrames()
check("8 frame shown with empty slot", #s == 1)
check("8 anchored to main tooltip right", s[1] and s[1]:GetLeft() == GameTooltip:GetRight())

-- 9. Cache: repeated compare calls don't rebuild
reset()
equipped[5] = 100
bags["0:3"] = 200
sets = { { id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } } }
hover(300)
local before = calls.SetBagItem
GameTooltip_ShowCompareItem(GameTooltip)
GameTooltip_ShowCompareItem(GameTooltip)
check("9 no rebuild on repeat calls", calls.SetBagItem == before, calls.SetBagItem - before)
fire("BAG_UPDATE_DELAYED")
GameTooltip_ShowCompareItem(GameTooltip)
check("9 rebuild after bag update", calls.SetBagItem == before + 1)

-- 10. Hide behaviours
shiftDown = false
fire("MODIFIER_STATE_CHANGED")
check("10 hidden on shift release", #setTooltipFrames() == 0)
shiftDown = true
hover(300)
check("10 shown again", #setTooltipFrames() == 1)
ShoppingTooltip1:Hide()
check("10 hidden when ShoppingTooltip1 hides", #setTooltipFrames() == 0)
hover(300)
GameTooltip:Hide()
check("10 hidden when main tooltip hides", #setTooltipFrames() == 0)
hover(300)
GameTooltip_HideShoppingTooltips(GameTooltip)
check("10 hidden via HideShoppingTooltips", #setTooltipFrames() == 0)

-- 11. Non-equippable and no-sets
hover(900)
check("11 non-equippable shows nothing", #setTooltipFrames() == 0)
sets = {}
hover(300)
check("11 no sets shows nothing", #setTooltipFrames() == 0)

-- 12. Fewer entries than pool hides stale frames
reset()
equipped[5] = 100
bags["0:3"] = 200; bags["0:4"] = 400
sets = {
	{ id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } },
	{ id = 2, name = "PvP", ids = { [5] = 400 }, locs = { [5] = LOC_BAG(0, 4) } },
}
hover(300)
check("12 two frames", #setTooltipFrames() == 2)
sets[2] = nil
fire("EQUIPMENT_SETS_CHANGED")
GameTooltip_ShowCompareItem(GameTooltip)
check("12 stale frame hidden", #setTooltipFrames() == 1, describe(setTooltipFrames()))

-- 13. Slash toggle
SlashCmdList.SETCOMPARER("toggle")
check("13 disabled hides frames", #setTooltipFrames() == 0 and SetComparerDB.enabled == false)
hover(300)
check("13 disabled shows nothing", #setTooltipFrames() == 0)
SlashCmdList.SETCOMPARER("toggle")
hover(300)
check("13 re-enabled works", #setTooltipFrames() == 1)

-- 14. Compare on the right side chains to the right
reset()
equipped[5] = 100
bags["0:3"] = 200
compareSide = "right"
GameTooltip.x = 300
sets = { { id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } } }
hover(300)
s = setTooltipFrames()
check("14 chained right of ShoppingTooltip1", s[1] and s[1]:GetLeft() == ShoppingTooltip1:GetRight())

-- 15. Bank tab item, using a real location captured in-game (bank tab 2, slot 6 = container 7)
reset()
equipped[5] = 100
bags["7:6"] = 200
check("15 helper reproduces real in-game value", LOC_BANK_TAB(2, 6) == 6291974, LOC_BANK_TAB(2, 6))
sets = { { id = 1, name = "Bank", ids = { [5] = 200 }, locs = { [5] = 6291974 } } }
hover(300)
s = setTooltipFrames()
check("15 bank tab 2 slot 6 resolves to container 7", #s == 1 and s[1].content == "bag:7:6", describe(s))

---------------------------------------------------------------------------
-- Bank button (SetBank.lua)
---------------------------------------------------------------------------
local SC = addonTable
local function bankReset()
	reset()
	defaultBagSizes()
	errors = {}
	used.UseContainerItem = {}
	printed = {}
	fire("BANKFRAME_CLOSED")
end
local function lastError() return errors[#errors] and errors[#errors].msg end

-- 16. Bank closed
bankReset()
bags["7:6"] = 200
sets = { { id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BANK_TAB(2, 6) } } }
SC.TakeSetFromBank(1)
check("16 bank closed shows 'Bank not open'", lastError() == "Bank not open", lastError())
check("16 bank closed error is red", errors[1] and errors[1].r == 1.0 and errors[1].g < 0.2)
check("16 bank closed moves nothing", #used.UseContainerItem == 0)

-- 17. Bank open: items in two bank tabs move; worn and bag items don't
bankReset()
fire("BANKFRAME_OPENED")
equipped[1] = 700                    -- worn head
bags["0:1"] = 701                    -- legs already in bags
bags["7:6"] = 200                    -- chest in bank tab 2
bags["6:10"] = 500                   -- ring in bank tab 1
sets = { { id = 1, name = "Tank",
	ids = { [1] = 700, [7] = 701, [5] = 200, [11] = 500 },
	locs = { [1] = LOC_WORN(1), [7] = LOC_BAG(0, 1), [5] = LOC_BANK_TAB(2, 6), [11] = LOC_BANK_TAB(1, 10) } } }
local moved = SC.TakeSetFromBank(1)
check("17 two bank items moved", moved == 2, moved)
check("17 used the decoded bank positions", table.concat(used.UseContainerItem, ",") == "7:6,6:10", table.concat(used.UseContainerItem, ","))
check("17 bank now empty of those items", bags["7:6"] == nil and bags["6:10"] == nil)
check("17 chat confirmation", printed[#printed] and printed[#printed]:find("moved 2 items of Tank") ~= nil, printed[#printed])
check("17 no error text", #errors == 0, lastError())

-- 18. Decoded position wrong (item was moved within the bank): falls back to scanning
bankReset()
fire("BANKFRAME_OPENED")
bags["7:40"] = 200
sets = { { id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BANK_TAB(2, 6) } } }
moved = SC.TakeSetFromBank(1)
check("18 found by scanning", moved == 1 and used.UseContainerItem[1] == "7:40", used.UseContainerItem[1])

-- 19. Missing (-1) item that is actually in the bank
bankReset()
fire("BANKFRAME_OPENED")
bags["6:3"] = 400
sets = { { id = 1, name = "PvP", ids = { [5] = 400 }, locs = { [5] = -1 } } }
moved = SC.TakeSetFromBank(1)
check("19 missing item found in bank", moved == 1 and used.UseContainerItem[1] == "6:3", used.UseContainerItem[1])

-- 20. Two identical rings come from two different bank slots
bankReset()
fire("BANKFRAME_OPENED")
bags["6:1"] = 500; bags["6:2"] = 500
sets = { { id = 1, name = "Tank", ids = { [11] = 500, [12] = 500 }, locs = { [11] = -1, [12] = -1 } } }
moved = SC.TakeSetFromBank(1)
check("20 both identical rings moved", moved == 2 and table.concat(used.UseContainerItem, ",") == "6:1,6:2", table.concat(used.UseContainerItem, ","))

-- 21. Not enough bag space (reagent bag space doesn't count)
bankReset()
fire("BANKFRAME_OPENED")
bagSize[0], bagSize[1], bagSize[2] = 1, 0, 0 -- only one free general slot; reagent bag 5 has 8 free
bags["7:6"] = 200; bags["6:10"] = 500
sets = { { id = 1, name = "Tank", ids = { [5] = 200, [11] = 500 },
	locs = { [5] = LOC_BANK_TAB(2, 6), [11] = LOC_BANK_TAB(1, 10) } } }
moved = SC.TakeSetFromBank(1)
check("21 only what fits is moved", moved == 1, moved)
check("21 space error", lastError() == "Not enough bag space (moved 1 of 2)", lastError())

-- 22. Nothing in bank
bankReset()
fire("BANKFRAME_OPENED")
equipped[5] = 100
sets = { { id = 1, name = "Healer", ids = { [5] = 100 }, locs = { [5] = LOC_WORN(5) } } }
moved = SC.TakeSetFromBank(1)
check("22 nothing to move", moved == 0 and lastError() == "No items from Healer in bank", lastError())

-- 23. Bank state via the player-interaction events
bankReset()
fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Banker)
check("23 banker interaction opens bank", SC.IsBankOpen())
fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", 5) -- some other interaction
check("23 other interaction doesn't close bank", SC.IsBankOpen())
fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.Banker)
check("23 banker hide closes bank", not SC.IsBankOpen())

-- 24. Equipment Manager rows: button per set row, none on "New Set", recycled rows act on current set
bankReset()
fire("BANKFRAME_OPENED")
bags["7:6"] = 200; bags["6:3"] = 400
sets = {
	{ id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BANK_TAB(2, 6) } },
	{ id = 2, name = "PvP", ids = { [5] = 400 }, locs = { [5] = LOC_BANK_TAB(1, 3) } },
}
check("24 scroll box hooked", #initCallbacks == 1, #initCallbacks)
local rowA, rowB = newFrame("Button"), newFrame("Button")
initRow(rowA, { setID = 1 })
initRow(rowB, { addSetButton = true })
check("24 set row has a button", rowA.scBankBtn and rowA.scBankBtn:IsShown())
check("24 'New Set' row button hidden", rowB.scBankBtn and not rowB.scBankBtn:IsShown())
-- Recycle rowA to show set 2, then click
initRow(rowA, { setID = 2 })
rowA.scBankBtn:Click()
check("24 recycled row moves the current set's item", used.UseContainerItem[1] == "6:3" and bags["7:6"] == 200, used.UseContainerItem[1])
check("24 button reused, not recreated", rowA.scBankBtn == rowA.scBankBtn)
-- Tooltip text
rowA.scBankBtn.scripts.OnEnter(rowA.scBankBtn)
check("24 tooltip title", GameTooltip.lines[1] == "Take items from bank", GameTooltip.lines[1])
check("24 tooltip counts bank items", GameTooltip.lines[2] == "0 items of this set are in your bank", GameTooltip.lines[2])
fire("BANKFRAME_CLOSED")
rowA.scBankBtn.scripts.OnEnter(rowA.scBankBtn)
check("24 tooltip when bank closed", GameTooltip.lines[2] == "Open your bank first", GameTooltip.lines[2])
-- Click with bank closed
errors = {}
rowA.scBankBtn:Click()
check("24 click with bank closed shows error", lastError() == "Bank not open")

-- 25. Put in bank: bag items move to the bank; worn and bank items don't
bankReset()
fire("BANKFRAME_OPENED")
equipped[1] = 700                    -- worn head
bags["0:3"] = 200                    -- chest in backpack
bags["1:2"] = 500                    -- ring in bag 1
bags["6:5"] = 701                    -- legs already in bank
sets = { { id = 1, name = "Tank",
	ids = { [1] = 700, [5] = 200, [11] = 500, [7] = 701 },
	locs = { [1] = LOC_WORN(1), [5] = LOC_BAG(0, 3), [11] = LOC_BAG(1, 2), [7] = LOC_BANK_TAB(1, 5) } } }
moved = SC.PutSetInBank(1)
check("25 two bag items deposited", moved == 2, moved)
check("25 used the bag positions", table.concat(used.UseContainerItem, ",") == "0:3,1:2", table.concat(used.UseContainerItem, ","))
check("25 items now in bank", bags["0:3"] == nil and bags["1:2"] == nil and bags["6:1"] == 200 and bags["6:2"] == 500)
check("25 worn item untouched", equipped[1] == 700)
check("25 chat confirmation", printed[#printed] and printed[#printed]:find("moved 2 items of Tank to bank") ~= nil, printed[#printed])

-- 26. Put in bank: bank closed
bankReset()
bags["0:3"] = 200
sets = { { id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } } }
SC.PutSetInBank(1)
check("26 bank closed shows 'Bank not open'", lastError() == "Bank not open" and #used.UseContainerItem == 0)

-- 27. Put in bank: stale bag position falls back to scanning bags; missing items are not looked for in bags
bankReset()
fire("BANKFRAME_OPENED")
bags["2:4"] = 200; bags["0:1"] = 400
sets = { { id = 1, name = "Tank", ids = { [5] = 200, [7] = 400 }, locs = { [5] = LOC_BAG(0, 3), [7] = -1 } } }
moved = SC.PutSetInBank(1)
check("27 stale bag position rescanned", moved == 1 and used.UseContainerItem[1] == "2:4", table.concat(used.UseContainerItem, ","))

-- 28. Put in bank: not enough bank space, and nothing in bags
bankReset()
fire("BANKFRAME_OPENED")
bagSize[6], bagSize[7] = 1, 0
bags["0:3"] = 200; bags["0:4"] = 500
sets = { { id = 1, name = "Tank", ids = { [5] = 200, [11] = 500 }, locs = { [5] = LOC_BAG(0, 3), [11] = LOC_BAG(0, 4) } } }
moved = SC.PutSetInBank(1)
check("28 only what fits is deposited", moved == 1, moved)
check("28 bank space error", lastError() == "Not enough bank space (moved 1 of 2)", lastError())
bankReset()
fire("BANKFRAME_OPENED")
equipped[5] = 100
sets = { { id = 1, name = "Healer", ids = { [5] = 100 }, locs = { [5] = LOC_WORN(5) } } }
moved = SC.PutSetInBank(1)
check("28 nothing in bags", moved == 0 and lastError() == "No items from Healer in bags", lastError())

-- 29. Row has both buttons; deposit button works and has its own tooltip
bankReset()
fire("BANKFRAME_OPENED")
bags["0:3"] = 200
sets = { { id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } } }
local rowC = newFrame("Button")
initRow(rowC, { setID = 1 })
check("29 deposit button shown", rowC.scDepositBtn and rowC.scDepositBtn:IsShown())
check("29 no .Check: bag button clear of the checkmark area", rowC.scBankBtn.points[1][2] == rowC and rowC.scBankBtn.points[1][4] == -32)
check("29 chest button left of bag button", rowC.scDepositBtn.points[1][2] == rowC.scBankBtn
	and rowC.scDepositBtn.points[1][1] == "RIGHT" and rowC.scDepositBtn.points[1][3] == "LEFT")
local rowD = newFrame("Button")
rowD.Check = newFrame("Texture")
initRow(rowD, { setID = 1 })
check("29 with .Check: bag button anchored left of the checkmark", rowD.scBankBtn.points[1][2] == rowD.Check
	and rowD.scBankBtn.points[1][1] == "RIGHT" and rowD.scBankBtn.points[1][3] == "LEFT")
check("29 different icons", rowC.scDepositBtn.normalTexture ~= rowC.scBankBtn.normalTexture)
rowC.scDepositBtn.scripts.OnEnter(rowC.scDepositBtn)
check("29 deposit tooltip", GameTooltip.lines[1] == "Put items in bank" and GameTooltip.lines[2] == "1 item of this set is in your bags",
	tostring(GameTooltip.lines[1]) .. " / " .. tostring(GameTooltip.lines[2]))
rowC.scDepositBtn:Click()
check("29 deposit click moves to bank", bags["0:3"] == nil and bags["6:1"] == 200)
initRow(rowC, { addSetButton = true })
check("29 both hidden on 'New Set' row", not rowC.scDepositBtn:IsShown() and not rowC.scBankBtn:IsShown())

-- 30. Client calls the row callback as (owner, row, elementData): buttons must go on each row,
--     not on the pane, and each row's buttons act on that row's set (bug: always used "Tank")
bankReset()
fire("BANKFRAME_OPENED")
bags["7:1"] = 300 -- Healer chest in bank
bags["7:2"] = 200 -- Tank chest in bank
sets = {
	{ id = 1, name = "Healer", ids = { [5] = 300 }, locs = { [5] = LOC_BANK_TAB(2, 1) } },
	{ id = 2, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BANK_TAB(2, 2) } },
}
local pane = PaperDollEquipmentManagerPane
for _, mode in ipairs({ "owner", "box", "plain" }) do
	callMode = mode
	boxRows = {}
	bags["7:1"] = 300; bags["7:2"] = 200
	used.UseContainerItem = {}
	local healerRow, tankRow = newFrame("Button"), newFrame("Button")
	initRow(healerRow, { setID = 1 })
	initRow(tankRow, { setID = 2 })
	check("30 [" .. mode .. "] no buttons on the pane or scroll box",
		pane.scBankBtn == nil and pane.scDepositBtn == nil and scrollBox.scBankBtn == nil)
	check("30 [" .. mode .. "] each row has its own shown buttons",
		healerRow.scBankBtn and tankRow.scBankBtn and healerRow.scBankBtn:IsShown() and tankRow.scBankBtn:IsShown())
	healerRow.scBankBtn:Click()
	check("30 [" .. mode .. "] Healer row moves Healer's item", used.UseContainerItem[1] == "7:1" and bags["7:2"] == 200,
		table.concat(used.UseContainerItem, ","))
	check("30 [" .. mode .. "] chat names Healer", printed[#printed] and printed[#printed]:find("of Healer") ~= nil, printed[#printed])
end
callMode = "plain"

-- 31. The debug command was removed: "/setcompare debug" no longer prints anything
printed = {}
SlashCmdList.SETCOMPARER("debug")
check("31 no debug output", #printed == 0, table.concat(printed, " / "))
check("31 no DebugRows function", SC.DebugRows == nil)
check("31 does not toggle the addon", SetComparerDB.enabled == true)

---------------------------------------------------------------------------
-- Options panel (Options.lua)
---------------------------------------------------------------------------
local panel = SC.OptionsPanel
-- find the panel's check buttons by label
local function panelChecks()
	local out = {}
	for _, f in ipairs(created) do
		if f.parent == panel and f.label then out[#out + 1] = f end
	end
	return out
end
local function checkByLabel(text)
	for _, cb in ipairs(panelChecks()) do
		if cb.label.text == text or (cb.label.text or ""):find(text, 1, true) then return cb end
	end
end
local function openPanel() panel:Hide(); panel:Show(); panel.scripts.OnShow(panel) end

-- 32. Registration, defaults, slash command
check("32 panel registered in Options > AddOns", settingsLog.registered and settingsLog.registered.frame == panel
	and settingsLog.registered.name == "SetComparer")
check("32 defaults", SetComparerDB.showBankButtons == true and type(SetComparerCharDB.hiddenSets) == "table")
SlashCmdList.SETCOMPARER("options")
check("32 /setcompare options opens the panel", settingsLog.opened == 42)
check("32 /setcompare options does not toggle", SetComparerDB.enabled == true)
settingsLog.opened = nil
SlashCmdList.SETCOMPARER("")
check("32 bare /setcompare opens the panel", settingsLog.opened == 42)
check("32 bare /setcompare does not toggle", SetComparerDB.enabled == true)
check("32 comparison on/off checkbox is in the panel", checkByLabel("Show set comparison frames") ~= nil)

-- 33. Per-set checkboxes; unticking a set removes its comparison frame
reset()
equipped[5] = 100
bags["0:3"] = 200; bags["0:4"] = 400
sets = {
	{ id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } },
	{ id = 2, name = "PvP", ids = { [5] = 400 }, locs = { [5] = LOC_BAG(0, 4) } },
}
openPanel()
local tankCheck, pvpCheck = checkByLabel("Tank"), checkByLabel("PvP")
check("33 one checkbox per set, ticked by default", tankCheck and pvpCheck and tankCheck:GetChecked() and pvpCheck:GetChecked())
hover(300)
check("33 both sets compared", #setTooltipFrames() == 2)
pvpCheck:ToggleClick()
check("33 unticked set saved per character", SetComparerCharDB.hiddenSets[2] == true)
check("33 open frames hidden after change", #setTooltipFrames() == 0)
hover(300)
s = setTooltipFrames()
check("33 unticked set no longer compared", #s == 1 and s[1].scHeader.text.text == "Set: Tank", describe(s))
pvpCheck:ToggleClick()
check("33 ticking again restores it", SetComparerCharDB.hiddenSets[2] == nil)
hover(300)
check("33 both compared again", #setTooltipFrames() == 2)

-- 34. A deleted set's checkbox disappears; set list follows EQUIPMENT_SETS_CHANGED while open
table.remove(sets, 2)
fire("EQUIPMENT_SETS_CHANGED")
check("34 removed set's checkbox hidden", not pvpCheck:IsShown() and tankCheck:IsShown())

-- 35. Turning comparison off greys out the set list and stops frames
local compareCb = checkByLabel("Show set comparison frames")
compareCb:ToggleClick()
check("35 comparison disabled", SetComparerDB.enabled == false)
check("35 set checkboxes greyed out", tankCheck:IsEnabled() == false and tankCheck.label.color[1] == 0.5)
hover(300)
check("35 no frames while disabled", #setTooltipFrames() == 0)
compareCb:ToggleClick()
check("35 re-enabled", SetComparerDB.enabled == true and tankCheck:IsEnabled())
SlashCmdList.SETCOMPARER("toggle")
check("35 slash toggle updates the open panel", compareCb:GetChecked() == false)
SlashCmdList.SETCOMPARER("toggle")
check("35 slash toggle back", compareCb:GetChecked() == true)

-- 36. Bank buttons on/off updates existing rows immediately
bankReset()
sets = { { id = 1, name = "Tank", ids = { [5] = 200 }, locs = { [5] = LOC_BAG(0, 3) } } }
boxRows = {}
local rowE = newFrame("Button")
initRow(rowE, { setID = 1 })
check("36 buttons shown by default", rowE.scBankBtn:IsShown() and rowE.scDepositBtn:IsShown())
openPanel()
local bankCb = checkByLabel("Show bank buttons")
bankCb:ToggleClick()
check("36 setting saved", SetComparerDB.showBankButtons == false)
check("36 buttons hidden on existing rows", not rowE.scBankBtn:IsShown() and not rowE.scDepositBtn:IsShown())
initRow(rowE, { setID = 1 })
check("36 stay hidden when rows refresh", not rowE.scBankBtn:IsShown())
bankCb:ToggleClick()
check("36 buttons back", rowE.scBankBtn:IsShown() and rowE.scDepositBtn:IsShown())

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
