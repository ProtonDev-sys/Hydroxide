local UserInput = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Theme = oh.Theme or import("ui/Theme")

local List = {}
local ListButton = {}

local lists = {}
local ctrlHeld = false
local constants = {
	tweenTime = TweenInfo.new(0.15),
	selected = Theme.Colors.Selection,
	deselected = Theme.Colors.Row,
}

function List.new(instance, multiClick)
	local list = {}

	instance.CanvasSize = UDim2.new(0, 0, 0, 15)

	list.Buttons = {}
	list.Instance = instance
	list.Clear = List.clear
	list.Recalculate = List.recalculate
	list.QueueRecalculate = List.queueRecalculate
	list.BeginBatch = List.beginBatch
	list.EndBatch = List.endBatch
	list.BindContextMenu = List.bindContextMenu
	list.BindContextMenuSelected = List.bindContextMenuSelected
	list.MultiClickEnabled = multiClick
	list.BatchDepth = 0
	list.RecalculateQueued = false

	table.insert(lists, list)

	return list
end

function ListButton.new(instance, list)
	local listButton = {}
	local listInstance = list.Instance

	list.Buttons[instance] = listButton

	instance.Parent = listInstance
	instance.MouseButton1Click:Connect(function()
		if not ctrlHeld and listButton.Callback then
			listButton.Callback()
		elseif list.MultiClickEnabled and ctrlHeld then
			if not list.Selected then
				list.Selected = {}
			end

			if listButton.SelectedCallback then
				listButton.SelectedCallback()
			end

			local foundButton = table.find(list.Selected, listButton)

			if not foundButton then
				table.insert(list.Selected, listButton)
				listButton.SelectAnimation:Play()
			else
				table.remove(list.Selected, foundButton)
				listButton.DeselectAnimation:Play()
			end
		end
	end)

	instance.MouseButton2Click:Connect(function()
		if not ctrlHeld and listButton.RightCallback then
			listButton.RightCallback()
		end
	end)

	listButton.List = list
	listButton.Instance = instance
	listButton.SetCallback = ListButton.setCallback
	listButton.SetRightCallback = ListButton.setRightCallback
	listButton.SetSelectedCallback = ListButton.setSelectedCallback
	listButton.Remove = ListButton.remove
	listButton.SelectAnimation =
		TweenService:Create(instance, constants.tweenTime, { ImageColor3 = constants.selected })
	listButton.DeselectAnimation =
		TweenService:Create(instance, constants.tweenTime, { ImageColor3 = constants.deselected })
	list:QueueRecalculate()
	return listButton
end

function List.clear(list)
	local instance = list.Instance

	for _i, listButton in pairs(instance:GetChildren()) do
		if listButton:IsA("ImageButton") then
			listButton:Destroy()
		end
	end

	instance.CanvasSize = UDim2.new(0, 0, 0, 15)
	list.Buttons = {}
	list.Selected = nil
	list.RecalculateQueued = false
end

function List.recalculate(list)
	local newHeight = 15
	local selected = list.Selected

	for instance in pairs(list.Buttons) do
		if not instance.Parent then
			list.Buttons[instance] = nil
		elseif instance.Visible then
			newHeight = newHeight + instance.AbsoluteSize.Y + 5
		end
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
	if not list.BoundContextMenu then
		local function showContextMenu()
			if not list.Selected then
				contextMenu:Show()
			end
		end

		list.Instance.ChildAdded:Connect(function(instance)
			instance.MouseButton2Click:Connect(showContextMenu)
		end)

		list.BoundContextMenu = contextMenu
	end
end

function List.bindContextMenuSelected(list, contextMenu)
	if not list.BoundContextMenuSelected then
		local function showContextMenu()
			if list.Selected then
				contextMenu:Show()
			end
		end

		list.Instance.ChildAdded:Connect(function(instance)
			instance.MouseButton2Click:Connect(showContextMenu)
		end)

		list.BoundContextMenuSelected = contextMenu
	end
end

function ListButton.setCallback(listButton, callback)
	listButton.Callback = callback
end

function ListButton.setRightCallback(listButton, callback)
	listButton.RightCallback = callback
end

function ListButton.setSelectedCallback(listButton, callback)
	listButton.SelectedCallback = callback
end

function ListButton.remove(listButton)
	local list = listButton.List
	local instance = listButton.Instance

	list.Buttons[instance] = nil

	if list.Selected then
		local selectedIndex = table.find(list.Selected, listButton)

		if selectedIndex then
			table.remove(list.Selected, selectedIndex)
		end

		if #list.Selected == 0 then
			list.Selected = nil
		end
	end

	instance:Destroy()
	list:QueueRecalculate()
end

oh.Events.ListInputBegan = UserInput.InputBegan:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftControl then
		ctrlHeld = true
	elseif not ctrlHeld and input.UserInputType == Enum.UserInputType.MouseButton1 then
		for _i, list in pairs(lists) do
			if list.Selected then
				for _k, listButton in pairs(list.Selected) do
					listButton.DeselectAnimation:Play()
				end

				list.Selected = nil
			end
		end
	end
end)

oh.Events.ListInputEnded = UserInput.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftControl then
		ctrlHeld = false
	end
end)

return List, ListButton
