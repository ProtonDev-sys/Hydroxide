local RakNetSpy = {}
local Methods = import("modules/RakNetSpy")
local TabSelector = import("ui/controls/TabSelector")
local TextViewer = import("ui/controls/TextViewer")

local Base = import("rbxassetid://11389137937").Base
local Tabs = Base.Tabs.Container
local Pages = Base.Body.Pages

local icons = {
	raknet = "rbxassetid://4229806545",
	pause = "rbxassetid://4842578510",
	clear = "rbxassetid://4892169181",
	details = "rbxassetid://4666594276",
	hex = "rbxassetid://9058292613",
	code = "rbxassetid://4800244808",
	copy = "rbxassetid://4891705738",
	replay = "rbxassetid://4907151581",
	diagnostics = "rbxassetid://4909102841",
}

local colours = {
	page = Color3.fromRGB(24, 24, 24),
	panel = Color3.fromRGB(29, 29, 29),
	input = Color3.fromRGB(18, 18, 18),
	button = Color3.fromRGB(38, 38, 38),
	buttonHover = Color3.fromRGB(48, 48, 48),
	buttonDisabled = Color3.fromRGB(28, 28, 28),
	row = Color3.fromRGB(31, 31, 31),
	rowAlternate = Color3.fromRGB(34, 34, 34),
	rowSelected = Color3.fromRGB(48, 42, 29),
	text = Color3.fromRGB(232, 232, 232),
	muted = Color3.fromRGB(156, 156, 156),
	border = Color3.fromRGB(58, 58, 58),
	send = Color3.fromRGB(105, 196, 255),
	receive = Color3.fromRGB(197, 139, 255),
	warning = Color3.fromRGB(238, 178, 69),
	error = Color3.fromRGB(240, 105, 105),
	good = Color3.fromRGB(113, 211, 137),
}

local ROW_HEIGHT = 42
local ROW_GAP = 3
local TOP_PIN_THRESHOLD = 8
local DEFAULT_RENDER_LIMIT = 150
local DEFAULT_TEXT_PREVIEW = 2048
local DEFAULT_HEX_PREVIEW = 1024
local DEFAULT_ARRAY_PREVIEW = 256
local alive = true

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

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius or 4)
	corner.Parent = instance
	return corner
end

local function addStroke(instance, colour, thickness)
	local stroke = Instance.new("UIStroke")
	stroke.Color = colour or colours.border
	stroke.Thickness = thickness or 1
	stroke.Parent = instance
	return stroke
end

local function makeLabel(parent, name, text, position, size, textSize)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.SourceSans
	label.Position = position
	label.Size = size
	label.Text = text or ""
	label.TextColor3 = colours.text
	label.TextSize = textSize or 15
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ZIndex = 3
	label.Parent = parent
	return label
end

local buttonEnabled = setmetatable({}, { __mode = "k" })

local function makeActionButton(parent, name, labelText, icon, layoutOrder, callback)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = colours.button
	button.BorderSizePixel = 0
	button.LayoutOrder = layoutOrder
	button.Size = UDim2.new(0, 100, 1, 0)
	button.Text = ""
	button.ZIndex = 3
	button.Parent = parent
	addCorner(button, 4)
	addStroke(button)

	local image = Instance.new("ImageLabel")
	image.Name = "Icon"
	image.BackgroundTransparency = 1
	image.Image = icon or ""
	image.ImageColor3 = colours.text
	image.Position = UDim2.new(0, 7, 0.5, -8)
	image.Size = UDim2.new(0, 16, 0, 16)
	image.ZIndex = button.ZIndex + 1
	image.Parent = button

	local label = makeLabel(button, "Label", labelText, UDim2.new(0, 27, 0, 0), UDim2.new(1, -31, 1, 0), 14)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.ZIndex = button.ZIndex + 1

	buttonEnabled[button] = true

	trackConnection(button.MouseEnter:Connect(function()
		if buttonEnabled[button] then
			button.BackgroundColor3 = colours.buttonHover
		end
	end))

	trackConnection(button.MouseLeave:Connect(function()
		button.BackgroundColor3 = buttonEnabled[button] and colours.button or colours.buttonDisabled
	end))

	trackConnection(button.MouseButton1Click:Connect(function()
		if buttonEnabled[button] and callback then
			callback()
		end
	end))

	return button
end

local function setButtonEnabled(button, enabled)
	enabled = enabled == true
	buttonEnabled[button] = enabled
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = enabled and colours.button or colours.buttonDisabled
	button.Label.TextTransparency = enabled and 0 or 0.48
	button.Icon.ImageTransparency = enabled and 0 or 0.48
end

local function setButtonText(button, text)
	button.Label.Text = text
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

local function safeString(value)
	local ran, result = pcall(tostring, value)
	return ran and result or "<unprintable>"
end

local function setStatus(text)
	if oh and type(oh.setStatus) == "function" then
		oh.setStatus(text)
	end
end

local function createTab()
	local template = Tabs:FindFirstChild("RemoteSpy") or Tabs:FindFirstChildWhichIsA("ImageButton")
	local tab

	if template then
		tab = template:Clone()
	else
		tab = Instance.new("ImageButton")
		tab.AutoButtonColor = false
		tab.BackgroundTransparency = 1
		tab.Image = ""
		tab.Size = UDim2.new(1, 0, 0, 42)

		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Position = UDim2.new(0.5, -10, 0.5, -10)
		icon.Size = UDim2.new(0, 20, 0, 20)
		icon.Parent = tab
	end

	local greatestOrder = 0

	for _, sibling in ipairs(Tabs:GetChildren()) do
		if sibling:IsA("GuiObject") then
			greatestOrder = math.max(greatestOrder, sibling.LayoutOrder)
		end
	end

	tab.LayoutOrder = greatestOrder + 1
	tab.Visible = true
	tab.ImageColor3 = Color3.fromRGB(20, 20, 20)

	local icon = tab:FindFirstChild("Icon")

	if not icon then
		icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Position = UDim2.new(0.5, -10, 0.5, -10)
		icon.Size = UDim2.new(0, 20, 0, 20)
		icon.Parent = tab
	end

	icon.Image = icons.raknet
	icon.ImageColor3 = Color3.fromRGB(127, 127, 127)

	local border = icon:FindFirstChild("Border")

	if border and border:IsA("ImageLabel") then
		border.Image = icons.raknet
	end

	return tab
end

-- The page is intentionally built from primitives. The shipped asset has no
-- RakNet page, and cloning RemoteSpy would retain unrelated prompts and state.
local Page = Instance.new("Frame")
Page.Name = "RakNetSpy"
Page.BackgroundColor3 = colours.page
Page.BackgroundTransparency = 0
Page.BorderSizePixel = 0
Page.ClipsDescendants = true
Page.Position = UDim2.new()
Page.Size = UDim2.new(1, 0, 1, 0)
Page.Visible = false
Page.ZIndex = 1
Page.Parent = Pages
trackInstance(Page)

local warning = Instance.new("TextLabel")
warning.Name = "RakNetWarning"
warning.BackgroundColor3 = Color3.fromRGB(45, 37, 22)
warning.BorderSizePixel = 0
warning.Font = Enum.Font.SourceSans
warning.Position = UDim2.new(0, 6, 0, 5)
warning.Size = UDim2.new(1, -12, 0, 44)
warning.Text = ""
warning.TextColor3 = colours.warning
warning.TextSize = 14
warning.TextWrapped = true
warning.TextXAlignment = Enum.TextXAlignment.Left
warning.TextYAlignment = Enum.TextYAlignment.Center
warning.ZIndex = 2
warning.Parent = Page
addCorner(warning, 4)
addStroke(warning, Color3.fromRGB(87, 69, 35))

local warningPadding = Instance.new("UIPadding")
warningPadding.PaddingLeft = UDim.new(0, 10)
warningPadding.PaddingRight = UDim.new(0, 10)
warningPadding.Parent = warning

local toolbar = Instance.new("Frame")
toolbar.Name = "Actions"
toolbar.BackgroundTransparency = 1
toolbar.BorderSizePixel = 0
toolbar.Position = UDim2.new(0, 6, 0, 54)
toolbar.Size = UDim2.new(1, -12, 0, 29)
toolbar.ZIndex = 2
toolbar.Parent = Page

local toolbarLayout = Instance.new("UIGridLayout")
toolbarLayout.CellPadding = UDim2.new(0, 4, 0, 4)
toolbarLayout.CellSize = UDim2.new(0.125, -4, 1, 0)
toolbarLayout.FillDirection = Enum.FillDirection.Horizontal
toolbarLayout.FillDirectionMaxCells = 8
toolbarLayout.SortOrder = Enum.SortOrder.LayoutOrder
toolbarLayout.Parent = toolbar

local filters = Instance.new("Frame")
filters.Name = "Filters"
filters.BackgroundTransparency = 1
filters.BorderSizePixel = 0
filters.Position = UDim2.new(0, 6, 0, 88)
filters.Size = UDim2.new(1, -12, 0, 29)
filters.ZIndex = 2
filters.Parent = Page

local function makeFilterButton(name, text, position, width)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = colours.button
	button.BorderSizePixel = 0
	button.Font = Enum.Font.SourceSans
	button.Position = position
	button.Size = UDim2.new(0, width, 1, 0)
	button.Text = text
	button.TextColor3 = colours.text
	button.TextSize = 14
	button.ZIndex = 3
	button.Parent = filters
	addCorner(button, 4)
	addStroke(button)
	return button
end

local sendFilter = makeFilterButton("Send", "Send  ON", UDim2.new(), 88)
local receiveFilter = makeFilterButton("Receive", "Receive  ON", UDim2.new(0, 93, 0, 0), 98)

local search = Instance.new("TextBox")
search.Name = "Search"
search.BackgroundColor3 = colours.input
search.BorderSizePixel = 0
search.ClearTextOnFocus = false
search.Font = Enum.Font.SourceSans
search.PlaceholderColor3 = colours.muted
search.PlaceholderText = "Filter by packet ID or captured payload text ..."
search.Position = UDim2.new(0, 196, 0, 0)
search.Size = UDim2.new(1, -196, 1, 0)
search.Text = ""
search.TextColor3 = colours.text
search.TextSize = 14
search.TextXAlignment = Enum.TextXAlignment.Left
search.ZIndex = 3
search.Parent = filters
addCorner(search, 4)
addStroke(search)

local searchPadding = Instance.new("UIPadding")
searchPadding.PaddingLeft = UDim.new(0, 9)
searchPadding.PaddingRight = UDim.new(0, 9)
searchPadding.Parent = search

local header = Instance.new("Frame")
header.Name = "Header"
header.BackgroundColor3 = colours.panel
header.BorderSizePixel = 0
header.Position = UDim2.new(0, 6, 0, 122)
header.Size = UDim2.new(1, -12, 0, 23)
header.ZIndex = 2
header.Parent = Page
addCorner(header, 3)

local directionHeader = makeLabel(header, "Direction", "Direction", UDim2.new(0, 8, 0, 0), UDim2.new(0.1, -8, 1, 0), 13)
local packetHeader = makeLabel(header, "Packet", "Packet ID", UDim2.new(0.1, 4, 0, 0), UDim2.new(0.15, -4, 1, 0), 13)
local transportHeader =
	makeLabel(header, "Transport", "Transport metadata", UDim2.new(0.25, 4, 0, 0), UDim2.new(0.32, -4, 1, 0), 13)
local previewHeader =
	makeLabel(header, "Preview", "Payload preview", UDim2.new(0.57, 4, 0, 0), UDim2.new(0.43, -12, 1, 0), 13)

for _, label in ipairs({ directionHeader, packetHeader, transportHeader, previewHeader }) do
	label.TextColor3 = colours.muted
end

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Packets"
scroll.Active = true
scroll.BackgroundColor3 = colours.input
scroll.BorderSizePixel = 0
scroll.BottomImage = ""
scroll.CanvasPosition = Vector2.new()
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.MidImage = ""
scroll.Position = UDim2.new(0, 6, 0, 150)
scroll.ScrollBarImageColor3 = Color3.fromRGB(95, 95, 95)
scroll.ScrollBarThickness = 7
scroll.Size = UDim2.new(1, -12, 1, -180)
scroll.TopImage = ""
scroll.ZIndex = 2
scroll.Parent = Page
addCorner(scroll, 4)
addStroke(scroll)

local rowsPadding = Instance.new("UIPadding")
rowsPadding.PaddingBottom = UDim.new(0, 4)
rowsPadding.PaddingLeft = UDim.new(0, 4)
rowsPadding.PaddingRight = UDim.new(0, 4)
rowsPadding.PaddingTop = UDim.new(0, 4)
rowsPadding.Parent = scroll

local rowsLayout = Instance.new("UIListLayout")
rowsLayout.Padding = UDim.new(0, ROW_GAP)
rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
rowsLayout.Parent = scroll

local footer =
	makeLabel(Page, "Footer", "No RakNet packets captured", UDim2.new(0, 8, 1, -27), UDim2.new(1, -16, 0, 22), 14)
footer.TextColor3 = colours.muted

local function updateResponsiveLayout()
	if not alive or not Page.Parent then
		return
	end

	local pageWidth = Page.AbsoluteSize.X
	local compactWidth = pageWidth > 0 and pageWidth < 900
	local warningHeight = compactWidth and 62 or 44
	local toolbarTop = warningHeight + 10
	local toolbarColumns = compactWidth and 4 or 8
	local toolbarRows = math.ceil(8 / toolbarColumns)
	local toolbarHeight = toolbarRows * 29 + math.max(0, toolbarRows - 1) * 4
	local toolbarWidth = math.max(1, pageWidth - 12)
	local toolbarCellWidth = math.max(88, math.floor((toolbarWidth - (toolbarColumns - 1) * 4) / toolbarColumns))
	local filtersTop = toolbarTop + toolbarHeight + 5
	local headerTop = filtersTop + 34
	local scrollTop = headerTop + 28

	warning.Size = UDim2.new(1, -12, 0, warningHeight)
	toolbar.Position = UDim2.new(0, 6, 0, toolbarTop)
	toolbar.Size = UDim2.new(1, -12, 0, toolbarHeight)
	toolbarLayout.FillDirectionMaxCells = toolbarColumns
	toolbarLayout.CellSize = UDim2.new(0, toolbarCellWidth, 0, 29)
	filters.Position = UDim2.new(0, 6, 0, filtersTop)
	header.Position = UDim2.new(0, 6, 0, headerTop)
	scroll.Position = UDim2.new(0, 6, 0, scrollTop)
	scroll.Size = UDim2.new(1, -12, 1, -(scrollTop + 30))
end

trackConnection(Page:GetPropertyChangedSignal("AbsoluteSize"):Connect(updateResponsiveLayout))
task.defer(updateResponsiveLayout)

local selectedEntry
local activeViewer
local viewerGeneration = 0
local rows = {}
local showSend = true
local showReceive = true
local renderQueued = false
local forceTopOnRender = true
local followingTop = true
local settingCanvasPosition = false
local renderedCount = 0
local searchCache = setmetatable({}, { __mode = "k" })
local renderDirty = true

local actionButtons = {}

local lifecycle = {
	Connected = true,
}

function lifecycle:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false
	alive = false
	viewerGeneration = viewerGeneration + 1

	if activeViewer then
		TextViewer.Hide(activeViewer)
	end

	activeViewer = nil
end

trackConnection(lifecycle)

local function hideViewer()
	viewerGeneration = viewerGeneration + 1
	local viewer = activeViewer
	activeViewer = nil

	if viewer then
		TextViewer.Hide(viewer)
	end
end

local function showViewer(title, text, actions)
	if not alive or not Page.Parent then
		return nil, viewerGeneration
	end

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

			if viewerGeneration == generation then
				viewerGeneration = viewerGeneration + 1
			end
		end,
	})
	activeViewer = viewer
	return viewer, generation
end

local function copyText(text)
	if type(setClipboard) ~= "function" then
		return false, "Clipboard access is unavailable"
	end

	local ran, err = pcall(setClipboard, text)
	return ran, ran and nil or safeString(err)
end

local function payloadBytes(entry)
	if type(entry) ~= "table" then
		return nil
	elseif type(entry.PayloadBytes) == "string" then
		return entry.PayloadBytes
	elseif type(entry.PreviewBytes) == "string" then
		return entry.PreviewBytes
	elseif type(entry.AsString) == "string" then
		return entry.AsString
	end
end

local function escapedText(bytes, maximum)
	if type(bytes) ~= "string" then
		return "(payload bytes unavailable)"
	end

	local shown = math.min(#bytes, maximum)
	local parts = {}

	for index = 1, shown do
		local byte = bytes:byte(index)

		if byte == 10 then
			parts[#parts + 1] = "\\n"
		elseif byte == 13 then
			parts[#parts + 1] = "\\r"
		elseif byte == 9 then
			parts[#parts + 1] = "\\t"
		elseif byte == 92 then
			parts[#parts + 1] = "\\\\"
		elseif byte >= 32 and byte <= 126 then
			parts[#parts + 1] = string.char(byte)
		else
			parts[#parts + 1] = ("\\x%02X"):format(byte)
		end
	end

	if #bytes > shown then
		parts[#parts + 1] = (" ... (%d/%d bytes shown)"):format(shown, #bytes)
	end

	return table.concat(parts)
end

local function compactPreview(entry)
	local bytes = payloadBytes(entry)

	if not bytes then
		return entry.PayloadState == "truncated" and "<payload truncated>" or "<payload unavailable>"
	end

	local shown = math.min(#bytes, 120)
	local parts = table.create and table.create(shown) or {}

	for index = 1, shown do
		local byte = bytes:byte(index)
		parts[index] = byte >= 32 and byte <= 126 and string.char(byte) or "."
	end

	local preview = table.concat(parts)

	if #bytes > shown then
		preview = preview .. "..."
	end

	return preview ~= "" and preview or "<empty payload>"
end

local function hexDump(bytes, maximum)
	if type(bytes) ~= "string" then
		return "(payload bytes unavailable)"
	end

	local shown = math.min(#bytes, maximum)
	local lines = {}

	for first = 1, shown, 16 do
		local hex = {}
		local ascii = {}
		local last = math.min(shown, first + 15)

		for index = first, last do
			local byte = bytes:byte(index)
			hex[#hex + 1] = ("%02X"):format(byte)
			ascii[#ascii + 1] = byte >= 32 and byte <= 126 and string.char(byte) or "."
		end

		lines[#lines + 1] = ("%08X  %-47s  |%s|"):format(first - 1, table.concat(hex, " "), table.concat(ascii))
	end

	if #bytes == 0 then
		lines[1] = "(empty payload)"
	elseif #bytes > shown then
		lines[#lines + 1] = ("... %d of %d bytes shown (preview cap)"):format(shown, #bytes)
	end

	return table.concat(lines, "\n")
end

local function arrayPreview(bytes, maximum)
	if type(bytes) ~= "string" then
		return "(payload bytes unavailable)"
	end

	local shown = math.min(#bytes, maximum)
	local lines = {}

	for first = 1, shown, 16 do
		local values = {}

		for index = first, math.min(shown, first + 15) do
			values[#values + 1] = tostring(bytes:byte(index))
		end

		lines[#lines + 1] = ("[%04d] %s"):format(first, table.concat(values, ", "))
	end

	if #bytes == 0 then
		lines[1] = "(empty payload)"
	elseif #bytes > shown then
		lines[#lines + 1] = ("... %d of %d byte values shown (preview cap)"):format(shown, #bytes)
	end

	return table.concat(lines, "\n")
end

local function timestampText(timestamp)
	if type(timestamp) ~= "number" then
		return "unknown"
	end

	local ran, calendar = pcall(function()
		return os.date("!%Y-%m-%d %H:%M:%S", math.floor(timestamp))
	end)

	if ran and calendar then
		return ("%.3f (%s UTC)"):format(timestamp, calendar)
	end

	return ("%.3f"):format(timestamp)
end

local function appendFieldErrors(lines, entry)
	local hasFieldErrors = type(entry.FieldErrors) == "table" and next(entry.FieldErrors) ~= nil

	if not hasFieldErrors and entry.PayloadError == nil then
		return
	end

	local names = {}

	if hasFieldErrors then
		for name in pairs(entry.FieldErrors) do
			names[#names + 1] = safeString(name)
		end
	end

	table.sort(names)
	lines[#lines + 1] = ""
	lines[#lines + 1] = "CAPTURE FIELD ERRORS"

	for _, name in ipairs(names) do
		lines[#lines + 1] = ("  %s: %s"):format(name, safeString(entry.FieldErrors[name]))
	end

	if entry.PayloadError then
		lines[#lines + 1] = "  Payload: " .. safeString(entry.PayloadError)
	end
end

local function describeEntry(entry)
	local bytes = payloadBytes(entry)
	local textLimit = settingNumber({ "MaxRakNetTextPreviewBytes" }, DEFAULT_TEXT_PREVIEW, 64, 65536)
	local hexLimit = settingNumber({ "MaxRakNetHexPreviewBytes", "MaxHexBytes" }, DEFAULT_HEX_PREVIEW, 64, 65536)
	local arrayLimit = settingNumber({ "MaxRakNetArrayPreviewBytes" }, DEFAULT_ARRAY_PREVIEW, 16, 8192)
	local lines = {
		"RAKNET PACKET DETAILS",
		"",
		"Direction: " .. safeString(entry.Direction),
		"Sequence: " .. safeString(entry.Sequence),
		"Packet ID: " .. safeString(entry.PacketId),
		"Reported size: " .. safeString(entry.Size),
		"Stored payload bytes: " .. safeString(entry.StoredBytes),
		"Priority: " .. safeString(entry.Priority),
		"Reliability: " .. safeString(entry.Reliability),
		"Ordering channel: " .. safeString(entry.OrderingChannel),
		"Captured: " .. timestampText(entry.Timestamp),
		"Payload state: " .. safeString(entry.PayloadState),
		"Payload complete: " .. safeString(entry.PayloadComplete == true),
		"Replayable outgoing send: " .. safeString(entry.Replayable == true),
		"",
		"TEXT PREVIEW (escaped, capped)",
		escapedText(bytes, textLimit),
		"",
		"HEX PREVIEW (capped)",
		hexDump(bytes, hexLimit),
		"",
		"BYTE ARRAY PREVIEW (capped)",
		arrayPreview(bytes, arrayLimit),
	}

	appendFieldErrors(lines, entry)
	return table.concat(lines, "\n")
end

local function describeHex(entry)
	local bytes = payloadBytes(entry)
	local maximum = settingNumber({ "MaxRakNetHexPreviewBytes", "MaxHexBytes" }, 4096, 64, 65536)

	return table.concat({
		"RAKNET PAYLOAD HEX",
		("Packet %s | %s | state %s | %s captured bytes"):format(
			safeString(entry.PacketId),
			safeString(entry.Direction),
			safeString(entry.PayloadState),
			safeString(entry.StoredBytes)
		),
		"",
		hexDump(bytes, maximum),
	}, "\n")
end

local function capabilityState(capabilities, availableName, installedName)
	if capabilities[installedName] then
		return "installed"
	elseif capabilities[availableName] then
		return "available, registration failed"
	end

	return "unavailable"
end

local function describeDiagnostics()
	local capabilities = Methods.Capabilities or {}
	local diagnostics = Methods.Diagnostics or {}
	local lines = {
		"RAKNET SPY DIAGNOSTICS",
		"",
		"Potassium RakNet enabled/connected: " .. safeString(Methods.Connected == true),
		"Capture state: " .. (Methods.Enabled and "running" or "paused"),
		"Send hook: " .. capabilityState(capabilities, "SendHook", "SendHookInstalled"),
		"Receive hook: " .. capabilityState(capabilities, "ReceiveHook", "ReceiveHookInstalled"),
		"raknet.send: " .. (capabilities.Send and "available" or "unavailable"),
		"Buffer snapshot APIs: " .. (capabilities.Buffer and "available" or "unavailable"),
		"",
		"CAPTURE COUNTERS",
	}

	local names = {}
	local detailedErrors = {
		LastCaptureError = true,
		LastReplayError = true,
		LastHookError = true,
	}

	for name, value in pairs(diagnostics) do
		if type(value) ~= "table" and not detailedErrors[name] then
			names[#names + 1] = name
		end
	end

	table.sort(names)

	for _, name in ipairs(names) do
		lines[#lines + 1] = ("  %-28s %s"):format(name .. ":", safeString(diagnostics[name]))
	end

	for _, name in ipairs({ "LastCaptureError", "LastReplayError", "LastHookError" }) do
		local value = diagnostics[name]

		if type(value) == "table" then
			lines[#lines + 1] = ("  %s: %s / %s"):format(name, safeString(value.Stage), safeString(value.Error))
		elseif value ~= nil then
			lines[#lines + 1] = ("  %s: %s"):format(name, safeString(value))
		end
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "POTASSIUM WARNING"
	lines[#lines + 1] =
		"Enable RakNet in Potassium's Miscellaneous options before use. Potassium warns that RakNet interception can result in a ban. Use only in experiences you own or are authorised to test."
	lines[#lines + 1] = "Docs: https://docs.potassium.pro/api-reference/RakNet%20Library/"

	return table.concat(lines, "\n")
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

local function buildSelectedCode(entry)
	local ran, scriptText, buildError = pcall(Methods.BuildScript, entry)

	if not ran then
		return nil, safeString(scriptText)
	elseif type(scriptText) ~= "string" or scriptText == "" then
		return nil, safeString(buildError or "Code could not be generated for this packet")
	end

	return scriptText
end

local function showCode()
	local entry = selectedEntry

	if not entry then
		return
	end

	local _, generation = showViewer("RakNet Code", "Generating bounded RakNet code ...")
	task.spawn(function()
		if not alive or not Page.Parent then
			return
		end

		local scriptText, buildError = buildSelectedCode(entry)

		if not alive or not Page.Parent or selectedEntry ~= entry or viewerGeneration ~= generation then
			return
		elseif not scriptText then
			showViewer("RakNet Code Unavailable", buildError)
		else
			showViewer(
				entry.Direction == "receive" and "RakNet Receive Template" or "RakNet Send Replay Code",
				scriptText
			)
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
		if not alive or not Page.Parent then
			return
		end

		local scriptText, buildError = buildSelectedCode(entry)

		if not alive or not Page.Parent or selectedEntry ~= entry then
			return
		elseif not scriptText then
			setStatus("RakNet code unavailable")
			showViewer("RakNet Code Unavailable", buildError)
			return
		end

		local copied, copyError = copyText(scriptText)

		if copied then
			setStatus(entry.Direction == "receive" and "RakNet receive template copied" or "RakNet replay code copied")
		else
			setStatus("RakNet code copy failed")
			showViewer("Copy Failed", copyError)
		end
	end)
end

local function showReplayConfirmation()
	local entry = selectedEntry

	if not entry or entry.Direction ~= "send" or not entry.Replayable then
		return
	end

	local started = false
	local confirmation = table.concat({
		("Replay outgoing RakNet packet %s with %s captured bytes?"):format(
			safeString(entry.PacketId),
			safeString(entry.StoredBytes)
		),
		"",
		("Priority %s | Reliability %s | Ordering channel %s"):format(
			safeString(entry.Priority),
			safeString(entry.Reliability),
			safeString(entry.OrderingChannel)
		),
		"",
		"This sends the complete captured payload back through raknet.send and can change game state.",
		"Potassium warns that RakNet interception/replay can result in a ban. Continue only where authorised.",
	}, "\n")

	showViewer("Confirm RakNet Replay", confirmation, {
		{
			Label = "Replay",
			Width = 96,
			Callback = function()
				if started then
					return
				end

				started = true
				local _, replayGeneration =
					showViewer("Replaying RakNet Packet", "Sending the captured outgoing payload ...")
				setStatus("Replaying RakNet packet ...")

				task.spawn(function()
					if not alive or not Page.Parent then
						return
					end

					local ran, succeeded, replayError = pcall(Methods.Replay, entry)

					if not ran then
						replayError = succeeded
						succeeded = false
					end

					if
						not alive
						or not Page.Parent
						or selectedEntry ~= entry
						or viewerGeneration ~= replayGeneration
					then
						return
					elseif succeeded then
						setStatus("RakNet packet replayed")
						showViewer(
							"RakNet Replay Complete",
							("Outgoing packet %s was passed to raknet.send."):format(safeString(entry.PacketId))
						)
					else
						setStatus("RakNet replay failed")
						showViewer("RakNet Replay Failed", safeString(replayError or "raknet.send failed"))
					end
				end)
			end,
		},
		{ Label = "Cancel", Width = 96, Callback = hideViewer },
	})
end

local function showDiagnostics()
	showViewer("RakNet Diagnostics", describeDiagnostics())
end

local function updateWarning()
	local capabilities = Methods.Capabilities or {}
	local sendInstalled = capabilities.SendHookInstalled == true
	local receiveInstalled = capabilities.ReceiveHookInstalled == true
	local state

	if sendInstalled and receiveInstalled then
		state = Methods.Enabled and "SEND + RECEIVE CAPTURE ACTIVE" or "CAPTURE PAUSED"
		warning.TextColor3 = Methods.Enabled and colours.good or colours.warning
	elseif sendInstalled then
		state = "PARTIAL SUPPORT: SEND CAPTURE ONLY"
		warning.TextColor3 = colours.warning
	elseif receiveInstalled then
		state = "PARTIAL SUPPORT: RECEIVE CAPTURE ONLY"
		warning.TextColor3 = colours.warning
	else
		state = "RAKNET UNAVAILABLE"
		warning.TextColor3 = colours.error
	end

	warning.Text = state
		.. "  •  Potassium warning: enable RakNet in Miscellaneous options; interception/replay can result in a ban. Use only where authorised."
	setButtonText(actionButtons.Pause, Methods.Enabled and "Pause" or "Resume")
	setButtonEnabled(actionButtons.Pause, Methods.Connected == true)
end

local function updateSelectionStyles()
	for index, row in ipairs(rows) do
		if row.Button.Visible then
			if row.Entry == selectedEntry then
				row.Button.BackgroundColor3 = colours.rowSelected
			else
				row.Button.BackgroundColor3 = index % 2 == 0 and colours.rowAlternate or colours.row
			end
		end
	end
end

local function updateActions()
	local hasSelection = selectedEntry ~= nil
	local bytes = hasSelection and payloadBytes(selectedEntry) or nil

	setButtonEnabled(actionButtons.Clear, #Methods.Logs > 0)
	setButtonEnabled(actionButtons.Details, hasSelection)
	setButtonEnabled(actionButtons.Hex, type(bytes) == "string")
	setButtonEnabled(actionButtons.Code, hasSelection)
	setButtonEnabled(actionButtons.CopyCode, hasSelection)
	setButtonEnabled(
		actionButtons.Replay,
		hasSelection and selectedEntry.Direction == "send" and selectedEntry.Replayable == true
	)
	setButtonEnabled(actionButtons.Diagnostics, true)

	if hasSelection and selectedEntry.Direction == "receive" then
		setButtonText(actionButtons.Code, "Receive Template")
		setButtonText(actionButtons.CopyCode, "Copy Template")
	else
		setButtonText(actionButtons.Code, "Code")
		setButtonText(actionButtons.CopyCode, "Copy Code")
	end

	updateSelectionStyles()
end

local function selectEntry(entry)
	selectedEntry = entry
	updateActions()

	if entry then
		footer.Text = ("Selected packet %s • %s • payload %s"):format(
			safeString(entry.PacketId),
			safeString(entry.Direction),
			safeString(entry.PayloadState)
		)
	end
end

local function makeRow(index)
	local button = Instance.new("TextButton")
	button.Name = "PacketRow" .. index
	button.AutoButtonColor = false
	button.BackgroundColor3 = colours.row
	button.BorderSizePixel = 0
	button.LayoutOrder = index
	button.Size = UDim2.new(1, -1, 0, ROW_HEIGHT)
	button.Text = ""
	button.Visible = false
	button.ZIndex = 3
	button.Parent = scroll
	addCorner(button, 3)

	local direction = makeLabel(button, "Direction", "", UDim2.new(0, 7, 0, 1), UDim2.new(0.1, -7, 0, 20), 14)
	direction.Font = Enum.Font.SourceSansBold

	local packet = makeLabel(button, "Packet", "", UDim2.new(0.1, 4, 0, 1), UDim2.new(0.15, -4, 0, 20), 14)
	packet.Font = Enum.Font.SourceSansSemibold

	local transport = makeLabel(button, "Transport", "", UDim2.new(0.25, 4, 0, 1), UDim2.new(0.32, -4, 0, 20), 13)
	transport.TextColor3 = colours.muted

	local preview = makeLabel(button, "Preview", "", UDim2.new(0.57, 4, 0, 1), UDim2.new(0.43, -12, 0, 20), 13)
	preview.Font = Enum.Font.Code

	local subline = makeLabel(button, "Subline", "", UDim2.new(0.1, 4, 0, 20), UDim2.new(0.9, -12, 0, 19), 12)
	subline.TextColor3 = colours.muted

	local row = {
		Button = button,
		Direction = direction,
		Packet = packet,
		Transport = transport,
		Preview = preview,
		Subline = subline,
		Entry = nil,
	}

	trackConnection(button.MouseEnter:Connect(function()
		if row.Entry ~= selectedEntry then
			button.BackgroundColor3 = colours.buttonHover
		end
	end))

	trackConnection(button.MouseLeave:Connect(function()
		if row.Entry == selectedEntry then
			button.BackgroundColor3 = colours.rowSelected
		else
			button.BackgroundColor3 = index % 2 == 0 and colours.rowAlternate or colours.row
		end
	end))

	trackConnection(button.MouseButton1Click:Connect(function()
		if row.Entry then
			selectEntry(row.Entry)
		end
	end))

	rows[index] = row
	return row
end

local function fillRow(row, entry, displayIndex)
	row.Entry = entry
	row.Button.LayoutOrder = displayIndex
	row.Button.Visible = true
	row.Direction.Text = entry.Direction == "send" and "SEND →" or "← RECEIVE"
	row.Direction.TextColor3 = entry.Direction == "send" and colours.send or colours.receive
	row.Packet.Text = safeString(entry.PacketId)
	row.Transport.Text = ("P %s  R %s  Ch %s"):format(
		safeString(entry.Priority),
		safeString(entry.Reliability),
		safeString(entry.OrderingChannel)
	)
	row.Preview.Text = compactPreview(entry)
	row.Subline.Text = ("%s bytes • %s • seq %s • %.3f"):format(
		safeString(entry.Size or entry.StoredBytes),
		safeString(entry.PayloadState),
		safeString(entry.Sequence),
		type(entry.Timestamp) == "number" and entry.Timestamp or 0
	)
	row.Button.BackgroundColor3 = entry == selectedEntry and colours.rowSelected
		or (displayIndex % 2 == 0 and colours.rowAlternate or colours.row)
end

local function matchesFilters(entry, query)
	if entry.Direction == "send" and not showSend then
		return false
	elseif entry.Direction == "receive" and not showReceive then
		return false
	elseif query == "" then
		return true
	end

	local searchable = searchCache[entry]

	if not searchable then
		local bytes = payloadBytes(entry)
		local searchLimit = settingNumber({ "MaxRakNetSearchBytes" }, 4096, 64, 65536)
		searchable = table
			.concat({
				safeString(entry.PacketId),
				safeString(entry.Direction),
				safeString(entry.Priority),
				safeString(entry.Reliability),
				safeString(entry.OrderingChannel),
				safeString(entry.PayloadState),
				type(bytes) == "string" and bytes:sub(1, searchLimit) or "",
			}, " ")
			:lower()
		searchCache[entry] = searchable
	end

	return searchable:find(query, 1, true) ~= nil
end

local function selectionIsRetained(entry, total)
	if not entry or total <= 0 then
		return false
	end

	local sequence = tonumber(entry.Sequence)
	local oldest = Methods.Logs[1]
	local newest = Methods.Logs[total]
	local oldestSequence = oldest and tonumber(oldest.Sequence)
	local newestSequence = newest and tonumber(newest.Sequence)

	if sequence and oldestSequence and newestSequence then
		return sequence >= oldestSequence and sequence <= newestSequence
	end

	for index = 1, total do
		if Methods.Logs[index] == entry then
			return true
		end
	end

	return false
end

local function renderNow()
	renderQueued = false

	if not alive or not Page.Parent or not Page.Visible then
		renderDirty = true
		return
	end

	renderDirty = false
	local oldPosition = scroll.CanvasPosition
	local anchorSequence
	local anchorDisplayIndex
	local anchorOffset = 0
	local rowStride = ROW_HEIGHT + ROW_GAP

	if not followingTop and renderedCount > 0 then
		anchorDisplayIndex = math.max(1, math.min(renderedCount, math.floor(oldPosition.Y / rowStride) + 1))
		local anchor = rows[anchorDisplayIndex]

		if anchor and anchor.Entry then
			anchorSequence = anchor.Entry.Sequence
			anchorOffset = oldPosition.Y - (anchorDisplayIndex - 1) * rowStride
		end
	end

	local query = search.Text:lower():match("^%s*(.-)%s*$") or ""
	local maximum = settingNumber(
		{ "MaxRenderedRakNetLogs", "MaxRakNetRenderedLogs", "MaxRenderedLogs" },
		DEFAULT_RENDER_LIMIT,
		10,
		500
	)
	local total = #Methods.Logs

	if selectedEntry and not selectionIsRetained(selectedEntry, total) then
		selectedEntry = nil
		hideViewer()
	end

	local matching = 0
	local shown = 0
	local newAnchorIndex
	local windowStart = 1

	local function showEntry(entry)
		shown = shown + 1
		local row = rows[shown] or makeRow(shown)
		fillRow(row, entry, shown)

		if anchorSequence ~= nil and entry.Sequence == anchorSequence then
			newAnchorIndex = shown
		end
	end

	if query == "" and showSend and showReceive then
		matching = total
		local newestLogIndex = total

		if anchorSequence ~= nil and anchorDisplayIndex then
			local anchorLogIndex

			for logIndex = total, 1, -1 do
				local entry = Methods.Logs[logIndex]

				if entry and entry.Sequence == anchorSequence then
					anchorLogIndex = logIndex
					break
				end
			end

			if anchorLogIndex then
				newestLogIndex = math.min(total, anchorLogIndex + anchorDisplayIndex - 1)
				windowStart = total - newestLogIndex + 1
			end
		end

		for logIndex = newestLogIndex, math.max(1, newestLogIndex - maximum + 1), -1 do
			local entry = Methods.Logs[logIndex]

			if entry then
				showEntry(entry)
			end
		end
	else
		local matches = {}
		local anchorMatchIndex

		for logIndex = total, 1, -1 do
			local entry = Methods.Logs[logIndex]

			if entry and matchesFilters(entry, query) then
				matches[#matches + 1] = entry

				if anchorSequence ~= nil and entry.Sequence == anchorSequence then
					anchorMatchIndex = #matches
				end
			end
		end

		matching = #matches

		if anchorMatchIndex and anchorDisplayIndex then
			windowStart = math.max(1, anchorMatchIndex - anchorDisplayIndex + 1)
		end

		for matchIndex = windowStart, math.min(matching, windowStart + maximum - 1) do
			showEntry(matches[matchIndex])
		end
	end

	for index = shown + 1, #rows do
		rows[index].Entry = nil
		rows[index].Button.Visible = false
	end

	renderedCount = shown
	local newerOutside = math.max(0, windowStart - 1)
	local olderOutside = math.max(0, matching - newerOutside - shown)
	local suffix = ""

	if newerOutside > 0 or olderOutside > 0 then
		suffix = (" • %d newer / %d older outside this window"):format(newerOutside, olderOutside)
	end

	footer.Text = ("Showing %d of %d matching • %d captured • newest first%s"):format(
		shown,
		matching,
		total,
		suffix
	)
	updateActions()

	local shouldForceTop = forceTopOnRender
	forceTopOnRender = false
	task.defer(function()
		if not alive or not scroll.Parent then
			return
		end

		local targetY

		if shouldForceTop or followingTop then
			targetY = 0
		elseif newAnchorIndex then
			targetY = (newAnchorIndex - 1) * rowStride + anchorOffset
		else
			targetY = oldPosition.Y
		end

		local maximumY = math.max(0, rowsLayout.AbsoluteContentSize.Y + 8 - scroll.AbsoluteSize.Y)
		settingCanvasPosition = true
		scroll.CanvasPosition = Vector2.new(0, math.max(0, math.min(targetY, maximumY)))
		settingCanvasPosition = false
	end)
end

local function queueRender(forceTop)
	if not alive or not Page.Parent then
		return
	end

	if forceTop then
		forceTopOnRender = true
		followingTop = true
	end

	renderDirty = true

	if not Page.Visible then
		return
	end

	if renderQueued then
		return
	end

	renderQueued = true
	task.defer(renderNow)
end

trackConnection(rowsLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
	scroll.CanvasSize = UDim2.new(0, 0, 0, rowsLayout.AbsoluteContentSize.Y + 8)
end))

trackConnection(scroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
	if not settingCanvasPosition then
		local wasFollowingTop = followingTop
		followingTop = scroll.CanvasPosition.Y <= TOP_PIN_THRESHOLD

		if followingTop and not wasFollowingTop then
			queueRender(true)
		end
	end
end))

local searchGeneration = 0
trackConnection(search:GetPropertyChangedSignal("Text"):Connect(function()
	searchGeneration = searchGeneration + 1
	local generation = searchGeneration

	task.delay(0.12, function()
		if alive and generation == searchGeneration and search.Parent then
			queueRender(true)
		end
	end)
end))

trackConnection(sendFilter.MouseButton1Click:Connect(function()
	showSend = not showSend
	sendFilter.Text = showSend and "Send  ON" or "Send  OFF"
	sendFilter.TextColor3 = showSend and colours.send or colours.muted
	queueRender(true)
end))

trackConnection(receiveFilter.MouseButton1Click:Connect(function()
	showReceive = not showReceive
	receiveFilter.Text = showReceive and "Receive  ON" or "Receive  OFF"
	receiveFilter.TextColor3 = showReceive and colours.receive or colours.muted
	queueRender(true)
end))

sendFilter.TextColor3 = colours.send
receiveFilter.TextColor3 = colours.receive

actionButtons.Pause = makeActionButton(toolbar, "Pause", "Pause", icons.pause, 1, function()
	local ran, result = pcall(Methods.SetEnabled, not Methods.Enabled)

	if not ran then
		showViewer("RakNet Capture Error", safeString(result))
	end

	updateWarning()
end)

actionButtons.Clear = makeActionButton(toolbar, "Clear", "Clear", icons.clear, 2, function()
	local ran, err = pcall(Methods.Clear)

	if not ran then
		showViewer("RakNet Clear Failed", safeString(err))
		return
	end

	selectedEntry = nil
	hideViewer()
	queueRender(true)
end)

actionButtons.Details = makeActionButton(toolbar, "Details", "Details", icons.details, 3, showDetails)
actionButtons.Hex = makeActionButton(toolbar, "Hex", "Hex", icons.hex, 4, showHex)
actionButtons.Code = makeActionButton(toolbar, "Code", "Code", icons.code, 5, showCode)
actionButtons.CopyCode = makeActionButton(toolbar, "CopyCode", "Copy Code", icons.copy, 6, copyCode)
actionButtons.Replay = makeActionButton(toolbar, "Replay", "Replay", icons.replay, 7, showReplayConfirmation)
actionButtons.Diagnostics =
	makeActionButton(toolbar, "Diagnostics", "Diagnostics", icons.diagnostics, 8, showDiagnostics)

trackConnection(Page:GetPropertyChangedSignal("Visible"):Connect(function()
	if Page.Visible then
		queueRender(false)
	else
		hideViewer()
	end
end))

local packetRenderScheduled = false
local eventConnection = Methods.ConnectEvent(function(_entry, action)
	if action == "cleared" then
		selectedEntry = nil
		hideViewer()
		queueRender(true)
	elseif action == "added" then
		if not Page.Visible then
			renderDirty = true
		elseif not packetRenderScheduled then
			packetRenderScheduled = true
			local delaySeconds = search.Text == "" and 0.05 or 0.15
			task.delay(delaySeconds, function()
				packetRenderScheduled = false

				if not alive or not Page.Parent then
					return
				elseif not Page.Visible then
					renderDirty = true
					return
				end

				queueRender(false)
			end)
		end
	elseif action == "paused" or action == "resumed" or action == "disconnected" then
		updateWarning()
		queueRender(false)
	end
end)
trackConnection(eventConnection)

local Tab = createTab()
trackInstance(Tab)

if not TabSelector.RegisterTab("RakNetSpy", Tab, Page) then
	Page:Destroy()
	Tab:Destroy()
	return RakNetSpy
end

updateWarning()
queueRender(true)

RakNetSpy.Page = Page
RakNetSpy.Tab = Tab
RakNetSpy.Select = selectEntry
RakNetSpy.Refresh = function()
	queueRender(false)
end

return RakNetSpy
