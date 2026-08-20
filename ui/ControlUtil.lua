local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local Theme = (oh and oh.Theme) or import("ui/Theme")

local ControlUtil = {}
local visualStates = setmetatable({}, { __mode = "k" })

local function warnFailure(context, message)
	if type(warn) == "function" then
		warn(("[Hydroxide] %s: %s"):format(context, tostring(message)))
	end
end

function ControlUtil.TrackConnection(connection)
	if connection and oh and oh.Events then
		oh.Events[#oh.Events + 1] = connection
	end

	return connection
end

function ControlUtil.DisconnectAll(connections)
	local pending = {}

	for key, connection in pairs(connections or {}) do
		pending[#pending + 1] = { key, connection }
	end

	for _, entry in ipairs(pending) do
		local key = entry[1]
		local connection = entry[2]

		if connection and connection.Disconnect then
			pcall(function()
				connection:Disconnect()
			end)
		elseif type(connection) == "table" then
			ControlUtil.DisconnectAll(connection)
		end

		connections[key] = nil
	end
end

function ControlUtil.RunCallback(context, callback, ...)
	if type(callback) ~= "function" then
		return true
	end

	local ok, result = pcall(callback, ...)

	if not ok then
		warnFailure(context or "UI callback failed", result)
	end

	return ok, result
end

function ControlUtil.ConnectActivated(button, callback)
	assert(button and button:IsA("GuiButton"), "ConnectActivated expects a GuiButton")
	button.Active = true
	button.Selectable = true

	local signal
	local hasActivated = pcall(function()
		signal = button.Activated
	end)

	if not hasActivated or signal == nil then
		signal = button.MouseButton1Click
	end

	return ControlUtil.TrackConnection(signal:Connect(callback))
end

function ControlUtil.ConnectSecondary(button, callback)
	assert(button and button:IsA("GuiButton"), "ConnectSecondary expects a GuiButton")
	button.Active = true
	button.Selectable = true

	local signal
	local hasSecondary = pcall(function()
		signal = button.SecondaryActivated
	end)

	if not hasSecondary or signal == nil then
		signal = button.MouseButton2Click
	end

	return ControlUtil.TrackConnection(signal:Connect(callback))
end

function ControlUtil.IsPrimaryPointer(input)
	return input
		and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
end

function ControlUtil.GetPointerPosition(input)
	if input and input.Position then
		return Vector2.new(input.Position.X, input.Position.Y)
	end

	local ok, position = pcall(UserInputService.GetMouseLocation, UserInputService)

	if ok and position then
		return position
	end

	return Vector2.new()
end

function ControlUtil.ContainsPoint(object, point)
	if not object or not point or not object:IsA("GuiObject") or not object.Visible then
		return false
	end

	local position = object.AbsolutePosition
	local size = object.AbsoluteSize

	return point.X >= position.X
		and point.X <= position.X + size.X
		and point.Y >= position.Y
		and point.Y <= position.Y + size.Y
end

function ControlUtil.GetScreenSize()
	local camera = workspace and workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize

	if viewport and viewport.X > 0 and viewport.Y > 0 then
		return viewport
	end

	return Vector2.new(1280, 720)
end

function ControlUtil.GetViewportSize(object)
	local ancestor = object
	local largest = Vector2.new()

	while ancestor do
		if ancestor:IsA("GuiObject") then
			local size = ancestor.AbsoluteSize

			if size.X * size.Y > largest.X * largest.Y then
				largest = size
			end
		end

		ancestor = ancestor.Parent
	end

	if largest.X > 0 and largest.Y > 0 then
		return largest
	end

	return ControlUtil.GetScreenSize()
end

function ControlUtil.ClampPopupPosition(x, y, width, height, viewportWidth, viewportHeight, margin)
	margin = math.max(0, tonumber(margin) or Theme.Metrics.PopupMargin)
	viewportWidth = math.max(1, tonumber(viewportWidth) or 1)
	viewportHeight = math.max(1, tonumber(viewportHeight) or 1)
	width = math.max(0, tonumber(width) or 0)
	height = math.max(0, tonumber(height) or 0)

	local maximumX = math.max(margin, viewportWidth - margin - width)
	local maximumY = math.max(margin, viewportHeight - margin - height)

	return math.max(margin, math.min(maximumX, tonumber(x) or margin)),
		math.max(margin, math.min(maximumY, tonumber(y) or margin))
end

function ControlUtil.IsReducedMotion()
	local ok, reduced = pcall(function()
		return GuiService.ReducedMotionEnabled
	end)

	return ok and reduced == true
end

function ControlUtil.MotionDuration(duration)
	return ControlUtil.IsReducedMotion() and 0 or math.max(0, tonumber(duration) or 0)
end

function ControlUtil.SetSelectedObject(object)
	if object and object:IsA("GuiObject") and object.Visible and object.Selectable then
		pcall(function()
			GuiService.SelectedObject = object
		end)
	end
end

local function setVisualEnabled(object, property, enabled)
	local state = visualStates[object]

	if enabled then
		if state and state[property] ~= nil then
			object[property] = state[property]
			state[property] = nil
		end
	else
		state = state or {}
		visualStates[object] = state

		if state[property] == nil then
			state[property] = object[property]
		end

		object[property] = math.max(state[property], 0.55)
	end
end

function ControlUtil.SetButtonEnabled(button, enabled)
	enabled = enabled ~= false
	button.Active = enabled
	button.Selectable = enabled

	pcall(function()
		button.AutoButtonColor = enabled
	end)

	if button:IsA("ImageButton") then
		setVisualEnabled(button, "ImageTransparency", enabled)
	elseif button:IsA("TextButton") then
		setVisualEnabled(button, "TextTransparency", enabled)
	end

	for _, descendant in ipairs(button:GetDescendants()) do
		if descendant:IsA("ImageLabel") or descendant:IsA("ImageButton") then
			setVisualEnabled(descendant, "ImageTransparency", enabled)
		elseif descendant:IsA("TextLabel") or descendant:IsA("TextButton") then
			setVisualEnabled(descendant, "TextTransparency", enabled)
		end
	end
end

return ControlUtil
