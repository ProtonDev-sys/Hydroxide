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

local draggedX, draggedY = Layout.GetDraggedPosition(100, 50, -1000, 900)
assertEqual(draggedX, -900, "drag permits negative off-screen x")
assertEqual(draggedY, 950, "drag permits positive off-screen y")

local scaledX, scaledY, scaledWidth, scaledHeight = Layout.ScaleWindow(1280, 720, 1024, 576, 300, 170, 680, 380)
assertEqual(scaledX, 240, "viewport scaling preserves horizontal centre")
assertEqual(scaledY, 136, "viewport scaling preserves vertical centre")
assertEqual(scaledWidth, 544, "viewport scaling updates width")
assertEqual(scaledHeight, 304, "viewport scaling updates height")

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
assertTrue(mainSource:find("Layout.GetDraggedPosition", 1, true), "main uses unrestricted drag calculation")
assertTrue(mainSource:find("Layout.ScaleWindow", 1, true), "main rescales on viewport changes")
assertTrue(mainSource:find("Theme.Apply(Interface)", 1, true), "main themes the shipped asset")
assertTrue(
	mainSource:find("Interface.DescendantAdded:Connect(Theme.ApplyObject)", 1, true),
	"main themes future controls"
)

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

local remoteUiSource = readFile("ui/modules/RemoteSpy.lua")
assertTrue(remoteUiSource:find("formatValueTree", 1, true), "argument viewer expands captured table contents")
assertTrue(remoteUiSource:find("MaxValueViewBytes", 1, true), "expanded argument output remains bounded")

local closureUiSource = readFile("ui/modules/ClosureSpy.lua")
assertTrue(closureUiSource:find("formatValueTree", 1, true), "closure argument viewer expands table contents")
assertTrue(closureUiSource:find("MaxValueViewBytes", 1, true), "closure expanded output remains bounded")

for _, path in ipairs({
	"ui/main.lua",
	"ui/controls/ActionPanel.lua",
	"ui/controls/List.lua",
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

print("ui_spec.lua: ok")
