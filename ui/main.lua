local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local Interface = import("rbxassetid://11389137937")

if oh.Cache["ui/main"] then
	return Interface
end

local Layout = import("ui/Layout")
local Theme = import("ui/Theme")
oh.Theme = Theme

local ControlUtil = import("ui/ControlUtil")
local Base = Interface.Base
local Open = Interface.Open
local Drag = Base.Drag
local Status = Base.Status
local Collapse = Drag.Collapse

local FALLBACK_VIEWPORT = Vector2.new(Layout.ReferenceViewportWidth, Layout.ReferenceViewportHeight)

local function getViewport()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or FALLBACK_VIEWPORT

	if viewport.X <= 0 or viewport.Y <= 0 then
		return FALLBACK_VIEWPORT
	end

	return viewport
end

local function parentInterface()
	local methods = (oh and oh.Methods) or {}
	local getHiddenUi = methods.gethui or methods.getHui

	if type(getHiddenUi) == "function" then
		local ok, parent = pcall(getHiddenUi)

		if ok and typeof(parent) == "Instance" then
			Interface.Parent = parent
			return
		end
	end

	if syn and type(syn.protect_gui) == "function" then
		pcall(syn.protect_gui, Interface)
	end

	Interface.Parent = CoreGui
end

local initialViewport = getViewport()
local baseWidth, baseHeight = Layout.GetDefaultSize(initialViewport.X, initialViewport.Y)
local baseX, baseY = Layout.GetCenteredPosition(initialViewport.X, initialViewport.Y, baseWidth, baseHeight)
baseX, baseY = Layout.ClampPosition(initialViewport.X, initialViewport.Y, baseWidth, baseHeight, baseX, baseY)

Theme.Apply(Interface)
oh.Events.Theme = ControlUtil.TrackConnection(Interface.DescendantAdded:Connect(Theme.ApplyObject))

Base.Size = UDim2.new(0, baseWidth, 0, baseHeight)
Base.Position = UDim2.new(0, baseX, 0, baseY)
Base.Visible = true

if Interface:IsA("ScreenGui") then
	Interface.Enabled = true
end

Open.Position = UDim2.new(0.5, -15, 0, -75)

function oh.setStatus(text)
	Status.Text = "• Status: " .. tostring(text or "")
end

function oh.getStatus()
	return Status.Text:gsub("• Status: ", "")
end

oh.setStatus("Starting capture backends ...")
Interface.Name = HttpService:GenerateGUID(false)
parentInterface()

-- Install traffic hooks before downloading the larger scanner/detail UI so
-- calls made during a cold first load are not silently missed.
for _, backend in ipairs({ "modules/RemoteSpy", "modules/RakNetSpy" }) do
	local loaded, loadError = pcall(import, backend)

	if not loaded and type(warn) == "function" then
		warn(("Hydroxide %s could not start early: %s"):format(backend, tostring(loadError)))
	end
end

local initialized, initializationError = xpcall(function()
	oh.setStatus("Loading interface modules ...")

	if prefetch then
		local prefetched, prefetchErrors = prefetch({
			"ui/ControlUtil",
			"ui/controls/TabSelector",
			"ui/controls/MessageBox",
			"ui/controls/Prompt",
			"ui/controls/CheckBox",
			"ui/controls/Dropdown",
			"ui/controls/List",
			"ui/controls/ContextMenu",
			"ui/controls/TextViewer",
			"ui/controls/FunctionInspector",
			"ui/controls/ActionPanel",
			"ui/modules/RemoteSpy",
			"ui/modules/RakNetSpy",
			"ui/modules/ClosureSpy",
			"ui/modules/ScriptScanner",
			"ui/modules/ModuleScanner",
			"ui/modules/UpvalueScanner",
			"ui/modules/ConstantScanner",
			"modules/RemoteSpy",
			"modules/RakNetSpy",
			"modules/ClosureSpy",
			"modules/ScriptScanner",
			"modules/ModuleScanner",
			"modules/UpvalueScanner",
			"modules/ConstantScanner",
			"objects/Remote",
			"objects/Closure",
			"objects/LocalScript",
			"objects/ModuleScript",
			"objects/Upvalue",
			"objects/Constant",
			"methods/scriptbuilder",
		})

		if not prefetched and type(warn) == "function" then
			warn("Hydroxide prefetch completed with errors:\n" .. table.concat(prefetchErrors, "\n"))
		end
	end

	import("ui/controls/TabSelector")
	import("ui/controls/MessageBox")
	import("ui/modules/RemoteSpy")
	import("ui/modules/ClosureSpy")
	import("ui/modules/ScriptScanner")
	import("ui/modules/ModuleScanner")
	import("ui/modules/UpvalueScanner")
	import("ui/modules/ConstantScanner")

	local rakNetLoaded, rakNetError = pcall(function()
		import("ui/modules/RakNetSpy")
	end)

	if not rakNetLoaded and type(warn) == "function" then
		warn("Hydroxide RakNet Spy could not be initialized; core tools remain available:\n" .. tostring(rakNetError))
	end

	local constants = {}
	local menuOpen = true
	local activeGesture
	local activePointer
	local gestureStart
	local gestureStartPosition
	local gestureStartSize
	local windowPosition = Vector2.new(baseX, baseY)
	local windowSize = Vector2.new(baseWidth, baseHeight)
	local relativeWindowSize = Vector2.new(1, 1)
	local lastViewport = initialViewport
	local viewportConnection
	local lastTitleTapAt = 0
	local lastTitleTapPosition
	local DOUBLE_TAP_WINDOW = 0.35
	local DOUBLE_TAP_DISTANCE = 12

	local function trackConnection(connection)
		return ControlUtil.TrackConnection(connection)
	end

	local function cancelGesture()
		activeGesture = nil
		activePointer = nil
		gestureStart = nil
		gestureStartPosition = nil
		gestureStartSize = nil
	end

	local function updateConstants()
		constants.opened = UDim2.new(0, windowPosition.X, 0, windowPosition.Y)
		constants.closed = UDim2.new(0, windowPosition.X, 0, -(windowSize.Y + 50))
		constants.reveal = UDim2.new(0.5, -15, 0, 20)
		constants.conceal = UDim2.new(0.5, -15, 0, -75)
	end

	local function applyWindowLayout()
		updateConstants()
		Base.Size = UDim2.new(0, windowSize.X, 0, windowSize.Y)
		Base.Position = menuOpen and constants.opened or constants.closed
		Open.Position = menuOpen and constants.conceal or constants.reveal
	end

	local function clampWindowPosition(viewport)
		local x, y = Layout.ClampPosition(
			viewport.X,
			viewport.Y,
			windowSize.X,
			windowSize.Y,
			windowPosition.X,
			windowPosition.Y
		)
		windowPosition = Vector2.new(x, y)
	end

	local function fitWindowToViewport()
		local viewport = getViewport()
		local positionX, positionY, width, height

		if viewport.X ~= lastViewport.X or viewport.Y ~= lastViewport.Y then
			local defaultWidth, defaultHeight = Layout.GetDefaultSize(viewport.X, viewport.Y)
			positionX, positionY, width, height = Layout.ScaleWindow(
				lastViewport.X,
				lastViewport.Y,
				viewport.X,
				viewport.Y,
				windowPosition.X,
				windowPosition.Y,
				windowSize.X,
				windowSize.Y,
				defaultWidth * relativeWindowSize.X,
				defaultHeight * relativeWindowSize.Y
			)
			windowPosition = Vector2.new(positionX, positionY)
			lastViewport = viewport
		else
			width, height = Layout.FitSize(viewport.X, viewport.Y, windowSize.X, windowSize.Y)
		end

		windowSize = Vector2.new(width, height)
		clampWindowPosition(viewport)
		applyWindowLayout()
	end

	local function resetWindow()
		cancelGesture()
		local viewport = getViewport()
		local width, height = Layout.GetDefaultSize(viewport.X, viewport.Y)
		local x, y = Layout.GetCenteredPosition(viewport.X, viewport.Y, width, height)
		x, y = Layout.ClampPosition(viewport.X, viewport.Y, width, height, x, y)
		windowPosition = Vector2.new(x, y)
		windowSize = Vector2.new(width, height)
		relativeWindowSize = Vector2.new(1, 1)
		lastViewport = viewport
		applyWindowLayout()
	end

	oh.resetWindow = resetWindow

	local resizeHandle = Base:FindFirstChild("HydroxideResizeHandle")

	if not resizeHandle then
		resizeHandle = Instance.new("TextButton")
		resizeHandle.Name = "HydroxideResizeHandle"
		resizeHandle.Active = true
		resizeHandle.AnchorPoint = Vector2.new(1, 1)
		resizeHandle.AutoButtonColor = false
		resizeHandle.BackgroundTransparency = 1
		resizeHandle.BorderSizePixel = 0
		resizeHandle.Position = UDim2.new(1, -2, 1, -2)
		resizeHandle.Size = UDim2.new(0, Theme.Metrics.MinimumHitSize, 0, Theme.Metrics.MinimumHitSize)
		resizeHandle.Text = ""
		resizeHandle.ZIndex = 1000
		resizeHandle.Parent = Base

		for index = 1, 3 do
			local grip = Instance.new("Frame")
			grip.Name = "Grip" .. index
			grip.AnchorPoint = Vector2.new(1, 0.5)
			grip.BackgroundColor3 = Theme.Colors.ResizeGrip
			grip.BackgroundTransparency = 0.15
			grip.BorderSizePixel = 0
			grip.Position = UDim2.new(1, -3, 1, -(index * 4))
			grip.Rotation = -45
			grip.Size = UDim2.new(0, index * 4 + 2, 0, 1)
			grip.ZIndex = resizeHandle.ZIndex + 1
			grip.Parent = resizeHandle
		end
	end

	local function beginGesture(kind, input)
		if activeGesture or not menuOpen or not ControlUtil.IsPrimaryPointer(input) then
			return
		end

		activeGesture = kind
		activePointer = input
		gestureStart = input.Position
		gestureStartPosition = windowPosition
		gestureStartSize = windowSize
	end

	local function inputMatchesGesture(input)
		if not activePointer then
			return false
		elseif activePointer.UserInputType == Enum.UserInputType.Touch then
			return input == activePointer
		end

		return input.UserInputType == Enum.UserInputType.MouseMovement
	end

	local function updateGesture(input)
		if not activeGesture or not inputMatchesGesture(input) then
			return
		end

		local delta = input.Position - gestureStart
		local viewport = getViewport()

		if delta.Magnitude > 8 then
			lastTitleTapAt = 0
		end

		if activeGesture == "move" then
			local positionX, positionY = Layout.GetDraggedPosition(
				gestureStartPosition.X,
				gestureStartPosition.Y,
				delta.X,
				delta.Y,
				viewport.X,
				viewport.Y,
				windowSize.X,
				windowSize.Y
			)
			windowPosition = Vector2.new(positionX, positionY)
		elseif activeGesture == "resize" then
			local width, height = Layout.FitSize(
				viewport.X,
				viewport.Y,
				gestureStartSize.X + delta.X,
				gestureStartSize.Y + delta.Y
			)
			windowSize = Vector2.new(width, height)
			clampWindowPosition(viewport)

			local defaultWidth, defaultHeight = Layout.GetDefaultSize(viewport.X, viewport.Y)
			relativeWindowSize = Vector2.new(width / defaultWidth, height / defaultHeight)
		end

		applyWindowLayout()
	end

	local function finishGesture(input)
		if not activePointer then
			return
		elseif activePointer.UserInputType == Enum.UserInputType.Touch then
			if input ~= activePointer then
				return
			end
		elseif input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end

		cancelGesture()
	end

	local function updateLayout()
		cancelGesture()
		fitWindowToViewport()
	end

	local function bindViewport()
		if viewportConnection then
			viewportConnection:Disconnect()
			viewportConnection = nil
		end

		local camera = workspace.CurrentCamera

		if camera then
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateLayout)
			trackConnection(viewportConnection)
		end

		updateLayout()
	end

	local function tweenPosition(object, target)
		local duration = ControlUtil.MotionDuration(Theme.Motion.Normal)

		if duration <= 0 then
			object.Position = target
		else
			object:TweenPosition(target, Enum.EasingDirection.Out, Enum.EasingStyle.Quad, duration, true)
		end
	end

	trackConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport))
	bindViewport()

	Drag.Active = true
	trackConnection(Drag.InputBegan:Connect(function(input)
		if ControlUtil.IsPrimaryPointer(input) then
			local now = os.clock()
			local point = Vector2.new(input.Position.X, input.Position.Y)

			if ControlUtil.ContainsPoint(Collapse, point) then
				return
			end

			if lastTitleTapPosition
				and now - lastTitleTapAt <= DOUBLE_TAP_WINDOW
				and (point - lastTitleTapPosition).Magnitude <= DOUBLE_TAP_DISTANCE
			then
				lastTitleTapAt = 0
				lastTitleTapPosition = nil
				resetWindow()
				return
			end

			lastTitleTapAt = now
			lastTitleTapPosition = point
		end

		beginGesture("move", input)
	end))
	trackConnection(resizeHandle.InputBegan:Connect(function(input)
		beginGesture("resize", input)
	end))
	oh.Events.Drag = trackConnection(UserInputService.InputChanged:Connect(updateGesture))
	trackConnection(UserInputService.InputEnded:Connect(finishGesture))
	trackConnection(UserInputService.WindowFocusReleased:Connect(cancelGesture))

	ControlUtil.ConnectActivated(Open, function()
		cancelGesture()
		menuOpen = true
		clampWindowPosition(getViewport())
		updateConstants()
		tweenPosition(Open, constants.conceal)
		tweenPosition(Base, constants.opened)
	end)

	ControlUtil.ConnectActivated(Collapse, function()
		cancelGesture()
		menuOpen = false
		updateConstants()
		tweenPosition(Base, constants.closed)
		tweenPosition(Open, constants.reveal)
	end)

	oh.setStatus("Ready")
end, function(err)
	return tostring(err)
end)

if not initialized then
	local message

	if initializationError:find("valid member", 1, true) then
		message = "The Hydroxide UI asset is incompatible. Rejoin and restart; if this repeats, report it at https://github.com/ProtonDev-sys/Hydroxide/issues.\n\n"
			.. initializationError
	else
		message = "Hydroxide UI startup failed; all installed hooks are being removed. Report this at https://github.com/ProtonDev-sys/Hydroxide/issues.\n\n"
			.. initializationError
	end

	if type(warn) == "function" then
		warn(message)
	end

	local runtime = oh

	if runtime and type(runtime.Exit) == "function" then
		pcall(runtime.Exit)
	else
		pcall(function()
			Interface:Destroy()
		end)
	end

	error(message, 0)
end

return Interface
