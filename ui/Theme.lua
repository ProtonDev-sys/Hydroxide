local Colors = {
	Background = Color3.fromRGB(16, 17, 20),
	Surface = Color3.fromRGB(23, 24, 28),
	SurfaceRaised = Color3.fromRGB(29, 31, 36),
	Input = Color3.fromRGB(12, 13, 16),
	Control = Color3.fromRGB(36, 39, 45),
	ControlHover = Color3.fromRGB(47, 51, 59),
	ControlDisabled = Color3.fromRGB(28, 30, 35),
	Row = Color3.fromRGB(27, 29, 34),
	RowAlternate = Color3.fromRGB(31, 33, 39),
	Selection = Color3.fromRGB(54, 39, 42),
	Text = Color3.fromRGB(232, 234, 239),
	TextMuted = Color3.fromRGB(151, 156, 166),
	TextDisabled = Color3.fromRGB(94, 99, 109),
	Border = Color3.fromRGB(59, 63, 72),
	Scrollbar = Color3.fromRGB(88, 93, 103),
	Accent = Color3.fromRGB(225, 76, 80),
	Danger = Color3.fromRGB(224, 83, 83),
	Warning = Color3.fromRGB(235, 179, 73),
	Send = Color3.fromRGB(91, 192, 235),
	Receive = Color3.fromRGB(190, 135, 240),
	Overlay = Color3.fromRGB(10, 11, 13),
	CodeBackground = Color3.fromRGB(11, 12, 14),
}

Colors.Focus = Colors.Accent
Colors.ResizeGrip = Colors.TextMuted

local Theme = {
	Colors = Colors,
	CornerRadius = 4,
	Metrics = {
		CompactControlHeight = 24,
		ControlHeight = 28,
		Gap = 6,
		MinimumHitSize = 28,
		Padding = 8,
		PopupMargin = 8,
		ScrollbarThickness = 6,
	},
	Motion = {
		Fast = 0.1,
		Normal = 0.15,
	},
	Typography = {
		BodyTextSize = 17,
		CodeTextSize = 14,
		SmallTextSize = 15,
	},
}

local function channel(value)
	return math.max(0, math.min(255, math.floor((tonumber(value) or 0) * 255 + 0.5)))
end

local function colorKey(color)
	local ok, red, green, blue = pcall(function()
		return channel(color.R), channel(color.G), channel(color.B)
	end)

	if not ok then
		return nil
	end

	return ("%d,%d,%d"):format(red, green, blue)
end

local legacyTokens = {
	["0,0,0"] = "CodeBackground",
	["12,12,12"] = "CodeBackground",
	["15,15,15"] = "Input",
	["18,18,18"] = "Input",
	["20,20,20"] = "Background",
	["24,24,24"] = "Surface",
	["25,25,25"] = "Surface",
	["28,28,28"] = "ControlDisabled",
	["29,29,29"] = "SurfaceRaised",
	["30,30,30"] = "SurfaceRaised",
	["31,31,31"] = "Row",
	["34,34,34"] = "RowAlternate",
	["35,35,35"] = "Row",
	["38,38,38"] = "Control",
	["40,40,40"] = "Control",
	["42,42,42"] = "Control",
	["45,45,45"] = "ControlHover",
	["48,48,48"] = "ControlHover",
	["50,50,50"] = "ControlHover",
	["55,35,35"] = "Selection",
	["48,42,29"] = "Selection",
	["58,58,58"] = "Border",
	["65,65,65"] = "Border",
	["92,92,92"] = "Scrollbar",
	["95,95,95"] = "Scrollbar",
	["100,100,100"] = "TextDisabled",
	["122,122,122"] = "TextDisabled",
	["127,127,127"] = "TextDisabled",
	["145,145,145"] = "TextMuted",
	["155,155,155"] = "TextMuted",
	["156,156,156"] = "TextMuted",
	["175,175,175"] = "TextMuted",
	["188,188,188"] = "TextMuted",
	["215,215,215"] = "Text",
	["225,225,225"] = "Text",
	["230,230,230"] = "Text",
	["232,232,232"] = "Text",
	["235,235,235"] = "Text",
	["240,240,240"] = "Text",
	["255,255,255"] = "Text",
	["20,0,0"] = "Danger",
	["30,10,10"] = "Selection",
	["40,20,20"] = "Selection",
	["170,0,0"] = "Danger",
	["140,12,12"] = "Selection",
	["225,0,0"] = "Accent",
	["105,196,255"] = "Send",
	["197,139,255"] = "Receive",
	["238,178,69"] = "Warning",
}

local canonicalColors = {}
local canonicalTokens = {}

for token, color in pairs(Colors) do
	local key = colorKey(color)
	canonicalColors[key] = color
	canonicalTokens[key] = token
end

function Theme.ResolveColor(color, role)
	local key = colorKey(color)

	if not key then
		return color
	end

	local token = legacyTokens[key] or canonicalTokens[key]

	if role == "Border" and token then
		if key == colorKey(Colors.Accent)
			or key == colorKey(Colors.Danger)
			or key == colorKey(Colors.Warning)
			or key == colorKey(Colors.Send)
			or key == colorKey(Colors.Receive)
		then
			return canonicalColors[key]
		end

		return Colors.Border
	end

	if canonicalColors[key] then
		return canonicalColors[key]
	end

	return token and Colors[token] or color
end

function Theme.ApplyObject(object)
	if object == nil then
		return
	end

	pcall(function()
		if object:IsA("GuiObject") then
			object.BackgroundColor3 = Theme.ResolveColor(object.BackgroundColor3)
			object.BorderColor3 = Theme.ResolveColor(object.BorderColor3, "Border")
		end

		if object:IsA("TextLabel") or object:IsA("TextButton") or object:IsA("TextBox") then
			object.TextColor3 = Theme.ResolveColor(object.TextColor3)
			object.TextStrokeColor3 = Theme.ResolveColor(object.TextStrokeColor3)
		end

		if object:IsA("GuiButton") then
			object.Selectable = true
		end

		if object:IsA("ImageLabel") or object:IsA("ImageButton") then
			object.ImageColor3 = Theme.ResolveColor(object.ImageColor3)
		end

		if object:IsA("ScrollingFrame") then
			object.ScrollBarImageColor3 = Theme.ResolveColor(object.ScrollBarImageColor3)

			if object.ScrollBarThickness > 0 then
				object.ScrollBarThickness = math.max(Theme.Metrics.ScrollbarThickness, object.ScrollBarThickness)
			end
		end

		if object:IsA("UIStroke") then
			object.Color = Theme.ResolveColor(object.Color, "Border")
		end
	end)
end

function Theme.Apply(root)
	if root == nil then
		return
	end

	Theme.ApplyObject(root)

	local ok, descendants = pcall(function()
		return root:GetDescendants()
	end)

	if ok then
		for _, descendant in ipairs(descendants) do
			Theme.ApplyObject(descendant)
		end
	end
end

return Theme
