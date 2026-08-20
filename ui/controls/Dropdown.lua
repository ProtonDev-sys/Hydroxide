local UserInputService = game:GetService("UserInputService")

local ControlUtil = import("ui/ControlUtil")
local Theme = (oh and oh.Theme) or import("ui/Theme")

local Dropdown = {}
local openDropdown

local function refreshCanvas(dropdown)
	local selection = dropdown.Instance.Selection
	local clip = selection.Clip
	local list = clip.List
	local layout = list:FindFirstChildWhichIsA("UIListLayout") or list:FindFirstChildWhichIsA("UIGridLayout")
	local scroller = list:IsA("ScrollingFrame") and list or (clip:IsA("ScrollingFrame") and clip)

	if scroller and layout then
		scroller.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + Theme.Metrics.Gap)
		scroller.ScrollBarThickness = math.max(Theme.Metrics.ScrollbarThickness, scroller.ScrollBarThickness)
	end
end

local function bindOption(dropdown, button)
	if not button:IsA("GuiButton") then
		return
	end

	local existing = dropdown.OptionConnections[button]

	if existing then
		pcall(function()
			existing:Disconnect()
		end)
	end

	dropdown.OptionConnections[button] = ControlUtil.ConnectActivated(button, function()
		dropdown:Collapse(button.Name)
	end)
end

function Dropdown.new(instance)
	assert(instance, "Dropdown.new requires an instance")

	local selection = instance:FindFirstChild("Selection")
	local collapseButton = instance:FindFirstChild("Collapse")
	assert(selection and selection:FindFirstChild("Clip") and selection.Clip:FindFirstChild("List"), "Dropdown asset is incomplete")
	assert(collapseButton and collapseButton:IsA("GuiButton"), "Dropdown requires a Collapse button")

	local dropdown = {
		Collapsed = true,
		Connections = {},
		Instance = instance,
		OptionConnections = setmetatable({}, { __mode = "k" }),
	}

	dropdown.Collapse = Dropdown.collapse
	dropdown.Expand = Dropdown.expand
	dropdown.Toggle = Dropdown.toggle
	dropdown.SetSelected = Dropdown.setSelected
	dropdown.SetCallback = Dropdown.setCallback
	dropdown.AddOption = Dropdown.addOption
	dropdown.RemoveOption = Dropdown.removeOption
	dropdown.Destroy = Dropdown.destroy

	selection.Visible = false
	Theme.Apply(instance)

	dropdown.Connections[#dropdown.Connections + 1] = ControlUtil.ConnectActivated(collapseButton, function()
		dropdown:Toggle()
	end)

	local list = selection.Clip.List

	for _, child in ipairs(list:GetChildren()) do
		bindOption(dropdown, child)
	end

	dropdown.Connections[#dropdown.Connections + 1] =
		ControlUtil.TrackConnection(list.ChildAdded:Connect(function(child)
			bindOption(dropdown, child)
			task.defer(function()
				if dropdown.Instance then
					refreshCanvas(dropdown)
				end
			end)
		end))

	local layout = list:FindFirstChildWhichIsA("UIListLayout") or list:FindFirstChildWhichIsA("UIGridLayout")

	if layout then
		dropdown.Connections[#dropdown.Connections + 1] =
			ControlUtil.TrackConnection(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
				refreshCanvas(dropdown)
			end))
	end

	refreshCanvas(dropdown)
	return dropdown
end

function Dropdown.expand(dropdown)
	if not dropdown.Instance or dropdown.Instance.Parent == nil then
		return false
	end

	if openDropdown and openDropdown ~= dropdown then
		openDropdown:Collapse()
	end

	dropdown.Instance.Selection.Visible = true
	dropdown.Collapsed = false
	openDropdown = dropdown

	local selected = dropdown.Selected
	local firstOption = selected

	if not firstOption or not firstOption.Parent or not firstOption.Visible then
		for _, child in ipairs(dropdown.Instance.Selection.Clip.List:GetChildren()) do
			if child:IsA("GuiButton") and child.Visible then
				firstOption = child
				break
			end
		end
	end

	ControlUtil.SetSelectedObject(firstOption)
	return true
end

function Dropdown.toggle(dropdown)
	if dropdown.Collapsed then
		return dropdown:Expand()
	end

	dropdown:Collapse()
	return false
end

function Dropdown.setSelected(dropdown, buttonName, notify)
	local list = dropdown.Instance.Selection.Clip.List
	local button = list:FindFirstChild(tostring(buttonName or ""))

	if not button or not button:IsA("GuiButton") then
		return false
	end

	dropdown.Instance.Label.Text = button.Name
	dropdown.Selected = button
	dropdown:Collapse()

	if notify ~= false and dropdown.Callback then
		ControlUtil.RunCallback("Dropdown callback failed", dropdown.Callback, dropdown, button)
	end

	return true
end

function Dropdown.collapse(dropdown, name)
	if name ~= nil then
		return dropdown:SetSelected(name, true)
	end

	if dropdown.Instance then
		dropdown.Instance.Selection.Visible = false
	end

	dropdown.Collapsed = true

	if openDropdown == dropdown then
		openDropdown = nil
	end

	return true
end

function Dropdown.addOption(dropdown, name, icon)
	name = tostring(name or "")

	if name == "" then
		return nil
	end

	local list = dropdown.Instance.Selection.Clip.List
	local existing = list:FindFirstChild(name)

	if existing and existing:IsA("GuiButton") then
		return existing
	end

	local template = list:FindFirstChildWhichIsA("TextButton")

	if not template then
		return nil
	end

	local button = template:Clone()
	button.Name = name
	button.LayoutOrder = #list:GetChildren() + 1

	if button.Text ~= "" then
		button.Text = name
	end

	local label = button:FindFirstChild("Label", true)

	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label.Text = name
	end

	local image = button:FindFirstChild("Icon", true)

	if icon and image and (image:IsA("ImageLabel") or image:IsA("ImageButton")) then
		image.Image = icon
		local border = image:FindFirstChild("Border")

		if border and (border:IsA("ImageLabel") or border:IsA("ImageButton")) then
			border.Image = icon
		end
	end

	Theme.Apply(button)
	button.Parent = list
	return button
end

function Dropdown.removeOption(dropdown, name)
	local list = dropdown.Instance.Selection.Clip.List
	local button = list:FindFirstChild(tostring(name or ""))

	if not button or not button:IsA("GuiButton") then
		return false
	end

	if dropdown.Selected == button then
		dropdown.Selected = nil
	end

	local connection = dropdown.OptionConnections[button]

	if connection then
		pcall(function()
			connection:Disconnect()
		end)
		dropdown.OptionConnections[button] = nil
	end

	button:Destroy()
	refreshCanvas(dropdown)
	return true
end

function Dropdown.setCallback(dropdown, callback)
	assert(callback == nil or type(callback) == "function", "Dropdown callback must be a function or nil")
	dropdown.Callback = callback
	return dropdown
end

function Dropdown.destroy(dropdown)
	dropdown:Collapse()
	ControlUtil.DisconnectAll(dropdown.Connections)
	dropdown.Connections = {}

	for button, connection in pairs(dropdown.OptionConnections) do
		if button and connection then
			pcall(function()
				connection:Disconnect()
			end)
		end
	end

	dropdown.OptionConnections = setmetatable({}, { __mode = "k" })
	dropdown.Callback = nil
	dropdown.Instance = nil
end

ControlUtil.TrackConnection(UserInputService.InputBegan:Connect(function(input)
	local dropdown = openDropdown

	if not dropdown or not dropdown.Instance then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		dropdown:Collapse()
	elseif ControlUtil.IsPrimaryPointer(input) then
		local point = ControlUtil.GetPointerPosition(input)
		local selection = dropdown.Instance.Selection

		if not ControlUtil.ContainsPoint(dropdown.Instance, point)
			and not ControlUtil.ContainsPoint(selection, point)
		then
			dropdown:Collapse()
		end
	end
end))

ControlUtil.TrackConnection(UserInputService.WindowFocusReleased:Connect(function()
	if openDropdown then
		openDropdown:Collapse()
	end
end))

return Dropdown
