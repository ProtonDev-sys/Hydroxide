local Remote = {}

function Remote.new(instance)
    local remote = {}

    remote.Instance = instance
    remote.Logs = {}
    remote.Calls = 0
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

    for index, value in pairs(args) do
        local indexBlock = blockedArgs[index]

        if indexBlock and (indexBlock.types[typeof(value)] or indexBlock.values[value] ~= nil) then
            return true
        end
    end

    return false
end

function Remote.areArgsIgnored(remote, args)
    local ignoredArgs = remote.IgnoredArgs

    for index, value in pairs(args) do
        local indexIgnore = ignoredArgs[index]

        if indexIgnore and (indexIgnore.types[typeof(value)] or indexIgnore.values[value] ~= nil) then
            return true
        end
    end

    return false
end

function Remote.incrementCalls(remote, call)
    remote.Calls = remote.Calls + 1
    table.insert(remote.Logs, call)
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
