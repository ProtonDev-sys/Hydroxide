# Runtime and UI compatibility

Last reviewed: 2026-10-12.

Hydroxide keeps runtime-specific APIs behind the compatibility table created in `init.lua`. Feature modules should read from `oh.Methods`, declare their `RequiredMethods`, and fail closed when an optional capability is unavailable. UI modules should not call executor globals directly.

## Potassium API surface

The compatibility boundary consumes these canonical names from the current Potassium API reference:

- Environment and instance access: `filtergc`, `getgc`, `getsenv`, `gettenv`, and `gethui`.
- Script inspection: `getloadedmodules`, `getrunningscripts`, `getscriptbytecode`, `getscriptclosure`, `getscriptfromthread`, `getcallingscript`, `getscripthash`, `getscripts`, `getthreadidentity`, `setthreadidentity`, and `decompile`.
- Debug and closure inspection: `debug.getcallstack`, `debug.getinfo`, constants, protos, stack values, and upvalues; plus `hookfunction`, `restorefunction`, and closure classification helpers.
- Off-thread hooks: `oth.hook`, `oth.unhook`, `oth.get_root_callback`, `oth.get_original_thread`, and `oth.is_hook_thread`.
- RakNet: `raknet.add_send_hook`, `raknet.remove_send_hook`, `raknet.add_receive_hook`, `raknet.remove_receive_hook`, and `raknet.send`.

Legacy executor aliases may be accepted only inside `init.lua`. New modules should use the canonical lower-case key exposed by `oh.Methods` and should wrap optional runtime calls with `pcall` where failure is recoverable. Potassium APIs that are not needed by a current feature, such as `getrenv`, `getscriptthread`, or `dumpbytecode`, are intentionally not promoted into a module requirement merely because they exist in the executor reference.

Primary reference: <https://docs.potassium.pro/llms.txt>

### Verified boundary contracts

- `request({ Url = url, Method = "GET" })` returns a response table. A numeric `StatusCode` must be in the 200–299 range; `Success` is a fallback only when status is absent. Accept only a nonempty string body within the source size limit. Potassium does not document HTTP timeout/cancellation options, so the loader does not invent them.
- `httpget(url)` supplies the simple launch path. `loadstring(source, chunkname)` returns a function, or `nil, error`; compilation must succeed before invoking the chunk. Startup errors unwind partial resources and published globals.
- `crypt.hash(data, "sha1")` supports verification of Git's `blob <byte length>\0<source>` object representation. A known empty-input digest checks the hash result format first. Only a file list fetched over HTTPS for the resolved commit can authorize reuse of a local cached source. See [configuration](CONFIGURATION.md) for the trust boundary and fallback behavior.
- `debug.getupvalue` returns the value, including `false` or `nil`; it does not return Lua 5.1's name/value pair. `debug.getupvalues` returns indexed values. `debug.getproto(fn, index, true)` returns active functions in a table; the default call returns a cloned function.
- Runtime globals are shared. Preserve existing values when publishing legacy aliases, restore only values still owned by the closing session, and capture the session in asynchronous work. Do not let an old callback populate a replacement session.

Primary references:

- <https://docs.potassium.pro/api-reference/Miscellaneous%20Library/request>
- <https://docs.potassium.pro/api-reference/Miscellaneous%20Library/httpget>
- <https://docs.potassium.pro/api-reference/Closure%20Library/loadstring>
- <https://docs.potassium.pro/api-reference/Crypt%20Library/crypt.hash>
- <https://docs.potassium.pro/api-reference/Debug%20Library/debug.getupvalue>
- <https://docs.potassium.pro/api-reference/Debug%20Library/debug.getproto>
- <https://git-scm.com/book/en/v2/Git-Internals-Git-Objects>

## Roblox UI conventions

Shared controls follow these rules:

- Use `GuiButton.Activated` for primary actions and `GuiButton.SecondaryActivated` for cross-platform secondary actions, with legacy signal fallbacks isolated in `ui/ControlUtil.lua`.
- Respect `GuiService.ReducedMotionEnabled` by setting tween duration to zero.
- Keep the main title bar and popup actions recoverable inside the current viewport.
- Give shared interactive controls a minimum 28-pixel target and make them selectable for keyboard/gamepad navigation.
- Own and disconnect dynamic event connections. GUI-bound signals belong to their instance and should not leave a permanent entry in `oh.Events` for each transient row. Runtime teardown still sweeps non-GUI listeners and other session resources.
- Measure text with enum font values and wrap/cap modal content against the active UI viewport.

Primary references:

- <https://create.roblox.com/docs/ui/buttons>
- <https://create.roblox.com/docs/production/publishing/accessibility>
- <https://create.roblox.com/docs/reference/engine/classes/TextService>

## Luau maintenance rules

- Prefer locals and explicit module boundaries over additional globals.
- Keep compatibility shims at system boundaries rather than duplicating aliases throughout the app.
- Bound history, generated output, text measurement, cache sizes, and background work.
- Avoid mutating a collection while iterating it unless the iteration contract is explicit.
- Treat `getfenv`/`setfenv` as compatibility-only introspection tools; they inhibit normal Luau analysis and optimization.
- Run the repository specs after changes and keep changed files free of parser errors and lint-style issues such as shadowed or unused state.

Shared implementations live in `objects/LogBuffer.lua`, `objects/ArgumentFilter.lua`,
`objects/ValueSnapshot.lua`, `objects/ScriptModel.lua`, `modules/Scanner.lua`, and
`ui/InspectUtil.lua`. Keep fixes in those shared boundaries; preserve the public exports of
the feature modules that consume them. Regression tests should execute those real modules
with controlled API boundaries rather than duplicating their implementation in a test.

Primary references:

- <https://luau.org/getting-started/>
- <https://luau.org/lint/>
- <https://luau.org/performance/>
