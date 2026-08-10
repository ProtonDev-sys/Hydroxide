local ScriptScanner = {}
local LocalScript = import("objects/LocalScript")

local requiredMethods = {
    ["getRunningScripts"] = true
}

local function getScriptList()
    if type(getRunningScripts) == "function" then
        local ran, result = pcall(getRunningScripts)

        if ran and type(result) == "table" then
            return result
        end
    end

    return {}
end

local function scan(query)
    local scripts = {}
    query = (query or ""):lower()

    for _, script in pairs(getScriptList()) do
        if typeof(script) == "Instance"
            and not scripts[script]
            and script:IsA("BaseScript")
            and script.Name:lower():find(query, 1, true)
        then
            scripts[script] = LocalScript.new(script)
        end
    end

    return scripts
end

ScriptScanner.RequiredMethods = requiredMethods
ScriptScanner.Scan = scan
return ScriptScanner
