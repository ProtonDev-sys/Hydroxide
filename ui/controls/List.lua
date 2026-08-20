local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")

local ControlUtil = import("ui/ControlUtil")
local Theme = (oh and oh.Theme) or import("ui/Theme")

local List = {}
local ListButton = {}

local lists = setmetatable({}, { __mode = "k" })
local ctrlHeld = false
local constants = {
	selected = Theme.Colors.Selection,
	deselected = Theme.Colors.Row,
}

local function isControlKey(keyCode)
	return keyCode == Enum.KeyCode.LeftControl or keyCode == Enum.KeyCode.RightControl
end

local function makeSelectionTween(instance, selected)
	local property = instance:IsA("ImageButton") and "ImageColor3" or "BackgroundColor3"

	return TweenService:Create(
		instance,
		TweenInfo.new(ControlUtil.MotionDuration(Theme.Motion.Normal)),
		{ [property] = selected and constants.selected or constants.deselected }
	)
end

local function bindContextButton(list, instance, contextMenu, selectedOnly)
	if not instance:IsA("GuiButton") then
		return
	end

	local key = selectedOnly and "Selected" or "Normal"
	list.ContextConnections[key] = list.ContextConnections[key] or setmetatable({}, { __mode = "k" })

	if list.ContextConnections[key][instance] then
		return
	end

	list.ContextConnections[key][instance] = ControlUtil.ConnectSecondary(instance, function()
		if (selectedOnly and list.Selected) or (not selectedOnly and not list.Selected) then
			contextMenu:Show()
		end
	end)
end

function List.new(instance, multiClick)
	local list = {
		BatchDepth = 0,
		Buttons = {},
		Connections = {},
		ContextConnections = {},
		Instance = instance,
		MultiClickEnabled = multiClick == true,
		RecalculateQueued = false,
	}

	instance.CanvasSize = UDim2.new(0, 0, 0, 15)
	instance.ScrollBarThickness = math.max(Theme.Metrics.ScrollbarThickness, instance.ScrollBarThickness)

	list.Clear = List.clear
	list.ClearSelection = List.clearSelection
	list.Recalculate = List.recalculate
	list.QueueRecalculate = List.queueRecalculate
	list.BeginBatch = List.beginBatch
	list.EndBatch = List.endBatch
	list.BindContextMenu = List.bindContextMenu
	list.BindContextMenuSelected = List.bindContextMenuSelected
	list.Destroy = List.destroy

	lists[list] = true
	return list
end

function ListButton.new(instance, list)
	assert(instance and instance:IsA("GuiButton"), "ListButton.new expects a GuiButton")

	local listButton = {
		Connections = {},
		Instance = instance,
		List = list,
	}

	listButton.SetCallback = ListButton.setCallback
	listButton.SetRightCallback = ListButton.setRightCallback
	listButton.SetSelectedCallback = ListButton.setSelectedCallback
	listButton.SetSelected = ListButton.setSelected
	listButton.Remove = ListButton.remove
	listButton.SelectAnimation = makeSelectionTween(instance, true)
	listButton.DeselectAnimation = makeSelectionTween(instance, false)

	list.Buttons[instance] = listButton
	instance.Parent = list.Instance
	instance.Selectable = true
	Theme.ApplyObject(instance)

	listButton.Connections[#listButton.Connections + 1] = ControlUtil.ConnectActivated(instance, function()
		if not ctrlHeld then
			ControlUtil.RunCallback("List row callback failed", listButton.Callback)
		elseif list.MultiClickEnabled then
			listButton:SetSelected(not listButton.Selected, true)
		end
	end)

	listButton.Connections[#listButton.Connections + 1] = ControlUtil.ConnectSecondary(instance, function()
		if not ctrlHeld then
			ControlUtil.RunCallback("List row secondary callback failed", listButton.RightCallback)
		end
	end)

	if list.BoundContextMenu then
		bindContextButton(list, instance, list.BoundContextMenu, false)
	end

	if list.BoundContextMenuSelected then
		bindContextButton(list, instance, list.BoundContextMenuSelected, true)
	end

	list:QueueRecalculate()
	return listButton
end

function List.clearSelection(list)
	if not list.Selected then
		return false
	end

	for _, listButton in ipairs(list.Selected) do
		listButton.Selected = false
		listButton.DeselectAnimation:Play()
	end

	list.Selected = nil
	return true
end

function List.clear(list)
	list:ClearSelection()
	local buttons = {}

	for instance, listButton in pairs(list.Buttons) do
		buttons[#buttons + 1] = { instance, listButton }
	end

	for _, entry in ipairs(buttons) do
		local instance = entry[1]
		local listButton = entry[2]
		ControlUtil.DisconnectAll(listButton.Connections)
		list.Buttons[instance] = nil

		if instance and instance.Parent then
			instance:Destroy()
		end
	end

	list.Instance.CanvasSize = UDim2.new(0, 0, 0, 15)
	list.RecalculateQueued = false
end

function List.recalculate(list)
	local newHeight = 15
	local selected = list.Selected

	local staleInstances = {}

	for instance in pairs(list.Buttons) do
		if not instance.Parent then
			staleInstances[#staleInstances + 1] = instance
		elseif instance.Visible then
			newHeight = newHeight + instance.AbsoluteSize.Y + 5
		end
	end

	for _, instance in ipairs(staleInstances) do
		list.Buttons[instance] = nil
	end

	if selected then
		for index = #selected, 1, -1 do
			local listButton = selected[index]

			if not listButton.Instance or not listButton.Instance.Parent or not list.Buttons[listButton.Instance] then
				table.remove(selected, index)
			end
		end

		if #selected == 0 then
			list.Selected = nil
		end
	end

	list.Instance.CanvasSize = UDim2.new(0, 0, 0, newHeight)
	list.RecalculateQueued = false
end

function List.queueRecalculate(list)
	if list.BatchDepth > 0 then
		list.RecalculateQueued = true
		return
	end

	if list.RecalculateQueued then
		return
	end

	list.RecalculateQueued = true
	task.defer(function()
		if list.Instance and list.Instance.Parent then
			list:Recalculate()
		else
			list.RecalculateQueued = false
		end
	end)
end

function List.beginBatch(list)
	list.BatchDepth = (list.BatchDepth or 0) + 1
end

function List.endBatch(list)
	list.BatchDepth = math.max((list.BatchDepth or 1) - 1, 0)

	if list.BatchDepth == 0 and list.RecalculateQueued then
		list.RecalculateQueued = false
		list:QueueRecalculate()
	end
end

function List.bindContextMenu(list, contextMenu)
	if list.BoundContextMenu then
		return
	end

	list.BoundContextMenu = contextMenu

	for instance in pairs(list.Buttons) do
		bindContextButton(list, instance, contextMenu, false)
	end

	list.Connections[#list.Connections + 1] =
		ControlUtil.TrackConnection(list.Instance.ChildAdded:Connect(function(instance)
			bindContextButton(list, instance, contextMenu, false)
		end))
end

function List.bindContextMenuSelected(list, contextMenu)
	if list.BoundContextMenuSelected then
		return
	end

	list.BoundContextMenuSelected = contextMenu

	for instance in pairs(list.Buttons) do
		bindContextButton(list, instance, contextMenu, true)
	end

	list.Connections[#list.Connections + 1] =
		ControlUtil.TrackConnection(list.Instance.ChildAdded:Connect(function(instance)
			bindContextButton(list, instance, contextMenu, true)
		end))
end

function List.destroy(list)
	list:Clear()
	ControlUtil.DisconnectAll(list.ContextConnections)
	ControlUtil.DisconnectAll(list.Connections)
	list.ContextConnections = {}
	list.Connections = {}
	lists[list] = nil
end

function ListButton.setCallback(listButton, callback)
	listButton.Callback = callback
	return listButton
end

function ListButton.setRightCallback(listButton, callback)
	listButton.RightCallback = callback
	return listButton
end

function ListButton.setSelectedCallback(listButton, callback)
	listButton.SelectedCallback = callback
	return listButton
end

function ListButton.setSelected(listButton, selected, notify)
	local list = listButton.List
	selected = selected == true

	if listButton.Selected == selected then
		return false
	end

	listButton.Selected = selected
	list.Selected = list.Selected or {}

	local index = table.find(list.Selected, listButton)

	if selected and not index then
		list.Selected[#list.Selected + 1] = listButton
		listButton.SelectAnimation:Play()
	elseif not selected and index then
		table.remove(list.Selected, index)
		listButton.DeselectAnimation:Play()
	end

	if list.Selected and #list.Selected == 0 then
		list.Selected = nil
	end

	if notify then
		ControlUtil.RunCallback("List selection callback failed", listButton.SelectedCallback)
	end

	return true
end

function ListButton.remove(listButton)
	local list = listButton.List
	local instance = listButton.Instance

	if not list or not instance then
		return false
	end

	if listButton.Selected then
		listButton:SetSelected(false, false)
	end

	ControlUtil.DisconnectAll(listButton.Connections)
	listButton.Connections = {}

	for _, connections in pairs(list.ContextConnections) do
		local connection = connections[instance]

		if connection then
			ControlUtil.DisconnectAll({ connection })
			connections[instance] = nil
		end
	end

	list.Buttons[instance] = nil
	instance:Destroy()
	listButton.Instance = nil
	listButton.List = nil
	list:QueueRecalculate()
	return true
end

ControlUtil.TrackConnection(UserInputService.InputBegan:Connect(function(input)
	if isControlKey(input.KeyCode) then
		ctrlHeld = true
	elseif not ctrlHeld and ControlUtil.IsPrimaryPointer(input) then
		for list in pairs(lists) do
			list:ClearSelection()
		end
	end
end))

ControlUtil.TrackConnection(UserInputService.InputEnded:Connect(function(input)
	if isControlKey(input.KeyCode) then
		ctrlHeld = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
			or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	end
end))

ControlUtil.TrackConnection(UserInputService.WindowFocusReleased:Connect(function()
	ctrlHeld = false
end))

return List, ListButton
