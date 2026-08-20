local Assets = import("rbxassetid://5042114982").Controls
local Storage = import("rbxassetid://11389137937").ContextMenus

local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ControlUtil = import("ui/ControlUtil")
local Theme = (oh and oh.Theme) or import("ui/Theme")

local ContextMenuButton = {}
local ContextMenu = {}

local currentContextMenu
local BODY_FONT = Enum.Font.SourceSans
local textConstraint = Vector2.new(1337420, Theme.Metrics.ControlHeight)

local function hideCurrent()
	local contextMenu = currentContextMenu
	currentContextMenu = nil

	if contextMenu then
		contextMenu:Hide()
	end
end

local function makeTween(object, properties)
	return TweenService:Create(
		object,
		TweenInfo.new(ControlUtil.MotionDuration(Theme.Motion.Normal)),
		properties
	)
end

function ContextMenuButton.new(icon, text)
	local instance = Assets.ContextMenuButton:Clone()
	local label = instance:FindFirstChild("Label")
	local iconObject = instance:FindFirstChild("Icon")

	assert(instance:IsA("GuiButton"), "ContextMenuButton asset must be a GuiButton")
	assert(label and label:IsA("TextLabel"), "ContextMenuButton asset requires a Label")

	local contextMenuButton = {
		Connections = {},
		Instance = instance,
	}

	contextMenuButton.SetIcon = ContextMenuButton.setIcon
	contextMenuButton.SetText = ContextMenuButton.setText
	contextMenuButton.SetCallback = ContextMenuButton.setCallback
	contextMenuButton.SetEnabled = ContextMenuButton.setEnabled
	contextMenuButton.Destroy = ContextMenuButton.destroy

	label.Text = tostring(text or "")
	label.TextWrapped = false

	if iconObject and (iconObject:IsA("ImageLabel") or iconObject:IsA("ImageButton")) and icon then
		iconObject.Image = icon
	end

	Theme.Apply(instance)

	local enterAnimation = makeTween(label, { TextTransparency = 0 })
	local leaveAnimation = makeTween(label, { TextTransparency = 0.2 })
	contextMenuButton.EnterAnimation = enterAnimation
	contextMenuButton.LeaveAnimation = leaveAnimation

	contextMenuButton.Connections[#contextMenuButton.Connections + 1] =
		ControlUtil.ConnectActivated(instance, function()
			if contextMenuButton.Enabled == false then
				return
			end

			local callback = contextMenuButton.Callback
			hideCurrent()
			ControlUtil.RunCallback("Context menu action failed", callback)
		end)

	contextMenuButton.Connections[#contextMenuButton.Connections + 1] =
		ControlUtil.TrackConnection(instance.MouseEnter:Connect(function()
			if contextMenuButton.Enabled ~= false then
				enterAnimation:Play()
			end
		end))

	contextMenuButton.Connections[#contextMenuButton.Connections + 1] =
		ControlUtil.TrackConnection(instance.MouseLeave:Connect(function()
			if contextMenuButton.Enabled ~= false then
				leaveAnimation:Play()
			end
		end))

	contextMenuButton:SetEnabled(true)
	return contextMenuButton
end

function ContextMenuButton.setIcon(contextMenuButton, newIcon)
	local iconObject = contextMenuButton.Instance:FindFirstChild("Icon")

	if iconObject and (iconObject:IsA("ImageLabel") or iconObject:IsA("ImageButton")) then
		iconObject.Image = newIcon or ""
	end

	return contextMenuButton
end

function ContextMenuButton.setText(contextMenuButton, newText)
	local label = contextMenuButton.Instance:FindFirstChild("Label")

	if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
		label.Text = tostring(newText or "")
	end

	if contextMenuButton.Menu then
		contextMenuButton.Menu:Recalculate()
	end

	return contextMenuButton
end

function ContextMenuButton.setCallback(contextMenuButton, callback)
	assert(callback == nil or type(callback) == "function", "ContextMenuButton callback must be a function or nil")
	contextMenuButton.Callback = callback
	return contextMenuButton
end

function ContextMenuButton.setEnabled(contextMenuButton, enabled)
	contextMenuButton.Enabled = enabled ~= false
	contextMenuButton.EnterAnimation:Cancel()
	contextMenuButton.LeaveAnimation:Cancel()
	ControlUtil.SetButtonEnabled(contextMenuButton.Instance, contextMenuButton.Enabled)

	if contextMenuButton.Enabled then
		contextMenuButton.LeaveAnimation:Play()
	end

	return contextMenuButton
end

function ContextMenuButton.destroy(contextMenuButton)
	ControlUtil.DisconnectAll(contextMenuButton.Connections)
	contextMenuButton.Connections = {}
	contextMenuButton.EnterAnimation:Cancel()
	contextMenuButton.LeaveAnimation:Cancel()
	contextMenuButton.Callback = nil
	contextMenuButton.Menu = nil

	if contextMenuButton.Instance then
		contextMenuButton.Instance:Destroy()
	end
end

function ContextMenu.new(contextMenuButtons)
	local instance = Assets.ContextMenu:Clone()
	instance.Parent = Storage
	instance.Visible = false
	Theme.Apply(instance)

	local contextMenu = {
		Buttons = {},
		Instance = instance,
		Visible = false,
	}

	contextMenu.Add = ContextMenu.add
	contextMenu.Clear = ContextMenu.clear
	contextMenu.Recalculate = ContextMenu.recalculate
	contextMenu.Show = ContextMenu.show
	contextMenu.Hide = ContextMenu.hide
	contextMenu.Destroy = ContextMenu.destroy

	for _, contextMenuButton in ipairs(contextMenuButtons or {}) do
		contextMenu:Add(contextMenuButton)
	end

	contextMenu:Recalculate()
	return contextMenu
end

function ContextMenu.add(contextMenu, contextMenuButton)
	assert(contextMenuButton and contextMenuButton.Instance, "ContextMenu:Add expects a ContextMenuButton")

	if contextMenuButton.Menu and contextMenuButton.Menu ~= contextMenu then
		error("ContextMenuButton is already attached to another menu", 2)
	end

	if table.find(contextMenu.Buttons, contextMenuButton) then
		return contextMenuButton
	end

	contextMenuButton.Menu = contextMenu
	contextMenuButton.Instance.LayoutOrder = #contextMenu.Buttons + 1
	contextMenuButton.Instance.Parent = contextMenu.Instance.List
	contextMenu.Buttons[#contextMenu.Buttons + 1] = contextMenuButton
	contextMenu:Recalculate()
	return contextMenuButton
end

function ContextMenu.clear(contextMenu, destroyButtons)
	for _, button in ipairs(contextMenu.Buttons) do
		button.Menu = nil

		if destroyButtons then
			button:Destroy()
		elseif button.Instance then
			button.Instance.Parent = nil
		end
	end

	contextMenu.Buttons = {}
	contextMenu:Recalculate()
end

function ContextMenu.recalculate(contextMenu)
	local width = 150
	local height = 0
	local rowHeight = Theme.Metrics.ControlHeight

	for _, contextMenuButton in ipairs(contextMenu.Buttons) do
		local buttonInstance = contextMenuButton.Instance
		local label = buttonInstance and buttonInstance:FindFirstChild("Label")

		if buttonInstance and buttonInstance.Parent and buttonInstance.Visible then
			local text = label and label.Text or ""
			local textWidth = TextService:GetTextSize(
				text,
				Theme.Typography.BodyTextSize,
				BODY_FONT,
				textConstraint
			).X
			local iconObject = buttonInstance:FindFirstChild("Icon")
			local iconWidth = iconObject and math.max(16, iconObject.AbsoluteSize.X) or 0

			width = math.max(width, iconWidth + textWidth + Theme.Metrics.Padding * 3)
			height = height + rowHeight
			buttonInstance.Size = UDim2.new(1, 0, 0, rowHeight)
		end
	end

	contextMenu.Instance.Size = UDim2.new(0, math.ceil(width), 0, math.max(1, height))
end

function ContextMenu.show(contextMenu, position)
	if currentContextMenu and currentContextMenu ~= contextMenu then
		currentContextMenu:Hide()
	end

	contextMenu:Recalculate()

	local instance = contextMenu.Instance
	local pointer = position and Vector2.new(position.X, position.Y) or ControlUtil.GetPointerPosition()
	local storagePosition = Storage:IsA("GuiObject") and Storage.AbsolutePosition or Vector2.new()
	local viewport = Storage:IsA("GuiObject") and Storage.AbsoluteSize or ControlUtil.GetScreenSize()

	if viewport.X <= 0 or viewport.Y <= 0 then
		viewport = ControlUtil.GetScreenSize()
	end
	local x, y = ControlUtil.ClampPopupPosition(
		pointer.X - storagePosition.X,
		pointer.Y - storagePosition.Y,
		instance.Size.X.Offset,
		instance.Size.Y.Offset,
		viewport.X,
		viewport.Y,
		Theme.Metrics.PopupMargin
	)

	instance.Position = UDim2.new(0, x, 0, y)
	instance.Visible = true
	contextMenu.Visible = true
	currentContextMenu = contextMenu

	for _, button in ipairs(contextMenu.Buttons) do
		if button.Enabled ~= false and button.Instance.Visible then
			ControlUtil.SetSelectedObject(button.Instance)
			break
		end
	end
end

function ContextMenu.hide(contextMenu)
	contextMenu.Visible = false

	if contextMenu.Instance then
		contextMenu.Instance.Visible = false
	end

	if currentContextMenu == contextMenu then
		currentContextMenu = nil
	end
end

function ContextMenu.destroy(contextMenu)
	contextMenu:Hide()
	contextMenu:Clear(false)

	if contextMenu.Instance then
		contextMenu.Instance:Destroy()
		contextMenu.Instance = nil
	end
end

ControlUtil.TrackConnection(UserInputService.InputBegan:Connect(function(input)
	if not currentContextMenu then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		hideCurrent()
	elseif ControlUtil.IsPrimaryPointer(input) then
		local point = ControlUtil.GetPointerPosition(input)

		if not ControlUtil.ContainsPoint(currentContextMenu.Instance, point) then
			hideCurrent()
		end
	end
end))

ControlUtil.TrackConnection(UserInputService.WindowFocusReleased:Connect(hideCurrent))

return ContextMenu, ContextMenuButton
