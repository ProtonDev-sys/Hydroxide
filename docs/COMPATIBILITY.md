# Runtime and UI compatibility

Last reviewed: 2026-08-20.

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

## Roblox UI conventions

Shared controls follow these rules:

- Use `GuiButton.Activated` for primary actions and `GuiButton.SecondaryActivated` for cross-platform secondary actions, with legacy signal fallbacks isolated in `ui/ControlUtil.lua`.
- Respect `GuiService.ReducedMotionEnabled` by setting tween duration to zero.
- Keep the main title bar and popup actions recoverable inside the current viewport.
- Give shared interactive controls a minimum 28-pixel target and make them selectable for keyboard/gamepad navigation.
- Own and disconnect dynamic event connections. Runtime teardown still performs a final sweep through `oh.Events`.
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

Primary references:

- <https://luau.org/getting-started/>
- <https://luau.org/lint/>
- <https://luau.org/performance/>
