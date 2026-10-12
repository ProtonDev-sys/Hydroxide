# Configuration

Set `getgenv().HydroxideConfig` before running the quick-start line. Omitted options use the defaults below; only supply overrides you need. Settings are read at startup, so restart Hydroxide after changing this table.

## Loading and capture switches

| Option | Default | Behavior |
| --- | --- | --- |
| `owner` | `"ProtonDev-sys"` | GitHub repository owner. |
| `repository` | `"Hydroxide"` | GitHub repository name. |
| `branch` | `"main"` | Branch/tag to resolve once, or a full 40-character commit SHA. |
| `web` | `true` | Set `false` to load modules from `hydroxide/` in the executor workspace. |
| `autoLaunch` | `true` | Set `false` to initialize the runtime without opening the UI. |
| `cache` | `true` | Reuse persistent source only when its Git blob hash can be verified; `false` uses downloads plus session memory. |
| `captureExecutorCalls` | `true` | Include executor-origin remote calls; `false` requires confirmed game-thread attribution. |
| `captureCallStacks` | `true` | Capture supported call stacks within the configured rate limit. |
| `suppressScriptErrors` | `false` | Legacy opt-in suppression of existing ScriptContext.Error connections, restored on exit. |

## Numeric limits

Limits are floored and clamped to the supported range. Invalid values, NaN, and infinities use the default. Byte values count bytes, not characters. Limits for history payloads are accounting bounds, not a measurement of all Lua/Roblox object overhead.

| Option | Default | Minimum | Maximum |
| --- | ---: | ---: | ---: |
| `maxStackFrames` | 24 | 1 | 64 |
| `maxStackCapturesPerSecond` | 60 | 1 | 1000 |
| `maxRemoteLogs` | 500 | 25 | 5000 |
| `maxClosureLogs` | 500 | 25 | 5000 |
| `maxRenderedLogs` | 100 | 10 | 500 |
| `maxArgumentPreviewLength` | 240 | 40 | 2000 |
| `maxHexBytes` | 512 | 32 | 8192 |
| `maxConcurrentImports` | 6 | 1 | 12 |
| `maxGeneratedTableEntries` | 256 | 8 | 5000 |
| `maxGeneratedTables` | 512 | 8 | 5000 |
| `maxGeneratedTableDepth` | 16 | 1 | 64 |
| `maxGeneratedStringBytes` | 65536 | 256 | 1048576 |
| `maxGeneratedBufferBytes` | 65536 | 256 | 1048576 |
| `maxGeneratedOutputBytes` | 1048576 | 16384 | 8388608 |
| `maxValueViewDepth` | 8 | 1 | 32 |
| `maxValueViewEntries` | 512 | 1 | 10000 |
| `maxValueViewTableEntries` | 256 | 1 | 5000 |
| `maxValueViewBytes` | 65536 | 1024 | 1048576 |
| `maxInspectorBytes` | 524288 | 8192 | 8388608 |
| `maxFunctionSourceCacheEntries` | 64 | 1 | 256 |
| `maxFunctionSourceCacheBytes` | 2097152 | 32768 | 16777216 |
| `maxConditionBufferBytes` | 4096 | 64 | 65536 |
| `maxCapturedCallBytes` | 262144 | 4096 | 8388608 |
| `maxCapturedArguments` | 128 | 8 | 1024 |
| `maxRemoteHistoryBytes` | 16777216 | 65536 | 268435456 |
| `maxClosureHistoryBytes` | 16777216 | 65536 | 268435456 |
| `maxScriptRows` | 750 | 50 | 2000 |
| `maxModuleRows` | 750 | 50 | 2000 |
| `maxModuleFunctions` | 32 | 1 | 128 |
| `maxRakNetLogs` | 500 | 0 | 5000 |
| `maxRenderedRakNetLogs` | 100 | 10 | 500 |
| `maxRakNetPacketBytes` | 65536 | 256 | 16777216 |
| `maxRakNetHistoryBytes` | 16777216 | 0 | 67108864 |
| `maxRakNetGeneratedOutputBytes` | 1048576 | 1024 | 8388608 |

Remote and closure log limits apply to each tracked remote/closure history. RakNet limits apply across its shared packet history. Visible-row limits control rendering separately from retained history.

For RakNet, explicit `0` disables that individual retention bound. Set **both** `maxRakNetLogs = 0` and `maxRakNetHistoryBytes = 0` to retain every snapshot until **Clear**; memory then grows with the captured traffic. Individual packet and generated-output limits still apply.

## Pinning and cache integrity

For a reproducible version, set `branch` to the full commit SHA and use that same SHA in the initial `init.lua` URL. The default quick start follows `main`; it resolves a commit for the subsequent imports. A mutable initial URL is not a publisher signature or a guarantee about future updates.

Source files are limited to 1 MiB each. Module paths must be safe relative paths without extensions; `rbxassetid://` imports must contain only a numeric ID. A branch that cannot be resolved stops startup with an error. A full commit SHA avoids the branch-resolution request.

The verified disk cache is stored beneath `hydroxide/cache/<owner>/<repository>/<commit>/`, or in similarly namespaced flat files when folder APIs are absent. The loader fetches the commit's file list over HTTPS and verifies each cached source against its Git blob SHA-1. It never executes a cache mismatch. If the hash capability or trusted file list is unavailable, it skips persistent cache and uses the resolved HTTPS source. This checks file integrity against GitHub; it does not sandbox downloaded Lua or authenticate the publisher independently of GitHub.

The runtime exposes `getgenv().oh.Runtime.Commit` and `getgenv().oh.Runtime.PersistentCache` for diagnostics. Existing caches in the old layout are ignored; they do not need to be deleted to launch.

## Programmatic startup and exit

```lua
getgenv().HydroxideConfig = { autoLaunch = false }
local runtime = assert(loadstring(httpget("https://raw.githubusercontent.com/ProtonDev-sys/Hydroxide/main/init.lua"), "Hydroxide"))()
getgenv().import("ui/main") -- open when needed
runtime.Exit() -- restore owned globals, listeners, and hooks
```

`Exit()` is idempotent. If a runtime API refuses cleanup, it returns `false` and retains the session for a later cleanup retry. The next launch retries cleanup before replacing the session. A saved old `Exit` function cannot close a newer runtime. Globals changed by another script after Hydroxide published them are preserved.

## Local development

Copy repository Lua files into a `hydroxide/` directory in the executor workspace, set `web = false`, and execute the local `init.lua`. Keep the directory structure, including shared helpers. Local mode does not request GitHub files or verify a remote file manifest.
