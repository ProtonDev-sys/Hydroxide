local ScriptScanner = {}
local LocalScript = import("objects/LocalScript")

local requiredMethods = {
    ["getRunningScripts"] = true
}

local function getScriptList()
	if type(getRunningScripts) ~= "function" then
		error("getRunningScripts is not available in this executor", 0)
	end

	local ran, result = pcall(getRunningScripts)

	if not ran then
		error("getRunningScripts failed: " .. tostring(result), 0)
	elseif type(result) ~= "table" then
		error("getRunningScripts did not return a table", 0)
	end

	return result
end

local function enumerate(query, callback, options)
    query = tostring(query or ""):lower()
    callback = type(callback) == "function" and callback or nil
    options = type(options) == "table" and options or {}

    local isCancelled = type(options.IsCancelled) == "function" and options.IsCancelled or nil
    local yieldEvery = math.max(16, math.floor(tonumber(options.YieldEvery) or 128))
    local allowYield = options.Yield ~= false
    local seen = {}
    local matched = 0
    local scanned = 0

    if isCancelled and isCancelled() then
        return matched, true
    end

    for _, script in pairs(getScriptList()) do
        scanned = scanned + 1

        if typeof(script) == "Instance"
            and not seen[script]
            and script:IsA("BaseScript")
            and script.Name:lower():find(query, 1, true)
        then
            seen[script] = true
            matched = matched + 1

            if callback then
                callback(script, matched)
            end
        end

        if scanned % yieldEvery == 0 then
            if allowYield and task and type(task.wait) == "function" then
                task.wait()
            end

            if isCancelled and isCancelled() then
                return matched, true
            end
        end
    end

    return matched, false
end

local function scan(query)
    local scripts = {}

    enumerate(query, function(script)
        scripts[script] = LocalScript.new(script)
    end, { Yield = false })

    return scripts
end

ScriptScanner.RequiredMethods = requiredMethods
ScriptScanner.Scan = scan
ScriptScanner.Enumerate = enumerate
return ScriptScanner
