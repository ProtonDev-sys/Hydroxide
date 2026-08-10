local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")

local TextViewer = {}
local viewer

local function trackInstance(instance)
	if oh and oh.Instances then
		oh.Instances[#oh.Instances + 1] = instance
	end
end

local function trackConnection(connection)
	if oh and oh.Events then
		oh.Events[#oh.Events + 1] = connection
	end
end

local function getParent()
	local ran, interface = pcall(import, "rbxassetid://11389137937")

	if ran and interface then
		return interface
	end

	return CoreGui
end

local function makeText(parent, text, size, position)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSans
	label.Text = text
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.TextSize = 18
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Size = size
	label.Position = position
	label.Parent = parent
	return label
end

local function makeButton(parent, text, position)
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(42, 42, 42)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSans
	button.Text = text
	button.TextColor3 = Color3.fromRGB(240, 240, 240)
	button.TextSize = 18
	button.Size = UDim2.new(0, 76, 0, 28)
	button.Position = position
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = button

	return button
end

local function estimateTextSize(text, textSize, font)
	local sampled = text:sub(1, 65536)
	local maxLine = ""
	local lineCount = 1
	local sampledLines = 0

	for line in (sampled .. "\n"):gmatch("(.-)\n") do
		if #line > #maxLine then
			maxLine = line
		end

		sampledLines = sampledLines + 1

		if sampledLines >= 200 then
			break
		end
	end

	for _ in text:gmatch("\n") do
		lineCount = lineCount + 1
	end

	if #maxLine > 2000 then
		maxLine = maxLine:sub(1, 2000)
	end

	local measured, bounds =
		pcall(TextService.GetTextSize, TextService, maxLine, textSize, font, Vector2.new(100000, 100000))

	if not measured then
		bounds = Vector2.new(math.min(#maxLine * textSize * 0.65, 50000), textSize)
	end

	return Vector2.new(math.max(bounds.X + 24, 640), math.max(lineCount * (textSize + 4) + 24, 160))
end

local function hide()
	if viewer and viewer.Overlay then
		viewer.Overlay.Visible = false
	end
end

local function ensureViewer()
	if viewer and viewer.Overlay and viewer.Overlay.Parent then
		return viewer
	end

	local overlay = Instance.new("Frame")
	overlay.Name = "HydroxideTextViewer"
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Visible = false
	overlay.ZIndex = 200
	overlay.Parent = getParent()
	trackInstance(overlay)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	panel.BorderSizePixel = 0
	panel.Position = UDim2.new(0.5, 0, 0.5, 0)
	panel.Size = UDim2.new(0.82, 0, 0.78, 0)
	panel.ZIndex = 201
	panel.Parent = overlay

	local panelSize = Instance.new("UISizeConstraint")
	panelSize.MinSize = Vector2.new(320, 240)
	panelSize.MaxSize = Vector2.new(980, 720)
	panelSize.Parent = panel

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 70, 70)
	stroke.Thickness = 1
	stroke.Parent = panel

	local title = makeText(panel, "Text Viewer", UDim2.new(1, -188, 0, 36), UDim2.new(0, 14, 0, 8))
	title.ZIndex = 202

	local copy = makeButton(panel, "Copy", UDim2.new(1, -164, 0, 12))
	local close = makeButton(panel, "Close", UDim2.new(1, -84, 0, 12))
	copy.ZIndex = 202
	close.ZIndex = 202

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroll"
	scroller.Active = true
	scroller.BackgroundColor3 = Color3.fromRGB(16, 16, 16)
	scroller.BorderSizePixel = 0
	scroller.BottomImage = ""
	scroller.CanvasPosition = Vector2.new()
	scroller.MidImage = ""
	scroller.Position = UDim2.new(0, 14, 0, 52)
	scroller.ScrollBarThickness = 8
	scroller.Size = UDim2.new(1, -28, 1, -66)
	scroller.TopImage = ""
	scroller.ZIndex = 202
	scroller.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.Parent = scroller

	local textBox = Instance.new("TextBox")
	textBox.BackgroundTransparency = 1
	textBox.ClearTextOnFocus = false
	textBox.Font = Enum.Font.Code
	textBox.MultiLine = true
	textBox.Selectable = true
	textBox.TextColor3 = Color3.fromRGB(230, 230, 230)
	textBox.TextEditable = false
	textBox.TextSize = 14
	textBox.TextWrapped = false
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextYAlignment = Enum.TextYAlignment.Top
	textBox.ZIndex = 203
	textBox.Parent = scroller

	viewer = {
		Overlay = overlay,
		Title = title,
		Text = "",
		TextBox = textBox,
		Scroller = scroller,
	}

	trackConnection(copy.MouseButton1Click:Connect(function()
		if setClipboard then
			setClipboard(viewer.TextBox.Text)
		end
	end))

	trackConnection(close.MouseButton1Click:Connect(hide))

	return viewer
end

function TextViewer.Show(title, text, options)
	local current = ensureViewer()
	text = tostring(text or "")
	options = type(options) == "table" and options or {}

	current.Text = text
	current.Title.Text = tostring(title or "Text Viewer")
	current.TextBox.Text = text
	current.TextBox.TextEditable = options.Editable == true
	current.Scroller.CanvasPosition = Vector2.new()

	local size = estimateTextSize(text, current.TextBox.TextSize, current.TextBox.Font)
	current.TextBox.Size = UDim2.new(0, size.X, 0, size.Y)
	current.Scroller.CanvasSize = UDim2.new(0, size.X + 16, 0, size.Y + 16)
	current.Overlay.Visible = true
	current.Overlay.Parent = getParent()
end

return TextViewer
