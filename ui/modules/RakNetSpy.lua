local RakNetSpy = {}
local Methods = import("modules/RakNetSpy")
local TextViewer = import("ui/controls/TextViewer")
local ActionPanel = import("ui/controls/ActionPanel")
local List, ListButton = import("ui/controls/List")
local Theme = oh.Theme or import("ui/Theme")

local Base = import("rbxassetid://11389137937").Base
local Assets = import("rbxassetid://5042114982").RemoteSpy
local Page = Base.Body.Pages.RemoteSpy
local RemoteList = Page.List
local RemoteLogs = Page.Logs

local icons = {
	raknet = "rbxassetid://4229806545",
	pause = "rbxassetid://4842578510",
	resume = "rbxassetid://4842578818",
	clear = "rbxassetid://4892169181",
	details = "rbxassetid://4666594276",
	hex = "rbxassetid://9058292613",
	code = "rbxassetid://4800244808",
	copy = "rbxassetid://4891705738",
	replay = "rbxassetid://4907151581",
	diagnostics = "rbxassetid://4909102841",
	ignore = "rbxassetid://4842578510",
	unignore = "rbxassetid://4842578818",
	block = "rbxassetid://4891641806",
	unblock = "rbxassetid://4891642508",
	filter = "rbxassetid://4702831188",
}

local alive = true
local activeViewer
local viewerGeneration = 0
local selectedGroup
local selectedEntry
local activeSource
local activeRakNetView
local activeQuery = ""
local showSend = true
local showReceive = true
local refreshQueued = false
local refreshDirty = true
local packetRows = {}
local entryRows = {}
local savedRemoteVisibility = {}

local function trackInstance(instance)
	if oh and oh.Instances then
		oh.Instances[#oh.Instances + 1] = instance
	end

	return instance
end

local function trackConnection(connection)
	if oh and oh.Events then
		oh.Events[#oh.Events + 1] = connection
	end

	return connection
end

local function safeString(value)
	local ran, result = pcall(tostring, value)
	return ran and result or "<unprintable>"
end

local function settingNumber(names, fallback, minimum, maximum)
	local settings = type(oh) == "table" and type(oh.Settings) == "table" and oh.Settings or {}
	local value

	for _, name in ipairs(names) do
		if settings[name] ~= nil then
			value = tonumber(settings[name])
			break
		end
	end

	value = math.floor(value or fallback)
	return math.max(minimum, math.min(maximum, value))
end

local function setStatus(text)
	if oh and type(oh.setStatus) == "function" then
		oh.setStatus(text)
	end
end

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 4)
	corner.Parent = instance
	return corner
end

local function addStroke(instance)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.Colors.Border
	stroke.Thickness = 1
	stroke.Parent = instance
	return stroke
end

local function hideViewer()
	viewerGeneration = viewerGeneration + 1

	if activeViewer then
		TextViewer.Hide(activeViewer)
	end

	activeViewer = nil
end

local function showViewer(title, text, actions)
	viewerGeneration = viewerGeneration + 1
	local generation = viewerGeneration
	local viewer

	viewer = TextViewer.Show(title, text, {
		Parent = Page,
		Actions = actions,
		MaxBytes = settingNumber({ "MaxRakNetInspectorBytes", "MaxInspectorBytes" }, 524288, 4096, 8388608),
		OnHide = function(hiddenViewer)
			if activeViewer == hiddenViewer then
				activeViewer = nil
			end
		end,
	})
	activeViewer = viewer
	return viewer, generation
end

-- Keep the transport selector small, then give both implementations the same
-- usable RemoteSpy canvas. RakNet receives fresh list/log views below; no old
-- RakNet panel or separate top-level tab is transplanted here.
local remoteViews = {}
local remoteViewLayouts = {}

for _, name in ipairs({ "List", "Logs", "Conditions" }) do
	local view = Page:FindFirstChild(name)

	if view and view:IsA("GuiObject") then
		remoteViews[#remoteViews + 1] = view
		remoteViewLayouts[view] = {
			Position = view.Position,
			Size = view.Size,
			Visible = view.Visible,
		}
		view.Position =
			UDim2.new(view.Position.X.Scale, view.Position.X.Offset, view.Position.Y.Scale, view.Position.Y.Offset + 30)
		view.Size = UDim2.new(view.Size.X.Scale, view.Size.X.Offset, view.Size.Y.Scale, view.Size.Y.Offset - 30)
	end
end

local sourceSwitch = trackInstance(Instance.new("Frame"))
sourceSwitch.Name = "TrafficSource"
sourceSwitch.BackgroundColor3 = Theme.Colors.SurfaceRaised
sourceSwitch.BorderSizePixel = 0
sourceSwitch.Position = UDim2.new(0, 5, 0, 3)
sourceSwitch.Size = UDim2.new(0, 190, 0, 24)
sourceSwitch.ZIndex = 30
sourceSwitch.Parent = Page
addCorner(sourceSwitch, 4)
addStroke(sourceSwitch)

local sourceButtons = {}
local selectSource

local function makeSourceButton(name, text, xOffset, width)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = Theme.Colors.Control
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSansSemibold
	button.Position = UDim2.new(0, xOffset, 0, 2)
	button.Size = UDim2.new(0, width, 1, -4)
	button.Text = text
	button.TextColor3 = Theme.Colors.TextMuted
	button.TextSize = 13
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.ZIndex = sourceSwitch.ZIndex + 1
	button.Parent = sourceSwitch
	addCorner(button, 3)
	trackConnection(button.MouseButton1Click:Connect(function()
		if selectSource then
			selectSource(name)
		end
	end))
	sourceButtons[name] = button
	return button
end

makeSourceButton("Remotes", "Roblox Remotes", 2, 98)
makeSourceButton("RakNet", "RakNet", 102, 86)

local function clearClonedContent(content)
	for _, child in ipairs(content:GetChildren()) do
		if child:IsA("GuiButton") then
			child:Destroy()
		end
	end

	content.CanvasPosition = Vector2.new()
	content.CanvasSize = UDim2.new(0, 0, 0, 15)
end

-- Build a new RakNet list from the same shell used by RemoteSpy rather than
-- embedding the previous navigator/history implementation.
local PacketList = trackInstance(RemoteList:Clone())
PacketList.Name = "RakNetPacketList"
PacketList.Visible = false
PacketList.ZIndex = math.max(PacketList.ZIndex, 9)
PacketList.Parent = Page

local ListFlags = PacketList.Flags
local ListQuery = PacketList.Query
local ListSearch = ListQuery.Search
local ListRefresh = ListQuery.Refresh
local ListResultsFrame = PacketList.Results
local ListClip = ListResultsFrame.Clip
local ListResults = ListClip.Content
local ListStatus = ListClip:FindFirstChild("ResultStatus")

clearClonedContent(ListResults)
ListSearch.Text = ""
ListSearch.ClearTextOnFocus = false
ListSearch.PlaceholderText = "Search RakNet packet IDs"

for _, child in ipairs(ListFlags:GetChildren()) do
	child:Destroy()
end

local flagLayout = Instance.new("UIListLayout")
flagLayout.FillDirection = Enum.FillDirection.Horizontal
flagLayout.Padding = UDim.new(0, 5)
flagLayout.SortOrder = Enum.SortOrder.LayoutOrder
flagLayout.Parent = ListFlags

local function makeFilterButton(name, text, width, order)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = true
	button.BackgroundColor3 = Theme.Colors.Control
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSansSemibold
	button.LayoutOrder = order
	button.Size = UDim2.new(0, width, 0, 20)
	button.Text = text
	button.TextColor3 = Theme.Colors.Text
	button.TextSize = 13
	button.TextTruncate = Enum.TextTruncate.AtEnd
	button.Parent = ListFlags
	addCorner(button, 3)
	addStroke(button)
	return button
end

local sendFilter = makeFilterButton("Send", "Send ON", 72, 1)
local receiveFilter = makeFilterButton("Receive", "Receive ON", 82, 2)

-- The logs view is also newly cloned from RemoteSpy's visual shell. Remove any
-- runtime inspector toolbar copied from the Roblox-remote view before installing
-- a RakNet-specific action set with the shared ActionPanel control.
local PacketLogs = trackInstance(RemoteLogs:Clone())
PacketLogs.Name = "RakNetPacketLogs"
PacketLogs.Visible = false
PacketLogs.ZIndex = math.max(PacketLogs.ZIndex, 9)
PacketLogs.Parent = Page

local copiedToolbar = PacketLogs:FindFirstChild("HydroxideActionToolbar")

if copiedToolbar then
	copiedToolbar:Destroy()
end

local LogsResultsFrame = PacketLogs.Results
LogsResultsFrame.Position = UDim2.new(0, 0, 0, 58)
LogsResultsFrame.Size = UDim2.new(1, 0, 1, -58)

local LogsButtons = PacketLogs.Buttons
local LogsPacket = PacketLogs.RemoteObject
local LogsBack = PacketLogs.Back
local LogsResults = LogsResultsFrame.Clip.Content

clearClonedContent(LogsResults)
LogsPacket.Label.Text = "RakNet packets"
LogsPacket.Icon.Image = icons.raknet

local packetList = List.new(ListResults)
local packetLogs = List.new(LogsResults)
local callInspector

local function filteredCount(group)
	local count = 0

	if showSend then
		count = count + (tonumber(group.SendCount) or 0)
	end

	if showReceive then
		count = count + (tonumber(group.ReceiveCount) or 0)
	end

	return count
end

local function packetLabel(group)
	local states = {}

	if Methods.IsPacketIdBlocked(group.PacketId) then
		states[#states + 1] = "BLOCKED"
	end

	if Methods.IsPacketIdIgnored(group.PacketId) then
		states[#states + 1] = "IGNORED"
	end

	local suffix = #states > 0 and ("  [" .. table.concat(states, ", ") .. "]") or ""
	return ("Packet %s  •  S%d R%d%s"):format(
		safeString(group.PacketId),
		tonumber(group.SendCount) or 0,
		tonumber(group.ReceiveCount) or 0,
		suffix
	)
end

local function groupMatchesQuery(group)
	if activeQuery == "" then
		return true
	end

	local text = table
		.concat({
			safeString(group.PacketId),
			packetLabel(group),
			Methods.IsPacketIdBlocked(group.PacketId) and "blocked" or "",
			Methods.IsPacketIdIgnored(group.PacketId) and "ignored" or "",
		}, " ")
		:lower()
	return text:find(activeQuery, 1, true) ~= nil
end

local function payloadBytes(entry)
	if type(entry.PayloadBytes) == "string" then
		return entry.PayloadBytes
	elseif type(entry.PreviewBytes) == "string" then
		return entry.PreviewBytes
	end
end

local function compactPreview(entry)
	local bytes = payloadBytes(entry)

	if type(bytes) ~= "string" then
		return safeString(entry.PayloadError or entry.PayloadState or "payload unavailable")
	end

	local limit = settingNumber({ "MaxRakNetTextPreviewBytes" }, 120, 16, 2048)
	local shown = bytes:sub(1, limit)
	local parts = {}

	for index = 1, #shown do
		local byte = shown:byte(index)

		if byte >= 32 and byte <= 126 then
			parts[#parts + 1] = string.char(byte)
		elseif byte == 9 then
			parts[#parts + 1] = "\\t"
		elseif byte == 10 then
			parts[#parts + 1] = "\\n"
		elseif byte == 13 then
			parts[#parts + 1] = "\\r"
		else
			parts[#parts + 1] = ("\\x%02X"):format(byte)
		end
	end

	if #bytes > limit then
		parts[#parts + 1] = (" … +%d bytes"):format(#bytes - limit)
	end

	return table.concat(parts)
end

local function formatTimestamp(timestamp)
	if type(timestamp) ~= "number" then
		return "unknown"
	end

	local seconds = math.floor(timestamp)
	local milliseconds = math.floor((timestamp - seconds) * 1000 + 0.5) % 1000
	local ran, formatted = pcall(os.date, "%Y-%m-%d %H:%M:%S", seconds)
	return ran and ("%s.%03d local"):format(formatted, milliseconds) or ("%.3f"):format(timestamp)
end

local function describeEntry(entry)
	local lines = {
		"RAKNET PACKET",
		("Packet ID: %s"):format(safeString(entry.PacketId)),
		("Direction: %s"):format(safeString(entry.Direction)),
		("Sequence: %s"):format(safeString(entry.Sequence)),
		("Captured: %s"):format(formatTimestamp(entry.Timestamp)),
		("Declared size: %s"):format(safeString(entry.Size)),
		("Stored bytes: %s"):format(safeString(entry.StoredBytes)),
		("Payload state: %s"):format(safeString(entry.PayloadState)),
		("Priority: %s"):format(safeString(entry.Priority)),
		("Reliability: %s"):format(safeString(entry.Reliability)),
		("Ordering channel: %s"):format(safeString(entry.OrderingChannel)),
		("Replayable: %s"):format(safeString(entry.Replayable == true)),
		("Block configured: %s"):format(safeString(entry.BlockConfigured == true)),
		("Blocked at capture: %s"):format(safeString(entry.Blocked == true)),
	}

	if entry.BlockError then
		lines[#lines + 1] = "Block error: " .. safeString(entry.BlockError)
	end

	if entry.PayloadError then
		lines[#lines + 1] = "Payload error: " .. safeString(entry.PayloadError)
	end

	local fieldNames = {}

	for name in pairs(entry.FieldErrors or {}) do
		fieldNames[#fieldNames + 1] = safeString(name)
	end

	table.sort(fieldNames)

	if #fieldNames > 0 then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "FIELD ERRORS"

		for _, name in ipairs(fieldNames) do
			lines[#lines + 1] = ("  %s: %s"):format(name, safeString(entry.FieldErrors[name]))
		end
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "PAYLOAD PREVIEW"
	lines[#lines + 1] = compactPreview(entry)
	return table.concat(lines, "\n")
end

local function hexDump(bytes, maximum)
	if type(bytes) ~= "string" then
		return "(payload bytes unavailable)"
	end

	local shown = math.min(#bytes, maximum)
	local lines = {}

	for offset = 1, shown, 16 do
		local hex = {}
		local ascii = {}

		for index = offset, math.min(offset + 15, shown) do
			local byte = bytes:byte(index)
			hex[#hex + 1] = ("%02X"):format(byte)
			ascii[#ascii + 1] = byte >= 32 and byte <= 126 and string.char(byte) or "."
		end

		lines[#lines + 1] = ("%08X  %-47s  |%s|"):format(offset - 1, table.concat(hex, " "), table.concat(ascii))
	end

	if shown < #bytes then
		lines[#lines + 1] = ("... %d more bytes not shown ..."):format(#bytes - shown)
	end

	return table.concat(lines, "\n")
end

local function describeHex(entry)
	local bytes = payloadBytes(entry)
	local maximum = settingNumber({ "MaxRakNetHexBytes", "MaxHexBytes" }, 4096, 32, 65536)
	return table.concat({
		("Packet %s • %s • %s bytes"):format(
			safeString(entry.PacketId),
			safeString(entry.Direction),
			safeString(entry.StoredBytes)
		),
		"",
		hexDump(bytes, maximum),
	}, "\n")
end

local function describeDiagnostics()
	local capabilities = Methods.Capabilities or {}
	local diagnostics = Methods.Diagnostics or {}
	local lines = {
		"RAKNET SPY DIAGNOSTICS",
		"",
		"Connected: " .. safeString(Methods.Connected == true),
		"Capture: " .. (Methods.Enabled and "running" or "paused"),
		"Send hook: " .. safeString(capabilities.SendHookInstalled == true),
		"Receive hook: " .. safeString(capabilities.ReceiveHookInstalled == true),
		"raknet.send: " .. safeString(capabilities.Send == true),
		"",
		"COUNTERS",
	}
	local names = {}

	for name, value in pairs(diagnostics) do
		if type(value) ~= "table" then
			names[#names + 1] = name
		end
	end

	table.sort(names)

	for _, name in ipairs(names) do
		lines[#lines + 1] = ("  %-28s %s"):format(name .. ":", safeString(diagnostics[name]))
	end

	for _, filter in ipairs({
		{ "Blocked", Methods.BlockedPacketIds },
		{ "Ignored", Methods.IgnoredPacketIds },
	}) do
		local values = {}

		for _, record in pairs(filter[2] or {}) do
			values[#values + 1] = safeString(record.PacketId)
		end

		table.sort(values)
		lines[#lines + 1] = ""
		lines[#lines + 1] = ("%s packet IDs (%d)"):format(filter[1], #values)
		lines[#lines + 1] = #values > 0 and ("  " .. table.concat(values, "\n  ")) or "  (none)"
	end

	return table.concat(lines, "\n")
end

local function copyText(text)
	local copyFunction = setclipboard or toclipboard

	if type(copyFunction) ~= "function" then
		return false, "clipboard function unavailable"
	end

	local ran, result = pcall(copyFunction, text)
	return ran, ran and result or safeString(result)
end

local function buildSelectedCode(entry)
	local ran, source, buildError = pcall(Methods.BuildScript, entry)

	if not ran then
		return nil, safeString(source)
	elseif type(source) ~= "string" or source == "" then
		return nil, safeString(buildError or "Code could not be generated for this packet")
	end

	return source
end

local function showDetails()
	if selectedEntry then
		showViewer("RakNet Packet Details", describeEntry(selectedEntry))
	end
end

local function showHex()
	if selectedEntry then
		showViewer("RakNet Payload Hex", describeHex(selectedEntry))
	end
end

local function showCode()
	local entry = selectedEntry

	if not entry then
		return
	end

	local _, generation = showViewer("RakNet Code", "Generating compile-validated RakNet code ...")
	task.spawn(function()
		local source, buildError = buildSelectedCode(entry)

		if not alive or selectedEntry ~= entry or viewerGeneration ~= generation then
			return
		elseif not source then
			showViewer("RakNet Code Unavailable", buildError)
		else
			showViewer(entry.Direction == "receive" and "RakNet Receive Template" or "RakNet Send Replay Code", source)
		end
	end)
end

local function copyCode()
	local entry = selectedEntry

	if not entry then
		return
	end

	setStatus("Building RakNet code ...")
	task.spawn(function()
		local source, buildError = buildSelectedCode(entry)

		if not alive or selectedEntry ~= entry then
			return
		elseif not source then
			setStatus("RakNet code unavailable")
			showViewer("RakNet Code Unavailable", buildError)
			return
		end

		local copied, copyError = copyText(source)

		if copied then
			setStatus(entry.Direction == "receive" and "RakNet receive template copied" or "RakNet replay code copied")
		else
			setStatus("RakNet code copy failed")
			showViewer("Copy Failed", copyError)
		end
	end)
end

local function replaySelected()
	local entry = selectedEntry

	if not entry then
		return
	elseif entry.Direction ~= "send" or not entry.Replayable then
		showViewer("RakNet Replay Unavailable", "Only complete outgoing captures can be replayed.")
		return
	elseif Methods.IsPacketIdBlocked(entry.PacketId) then
		showViewer("RakNet Packet Is Blocked", "Unblock this packet ID before replaying it.")
		return
	end

	local started = false
	showViewer(
		"Confirm RakNet Replay",
		("Replay outgoing packet %s with %s captured bytes?\n\nPriority %s • Reliability %s • Channel %s"):format(
			safeString(entry.PacketId),
			safeString(entry.StoredBytes),
			safeString(entry.Priority),
			safeString(entry.Reliability),
			safeString(entry.OrderingChannel)
		),
		{
			{
				Label = "Replay",
				Callback = function()
					if started then
						return
					end

					started = true
					local _, generation = showViewer("Replaying RakNet Packet", "Sending captured payload ...")
					task.spawn(function()
						local ran, succeeded, replayError = pcall(Methods.Replay, entry)

						if not ran then
							replayError = succeeded
							succeeded = false
						end

						if not alive or selectedEntry ~= entry or viewerGeneration ~= generation then
							return
						elseif succeeded then
							setStatus("RakNet packet replayed")
							showViewer(
								"RakNet Replay Complete",
								"The captured outgoing payload was passed to raknet.send."
							)
						else
							setStatus("RakNet replay failed")
							showViewer("RakNet Replay Failed", safeString(replayError or "raknet.send failed"))
						end
					end)
				end,
			},
			{ Label = "Cancel", Callback = hideViewer },
		}
	)
end

local function clearFilters()
	local ran, changed = pcall(Methods.ClearPacketFilters)

	if not ran then
		showViewer("RakNet Filter Reset Failed", safeString(changed))
	elseif changed then
		setStatus("Cleared ignored and blocked RakNet packet IDs")
	else
		setStatus("RakNet packet filters were already clear")
	end
end

local function showDiagnostics()
	showViewer("RakNet Diagnostics", describeDiagnostics())
end

callInspector = ActionPanel.Install(LogsButtons, LogsResultsFrame, {
	Columns = 4,
	MinimumCellWidth = 88,
	ButtonHeight = 21,
	Gap = 3,
	Actions = {
		{ Name = "Details", Label = "Details", Icon = icons.details, Callback = showDetails },
		{ Name = "Hex", Label = "Hex", Icon = icons.hex, Callback = showHex },
		{ Name = "Code", Label = "Code", Icon = icons.code, Callback = showCode },
		{ Name = "CopyCode", Label = "Copy Code", Icon = icons.copy, Callback = copyCode },
		{ Name = "Replay", Label = "Replay", Icon = icons.replay, Callback = replaySelected },
		{ Name = "ClearFilters", Label = "Clear Filters", Icon = icons.filter, Callback = clearFilters },
		{ Name = "Diagnostics", Label = "Diagnostics", Icon = icons.diagnostics, Callback = showDiagnostics },
	},
})

local function setAssetButton(button, labelText, icon, enabled)
	if not button then
		return
	end

	enabled = enabled ~= false
	button.Active = enabled
	button.AutoButtonColor = enabled

	if button:FindFirstChild("Label") then
		button.Label.Text = labelText
		button.Label.TextTransparency = enabled and 0 or 0.45
	end

	if button:FindFirstChild("Icon") then
		button.Icon.Image = icon
		button.Icon.ImageTransparency = enabled and 0 or 0.45

		local border = button.Icon:FindFirstChild("Border")

		if border and border:IsA("ImageLabel") then
			border.Image = icon
		end
	end

	button.ImageTransparency = enabled and 0 or 0.45
end

local function updateSelectionStyles()
	for entry, model in pairs(entryRows) do
		if model.Instance and model.Instance.Parent then
			model.Instance.ImageColor3 = entry == selectedEntry and Theme.Colors.Selection or Theme.Colors.Row
		end
	end
end

local function updateControls()
	local packetId = selectedGroup and selectedGroup.PacketId
	local ignored = packetId ~= nil and Methods.IsPacketIdIgnored(packetId) or false
	local blocked = packetId ~= nil and Methods.IsPacketIdBlocked(packetId) or false
	local hasEntry = selectedEntry ~= nil
	local bytes = hasEntry and payloadBytes(selectedEntry) or nil

	setAssetButton(
		LogsButtons.Ignore,
		ignored and "Unignore" or "Ignore",
		ignored and icons.unignore or icons.ignore,
		packetId ~= nil
	)
	setAssetButton(
		LogsButtons.Block,
		blocked and "Unblock" or "Block",
		blocked and icons.unblock or icons.block,
		packetId ~= nil
	)
	setAssetButton(LogsButtons.Clear, "Clear", icons.clear, #Methods.Logs > 0)
	setAssetButton(
		LogsButtons.Conditions,
		Methods.Enabled and "Pause" or "Resume",
		Methods.Enabled and icons.pause or icons.resume,
		Methods.Connected == true
	)

	if callInspector then
		callInspector:SetEnabled("Details", hasEntry)
		callInspector:SetEnabled("Hex", type(bytes) == "string")
		callInspector:SetEnabled("Code", hasEntry)
		callInspector:SetEnabled("CopyCode", hasEntry)
		callInspector:SetEnabled(
			"Replay",
			hasEntry and selectedEntry.Direction == "send" and selectedEntry.Replayable == true and not blocked
		)
		callInspector:SetEnabled(
			"ClearFilters",
			next(Methods.IgnoredPacketIds or {}) ~= nil or next(Methods.BlockedPacketIds or {}) ~= nil
		)
		callInspector:SetEnabled("Diagnostics", true)

		if hasEntry then
			callInspector:SetStatus(
				("Packet %s • %s"):format(safeString(selectedEntry.PacketId), safeString(selectedEntry.Direction)),
				("%s bytes • %s"):format(
					safeString(selectedEntry.StoredBytes),
					safeString(selectedEntry.PayloadState)
				)
			)
		else
			callInspector:SetStatus("Select a captured RakNet packet to inspect")
		end
	end

	updateSelectionStyles()
end

local function selectEntry(entry)
	selectedEntry = entry
	updateControls()
end

local function createPacketField(contents, index, text, icon, colour)
	local field = Assets.RemoteArg:Clone()
	field.Name = tostring(index)
	field.Index.Text = tostring(index)
	field.Icon.Image = icon or icons.raknet
	field.Label.Text = text
	field.Label.TextColor3 = colour or Theme.Colors.Text
	field.Parent = contents
	return field.AbsoluteSize.Y + 5
end

local function makeEntryRow(entry, layoutOrder)
	local pod = Assets.CallPod:Clone()
	pod.Name = "RakNetPacket_" .. safeString(entry.Sequence)
	pod.LayoutOrder = layoutOrder
	pod.ImageColor3 = Theme.Colors.Row
	local height = 0
	local directionText = entry.Direction == "send" and "SEND →" or "← RECEIVE"
	local directionColour = entry.Blocked and Theme.Colors.Danger
		or (entry.Direction == "send" and Theme.Colors.Send or Theme.Colors.Receive)
	height = height
		+ createPacketField(
			pod.Contents,
			1,
			("%s  •  packet %s  •  sequence %s"):format(
				directionText,
				safeString(entry.PacketId),
				safeString(entry.Sequence)
			),
			icons.raknet,
			directionColour
		)
	height = height + createPacketField(pod.Contents, 2, compactPreview(entry), icons.details, Theme.Colors.Text)
	height = height
		+ createPacketField(
			pod.Contents,
			3,
			("Priority %s  •  Reliability %s  •  Channel %s"):format(
				safeString(entry.Priority),
				safeString(entry.Reliability),
				safeString(entry.OrderingChannel)
			),
			icons.diagnostics,
			Theme.Colors.TextMuted
		)
	height = height
		+ createPacketField(
			pod.Contents,
			4,
			("%s bytes  •  %s%s"):format(
				safeString(entry.StoredBytes),
				safeString(entry.PayloadState),
				entry.Blocked and "  •  BLOCKED" or ""
			),
			entry.Blocked and icons.block or icons.raknet,
			entry.Blocked and Theme.Colors.Danger or Theme.Colors.TextMuted
		)
	pod.Size = pod.Size + UDim2.new(0, 0, 0, height)

	local listButton = ListButton.new(pod, packetLogs)
	local model = {
		Entry = entry,
		Instance = pod,
		ListButton = listButton,
	}
	entryRows[entry] = model
	local function choose()
		selectEntry(entry)
	end
	listButton:SetCallback(choose)
	listButton:SetRightCallback(choose)
	return model
end

local function selectedGroupIsCurrent()
	return selectedGroup
		and Methods.PacketGroups[Methods.PacketIdKey(selectedGroup.PacketId)] == selectedGroup
		and filteredCount(selectedGroup) > 0
end

local function renderSelectedLogs()
	if not selectedGroupIsCurrent() then
		selectedGroup = nil
		selectedEntry = nil
		activeRakNetView = PacketList
		PacketLogs.Visible = false
		PacketList.Visible = activeSource == "RakNet"
		updateControls()
		return
	end

	local oldCanvas = LogsResults.CanvasPosition
	local followTop = oldCanvas.Y <= 6
	local source = selectedGroup.Logs
	local maximum = settingNumber({ "MaxRenderedRakNetLogs", "MaxRakNetRenderedLogs" }, 100, 10, 500)
	local entries = {}

	for index = #source, 1, -1 do
		local entry = source[index]

		if entry and ((showSend and entry.Direction == "send") or (showReceive and entry.Direction == "receive")) then
			entries[#entries + 1] = entry

			if #entries >= maximum then
				break
			end
		end
	end

	packetLogs:Clear()
	entryRows = {}
	packetLogs:BeginBatch()

	for order, entry in ipairs(entries) do
		makeEntryRow(entry, order)
	end

	packetLogs:EndBatch()

	if selectedEntry and not entryRows[selectedEntry] then
		selectedEntry = nil
	end

	LogsPacket.Label.Text = "Packet " .. safeString(selectedGroup.PacketId)
	LogsPacket.Label.TextColor3 = Methods.IsPacketIdBlocked(selectedGroup.PacketId) and Theme.Colors.Danger
		or (Methods.IsPacketIdIgnored(selectedGroup.PacketId) and Theme.Colors.Warning or Theme.Colors.Text)
	updateControls()
	task.defer(function()
		if alive and LogsResults.Parent then
			local maximumY = math.max(0, LogsResults.AbsoluteCanvasSize.Y - LogsResults.AbsoluteSize.Y)
			LogsResults.CanvasPosition = Vector2.new(0, followTop and 0 or math.min(oldCanvas.Y, maximumY))
		end
	end)
end

local function showPacketList()
	hideViewer()
	selectedEntry = nil
	activeRakNetView = PacketList
	PacketLogs.Visible = false
	PacketList.Visible = activeSource == "RakNet"
	updateControls()
end

local function showPacketLogs(group)
	if not group then
		return
	end

	hideViewer()
	selectedGroup = group
	selectedEntry = nil
	activeRakNetView = PacketLogs
	PacketList.Visible = false
	PacketLogs.Visible = activeSource == "RakNet"
	renderSelectedLogs()
end

local function makePacketRow(group)
	local button = Assets.RemoteLog:Clone()
	button.Name = "RakNetPacketId"
	button.Icon.Image = icons.raknet
	local listButton = ListButton.new(button, packetList)
	local model = {
		Button = button,
		Group = group,
		ListButton = listButton,
	}
	local function choose()
		if model.Group then
			showPacketLogs(model.Group)
		end
	end
	listButton:SetCallback(choose)
	listButton:SetRightCallback(choose)
	packetRows[group.Key] = model
	return model
end

local function refreshPacketList()
	local desired = {}
	local groups = {}

	for _, group in ipairs(Methods.PacketGroupList or {}) do
		if group and filteredCount(group) > 0 and groupMatchesQuery(group) then
			groups[#groups + 1] = group
			desired[group.Key] = true
		end
	end

	table.sort(groups, function(left, right)
		return safeString(left.PacketId) < safeString(right.PacketId)
	end)

	packetList:BeginBatch()

	for key, model in pairs(packetRows) do
		if not desired[key] then
			model.ListButton:Remove()
			packetRows[key] = nil
		end
	end

	for order, group in ipairs(groups) do
		local model = packetRows[group.Key] or makePacketRow(group)
		model.Group = group
		model.Button.LayoutOrder = order
		model.Button.Label.Text = packetLabel(group)
		model.Button.Calls.Text = tostring(filteredCount(group))
		model.Button.Label.TextColor3 = Methods.IsPacketIdBlocked(group.PacketId) and Theme.Colors.Danger
			or (Methods.IsPacketIdIgnored(group.PacketId) and Theme.Colors.Warning or Theme.Colors.Text)
	end

	packetList:EndBatch()

	if ListStatus then
		ListStatus.Visible = #groups == 0
		ListStatus.Text = Methods.Connected
				and (activeQuery ~= "" and "No matching RakNet packet IDs" or "No RakNet packets captured")
			or "RakNet hooks are unavailable"
	end

	if selectedGroup and not selectedGroupIsCurrent() then
		selectedGroup = nil
		selectedEntry = nil
		showPacketList()
	end
end

local function performRefresh()
	refreshQueued = false
	refreshDirty = false

	if not alive then
		return
	end

	refreshPacketList()

	if activeRakNetView == PacketLogs then
		renderSelectedLogs()
	else
		updateControls()
	end
end

local function queueRefresh()
	refreshDirty = true

	if refreshQueued or activeSource ~= "RakNet" or not Page.Visible then
		return
	end

	refreshQueued = true
	task.defer(performRefresh)
end

trackConnection(sendFilter.MouseButton1Click:Connect(function()
	showSend = not showSend
	sendFilter.Text = showSend and "Send ON" or "Send OFF"
	sendFilter.TextColor3 = showSend and Theme.Colors.Send or Theme.Colors.TextDisabled
	queueRefresh()
end))

trackConnection(receiveFilter.MouseButton1Click:Connect(function()
	showReceive = not showReceive
	receiveFilter.Text = showReceive and "Receive ON" or "Receive OFF"
	receiveFilter.TextColor3 = showReceive and Theme.Colors.Receive or Theme.Colors.TextDisabled
	queueRefresh()
end))

sendFilter.TextColor3 = Theme.Colors.Send
receiveFilter.TextColor3 = Theme.Colors.Receive

local searchGeneration = 0
trackConnection(ListSearch:GetPropertyChangedSignal("Text"):Connect(function()
	searchGeneration = searchGeneration + 1
	local generation = searchGeneration
	task.delay(0.12, function()
		if alive and generation == searchGeneration and ListSearch.Parent then
			activeQuery = ListSearch.Text:lower():match("^%s*(.-)%s*$") or ""
			queueRefresh()
		end
	end)
end))

trackConnection(ListRefresh.MouseButton1Click:Connect(function()
	queueRefresh()
	setStatus("Refreshed RakNet packet list")
end))

trackConnection(LogsBack.MouseButton1Click:Connect(showPacketList))

trackConnection(LogsButtons.Ignore.MouseButton1Click:Connect(function()
	if not selectedGroup then
		return
	end

	local packetId = selectedGroup.PacketId
	local ignored = Methods.IsPacketIdIgnored(packetId)
	local ran, result = pcall(Methods.SetPacketIdIgnored, packetId, not ignored)

	if not ran then
		showViewer("RakNet Ignore Failed", safeString(result))
	else
		setStatus((ignored and "Capturing" or "Ignoring") .. " RakNet packet ID " .. safeString(packetId))
		queueRefresh()
	end
end))

trackConnection(LogsButtons.Block.MouseButton1Click:Connect(function()
	if not selectedGroup then
		return
	end

	local packetId = selectedGroup.PacketId
	local blocked = Methods.IsPacketIdBlocked(packetId)
	local ran, result = pcall(Methods.SetPacketIdBlocked, packetId, not blocked)

	if not ran then
		showViewer("RakNet Block Failed", safeString(result))
	else
		setStatus((blocked and "Allowing" or "Blocking") .. " RakNet packet ID " .. safeString(packetId))
		queueRefresh()
	end
end))

trackConnection(LogsButtons.Clear.MouseButton1Click:Connect(function()
	local ran, clearError = pcall(Methods.Clear)

	if not ran then
		showViewer("RakNet Clear Failed", safeString(clearError))
	else
		selectedGroup = nil
		selectedEntry = nil
		showPacketList()
		queueRefresh()
	end
end))

trackConnection(LogsButtons.Conditions.MouseButton1Click:Connect(function()
	local ran, result = pcall(Methods.SetEnabled, not Methods.Enabled)

	if not ran then
		showViewer("RakNet Capture Error", safeString(result))
	else
		setStatus(Methods.Enabled and "RakNet capture resumed" or "RakNet capture paused")
		updateControls()
	end
end))

selectSource = function(name, quiet)
	name = name == "RakNet" and "RakNet" or "Remotes"

	if name == "RakNet" then
		if activeSource ~= "RakNet" then
			for _, view in ipairs(remoteViews) do
				savedRemoteVisibility[view] = view.Visible
				view.Visible = false
			end
		end

		activeRakNetView = activeRakNetView or PacketList
		PacketList.Visible = activeRakNetView == PacketList
		PacketLogs.Visible = activeRakNetView == PacketLogs
	else
		hideViewer()
		PacketList.Visible = false
		PacketLogs.Visible = false

		if activeSource == "RakNet" then
			for _, view in ipairs(remoteViews) do
				if savedRemoteVisibility[view] ~= nil then
					view.Visible = savedRemoteVisibility[view]
					savedRemoteVisibility[view] = nil
				end
			end
		end
	end

	activeSource = name

	for sourceName, button in pairs(sourceButtons) do
		local selected = sourceName == name
		button.BackgroundColor3 = selected and Theme.Colors.Selection or Theme.Colors.Control
		button.TextColor3 = selected and Theme.Colors.Text or Theme.Colors.TextMuted
	end

	if name == "RakNet" and refreshDirty then
		queueRefresh()
	end

	if not quiet then
		setStatus(name == "RakNet" and "RemoteSpy source: RakNet" or "RemoteSpy source: Roblox remotes")
	end
end

trackConnection(Page:GetPropertyChangedSignal("Visible"):Connect(function()
	if Page.Visible and activeSource == "RakNet" then
		queueRefresh()
	elseif not Page.Visible then
		hideViewer()
	end
end))

local backendConnection = Methods.ConnectEvent(function(_entry, action)
	if action == "cleared" then
		selectedGroup = nil
		selectedEntry = nil
		activeRakNetView = PacketList
		packetLogs:Clear()
		entryRows = {}
	elseif action == "disconnected" or action == "paused" or action == "resumed" then
		updateControls()
	end

	queueRefresh()
end)
trackConnection(backendConnection)

local lifecycle = {
	Connected = true,
}

function lifecycle:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false
	alive = false
	hideViewer()
	PacketList.Visible = false
	PacketLogs.Visible = false

	for _, view in ipairs(remoteViews) do
		local layout = remoteViewLayouts[view]

		if layout and view.Parent then
			view.Position = layout.Position
			view.Size = layout.Size

			if savedRemoteVisibility[view] ~= nil then
				view.Visible = savedRemoteVisibility[view]
			else
				view.Visible = layout.Visible
			end
		end
	end
end

trackConnection(lifecycle)

activeRakNetView = PacketList
updateControls()
selectSource("Remotes", true)

RakNetSpy.PacketList = PacketList
RakNetSpy.PacketLogs = PacketLogs
RakNetSpy.SourceSwitch = sourceSwitch
RakNetSpy.SelectSource = selectSource
RakNetSpy.Select = selectEntry
RakNetSpy.Refresh = queueRefresh

return RakNetSpy
