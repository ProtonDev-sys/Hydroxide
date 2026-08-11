local RakNetSpy = {}

local packValues = table.pack or function(...)
	return { n = select("#", ...), ... }
end
local unpackValues = table.unpack or unpack

local DEFAULT_MAX_LOGS = 500
local DEFAULT_MAX_PACKET_BYTES = 65536
local DEFAULT_MAX_HISTORY_BYTES = 4194304
local DEFAULT_MAX_GENERATED_OUTPUT_BYTES = 1048576

local settings = type(oh) == "table" and type(oh.Settings) == "table" and oh.Settings or {}

local function settingNumber(names, defaultValue, minimum, maximum)
	local value

	for _, name in ipairs(names) do
		if settings[name] ~= nil then
			value = tonumber(settings[name])
			break
		end
	end

	value = math.floor(value or defaultValue)
	return math.max(minimum, math.min(maximum, value))
end

local maxLogs = settingNumber({ "MaxRakNetLogs", "maxRakNetLogs" }, DEFAULT_MAX_LOGS, 1, 5000)
local maxPacketBytes = settingNumber(
	{ "MaxRakNetPacketBytes", "MaxRakNetPayloadBytes", "maxRakNetPacketBytes", "maxRakNetPayloadBytes" },
	DEFAULT_MAX_PACKET_BYTES,
	1,
	16777216
)
local maxHistoryBytes = settingNumber(
	{ "MaxRakNetHistoryBytes", "MaxRakNetTotalBytes", "maxRakNetHistoryBytes", "maxRakNetTotalBytes" },
	DEFAULT_MAX_HISTORY_BYTES,
	1,
	67108864
)
local maxGeneratedOutputBytes = settingNumber({
	"MaxRakNetGeneratedOutputBytes",
	"maxRakNetGeneratedOutputBytes",
	"MaxGeneratedOutputBytes",
	"maxGeneratedOutputBytes",
}, DEFAULT_MAX_GENERATED_OUTPUT_BYTES, 1024, 8388608)

local diagnostics = {
	Callbacks = 0,
	PacketsCaptured = 0,
	SendPacketsCaptured = 0,
	ReceivePacketsCaptured = 0,
	PacketsSkippedPaused = 0,
	CaptureErrors = 0,
	PayloadFailures = 0,
	PayloadTruncations = 0,
	LogsDropped = 0,
	BytesDropped = 0,
	HistoryBytes = 0,
	EventErrors = 0,
	ReplayAttempts = 0,
	ReplaySuccesses = 0,
	ReplayFailures = 0,
	SendHookRegisterErrors = 0,
	ReceiveHookRegisterErrors = 0,
	SendHookRemoveErrors = 0,
	ReceiveHookRemoveErrors = 0,
	LastCaptureError = nil,
	LastReplayError = nil,
	LastHookError = nil,
}

local function safeError(value)
	local ran, result = pcall(tostring, value)
	return ran and result or "<unprintable error>"
end

local function createHistory(capacity, byteCapacity)
	local storage = {}
	local head = 1
	local count = 0
	local storedBytes = 0
	local methods = {}
	local proxy = {}

	local function physicalIndex(logicalIndex)
		return ((head + logicalIndex - 2) % capacity) + 1
	end

	local function popOldest()
		if count == 0 then
			return nil
		end

		local entry = storage[head]
		storage[head] = nil
		head = (head % capacity) + 1
		count = count - 1
		storedBytes = math.max(0, storedBytes - (entry.StoredBytes or 0))

		if count == 0 then
			head = 1
		end

		return entry
	end

	function methods.Push(_, entry)
		local dropped = {}
		local entryBytes = math.max(0, math.floor(tonumber(entry.StoredBytes) or 0))

		while count > 0 and (count >= capacity or storedBytes + entryBytes > byteCapacity) do
			dropped[#dropped + 1] = popOldest()
		end

		count = count + 1
		storage[physicalIndex(count)] = entry
		storedBytes = storedBytes + entryBytes
		return dropped
	end

	function methods.Clear()
		storage = {}
		head = 1
		count = 0
		storedBytes = 0
	end

	function methods.Bytes()
		return storedBytes
	end

	local function iterate()
		local logicalIndex = 0

		return function()
			logicalIndex = logicalIndex + 1

			if logicalIndex <= count then
				return logicalIndex, storage[physicalIndex(logicalIndex)]
			end
		end
	end

	return setmetatable(proxy, {
		__len = function()
			return count
		end,
		__index = function(_, key)
			if type(key) == "number" and key >= 1 and key <= count and key % 1 == 0 then
				return storage[physicalIndex(key)]
			end

			return methods[key]
		end,
		__iter = iterate,
		__pairs = iterate,
	})
end

local logs = createHistory(maxLogs, maxHistoryBytes)
local listeners = {}
local sequence = 0

local function emit(entry, action)
	for connection, callback in pairs(listeners) do
		if connection.Connected then
			local ran, err = pcall(callback, entry, action)

			if not ran then
				diagnostics.EventErrors = diagnostics.EventErrors + 1
				diagnostics.LastCaptureError = {
					Stage = "event",
					Error = safeError(err),
				}
			end
		end
	end
end

local function connectEvent(callback)
	assert(type(callback) == "function", "RakNetSpy.ConnectEvent expects a callback")

	local connection = {
		Connected = true,
	}

	function connection:Disconnect()
		if not self.Connected then
			return
		end

		self.Connected = false
		listeners[self] = nil
	end

	listeners[connection] = callback
	return connection
end

local function captureTimestamp()
	if DateTime and type(DateTime.now) == "function" then
		local ran, value = pcall(function()
			return DateTime.now().UnixTimestampMillis / 1000
		end)

		if ran and type(value) == "number" then
			return value
		end
	end

	if os and type(os.time) == "function" then
		return os.time()
	end

	return 0
end

local function readField(packet, name)
	local ran, value = pcall(function()
		return packet[name]
	end)

	if ran then
		return true, value
	end

	return false, safeError(value)
end

local function getBufferLength(value)
	if type(buffer) == "table" and type(buffer.len) == "function" then
		local ran, length = pcall(buffer.len, value)

		if ran and type(length) == "number" and length >= 0 then
			return math.floor(length)
		end
	end

	if type(buffer) == "table" and type(buffer.tostring) == "function" then
		local ran, bytes = pcall(buffer.tostring, value)

		if ran and type(bytes) == "string" then
			return #bytes
		end
	end

	return nil
end

local function bufferToString(value, limit)
	local length = getBufferLength(value)

	if length and length > limit then
		return nil, "truncated", ("buffer contains %d bytes (limit %d)"):format(length, limit)
	end

	if type(buffer) == "table" and type(buffer.tostring) == "function" then
		local ran, bytes = pcall(buffer.tostring, value)

		if not ran then
			return nil, "failed", safeError(bytes)
		elseif type(bytes) ~= "string" then
			return nil, "failed", "buffer.tostring did not return a string"
		elseif #bytes > limit then
			return nil, "truncated", ("buffer contains %d bytes (limit %d)"):format(#bytes, limit)
		end

		return bytes
	end

	if length and type(buffer) == "table" and type(buffer.readu8) == "function" then
		local parts = {}

		for index = 0, length - 1 do
			local ran, byte = pcall(buffer.readu8, value, index)

			if not ran or type(byte) ~= "number" or byte < 0 or byte > 255 then
				return nil, "failed", ran and "buffer.readu8 returned an invalid byte" or safeError(byte)
			end

			parts[index + 1] = string.char(byte)
		end

		return table.concat(parts)
	end

	return nil, "failed", "buffer copy APIs are unavailable"
end

local function copyString(value, limit)
	if type(value) ~= "string" then
		return nil, "failed", "AsString is not a string"
	elseif #value > limit then
		return nil, "truncated", ("string contains %d bytes (limit %d)"):format(#value, limit)
	end

	return value
end

local function copyArray(value, limit)
	if type(value) ~= "table" then
		return nil, "failed", "AsArray is not a table"
	end

	local ran, count = pcall(function()
		return #value
	end)

	if not ran or type(count) ~= "number" or count < 0 then
		return nil, "failed", ran and "AsArray has an invalid length" or safeError(count)
	end

	count = math.floor(count)

	if count > limit then
		return nil, "truncated", ("array contains %d bytes (limit %d)"):format(count, limit)
	end

	local chunks = {}

	for index = 1, count do
		local byte = rawget(value, index)

		if type(byte) ~= "number" or byte % 1 ~= 0 or byte < 0 or byte > 255 then
			return nil, "failed", ("AsArray byte %d is invalid"):format(index)
		end

		chunks[index] = string.char(byte)
	end

	return table.concat(chunks)
end

local function copyBufferPreview(value, limit)
	if type(buffer) ~= "table" or type(buffer.len) ~= "function" or type(buffer.readu8) ~= "function" then
		return nil, "buffer preview APIs are unavailable"
	end

	local ran, bytes = pcall(function()
		local length = buffer.len(value)
		local shown = math.min(length, limit)
		local chunks = {}

		for offset = 0, shown - 1 do
			local byte = buffer.readu8(value, offset)
			chunks[offset + 1] = string.char(byte)
		end

		return table.concat(chunks)
	end)

	if not ran then
		return nil, safeError(bytes)
	end

	return bytes
end

local METADATA_FIELDS = { "PacketId", "Size", "Priority", "Reliability", "OrderingChannel" }

local function snapshotPacket(packet, direction)
	sequence = sequence + 1

	local entry = {
		Sequence = sequence,
		Direction = direction,
		Timestamp = captureTimestamp(),
		FieldErrors = {},
		PayloadComplete = false,
		PayloadState = "failed",
		Replayable = false,
		StoredBytes = 0,
	}
	for _, name in ipairs(METADATA_FIELDS) do
		local ok, value = readField(packet, name)

		if ok then
			entry[name] = value
		else
			entry.FieldErrors[name] = value
		end
	end

	local payloadLimit = math.min(maxPacketBytes, maxHistoryBytes)
	local previewLimit = math.min(payloadLimit, math.max(16, math.floor(tonumber(settings.MaxHexBytes) or 512)))
	local declaredSize = tonumber(entry.Size)
	local bufferRead, rawBuffer = readField(packet, "AsBuffer")
	local actualSize = bufferRead and getBufferLength(rawBuffer) or nil
	local truncated = (declaredSize ~= nil and declaredSize > payloadLimit)
		or (actualSize ~= nil and actualSize > payloadLimit)
	local failed = false

	if not bufferRead then
		entry.FieldErrors.AsBuffer = rawBuffer
	end

	if truncated then
		if bufferRead then
			local previewBytes, previewError = copyBufferPreview(rawBuffer, previewLimit)
			entry.PreviewBytes = previewBytes
			entry.StoredBytes = type(previewBytes) == "string" and #previewBytes or 0

			if previewError then
				entry.FieldErrors.AsBuffer = previewError
			end
		end

		entry.SkippedPayloadFields = "AsString and AsArray were not materialized for an oversized packet"
	else
		local bufferBytes, bufferState, bufferError = bufferToString(rawBuffer, payloadLimit)

		if bufferBytes then
			entry.PayloadBytes = bufferBytes
			entry.StoredBytes = #bufferBytes
			entry.SkippedPayloadFields = "AsString and AsArray were not materialized; AsBuffer was canonical"
		elseif bufferState == "truncated" then
			truncated = true
			entry.FieldErrors.AsBuffer = entry.FieldErrors.AsBuffer or bufferError
		else
			entry.FieldErrors.AsBuffer = entry.FieldErrors.AsBuffer or bufferError
			local stringRead, rawString = readField(packet, "AsString")
			local stringBytes, stringState, stringError

			if not stringRead then
				entry.FieldErrors.AsString = rawString
			else
				stringBytes, stringState, stringError = copyString(rawString, payloadLimit)
			end

			if stringBytes then
				entry.PayloadBytes = stringBytes
				entry.StoredBytes = #stringBytes
				entry.SkippedPayloadFields = "AsArray was not materialized; AsString was the fallback"
			elseif stringRead and stringState == "truncated" then
				truncated = true
				entry.FieldErrors.AsString = stringError
			else
				if stringRead then
					entry.FieldErrors.AsString = entry.FieldErrors.AsString or stringError
				end

				local arrayRead, rawArray = readField(packet, "AsArray")
				local arrayBytes, arrayState, arrayError = copyArray(rawArray, payloadLimit)

				if not arrayRead then
					entry.FieldErrors.AsArray = rawArray
				elseif arrayBytes then
					entry.PayloadBytes = arrayBytes
					entry.StoredBytes = #arrayBytes
				elseif arrayState == "truncated" then
					truncated = true
					entry.FieldErrors.AsArray = arrayError
				else
					entry.FieldErrors.AsArray = entry.FieldErrors.AsArray or arrayError
				end
			end
		end

		failed = not truncated and type(entry.PayloadBytes) ~= "string"
	end

	if truncated then
		entry.PayloadState = "truncated"
		entry.PayloadError = entry.PayloadError or "RakNet payload exceeded the capture limit"
		diagnostics.PayloadTruncations = diagnostics.PayloadTruncations + 1
	elseif failed or not entry.PayloadBytes then
		entry.PayloadState = "failed"
		entry.PayloadError = entry.PayloadError or "RakNet payload could not be copied completely"
		diagnostics.PayloadFailures = diagnostics.PayloadFailures + 1
	else
		entry.PayloadState = "complete"
		entry.PayloadComplete = true
	end

	entry.Replayable = direction == "send"
		and entry.PayloadComplete
		and type(entry.Priority) == "number"
		and type(entry.Reliability) == "number"
		and type(entry.OrderingChannel) == "number"
		and type(raknetSend) == "function"

	return entry
end

local function retainEntry(entry)
	local dropped = logs:Push(entry)

	for _, oldEntry in ipairs(dropped) do
		diagnostics.LogsDropped = diagnostics.LogsDropped + 1
		diagnostics.BytesDropped = diagnostics.BytesDropped + (oldEntry.StoredBytes or 0)
	end

	diagnostics.HistoryBytes = logs:Bytes()
	diagnostics.PacketsCaptured = diagnostics.PacketsCaptured + 1

	if entry.Direction == "send" then
		diagnostics.SendPacketsCaptured = diagnostics.SendPacketsCaptured + 1
	else
		diagnostics.ReceivePacketsCaptured = diagnostics.ReceivePacketsCaptured + 1
	end

	emit(entry, "added")
end

local function capture(packet, direction)
	diagnostics.Callbacks = diagnostics.Callbacks + 1

	if RakNetSpy.Enabled == false then
		diagnostics.PacketsSkippedPaused = diagnostics.PacketsSkippedPaused + 1
		return
	end

	local ran, entry = pcall(snapshotPacket, packet, direction)

	if not ran then
		diagnostics.CaptureErrors = diagnostics.CaptureErrors + 1
		diagnostics.LastCaptureError = {
			Stage = direction,
			Error = safeError(entry),
		}
		return
	end

	local retained, retainError = pcall(retainEntry, entry)

	if not retained then
		diagnostics.CaptureErrors = diagnostics.CaptureErrors + 1
		diagnostics.LastCaptureError = {
			Stage = direction .. "-retention",
			Error = safeError(retainError),
		}
	end
end

-- Potassium removes hooks by the callback object passed to add_*_hook. Keep
-- these exact functions for the full module lifetime.
local sendCallback = function(packet)
	local _ = pcall(capture, packet, "send")
end
local receiveCallback = function(packet)
	local _ = pcall(capture, packet, "receive")
end

local capabilities = {
	SendHook = type(raknetAddSendHook) == "function" and type(raknetRemoveSendHook) == "function",
	ReceiveHook = type(raknetAddReceiveHook) == "function" and type(raknetRemoveReceiveHook) == "function",
	Send = type(raknetSend) == "function",
	Buffer = type(buffer) == "table"
		and (
			type(buffer.tostring) == "function"
			or (type(buffer.len) == "function" and type(buffer.readu8) == "function")
		),
	SendHookInstalled = false,
	ReceiveHookInstalled = false,
}

local function numberLiteral(value)
	if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
		return nil
	end

	return tostring(value)
end

local function quoteBytes(value)
	local parts = { '"' }
	local chunkParts = {}
	local chunkLength = 0

	local function append(part)
		chunkLength = chunkLength + 1
		chunkParts[chunkLength] = part

		if chunkLength >= 1024 then
			parts[#parts + 1] = table.concat(chunkParts, "", 1, chunkLength)
			chunkParts = {}
			chunkLength = 0
		end
	end

	for index = 1, #value do
		local byte = value:byte(index)

		if byte == 34 then
			append('\\"')
		elseif byte == 92 then
			append("\\\\")
		elseif byte >= 32 and byte <= 126 then
			append(string.char(byte))
		else
			append(("\\%03d"):format(byte))
		end
	end

	if chunkLength > 0 then
		parts[#parts + 1] = table.concat(chunkParts, "", 1, chunkLength)
	end

	parts[#parts + 1] = '"'
	return table.concat(parts)
end

local function quotedBytesLength(value, maximum)
	local length = 2

	if length > maximum then
		return nil
	end

	for index = 1, #value do
		local byte = value:byte(index)
		local added = 1

		if byte == 34 or byte == 92 then
			added = 2
		elseif byte < 32 or byte > 126 then
			added = 4
		end

		length = length + added

		if length > maximum then
			return nil
		end
	end

	return length
end

local function buildReceiveTemplate(entry)
	local packetId = numberLiteral(entry.PacketId)
	local idCondition = packetId and ("\tif packet.PacketId ~= %s then\n\t\treturn\n\tend\n\n"):format(packetId) or ""

	return table.concat({
		"-- Generated by Hydroxide RakNet Spy\n",
		"-- RECEIVE-HOOK TEMPLATE (not a replay)\n",
		"-- Incoming captures cannot be replayed with raknet.send.\n",
		"local function receiveHook(packet)\n",
		idCondition,
		"\t-- Inspect packet.AsBuffer, call packet:SetData(...), or packet:Block().\n",
		'\tprint("RakNet receive", packet.PacketId, packet.Size)\n',
		"end\n\n",
		"raknet.add_receive_hook(receiveHook)\n",
		"-- Remove later with: raknet.remove_receive_hook(receiveHook)\n",
		"return receiveHook",
	})
end

local function buildScript(entry)
	if type(entry) ~= "table" then
		return nil, "Select a captured RakNet packet first"
	elseif entry.Direction == "receive" then
		return buildReceiveTemplate(entry)
	elseif entry.Direction ~= "send" then
		return nil, "Unknown RakNet packet direction"
	elseif not entry.PayloadComplete or type(entry.PayloadBytes) ~= "string" then
		return nil, "Only complete outgoing RakNet payloads can generate replay code"
	end

	local priority = numberLiteral(entry.Priority)
	local reliability = numberLiteral(entry.Reliability)
	local orderingChannel = numberLiteral(entry.OrderingChannel)

	if not (priority and reliability and orderingChannel) then
		return nil, "The captured RakNet send metadata is incomplete"
	end

	local prefix = "-- Generated by Hydroxide RakNet Spy\n"
		.. "-- Outgoing packet replay; review before running.\nreturn raknet.send("
	local suffix = (", %s, %s, %s)"):format(priority, reliability, orderingChannel)
	local literalBudget = maxGeneratedOutputBytes - #prefix - #suffix

	if literalBudget < 2 or not quotedBytesLength(entry.PayloadBytes, literalBudget) then
		return nil, ("Generated RakNet script would exceed the %d-byte output limit"):format(maxGeneratedOutputBytes)
	end

	return prefix .. quoteBytes(entry.PayloadBytes) .. suffix
end

local function replay(entry)
	diagnostics.ReplayAttempts = diagnostics.ReplayAttempts + 1

	if type(entry) ~= "table" then
		diagnostics.ReplayFailures = diagnostics.ReplayFailures + 1
		return false, "Select a captured RakNet packet first"
	elseif entry.Direction ~= "send" then
		diagnostics.ReplayFailures = diagnostics.ReplayFailures + 1
		return false, "Incoming RakNet captures cannot be replayed"
	elseif not entry.PayloadComplete or type(entry.PayloadBytes) ~= "string" then
		diagnostics.ReplayFailures = diagnostics.ReplayFailures + 1
		return false, "Truncated or failed RakNet payloads cannot be replayed"
	elseif not capabilities.Send then
		diagnostics.ReplayFailures = diagnostics.ReplayFailures + 1
		return false, "raknet.send is unavailable"
	elseif
		type(entry.Priority) ~= "number"
		or type(entry.Reliability) ~= "number"
		or type(entry.OrderingChannel) ~= "number"
	then
		diagnostics.ReplayFailures = diagnostics.ReplayFailures + 1
		return false, "The captured RakNet send metadata is incomplete"
	end

	local results =
		packValues(pcall(raknetSend, entry.PayloadBytes, entry.Priority, entry.Reliability, entry.OrderingChannel))

	if not results[1] then
		local err = safeError(results[2])
		diagnostics.ReplayFailures = diagnostics.ReplayFailures + 1
		diagnostics.LastReplayError = err
		return false, err
	end

	diagnostics.ReplaySuccesses = diagnostics.ReplaySuccesses + 1
	return true, unpackValues(results, 2, results.n)
end

local disconnected = false
local teardown = {
	Connected = true,
}

function teardown:Disconnect()
	if disconnected then
		return
	end

	disconnected = true
	self.Connected = false
	RakNetSpy.Connected = false
	RakNetSpy.Enabled = false

	if capabilities.SendHookInstalled then
		local ran, err = pcall(raknetRemoveSendHook, sendCallback)

		if not ran then
			diagnostics.SendHookRemoveErrors = diagnostics.SendHookRemoveErrors + 1
			diagnostics.LastHookError = safeError(err)
		else
			capabilities.SendHookInstalled = false
		end
	end

	if capabilities.ReceiveHookInstalled then
		local ran, err = pcall(raknetRemoveReceiveHook, receiveCallback)

		if not ran then
			diagnostics.ReceiveHookRemoveErrors = diagnostics.ReceiveHookRemoveErrors + 1
			diagnostics.LastHookError = safeError(err)
		else
			capabilities.ReceiveHookInstalled = false
		end
	end

	emit(nil, "disconnected")

	for connection in pairs(listeners) do
		connection.Connected = false
		listeners[connection] = nil
	end
end

RakNetSpy.Enabled = true
RakNetSpy.Connected = false
RakNetSpy.IsSupported = capabilities.SendHook or capabilities.ReceiveHook
RakNetSpy.Capabilities = capabilities
RakNetSpy.Diagnostics = diagnostics
RakNetSpy.Logs = logs
RakNetSpy.ConnectEvent = function(first, second)
	return connectEvent(first == RakNetSpy and second or first)
end
RakNetSpy.BuildScript = function(first, second)
	return buildScript(first == RakNetSpy and second or first)
end
RakNetSpy.Replay = function(first, second)
	return replay(first == RakNetSpy and second or first)
end
RakNetSpy.Disconnect = function()
	teardown:Disconnect()
end
RakNetSpy.SetEnabled = function(first, second)
	local enabled = first == RakNetSpy and second or first
	RakNetSpy.Enabled = enabled ~= false
	emit(nil, RakNetSpy.Enabled and "resumed" or "paused")
	return RakNetSpy.Enabled
end
RakNetSpy.Pause = function()
	return RakNetSpy.SetEnabled(false)
end
RakNetSpy.Resume = function()
	return RakNetSpy.SetEnabled(true)
end
RakNetSpy.Clear = function()
	logs:Clear()
	diagnostics.HistoryBytes = 0
	emit(nil, "cleared")
end

if capabilities.SendHook then
	local ran, err = pcall(raknetAddSendHook, sendCallback)

	if ran then
		capabilities.SendHookInstalled = true
	else
		diagnostics.SendHookRegisterErrors = diagnostics.SendHookRegisterErrors + 1
		diagnostics.LastHookError = safeError(err)
	end
end

if capabilities.ReceiveHook then
	local ran, err = pcall(raknetAddReceiveHook, receiveCallback)

	if ran then
		capabilities.ReceiveHookInstalled = true
	else
		diagnostics.ReceiveHookRegisterErrors = diagnostics.ReceiveHookRegisterErrors + 1
		diagnostics.LastHookError = safeError(err)
	end
end

RakNetSpy.Connected = capabilities.SendHookInstalled or capabilities.ReceiveHookInstalled

if type(oh) == "table" and type(oh.Events) == "table" then
	oh.Events[#oh.Events + 1] = teardown
end

return RakNetSpy
