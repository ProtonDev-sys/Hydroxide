local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")

local TextViewer = {}
local defaultViewer
local embeddedViewers = setmetatable({}, { __mode = "k" })

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

local function getInterface()
	local ran, interface = pcall(import, "rbxassetid://11389137937")
	return ran and interface or nil
end

local function findDefaultDock()
	local interface = getInterface()
	local base = interface and interface:FindFirstChild("Base")
	local body = base and base:FindFirstChild("Body")

	if body then
		for _, descendant in ipairs(body:GetDescendants()) do
			if descendant:IsA("TextBox") then
				local placeholder = tostring(descendant.PlaceholderText or ""):lower()

				if placeholder:find("filter explorer", 1, true) then
					local ancestor = descendant.Parent

					while ancestor and ancestor ~= body do
						if ancestor:IsA("GuiObject") and ancestor.Name:lower():find("explorer", 1, true) then
							return ancestor
						end

						ancestor = ancestor.Parent
					end
				end
			end
		end

		local dock = body:FindFirstChild("HydroxideInspectorDock")

		if not dock then
			dock = Instance.new("Frame")
			dock.Name = "HydroxideInspectorDock"
			dock.AnchorPoint = Vector2.new(1, 0)
			dock.BackgroundTransparency = 1
			dock.BorderSizePixel = 0
			dock.ClipsDescendants = true
			dock.Position = UDim2.new(1, -8, 0, 8)
			dock.Size = UDim2.new(0.4, -12, 1, -16)
			dock.ZIndex = 70
			dock.Parent = body
		end

		return dock
	end

	return interface or CoreGui
end

local function makeText(parent, text, size, position, zIndex)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSans
	label.Text = text
	label.TextColor3 = Color3.fromRGB(235, 235, 235)
	label.TextSize = 18
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Size = size
	label.Position = position
	label.ZIndex = zIndex
	label.Parent = parent
	return label
end

local function makeButton(parent, text, position, zIndex)
	local button = Instance.new("TextButton")
	button.AutoButtonColor = true
	button.BackgroundColor3 = Color3.fromRGB(42, 42, 42)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSans
	button.Text = text
	button.TextColor3 = Color3.fromRGB(240, 240, 240)
	button.TextSize = 17
	button.Size = UDim2.new(0, 68, 0, 26)
	button.Position = position
	button.ZIndex = zIndex
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

	return Vector2.new(math.max(bounds.X + 24, 360), math.max(lineCount * (textSize + 4) + 24, 160))
end

local function makeViewer(parent)
	local overlay = Instance.new("Frame")
	overlay.Name = "HydroxideIntegratedTextViewer"
	overlay.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
	overlay.BorderSizePixel = 0
	overlay.ClipsDescendants = true
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Visible = false
	overlay.ZIndex = 80
	overlay.Parent = parent
	trackInstance(overlay)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Color3.fromRGB(24, 24, 24)
	panel.BorderSizePixel = 0
	panel.Position = UDim2.new(0, 5, 0, 5)
	panel.Size = UDim2.new(1, -10, 1, -10)
	panel.ZIndex = overlay.ZIndex + 1
	panel.Parent = overlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(65, 65, 65)
	stroke.Thickness = 1
	stroke.Parent = panel

	local title = makeText(panel, "Inspector", UDim2.new(1, -158, 0, 34), UDim2.new(0, 10, 0, 4), panel.ZIndex + 1)
	local copy = makeButton(panel, "Copy", UDim2.new(1, -146, 0, 8), panel.ZIndex + 1)
	local hide = makeButton(panel, "Hide", UDim2.new(1, -74, 0, 8), panel.ZIndex + 1)

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroll"
	scroller.Active = true
	scroller.BackgroundColor3 = Color3.fromRGB(12, 12, 12)
	scroller.BorderSizePixel = 0
	scroller.BottomImage = ""
	scroller.CanvasPosition = Vector2.new()
	scroller.MidImage = ""
	scroller.Position = UDim2.new(0, 8, 0, 42)
	scroller.ScrollBarThickness = 7
	scroller.Size = UDim2.new(1, -16, 1, -50)
	scroller.TopImage = ""
	scroller.ZIndex = panel.ZIndex + 1
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
	textBox.Text = ""
	textBox.TextColor3 = Color3.fromRGB(230, 230, 230)
	textBox.TextEditable = false
	textBox.TextSize = 14
	textBox.TextWrapped = false
	textBox.TextXAlignment = Enum.TextXAlignment.Left
	textBox.TextYAlignment = Enum.TextYAlignment.Top
	textBox.ZIndex = scroller.ZIndex + 1
	textBox.Parent = scroller

	local current = {
		Overlay = overlay,
		Title = title,
		TextBox = textBox,
		Scroller = scroller,
	}

	trackConnection(copy.MouseButton1Click:Connect(function()
		if setClipboard then
			setClipboard(current.TextBox.Text)
		end
	end))

	trackConnection(hide.MouseButton1Click:Connect(function()
		current.Overlay.Visible = false
	end))

	return current
end

local function ensureViewer(parent)
	if parent then
		local current = embeddedViewers[parent]

		if current and current.Overlay and current.Overlay.Parent then
			return current
		end

		current = makeViewer(parent)
		embeddedViewers[parent] = current
		return current
	end

	if defaultViewer and defaultViewer.Overlay and defaultViewer.Overlay.Parent then
		return defaultViewer
	end

	defaultViewer = makeViewer(findDefaultDock())
	return defaultViewer
end

function TextViewer.Show(title, text, options)
	options = type(options) == "table" and options or {}
	text = tostring(text or "")

	local current = ensureViewer(options.Parent)
	current.Title.Text = tostring(title or "Inspector")
	current.TextBox.Text = text
	current.TextBox.TextEditable = options.Editable == true
	current.Scroller.CanvasPosition = Vector2.new()

	local size = estimateTextSize(text, current.TextBox.TextSize, current.TextBox.Font)
	current.TextBox.Size = UDim2.new(0, size.X, 0, size.Y)
	current.Scroller.CanvasSize = UDim2.new(0, size.X + 16, 0, size.Y + 16)
	current.Overlay.Visible = true
	return current
end

return TextViewer
