local ActionPanel = {}

local DEFAULT_BUTTON_WIDTH = 96
local DEFAULT_BUTTON_HEIGHT = 22
local DEFAULT_GAP = 5
local STATUS_HEIGHT = 20
local ACTIONS_TOP = STATUS_HEIGHT + 4

local function trackConnection(connection)
	if oh and oh.Events then
		oh.Events[#oh.Events + 1] = connection
	end
end

local function findTemplate(container)
	return container:FindFirstChild("Clear")
		or container:FindFirstChild("Conditions")
		or container:FindFirstChild("Ignore")
		or container:FindFirstChildWhichIsA("GuiButton")
end

local function makeToolbar(results, height)
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
	toolbar.Size = UDim2.new(results.Size.X.Scale, results.Size.X.Offset, 0, height)
	toolbar.ZIndex = math.max(2, results.ZIndex + 1)
	toolbar.Parent = parent

	results.Position = results.Position + UDim2.new(0, 0, 0, height)
	results.Size = results.Size - UDim2.new(0, 0, 0, height)
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
	status.TextColor3 = Color3.fromRGB(155, 155, 155)
	status.TextSize = 15
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.ZIndex = toolbar.ZIndex + 1
	status.Parent = toolbar
	return status
end

local function configureButton(button, toolbar, action, width, height)
	button.Name = action.Name
	button.Size = UDim2.new(0, action.Width or width, 0, height)
	button.Visible = true
	button.ClipsDescendants = true
	button.ZIndex = toolbar.ZIndex + 1

	local icon = button:FindFirstChild("Icon", true)
	local label = button:FindFirstChild("Label", true)

	if icon then
		icon.ZIndex = button.ZIndex + 1

		if action.Icon then
			icon.Image = action.Icon

			local border = icon:FindFirstChild("Border")

			if border and border:IsA("ImageLabel") then
				border.Image = action.Icon
				border.ZIndex = icon.ZIndex
			end
		end
	end

	if label then
		label.Text = action.Label or action.Name
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = button.ZIndex + 1
	end
end

function ActionPanel.Install(container, results, options)
	options = type(options) == "table" and options or {}

	local actions = options.Actions or {}

	if not container or not results or #actions == 0 then
		return nil
	end

	local template = findTemplate(container)

	if not template then
		return nil
	end

	local columns = math.max(1, math.floor(tonumber(options.Columns) or 5))
	local buttonWidth = math.max(72, math.floor(tonumber(options.ButtonWidth) or DEFAULT_BUTTON_WIDTH))
	local buttonHeight = math.max(20, math.floor(tonumber(options.ButtonHeight) or DEFAULT_BUTTON_HEIGHT))
	local gap = math.max(2, math.floor(tonumber(options.Gap) or DEFAULT_GAP))
	local rows = math.ceil(#actions / columns)
	local actionHeight = rows * buttonHeight + math.max(0, rows - 1) * gap
	local toolbarHeight = ACTIONS_TOP + actionHeight + 2
	local toolbar = makeToolbar(results, toolbarHeight)

	if not toolbar then
		return nil
	end

	local actionsFrame = Instance.new("Frame")
	actionsFrame.Name = "InspectorActions"
	actionsFrame.BackgroundTransparency = 1
	actionsFrame.BorderSizePixel = 0
	actionsFrame.ClipsDescendants = true
	actionsFrame.Position = UDim2.new(0, 0, 0, ACTIONS_TOP)
	actionsFrame.Size = UDim2.new(1, 0, 0, actionHeight)
	actionsFrame.ZIndex = toolbar.ZIndex + 1
	actionsFrame.Parent = toolbar

	local layout = Instance.new("UIGridLayout")
	layout.CellPadding = UDim2.new(0, gap, 0, gap)
	layout.CellSize = UDim2.new(1 / columns, -gap * (columns - 1) / columns, 0, buttonHeight)
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.FillDirectionMaxCells = columns
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.StartCorner = Enum.StartCorner.TopLeft
	layout.Parent = actionsFrame

	local panel = {
		Buttons = {},
		Enabled = {},
		Status = makeStatus(toolbar),
		Toolbar = toolbar,
	}

	for index, action in ipairs(actions) do
		local button = template:Clone()
		button.LayoutOrder = index
		button.Parent = actionsFrame

		configureButton(button, toolbar, action, buttonWidth, buttonHeight)

		panel.Enabled[action.Name] = false
		if type(action.Callback) == "function" then
			trackConnection(button.MouseButton1Click:Connect(function()
				if panel.Enabled[action.Name] then
					action.Callback()
				end
			end))
		end

		panel.Buttons[action.Name] = button
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
			return
		end

		enabled = enabled == true
		button.Active = enabled
		button.AutoButtonColor = enabled
		self.Enabled[name] = enabled

		if button:IsA("ImageButton") then
			button.ImageTransparency = enabled and 0 or 0.45
		end

		local label = button:FindFirstChild("Label", true)
		local icon = button:FindFirstChild("Icon", true)

		if label then
			label.TextTransparency = enabled and 0 or 0.45
		end

		if icon then
			icon.ImageTransparency = enabled and 0 or 0.45
		end
	end

	return panel
end

return ActionPanel
