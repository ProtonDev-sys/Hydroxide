# Hydroxide
<i>Lua runtime introspection and network-capture tooling for games on the Roblox engine.</i>

This fork keeps the upstream Hydroxide interface and adds Potassium support, bounded inspectors,
and a shared RemoteSpy/RakNet workflow on `main`.

<p align="center">
    <img src="https://cdn.discordapp.com/attachments/633472429917995038/722143730500501534/Hydroxide_Logo.png"/>
    </br>
    <img src="https://raw.githubusercontent.com/ProtonDev-sys/Hydroxide/main/github-assets/ui.png" width="677px"/>
</p>

## Quick start

Run this in Potassium:

```lua
assert(loadstring(httpget("https://raw.githubusercontent.com/ProtonDev-sys/Hydroxide/main/init.lua"), "Hydroxide"))()
```

The initializer opens the interface and supplies the defaults. Existing scripts that call
`getgenv().import("ui/main")` afterwards continue to work without opening a second interface.

Only set options you want to change, before the launch line:

```lua
getgenv().HydroxideConfig = {
    maxRenderedLogs = 75,
    captureCallStacks = false,
}
```

See [configuration](docs/CONFIGURATION.md) for every option, commit pinning, local development,
and programmatic startup. No configuration block is required for normal use.

## Potassium compatibility

The compatibility table in `init.lua` resolves documented Potassium APIs once and keeps legacy
aliases at the boundary. Optional capabilities are checked before use. See
[runtime and UI compatibility](docs/COMPATIBILITY.md) for the API references and maintenance rules.

- `filtergc` narrows closure scans; `getrunningscripts` and `getloadedmodules` enumerate script views.
- `getscriptclosure`, `getsenv`, debug APIs, and `decompile` supply lazy script/function inspection.
- Existing remote and closure hooks preserve original returns and errors when capture fails,
  and are restored on exit. Call stack snapshots have a separate rate limit.
- Potassium's RakNet callbacks supply the packet view when enabled in Potassium's settings.
  Hydroxide does not enable that setting automatically.
- Source imports resolve one commit. Persistent cache entries include owner, repository, and
  commit, and are verified against GitHub blob hashes using `crypt.hash`. Corrupt entries are
  downloaded again. If the trusted file list or hashing is unavailable, imports bypass disk
  cache and use the resolved HTTPS source. An unresolved branch stops startup.

## Working with captures

Remote and closure histories use bounded circular buffers with per-history byte accounting.
RakNet defaults to 500 snapshots and 16 MiB of payload history; explicit zero limits retain
snapshots until **Clear**. The UI renders a smaller newest-first window and follows new calls
only while pinned to the top. These limits bound retained payloads and visible rows, not every
Lua/Roblox allocation in the client. See [configuration](docs/CONFIGURATION.md) for their scope.

Select a RemoteSpy or ClosureSpy call to inspect arguments, returns, caller/target functions,
call chains, source, paths, diagnostics, replay code, and bounded hex previews. Right-click
provides the same actions. Nested value views identify shared/cyclic references and preserve
packed nils and false values. Large output is capped and shown in a read-only in-menu viewer.

Generated replay scripts preserve supported Instances, shared/cyclic tables, binary strings,
buffers, non-finite numbers, and nil argument positions. Unsupported or truncated captures
are labelled and cannot be replayed. RemoteSpy and RakNet output is compiled before display
or copying. Replay requires an in-menu confirmation and respects blocked remote/packet IDs.
Conditions support argument indices, type matching, typed values, buffers, and nil/false values.

The upstream asset-based window keeps its compact dark UI, resizable layout, viewport recovery,
and shared controls. Scanners defer work until their tab is opened, render in cancellable
batches, and use bounded source caches. Function inspection stops when dismissed or superseded.
`ScriptContext.Error` connections are left untouched by default.

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
    * Retain bounded outgoing and incoming packet snapshots without holding live packet objects; optional zero limits retain them until Clear
    * Browse packet-ID groups with counts and ignore, block, unblock, or clear filters for individual packet IDs
    * Inspect packet metadata plus capped hex, text, and array payload views
    * Generate compile-validated outgoing send scripts and clearly labelled incoming receive-hook templates
    * Replay only complete outgoing captures after an in-menu confirmation
* ClosureSpy
    * Log calls of closures
    * View general information of closures (location, protos, constants, etc.)
    * Inspect call chains, caller source, calling scripts, and nested caller functions from the logs pane

## Maintenance and validation

Common log storage, argument filters, value snapshots, script models, scanner iteration, and
inspector formatting live in shared modules. Repeated execution restores the prior session's
owned globals and resources; failed initialization cleans up partial state. Scanners yield in
bounded batches and stop when their view closes or a newer search replaces them.

Run the regression suites with Lua 5.4 from the repository root:

```sh
for spec in tests/*_spec.lua; do lua5.4 "$spec" || exit 1; done
```

The suites execute the real modules with mocked Roblox/Potassium boundaries, including
initializer failures, cache integrity, concurrent imports, packed nil/false values, history
limits, replay generation, scanner cancellation, UI control cleanup, and source cache ownership.
Live Roblox rendering and executor behavior still need an in-client smoke test; command-line
checks do not establish frame rates or compatibility with a particular running game.


## Images/Videos
<p align="center">
    <img src="https://i.gyazo.com/63afdd764cdca533af5ebca843217a7e.gif" />
</p>
