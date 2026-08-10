## Script
```lua
local owner = "ProtonDev-sys"
local repository = "Hydroxide"
local branch = "revision"

getgenv().HydroxideConfig = {
    owner = owner,
    repository = repository,
    branch = branch
}

local baseUrl = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(owner, repository, branch)

local function webImport(file)
    local source = httpget(baseUrl .. file .. ".lua")
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
* `oth.hook`, `oth.get_root_callback`, `oth.get_original_thread`, and `oth.unhook(target)` are used for direct C-function hooks when available.
* `getscriptfromthread` preserves calling-script attribution for off-thread hooks.
* `restorefunction` and documented `Connection:Enable()` teardown restore hooks and temporarily disabled error connections.
* `getthreadidentity` and `setthreadidentity` replace legacy thread-context names internally.

Imported source is cached by the resolved branch commit, preventing stale or partially mixed module versions. Set `getgenv().HydroxideConfig.cache = false` to disable the persistent cache, or `suppressScriptErrors = false` to leave `ScriptContext.Error` connections untouched.

The loader defaults to `ProtonDev-sys/Hydroxide` on `revision`. Override `owner`, `repository`, or `branch` in `HydroxideConfig` when testing another fork or commit.

# Hydroxide
<i>Lua runtime introspection and network capturing tool for games on the Roblox engine.</i>

~~Report issues to our Discord server: https://discord.gg/DJxBwAX~~

<ins>New Discord server will be established when the next major release is ready for use</ins>

<p align="center">
    <img src="https://cdn.discordapp.com/attachments/633472429917995038/722143730500501534/Hydroxide_Logo.png"/>
    </br>
    <img src="https://raw.githubusercontent.com/Upbolt/Hydroxide/revision/github-assets/ui.png" width="677px"/>
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
    * View general information of modules (return value, source, protos, constants, etc.)
    * Retrieve protos from loaded ModuleScripts
* RemoteSpy
    * Log calls of remote objects (RemoteEvent, UnreliableRemoteEvent, RemoteFunction, BindableEvent, BindableFunction)
    * Ignore/Block calls based on parameters passed
    * Traceback calling function/closure
* ClosureSpy
    * Log calls of closures
    * View general information of closures (location, protos, constants, etc.)

More to come, soon.

## Images/Videos
<p align="center">
    <img src="https://i.gyazo.com/63afdd764cdca533af5ebca843217a7e.gif" />
</p>
