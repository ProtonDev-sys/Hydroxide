local CoreGui = game:GetService("CoreGui")
local TextService = game:GetService("TextService")
local UserInput = game:GetService("UserInputService")
local Theme = oh.Theme or import("ui/Theme")

local TextViewer = {}
local defaultViewer
local embeddedViewers = setmetatable({}, { __mode = "k" })
local DEFAULT_DOCK_WIDTH = 0.44
local MINIMUM_DOCK_RATIO = 0.3
local MAXIMUM_DOCK_RATIO = 0.7
local MINIMUM_DOCK_WIDTH = 240
local MINIMUM_PAGE_WIDTH = 220
local ACTION_BUTTON_HEIGHT = 26
local ACTION_GAP = 6

local function trackInstance(instance)
	if oh and oh.Instances then
		oh.Instances[#oh.Instances + 1] = instance
	end
end

local function trackConnection(connection)
	if oh and oh.Events then
		oh.Events[#oh.Events + 1] = connection
	end

	return connection
end

local function clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
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
	label.TextColor3 = Theme.Colors.Text
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
	button.BackgroundColor3 = Theme.Colors.Control
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSans
	button.Text = text
	button.TextColor3 = Theme.Colors.Text
	button.TextSize = 17
	button.TextTruncate = Enum.TextTruncate.AtEnd
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
	overlay.BackgroundColor3 = Theme.Colors.Overlay
	overlay.BorderSizePixel = 0
	overlay.ClipsDescendants = true
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Visible = false
	overlay.ZIndex = 80
	overlay.Parent = parent
	trackInstance(overlay)

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = Theme.Colors.Surface
	panel.BorderSizePixel = 0
	panel.Position = UDim2.new(0, 5, 0, 5)
	panel.Size = UDim2.new(1, -10, 1, -10)
	panel.ZIndex = overlay.ZIndex + 1
	panel.Parent = overlay

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 5)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Border
	stroke.Thickness = 1
	stroke.Parent = panel

	local title = makeText(panel, "Inspector", UDim2.new(1, -158, 0, 34), UDim2.new(0, 10, 0, 4), panel.ZIndex + 1)
	local copy = makeButton(panel, "Copy", UDim2.new(1, -146, 0, 8), panel.ZIndex + 1)
	local hide = makeButton(panel, "Hide", UDim2.new(1, -74, 0, 8), panel.ZIndex + 1)

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroll"
	scroller.Active = true
	scroller.BackgroundColor3 = Theme.Colors.CodeBackground
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

	local actionFrame = Instance.new("ScrollingFrame")
	actionFrame.Name = "Actions"
	actionFrame.Active = true
	actionFrame.BackgroundTransparency = 1
	actionFrame.BorderSizePixel = 0
	actionFrame.BottomImage = ""
	actionFrame.CanvasPosition = Vector2.new()
	actionFrame.CanvasSize = UDim2.new()
	actionFrame.ClipsDescendants = true
	actionFrame.MidImage = ""
	actionFrame.Position = UDim2.new(0, 8, 1, -38)
	actionFrame.ScrollBarImageColor3 = Theme.Colors.Scrollbar
	actionFrame.ScrollBarThickness = 0
	actionFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	actionFrame.Size = UDim2.new(1, -16, 0, 30)
	actionFrame.TopImage = ""
	actionFrame.Visible = false
	actionFrame.ZIndex = panel.ZIndex + 2
	actionFrame.Parent = panel

	local actionLayout = Instance.new("UIGridLayout")
	actionLayout.CellPadding = UDim2.new(0, ACTION_GAP, 0, ACTION_GAP)
	actionLayout.CellSize = UDim2.new(0, 92, 0, ACTION_BUTTON_HEIGHT)
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	actionLayout.FillDirectionMaxCells = 1
	actionLayout.SortOrder = Enum.SortOrder.LayoutOrder
	actionLayout.StartCorner = Enum.StartCorner.TopLeft
	actionLayout.Parent = actionFrame

	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Font = Enum.Font.Code
	textLabel.Text = ""
	textLabel.TextColor3 = Theme.Colors.Text
	textLabel.TextSize = 14
	textLabel.TextWrapped = false
	textLabel.TextXAlignment = Enum.TextXAlignment.Left
	textLabel.TextYAlignment = Enum.TextYAlignment.Top
	textLabel.ZIndex = scroller.ZIndex + 1
	textLabel.Parent = scroller

	local splitter

	if sourceDock ~= nil then
		splitter = Instance.new("TextButton")
		splitter.Name = "Splitter"
		splitter.Active = true
		splitter.AutoButtonColor = false
		splitter.BackgroundTransparency = 1
		splitter.BorderSizePixel = 0
		splitter.Position = UDim2.new(0, 0, 0, 5)
		splitter.Size = UDim2.new(0, 16, 1, -10)
		splitter.Text = ""
		splitter.ZIndex = overlay.ZIndex + 10
		splitter.Parent = parent

		local splitterLine = Instance.new("Frame")
		splitterLine.Name = "Line"
		splitterLine.AnchorPoint = Vector2.new(0, 0.5)
		splitterLine.BackgroundColor3 = Theme.Colors.TextMuted
		splitterLine.BorderSizePixel = 0
		splitterLine.Position = UDim2.new(0, 2, 0.5, 0)
		splitterLine.Size = UDim2.new(0, 2, 0, 34)
		splitterLine.ZIndex = splitter.ZIndex + 1
		splitterLine.Parent = splitter
	end

	local current = {
		ActionConnections = {},
		Dock = parent,
		DockRatio = DEFAULT_DOCK_WIDTH,
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
		ActionLayout = actionLayout,
		ActionWidths = {},
		Embedded = sourceDock == nil,
		NormalDockRatio = DEFAULT_DOCK_WIDTH,
		OnHide = nil,
		Panel = panel,
		SplitDragging = false,
		SplitPointer = nil,
		Splitter = splitter,
	}

	local function disconnectActionConnections()
		for _, connection in ipairs(current.ActionConnections) do
			pcall(function()
				connection:Disconnect()
			end)
		end

		current.ActionConnections = {}
	end

	local function updateHeaderLayout()
		local panelWidth = math.floor(current.Panel.AbsoluteSize.X)

		if panelWidth <= 0 then
			return
		end

		local margin = math.min(8, math.floor(panelWidth * 0.1))
		local buttonGap = math.min(4, math.max(0, panelWidth - margin * 2 - 2))
		local buttonWidth = math.max(1, math.min(68, math.floor((panelWidth - margin * 2 - buttonGap) / 2)))
		local buttonsWidth = buttonWidth * 2 + buttonGap

		copy.Position = UDim2.new(1, -(margin + buttonsWidth), 0, 8)
		copy.Size = UDim2.new(0, buttonWidth, 0, ACTION_BUTTON_HEIGHT)
		hide.Position = UDim2.new(1, -(margin + buttonWidth), 0, 8)
		hide.Size = UDim2.new(0, buttonWidth, 0, ACTION_BUTTON_HEIGHT)
		title.Size = UDim2.new(0, math.max(0, panelWidth - margin - buttonsWidth - 10), 0, 34)
		title.Visible = title.Size.X.Offset >= 24
	end

	local function getDockBounds()
		local dockParent = current.Dock.Parent
		local parentWidth = dockParent and dockParent.AbsoluteSize.X or 0

		if parentWidth <= 0 then
			return MINIMUM_DOCK_RATIO, MAXIMUM_DOCK_RATIO
		end

		local minimumDockPixels =
			math.max(parentWidth * MINIMUM_DOCK_RATIO, math.min(MINIMUM_DOCK_WIDTH, parentWidth * 0.5))
		local minimumPagePixels =
			math.max(parentWidth * (1 - MAXIMUM_DOCK_RATIO), math.min(MINIMUM_PAGE_WIDTH, parentWidth * 0.45))
		local maximumDockPixels = math.max(minimumDockPixels, parentWidth - minimumPagePixels)
		return minimumDockPixels / parentWidth, maximumDockPixels / parentWidth
	end

	local function applyDockRatio(ratio, remember)
		if current.Embedded then
			return ratio
		end

		local minimumRatio, maximumRatio = getDockBounds()
		ratio = clamp(tonumber(ratio) or DEFAULT_DOCK_WIDTH, minimumRatio, maximumRatio)
		current.DockRatio = ratio
		current.Dock.Size = UDim2.new(ratio, -12, 1, -16)

		if remember then
			current.NormalDockRatio = ratio
		end

		if current.Pages and current.RestorePagesSize then
			current.Pages.Size =
				UDim2.new(1 - ratio, -4, current.RestorePagesSize.Y.Scale, current.RestorePagesSize.Y.Offset)
		end

		return ratio
	end

	local function updateActionLayout()
		local actionCount = #current.ActionWidths

		if actionCount == 0 then
			current.ActionFrame.Visible = false
			current.ActionFrame.CanvasSize = UDim2.new()
			current.Scroller.Size = UDim2.new(1, -16, 1, -50)
			return
		end

		local width = math.floor(current.ActionFrame.AbsoluteSize.X)

		if width <= 0 then
			return
		end

		local preferredWidth = 76

		for _, actionWidth in ipairs(current.ActionWidths) do
			preferredWidth = math.max(preferredWidth, actionWidth)
		end

		local columns =
			math.max(1, math.min(actionCount, math.floor((width + ACTION_GAP) / (preferredWidth + ACTION_GAP))))
		local cellWidth =
			math.max(1, math.min(preferredWidth, math.floor((width - ACTION_GAP * (columns - 1)) / columns)))
		local rows = math.ceil(actionCount / columns)
		local contentHeight = rows * ACTION_BUTTON_HEIGHT + math.max(0, rows - 1) * ACTION_GAP
		local availablePanelHeight = math.max(ACTION_BUTTON_HEIGHT, current.Panel.AbsoluteSize.Y - 70)
		local maximumVisibleHeight = math.max(ACTION_BUTTON_HEIGHT, math.floor(availablePanelHeight * 0.35))
		local visibleHeight = math.min(contentHeight, maximumVisibleHeight)

		current.ActionLayout.FillDirectionMaxCells = columns
		current.ActionLayout.CellSize = UDim2.new(0, cellWidth, 0, ACTION_BUTTON_HEIGHT)
		current.ActionFrame.Position = UDim2.new(0, 8, 1, -(visibleHeight + 8))
		current.ActionFrame.Size = UDim2.new(1, -16, 0, visibleHeight)
		current.ActionFrame.CanvasSize = UDim2.new(0, width, 0, contentHeight)
		current.ActionFrame.ScrollBarThickness = contentHeight > visibleHeight and 4 or 0
		current.ActionFrame.Visible = true
		current.Scroller.Size = UDim2.new(1, -16, 1, -(50 + visibleHeight + 6))

		local maximumScroll = math.max(0, contentHeight - visibleHeight)
		if current.ActionFrame.CanvasPosition.Y > maximumScroll then
			current.ActionFrame.CanvasPosition = Vector2.new(0, maximumScroll)
		end
	end

	local function queueActionLayout()
		if current.ActionLayoutQueued then
			return
		end

		current.ActionLayoutQueued = true
		task.defer(function()
			current.ActionLayoutQueued = false
			if current.Overlay.Parent then
				updateActionLayout()
			end
		end)
	end

	local function cancelSplitDrag()
		current.SplitDragging = false
		current.SplitPointer = nil
	end

	current.ApplyDockRatio = applyDockRatio
	current.DisconnectActionConnections = disconnectActionConnections
	current.UpdateActionLayout = updateActionLayout
	updateHeaderLayout()

	function current.Hide()
		local wasVisible = current.Overlay.Visible
		cancelSplitDrag()
		disconnectActionConnections()
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

	trackConnection(current.ActionFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueActionLayout))
	trackConnection(panel:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		updateHeaderLayout()
		queueActionLayout()
	end))

	if current.Splitter then
		trackConnection(current.Splitter.InputBegan:Connect(function(input)
			local inputType = input.UserInputType

			if
				current.SplitDragging
				or not current.Overlay.Visible
				or (inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch)
			then
				return
			end

			current.SplitDragging = true
			current.SplitPointer = input
		end))

		trackConnection(UserInput.InputChanged:Connect(function(input)
			if not current.SplitDragging then
				return
			end

			local pointer = current.SplitPointer
			local matchesPointer = pointer
				and (
					(pointer.UserInputType == Enum.UserInputType.Touch and input == pointer)
					or (
						pointer.UserInputType == Enum.UserInputType.MouseButton1
						and input.UserInputType == Enum.UserInputType.MouseMovement
					)
				)

			if not matchesPointer then
				return
			end

			local dockParent = current.Dock.Parent
			local parentWidth = dockParent and dockParent.AbsoluteSize.X or 0

			if parentWidth > 0 then
				local localPointerX = input.Position.X - dockParent.AbsolutePosition.X
				local ratio = 1 - localPointerX / parentWidth
				applyDockRatio(ratio, true)
			end
		end))

		trackConnection(UserInput.InputEnded:Connect(function(input)
			local pointer = current.SplitPointer

			if
				pointer
				and (
					(pointer.UserInputType == Enum.UserInputType.Touch and input == pointer)
					or (
						pointer.UserInputType == Enum.UserInputType.MouseButton1
						and input.UserInputType == Enum.UserInputType.MouseButton1
					)
				)
			then
				cancelSplitDrag()
			end
		end))

		trackConnection(UserInput.WindowFocusReleased:Connect(cancelSplitDrag))
		trackConnection(current.Dock.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
			cancelSplitDrag()

			if current.Overlay.Visible then
				applyDockRatio(current.DockRatio, true)
			end
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

	current.DisconnectActionConnections()
	current.ActionWidths = {}

	for _, child in ipairs(current.ActionFrame:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end

	local actions = type(options.Actions) == "table" and options.Actions or {}
	current.ActionFrame.CanvasPosition = Vector2.new()

	for _, action in ipairs(actions) do
		if type(action) == "table" and type(action.Callback) == "function" then
			local actionIndex = #current.ActionWidths + 1
			local actionWidth = math.max(76, tonumber(action.Width) or 92)
			local actionButton = makeButton(
				current.ActionFrame,
				tostring(action.Label or action.Name or "Action"),
				UDim2.new(),
				current.ActionFrame.ZIndex + 1
			)
			actionButton.LayoutOrder = actionIndex
			actionButton.Size = UDim2.new(0, actionWidth, 0, ACTION_BUTTON_HEIGHT)
			current.ActionWidths[actionIndex] = actionWidth
			current.ActionConnections[#current.ActionConnections + 1] = actionButton.MouseButton1Click:Connect(
				function()
					action.Callback(current)
				end
			)
		end
	end

	current.UpdateActionLayout()

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
		current.ApplyDockRatio(current.NormalDockRatio, true)
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
