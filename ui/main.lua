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

local function calculateBaseSize()
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)

	if viewport.X <= 0 or viewport.Y <= 0 then
		viewport = Vector2.new(1280, 720)
	end

	local horizontalMargin = math.min(32, math.max(8, math.floor(viewport.X * 0.03)))
	local verticalMargin = math.min(56, math.max(8, math.floor(viewport.Y * 0.05)))
	local width = math.floor(math.max(1, math.min(1280, viewport.X - horizontalMargin)))
	local height = math.floor(math.max(1, math.min(760, viewport.Y - verticalMargin)))
	return width, height
end

local baseWidth, baseHeight = calculateBaseSize()

Base.Size = UDim2.new(0, baseWidth, 0, baseHeight)
Base.Position = UDim2.new(0.5, -baseWidth / 2, 0.5, -baseHeight / 2)
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
	local dragging
	local dragStart
	local startPos
	local viewportConnection

	local function updateLayout()
		baseWidth, baseHeight = calculateBaseSize()
		Base.Size = UDim2.new(0, baseWidth, 0, baseHeight)
		constants.opened = UDim2.new(0.5, -baseWidth / 2, 0.5, -baseHeight / 2)
		constants.closed = UDim2.new(0.5, -baseWidth / 2, 0, -(baseHeight + 50))
		constants.reveal = UDim2.new(0.5, -15, 0, 20)
		constants.conceal = UDim2.new(0.5, -15, 0, -75)
		dragging = false
		Base:TweenPosition(menuOpen and constants.opened or constants.closed, "Out", "Quad", 0, true)
		Open:TweenPosition(menuOpen and constants.conceal or constants.reveal, "Out", "Quad", 0, true)
	end

	local function bindViewport()
		if viewportConnection then
			viewportConnection:Disconnect()
			viewportConnection = nil
		end

		local camera = workspace.CurrentCamera

		if camera then
			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateLayout)
			oh.Events[#oh.Events + 1] = viewportConnection
		end

		updateLayout()
	end

	oh.Events[#oh.Events + 1] = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bindViewport)
	bindViewport()

	Drag.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			local dragEnded

			dragging = true
			dragStart = input.Position
			startPos = Base.Position

			dragEnded = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					dragEnded:Disconnect()
				end
			end)
		end
	end)

	oh.Events.Drag = UserInput.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement and dragging then
			local delta = input.Position - dragStart
			Base.Position =
				UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
		end
	end)

	Open.MouseButton1Click:Connect(function()
		menuOpen = true
		Open:TweenPosition(constants.conceal, "Out", "Quad", 0.15, true)
		Base:TweenPosition(constants.opened, "Out", "Quad", 0.15, true)
	end)

	Collapse.MouseButton1Click:Connect(function()
		menuOpen = false
		Base:TweenPosition(constants.closed, "Out", "Quad", 0.15, true)
		Open:TweenPosition(constants.reveal, "Out", "Quad", 0.15, true)
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
