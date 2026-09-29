local ADDON, ns = ...
local L, C, DB = ns.L, ns.C, ns.DB

-- The button on the minimap: a click opens or closes the window, a
-- right-click opens the options. It can be dragged around the minimap's edge,
-- and turned off in the options. Minimap addons that gather buttons (such as
-- EllesmereUI's minimap) take it like any other.

local MinimapButton = {}
ns.MinimapButton = MinimapButton

local _G = _G
local cos, sin, rad, deg, atan2, sqrt, max, min = math.cos, math.sin, math.rad, math.deg, math.atan2, math.sqrt, math.max, math.min

-- The addon's icon is the .toc's IconTexture, so the AddOns list, the addon
-- compartment and this button all show the one set there.
local ICON = "Interface\\Icons\\Achievement_Quests_Completed_08"
local OUTSIDE = 5 -- how far past the minimap's edge the button's middle sits

-- Which quarters of the minimap are round, for the shapes minimap addons give
-- through GetMinimapShape (without one the minimap is round). Quarters:
-- 1 bottom right, 2 bottom left, 3 top right, 4 top left.
local SHAPES = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { false, false, false, true },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
	["SIDE-LEFT"] = { false, true, false, true },
	["SIDE-RIGHT"] = { true, false, true, false },
	["SIDE-TOP"] = { false, false, true, true },
	["SIDE-BOTTOM"] = { true, true, false, false },
	["TRICORNER-TOPLEFT"] = { false, true, true, true },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}

local button

-- Puts the button on the minimap's edge at an angle (degrees, 0 is to the
-- right, counterclockwise), following the edge of a square minimap too.
local function Place(angle)
	local minimap = _G.Minimap
	local x, y = cos(rad(angle)), sin(rad(angle))
	local quarter = 1
	if x < 0 then
		quarter = quarter + 1
	end
	if y > 0 then
		quarter = quarter + 2
	end
	local shape = _G.GetMinimapShape and _G.GetMinimapShape() or "ROUND"
	local round = (SHAPES[shape] or SHAPES.ROUND)[quarter]
	local w = minimap:GetWidth() / 2 + OUTSIDE
	local h = minimap:GetHeight() / 2 + OUTSIDE
	if round then
		x, y = x * w, y * h
	else
		-- Out along the diagonal, then held to the square's edge.
		local dw, dh = sqrt(2 * w * w) - 10, sqrt(2 * h * h) - 10
		x = max(-w, min(x * dw, w))
		y = max(-h, min(y * dh, h))
	end
	button:ClearAllPoints()
	button:SetPoint("CENTER", minimap, "CENTER", x, y)
end

-- The angle from the minimap's middle to the mouse.
local function CursorAngle()
	local minimap = _G.Minimap
	local mx, my = minimap:GetCenter()
	local scale = minimap:GetEffectiveScale()
	local px, py = GetCursorPosition()
	return deg(atan2(py / scale - my, px / scale - mx)) % 360
end

local function OnDragUpdate(self)
	self.angle = CursorAngle()
	Place(self.angle)
end

local function OnEnter(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:SetText(L["Almanac"], 1, 1, 1)
	GameTooltip:AddLine(L["Click: open or close"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Right-click: options"], 0.8, 0.8, 0.8)
	GameTooltip:AddLine(L["Drag: move it around the minimap"], 0.8, 0.8, 0.8)
	GameTooltip:Show()
end

local function OnLeave(self)
	if GameTooltip:IsOwned(self) then
		GameTooltip:Hide()
	end
end

local function OnClick(_, mouseButton)
	if mouseButton == "RightButton" then
		ns.Window.Open("options")
	else
		ns.Window.Toggle()
	end
end

-- Dragging moves it around the edge, unless a minimap addon has taken it
-- somewhere else (its parent is no longer the minimap).
local function OnDragStart(self)
	if self:GetParent() ~= _G.Minimap then
		return
	end
	OnLeave(self)
	self:SetScript("OnUpdate", OnDragUpdate)
end

local function OnDragStop(self)
	self:SetScript("OnUpdate", nil)
	if self.angle then
		DB.Set("minimapAngle", self.angle)
	end
end

function MinimapButton.Update()
	if button then
		button:SetShown(DB.settings.minimapButton)
	end
end

function MinimapButton.Create()
	if button or not _G.Minimap then
		return
	end
	button = CreateFrame("Button", "AlmanacMinimapButton", _G.Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("AnyUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local background = button:CreateTexture(nil, "BACKGROUND")
	background:SetSize(24, 24)
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetPoint("CENTER")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetTexture(C.AddOnMetadata(ADDON, "IconTexture") or ICON)
	icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
	icon:SetPoint("CENTER")
	button.icon = icon
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetSize(50, 50)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")
	button:SetScript("OnEnter", OnEnter)
	button:SetScript("OnLeave", OnLeave)
	button:SetScript("OnClick", OnClick)
	button:SetScript("OnDragStart", OnDragStart)
	button:SetScript("OnDragStop", OnDragStop)
	Place(DB.settings.minimapAngle)
	MinimapButton.Update()
	ns.Listen("settings", function(key)
		if key == "minimapButton" then
			MinimapButton.Update()
		end
	end)
end

function MinimapButton.Button()
	return button
end
