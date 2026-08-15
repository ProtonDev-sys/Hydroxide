# Hydroxide
<i>Lua runtime introspection and network-capture tooling for games on the Roblox engine.</i>

This fork consolidates the Potassium modernization, responsive shared theme, bounded inspectors,
and the new RemoteSpy-style RakNet workflow on `main`.

Report issues in [ProtonDev-sys/Hydroxide](https://github.com/ProtonDev-sys/Hydroxide/issues).

<p align="center">
    <img src="https://cdn.discordapp.com/attachments/633472429917995038/722143730500501534/Hydroxide_Logo.png"/>
    </br>
    <img src="https://raw.githubusercontent.com/ProtonDev-sys/Hydroxide/main/github-assets/ui.png" width="677px"/>
</p>

## Quick start
```lua
local owner = "ProtonDev-sys"
local repository = "Hydroxide"
local branch = "main"

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
    maxArgumentPreviewLength = 240,
    maxHexBytes = 512,
    maxGeneratedTableEntries = 256,
    maxGeneratedTables = 512,
    maxGeneratedTableDepth = 16,
    maxGeneratedStringBytes = 65536,
    maxGeneratedBufferBytes = 65536,
    maxGeneratedOutputBytes = 1048576,
    maxValueViewDepth = 8,
    maxValueViewEntries = 512,
    maxValueViewTableEntries = 256,
    maxValueViewBytes = 65536,
    maxInspectorBytes = 524288,
    maxFunctionSourceCacheEntries = 64,
    maxFunctionSourceCacheBytes = 2097152,
    maxConditionBufferBytes = 4096,
    maxCapturedCallBytes = 262144,
    maxCapturedArguments = 128,
    maxRemoteHistoryBytes = 16777216,
    maxClosureHistoryBytes = 16777216,
    maxScriptRows = 750,
    maxModuleRows = 750,
    maxModuleFunctions = 32,
    maxRakNetLogs = 0, -- keep captures until Clear; use a positive value to cap history
    maxRenderedRakNetLogs = 100,
    maxRakNetPacketBytes = 65536,
    maxRakNetHistoryBytes = 0, -- keep captures until Clear; individual packets remain bounded
    maxRakNetGeneratedOutputBytes = 1048576,
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
* `getrunningscripts` powers Script Scanner for running `LocalScript` and client-context `Script` instances without a GC scan.
* `getscriptclosure` and `getsenv` provide the same lazy closure, environment, proto, constant, function, and source inspection for both running scripts and loaded modules.
* `hookmetamethod` captures ordinary namecalls on their original thread for caller filtering and stack/source inspection. Potassium's `oth.hook`, `oth.get_root_callback`, `oth.get_original_thread`, and `oth.unhook(target)` provide the direct C-function pass-through, with `hookfunction` retained as a fallback.
* `getscriptfromthread` preserves calling-script attribution for off-thread hooks.
* `raknet.add_send_hook`, `raknet.add_receive_hook`, their matching remove functions, and `raknet.send` power a new RemoteSpy-style RakNet transport view, with per-packet capture and UI-render limits when RakNet is enabled in Potassium's own settings. It is built from the same list, log, and action-panel components rather than embedding the previous RakNet panel. The shared workflow can ignore, block, inspect, generate code for, copy, and replay supported packet captures without enabling RakNet automatically.
* `debug.getcallstack` captures bounded call stacks for remote and closure calls when the active hook runs on the original thread.
* `decompile` powers lazy script, module, and function source inspection without slowing initial UI loading.
* `restorefunction` and documented `Connection:Enable()` teardown restore hooks and temporarily disabled error connections.
* `getthreadidentity` and `setthreadidentity` capture the launch identity and restore it around privileged inspection work, replacing legacy thread-context names internally.

Remote and closure histories use fixed-capacity circular buffers plus aggregate per-call and per-tool byte budgets, so many individually valid buffers cannot exhaust memory. Visible call rows are rendered newest-first in a smaller window to keep high-traffic sessions responsive. The list follows new calls only while it is pinned to the top, so manual inspection does not get pulled away. Every matching call is still counted and logged into that bounded history, while expensive stack snapshots use a token-bucket limit (`maxStackCapturesPerSecond`, default 60) so remote spam cannot stall the client; calls skipped by that safeguard are labelled in the inspector. RakNet snapshots are retained until **Clear** by default and only a bounded visible window is rendered; set a positive `maxRakNetLogs` or `maxRakNetHistoryBytes` to opt into eviction. Imported source is cached by the resolved branch commit, preventing stale or partially mixed module versions. The main Hydroxide window opens immediately at a compact viewport-relative size, scales when the viewport changes, can be dragged beyond the screen bounds, and can be resized. Asset-backed and dynamically created controls share one centralized dark theme. RemoteSpy/ClosureSpy call logs expose responsive icon action strips for arguments, returns, cleaned call chains, caller and target functions, decompiled scripts, paths, replay code, confirmed replay calls, diagnostics, and string/buffer hex previews. Inspector output is read-only and opens inside the Hydroxide menu instead of modal source popups; its split can be resized for long function data, and very large output is capped by `MaxInspectorBytes` (default 512 KB). Script and Module scanners wait until their tab is first opened, then use matching icon-based detail navigation, full-width detail views, cancellable row batches, bounded background workers, and no hidden-tab scan or metadata work. Function-source caches have aggregate entry and byte eviction limits. Module sections expose source, environment, functions, protos, constants, per-function metadata/source, and an Enter-to-apply filter for reaching relevant entries without rendering an unbounded list. Set `getgenv().HydroxideConfig.cache = false` to disable the persistent cache, `captureExecutorCalls = false` to hide RemoteSpy calls unless they are confirmed to come from a game thread, or `suppressScriptErrors = false` to leave `ScriptContext.Error` connections untouched.

Click a captured RemoteSpy or ClosureSpy call to enable the inspector actions; right-click still opens the same actions as a shortcut. Argument and return viewers expand nested table contents with stable ordering, shared/cyclic reference labels, and configurable depth, entry, and byte limits. RemoteSpy replay generation opens a read-only code viewer, while **Copy Code** copies the generated source. It preserves packed nils, shared and cyclic tables, binary strings and buffers, non-finite numbers, and safe Instance paths; values that cannot be reconstructed are explicitly marked and replay is disabled instead of emitting misleading code. Every generated RemoteSpy and RakNet script is compiled before it is shown or copied. Generation is bounded by the table, depth, string, buffer, and output limits above. Live replay uses an in-menu confirmation, and an intentionally blocked remote or packet ID must be unblocked first. Conditions default to the selected argument and a safe type match, include buffer/current Roblox value types, validate indices, and retain an advanced typed-value option.

Upvalue Scanner's **Generate Script** action opens a validated, read-only fork-only script instead of silently copying a fragile snippet. The generated script uses the current Potassium debug aliases, verifies the closure and table target before mutation, and refuses identity-based table/function/thread keys that cannot be replayed safely.

The loader defaults to `ProtonDev-sys/Hydroxide` on `main`. Override `owner`, `repository`, or `branch` in `HydroxideConfig` when testing another fork or commit.

## Features
* Upvalue Scanner
    * View/Modify Upvalues
    * View first-level values in table upvalues
    * View information of closure
* Constant Scanner
    * View/Modify Constants
    * View information of closure
* Script Scanner
    * View general information of scripts (source, environment, protos, constants, etc.)
    * Retrieve protos from running client `BaseScript` instances
* Module Scanner
    * Inspect loaded ModuleScripts with the same source, environment, function, proto, and constant tooling as running scripts
* RemoteSpy
    * Log calls of remote objects (RemoteEvent, UnreliableRemoteEvent, RemoteFunction, BindableEvent, BindableFunction)
    * Switch between Roblox remote calls and RakNet packet traffic in one RemoteSpy workspace
    * Inspect call stacks, calling functions, calling scripts, decompiled source, replay state, and return/error status when supported
    * Expand nested argument and return tables with shared/cyclic reference labels and bounded output
    * Generate read-only replay scripts with nil argument, Instance path, shared table, cyclic table, and buffer handling
    * Ignore/Block calls based on parameters passed
    * Traceback calling function/closure
* RakNet Spy (Potassium)
    * Retain outgoing and incoming packet snapshots until Clear without retaining live packet objects
    * Browse packet-ID groups with counts and ignore, block, unblock, or clear filters for individual packet IDs
    * Inspect packet metadata plus capped hex, text, and array payload views
    * Generate compile-validated outgoing send scripts and clearly labelled incoming receive-hook templates
    * Replay only complete outgoing captures after an in-menu confirmation
* ClosureSpy
    * Log calls of closures
    * View general information of closures (location, protos, constants, etc.)
    * Inspect call chains, caller source, calling scripts, and nested caller functions from the logs pane

More to come, soon.

## Images/Videos
<p align="center">
    <img src="https://i.gyazo.com/63afdd764cdca533af5ebca843217a7e.gif" />
</p>
