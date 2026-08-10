local TextService = game:GetService("TextService")

local InlineViewer = {}

local function trackConnection(connection)
	if oh and oh.Events then
		oh.Events[#oh.Events + 1] = connection
	end
end

local function makeButton(parent, text, offset)
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(42, 42, 42)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSans
	button.Position = UDim2.new(1, offset, 0, 6)
	button.Size = UDim2.new(0, 72, 0, 24)
	button.Text = text
	button.TextColor3 = Color3.fromRGB(235, 235, 235)
	button.TextSize = 16
	button.ZIndex = 12
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = button

	return button
end

local function estimateSize(text, textSize, font)
	local maxLine = ""
	local lines = 1
	local sampled = 0

	for line in (text:sub(1, 65536) .. "\n"):gmatch("(.-)\n") do
		if #line > #maxLine then
			maxLine = line
		end

		sampled = sampled + 1

		if sampled >= 200 then
			break
		end
	end

	for _ in text:gmatch("\n") do
		lines = lines + 1
	end

	if #maxLine > 1600 then
		maxLine = maxLine:sub(1, 1600)
	end

	local measured, bounds =
		pcall(TextService.GetTextSize, TextService, maxLine, textSize, font, Vector2.new(100000, 100000))

	if not measured then
		bounds = Vector2.new(math.min(#maxLine * textSize * 0.62, 36000), textSize)
	end

	return Vector2.new(math.max(bounds.X + 20, 420), math.max(lines * (textSize + 4) + 16, 100))
end

function InlineViewer.Install(parent, options)
	options = type(options) == "table" and options or {}

	if not parent then
		return nil
	end

	local existing = parent:FindFirstChild("HydroxideInlineInspector")
	if existing then
		existing:Destroy()
	end

	local heightScale = tonumber(options.HeightScale) or 0.44
	local topScale = tonumber(options.TopScale)

	if topScale then
		topScale = math.max(0, math.min(0.9, topScale))
	else
		topScale = math.max(0, math.min(0.7, 1 - heightScale))
	end

	local panel = Instance.new("Frame")
	panel.Name = "HydroxideInlineInspector"
	panel.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	panel.BorderSizePixel = 0
	panel.Position = UDim2.new(0, 8, topScale, -2)
	panel.Size = UDim2.new(1, -16, 1 - topScale, -8)
	panel.Visible = false
	panel.ZIndex = 10
	panel.Parent = parent

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(58, 58, 58)
	stroke.Thickness = 1
	stroke.Parent = panel

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.SourceSans
	title.Position = UDim2.new(0, 10, 0, 5)
	title.Size = UDim2.new(1, -172, 0, 26)
	title.Text = "Inspector"
	title.TextColor3 = Color3.fromRGB(235, 235, 235)
	title.TextSize = 17
	title.TextTruncate = Enum.TextTruncate.AtEnd
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = 11
	title.Parent = panel

	local copy = makeButton(panel, "Copy", -150)
	local clear = makeButton(panel, "Clear", -74)

	local scroll = Instance.new("ScrollingFrame")
	scroll.Active = true
	scroll.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	scroll.BorderSizePixel = 0
	scroll.BottomImage = ""
	scroll.CanvasPosition = Vector2.new()
	scroll.MidImage = ""
	scroll.Position = UDim2.new(0, 8, 0, 36)
	scroll.ScrollBarThickness = 7
	scroll.Size = UDim2.new(1, -16, 1, -44)
	scroll.TopImage = ""
	scroll.ZIndex = 11
	scroll.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 8)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.PaddingTop = UDim.new(0, 8)
	padding.Parent = scroll

	local textBox = Instance.new("TextBox")
	textBox.BackgroundTransparency = 1
	textBox.ClearTextOnFocus = false
	textBox.Font = Enum.Font.Code
	textBox.MultiLine = true
	textBox.Selectable = true
	textBox.Text = ""
	textBox.TextColor3 = Color3.fromRGB(230, 230, 230)
	textBox.TextEditable = false
	textBox.TextSize = 14
	textBox.TextWrapped = false
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextYAlignment = Enum.TextYAlignment.Top
	textBox.ZIndex = 12
	textBox.Parent = scroll

	local viewer = {
		Panel = panel,
		Title = title,
		Scroller = scroll,
		TextBox = textBox,
	}

	function viewer:Show(viewTitle, text, viewOptions)
		viewOptions = type(viewOptions) == "table" and viewOptions or {}
		text = tostring(text or "")

		self.Title.Text = tostring(viewTitle or "Inspector")
		self.TextBox.Text = text
		self.TextBox.TextEditable = viewOptions.Editable == true
		self.Scroller.CanvasPosition = Vector2.new()

		local size = estimateSize(text, self.TextBox.TextSize, self.TextBox.Font)
		self.TextBox.Size = UDim2.new(0, size.X, 0, size.Y)
		self.Scroller.CanvasSize = UDim2.new(0, size.X + 16, 0, size.Y + 16)
		self.Panel.Visible = true
	end

	function viewer:Clear()
		self.Panel.Visible = false
		self.TextBox.Text = ""
	end

	trackConnection(copy.MouseButton1Click:Connect(function()
		if setClipboard then
			setClipboard(viewer.TextBox.Text)
		end
	end))

	trackConnection(clear.MouseButton1Click:Connect(function()
		viewer:Clear()
	end))

	return viewer
end

return InlineViewer
