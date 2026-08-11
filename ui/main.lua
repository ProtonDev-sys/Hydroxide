local CoreGui = game:GetService("CoreGui")
local UserInput = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Interface = import("rbxassetid://11389137937")

if oh.Cache["ui/main"] then
	return Interface
end

local Base = Interface.Base
local Open = Interface.Open
local Drag = Base.Drag
local Status = Base.Status
local Collapse = Drag.Collapse

local FALLBACK_VIEWPORT = Vector2.new(1280, 720)
local MINIMUM_SIZE = Vector2.new(720, 480)
local MAXIMUM_SIZE = Vector2.new(1280, 760)
local VIEWPORT_MARGIN = 8

local function getViewport()
	local camera = workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or FALLBACK_VIEWPORT

	if viewport.X <= 0 or viewport.Y <= 0 then
		return FALLBACK_VIEWPORT
	end

	return viewport
end

local function getSizeBounds(viewport)
	local availableWidth = math.max(1, math.floor(viewport.X - VIEWPORT_MARGIN * 2))
	local availableHeight = math.max(1, math.floor(viewport.Y - VIEWPORT_MARGIN * 2))
	local maximumWidth = math.min(MAXIMUM_SIZE.X, availableWidth)
	local maximumHeight = math.min(MAXIMUM_SIZE.Y, availableHeight)
	local minimumWidth = math.min(MINIMUM_SIZE.X, maximumWidth)
	local minimumHeight = math.min(MINIMUM_SIZE.Y, maximumHeight)
	return minimumWidth, minimumHeight, maximumWidth, maximumHeight
end

local function clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

local initialViewport = getViewport()
local _, _, baseWidth, baseHeight = getSizeBounds(initialViewport)
local baseX = math.floor((initialViewport.X - baseWidth) / 2)
local baseY = math.floor((initialViewport.Y - baseHeight) / 2)

Base.Size = UDim2.new(0, baseWidth, 0, baseHeight)
Base.Position = UDim2.new(0, baseX, 0, baseY)
Base.Visible = true

if Interface:IsA("ScreenGui") then
	Interface.Enabled = true
end

Open.Position = UDim2.new(0.5, -15, 0, -75)

function oh.setStatus(text)
	Status.Text = "• Status: " .. text
end

function oh.getStatus()
	return Status.Text:gsub("• Status: ", "")
end

oh.setStatus("Starting capture backends ...")
Interface.Name = HttpService:GenerateGUID(false)

if getHui then
	Interface.Parent = getHui()
else
	if syn then
		syn.protect_gui(Interface)
	end

	Interface.Parent = CoreGui
end

-- Install traffic hooks before downloading the larger scanner/detail UI so
-- calls made during a cold first load are not silently missed.
for _, backend in ipairs({ "modules/RemoteSpy", "modules/RakNetSpy" }) do
	local loaded, loadError = pcall(import, backend)

	if not loaded and warn then
		warn(("Hydroxide %s could not start early: %s"):format(backend, tostring(loadError)))
	end
end

local initialized, initializationError = xpcall(function()
	oh.setStatus("Loading interface modules ...")

	if prefetch then
		local prefetched, prefetchErrors = prefetch({
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

		if not prefetched and warn then
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

	if not rakNetLoaded and warn then
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
	local viewportConnection

	local function trackConnection(connection)
		oh.Events[#oh.Events + 1] = connection
		return connection
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

	local function clampWindowToViewport()
		local viewport = getViewport()
		local minimumWidth, minimumHeight, maximumWidth, maximumHeight = getSizeBounds(viewport)
		local width = clamp(math.floor(windowSize.X), minimumWidth, maximumWidth)
		local height = clamp(math.floor(windowSize.Y), minimumHeight, maximumHeight)
		local maximumX = math.max(VIEWPORT_MARGIN, math.floor(viewport.X - VIEWPORT_MARGIN - width))
		local maximumY = math.max(VIEWPORT_MARGIN, math.floor(viewport.Y - VIEWPORT_MARGIN - height))

		windowSize = Vector2.new(width, height)
		windowPosition = Vector2.new(
			clamp(math.floor(windowPosition.X), VIEWPORT_MARGIN, maximumX),
			clamp(math.floor(windowPosition.Y), VIEWPORT_MARGIN, maximumY)
		)
		applyWindowLayout()
	end

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
		resizeHandle.Size = UDim2.new(0, 20, 0, 20)
		resizeHandle.Text = ""
		resizeHandle.ZIndex = 1000
		resizeHandle.Parent = Base

		for index = 1, 3 do
			local grip = Instance.new("Frame")
			grip.Name = "Grip" .. index
			grip.AnchorPoint = Vector2.new(1, 0.5)
			grip.BackgroundColor3 = Color3.fromRGB(145, 145, 145)
			grip.BackgroundTransparency = 0.15
			grip.BorderSizePixel = 0
			grip.Position = UDim2.new(1, -2, 1, -(index * 4 - 1))
			grip.Rotation = -45
			grip.Size = UDim2.new(0, index * 4 + 2, 0, 1)
			grip.ZIndex = resizeHandle.ZIndex + 1
			grip.Parent = resizeHandle
		end
	end

	local function beginGesture(kind, input)
		local inputType = input.UserInputType

		if
			activeGesture
			or not menuOpen
			or (inputType ~= Enum.UserInputType.MouseButton1 and inputType ~= Enum.UserInputType.Touch)
		then
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

		if activeGesture == "move" then
			local maximumX = math.max(VIEWPORT_MARGIN, viewport.X - VIEWPORT_MARGIN - windowSize.X)
			local maximumY = math.max(VIEWPORT_MARGIN, viewport.Y - VIEWPORT_MARGIN - windowSize.Y)
			windowPosition = Vector2.new(
				clamp(math.floor(gestureStartPosition.X + delta.X), VIEWPORT_MARGIN, maximumX),
				clamp(math.floor(gestureStartPosition.Y + delta.Y), VIEWPORT_MARGIN, maximumY)
			)
		elseif activeGesture == "resize" then
			local minimumWidth, minimumHeight, maximumWidth, maximumHeight = getSizeBounds(viewport)
			maximumWidth = math.min(maximumWidth, viewport.X - VIEWPORT_MARGIN - gestureStartPosition.X)
			maximumHeight = math.min(maximumHeight, viewport.Y - VIEWPORT_MARGIN - gestureStartPosition.Y)
			windowSize = Vector2.new(
				clamp(math.floor(gestureStartSize.X + delta.X), minimumWidth, maximumWidth),
				clamp(math.floor(gestureStartSize.Y + delta.Y), minimumHeight, maximumHeight)
			)
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
		clampWindowToViewport()
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

	trackConnection(workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport))
	bindViewport()

	Drag.Active = true
	trackConnection(Drag.InputBegan:Connect(function(input)
		beginGesture("move", input)
	end))
	trackConnection(resizeHandle.InputBegan:Connect(function(input)
		beginGesture("resize", input)
	end))
	oh.Events.Drag = UserInput.InputChanged:Connect(updateGesture)
	trackConnection(UserInput.InputEnded:Connect(finishGesture))
	trackConnection(UserInput.WindowFocusReleased:Connect(cancelGesture))

	trackConnection(Open.MouseButton1Click:Connect(function()
		cancelGesture()
		menuOpen = true
		Open:TweenPosition(constants.conceal, "Out", "Quad", 0.15, true)
		Base:TweenPosition(constants.opened, "Out", "Quad", 0.15, true)
	end))

	trackConnection(Collapse.MouseButton1Click:Connect(function()
		cancelGesture()
		menuOpen = false
		Base:TweenPosition(constants.closed, "Out", "Quad", 0.15, true)
		Open:TweenPosition(constants.reveal, "Out", "Quad", 0.15, true)
	end))

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

	if warn then
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
