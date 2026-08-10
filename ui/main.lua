local CoreGui = game:GetService("CoreGui")
local UserInput = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Interface = import("rbxassetid://11389137937")

if oh.Cache["ui/main"] then
	return Interface
end

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
		"ui/controls/InlineViewer",
		"ui/controls/ActionPanel",
		"ui/modules/RemoteSpy",
		"ui/modules/ClosureSpy",
		"ui/modules/ScriptScanner",
		"ui/modules/ModuleScanner",
		"ui/modules/UpvalueScanner",
		"ui/modules/ConstantScanner",
		"modules/RemoteSpy",
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
local MessageBox, MessageType = import("ui/controls/MessageBox")
local Base = Interface.Base
local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
local baseWidth = math.floor(math.max(480, math.min(1280, viewport.X - 32)))
local baseHeight = math.floor(math.max(350, math.min(760, viewport.Y - 56)))

Base.Size = UDim2.new(0, baseWidth, 0, baseHeight)

local RemoteSpy
local ClosureSpy
local ScriptScanner
local ModuleScanner
local UpvalueScanner
local ConstantScanner

xpcall(function()
	RemoteSpy = import("ui/modules/RemoteSpy")
	ClosureSpy = import("ui/modules/ClosureSpy")
	ScriptScanner = import("ui/modules/ScriptScanner")
	ModuleScanner = import("ui/modules/ModuleScanner")
	UpvalueScanner = import("ui/modules/UpvalueScanner")
	ConstantScanner = import("ui/modules/ConstantScanner")
end, function(err)
	err = tostring(err)
	local message
	if err:find("valid member") then
		message = "The UI asset changed. Rejoin and restart Hydroxide. If this repeats, report it at https://github.com/ProtonDev-sys/Hydroxide/issues.\n\n"
			.. err
	else
		message = "Report this error at https://github.com/ProtonDev-sys/Hydroxide/issues:\n\n" .. err
	end

	MessageBox.Show("An error has occurred", message, MessageType.OK, function()
		Interface:Destroy()
	end)
end)

local constants = {
	opened = UDim2.new(0.5, -baseWidth / 2, 0.5, -baseHeight / 2),
	closed = UDim2.new(0.5, -baseWidth / 2, 0, -(baseHeight + 50)),
	reveal = UDim2.new(0.5, -15, 0, 20),
	conceal = UDim2.new(0.5, -15, 0, -75),
}

local Open = Interface.Open
local Drag = Base.Drag
local Status = Base.Status
local Collapse = Drag.Collapse

Base.Position = constants.closed

function oh.setStatus(text)
	Status.Text = "• Status: " .. text
end

function oh.getStatus()
	return Status.Text:gsub("• Status: ", "")
end

local dragging
local dragStart
local startPos

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
	Open:TweenPosition(constants.conceal, "Out", "Quad", 0.15)
	Base:TweenPosition(constants.opened, "Out", "Quad", 0.15)
end)

Collapse.MouseButton1Click:Connect(function()
	Base:TweenPosition(constants.closed, "Out", "Quad", 0.15)
	Open:TweenPosition(constants.reveal, "Out", "Quad", 0.15)
end)

Interface.Name = HttpService:GenerateGUID(false)
if getHui then
	Interface.Parent = getHui()
else
	if syn then
		syn.protect_gui(Interface)
	end

	Interface.Parent = CoreGui
end

return Interface
