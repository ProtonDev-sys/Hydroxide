local ModuleScanner = {}
local ModuleScript = import("objects/ModuleScript")

local requiredMethods = {
    ["getProtos"] = true,
    ["getConstants"] = true,
    ["getScriptClosure"] = true,
    ["getLoadedModules"] = true
}

local function scan(query)
    local modules = {}
    query = (query or ""):lower()
    local ran, loadedModules = pcall(getLoadedModules)

    if not ran or type(loadedModules) ~= "table" then
        return modules
    end

    for _, module in pairs(loadedModules) do
        if typeof(module) == "Instance" and module.Name:lower():find(query, 1, true) then
            local closureRan, closure = pcall(getScriptClosure, module)
            local created, moduleScript = false, nil

            if closureRan and closure then
                created, moduleScript = pcall(ModuleScript.new, module, closure)
            end

            if created and moduleScript then
                modules[module] = moduleScript
            end
        end
    end

    return modules
end

ModuleScanner.Scan = scan
ModuleScanner.RequiredMethods = requiredMethods
return ModuleScanner
