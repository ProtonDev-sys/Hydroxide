local ActionPanel = {}

local DEFAULT_BUTTON_WIDTH = 96
local DEFAULT_BUTTON_HEIGHT = 22
local DEFAULT_GAP = 5
local STATUS_TOP = 25
local STATUS_HEIGHT = 20
local ACTIONS_TOP = 48

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

local function shiftResults(results, offset)
	if not results or results:GetAttribute("HydroxideActionPanelShifted") then
		return
	end

	results.Position = results.Position + UDim2.new(0, 0, 0, offset)
	results.Size = results.Size - UDim2.new(0, 0, 0, offset)
	results:SetAttribute("HydroxideActionPanelShifted", true)
end

local function makeStatus(container)
	local status = container:FindFirstChild("InspectorStatus")

	if status then
		return status
	end

	status = Instance.new("TextLabel")
	status.Name = "InspectorStatus"
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.SourceSans
	status.Position = UDim2.new(0, 1, 0, STATUS_TOP)
	status.Size = UDim2.new(1, -2, 0, STATUS_HEIGHT)
	status.Text = "Select a captured call to inspect"
	status.TextColor3 = Color3.fromRGB(155, 155, 155)
	status.TextSize = 15
	status.TextTruncate = Enum.TextTruncate.AtEnd
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.ZIndex = 2
	status.Parent = container
	return status
end

local function configureButton(button, action, width, height)
	button.Name = action.Name
	button.Size = UDim2.new(0, action.Width or width, 0, height)
	button.Visible = true

	local icon = button:FindFirstChild("Icon", true)
	local label = button:FindFirstChild("Label", true)

	if icon and action.Icon then
		icon.Image = action.Icon

		local border = icon:FindFirstChild("Border")

		if border and border:IsA("ImageLabel") then
			border.Image = action.Icon
		end
	end

	if label then
		label.Text = action.Label or action.Name
		label.TextTruncate = Enum.TextTruncate.AtEnd
	end
end

function ActionPanel.Install(container, results, options)
	options = type(options) == "table" and options or {}

	local actions = options.Actions or {}

	if not container or #actions == 0 then
		return nil
	end

	local template = findTemplate(container)

	if not template then
		return nil
	end

	local panel = {
		Buttons = {},
		Enabled = {},
		Status = makeStatus(container),
	}
	local columns = math.max(1, math.floor(tonumber(options.Columns) or 5))
	local buttonWidth = math.max(72, math.floor(tonumber(options.ButtonWidth) or DEFAULT_BUTTON_WIDTH))
	local buttonHeight = math.max(20, math.floor(tonumber(options.ButtonHeight) or DEFAULT_BUTTON_HEIGHT))
	local gap = math.max(2, math.floor(tonumber(options.Gap) or DEFAULT_GAP))
	local rows = math.ceil(#actions / columns)
	local actionHeight = rows * (buttonHeight + gap)

	container.ClipsDescendants = false
	container.Size = UDim2.new(1, -16, container.Size.Y.Scale, math.max(container.Size.Y.Offset, ACTIONS_TOP + actionHeight))
	shiftResults(results, STATUS_HEIGHT + actionHeight + 9)

	for index, action in ipairs(actions) do
		local button = container:FindFirstChild(action.Name)

		if not button then
			button = template:Clone()
			button.Parent = container
		end

		local column = (index - 1) % columns
		local row = math.floor((index - 1) / columns)

		configureButton(button, action, buttonWidth, buttonHeight)

		if not action.Width then
			button.Size = UDim2.new(1 / columns, -(gap * (columns - 1) / columns), 0, buttonHeight)
			button.Position = UDim2.new(
				column / columns,
				column * gap / columns,
				0,
				ACTIONS_TOP + row * (buttonHeight + gap)
			)
		else
			button.Position = UDim2.new(0, column * (buttonWidth + gap), 0, ACTIONS_TOP + row * (buttonHeight + gap))
		end

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
		local text = tostring(primary or "Select a captured call to inspect")

		if secondary and secondary ~= "" then
			text = text .. "  -  " .. tostring(secondary)
		end

		self.Status.Text = text
	end

	function panel:SetEnabled(name, enabled)
		local button = self.Buttons[name]

		if not button then
			return
		end

		button.Active = enabled == true
		button.AutoButtonColor = enabled == true
		self.Enabled[name] = enabled == true

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
