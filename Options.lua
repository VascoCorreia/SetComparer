-- SetComparer: options panel (Esc > Options > AddOns > SetComparer, or /setcompare options)

local _, SetComparer = ...

local panel = CreateFrame("Frame")
panel.name = "SetComparer"
panel:Hide()

local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("SetComparer")

local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
subtitle:SetText("Compare items against your saved equipment sets, and move sets to and from the bank.")

---------------------------------------------------------------------------
-- Checkbox helper
---------------------------------------------------------------------------

local function CreateCheck(label, tooltip, onClick)
	local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	-- Own label: the template's text field is named differently between clients
	cb.label = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	cb.label:SetPoint("LEFT", cb, "RIGHT", 4, 1)
	cb.label:SetText(label)
	cb.tooltip = tooltip
	cb:SetScript("OnClick", function(self) onClick(self, self:GetChecked() and true or false) end)
	cb:SetScript("OnEnter", function(self)
		if not self.tooltip then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetText(self.label:GetText(), 1, 1, 1)
		GameTooltip:AddLine(self.tooltip, nil, nil, nil, true)
		GameTooltip:Show()
	end)
	cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
	return cb
end

local function SetCheckEnabled(cb, enabled)
	cb:SetEnabled(enabled)
	if enabled then
		cb.label:SetTextColor(1, 1, 1)
	else
		cb.label:SetTextColor(0.5, 0.5, 0.5)
	end
end

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

local compareCheck = CreateCheck("Show set comparison frames",
	"When you shift-hover an item, show the matching item from each of your equipment sets next to the default comparison.",
	function(_, checked)
		SetComparer.SetCompareEnabled(checked)
		SetComparer.RefreshOptions()
	end)
compareCheck:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", -2, -16)

local bankCheck = CreateCheck("Show bank buttons in the Equipment Manager",
	"Show the \"Put items in bank\" and \"Take items from bank\" buttons on each set in the Equipment Manager.",
	function(_, checked)
		SetComparerDB.showBankButtons = checked
		if SetComparer.DecorateAllRows then SetComparer.DecorateAllRows() end
	end)
bankCheck:SetPoint("TOPLEFT", compareCheck, "BOTTOMLEFT", 0, -6)

local setsHeader = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
setsHeader:SetPoint("TOPLEFT", bankCheck, "BOTTOMLEFT", 2, -20)
setsHeader:SetText("Sets to compare against (this character)")

local setsNote = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
setsNote:SetPoint("TOPLEFT", setsHeader, "BOTTOMLEFT", 0, -4)
setsNote:SetJustifyH("LEFT")

---------------------------------------------------------------------------
-- One checkbox per saved set (rebuilt whenever the panel is shown or sets change)
---------------------------------------------------------------------------

local setChecks = {}

local function RefreshSetList()
	local ids = C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs() or {}
	local enabled = SetComparerDB and SetComparerDB.enabled

	if #ids == 0 then
		setsNote:SetText("You have no saved equipment sets.")
	elseif not enabled then
		setsNote:SetText("Turn on \"Show set comparison frames\" to choose sets.")
	else
		setsNote:SetText("Unticked sets get no comparison frame. New sets are compared by default.")
	end

	for i, setID in ipairs(ids) do
		local cb = setChecks[i]
		if not cb then
			cb = CreateCheck("", nil, function(self, checked)
				SetComparer.SetSetCompared(self.setID, checked)
			end)
			if i == 1 then
				cb:SetPoint("TOPLEFT", setsNote, "BOTTOMLEFT", -2, -8)
			else
				cb:SetPoint("TOPLEFT", setChecks[i - 1], "BOTTOMLEFT", 0, -2)
			end
			setChecks[i] = cb
		end
		local name, icon = C_EquipmentSet.GetEquipmentSetInfo(setID)
		cb.setID = setID
		cb.label:SetText(icon and ("|T" .. icon .. ":16|t " .. (name or "?")) or (name or "?"))
		cb:SetChecked(SetComparer.IsSetCompared(setID))
		SetCheckEnabled(cb, enabled)
		cb:Show()
	end
	for i = #ids + 1, #setChecks do setChecks[i]:Hide() end
end

function SetComparer.RefreshOptions()
	if not SetComparerDB then return end
	compareCheck:SetChecked(SetComparerDB.enabled)
	bankCheck:SetChecked(SetComparerDB.showBankButtons ~= false)
	RefreshSetList()
end

panel:SetScript("OnShow", SetComparer.RefreshOptions)

local events = CreateFrame("Frame")
events:RegisterEvent("EQUIPMENT_SETS_CHANGED")
events:SetScript("OnEvent", function()
	if panel:IsShown() then RefreshSetList() end
end)

---------------------------------------------------------------------------
-- Register with the game's options window
---------------------------------------------------------------------------

local category
if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
	category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
	Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
	InterfaceOptions_AddCategory(panel)
end

SetComparer.OptionsPanel = panel

function SetComparer.OpenOptions()
	if category and Settings and Settings.OpenToCategory then
		Settings.OpenToCategory(category.GetID and category:GetID() or category.ID)
	elseif InterfaceOptionsFrame_OpenToCategory then
		-- Called twice: the first call sometimes only opens the window
		InterfaceOptionsFrame_OpenToCategory(panel)
		InterfaceOptionsFrame_OpenToCategory(panel)
	end
end
