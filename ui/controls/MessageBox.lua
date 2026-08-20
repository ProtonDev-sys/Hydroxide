local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local ControlUtil = import("ui/ControlUtil")
local Theme = (oh and oh.Theme) or import("ui/Theme")

local Interface = import("rbxassetid://11389137937")
local Base = Interface.Base
local Object = Base.MessageBox
local Shadow = Base.MessageBoxShadow

local MessageBox = {}
local MessageType = {
	OK = 1,
	OKCancel = 2,
	YesNo = 3,
}

local activeDialog
local buttonConnections = {}
local TEXT_SIZE = Theme.Typography.BodyTextSize
local DYNAMIC_TEXT_BOUNDS = Vector2.new(100000, 100000)

local function disconnectButtons()
	ControlUtil.DisconnectAll(buttonConnections)
	buttonConnections = {}
end

local function hideButtonGroups(buttons)
	for _, child in ipairs(buttons:GetChildren()) do
		if child:IsA("GuiObject") then
			child.Visible = false
		end
	end
end

local function layoutButtons(group, first, second)
	if not group or not first then
		return
	end

	local height = Theme.Metrics.ControlHeight
	local gap = Theme.Metrics.Gap
	local width = 96

	group.AnchorPoint = Vector2.new(0, 0)
	group.Position = UDim2.new(0, Theme.Metrics.Padding, 1, -(height + Theme.Metrics.Padding))
	group.Size = UDim2.new(1, -(Theme.Metrics.Padding * 2), 0, height)

	first.AnchorPoint = Vector2.new(0, 0)
	first.Size = UDim2.new(0, width, 0, height)
	first.Selectable = true

	if second then
		second.AnchorPoint = Vector2.new(0, 0)
		second.Size = UDim2.new(0, width, 0, height)
		second.Position = UDim2.new(0.5, gap / 2, 0, 0)
		second.Selectable = true
		first.Position = UDim2.new(0.5, -(width + gap / 2), 0, 0)
	else
		first.Position = UDim2.new(0.5, -(width / 2), 0, 0)
	end
end

local function resolveButtons(buttons, messageType)
	if messageType == MessageType.OK then
		return buttons.OK, buttons.OK and buttons.OK.OK, nil
	elseif messageType == MessageType.OKCancel then
		return buttons.OKCancel, buttons.OKCancel and buttons.OKCancel.OK, buttons.OKCancel and buttons.OKCancel.Cancel
	elseif messageType == MessageType.YesNo then
		return buttons.YesNo, buttons.YesNo and buttons.YesNo.Yes, buttons.YesNo and buttons.YesNo.No
	end
end

local function calculateDialogSize(title, message)
	local viewport = ControlUtil.GetViewportSize(Base)
	local maximumWidth = math.max(240, math.min(560, viewport.X - Theme.Metrics.PopupMargin * 4))
	local minimumWidth = math.min(340, maximumWidth)
	local titleWidth = TextService:GetTextSize(title, TEXT_SIZE, Enum.Font.SourceSans, DYNAMIC_TEXT_BOUNDS).X
	local bodyWidth = TextService:GetTextSize(message, TEXT_SIZE, Enum.Font.SourceSans, DYNAMIC_TEXT_BOUNDS).X
	local width = math.max(minimumWidth, math.min(maximumWidth, math.max(titleWidth + 40, bodyWidth + 48)))
	local bodyBounds = TextService:GetTextSize(
		message,
		TEXT_SIZE,
		Enum.Font.SourceSans,
		Vector2.new(math.max(1, width - 32), 100000)
	)
	local maximumHeight = math.max(160, viewport.Y - Theme.Metrics.PopupMargin * 4)
	local height = math.max(150, math.min(maximumHeight, bodyBounds.Y + 104))

	return math.floor(width + 0.5), math.floor(height + 0.5), bodyBounds.Y + 104 > maximumHeight
end

local function complete(callback)
	MessageBox.Hide()
	ControlUtil.RunCallback("Message box callback failed", callback)
end

function MessageBox.Show(title, message, messageType, firstCallback, secondCallback)
	title = tostring(title or "Hydroxide")
	message = tostring(message or "")
	messageType = messageType or MessageType.OK

	disconnectButtons()

	local inner = Object:FindFirstChild("Inner")
	local buttons = inner and inner:FindFirstChild("Buttons")
	local messageLabel = inner and inner:FindFirstChild("Message")
	local titleLabel = Object:FindFirstChild("Title")
	assert(inner and buttons and messageLabel and titleLabel, "MessageBox asset is incomplete")

	hideButtonGroups(buttons)
	local group, first, second = resolveButtons(buttons, messageType)

	if not group or not first then
		return false
	end

	local width, height, truncated = calculateDialogSize(title, message)
	titleLabel.Text = title
	messageLabel.Text = message
	messageLabel.TextWrapped = true
	messageLabel.TextTruncate = truncated and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None
	messageLabel.TextYAlignment = Enum.TextYAlignment.Top

	Object.Size = UDim2.new(0, width, 0, height)
	Object.Position = UDim2.new(0.5, -(width / 2), 0.5, -(height / 2))
	layoutButtons(group, first, second)

	buttonConnections[#buttonConnections + 1] = ControlUtil.ConnectActivated(first, function()
		complete(firstCallback)
	end)

	if second then
		buttonConnections[#buttonConnections + 1] = ControlUtil.ConnectActivated(second, function()
			complete(secondCallback)
		end)
	end

	activeDialog = {
		First = first,
		FirstCallback = firstCallback,
		Second = second,
		SecondCallback = secondCallback,
	}

	Theme.Apply(Object)
	group.Visible = true
	Shadow.Visible = true
	Object.Visible = true
	ControlUtil.SetSelectedObject(first)
	return true
end

function MessageBox.Hide()
	disconnectButtons()
	activeDialog = nil
	Shadow.Visible = false
	Object.Visible = false
	hideButtonGroups(Object.Inner.Buttons)
end

function MessageBox.IsVisible()
	return activeDialog ~= nil and Object.Visible
end

ControlUtil.TrackConnection(UserInputService.InputBegan:Connect(function(input, processed)
	if processed or not activeDialog then
		return
	end

	if input.KeyCode == Enum.KeyCode.Escape then
		complete(activeDialog.SecondCallback)
	elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
		complete(activeDialog.FirstCallback)
	end
end))

return MessageBox, MessageType
