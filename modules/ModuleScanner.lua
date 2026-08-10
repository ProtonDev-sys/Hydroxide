local ModuleScanner = {}
local ModuleScript = import("objects/ModuleScript")

local requiredMethods = {
    ["getLoadedModules"] = true
}

local function getModuleList()
    if type(getLoadedModules) == "function" then
        local ran, result = pcall(getLoadedModules)

        if ran and type(result) == "table" then
            return result
        end
    end

    return {}
end

local function scan(query)
    local modules = {}
    query = (query or ""):lower()

    for _, module in pairs(getModuleList()) do
        if typeof(module) == "Instance"
            and not modules[module]
            and module:IsA("ModuleScript")
            and module.Name:lower():find(query, 1, true)
        then
            modules[module] = ModuleScript.new(module)
        end
    end

    return modules
end

ModuleScanner.Scan = scan
ModuleScanner.RequiredMethods = requiredMethods
return ModuleScanner
