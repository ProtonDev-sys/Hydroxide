local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function assertTrue(value, label)
	if not value then
		error(label .. ": expected truthy value", 2)
	end
end

local function readFile(path)
	local file = assert(io.open(path, "rb"))
	local contents = file:read("*a")
	file:close()
	return contents
end

local Layout = assert(loadfile("ui/Layout.lua"))()

local width, height = Layout.GetDefaultSize(1280, 720)
assertEqual(width, 680, "reference viewport compact width")
assertEqual(height, 380, "reference viewport compact height")
assertTrue(width < 1280 - 16 and height < 720 - 16, "reference window leaves useful screen space")

local smallerWidth, smallerHeight = Layout.GetDefaultSize(1024, 576)
assertEqual(smallerWidth, 544, "smaller viewport scales width")
assertEqual(smallerHeight, 304, "smaller viewport scales height")

local largerWidth, largerHeight = Layout.GetDefaultSize(1920, 1080)
assertEqual(largerWidth, 840, "larger viewport respects width cap")
assertEqual(largerHeight, 500, "larger viewport respects height cap")
assertTrue(largerWidth > width and largerHeight > height, "larger viewport grows window")

local phoneWidth, phoneHeight = Layout.GetDefaultSize(480, 270)
assertEqual(phoneWidth, 464, "narrow viewport fits width")
assertEqual(phoneHeight, 254, "short viewport fits height")

local studioPhoneWidth, studioPhoneHeight = Layout.GetDefaultSize(749, 361)
assertEqual(studioPhoneWidth, 500, "Studio iPhone safe viewport uses readable compact width")
assertEqual(studioPhoneHeight, 280, "Studio iPhone safe viewport uses readable compact height")

local legacyDraggedX, legacyDraggedY = Layout.GetDraggedPosition(100, 50, -1000, 900)
assertEqual(legacyDraggedX, -900, "legacy drag calculation remains available")
assertEqual(legacyDraggedY, 950, "legacy drag calculation remains available vertically")

local draggedX, draggedY = Layout.GetDraggedPosition(100, 50, -1000, 900, 1280, 720, 680, 380)
assertEqual(draggedX, -552, "drag keeps a recoverable horizontal strip visible")
assertEqual(draggedY, 680, "drag keeps the title bar recoverable")

local clampedX, clampedY = Layout.ClampPosition(480, 270, phoneWidth, phoneHeight, 900, -500)
assertEqual(clampedX, 352, "position clamp preserves a visible right-side strip")
assertEqual(clampedY, 8, "position clamp keeps the title bar below the viewport margin")

local scaledX, scaledY, scaledWidth, scaledHeight = Layout.ScaleWindow(1280, 720, 1024, 576, 300, 170, 680, 380)
assertEqual(scaledX, 240, "viewport scaling preserves horizontal centre")
assertEqual(scaledY, 136, "viewport scaling preserves vertical centre")
assertEqual(scaledWidth, 544, "viewport scaling updates width")
assertEqual(scaledHeight, 304, "viewport scaling updates height")

local recoveredX, recoveredY = Layout.ScaleWindow(1280, 720, 1024, 576, -5000, 5000, 680, 380)
local minimumX, minimumY, maximumX, maximumY = Layout.GetPositionBounds(1024, 576, 544, 304)
assertTrue(recoveredX >= minimumX and recoveredX <= maximumX, "viewport scaling recovers horizontal position")
assertTrue(recoveredY >= minimumY and recoveredY <= maximumY, "viewport scaling recovers vertical position")

local _, _, restoredWidth, restoredHeight = Layout.ScaleWindow(1920, 1080, 1280, 720, 540, 290, 840, 500, 840, 470)
assertEqual(restoredWidth, 840, "relative user width survives a capped viewport")
assertEqual(restoredHeight, 470, "relative user height survives a capped viewport")

Color3 = {
	fromRGB = function(red, green, blue)
		return {
			R = red / 255,
			G = green / 255,
			B = blue / 255,
		}
	end,
}

local Theme = assert(loadfile("ui/Theme.lua"))()

local legacySurface = Color3.fromRGB(30, 30, 30)
assertEqual(Theme.ResolveColor(legacySurface), Theme.Colors.SurfaceRaised, "legacy asset surface uses shared theme")
assertEqual(
	Theme.ResolveColor(Theme.Colors.SurfaceRaised),
	Theme.Colors.SurfaceRaised,
	"theme application is idempotent"
)
assertEqual(Theme.ResolveColor(Color3.fromRGB(225, 0, 0)), Theme.Colors.Accent, "legacy accent uses shared theme")
assertTrue(Theme.Metrics.MinimumHitSize >= 28, "shared controls expose a minimum interactive target")
assertTrue(Theme.Motion.Normal > 0, "shared motion timing is centralized")
assertEqual(Theme.Colors.Focus, Theme.Colors.Accent, "focus uses the shared accent")

local themedObject = {
	BackgroundColor3 = Color3.fromRGB(40, 40, 40),
	BorderColor3 = Color3.fromRGB(50, 50, 50),
}

function themedObject:IsA(className)
	return className == "GuiObject"
end

Theme.ApplyObject(themedObject)
assertEqual(themedObject.BackgroundColor3, Theme.Colors.Control, "dynamic background is themed")
assertEqual(themedObject.BorderColor3, Theme.Colors.Border, "dynamic border is themed")

local mainSource = readFile("ui/main.lua")
assertTrue(mainSource:find('import("ui/ControlUtil")', 1, true), "main uses shared control behavior")
assertTrue(mainSource:find("Layout.GetDraggedPosition", 1, true), "main uses shared drag calculation")
assertTrue(mainSource:find("Layout.ClampPosition", 1, true), "main keeps the window recoverable")
assertTrue(mainSource:find("Layout.ScaleWindow", 1, true), "main rescales on viewport changes")
assertTrue(mainSource:find("ControlUtil.ConnectActivated", 1, true), "main uses cross-device button activation")
assertTrue(mainSource:find("ControlUtil.MotionDuration", 1, true), "main honours reduced motion")
assertTrue(mainSource:find("oh.resetWindow = resetWindow", 1, true), "main exposes a window reset QoL action")
assertTrue(mainSource:find("DOUBLE_TAP_WINDOW", 1, true), "double-clicking the title bar resets the window")
assertTrue(mainSource:find("Theme.Apply(Interface)", 1, true), "main themes the shipped asset")
assertTrue(
	mainSource:find("Interface.DescendantAdded:Connect(Theme.ApplyObject)", 1, true),
	"main themes future controls"
)

local controlUtilSource = readFile("ui/ControlUtil.lua")
assertTrue(controlUtilSource:find("button.Activated", 1, true), "shared controls prefer Activated")
assertTrue(controlUtilSource:find("ReducedMotionEnabled", 1, true), "shared controls honour reduced motion")
assertTrue(controlUtilSource:find("ClampPopupPosition", 1, true), "shared popups can remain on-screen")
assertTrue(controlUtilSource:find("GetScreenSize", 1, true), "shared popups use the current screen size")

local actionPanelSource = readFile("ui/controls/ActionPanel.lua")
assertTrue(actionPanelSource:find("ControlUtil.ConnectActivated", 1, true), "action panels use cross-device activation")
assertTrue(actionPanelSource:find("Theme.Metrics.MinimumHitSize", 1, true), "action panels use shared hit targets")
assertTrue(actionPanelSource:find("function panel:Destroy", 1, true), "action panels restore layout and clean up")

local checkBoxSource = readFile("ui/controls/CheckBox.lua")
assertTrue(checkBoxSource:find("ControlUtil.ConnectActivated", 1, true), "checkbox works across input devices")
assertTrue(checkBoxSource:find("function CheckBox.setEnabled", 1, true), "checkbox state has a single render path")

local contextMenuSource = readFile("ui/controls/ContextMenu.lua")
assertTrue(contextMenuSource:find("Enum.Font.SourceSans", 1, true), "context menus use the current enum font API")
assertTrue(contextMenuSource:find("ControlUtil.ClampPopupPosition", 1, true), "context menus stay within the viewport")
assertTrue(contextMenuSource:find("contextMenu.Buttons[#contextMenu.Buttons + 1]", 1, true), "context menus retain their buttons")

local dropdownSource = readFile("ui/controls/Dropdown.lua")
assertTrue(dropdownSource:find("openDropdown", 1, true), "only one dropdown remains open")
assertTrue(dropdownSource:find("UserInputService.InputBegan", 1, true), "dropdowns close on outside input")
assertTrue(dropdownSource:find("ControlUtil.ConnectActivated", 1, true), "dropdowns work across input devices")

local listSource = readFile("ui/controls/List.lua")
assertTrue(listSource:find('instance:IsA("GuiButton")', 1, true), "list context binding ignores layout objects")
assertTrue(listSource:find("RightControl", 1, true), "multi-select supports either Control key")
assertTrue(listSource:find("function List.destroy", 1, true), "lists expose lifecycle cleanup")

local messageBoxSource = readFile("ui/controls/MessageBox.lua")
assertTrue(messageBoxSource:find("Enum.Font.SourceSans", 1, true), "message boxes use the current enum font API")
assertTrue(messageBoxSource:find("ControlUtil.SetSelectedObject", 1, true), "message boxes select the primary action")
assertTrue(messageBoxSource:find("MessageBox.Hide()", 1, true), "message boxes close before invoking callbacks")

local promptSource = readFile("ui/controls/Prompt.lua")
assertTrue(promptSource:find("currentPrompt:Hide()", 1, true), "prompts are mutually exclusive")
assertTrue(promptSource:find("Enum.KeyCode.Escape", 1, true), "prompts support keyboard dismissal")

local tabSelectorSource = readFile("ui/controls/TabSelector.lua")
assertTrue(tabSelectorSource:find("ControlUtil.ConnectActivated", 1, true), "tabs support click, touch, and gamepad activation")
assertTrue(tabSelectorSource:find("current runtime", 1, true), "runtime capability errors use neutral wording")

local rakNetUiSource = readFile("ui/modules/RakNetSpy.lua")
assertTrue(rakNetUiSource:find("local Page = Base.Body.Pages.RemoteSpy", 1, true), "RakNet shares the RemoteSpy page")
assertTrue(
	rakNetUiSource:find('sourceSwitch.Name = "TrafficSource"', 1, true),
	"RemoteSpy exposes a traffic source switch"
)
assertTrue(
	rakNetUiSource:find("local PacketList = trackInstance(RemoteList:Clone())", 1, true)
		and rakNetUiSource:find("local PacketLogs = trackInstance(RemoteLogs:Clone())", 1, true),
	"RakNet builds new RemoteSpy-style list and log views"
)
assertTrue(rakNetUiSource:find("ActionPanel.Install", 1, true), "RakNet uses the shared RemoteSpy action panel")
assertTrue(
	not rakNetUiSource:find('workspace.Name = "Workspace"', 1, true)
		and not rakNetUiSource:find('navigator.Name = "PacketIds"', 1, true),
	"the previous embedded RakNet workspace is gone"
)
assertTrue(rakNetUiSource:find('makeSourceButton("Remotes"', 1, true), "traffic switch includes Roblox remotes")
assertTrue(rakNetUiSource:find('makeSourceButton("RakNet"', 1, true), "traffic switch includes RakNet")
assertTrue(
	not rakNetUiSource:find('RegisterTab("RakNetSpy"', 1, true),
	"RakNet no longer creates a separate top-level tab"
)
assertTrue(rakNetUiSource:find("Methods.SetPacketIdBlocked", 1, true), "RakNet UI exposes packet-ID blocking")

for _, path in ipairs({
	"ui/main.lua",
	"ui/ControlUtil.lua",
	"ui/controls/ActionPanel.lua",
	"ui/controls/CheckBox.lua",
	"ui/controls/ContextMenu.lua",
	"ui/controls/Dropdown.lua",
	"ui/controls/List.lua",
	"ui/controls/MessageBox.lua",
	"ui/controls/Prompt.lua",
	"ui/controls/TabSelector.lua",
	"ui/controls/TextViewer.lua",
	"ui/modules/ClosureSpy.lua",
	"ui/modules/ConstantScanner.lua",
	"ui/modules/RakNetSpy.lua",
	"ui/modules/RemoteSpy.lua",
	"ui/modules/UpvalueScanner.lua",
}) do
	local source = readFile(path)
	assertTrue(not source:find("Color3.fromRGB", 1, true), path .. " has no independent RGB palette")
	assertTrue(not source:find("Color3.new", 1, true), path .. " has no independent Color3 palette")
end

oh = { Settings = { MaxValueViewBytes = 1024 }, Events = {} }
typeof = function(value)
	return type(value) == "table" and rawget(value, "Class") == "Instance" and "Instance" or type(value)
end
local InspectUtil = assert(loadfile("ui/InspectUtil.lua"))()
assertEqual(InspectUtil.SourceURL(nil, "ohaux"),
	"https://raw.githubusercontent.com/ProtonDev-sys/Hydroxide/main/ohaux.lua",
	"manual edit scripts use the default repository without a live runtime")
assertEqual(InspectUtil.SourceURL({ Owner = "example-org", Repository = "custom.repo", Branch = "feature/ui" }, "ohaux"),
	"https://raw.githubusercontent.com/example-org/custom.repo/feature/ui/ohaux.lua",
	"edit scripts preserve configured forks and branch names")
local pinnedCommit = string.rep("A1", 20)
assertEqual(InspectUtil.SourceURL({ Owner = "example-org", Repository = "custom.repo", Branch = "main", Commit = pinnedCommit }, "ohaux"),
	"https://raw.githubusercontent.com/example-org/custom.repo/" .. pinnedCommit:lower() .. "/ohaux.lua",
	"edit scripts use the loaded immutable commit instead of a branch that can move")
assertEqual(InspectUtil.SourceURL({ Branch = 'feature/a%20b"?#' }, "ohaux"),
	"https://raw.githubusercontent.com/ProtonDev-sys/Hydroxide/feature/a%2520b%22%3F%23/ohaux.lua",
	"source revisions cannot add a query, fragment, or script literal")
for _, invalid in ipairs({
	{ Owner = "example/other" }, { Repository = ".." }, { Branch = "../other" },
	{ Branch = "main/../other" }, { Branch = "/main" }, { Branch = "main//other" },
	{ Branch = "" }, { Commit = "short" }, { Commit = false },
}) do
	assertEqual(pcall(InspectUtil.SourceURL, invalid, "ohaux"), false, "invalid source configuration is rejected before exporting code")
end
assertEqual(pcall(InspectUtil.SourceURL, {}, "../ohaux"), false, "source assets cannot escape their configured repository path")

local packedDescription = InspectUtil.DescribePackedValues("Arguments", { n = 2, false })
assertTrue(packedDescription:find("Count: 2", 1, true), "packed argument count retains trailing nil")
assertTrue(packedDescription:find("false", 1, true), "argument viewer retains false values")
assertTrue(packedDescription:find("nil", 1, true), "argument viewer shows trailing nil values")
assertEqual(InspectUtil.PackedCount({ n = math.huge }), 0, "infinite packed count cannot create an unbounded render loop")
assertEqual(InspectUtil.PackedCount({ n = 0 / 0 }), 0, "NaN packed count is rejected")

local hostileValue = setmetatable({}, {
	__tostring = function() error("do not stringify tables") end,
	__pairs = function() error("do not invoke iterator metamethods") end,
	__len = function() error("do not inspect length when packed count is supplied") end,
})
assertEqual(InspectUtil.Summary(hostileValue), "table (0 entries)", "table previews avoid value metamethods")
rawset(hostileValue, "n", 3)
assertEqual(InspectUtil.PackedCount(hostileValue), 3, "packed count avoids length metamethods")

formatValueTree = function(value, options)
	assertEqual(value.answer, 42, "table viewer receives the original captured data")
	return "{ answer = 42 }"
end
local treeDescription = InspectUtil.DescribePackedValues("Arguments", { n = 1, { answer = 42 } })
assertTrue(treeDescription:find("{ answer = 42 }", 1, true), "argument viewer preserves expanded tables")

formatValueTree = function() return string.rep("x", 100000) end
getInstancePath = function() return string.rep("path", 10000) end
for _, maximum in ipairs({ 1, 32, 256, 1024 }) do
	oh.Settings.MaxValueViewBytes = maximum
	local values = { n = 3, {}, { Class = "Instance" }, "tail" }
	assertTrue(#InspectUtil.DescribePackedValues("Arguments", values) <= maximum, "value output enforces its complete byte budget")
end
formatValueTree = nil

local realDate = os.date
os.date = function(_, seconds) return tostring(seconds) end
assertEqual(InspectUtil.Timestamp(12.9996), "13.000 local", "timestamp rounding carries into the next second")
assertEqual(InspectUtil.Timestamp(math.huge), "unknown", "nonfinite timestamps render safely")
os.date = realDate

local heap, sorted = {}, {}
for index = 200, 1, -1 do
	local row = { Sort = tostring(index % 13), Stable = ("%03d"):format(index) }
	sorted[#sorted + 1] = row
	InspectUtil.AddBoundedRow(heap, row, 17)
	assertTrue(#heap <= 17, "scanner retains only its configured row budget")
end
table.sort(sorted, InspectUtil.RowComesBefore)
table.sort(heap, InspectUtil.RowComesBefore)
for index, row in ipairs(heap) do
	assertEqual(row, sorted[index], "bounded scanner rows match full sorted results")
end
local noRows = {}
InspectUtil.AddBoundedRow(noRows, sorted[1], 0)
assertEqual(#noRows, 0, "zero row budget retains no results")

local function signal()
	local event = { Connections = {} }
	function event:Connect(callback)
		local connection = { Connected = true, Callback = callback }
		function connection:Disconnect() self.Connected = false end
		self.Connections[#self.Connections + 1] = connection
		return connection
	end
	function event:Fire(...)
		for _, connection in ipairs(self.Connections) do
			if connection.Connected then connection.Callback(...) end
		end
	end
	return event
end

local services = {
	GuiService = { ReducedMotionEnabled = false },
	UserInputService = {
		InputBegan = signal(), InputEnded = signal(), WindowFocusReleased = signal(),
		IsKeyDown = function() return false end,
	},
	TweenService = {
		Create = function()
			return { Play = function() end, Cancel = function() end }
		end,
	},
}
game = { GetService = function(_, name) return assert(services[name], name) end }
Enum = {
	KeyCode = { LeftControl = "LeftControl", RightControl = "RightControl" },
	UserInputType = { MouseButton1 = "MouseButton1", Touch = "Touch" },
}
UDim2 = { new = function(xScale, xOffset, yScale, yOffset)
	return { X = { Scale = xScale, Offset = xOffset }, Y = { Scale = yScale, Offset = yOffset } }
end }
TweenInfo = { new = function(duration) return duration end }
if not table.find then
	table.find = function(values, wanted)
		for index, value in ipairs(values) do if value == wanted then return index end end
	end
end
local deferred = {}
task = { defer = function(callback) deferred[#deferred + 1] = callback end }
local function flushDeferred()
	local pending = deferred
	deferred = {}
	for _, callback in ipairs(pending) do callback() end
end

local ControlUtil
import = function(name)
	if name == "ui/Theme" then return Theme end
	if name == "ui/ControlUtil" then return ControlUtil end
	error("unexpected UI import: " .. name)
end
ControlUtil = assert(loadfile("ui/ControlUtil.lua"))()
local List, ListButton = assert(loadfile("ui/controls/List.lua"))()
local globalConnections = #oh.Events

local function button()
	local object = {
		Activated = signal(), MouseButton1Click = signal(), MouseButton2Click = signal(),
		Active = true, Visible = true, Selectable = true, AbsoluteSize = { X = 100, Y = 20 },
		TextTransparency = 0, BackgroundColor3 = Theme.Colors.Row, BorderColor3 = Theme.Colors.Border,
		TextColor3 = Theme.Colors.Text, TextStrokeColor3 = Theme.Colors.Text,
	}
	function object:IsA(name)
		return name == "TextButton" or name == "GuiButton" or name == "GuiObject"
	end
	function object:GetDescendants() return {} end
	function object:Destroy()
		self.Parent = nil
		for _, event in ipairs({ self.Activated, self.MouseButton1Click, self.MouseButton2Click }) do
			for _, connection in ipairs(event.Connections) do connection:Disconnect() end
		end
	end
	return object
end

local frame = { Parent = {}, ScrollBarThickness = 0, ChildAdded = signal() }
local list = List.new(frame)
local rowInstance = button()
local row = ListButton.new(rowInstance, list)
local calls = 0
row:SetCallback(function() calls = calls + 1 end)
rowInstance.Activated:Fire()
assertEqual(calls, 1, "rows respond to cross-device activation")
ControlUtil.SetButtonEnabled(rowInstance, false)
rowInstance.Activated:Fire()
assertEqual(calls, 1, "disabled buttons cannot invoke actions")
Theme.ApplyObject(rowInstance)
assertEqual(rowInstance.Selectable, false, "applying the theme preserves disabled focus state")
ControlUtil.SetButtonEnabled(rowInstance, true)
services.UserInputService.InputBegan:Fire({ KeyCode = Enum.KeyCode.LeftControl })
rowInstance.Activated:Fire()
assertEqual(calls, 2, "Control does not suppress single-select list actions")
services.UserInputService.WindowFocusReleased:Fire()

list:BeginBatch()
flushDeferred()
assertEqual(frame.CanvasSize.Y.Offset, 15, "a queued layout waits for an active batch")
list:EndBatch()
flushDeferred()
assertEqual(frame.CanvasSize.Y.Offset, 40, "batch completion measures the final row heights")

list:BindContextMenu({ Show = function() end })
local retainedConnections = #oh.Events
for _ = 1, 100 do ListButton.new(button(), list) end
assertEqual(#oh.Events, retainedConnections, "transient row connections do not grow the runtime registry")
row:SetSelected(true)
list:Clear()
assertEqual(list.Selected, nil, "clearing a list clears selection")
assertEqual(row.Instance, nil, "clearing a list releases external row handles")
assertEqual(row.Callback, nil, "clearing a list releases captured callback values")
assertEqual(next(list.ContextConnections.Normal), nil, "clearing a list releases context bindings")
assertEqual(row:Remove(), false, "removing an already cleared row is harmless")
flushDeferred()
assertEqual(frame.CanvasSize.Y.Offset, 15, "queued work cannot restore rows after Clear")
list:Destroy()
list:QueueRecalculate()
assertEqual(#deferred, 0, "destroyed lists cannot schedule work")
assertTrue(globalConnections > 0, "global input listeners remain registered for runtime teardown")

local batchDepth, renderedRows, currentSearch = 0, 0, true
local batchedList = {
	BeginBatch = function() batchDepth = batchDepth + 1 end,
	EndBatch = function() batchDepth = batchDepth - 1 end,
}
task.wait = function()
	assertEqual(batchDepth, 0, "scan rendering yields only after releasing the list batch")
	currentSearch = false
end
local rendered, cancelled = ControlUtil.RenderRows(batchedList, { 1, 2, 3, 4, 5 }, function()
	renderedRows = renderedRows + 1
end, function() return currentSearch end, 2)
assertTrue(rendered and cancelled, "superseded scans stop cleanly")
assertEqual(renderedRows, 2, "superseded scan does not append stale rows after yielding")
assertEqual(batchDepth, 0, "cancelled scans leave batching balanced")
local succeeded, renderError = ControlUtil.RenderRows(batchedList, { 1 }, function()
	error("row cannot render")
end, function() return true end)
assertTrue(not succeeded and renderError:find("row cannot render", 1, true), "row creation failure reaches the caller")
assertEqual(batchDepth, 0, "failed row rendering still releases batching")

print("ui_spec.lua: ok")
