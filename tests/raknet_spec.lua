local root = (arg and arg[0] and arg[0]:match("^(.*[/\\])tests[/\\][^/\\]+$")) or ""
assert(root, "unable to locate repository root")

local function assertEqual(actual, expected, label)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function assertContains(haystack, needle, label)
	if type(haystack) ~= "string" or not haystack:find(needle, 1, true) then
		error(("%s: expected to find %s"):format(label, needle), 2)
	end
end

local packValues = table.pack or function(...)
	return { n = select("#", ...), ... }
end

local bufferLibrary = {}

function bufferLibrary.fromstring(bytes)
	assert(type(bytes) == "string", "buffer.fromstring expects bytes")
	return {
		__type = "buffer",
		bytes = bytes,
	}
end

function bufferLibrary.tostring(value)
	assert(type(value) == "table" and value.__type == "buffer", "invalid buffer")
	return value.bytes
end

function bufferLibrary.len(value)
	return #bufferLibrary.tostring(value)
end

function bufferLibrary.readu8(value, offset)
	return assert(bufferLibrary.tostring(value):byte(offset + 1), "buffer read out of bounds")
end

_G.buffer = bufferLibrary
_G.typeof = function(value)
	return type(value) == "table" and value.__type or type(value)
end
_G.DateTime = {
	now = function()
		return { UnixTimestampMillis = 1700000000125 }
	end,
}

local function arrayFromBytes(bytes)
	local result = {}

	for index = 1, #bytes do
		result[index] = bytes:byte(index)
	end

	return result
end

local function makePacket(bytes, overrides, reads)
	overrides = overrides or {}
	reads = reads or {}

	local values = {
		PacketId = overrides.PacketId or (bytes:byte(1) or 0),
		Size = overrides.Size or #bytes,
		Priority = overrides.Priority or 1,
		AsBuffer = overrides.AsBuffer or bufferLibrary.fromstring(bytes),
		AsString = overrides.AsString or bytes,
		AsArray = overrides.AsArray or arrayFromBytes(bytes),
		Reliability = overrides.Reliability or 3,
		OrderingChannel = overrides.OrderingChannel or 0,
	}

	local packet = setmetatable({}, {
		__index = function(_, key)
			reads[key] = (reads[key] or 0) + 1

			if overrides.ErrorField == key then
				error("field read failed: " .. key)
			end

			return values[key]
		end,
	})

	return packet, values, reads
end

local function install(settings)
	local sendHooks = {}
	local receiveHooks = {}
	local removedSend = {}
	local removedReceive = {}
	local sent = {}

	_G.raknetAddSendHook = function(callback)
		sendHooks[#sendHooks + 1] = callback
	end
	_G.raknetRemoveSendHook = function(callback)
		removedSend[#removedSend + 1] = callback
	end
	_G.raknetAddReceiveHook = function(callback)
		receiveHooks[#receiveHooks + 1] = callback
	end
	_G.raknetRemoveReceiveHook = function(callback)
		removedReceive[#removedReceive + 1] = callback
	end
	_G.raknetSend = function(...)
		sent[#sent + 1] = packValues(...)
		return "sent", nil, select("#", ...)
	end
	_G.oh = {
		Settings = settings,
		Events = {},
	}

	local spy = dofile(root .. "modules/RakNetSpy.lua")

	return spy,
		{
			SendHooks = sendHooks,
			ReceiveHooks = receiveHooks,
			RemovedSend = removedSend,
			RemovedReceive = removedReceive,
			Sent = sent,
			Events = _G.oh.Events,
		}
end

local spy, harness = install({
	MaxRakNetLogs = 2,
	MaxRakNetPacketBytes = 32,
	MaxRakNetHistoryBytes = 100,
})

assertEqual(spy.IsSupported, true, "RakNet hooks supported")
assertEqual(spy.Capabilities.SendHookInstalled, true, "send hook installed")
assertEqual(spy.Capabilities.ReceiveHookInstalled, true, "receive hook installed")
assertEqual(#harness.SendHooks, 1, "one send callback registered")
assertEqual(#harness.ReceiveHooks, 1, "one receive callback registered")
assertEqual(#harness.Events, 1, "teardown registered with runtime events")
assertEqual(type(harness.Events[1].Disconnect), "function", "runtime teardown is disconnectable")

local events = {}
local eventConnection = spy.ConnectEvent(function(entry, action)
	events[#events + 1] = { Entry = entry, Action = action }
end)

local binaryBytes = "\0A\255"
local binaryPacket, binaryValues, binaryReads = makePacket(binaryBytes, {
	PacketId = 0,
	Priority = 2,
	Reliability = 4,
	OrderingChannel = 7,
})
harness.SendHooks[1](binaryPacket)

assertEqual(#spy.Logs, 1, "send capture retained")
local binaryLog = spy.Logs[1]
assertEqual(binaryLog.Direction, "send", "send direction")
assertEqual(binaryLog.PacketId, 0, "zero packet id retained")
assertEqual(binaryLog.PayloadBytes, binaryBytes, "binary zero payload retained")
assertEqual(binaryLog.AsBuffer, nil, "redundant buffer representation is not retained")
assertEqual(binaryLog.AsString, nil, "redundant string representation is not retained")
assertEqual(binaryLog.AsArray, nil, "memory-heavy array representation is not retained")
assertEqual(binaryLog.PayloadState, "complete", "complete payload state")
assertEqual(binaryLog.Replayable, true, "complete outgoing packet replayable")
assertEqual(binaryLog.Packet, nil, "packet object is never retained")
assertEqual(binaryLog.Timestamp, 1700000000.125, "capture timestamp")

for _, field in ipairs({
	"PacketId",
	"Size",
	"Priority",
	"Reliability",
	"OrderingChannel",
}) do
	assertEqual(binaryReads[field], 1, field .. " snapshotted exactly once")
end
assertEqual(binaryReads.AsBuffer, 1, "canonical buffer representation read once")
assertEqual(binaryReads.AsString, nil, "redundant string representation is not materialized")
assertEqual(binaryReads.AsArray, nil, "redundant array representation is not materialized")

binaryValues.AsBuffer.bytes = "mutated"
binaryValues.AsArray[1] = 99
assertEqual(binaryLog.PayloadBytes, binaryBytes, "packet representation mutation cannot alter history")
assertEqual(events[1].Entry, binaryLog, "event receives immutable packet snapshot")
assertEqual(events[1].Action, "added", "event action")

local replayResults = packValues(spy.Replay(binaryLog))
assertEqual(replayResults[1], true, "outgoing replay succeeds")
assertEqual(replayResults[2], "sent", "replay preserves send result")
assertEqual(replayResults[3], nil, "replay preserves nil result")
assertEqual(replayResults[4], 4, "replay preserves trailing result")
assertEqual(replayResults.n, 4, "replay preserves result arity")
assertEqual(#harness.Sent, 1, "raknet.send called once")
assertEqual(harness.Sent[1][1], binaryBytes, "replay payload binary roundtrip")
assertEqual(harness.Sent[1][2], 2, "replay priority")
assertEqual(harness.Sent[1][3], 4, "replay reliability")
assertEqual(harness.Sent[1][4], 7, "replay ordering channel")

local outgoingSource = assert(spy.BuildScript(binaryLog))
assertContains(outgoingSource, "Generated by Hydroxide RakNet Spy", "outgoing script header")
assertContains(outgoingSource, 'raknet.send("', "outgoing script uses Potassium's binary-safe string input")
assertContains(outgoingSource, ", 2, 4, 7)", "outgoing script metadata")

local generatedSends = {}
local outgoingChunk, compileError = load(outgoingSource, "generated-raknet-send", "t", {
	buffer = bufferLibrary,
	raknet = {
		send = function(...)
			generatedSends[#generatedSends + 1] = packValues(...)
			return "generated-send"
		end,
	},
})
assert(outgoingChunk, compileError)
assertEqual(outgoingChunk(), "generated-send", "generated outgoing script executes")
assertEqual(generatedSends[1][1], binaryBytes, "generated script binary zero roundtrip")

local receivePacket = makePacket("RX", { PacketId = 19 })
harness.ReceiveHooks[1](receivePacket)
assertEqual(#spy.Logs, 2, "receive capture retained")
local receiveLog = spy.Logs[2]
assertEqual(receiveLog.Direction, "receive", "receive direction")
assertEqual(receiveLog.Replayable, false, "incoming capture is never replayable")
local receiveReplay, receiveReplayError = spy.Replay(receiveLog)
assertEqual(receiveReplay, false, "incoming replay rejected")
assertContains(receiveReplayError, "Incoming", "incoming replay explanation")

local receiveSource = assert(spy.BuildScript(receiveLog))
assertContains(receiveSource, "RECEIVE-HOOK TEMPLATE (not a replay)", "incoming template label")
assertContains(receiveSource, "Incoming captures cannot be replayed", "incoming template warning")
assertContains(receiveSource, "packet.PacketId ~= 19", "incoming template packet filter")
assertContains(receiveSource, "raknet.add_receive_hook(receiveHook)", "incoming template registration")
local generatedReceiveHook
local receiveChunk, receiveCompileError = load(receiveSource, "generated-raknet-receive", "t", {
	print = function() end,
	raknet = {
		add_receive_hook = function(callback)
			generatedReceiveHook = callback
		end,
	},
})
assert(receiveChunk, receiveCompileError)
assertEqual(receiveChunk(), generatedReceiveHook, "incoming template returns exact registered callback")

harness.SendHooks[1](makePacket("C1"))
assertEqual(#spy.Logs, 2, "count bound maintained")
assertEqual(spy.Logs[1], receiveLog, "count eviction removes oldest entry")
assertEqual(spy.Logs[2].PayloadBytes, "C1", "count eviction retains newest entry")
assertEqual(spy.Diagnostics.LogsDropped, 1, "count eviction diagnosed")

spy.Pause()
harness.SendHooks[1](makePacket("PA"))
assertEqual(#spy.Logs, 2, "paused spy does not retain packets")
assertEqual(spy.Diagnostics.PacketsSkippedPaused, 1, "paused callback diagnosed")
spy.Resume()

eventConnection:Disconnect()
spy.Clear()
assertEqual(#spy.Logs, 0, "clear removes captured packets")
assertEqual(spy.Diagnostics.HistoryBytes, 0, "clear resets retained byte count")

local sendCallback = harness.SendHooks[1]
local receiveCallback = harness.ReceiveHooks[1]
harness.Events[1]:Disconnect()
harness.Events[1]:Disconnect()
assertEqual(#harness.RemovedSend, 1, "send hook removed once")
assertEqual(#harness.RemovedReceive, 1, "receive hook removed once")
assertEqual(harness.RemovedSend[1], sendCallback, "send hook removed with exact registered callback")
assertEqual(harness.RemovedReceive[1], receiveCallback, "receive hook removed with exact registered callback")
assertEqual(spy.Connected, false, "teardown disconnects spy")

local byteSpy, byteHarness = install({
	MaxRakNetLogs = 10,
	MaxRakNetPacketBytes = 8,
	MaxRakNetHistoryBytes = 3,
})

byteHarness.SendHooks[1](makePacket("AA"))
byteHarness.SendHooks[1](makePacket("BB"))
assertEqual(#byteSpy.Logs, 1, "total byte bound evicts oldest payload")
assertEqual(byteSpy.Logs[1].PayloadBytes, "BB", "byte eviction keeps newest payload")
assertEqual(byteSpy.Diagnostics.HistoryBytes, 2, "history byte counter bounded")
assertEqual(byteSpy.Diagnostics.BytesDropped, 2, "evicted payload bytes diagnosed")

local oversizedPacket, _, oversizedReads = makePacket("123456789", { Size = 9 })
byteHarness.SendHooks[1](oversizedPacket)
local truncatedLog = byteSpy.Logs[#byteSpy.Logs]
assertEqual(truncatedLog.PayloadState, "truncated", "oversized payload marked truncated")
assertEqual(truncatedLog.Replayable, false, "truncated payload cannot replay")
assertEqual(truncatedLog.StoredBytes, 3, "truncated payload retains only a bounded preview")
assertEqual(truncatedLog.PreviewBytes, "123", "truncated payload preview is bounded by history budget")
assertEqual(byteSpy.BuildScript(truncatedLog), nil, "truncated payload cannot generate replay code")
assertEqual(byteSpy.Replay(truncatedLog), false, "truncated payload replay rejected")
assertEqual(oversizedReads.AsBuffer, 1, "oversized buffer field still snapshotted")
assertEqual(oversizedReads.AsString, nil, "oversized string representation is never materialized")
assertEqual(oversizedReads.AsArray, nil, "oversized array representation is never materialized")

local failedPacket = makePacket("OK", { AsBuffer = "not a buffer", AsString = {}, AsArray = { "not-a-byte" } })
local callbackSucceeded = pcall(byteHarness.SendHooks[1], failedPacket)
assertEqual(callbackSucceeded, true, "failed payload capture is fail-open")
local failedLog = byteSpy.Logs[#byteSpy.Logs]
assertEqual(failedLog.PayloadState, "failed", "invalid payload marked failed")
assertEqual(failedLog.Replayable, false, "failed payload cannot replay")

local throwingPacket = makePacket("ER", { ErrorField = "AsBuffer" })
assertEqual(pcall(byteHarness.ReceiveHooks[1], throwingPacket), true, "throwing packet field is fail-open")
local throwingLog = byteSpy.Logs[#byteSpy.Logs]
assertEqual(throwingLog.PayloadState, "complete", "string fallback survives a buffer field read failure")
assertEqual(throwingLog.PayloadBytes, "ER", "string fallback preserves payload bytes")
assertContains(throwingLog.FieldErrors.AsBuffer, "field read failed", "field read error diagnosed")

local arrayFallbackPacket = makePacket("AR", { AsBuffer = "not a buffer", AsString = {}, AsArray = { 65, 82 } })
byteHarness.ReceiveHooks[1](arrayFallbackPacket)
local arrayFallbackLog = byteSpy.Logs[#byteSpy.Logs]
assertEqual(arrayFallbackLog.PayloadState, "complete", "array representation is used as a final fallback")
assertEqual(arrayFallbackLog.PayloadBytes, "AR", "array fallback preserves payload bytes")

local throwingStringPacket, _, throwingStringReads =
	makePacket("AF", { AsBuffer = "not a buffer", ErrorField = "AsString", AsArray = { 65, 70 } })
assertEqual(pcall(byteHarness.ReceiveHooks[1], throwingStringPacket), true, "throwing string field is fail-open")
local throwingStringLog = byteSpy.Logs[#byteSpy.Logs]
assertEqual(throwingStringLog.PayloadState, "complete", "array fallback survives a string field read failure")
assertEqual(throwingStringLog.PayloadBytes, "AF", "array fallback preserves bytes after a string read failure")
assertEqual(throwingStringReads.AsArray, 1, "array fallback is read after a string field failure")
assertContains(throwingStringLog.FieldErrors.AsString, "field read failed", "string field read error diagnosed")

local budgetSpy, budgetHarness = install({
	MaxRakNetLogs = 2,
	MaxRakNetPacketBytes = 2048,
	MaxRakNetHistoryBytes = 4096,
	MaxRakNetGeneratedOutputBytes = 1024,
	MaxGeneratedOutputBytes = 8192,
})
budgetHarness.SendHooks[1](makePacket(string.rep("\0", 300)))
local budgetLog = budgetSpy.Logs[1]
assertEqual(budgetLog.PayloadState, "complete", "output budget does not truncate packet capture")
local oversizedSource, oversizedSourceError = budgetSpy.BuildScript(budgetLog)
assertEqual(oversizedSource, nil, "RakNet-specific generated output limit rejects oversized script")
assertContains(oversizedSourceError, "1024-byte output limit", "generated output rejection explains active limit")

local genericBudgetSpy, genericBudgetHarness = install({
	MaxRakNetLogs = 2,
	MaxRakNetPacketBytes = 2048,
	MaxRakNetHistoryBytes = 4096,
	MaxGeneratedOutputBytes = 1024,
})
genericBudgetHarness.SendHooks[1](makePacket(string.rep("\0", 300)))
local genericSource, genericSourceError = genericBudgetSpy.BuildScript(genericBudgetSpy.Logs[1])
assertEqual(genericSource, nil, "generic generated output limit rejects oversized RakNet script")
assertContains(genericSourceError, "1024-byte output limit", "generic generated output limit is honored")

local listenerSpy, listenerHarness = install({
	MaxRakNetLogs = 2,
	MaxRakNetPacketBytes = 8,
	MaxRakNetHistoryBytes = 8,
})
listenerSpy.ConnectEvent(function()
	error("listener failure")
end)
assertEqual(pcall(listenerHarness.SendHooks[1], makePacket("EV")), true, "listener error is fail-open")
assertEqual(#listenerSpy.Logs, 1, "listener error does not lose capture")
assertEqual(listenerSpy.Diagnostics.EventErrors, 1, "listener error diagnosed")

byteSpy.Disconnect()
listenerSpy.Disconnect()
budgetSpy.Disconnect()
genericBudgetSpy.Disconnect()

print("raknet_spec.lua: ok")
