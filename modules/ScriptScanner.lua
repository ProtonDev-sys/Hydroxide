local ScriptScanner = {}
local LocalScript = import("objects/LocalScript")

local requiredMethods = {
    ["getGc"] = true,
    ["getSenv"] = true,
    ["getProtos"] = true,
    ["getConstants"] = true,
    ["getScriptClosure"] = true,
    ["isXClosure"] = true
}

local function scan(query)
    local scripts = {}
    query = (query or ""):lower()

    for _, closure in pairs(getGc()) do
        if type(closure) == "function" and not isXClosure(closure) then
            local script = safeGetClosureScript and safeGetClosureScript(closure)

            if typeof(script) == "Instance" and
                not scripts[script] and
                script:IsA("LocalScript") and
                script.Name:lower():find(query, 1, true) and
                getScriptClosure(script) and
                pcall(function()
                    return getSenv(script)
                end)
            then
                scripts[script] = LocalScript.new(script)
            end
        end
    end

    return scripts
end

ScriptScanner.RequiredMethods = requiredMethods
ScriptScanner.Scan = scan
return ScriptScanner
