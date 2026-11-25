-- Mock WoW environment test harness for SetComparer.lua
-- Usage: lua test_setcomparer.lua <path to SetComparer.lua>
local ADDON_PATH = assert(arg[1], "pass addon path")

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
		GetStringWidth = function(fs) return #fs.text * 7 end }
end
-- tooltip methods
function FrameMT:SetOwner(o) self.owner = o end
function FrameMT:ClearLines() self.lines = {}; self.content = nil end
function FrameMT:AddLine(t) table.insert(self.lines, t) end
function FrameMT:SetInventoryItem(u, slot) calls.SetInventoryItem = calls.SetInventoryItem + 1; self.content = "inv:" .. slot end
function FrameMT:SetBagItem(b, s) calls.SetBagItem = calls.SetBagItem + 1; self.content = "bag:" .. b .. ":" .. s end
function FrameMT:SetItemByID(id) calls.SetItemByID = calls.SetItemByID + 1; self.content = "id:" .. id end
function FrameMT:GetItem() return self.itemName, self.itemLink end

function CreateFrame(kind, name, parent, template) return newFrame(kind, name) end

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
C_Container = { GetContainerItemLink = function(b, s) local id = bags[b .. ":" .. s]; return id and link(id) end }

local sets = {} -- { id, name, ids = {}, locs = {} }
C_EquipmentSet = {
	GetNumEquipmentSets = function() return #sets end,
	GetEquipmentSetIDs = function() local t = {}; for _, s in ipairs(sets) do t[#t + 1] = s.id end; return t end,
	GetEquipmentSetInfo = function(id) for _, s in ipairs(sets) do if s.id == id then return s.name, 0, id end end end,
	GetItemIDs = function(id) for _, s in ipairs(sets) do if s.id == id then return s.ids end end end,
	GetItemLocations = function(id) for _, s in ipairs(sets) do if s.id == id then return s.locs end end end,
}
local function LOC_WORN(slot) return 0x100000 + slot end
local function LOC_BAG(b, s) return 0x100000 + 0x200000 + (b << 8) + s end
local function LOC_BANK_TAB(tab, s) return 0x400000 + 0x200000 + (tab << 8) + s end

local shiftDown = true
function IsModifiedClick() return shiftDown end
function GetCVarBool() return false end
SlashCmdList = {}
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

local chunk = assert(loadfile(ADDON_PATH))
chunk("SetComparer", {})
local eventFrame
for _, f in ipairs(created) do if f.scripts.OnEvent then eventFrame = f end end
assert(eventFrame, "no event frame")
local function fire(ev, ...) eventFrame.scripts.OnEvent(eventFrame, ev, ...) end
fire("ADDON_LOADED", "SetComparer")
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
SlashCmdList.SETCOMPARER("")
check("13 disabled hides frames", #setTooltipFrames() == 0 and SetComparerDB.enabled == false)
hover(300)
check("13 disabled shows nothing", #setTooltipFrames() == 0)
SlashCmdList.SETCOMPARER("")
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

io.write(("\n%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
