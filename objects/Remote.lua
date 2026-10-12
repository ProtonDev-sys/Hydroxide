local Remote = {}

local DEFAULT_MAX_LOGS = 500
local DEFAULT_MAX_HISTORY_BYTES = 16777216

local createLogBuffer = import("objects/LogBuffer")

local function normalizeMaxHistoryBytes(value)
    value = tonumber(value)

    if not value or value ~= value or value == math.huge or value == -math.huge then
        return DEFAULT_MAX_HISTORY_BYTES
    end

    return math.max(1, math.floor(value))
end

local function normalizeMaxLogs(value)
    value = tonumber(value)

    if not value or value ~= value or value == math.huge or value == -math.huge then
        return DEFAULT_MAX_LOGS
    end

    return math.max(1, math.floor(value))
end

local ArgumentFilter = import("objects/ArgumentFilter")
local addArgCondition = ArgumentFilter.Add

function Remote.new(instance, maxLogs, maxHistoryBytes)
    local remote = {}

    remote.Instance = instance
    remote.MaxLogs = normalizeMaxLogs(maxLogs)
    remote.MaxHistoryBytes = normalizeMaxHistoryBytes(maxHistoryBytes)
    remote.Logs = createLogBuffer(remote.MaxLogs, remote.MaxHistoryBytes)
    remote.HistoryBytes = 0
    remote.Calls = 0
    remote.TotalCalls = 0
    remote.DroppedCalls = 0
    remote.Blocked = false
    remote.Ignored = false
    remote.Clear = Remote.clear
    remote.Block = Remote.block
    remote.Unblock = Remote.unblock
    remote.SetBlocked = Remote.setBlocked
    remote.Ignore = Remote.ignore
    remote.Unignore = Remote.unignore
    remote.SetIgnored = Remote.setIgnored
    remote.BlockedArgs = {}
    remote.IgnoredArgs = {}
    remote.BlockArg = Remote.blockArg
    remote.IgnoreArg = Remote.ignoreArg
    remote.AreArgsBlocked = Remote.areArgsBlocked
    remote.AreArgsIgnored = Remote.areArgsIgnored
    remote.IncrementCalls = Remote.incrementCalls
    remote.RefreshCallBytes = Remote.refreshCallBytes
    remote.DecrementCalls = Remote.decrementCalls

    return remote
end

function Remote.clear(remote)
    remote.Calls = 0
    remote.TotalCalls = 0
    remote.DroppedCalls = 0
    remote.Logs:Clear()
    remote.HistoryBytes = 0
end

function Remote.setBlocked(remote, blocked)
    remote.Blocked = blocked and true or false
end

function Remote.block(remote)
    remote:SetBlocked(not remote.Blocked)
end

function Remote.unblock(remote)
    remote:SetBlocked(false)
end

function Remote.setIgnored(remote, ignored)
    remote.Ignored = ignored and true or false
end

function Remote.ignore(remote)
    remote:SetIgnored(not remote.Ignored)
end

function Remote.unignore(remote)
    remote:SetIgnored(false)
end

function Remote.blockArg(remote, index, value, byType)
    return addArgCondition(remote.BlockedArgs, index, value, byType)
end

function Remote.ignoreArg(remote, index, value, byType)
    return addArgCondition(remote.IgnoredArgs, index, value, byType)
end

function Remote.areArgsBlocked(remote, args)
    return ArgumentFilter.Matches(remote.BlockedArgs, args)
end

function Remote.areArgsIgnored(remote, args)
    return ArgumentFilter.Matches(remote.IgnoredArgs, args)
end

function Remote.incrementCalls(remote, call)
    local logs = remote.Logs
    local dropped = false

    remote.Calls = remote.Calls + 1
    remote.TotalCalls = remote.TotalCalls + 1
    local droppedCount = logs:Push(call)

    if droppedCount > 0 then
        remote.DroppedCalls = remote.DroppedCalls + droppedCount
        dropped = droppedCount
    end

    remote.HistoryBytes = logs:Bytes()

    return dropped
end

function Remote.refreshCallBytes(remote, call)
    local dropped = remote.Logs:RefreshBytes(call)

    if dropped > 0 then
        remote.DroppedCalls = remote.DroppedCalls + dropped
    end

    remote.HistoryBytes = remote.Logs:Bytes()
    return dropped
end

function Remote.decrementCalls(remote, call)
    local logs = remote.Logs
    if logs:Remove(call) then
        remote.Calls = math.max(0, remote.Calls - 1)
        remote.HistoryBytes = logs:Bytes()
    end
end

return Remote
