local ControlUtil = import("ui/ControlUtil")
local Theme = (oh and oh.Theme) or import("ui/Theme")

local ActionPanel = {}

local DEFAULT_BUTTON_WIDTH = 96
local DEFAULT_BUTTON_HEIGHT = Theme.Metrics.ControlHeight
local DEFAULT_GAP = Theme.Metrics.Gap
local STATUS_HEIGHT = Theme.Metrics.CompactControlHeight
local ACTIONS_TOP = STATUS_HEIGHT + Theme.Metrics.Gap
local MINIMUM_RESULTS_HEIGHT = 72

local function findTemplate(container)
	return container:FindFirstChild("Clear")
		or container:FindFirstChild("Conditions")
		or container:FindFirstChild("Ignore")
		or container:FindFirstChildWhichIsA("GuiButton")
end

local function makeToolbar(results)
	if not results or not results.Parent then
		return nil
	end

	local parent = results.Parent
	local toolbar = parent:FindFirstChild("HydroxideActionToolbar")

	if toolbar then
		return toolbar
	end

	toolbar = Instance.new("Frame")
	toolbar.Name = "HydroxideActionToolbar"
	toolbar.BackgroundTransparency = 1
	toolbar.BorderSizePixel = 0
	toolbar.ClipsDescendants = true
	toolbar.Position = results.Position
	toolbar.Size = UDim2.new(results.Size.X.Scale, results.Size.X.Offset, 0, ACTIONS_TOP)
	toolbar.ZIndex = math.max(2, results.ZIndex + 1)
	toolbar.Parent = parent
	return toolbar
end

local function makeStatus(toolbar)
	local status = Instance.new("TextLabel")
	status.Name = "InspectorStatus"
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.SourceSans
	status.Position = UDim2.new(0, 2, 0, 0)
	status.Size = UDim2.new(1, -4, 0, STATUS_HEIGHT)
	status.Text = "Select a captured call to inspect"
	status.TextColor3 = Theme.Colors.TextMuted
	status.TextSize = Theme.Typography.SmallTextSize
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.ZIndex = toolbar.ZIndex + 1
	status.Parent = toolbar
	return status
end

local function configureButton(button, toolbar, action, width, height)
	button.Name = action.Name
	button.AnchorPoint = Vector2.new(0, 0)
	button.Position = UDim2.new()
	button.Size = UDim2.new(0, action.Width or width, 0, height)
	button.Visible = true
	button.ClipsDescendants = true
	button.Selectable = true
	button.ZIndex = toolbar.ZIndex + 1

	local icon = button:FindFirstChild("Icon", true)
	local label = button:FindFirstChild("Label", true)

	if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		icon.ZIndex = button.ZIndex + 1

		if action.Icon then
			icon.Image = action.Icon

			local border = icon:FindFirstChild("Border")

			if border and (border:IsA("ImageLabel") or border:IsA("ImageButton")) then
				border.Image = action.Icon
				border.ZIndex = icon.ZIndex
			end
		end
	end

	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label.Text = action.Label or action.Name
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = button.ZIndex + 1
	end

	Theme.Apply(button)
end

function ActionPanel.Install(container, results, options)
	options = type(options) == "table" and options or {}
	local actions = options.Actions or {}

	if not container or not results or #actions == 0 then
		return nil
	end

	local template = findTemplate(container)

	if not template or not template:IsA("GuiButton") then
		return nil
	end

	local maximumColumns = math.max(1, math.floor(tonumber(options.Columns) or 5))
	local buttonWidth = math.max(72, math.floor(tonumber(options.ButtonWidth) or DEFAULT_BUTTON_WIDTH))
	local buttonHeight = math.max(
		Theme.Metrics.MinimumHitSize,
		math.floor(tonumber(options.ButtonHeight) or DEFAULT_BUTTON_HEIGHT)
	)
	local gap = math.max(2, math.floor(tonumber(options.Gap) or DEFAULT_GAP))
	local minimumCellWidth = math.max(72, math.floor(tonumber(options.MinimumCellWidth) or buttonWidth))
	local originalResultsPosition = results.Position
	local originalResultsSize = results.Size
	local toolbar = makeToolbar(results)

	if not toolbar then
		return nil
	end

	local actionsFrame = Instance.new("ScrollingFrame")
	actionsFrame.Name = "InspectorActions"
	actionsFrame.Active = true
	actionsFrame.BackgroundTransparency = 1
	actionsFrame.BorderSizePixel = 0
	actionsFrame.BottomImage = ""
	actionsFrame.CanvasPosition = Vector2.new()
	actionsFrame.CanvasSize = UDim2.new()
	actionsFrame.ClipsDescendants = true
	actionsFrame.MidImage = ""
	actionsFrame.Position = UDim2.new(0, 0, 0, ACTIONS_TOP)
	actionsFrame.ScrollBarImageColor3 = Theme.Colors.Scrollbar
	actionsFrame.ScrollBarThickness = Theme.Metrics.ScrollbarThickness
	actionsFrame.ScrollingDirection = Enum.ScrollingDirection.Y
	actionsFrame.Size = UDim2.new(1, 0, 0, buttonHeight + gap)
	actionsFrame.TopImage = ""
	actionsFrame.ZIndex = toolbar.ZIndex + 1
	actionsFrame.Parent = toolbar

	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.new(0, gap, 0, gap)
	layout.CellSize = UDim2.new(0, minimumCellWidth, 0, buttonHeight)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = maximumColumns
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.StartCorner = Enum.StartCorner.TopLeft
	layout.Parent = actionsFrame

	local panel = {
		Buttons = {},
		Connections = {},
		Enabled = {},
		Status = makeStatus(toolbar),
		Toolbar = toolbar,
	}

	local layoutQueued = false
	local layoutRunning = false
	local destroyed = false

	local function updateLayout()
		if destroyed or layoutRunning or not toolbar.Parent or not results.Parent then
			return
		end

		layoutRunning = true
		local width = math.floor(toolbar.AbsoluteSize.X)
		local parentHeight = toolbar.Parent.AbsoluteSize.Y

		if width > 0 and parentHeight > 0 then
			local layoutWidth = math.max(1, width - 4)
			local fittingColumns = math.floor((layoutWidth + gap) / (minimumCellWidth + gap))
			local columns = math.max(1, math.min(maximumColumns, #actions, fittingColumns))
			local cellWidth = math.max(1, math.floor((layoutWidth - gap * (columns - 1)) / columns))
			local rows = math.ceil(#actions / columns)
			local contentHeight = rows * buttonHeight + math.max(0, rows - 1) * gap
			local desiredToolbarHeight = ACTIONS_TOP + contentHeight + gap
			local originalResultsHeight = originalResultsSize.Y.Scale * parentHeight + originalResultsSize.Y.Offset
			local minimumToolbarHeight = ACTIONS_TOP + buttonHeight + gap
			local reservedResultsHeight =
				math.min(MINIMUM_RESULTS_HEIGHT, math.max(0, math.floor(originalResultsHeight - minimumToolbarHeight)))
			local maximumToolbarHeight = math.max(0, math.floor(originalResultsHeight - reservedResultsHeight))
			local toolbarHeight = math.min(desiredToolbarHeight, maximumToolbarHeight)
			local actionHeight = math.max(0, toolbarHeight - ACTIONS_TOP - 2)

			layout.FillDirectionMaxCells = columns
			layout.CellSize = UDim2.new(0, cellWidth, 0, buttonHeight)
			toolbar.Position = originalResultsPosition
			toolbar.Size = UDim2.new(originalResultsSize.X.Scale, originalResultsSize.X.Offset, 0, toolbarHeight)
			actionsFrame.Size = UDim2.new(1, 0, 0, actionHeight)
			actionsFrame.CanvasSize = UDim2.new(0, width, 0, contentHeight)
			actionsFrame.ScrollBarThickness =
				contentHeight > actionHeight and Theme.Metrics.ScrollbarThickness or 0
			results.Position = originalResultsPosition + UDim2.new(0, 0, 0, toolbarHeight)
			results.Size = originalResultsSize - UDim2.new(0, 0, 0, toolbarHeight)

			local maximumScroll = math.max(0, contentHeight - actionHeight)

			if actionsFrame.CanvasPosition.Y > maximumScroll then
				actionsFrame.CanvasPosition = Vector2.new(0, maximumScroll)
			end
		end

		layoutRunning = false
	end

	local function queueLayout()
		if destroyed or layoutQueued then
			return
		end

		layoutQueued = true
		task.defer(function()
			layoutQueued = false
			updateLayout()
		end)
	end

	panel.Connections[#panel.Connections + 1] =
		ControlUtil.TrackConnection(actionsFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout))
	panel.Connections[#panel.Connections + 1] =
		ControlUtil.TrackConnection(toolbar.Parent:GetPropertyChangedSignal("AbsoluteSize"):Connect(queueLayout))

	for index, action in ipairs(actions) do
		local button = template:Clone()
		button.LayoutOrder = index
		button.Parent = actionsFrame
		configureButton(button, toolbar, action, buttonWidth, buttonHeight)

		panel.Enabled[action.Name] = false

		if type(action.Callback) == "function" then
			panel.Connections[#panel.Connections + 1] = ControlUtil.ConnectActivated(button, function()
				if panel.Enabled[action.Name] then
					ControlUtil.RunCallback("Action panel callback failed", action.Callback)
				end
			end)
		end

		panel.Buttons[action.Name] = button
		ControlUtil.SetButtonEnabled(button, false)
	end

	function panel:SetStatus(primary, secondary)
		local statusText = tostring(primary or "Select a captured call to inspect")

		if secondary and secondary ~= "" then
			statusText = statusText .. "  -  " .. tostring(secondary)
		end

		self.Status.Text = statusText
	end

	function panel:SetEnabled(name, enabled)
		local button = self.Buttons[name]

		if not button then
			return false
		end

		enabled = enabled == true
		self.Enabled[name] = enabled
		ControlUtil.SetButtonEnabled(button, enabled)
		return true
	end

	function panel:Destroy()
		if destroyed then
			return
		end

		destroyed = true
		ControlUtil.DisconnectAll(self.Connections)
		self.Connections = {}

		if results and results.Parent then
			results.Position = originalResultsPosition
			results.Size = originalResultsSize
		end

		if toolbar and toolbar.Parent then
			toolbar:Destroy()
		end

		self.Buttons = {}
		self.Enabled = {}
		self.Status = nil
		self.Toolbar = nil
	end

	Theme.Apply(toolbar)
	task.defer(updateLayout)
	return panel
end

return ActionPanel
