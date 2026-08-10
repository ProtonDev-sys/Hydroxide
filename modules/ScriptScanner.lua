local ScriptScanner = {}
local LocalScript = import("objects/LocalScript")

local requiredMethods = {
    ["getRunningScripts"] = true,
    ["getSenv"] = true,
    ["getProtos"] = true,
    ["getConstants"] = true,
    ["getScriptClosure"] = true
}

local function scan(query)
    local scripts = {}
    query = (query or ""):lower()
    local ran, runningScripts = pcall(getRunningScripts)

    if not ran or type(runningScripts) ~= "table" then
        return scripts
    end

    for _, script in pairs(runningScripts) do
        if typeof(script) == "Instance"
            and not scripts[script]
            and script:IsA("LocalScript")
            and script.Name:lower():find(query, 1, true)
        then
            local closureRan, closure = pcall(getScriptClosure, script)
            local environmentRan, scriptEnvironment = pcall(getSenv, script)

            if closureRan and closure and environmentRan and type(scriptEnvironment) == "table" then
                scripts[script] = LocalScript.new(script, closure, scriptEnvironment)
            end
        end
    end

    return scripts
end

ScriptScanner.RequiredMethods = requiredMethods
ScriptScanner.Scan = scan
return ScriptScanner
