local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")

local TextViewer = {}
local defaultViewer
local embeddedViewers = setmetatable({}, { __mode = "k" })
local DEFAULT_DOCK_WIDTH = 0.44
local EXPANDED_DOCK_WIDTH = 0.72

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

local function findExplorerDock(body)
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
end

local function findDefaultDock()
	local interface = getInterface()
	local base = interface and interface:FindFirstChild("Base")
	local body = base and base:FindFirstChild("Body")

	if body then
		local dock = body:FindFirstChild("HydroxideInspectorDock")

		if not dock then
			dock = Instance.new("Frame")
			dock.Name = "HydroxideInspectorDock"
			dock.AnchorPoint = Vector2.new(1, 0)
			dock.BackgroundTransparency = 1
			dock.BorderSizePixel = 0
			dock.ClipsDescendants = true
			dock.Position = UDim2.new(1, -8, 0, 8)
			dock.Size = UDim2.new(DEFAULT_DOCK_WIDTH, -12, 1, -16)
			dock.Visible = false
			dock.ZIndex = 70
			dock.Parent = body
		end

		return dock, findExplorerDock(body), body:FindFirstChild("Pages")
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
	local maxLineSample = ""
	local maxLineLength = 0
	local lineCount = 0
	local lineStart = 1

	while true do
		local newline = text:find("\n", lineStart, true)
		local lineEnd = newline and newline - 1 or #text
		local lineLength = math.max(0, lineEnd - lineStart + 1)
		lineCount = lineCount + 1

		if lineLength > maxLineLength then
			maxLineLength = lineLength
			maxLineSample = text:sub(lineStart, math.min(lineEnd, lineStart + 1999))
		end

		if not newline then
			break
		end

		lineStart = newline + 1
	end

	local measured, bounds =
		pcall(TextService.GetTextSize, TextService, maxLineSample, textSize, font, Vector2.new(100000, 100000))

	if not measured then
		bounds = Vector2.new(#maxLineSample * textSize * 0.65, textSize)
	end

	local characterWidth = #maxLineSample > 0 and bounds.X / #maxLineSample or textSize * 0.65
	local estimatedWidth = math.max(bounds.X, math.ceil(characterWidth * maxLineLength))
	return Vector2.new(math.max(estimatedWidth + 24, 360), math.max(lineCount * (textSize + 4) + 24, 160))
end

local function makeViewer(parent, sourceDock, pages)
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

	local title = makeText(panel, "Inspector", UDim2.new(1, -230, 0, 34), UDim2.new(0, 10, 0, 4), panel.ZIndex + 1)
	local expand = makeButton(panel, "Expand", UDim2.new(1, -218, 0, 8), panel.ZIndex + 1)
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

	local actionFrame = Instance.new("Frame")
	actionFrame.Name = "Actions"
	actionFrame.BackgroundTransparency = 1
	actionFrame.BorderSizePixel = 0
	actionFrame.Position = UDim2.new(0, 8, 1, -38)
	actionFrame.Size = UDim2.new(1, -16, 0, 30)
	actionFrame.Visible = false
	actionFrame.ZIndex = panel.ZIndex + 2
	actionFrame.Parent = panel

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	actionLayout.Padding = UDim.new(0, 6)
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionLayout.Parent = actionFrame

	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.Code
	textLabel.Text = ""
	textLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	textLabel.TextSize = 14
	textLabel.TextWrapped = false
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.ZIndex = scroller.ZIndex + 1
	textLabel.Parent = scroller

	local current = {
		Dock = parent,
		SourceDock = sourceDock,
		Pages = pages,
		OriginalPagesPosition = pages and pages.Position or nil,
		OriginalPagesSize = pages and pages.Size or nil,
		RestorePagesPosition = pages and pages.Position or nil,
		RestorePagesSize = pages and pages.Size or nil,
		RestoreSourceDockVisible = sourceDock and sourceDock.Visible or false,
		Overlay = overlay,
		Title = title,
		TextBox = textLabel,
		TextObject = textLabel,
		CopyText = "",
		Scroller = scroller,
		ActionFrame = actionFrame,
		Embedded = sourceDock == nil,
		Expanded = false,
		OnHide = nil,
	}

	function current.Hide()
		local wasVisible = current.Overlay.Visible
		current.Overlay.Visible = false

		if not current.Embedded then
			current.Dock.Visible = false

			if current.SourceDock and current.SourceDock.Parent then
				current.SourceDock.Visible = current.RestoreSourceDockVisible == true
			end

			if current.Pages and current.RestorePagesSize then
				current.Pages.Position = current.RestorePagesPosition
				current.Pages.Size = current.RestorePagesSize
			end
		end

		if wasVisible and type(current.OnHide) == "function" then
			local callback = current.OnHide
			current.OnHide = nil
			pcall(callback, current)
		end
	end

	trackConnection(copy.MouseButton1Click:Connect(function()
		if setClipboard then
			setClipboard(current.CopyText)
		end
	end))

	trackConnection(hide.MouseButton1Click:Connect(function()
		current.Hide()
	end))

	if current.Embedded then
		expand.Visible = false
		title.Size = UDim2.new(1, -158, 0, 34)
	else
		trackConnection(expand.MouseButton1Click:Connect(function()
			current.Expanded = not current.Expanded
			local width = current.Expanded and EXPANDED_DOCK_WIDTH or DEFAULT_DOCK_WIDTH
			current.Dock.Size = UDim2.new(
				width,
				-12,
				1,
				-16
			)

			if current.Pages and current.RestorePagesSize then
				current.Pages.Size =
					UDim2.new(1 - width, -4, current.RestorePagesSize.Y.Scale, current.RestorePagesSize.Y.Offset)
			end

			expand.Text = current.Expanded and "Restore" or "Expand"
		end))
	end

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

	local dock, sourceDock, pages = findDefaultDock()
	defaultViewer = makeViewer(dock, sourceDock or false, pages)
	return defaultViewer
end

function TextViewer.Show(title, text, options)
	options = type(options) == "table" and options or {}
	text = tostring(text or "")
	local copyText = options.CopyText ~= nil and tostring(options.CopyText) or text

	local settings = oh and oh.Settings or {}
	local maxBytes = tonumber(options.MaxBytes or settings.MaxInspectorBytes or settings.maxInspectorBytes) or 524288

	if maxBytes > 0 and #text > maxBytes then
		text = text:sub(1, maxBytes) .. ("\n\n-- ... inspector output truncated at %d bytes ..."):format(maxBytes)
	end

	local current = ensureViewer(options.Parent)
	current.OnHide = type(options.OnHide) == "function" and options.OnHide or nil

	if not current.Embedded and not current.Overlay.Visible then
		if current.SourceDock and current.SourceDock.Parent then
			current.RestoreSourceDockVisible = current.SourceDock.Visible
		end

		if current.Pages then
			current.RestorePagesPosition = current.Pages.Position
			current.RestorePagesSize = current.Pages.Size
		end
	end

	for _, child in ipairs(current.ActionFrame:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end

	local actions = type(options.Actions) == "table" and options.Actions or {}
	current.ActionFrame.Visible = #actions > 0
	current.Scroller.Size = UDim2.new(1, -16, 1, #actions > 0 and -86 or -50)

	for index, action in ipairs(actions) do
		if type(action) == "table" and type(action.Callback) == "function" then
			local actionButton = makeButton(current.ActionFrame, tostring(action.Label or action.Name or "Action"), UDim2.new(), current.ActionFrame.ZIndex + 1)
			actionButton.LayoutOrder = index
			actionButton.Size = UDim2.new(0, math.max(76, tonumber(action.Width) or 92), 0, 26)
			actionButton.MouseButton1Click:Connect(function()
				action.Callback(current)
			end)
		end
	end

	current.Title.Text = tostring(title or "Inspector")
	current.TextBox.Text = text
	current.CopyText = copyText
	current.Scroller.CanvasPosition = Vector2.new()

	local size = estimateTextSize(text, current.TextBox.TextSize, current.TextBox.Font)
	current.TextBox.Size = UDim2.new(0, size.X, 0, size.Y)
	current.Scroller.CanvasSize = UDim2.new(0, size.X + 16, 0, size.Y + 16)

	if not current.Embedded then
		if current.SourceDock and current.SourceDock.Parent then
			current.SourceDock.Visible = false
		end

		current.Dock.Visible = true

		if current.Pages and current.RestorePagesSize then
			local width = current.Expanded and EXPANDED_DOCK_WIDTH or DEFAULT_DOCK_WIDTH
			current.Pages.Size =
				UDim2.new(1 - width, -4, current.RestorePagesSize.Y.Scale, current.RestorePagesSize.Y.Offset)
		end
	end

	current.Overlay.Visible = true
	return current
end

function TextViewer.HideDefault()
	if not (defaultViewer and defaultViewer.Overlay) then
		return
	end

	defaultViewer.Hide()
end

function TextViewer.Hide(viewer)
	if viewer and type(viewer.Hide) == "function" then
		viewer.Hide()
	end
end

return TextViewer
