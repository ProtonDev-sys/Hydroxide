local Remote = {}

local DEFAULT_MAX_LOGS = 500

local function normalizeMaxLogs(value)
    value = tonumber(value)

    if not value then
        return DEFAULT_MAX_LOGS
    end

    return math.max(1, math.floor(value))
end

local function argumentCount(args)
    if type(args.n) == "number" then
        return math.max(0, math.floor(args.n))
    end

    return #args
end

function Remote.new(instance, maxLogs)
    local remote = {}

    remote.Instance = instance
    remote.Logs = {}
    remote.Calls = 0
    remote.TotalCalls = 0
    remote.DroppedCalls = 0
    remote.MaxLogs = normalizeMaxLogs(maxLogs)
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
    remote.DecrementCalls = Remote.decrementCalls

    return remote
end

function Remote.clear(remote)
    remote.Calls = 0
    remote.TotalCalls = 0
    remote.DroppedCalls = 0
    remote.Logs = {}
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
    local blockedArgs = remote.BlockedArgs
    local blockedIndex = blockedArgs[index]

    if not blockedIndex then
        blockedIndex = {
            types = {},
            values = {}
        }
        blockedArgs[index] = blockedIndex
    end

    if byType then
        blockedIndex.types[value] = true
    else
        blockedIndex.values[value] = true
    end
end

function Remote.ignoreArg(remote, index, value, byType)
    local ignoredArgs = remote.IgnoredArgs
    local ignoredIndex = ignoredArgs[index]

    if not ignoredIndex then
        ignoredIndex = {
            types = {},
            values = {}
        }

        ignoredArgs[index] = ignoredIndex
    end

    if byType then
        ignoredIndex.types[value] = true
    else
        ignoredIndex.values[value] = true
    end
end

function Remote.areArgsBlocked(remote, args)
    local blockedArgs = remote.BlockedArgs

    for index = 1, argumentCount(args) do
        local value = args[index]
        local indexBlock = blockedArgs[index]

        if indexBlock
            and (indexBlock.types[typeof(value)] or (value ~= nil and indexBlock.values[value] ~= nil))
        then
            return true
        end
    end

    return false
end

function Remote.areArgsIgnored(remote, args)
    local ignoredArgs = remote.IgnoredArgs

    for index = 1, argumentCount(args) do
        local value = args[index]
        local indexIgnore = ignoredArgs[index]

        if indexIgnore
            and (indexIgnore.types[typeof(value)] or (value ~= nil and indexIgnore.values[value] ~= nil))
        then
            return true
        end
    end

    return false
end

function Remote.incrementCalls(remote, call)
    local logs = remote.Logs
    local dropped = false

    remote.Calls = remote.Calls + 1
    remote.TotalCalls = remote.TotalCalls + 1
    logs[#logs + 1] = call

    if #logs > remote.MaxLogs then
        table.remove(logs, 1)
        remote.DroppedCalls = remote.DroppedCalls + 1
        dropped = true
    end

    return dropped
end

function Remote.decrementCalls(remote, call)
    local logs = remote.Logs
    local index = table.find(logs, call)

    if index then
        table.remove(logs, index)
        remote.Calls = math.max(0, remote.Calls - 1)
    end
end

return Remote
