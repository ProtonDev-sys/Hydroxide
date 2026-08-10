## Script
```lua
local owner = "ProtonDev-sys"
local repository = "Hydroxide"
local branch = "potassium-modernization-fork"

getgenv().HydroxideConfig = {
    owner = owner,
    repository = repository,
    branch = branch,
    captureExecutorCalls = true,
    captureCallStacks = true,
    maxRemoteLogs = 500,
    maxClosureLogs = 500,
    maxRenderedLogs = 100,
    maxStackFrames = 24,
    maxStackCapturesPerSecond = 60,
    maxGeneratedTableEntries = 256,
    maxGeneratedTables = 512,
    maxGeneratedTableDepth = 16,
    maxGeneratedStringBytes = 65536,
    maxGeneratedBufferBytes = 65536,
    maxGeneratedOutputBytes = 1048576,
    maxConcurrentImports = 6
}

local baseUrl = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(owner, repository, branch)

local function fetch(url)
    if type(request) == "function" then
        local ok, response = pcall(request, { Url = url, Method = "GET" })

        if ok and response and type(response.Body) == "string"
            and (response.Success or (response.StatusCode and response.StatusCode >= 200 and response.StatusCode < 300))
        then
            return response.Body
        end
    end

    if type(httpget) == "function" then
        local ok, source = pcall(httpget, url)

        if ok and type(source) == "string" then
            return source
        end
    end

    local ok, source = pcall(function()
        return game:HttpGet(url)
    end)

    if ok and type(source) == "string" then
        return source
    end

    ok, source = pcall(function()
        return game:HttpGetAsync(url)
    end)
    assert(ok and type(source) == "string", "Hydroxide could not download " .. url)
    return source
end

local function webImport(file)
    local source = fetch(baseUrl .. file .. ".lua")
    local chunk, compileError = loadstring(source, file .. ".lua")

    assert(chunk, compileError)
    return chunk()
end

webImport("init")
getgenv().import("ui/main")
```

## Potassium compatibility

This fork targets the current [Potassium API reference](https://docs.potassium.pro/) and keeps legacy aliases only as fallbacks. The runtime uses Potassium's documented APIs directly:

* `filtergc` narrows scanner work to non-executor Lua closures instead of walking every GC object.
* `getrunningscripts` powers Script Scanner without a GC scan.
* `hookmetamethod` captures ordinary namecalls on their original thread for caller filtering and stack/source inspection. Potassium's `oth.hook`, `oth.get_root_callback`, `oth.get_original_thread`, and `oth.unhook(target)` provide the direct C-function pass-through, with `hookfunction` retained as a fallback.
* `getscriptfromthread` preserves calling-script attribution for off-thread hooks.
* `debug.getcallstack` captures bounded call stacks for remote and closure calls when the active hook runs on the original thread.
* `decompile` powers lazy script, module, and function source inspection without slowing initial UI loading.
* `restorefunction` and documented `Connection:Enable()` teardown restore hooks and temporarily disabled error connections.
* `getthreadidentity` and `setthreadidentity` capture the launch identity and restore it around privileged inspection work, replacing legacy thread-context names internally.

Remote and closure histories use fixed-capacity circular buffers, while visible call rows are rendered in a smaller window to keep high-traffic sessions responsive. Every matching call is still counted and logged into that bounded history, while expensive stack snapshots use a token-bucket limit (`maxStackCapturesPerSecond`, default 60) so remote spam cannot stall the client; calls skipped by that safeguard are labelled in the inspector. Imported source is cached by the resolved branch commit, preventing stale or partially mixed module versions. The main Hydroxide window expands to the available viewport, and RemoteSpy/ClosureSpy call logs expose built-in inspector action strips for arguments, returns, cleaned call chains, caller and target functions, decompiled scripts, paths, replay code, confirmed replay calls, diagnostics, and hex previews. Inspector output opens inside the Hydroxide menu instead of modal source popups, and very large inspector panes are capped by `MaxInspectorBytes` (default 512 KB) to keep the UI responsive. Set `getgenv().HydroxideConfig.cache = false` to disable the persistent cache, `captureExecutorCalls = false` to hide RemoteSpy calls unless they are confirmed to come from a game thread, or `suppressScriptErrors = false` to leave `ScriptContext.Error` connections untouched.

Click a captured RemoteSpy or ClosureSpy call to enable the inspector actions; right-click still opens the same actions as a shortcut. RemoteSpy replay generation opens an editable code viewer, while **Copy Code** copies the generated source. It preserves packed nils, shared and cyclic tables, binary strings, non-finite numbers, and safe Instance paths; values that cannot be reconstructed are explicitly warned about and omitted instead of producing broken code. Generation is bounded by the table, depth, string, buffer, and output limits above. Live replay requires confirmation, and an intentionally blocked remote must be unblocked first. Click a Module Scanner row to view the module's decompiled source; Script Scanner rows now populate source, environment, proto, and constant panes lazily, and function rows open their metadata, environment, constants, protos, upvalues, hash, and decompiled source in the same menu panel.

Upvalue Scanner's **Generate Script** action now opens a validated, editable fork-only script instead of silently copying a fragile snippet. The generated script uses the current Potassium debug aliases, verifies the closure and table target before mutation, and refuses identity-based table/function/thread keys that cannot be replayed safely.

The loader defaults to `ProtonDev-sys/Hydroxide` on `potassium-modernization-fork`. Override `owner`, `repository`, or `branch` in `HydroxideConfig` when testing another fork or commit.

# Hydroxide
<i>Lua runtime introspection and network capturing tool for games on the Roblox engine.</i>

Report issues in [ProtonDev-sys/Hydroxide](https://github.com/ProtonDev-sys/Hydroxide/issues).

<p align="center">
    <img src="https://cdn.discordapp.com/attachments/633472429917995038/722143730500501534/Hydroxide_Logo.png"/>
    </br>
    <img src="https://raw.githubusercontent.com/ProtonDev-sys/Hydroxide/potassium-modernization-fork/github-assets/ui.png" width="677px"/>
</p>

## Features
* Upvalue Scanner
    * View/Modify Upvalues
    * View first-level values in table upvalues
    * View information of closure
* Constant Scanner
    * View/Modify Constants
    * View information of closure
* Script Scanner
    * View general information of scripts (source, protos, constants, etc.)
    * Retrieve protos from running LocalScripts
* Module Scanner
    * Browse loaded ModuleScripts and view their complete decompiled source
* RemoteSpy
    * Log calls of remote objects (RemoteEvent, UnreliableRemoteEvent, RemoteFunction, BindableEvent, BindableFunction)
    * Inspect call stacks, calling functions, calling scripts, decompiled source, replay state, and return/error status when supported
    * Generate editable replay scripts with nil argument, Instance path, shared table, and cyclic table handling
    * Ignore/Block calls based on parameters passed
    * Traceback calling function/closure
* ClosureSpy
    * Log calls of closures
    * View general information of closures (location, protos, constants, etc.)
    * Inspect call chains, caller source, calling scripts, and nested caller functions from the logs pane

More to come, soon.

## Images/Videos
<p align="center">
    <img src="https://i.gyazo.com/63afdd764cdca533af5ebca843217a7e.gif" />
</p>
