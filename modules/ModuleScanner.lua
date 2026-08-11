local ModuleScanner = {}
local ModuleScript = import("objects/ModuleScript")

local requiredMethods = {
    ["getLoadedModules"] = true
}

local function getModuleList()
	if type(getLoadedModules) ~= "function" then
		error("getLoadedModules is not available in this executor", 0)
	end

	local ran, result = pcall(getLoadedModules)

	if not ran then
		error("getLoadedModules failed: " .. tostring(result), 0)
	elseif type(result) ~= "table" then
		error("getLoadedModules did not return a table", 0)
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

    for _, module in pairs(getModuleList()) do
        scanned = scanned + 1

        if typeof(module) == "Instance"
            and not seen[module]
            and module:IsA("ModuleScript")
            and module.Name:lower():find(query, 1, true)
        then
            seen[module] = true
            matched = matched + 1

            if callback then
                callback(module, matched)
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
    local modules = {}

    enumerate(query, function(module)
        modules[module] = ModuleScript.new(module)
    end, { Yield = false })

    return modules
end

ModuleScanner.Scan = scan
ModuleScanner.Enumerate = enumerate
ModuleScanner.RequiredMethods = requiredMethods
return ModuleScanner
