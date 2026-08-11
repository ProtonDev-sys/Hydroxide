local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local RemoteSpy = {}
local Methods = import("modules/RemoteSpy")
local ClosureSpy = import("modules/ClosureSpy")
local Closure = import("objects/Closure")

if not hasMethods(Methods.RequiredMethods) then
	return RemoteSpy
end

if not Methods.IsSupported then
	if not oh.RemoteSpyUnsupportedWarned then
		oh.RemoteSpyUnsupportedWarned = true

		if type(warn) == "function" then
			warn("[Hydroxide] RemoteSpy is unavailable: this executor does not expose a supported remote hook path.")
		end
	end

	return RemoteSpy
end

local Prompt = import("ui/controls/Prompt")
local CheckBox = import("ui/controls/CheckBox")
local Dropdown = import("ui/controls/Dropdown")
local List, ListButton = import("ui/controls/List")
local MessageBox, MessageType = import("ui/controls/MessageBox")
local TextViewer = import("ui/controls/TextViewer")
local FunctionInspector = import("ui/controls/FunctionInspector")
local ActionPanel = import("ui/controls/ActionPanel")
local ContextMenu, ContextMenuButton = import("ui/controls/ContextMenu")
local TabSelector = import("ui/controls/TabSelector")

local Base = import("rbxassetid://11389137937").Base
local Assets = import("rbxassetid://5042114982").RemoteSpy

local Prompts = Base.Prompts
local Page = Base.Body.Pages.RemoteSpy

local RemoteList = Page.List
local ListFlags = RemoteList.Flags
local ListQuery = RemoteList.Query
local ListSearch = ListQuery.Search
local ListRefresh = ListQuery.Refresh
local ListResults = RemoteList.Results.Clip.Content

local RemoteLogs = Page.Logs
local LogsButtons = RemoteLogs.Buttons
local LogsRemote = RemoteLogs.RemoteObject
local LogsBack = RemoteLogs.Back
local LogsClip = RemoteLogs.Results.Clip
local LogsResults = LogsClip.Content

local RemoteConditions = Page.Conditions
local ConditionsRemote = RemoteConditions.RemoteObject
local ConditionsButtons = RemoteConditions.Buttons
local ConditionsResults = RemoteConditions.Results.Clip.Content
local ConditionsBack = RemoteConditions.Back

local NewRemoteCondition = Prompts.NewRemoteCondition
local NewConditionInner = NewRemoteCondition.Inner
local NewConditionButtons = NewConditionInner.Buttons
local NewConditionContent = NewConditionInner.Content
local NewConditionIndex = NewConditionContent.Index

local remotesViewing = Methods.RemotesViewing
local currentRemotes = Methods.CurrentRemotes

local icons = {
	type = "rbxassetid://4702850565",
	status = "rbxassetid://4909102841",
	valueType = "rbxassetid://4702850565",
	block = "rbxassetid://4891641806",
	unblock = "rbxassetid://4891642508",
	ignore = "rbxassetid://4842578510",
	unignore = "rbxassetid://4842578818",
	RemoteEvent = "rbxassetid://4229806545",
	UnreliableRemoteEvent = "rbxassetid://4229806545",
	RemoteFunction = "rbxassetid://4229810474",
	BindableEvent = "rbxassetid://4229809371",
	BindableFunction = "rbxassetid://4229807624",
	copy = "rbxassetid://4891705738",
	arguments = "rbxassetid://4666594276",
	results = "rbxassetid://4666593882",
	hex = "rbxassetid://9058292613",
	repeatCall = "rbxassetid://4907151581",
	script = "rbxassetid://4800244808",
	source = "rbxassetid://4891705738",
	spy = "rbxassetid://4666593447",
	stack = "rbxassetid://5179169654",
}

local constants = {
	fadeLength = TweenInfo.new(0.15),
	textWidth = Vector2.new(1337420, 20),
	normalColor = Color3.new(1, 1, 1),
	blockedColor = Color3.fromRGB(170, 0, 0),
	ignoredColor = Color3.fromRGB(100, 100, 100),
	maxHexBytes = 4096,
}

oh.Settings = oh.Settings or {}
if type(oh.Settings.MaxRenderedLogs) ~= "number" and type(oh.Settings.maxRenderedLogs) ~= "number" then
	oh.Settings.MaxRenderedLogs = 100
end

local newRemoteCondition = Prompt.new(NewRemoteCondition)
local conditionStatus = Dropdown.new(NewConditionContent.Status)
local conditionType = Dropdown.new(NewConditionContent.Type)
local conditionValueType = Dropdown.new(NewConditionContent.ValueType)

local supportedConditionTypes = {
	"nil",
	"string",
	"number",
	"boolean",
	"table",
	"function",
	"thread",
	"buffer",
	"Instance",
	"EnumItem",
	"BrickColor",
	"CFrame",
	"Color3",
	"Vector2",
	"Vector2int16",
	"Vector3",
	"Vector3int16",
	"UDim",
	"UDim2",
	"Rect",
	"Ray",
	"Region3",
	"Region3int16",
	"NumberRange",
	"NumberSequence",
	"NumberSequenceKeypoint",
	"ColorSequence",
	"ColorSequenceKeypoint",
	"DateTime",
	"TweenInfo",
	"PhysicalProperties",
	"PathWaypoint",
	"RaycastParams",
	"OverlapParams",
	"Font",
	"Content",
	"SharedTable",
	"Axes",
	"Faces",
	"Random",
}

for _, valueType in ipairs(supportedConditionTypes) do
	conditionType:AddOption(valueType, oh.Constants.Types[valueType] or oh.Constants.Types.userdata)
end

conditionStatus:AddOption("Ignore", icons and icons.ignore)
conditionStatus:AddOption("Block", icons and icons.block)
conditionValueType:AddOption("Type")
conditionValueType:AddOption("Value")

local remoteList = List.new(ListResults, true)
local remoteLogs = List.new(LogsResults)
local remoteConditions = List.new(ConditionsResults, true)

local currentLogs = setmetatable({}, { __mode = "k" })
local removed = setmetatable({}, { __mode = "k" })

local selected = {}
local updateCallInspector

local pathContext = ContextMenuButton.new("rbxassetid://4891705738", "Get Remote Path")
local conditionContext = ContextMenuButton.new("rbxassetid://4891633802", "Call Conditions")
local clearContext = ContextMenuButton.new("rbxassetid://4892169181", "Clear Calls")
local ignoreContext = ContextMenuButton.new("rbxassetid://4842578510", "Ignore Calls")
local blockContext = ContextMenuButton.new("rbxassetid://4891641806", "Block Calls")
local removeContext = ContextMenuButton.new("rbxassetid://4702831188", "Remove Log")

local scriptContext = ContextMenuButton.new(icons.script, "View Replay Code")
local copyScriptContext = ContextMenuButton.new(icons.copy, "Copy Replay Code")
local argumentsContext = ContextMenuButton.new(icons.arguments, "View Arguments")
local returnsContext = ContextMenuButton.new(icons.results, "View Returns")
local callStackContext = ContextMenuButton.new(icons.stack, "View Call Stack")
local functionStackContext = ContextMenuButton.new(icons.spy, "View Function Stack")
local inspectFunctionContext = ContextMenuButton.new(icons.spy, "Inspect Calling Function")
local inspectScriptContext = ContextMenuButton.new(icons.source, "Inspect Calling Script")
local callingScriptContext = ContextMenuButton.new(icons.copy, "Copy Calling Script Path")
local spyClosureContext = ContextMenuButton.new(icons.spy, "Spy Calling Function")
local repeatCallContext = ContextMenuButton.new(icons.repeatCall, "Replay Call")
local viewAsHexContext = ContextMenuButton.new(icons.hex, "Toggle Binary Hex View")
local diagnosticsContext = ContextMenuButton.new(icons.status, "View Capture Diagnostics")

local removeConditionContext = ContextMenuButton.new("rbxassetid://4702831188", "Remove Condition")

local pathContextSelected = ContextMenuButton.new("rbxassetid://4891705738", "Get Paths")
local clearContextSelected = ContextMenuButton.new("rbxassetid://4892169181", "Clear Calls")
local ignoreContextSelected = ContextMenuButton.new("rbxassetid://4842578510", "Ignore Calls")
local blockContextSelected = ContextMenuButton.new("rbxassetid://4891641806", "Block Calls")
local unignoreContextSelected = ContextMenuButton.new("rbxassetid://4842578818", "Unignore Calls")
local unblockContextSelected = ContextMenuButton.new("rbxassetid://4891642508", "Unblock Calls")
local removeContextSelected = ContextMenuButton.new("rbxassetid://4702831188", "Remove Logs")

local removeConditionContextSelected = ContextMenuButton.new("rbxassetid://4702831188", "Remove Conditions")

local remoteListMenu =
	ContextMenu.new({ pathContext, conditionContext, clearContext, ignoreContext, blockContext, removeContext })
local remoteListMenuSelected = ContextMenu.new({
	pathContextSelected,
	clearContextSelected,
	ignoreContextSelected,
	unignoreContextSelected,
	blockContextSelected,
	unblockContextSelected,
	removeContextSelected,
})
local remoteLogsMenu = ContextMenu.new({
	scriptContext,
	copyScriptContext,
	argumentsContext,
	returnsContext,
	callStackContext,
	functionStackContext,
	inspectFunctionContext,
	inspectScriptContext,
	callingScriptContext,
	spyClosureContext,
	repeatCallContext,
	viewAsHexContext,
	diagnosticsContext,
})
local remoteConditionMenu = ContextMenu.new({ removeConditionContext })
local remoteConditionMenuSelected = ContextMenu.new({ removeConditionContextSelected })

local queuedLogRenders = {}
local queuedCountUpdates = {}
local logRenderTaskQueued = false
local countUpdateTaskQueued = false
local renderedCallLog
local renderedCallButtons = {}
local unpackValues = table.unpack or unpack
local detailsGeneration = 0
local alive = true

local function pageIsAlive()
	return alive and Page ~= nil and Page.Parent ~= nil
end

local function pageIsActive()
	return pageIsAlive() and Page.Visible
end

local function getStatusSafely()
	if not oh or type(oh.getStatus) ~= "function" then
		return nil
	end

	local ran, status = pcall(oh.getStatus)
	return ran and status or nil
end

local function setStatusSafely(status)
	if not oh or type(oh.setStatus) ~= "function" then
		return false
	end

	return pcall(oh.setStatus, status)
end

local function trackConnection(connection)
	if connection and oh and oh.Events then
		oh.Events[#oh.Events + 1] = connection
	end

	return connection
end

local function invalidateAsyncWork()
	if not alive then
		return
	end

	alive = false
	detailsGeneration = detailsGeneration + 1
	queuedLogRenders = {}
	queuedCountUpdates = {}
	logRenderTaskQueued = false
	countUpdateTaskQueued = false
end

local lifecycle = {
	Connected = true,
}

function lifecycle:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false
	invalidateAsyncWork()
end

trackConnection(lifecycle)

local destroyingRan, destroyingConnection = pcall(function()
	return Page.Destroying:Connect(invalidateAsyncWork)
end)

if destroyingRan then
	trackConnection(destroyingConnection)
end

trackConnection(Page.AncestryChanged:Connect(function(_, parent)
	if parent == nil then
		invalidateAsyncWork()
	end
end))

local function getMaxRenderedLogs()
	local settings = oh.Settings or {}
	local value = tonumber(settings.MaxRenderedLogs or settings.maxRenderedLogs)

	if not value or value < 1 then
		return 100
	end

	return math.floor(value)
end

local function getMaxHexBytes()
	local settings = oh.Settings or {}
	local value = tonumber(settings.MaxHexBytes or settings.maxHexBytes) or constants.maxHexBytes

	return math.max(1, math.floor(value))
end

local function getArgCount(args)
	return type(args) == "table" and (tonumber(args.n) or #args) or 0
end

local function clearSelectedCall(button)
	if button and selected.callPodButton ~= button then
		return
	elseif button then
		selected.callPodButton = nil

		if updateCallInspector then
			updateCallInspector()
		end

		return
	end

	selected.args = nil
	selected.callingScript = nil
	selected.func = nil
	selected.callInfo = nil
	selected.callPodButton = nil
	selected.callRemote = nil
	selected.hexViewEnabled = nil

	if updateCallInspector then
		updateCallInspector()
	end
end

local function selectedCallAlive()
	return selected.callInfo ~= nil
end

local function guardSelectedCall(title)
	if not pageIsActive() then
		return false
	elseif selectedCallAlive() then
		return true
	end

	clearSelectedCall()
	detailsGeneration = detailsGeneration + 1
	TextViewer.Show(title or "No Call Selected", "Select a captured call to inspect.")
	return false
end

local function renderDetails(title, text, options)
	if not pageIsActive() then
		return nil
	end

	local generation = detailsGeneration
	local viewerOptions = {}

	for name, value in pairs(type(options) == "table" and options or {}) do
		viewerOptions[name] = value
	end

	local onHide = viewerOptions.OnHide
	viewerOptions.OnHide = function(viewer)
		if generation == detailsGeneration then
			detailsGeneration = detailsGeneration + 1
		end

		if type(onHide) == "function" then
			pcall(onHide, viewer)
		end
	end
	return TextViewer.Show(title, text, viewerOptions)
end

local function showDetails(title, text, options)
	detailsGeneration = detailsGeneration + 1
	renderDetails(title, text, options)
end

local function showDetailsAsync(title, loadingText, callback, options)
	if not guardSelectedCall(title) then
		return
	end

	detailsGeneration = detailsGeneration + 1
	local generation = detailsGeneration
	local callInfo = selected.callInfo
	renderDetails(title, loadingText)
	local function requestIsActive()
		return pageIsActive() and generation == detailsGeneration and selected.callInfo == callInfo
	end

	task.spawn(function()
		if not requestIsActive() then
			return
		end

		local text

		local function inspect()
			local ran, result = pcall(callback, callInfo, requestIsActive)
			text = ran and result or ("Inspector failed: " .. tostring(result))
		end

		local inspected, inspectError = pcall(function()
			if type(withExecutorIdentity) == "function" then
				withExecutorIdentity(inspect)
			else
				inspect()
			end
		end)

		if not inspected then
			text = "Inspector failed: " .. tostring(inspectError)
		end

		if requestIsActive() then
			renderDetails(title, text or "No inspection data was returned.", options)
		end
	end)
end

local function resetRenderedCalls()
	renderedCallLog = nil
	renderedCallButtons = {}
	clearSelectedCall()
	remoteLogs:Clear()
end

local function getRemoteMethod(remoteInstance, callInfo)
	if callInfo and type(callInfo.method) == "string" then
		return callInfo.method
	end

	local remoteClassName = remoteInstance.ClassName

	if remoteClassName == "RemoteEvent" or remoteClassName == "UnreliableRemoteEvent" then
		return "FireServer"
	elseif remoteClassName == "RemoteFunction" then
		return "InvokeServer"
	elseif remoteClassName == "BindableEvent" then
		return "Fire"
	elseif remoteClassName == "BindableFunction" then
		return "Invoke"
	end
end

local function truncate(value, limit)
	value = tostring(value)

	if #value > limit then
		return value:sub(1, limit) .. "... (" .. #value .. " chars)"
	end

	return value
end

local function instanceSummary(value)
	local ran, fullName = pcall(function()
		return value:GetFullName()
	end)

	if ran and fullName then
		return fullName
	end

	return tostring(value)
end

local function argumentSummary(value)
	if type(value) == "table" and rawget(value, "__hydroxideCaptureMarker") == true then
		return ("%s capture unavailable: %s"):format(tostring(value.Kind or "value"), tostring(value.Detail or "unknown reason"))
	end

	if type(summarizeValue) == "function" then
		local maxLength = (oh.Settings and oh.Settings.MaxArgumentPreviewLength) or 140
		local ran, result = pcall(summarizeValue, value, maxLength)

		if ran and type(result) == "string" then
			return result
		end
	end

	local valueType = typeof(value)
	local rawType = type(value)

	if rawType == "string" then
		return '"' .. truncate(value:gsub("\n", "\\n"), 120) .. '"'
	elseif rawType == "table" or valueType == "table" then
		local count = 0

		for _key in pairs(value) do
			count = count + 1

			if count >= 1000 then
				return "table (1000+ entries)"
			end
		end

		return ("table (%d entries)"):format(count)
	elseif rawType == "function" then
		return "function"
	elseif valueType == "Instance" then
		return truncate(instanceSummary(value), 140)
	elseif rawType == "nil" then
		return "nil"
	end

	return truncate(tostring(value), 140)
end

local function formatTimestamp(timestamp)
	if type(timestamp) ~= "number" then
		return "unknown"
	end

	local seconds = math.floor(timestamp)
	local milliseconds = math.floor((timestamp - seconds) * 1000 + 0.5) % 1000
	local ran, formatted = pcall(os.date, "%Y-%m-%d %H:%M:%S", seconds)

	if ran and type(formatted) == "string" then
		return ("%s.%03d local"):format(formatted, milliseconds)
	end

	return ("%.3f"):format(timestamp)
end

local function safeInstancePath(instance)
	if typeof(instance) ~= "Instance" then
		return nil
	end

	local ran, path = pcall(getInstancePath, instance)
	return ran and path or nil
end

local function cleanSource(source)
	if type(source) ~= "string" then
		return "unknown"
	end

	return source:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[@=]", "")
end

local function describePackedValues(title, values)
	local count = getArgCount(values)
	local lines = {
		title,
		("Count: %d"):format(count),
		"",
	}

	if count == 0 then
		lines[#lines + 1] = "(none)"
		return table.concat(lines, "\n")
	end

	for index = 1, count do
		local value = values[index]
		local valueType = typeof(value)
		local detail = valueType == "Instance" and safeInstancePath(value) or argumentSummary(value)
		lines[#lines + 1] = ("[%02d]  %-18s  %s"):format(index, valueType, detail or "unavailable")
	end

	return table.concat(lines, "\n")
end

local function describeFunction(func, isAlive)
	return FunctionInspector.DescribeFunction(func, {
		Summarize = argumentSummary,
		GetPath = safeInstancePath,
		IsAlive = isAlive,
	})
end

local function describeStackFunctions(callInfo, isAlive)
	return FunctionInspector.DescribeStack(callInfo and callInfo.stack, {
		Summarize = argumentSummary,
		GetPath = safeInstancePath,
		IsAlive = isAlive,
	})
end

local function describeScript(scriptInstance, isAlive)
	local function inspectionIsActive()
		return type(isAlive) ~= "function" or isAlive()
	end

	if not inspectionIsActive() then
		return "Calling-script inspection was cancelled."
	end

	if typeof(scriptInstance) ~= "Instance" then
		return "No calling script was captured for this call."
	end

	local lines = {}
	lines[#lines + 1] = "Name: " .. scriptInstance.Name
	lines[#lines + 1] = "Class: " .. scriptInstance.ClassName
	lines[#lines + 1] = "Path: " .. (safeInstancePath(scriptInstance) or "unavailable")

	if type(decompile) == "function" and inspectionIsActive() then
		local decompiled, source = pcall(decompile, scriptInstance)

		if not inspectionIsActive() then
			return "Calling-script inspection was cancelled."
		end

		if decompiled and type(source) == "string" and source ~= "" then
			local settings = oh and oh.Settings or {}
			local maximum = math.max(
				8192,
				math.min(8388608, math.floor(tonumber(settings.MaxInspectorBytes or settings.maxInspectorBytes) or 524288))
			)
			local marker = "\n-- ... source truncated by the inspector safety limit ..."

			if #source > maximum then
				source = source:sub(1, math.max(0, maximum - #marker)) .. marker
			end

			lines[#lines + 1] = ""
			lines[#lines + 1] = "-- Decompiled source"
			lines[#lines + 1] = source
		else
			lines[#lines + 1] = ""
			lines[#lines + 1] = "Decompiler failed or returned no source."
		end
	else
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Decompiler is not available in this executor."
	end

	return table.concat(lines, "\n")
end

local function describeCallStack(callInfo)
	if not callInfo then
		return "No call is selected."
	end

	local caller = type(callInfo.caller) == "table" and callInfo.caller or {}
	local state = callInfo.blocked and "Blocked"
		or (callInfo.error and "Forward error")
		or (callInfo.forwarded and "Forwarded")
		or "Captured"
	local callerName = caller.name or "anonymous"
	local callerSource = cleanSource(caller.shortSource or caller.source)
	local callerLine = tonumber(caller.line)
	local location = callerSource .. ":" .. (callerLine and tostring(math.floor(callerLine)) or "?")
	local scriptPath = safeInstancePath(callInfo.script) or "unknown"
	local lines = {
		"REMOTE CALL TRACE",
		("Call: %s"):format(tostring(callInfo.method or "unknown")),
		("State: %s"):format(state),
		("Captured: %s"):format(formatTimestamp(callInfo.timestamp)),
		("Duration: %s"):format(
			type(callInfo.durationMs) == "number" and ("%.3f ms"):format(callInfo.durationMs) or "not available"
		),
		("Capture path: %s%s"):format(
			tostring(caller.captureSource or "unknown"),
			callInfo.offThread and " (off-thread)" or " (original thread)"
		),
		("Calling script: %s"):format(scriptPath),
		("Caller: %s"):format(tostring(callerName)),
		("Location: %s"):format(location),
		("Arguments: %d | Returns: %d"):format(getArgCount(callInfo.args), getArgCount(callInfo.returns)),
	}

	if callInfo.error then
		lines[#lines + 1] = "Error: " .. tostring(callInfo.error)
	end

	if caller.limitation then
		lines[#lines + 1] = "Capture note: " .. tostring(caller.limitation)
	end

	lines[#lines + 1] = ""

	local stack = callInfo.stack

	if type(stack) ~= "table" or #stack == 0 then
		lines[#lines + 1] = "No structured stack was captured for this call."
		return table.concat(lines, "\n")
	end

	lines[#lines + 1] = ("External call chain (%d frames; native and Hydroxide frames removed):"):format(#stack)
	lines[#lines + 1] = "First frame is closest to the remote call; arrows walk outward through the caller chain."

	for index, frame in ipairs(stack) do
		if type(frame) == "table" then
			local name = frame.name or frame.Name or "anonymous"
			local source = cleanSource(frame.shortSource or frame.short_src or frame.source or frame.Source)
			local line = tonumber(frame.line or frame.currentline or frame.Line)
			local scriptInstance = frame.script or frame.Script
			local frameScriptPath = safeInstancePath(scriptInstance)
			local func = frame.func or frame.Function or frame.functionValue
			lines[#lines + 1] = ("%02d  %s%s"):format(
				index,
				tostring(name),
				func and ("  [" .. tostring(func) .. "]") or ""
			)
			lines[#lines + 1] = ("    %s:%s%s"):format(
				source,
				line and tostring(math.floor(line)) or "?",
				frameScriptPath and ("  [" .. frameScriptPath .. "]") or ""
			)

			if frame.what then
				lines[#lines + 1] = "    kind: " .. tostring(frame.what)
			end

			if index < #stack then
				lines[#lines + 1] = "    ->"
			end
		else
			lines[#lines + 1] = ("%02d  %s"):format(index, tostring(frame))
		end
	end

	return table.concat(lines, "\n")
end

local function describeDiagnostics()
	local diagnostics = Methods.Diagnostics or {}
	local remoteModel = selected.remoteLog and selected.remoteLog.Remote
	local callInfo = selected.callInfo or {}
	local lines = {
		"REMOTE CAPTURE DIAGNOSTICS",
		("Selected state: %s"):format(
			callInfo.blocked and "blocked"
				or (callInfo.error and "forward error")
				or (callInfo.forwarded and "forwarded")
				or "captured"
		),
		("Capture route: %s"):format(tostring(callInfo.caller and callInfo.caller.captureSource or "unknown")),
		("Visible row: %s"):format(
			selected.callPodButton and selected.callPodButton.Instance and selected.callPodButton.Instance.Parent and "yes"
				or "no (selection retained in memory)"
		),
		("Remote blocked: %s"):format(tostring(remoteModel and remoteModel.Blocked == true)),
		("Remote ignored: %s"):format(tostring(remoteModel and remoteModel.Ignored == true)),
		"",
		"Session counters:",
	}
	local counterNames = {
		"CallsCaptured",
		"CallsForwarded",
		"CallsBlocked",
		"ForwardErrors",
		"CallsDeduplicated",
		"CaptureErrors",
		"LogsDropped",
		"StackCaptures",
		"StackCapturesRateLimited",
		"DirectHooksInstalled",
		"DirectHookFailures",
		"OthHookAttempts",
		"OthHookFailures",
		"FunctionHookAttempts",
		"FunctionHookFailures",
	}

	for _, name in ipairs(counterNames) do
		lines[#lines + 1] = ("  %-28s %s"):format(name .. ":", tostring(diagnostics[name] or 0))
	end

	lines[#lines + 1] = ""
	lines[#lines + 1] = "Namecall hook: "
		.. (diagnostics.NamecallHookInstalled and "installed" or (diagnostics.NamecallHookFailure or "not installed"))

	if type(diagnostics.LastCaptureError) == "table" then
		lines[#lines + 1] = ("Last capture error: %s - %s"):format(
			tostring(diagnostics.LastCaptureError.Stage or "unknown"),
			tostring(diagnostics.LastCaptureError.Error or "unknown")
		)
	end

	if type(diagnostics.LastHookError) == "table" then
		lines[#lines + 1] = ("Last hook error: %s - %s"):format(
			tostring(diagnostics.LastHookError.Stage or "unknown"),
			tostring(diagnostics.LastHookError.Error or "unknown")
		)
	end

	return table.concat(lines, "\n")
end

local callInspector

local function hasSelectedCall()
	return selectedCallAlive()
end

local function hasStringArg()
	local args = selected.args
	local argCount = getArgCount(args)

	for index = 1, argCount do
		local value = args[index]

		if type(value) == "string"
			or typeof(value) == "buffer"
			or (type(value) == "table" and value.__hydroxideCaptureMarker == true and type(value.Preview) == "string")
		then
			return true
		end
	end

	return false
end

updateCallInspector = function()
	if not callInspector then
		return
	end

	local selectedCall = hasSelectedCall() and selected.callInfo

	if not selectedCall then
		callInspector:SetStatus("Select a captured call to inspect")
		callInspector:SetEnabled("ReplayCode", false)
		callInspector:SetEnabled("CopyCode", false)
		callInspector:SetEnabled("Arguments", false)
		callInspector:SetEnabled("Returns", false)
		callInspector:SetEnabled("CallStack", false)
		callInspector:SetEnabled("FunctionStack", false)
		callInspector:SetEnabled("Function", false)
		callInspector:SetEnabled("ScriptSource", false)
		callInspector:SetEnabled("ScriptPath", false)
		callInspector:SetEnabled("SpyFunction", false)
		callInspector:SetEnabled("Repeat", false)
		callInspector:SetEnabled("Hex", false)
		callInspector:SetEnabled("Diagnostics", false)
		return
	end

	local callInfo = selected.callInfo
	local argCount = getArgCount(selected.args)
	local caller = typeof(callInfo.script) == "Instance" and callInfo.script.Name or "unknown script"
	local state = callInfo.blocked and "blocked"
		or (callInfo.error and "forward error")
		or (callInfo.forwarded and "forwarded")
		or "captured"
	local duration = type(callInfo.durationMs) == "number" and ("%.2f ms"):format(callInfo.durationMs) or "no timing"
	local status = ("%s | %d args | %s | %s"):format(tostring(callInfo.method or "unknown"), argCount, state, duration)
	local remoteInstance = selected.remoteLog and selected.remoteLog.Remote and selected.remoteLog.Remote.Instance
	local method = remoteInstance and getRemoteMethod(remoteInstance, selected.callInfo)

	callInspector:SetStatus(status, caller)
	local replayable = callInfo.replayable ~= false
	callInspector:SetEnabled("ReplayCode", replayable)
	callInspector:SetEnabled("CopyCode", replayable)
	callInspector:SetEnabled("Arguments", true)
	callInspector:SetEnabled("Returns", callInfo.completed == true)
	callInspector:SetEnabled("CallStack", true)
	callInspector:SetEnabled("FunctionStack", type(callInfo.stack) == "table" and #callInfo.stack > 0)
	callInspector:SetEnabled("Function", type(selected.func) == "function")
	callInspector:SetEnabled("ScriptSource", typeof(selected.callingScript) == "Instance")
	callInspector:SetEnabled("ScriptPath", typeof(selected.callingScript) == "Instance")
	callInspector:SetEnabled("SpyFunction", type(selected.func) == "function")
	callInspector:SetEnabled("Repeat", replayable and method ~= nil and remoteInstance ~= nil)
	callInspector:SetEnabled("Hex", hasStringArg())
	callInspector:SetEnabled("Diagnostics", true)
end

local function selectCall(log, button, callInfo)
	selected.args = callInfo.args
	selected.callingScript = callInfo.script
	selected.func = callInfo.func
	selected.callInfo = callInfo
	selected.callPodButton = button
	selected.callRemote = log
	selected.hexViewEnabled = button and button.hexViewEnabled == true or false
	updateCallInspector()
	showDetails("Remote Call Stack", describeCallStack(callInfo))
end

local function checkCurrentIgnored()
	local selectedRemote = (selected.remoteLog or selected.logContext).Remote

	LogsButtons.Ignore.Label.Text = (selectedRemote.Ignored and "Unignore") or "Ignore"
	LogsButtons.Ignore.Icon.Image = (selectedRemote.Ignored and icons.unignore) or icons.ignore

	local newWidth = TextService:GetTextSize(
		(selectedRemote.Ignored and "Unignore") or "Ignore",
		18,
		"SourceSans",
		constants.textWidth
	).X + 30

	LogsButtons.Ignore.Size = UDim2.new(0, newWidth, 0, 20)
end

local function checkCurrentBlocked()
	local selectedRemote = (selected.remoteLog or selected.logContext).Remote

	LogsButtons.Block.Label.Text = (selectedRemote.Blocked and "Unblock") or "Block"
	LogsButtons.Block.Icon.Image = (selectedRemote.Blocked and icons.unblock) or icons.block

	local newWidth = TextService:GetTextSize(
		(selectedRemote.Blocked and "Unblock") or "Block",
		18,
		"SourceSans",
		constants.textWidth
	).X + 30

	LogsButtons.Block.Size = UDim2.new(0, newWidth, 0, 20)
end

local Condition = {}
local function conditionIsNaN(value)
	return type(value) == "number" and value ~= value
end

local function conditionBranchIsEmpty(branch)
	return branch
		and next(branch.types) == nil
		and next(branch.values) == nil
		and branch.nan ~= true
end

function Condition.new(remote, status, index, value, type)
	local condition = {}
	local instance = Assets.ConditionPod:Clone()
	local content = instance.Content
	local identifiers = instance.Identifiers
	local button = ListButton.new(instance, remoteConditions)
	local check = CheckBox.new(content.Toggle)
	local valueType = type or typeof(value)
	local typeIcons = oh.Constants.Types
	local storage = status == "Ignore" and remote.IgnoredArgs or remote.BlockedArgs
	local branch = storage[index]

	condition.Branch = branch
	condition.Storage = storage
	condition.Status = status
	condition.Index = index
	condition.Value = value
	condition.Type = type
	condition.Remote = remote
	condition.Enabled = true
	condition.Instance = instance
	condition.Button = button
	condition.Toggle = Condition.toggle
	condition.Remove = Condition.remove
	button.Condition = condition

	check:SetCallback(function()
		condition:Toggle()
	end)

	button:SetRightCallback(function()
		selected.condition = condition
	end)

	identifiers.ByType.Visible = type ~= nil
	identifiers.Status.Image = (status == "Ignore" and icons.ignore) or icons.block
	identifiers.Status.Border.Image = identifiers.Status.Image

	content.Index.Text = index
	content.Label.Text = (type and valueType) or toString(value)
	content.Label.TextColor3 = oh.Constants.Syntax[valueType] or oh.Constants.Syntax["userdata"]
	content.Type.Image = typeIcons[valueType] or typeIcons["userdata"]

	return condition
end

function Condition.toggle(condition)
	condition.Enabled = not condition.Enabled

	local index = condition.Index
	local value = condition.Value
	local storage = condition.Storage
	local argStatus = storage[index] or condition.Branch

	if condition.Enabled then
		condition.Branch = argStatus
		storage[index] = argStatus
	end

	if conditionIsNaN(value) then
		argStatus.nan = condition.Enabled or false
	elseif value ~= nil then
		argStatus.values[value] = condition.Enabled or nil
	else
		argStatus.types[condition.Type] = condition.Enabled or nil
	end

	if not condition.Enabled and conditionBranchIsEmpty(argStatus) and storage[index] == argStatus then
		storage[index] = nil
	end
end

function Condition.remove(condition)
	local branch = condition.Branch
	local storage = condition.Storage
	condition.Button:Remove()

	if condition.Enabled then
		if conditionIsNaN(condition.Value) then
			branch.nan = false
		elseif condition.Value ~= nil then
			branch.values[condition.Value] = nil
		else
			branch.types[condition.Type] = nil
		end

		if conditionBranchIsEmpty(branch) and storage[condition.Index] == branch then
			storage[condition.Index] = nil
		end
	end
end

local function createConditions(remote)
	remoteConditions:Clear()
	selected.condition = nil

	RemoteList.Visible = false
	RemoteLogs.Visible = false
	RemoteConditions.Visible = true

	local remoteInstance = remote.Instance
	local remoteInstanceName = remoteInstance.Name
	local remoteClassName = remoteInstance.ClassName
	local nameLength = TextService:GetTextSize(remoteInstanceName, 18, "SourceSans", constants.textWidth).X + 20

	ConditionsRemote.Icon.Image = icons[remoteClassName]
	ConditionsRemote.Label.Text = remoteInstanceName
	ConditionsRemote.Label.Size = UDim2.new(0, nameLength, 0, 20)
	ConditionsRemote.Position = UDim2.new(1, -nameLength, 0, 0)

	for index, arg in pairs(remote.IgnoredArgs) do
		for type in pairs(arg.types) do
			Condition.new(remote, "Ignore", index, nil, type)
		end

		for value in pairs(arg.values) do
			Condition.new(remote, "Ignore", index, value)
		end

		if arg.nan then
			Condition.new(remote, "Ignore", index, 0 / 0)
		end
	end

	for index, arg in pairs(remote.BlockedArgs) do
		for type in pairs(arg.types) do
			Condition.new(remote, "Block", index, nil, type)
		end

		for value in pairs(arg.values) do
			Condition.new(remote, "Block", index, value)
		end

		if arg.nan then
			Condition.new(remote, "Block", index, 0 / 0)
		end
	end
end

remoteList:BindContextMenu(remoteListMenu)
remoteList:BindContextMenuSelected(remoteListMenuSelected)
remoteLogs:BindContextMenu(remoteLogsMenu)
remoteConditions:BindContextMenu(remoteConditionMenu)
remoteConditions:BindContextMenuSelected(remoteConditionMenuSelected)

-- Log Objects
local Log = {}
local ArgsLog = {}
local renderLatestCalls
local queueLogRender

function Log.new(remote)
	local log = {}
	local button = Assets.RemoteLog:Clone()
	local remoteInstance = remote.Instance
	local remoteInstanceName = remoteInstance.Name
	local remoteClassName = remoteInstance.ClassName
	local listButton = ListButton.new(button, remoteList)

	local normalAnimation =
		TweenService:Create(button.Label, constants.fadeLength, { TextColor3 = constants.normalColor })
	local blockAnimation =
		TweenService:Create(button.Label, constants.fadeLength, { TextColor3 = constants.blockedColor })
	local ignoreAnimation =
		TweenService:Create(button.Label, constants.fadeLength, { TextColor3 = constants.ignoredColor })

	button.Name = remoteInstanceName
	button.Label.Text = remoteInstanceName
	button.Icon.Image = icons[remoteClassName]

	local function viewLogs()
		if selected.remoteLog then
			resetRenderedCalls()
		end

		local nameLength = TextService:GetTextSize(remoteInstanceName, 18, "SourceSans", constants.textWidth).X + 20

		selected.remoteLog = log

		renderLatestCalls(log, true)

		checkCurrentBlocked()
		checkCurrentIgnored()

		LogsRemote.Icon.Image = icons[remoteClassName]
		LogsRemote.Label.Text = remoteInstanceName
		LogsRemote.Label.Size = UDim2.new(0, nameLength, 0, 20)
		LogsRemote.Position = UDim2.new(1, -nameLength, 0, 0)
	end

	listButton:SetCallback(function()
		if selected.remoteLog ~= log then
			viewLogs()
		elseif queuedLogRenders[log] or renderedCallLog ~= log then
			renderLatestCalls(log)
		end

		RemoteList.Visible = false
		RemoteLogs.Visible = true
	end)

	listButton:SetRightCallback(function()
		ignoreContext:SetIcon((remote.Ignored and icons.unignore) or icons.ignore)
		ignoreContext:SetText((remote.Ignored and "Unignore Calls") or "Ignore Calls")
		blockContext:SetIcon((remote.Blocked and icons.unblock) or icons.block)
		blockContext:SetText((remote.Blocked and "Unblock Calls") or "Block Calls")

		selected.logContext = log
	end)

	currentLogs[remoteInstance] = log

	log.Remote = remote
	log.Button = listButton
	log.BlockAnimation = blockAnimation
	log.IgnoreAnimation = ignoreAnimation
	log.NormalAnimation = normalAnimation
	log.NormalAnimation = normalAnimation
	log.Clear = Log.clear
	log.PlayBlock = Log.playBlock
	log.PlayIgnore = Log.playIgnore
	log.PlayNormal = Log.playNormal
	log.Adjust = Log.adjust
	log.IncrementCalls = Log.incrementCalls
	log.Decrementcalls = Log.decrementCalls
	log.Remove = Log.remove
	listButton.Log = log

	local destroyingRan, destroyingConnection = pcall(function()
		return remoteInstance.Destroying:Connect(function()
			if pageIsAlive() and currentLogs[remoteInstance] == log then
				log:Remove(true)
			end
		end)
	end)

	if destroyingRan and destroyingConnection then
		log.DestroyingConnection = destroyingConnection
		oh.Events[#oh.Events + 1] = destroyingConnection
	end

	return log
end

local function createArg(instance, index, value)
	local arg = Assets.RemoteArg:Clone()
	local valueType = typeof(value)

	arg.Icon.Image = oh.Constants.Types[valueType] or oh.Constants.Types["userdata"]
	arg.Index.Text = index

	arg.Label.Text = argumentSummary(value)

	arg.Label.TextColor3 = oh.Constants.Syntax[valueType] or oh.Constants.Syntax["userdata"]
	arg.Name = tostring(index)
	arg.Parent = instance.Contents

	return arg.AbsoluteSize.Y + 5
end

function ArgsLog.new(log, callInfo)
	local instance = Assets.CallPod:Clone()
	local args = callInfo.args or {}

	if selected.remoteLog ~= log then
		instance.Visible = false
	end

	local button = ListButton.new(instance, remoteLogs)
	local height = 0

	local argCount = getArgCount(args)

	if argCount == 0 then
		height = height + createArg(instance, 1, nil)
	else
		for i = 1, argCount do
			local v = args[i]
			height = height + createArg(instance, i, v)
		end
	end

	local function chooseCall()
		selectCall(log, button, callInfo)
	end

	button:SetCallback(chooseCall)
	button:SetRightCallback(chooseCall)

	button.Instance.Size = button.Instance.Size + UDim2.new(0, 0, 0, height)

	return button
end

renderLatestCalls = function(log, rebuild)
	if not pageIsActive() then
		queuedLogRenders[log] = true
		return
	end
	queuedLogRenders[log] = nil

	local oldCanvasY = LogsResults.CanvasPosition.Y
	local followNewest = rebuild == true or oldCanvasY <= 6
	local anchorCall
	local anchorOrder

	if not followNewest and renderedCallLog == log then
		for call, button in pairs(renderedCallButtons) do
			local instance = button.Instance

			if instance and instance.Parent and instance.Visible then
				local order = instance.LayoutOrder
				local relativeBottom = instance.AbsolutePosition.Y - LogsResults.AbsolutePosition.Y + instance.AbsoluteSize.Y

				if relativeBottom > 0 and (not anchorOrder or order < anchorOrder) then
					anchorCall = call
					anchorOrder = order
				end
			end
		end
	end

	remoteLogs:BeginBatch()

	if rebuild or renderedCallLog ~= log then
		resetRenderedCalls()
		renderedCallLog = log
	end

	local logs = log.Remote.Logs
	local total = #logs
	local newest = total

	if anchorCall and anchorOrder then
		for index = total, 1, -1 do
			if logs[index] == anchorCall then
				newest = math.min(total, index + anchorOrder - 1)
				break
			end
		end
	end

	local first = math.max(1, newest - getMaxRenderedLogs() + 1)
	local desiredCalls = {}
	local desiredOrder = {}
	local layoutOrder = 0

	for index = newest, first, -1 do
		local call = logs[index]

		if call then
			layoutOrder = layoutOrder + 1
			desiredCalls[call] = true
			desiredOrder[call] = layoutOrder
		end
	end

	for call, button in pairs(renderedCallButtons) do
		if not desiredCalls[call] then
			clearSelectedCall(button)
			button:Remove()
			renderedCallButtons[call] = nil
		end
	end

	for index = newest, first, -1 do
		local call = logs[index]

		if call then
			local button = renderedCallButtons[call]

			if not button then
				button = ArgsLog.new(log, call)
				renderedCallButtons[call] = button
			end

			button.Instance.LayoutOrder = desiredOrder[call]
			button.Instance.Visible = selected.remoteLog == log
		end
	end

	remoteLogs:EndBatch()
	remoteLogs:QueueRecalculate()

	task.defer(function()
		if not pageIsActive()
			or selected.remoteLog ~= log
			or not RemoteLogs.Visible
			or not LogsResults.Parent
		then
			return
		end

		if followNewest then
			LogsResults.CanvasPosition = Vector2.new(LogsResults.CanvasPosition.X, 0)
		else
			local maximum = math.max(0, LogsResults.AbsoluteCanvasSize.Y - LogsResults.AbsoluteWindowSize.Y)
			LogsResults.CanvasPosition = Vector2.new(LogsResults.CanvasPosition.X, math.min(maximum, oldCanvasY))
		end
	end)
end

local function flushLogRenders()
	logRenderTaskQueued = false

	if not pageIsActive() then
		return
	end

	local pending = queuedLogRenders
	queuedLogRenders = {}

	for log in pairs(pending) do
		if pageIsActive()
			and selected.remoteLog == log
			and log.Button
			and log.Button.Instance
			and log.Button.Instance.Parent
		then
			if RemoteLogs.Visible then
				renderLatestCalls(log)
			else
				queuedLogRenders[log] = true
			end
		end
	end
end

local function scheduleLogRenders()
	if logRenderTaskQueued or not pageIsActive() then
		return
	end

	logRenderTaskQueued = true
	task.defer(flushLogRenders)
end

queueLogRender = function(log)
	if not pageIsAlive() or not log then
		return
	end

	queuedLogRenders[log] = true
	scheduleLogRenders()
end

local function updateCountDisplay(log)
	local buttonInstance = log.Button.Instance
	local calls = log.Remote.Calls

	buttonInstance.Calls.Text = (calls < 10000 and calls) or "..."
	log:Adjust()
end

local function flushCountUpdates()
	countUpdateTaskQueued = false

	if not pageIsActive() then
		return
	end

	local processed = 0

	for log in pairs(queuedCountUpdates) do
		queuedCountUpdates[log] = nil

		if log.Button and log.Button.Instance and log.Button.Instance.Parent then
			updateCountDisplay(log)
		end

		processed = processed + 1

		if processed >= 100 then
			break
		end
	end

	if next(queuedCountUpdates) ~= nil and pageIsActive() then
		countUpdateTaskQueued = true
		task.defer(flushCountUpdates)
	end
end

local function scheduleCountUpdates()
	if countUpdateTaskQueued or not pageIsActive() then
		return
	end

	countUpdateTaskQueued = true
	task.defer(flushCountUpdates)
end

local function queueCountUpdate(log)
	if not pageIsAlive() or not log then
		return
	end

	queuedCountUpdates[log] = true
	scheduleCountUpdates()
end

trackConnection(Page:GetPropertyChangedSignal("Visible"):Connect(function()
	if not pageIsAlive() then
		return
	elseif not Page.Visible then
		detailsGeneration = detailsGeneration + 1
		return
	end

	scheduleCountUpdates()

	if selected.remoteLog then
		queuedLogRenders[selected.remoteLog] = true
		scheduleLogRenders()
	end
end))

function Log.playIgnore(log)
	log.IgnoreAnimation:Play()
end

function Log.playBlock(log)
	log.BlockAnimation:Play()
end

function Log.playNormal(log)
	log.NormalAnimation:Play()
end

function Log.adjust(log)
	local remoteClassName = log.Remote.Instance.ClassName
	local logInstance = log.Button.Instance
	local logIcon = logInstance.Icon

	local callWidth = TextService:GetTextSize(logInstance.Calls.Text, 18, "SourceSans", constants.textWidth).X + 10
	local iconPosition = callWidth
		- (
			(
				(
					remoteClassName == "RemoteEvent"
					or remoteClassName == "UnreliableRemoteEvent"
					or remoteClassName == "BindableEvent"
				) and 4
			) or 0
		)
	local labelWidth = iconPosition + 21

	logInstance.Calls.Size = UDim2.new(0, callWidth, 1, 0)
	logIcon.Position = UDim2.new(
		0,
		iconPosition,
		0.5,
		((remoteClassName == "RemoteEvent" or remoteClassName == "UnreliableRemoteEvent") and -9) or -7
	)
	logInstance.Label.Position = UDim2.new(0, labelWidth, 0, 0)
	logInstance.Label.Size = UDim2.new(1, -labelWidth, 1, 0)
end

function Log.clear(log)
	local logInstance = log.Button.Instance

	log.Remote:Clear()

	if selected.remoteLog == log then
		resetRenderedCalls()
	end

	logInstance.Calls.Text = 0
	log:Adjust()
end

function Log.incrementCalls(log, callInfo)
	queueCountUpdate(log)

	if selected.remoteLog == log then
		queueLogRender(log)
	end
end

function Log.decrementCalls(log, args)
	local remote = log.Remote

	remote:DecrementCalls(args)
	queueCountUpdate(log)
end

function Log.remove(log, destroyed)
	local remoteInstance = log.Remote.Instance
	local destroyingConnection = log.DestroyingConnection
	local returnToList = selected.remoteLog == log or selected.conditionLog == log
	queuedLogRenders[log] = nil
	queuedCountUpdates[log] = nil

	if destroyingConnection then
		pcall(function()
			destroyingConnection:Disconnect()
		end)
		log.DestroyingConnection = nil
	end

	if selected.remoteLog == log then
		resetRenderedCalls()
		selected.remoteLog = nil
	end

	if selected.logContext == log then
		selected.logContext = nil
	end

	if selected.conditionLog == log then
		selected.conditionLog = nil
		selected.condition = nil
		remoteConditions:Clear()
		newRemoteCondition:Hide()
	end

	if returnToList then
		detailsGeneration = detailsGeneration + 1
		TextViewer.HideDefault()
		RemoteLogs.Visible = false
		RemoteConditions.Visible = false
		RemoteList.Visible = true
	end

	log.Button:Remove()
	currentLogs[remoteInstance] = nil
	removed[remoteInstance] = true

	if destroyed then
		currentRemotes[remoteInstance] = nil
	end
end

-- UI Functionality

local function refreshLogs()
	for remoteInstance, log in pairs(currentLogs) do
		log.Button.Instance.Visible = remotesViewing[remoteInstance.ClassName]
	end

	remoteList:Recalculate()
end

for _i, flag in pairs(ListFlags:GetChildren()) do
	if flag:IsA("Frame") then
		local check = CheckBox.new(flag)
		local enabled = remotesViewing[flag.Name] == true
		local toggle = flag:FindFirstChild("Toggle") or flag
		local label = toggle and toggle:FindFirstChild("Label")

		check.Enabled = enabled

		if label then
			label.Text = (enabled and "✓") or ""
		end

		check:SetCallback(function(enabled)
			remotesViewing[flag.Name] = enabled
			refreshLogs()
		end)
	end
end

ListSearch.FocusLost:Connect(function(returned)
	if returned then
		local query = ListSearch.Text:lower()

		for remoteInstance, log in pairs(currentLogs) do
			local instance = log.Button.Instance
			instance.Visible = remoteInstance.Name:lower():find(query, 1, true) ~= nil
		end

		remoteList:Recalculate()
		ListSearch.Text = ""
	end
end)

ListRefresh.MouseButton1Click:Connect(function()
	refreshLogs()
end)

LogsBack.MouseButton1Click:Connect(function()
	RemoteLogs.Visible = false
	RemoteList.Visible = true
end)

LogsButtons.Ignore.MouseButton1Click:Connect(function()
	local selectedLog = selected.remoteLog
	local selectedRemote = selectedLog and selectedLog.Remote

	if not selectedRemote or currentLogs[selectedRemote.Instance] ~= selectedLog then
		return
	end

	selectedRemote:Ignore()

	checkCurrentIgnored()

	if selectedRemote.Blocked then
		selectedLog:PlayBlock()
	elseif selectedRemote.Ignored then
		selectedLog:PlayIgnore()
	else
		selectedLog:PlayNormal()
	end
end)

LogsButtons.Block.MouseButton1Click:Connect(function()
	local selectedLog = selected.remoteLog
	local selectedRemote = selectedLog and selectedLog.Remote

	if not selectedRemote or currentLogs[selectedRemote.Instance] ~= selectedLog then
		return
	end

	selectedRemote:Block()

	checkCurrentBlocked()

	if selectedRemote.Blocked then
		selectedLog:PlayBlock()
	elseif selectedRemote.Ignored then
		selectedLog:PlayIgnore()
	else
		selectedLog:PlayNormal()
	end
end)

LogsButtons.Clear.MouseButton1Click:Connect(function()
	local selectedLog = selected.remoteLog
	local selectedRemote = selectedLog and selectedLog.Remote

	if selectedRemote and currentLogs[selectedRemote.Instance] == selectedLog then
		selectedLog:Clear()
	end
end)

LogsButtons.Conditions.MouseButton1Click:Connect(function()
	local selectedLog = selected.remoteLog
	local selectedRemote = selectedLog and selectedLog.Remote

	if not selectedRemote or currentLogs[selectedRemote.Instance] ~= selectedLog then
		return
	end

	selected.conditionLog = selectedLog

	createConditions(selectedRemote)
end)

ConditionsBack.MouseButton1Click:Connect(function()
	RemoteConditions.Visible = false

	if selected.remoteLog then
		RemoteLogs.Visible = true
	else
		RemoteList.Visible = true
	end
end)

local function validConditionIndex(value)
	local index = tonumber(value)

	if not index or index ~= index or index == math.huge or index == -math.huge or index < 1 or index % 1 ~= 0 then
		return nil
	end

	return index
end

local function selectedArgument(index)
	local args = selected.args
	local count = getArgCount(args)

	if selected.callRemote ~= selected.conditionLog or not args or index < 1 or index > count then
		return nil, false
	end

	return args[index], true
end

local function conditionBufferHex(value)
	if
		not buffer
		or type(buffer.len) ~= "function"
		or type(buffer.readu8) ~= "function"
		or typeof(value) ~= "buffer"
	then
		return nil
	end

	local measured, length = pcall(buffer.len, value)
	local maximum = tonumber(oh.Settings and oh.Settings.MaxConditionBufferBytes) or 4096

	if not measured or type(length) ~= "number" or length < 0 or length > maximum then
		return nil
	end

	local bytes = table.create and table.create(length) or {}

	for offset = 0, length - 1 do
		local read, byte = pcall(buffer.readu8, value, offset)

		if not read then
			return nil
		end

		bytes[offset + 1] = ("%02X"):format(byte)
	end

	return table.concat(bytes, " ")
end

local function prefillCondition(index, populateValue)
	index = validConditionIndex(index) or 1
	NewConditionIndex.Value.Input.Text = tostring(index)

	local value, present = selectedArgument(index)
	local input = NewConditionContent.Value.Input
	populateValue = populateValue == true

	if present then
		local valueType = typeof(value)
		conditionType:AddOption(valueType, oh.Constants.Types[valueType] or oh.Constants.Types.userdata)
		conditionType:SetSelected(valueType)

		if not populateValue then
			input.Text = ""
		elseif type(value) == "string" then
			input.Text = value
		elseif valueType == "buffer" then
			input.Text = conditionBufferHex(value) or ""
		elseif type(value) == "table" or type(value) == "function" or type(value) == "thread" or value == nil then
			input.Text = ""
		elseif type(dataToString) == "function" then
			local serialized, result = pcall(dataToString, value)
			input.Text = serialized and tostring(result) or ""
		else
			input.Text = tostring(value)
		end
	elseif not conditionType.Selected then
		conditionType:SetSelected("string")
		input.Text = ""
	elseif not populateValue then
		input.Text = ""
	end
end

local function setConditionAssociation(mode)
	local input = NewConditionContent.Value.Input
	local byType = mode == "Type"

	input.TextEditable = not byType
	input.ClearTextOnFocus = false
	input.PlaceholderText = byType and "Value is not needed for a type match" or "Enter a value or Luau constructor"
	input.TextTransparency = byType and 0.45 or 0
end

local function parseHexBuffer(text)
	if not buffer or type(buffer.create) ~= "function" or type(buffer.writeu8) ~= "function" then
		return nil, "buffer creation is unavailable"
	end

	local bytes = {}

	for token in text:gmatch("%S+") do
		if not token:match("^%x%x$") then
			return nil, "Hex buffers must use two-digit bytes such as DE AD BE EF"
		end

		bytes[#bytes + 1] = tonumber(token, 16)

		local maximum = tonumber(oh.Settings and oh.Settings.MaxConditionBufferBytes) or 4096

		if #bytes > maximum then
			return nil, ("Buffer conditions are limited to %d bytes"):format(maximum)
		end
	end

	local result = buffer.create(#bytes)

	for index, byte in ipairs(bytes) do
		buffer.writeu8(result, index - 1, byte)
	end

	return result
end


local function parseConditionValue(valueType, text)
	if valueType == "nil" then
		return nil, "Use a Type condition to match nil arguments"
	elseif valueType == "string" then
		return text
	elseif valueType == "number" then
		local normalized = text:lower():gsub("^%s+", ""):gsub("%s+$", "")
		local value = tonumber(normalized)

		if normalized == "nan" or normalized == "0/0" then
			value = 0 / 0
		elseif normalized == "inf" or normalized == "+inf" or normalized == "infinity" or normalized == "math.huge" then
			value = math.huge
		elseif normalized == "-inf" or normalized == "-infinity" or normalized == "-math.huge" then
			value = -math.huge
		end

		if value == nil then
			return nil, "Enter a valid number"
		end

		return value
	elseif valueType == "boolean" then
		local lowered = text:lower():gsub("^%s+", ""):gsub("%s+$", "")

		if lowered == "true" then
			return true
		elseif lowered == "false" then
			return false
		end

		return nil, "Enter true or false"
	elseif valueType == "table" or valueType == "function" or valueType == "thread" then
		return nil, "Use a Type condition for reference values such as " .. valueType
	elseif valueType == "buffer" and text:match("^%s*[%x][%x%s]*%s*$") then
		return parseHexBuffer(text)
	end

	local chunk, compileError = loadstring("return " .. text)

	if not chunk then
		return nil, tostring(compileError or "The value could not be compiled")
	end

	local ran, value = pcall(chunk)

	if not ran then
		return nil, tostring(value)
	elseif typeof(value) ~= valueType then
		return nil, ("Expected %s, got %s"):format(valueType, typeof(value))
	elseif valueType == "buffer" and buffer and type(buffer.len) == "function" then
		local measured, length = pcall(buffer.len, value)
		local maximum = tonumber(oh.Settings and oh.Settings.MaxConditionBufferBytes) or 4096

		if not measured then
			return nil, "The buffer length could not be read"
		elseif length > maximum then
			return nil, ("Buffer conditions are limited to %d bytes"):format(maximum)
		end
	end

	return value
end

ConditionsButtons.New.MouseButton1Click:Connect(function()
	if not conditionStatus.Selected then
		conditionStatus:SetSelected("Ignore")
	end

	if not conditionValueType.Selected then
		conditionValueType:SetSelected("Type")
	end

	prefillCondition(
		NewConditionIndex.Value.Input.Text,
		conditionValueType.Selected and conditionValueType.Selected.Name == "Value"
	)
	setConditionAssociation(conditionValueType.Selected and conditionValueType.Selected.Name or "Type")
	newRemoteCondition:Show()
end)

NewConditionButtons.Add.MouseButton1Click:Connect(function()
	local status = conditionStatus.Selected and conditionStatus.Selected.Name
	local selectedType = conditionType.Selected and conditionType.Selected.Name
	local valueType = conditionValueType.Selected and conditionValueType.Selected.Name
	local valueText = NewConditionContent.Value.Input.Text
	local argIndex = validConditionIndex(NewConditionIndex.Value.Input.Text)
	local conditionLog = selected.conditionLog
	local selectedRemote = conditionLog and conditionLog.Remote

	if
		not selectedRemote
		or not selectedRemote.Instance
		or currentLogs[selectedRemote.Instance] ~= conditionLog
	then
		newRemoteCondition:Hide()
		setStatusSafely("Condition target is no longer available")
		return
	end

	if status ~= "Ignore" and status ~= "Block" then
		return MessageBox.Show("Error", "Choose Ignore or Block", MessageType.OK)
	elseif type(selectedType) ~= "string" or selectedType == "" then
		return MessageBox.Show("Error", "Choose an argument type", MessageType.OK)
	elseif valueType ~= "Value" and valueType ~= "Type" then
		return MessageBox.Show("Error", "Choose whether to match by Type or Value", MessageType.OK)
	elseif not argIndex then
		return MessageBox.Show("Error", "Argument index must be a positive whole number", MessageType.OK)
	end

	local byType = valueType == "Type"
	local value = selectedType

	if not byType then
		local parsed, parseError = parseConditionValue(selectedType, valueText)

		if parseError then
			return MessageBox.Show("Invalid Condition Value", parseError, MessageType.OK)
		end

		value = parsed
	end

	local added, addError
	if status == "Block" then
		added, addError = selectedRemote:BlockArg(argIndex, value, byType)
	else
		added, addError = selectedRemote:IgnoreArg(argIndex, value, byType)
	end

	if not added then
		return MessageBox.Show("Condition Not Added", tostring(addError or "That condition already exists"), MessageType.OK)
	end

	if byType then
		Condition.new(selectedRemote, status, argIndex, nil, value)
	else
		Condition.new(selectedRemote, status, argIndex, value)
	end

	newRemoteCondition:Hide()
end)

NewConditionButtons.Cancel.MouseButton1Click:Connect(function()
	newRemoteCondition:Hide()
end)

NewConditionIndex.Add.MouseButton1Click:Connect(function()
	local newIndex = (validConditionIndex(NewConditionIndex.Value.Input.Text) or 1) + 1
	prefillCondition(newIndex, conditionValueType.Selected and conditionValueType.Selected.Name == "Value")
end)

NewConditionIndex.Sub.MouseButton1Click:Connect(function()
	local newIndex = math.max(1, (validConditionIndex(NewConditionIndex.Value.Input.Text) or 1) - 1)
	prefillCondition(newIndex, conditionValueType.Selected and conditionValueType.Selected.Name == "Value")
end)

NewConditionIndex.Value.Input.FocusLost:Connect(function()
	prefillCondition(
		validConditionIndex(NewConditionIndex.Value.Input.Text) or 1,
		conditionValueType.Selected and conditionValueType.Selected.Name == "Value"
	)
end)

pathContext:SetCallback(function()
	local selectedInstance = selected.logContext.Remote.Instance
	local oldStatus = getStatusSafely()
	local generation = detailsGeneration
	local pendingStatus = "Copying " .. selectedInstance.Name .. "'s path"

	local statusSet = setStatusSafely(pendingStatus)
	setClipboard(getInstancePath(selectedInstance))
	task.wait(0.25)

	if pageIsActive()
		and generation == detailsGeneration
		and selected.logContext
		and selected.logContext.Remote.Instance == selectedInstance
		and statusSet
		and getStatusSafely() == pendingStatus
		and oldStatus ~= nil
	then
		setStatusSafely(oldStatus)
	end
end)

conditionContext:SetCallback(function()
	selected.conditionLog = selected.logContext or selected.remoteLog

	createConditions(selected.conditionLog.Remote)
end)

clearContext:SetCallback(function()
	selected.logContext:Clear()
end)

ignoreContext:SetCallback(function()
	local selectedRemote = selected.logContext.Remote

	selected.logContext.Remote:Ignore()

	checkCurrentIgnored()

	if selectedRemote.Blocked then
		selected.logContext:PlayBlock()
	elseif selectedRemote.Ignored then
		selected.logContext:PlayIgnore()
	else
		selected.logContext:PlayNormal()
	end
end)

blockContext:SetCallback(function()
	local selectedRemote = selected.logContext.Remote

	selected.logContext.Remote:Block()

	checkCurrentBlocked()

	if selectedRemote.Blocked then
		selected.logContext:PlayBlock()
	elseif selectedRemote.Ignored then
		selected.logContext:PlayIgnore()
	else
		selected.logContext:PlayNormal()
	end
end)

removeContext:SetCallback(function()
	selected.logContext:Remove()
end)

local function clearListSelection(list)
	for _, button in ipairs(list.Selected or {}) do
		if button.DeselectAnimation then
			button.DeselectAnimation:Play()
		end
	end

	list.Selected = nil
end

local function getSelectedLogs()
	local results = {}
	local seen = {}

	for _, button in ipairs(remoteList.Selected or {}) do
		local log = button.Log
		local instance = button.Instance
		local remote = log and log.Remote
		local remoteInstance = remote and remote.Instance

		if log
			and not seen[log]
			and log.Button == button
			and instance
			and instance.Parent == ListResults
			and remoteList.Buttons[instance] == button
			and currentLogs[remoteInstance] == log
		then
			seen[log] = true
			results[#results + 1] = log
		end
	end

	return results
end

local function getSelectedConditions()
	local results = {}
	local seen = {}
	local currentRemote = selected.conditionLog and selected.conditionLog.Remote

	for _, button in ipairs(remoteConditions.Selected or {}) do
		local condition = button.Condition
		local instance = button.Instance

		if condition
			and not seen[condition]
			and condition.Button == button
			and condition.Remote == currentRemote
			and instance
			and instance.Parent == ConditionsResults
			and remoteConditions.Buttons[instance] == button
		then
			seen[condition] = true
			results[#results + 1] = condition
		end
	end

	return results
end

pathContextSelected:SetCallback(function()
	local paths = ""

	for _, log in ipairs(getSelectedLogs()) do
		paths = paths .. getInstancePath(log.Remote.Instance) .. "\n"
	end

	setClipboard(paths)
	clearListSelection(remoteList)
end)

ignoreContextSelected:SetCallback(function()
	for _, log in ipairs(getSelectedLogs()) do
		local remote = log.Remote

		if not remote.Ignored then
			remote:Ignore()
		end

		if remote.Blocked then
			log:PlayBlock()
		elseif remote.Ignored then
			log:PlayIgnore()
		else
			log:PlayNormal()
		end
	end

	clearListSelection(remoteList)
end)

unignoreContextSelected:SetCallback(function()
	for _, log in ipairs(getSelectedLogs()) do
		local remote = log.Remote

		if remote.Ignored then
			remote:Ignore()
		end

		if remote.Blocked then
			log:PlayBlock()
		else
			log:PlayNormal()
		end
	end

	clearListSelection(remoteList)
end)

blockContextSelected:SetCallback(function()
	for _, log in ipairs(getSelectedLogs()) do
		local remote = log.Remote

		if not remote.Blocked then
			remote:Block()
		end

		if remote.Blocked then
			log:PlayBlock()
		elseif remote.Ignored then
			log:PlayIgnore()
		else
			log:PlayNormal()
		end
	end

	clearListSelection(remoteList)
end)

unblockContextSelected:SetCallback(function()
	for _, log in ipairs(getSelectedLogs()) do
		local remote = log.Remote

		remote:Unblock()

		if remote.Ignored then
			log:PlayIgnore()
		else
			log:PlayNormal()
		end
	end

	clearListSelection(remoteList)
end)

clearContextSelected:SetCallback(function()
	for _, log in ipairs(getSelectedLogs()) do
		log:Clear()
	end

	clearListSelection(remoteList)
end)

removeContextSelected:SetCallback(function()
	local targets = getSelectedLogs()
	clearListSelection(remoteList)

	for _, log in ipairs(targets) do
		log:Remove()
	end

	remoteList:Recalculate()
end)

local function buildReplayScript(remoteLog, callInfo, args)
	if type(buildRemoteScript) ~= "function" then
		return nil, "The replay-script builder is unavailable."
	elseif callInfo and callInfo.replayable == false then
		return nil, "This call contains values that exceeded the bounded capture limits and cannot be replayed safely."
	end

	local remoteInstance = remoteLog and remoteLog.Remote and remoteLog.Remote.Instance

	if not remoteInstance then
		return nil, "The selected remote is no longer available."
	end

	local method = getRemoteMethod(remoteInstance, callInfo)
	local ran, script, buildError = pcall(buildRemoteScript, remoteInstance, method, args or {}, callInfo)

	if not ran then
		return nil, tostring(script)
	elseif type(script) ~= "string" or script == "" then
		return nil, tostring(buildError or "The captured values could not be serialized safely.")
	end

	return script
end

local function generateReplayScript()
	if not guardSelectedCall("Replay Code") then
		return
	end

	detailsGeneration = detailsGeneration + 1
	local generation = detailsGeneration
	local callInfo = selected.callInfo
	local remoteLog = selected.remoteLog
	local args = selected.args or {}
	renderDetails("Remote Replay Code", "Building compact replay code ...")

	task.spawn(function()
		local script, buildError = buildReplayScript(remoteLog, callInfo, args)

		if not pageIsActive() or generation ~= detailsGeneration or selected.callInfo ~= callInfo then
			return
		elseif not script then
			renderDetails("Replay Code Unavailable", buildError or "Replay code could not be generated.")
			return
		end

		renderDetails("Remote Replay Code", script)
	end)
end

local function copyReplayScript()
	if not guardSelectedCall("Copy Replay Code") then
		return
	end

	local callInfo = selected.callInfo
	local remoteLog = selected.remoteLog
	local args = selected.args or {}
	local generation = detailsGeneration
	local pendingStatus = "Building replay code ..."
	local oldStatus = getStatusSafely()
	local statusSet = setStatusSafely(pendingStatus)
	local function restorePendingStatus()
		if statusSet and oldStatus ~= nil and getStatusSafely() == pendingStatus then
			setStatusSafely(oldStatus)
		end
	end

	task.spawn(function()
		local script, buildError = buildReplayScript(remoteLog, callInfo, args)

		if not pageIsActive() or generation ~= detailsGeneration or selected.callInfo ~= callInfo then
			restorePendingStatus()
			return
		end

		if not script then
			setStatusSafely("Replay code unavailable")

			if pageIsActive() and generation == detailsGeneration and selected.callInfo == callInfo then
				showDetails("Replay Code Unavailable", buildError or "Replay code could not be generated.")
			end

			return
		end

		local copied, copyError = pcall(setClipboard, script)

		if not pageIsActive() or generation ~= detailsGeneration or selected.callInfo ~= callInfo then
			restorePendingStatus()
			return
		end

		if not copied then
			setStatusSafely("Replay code copy failed")

			if pageIsActive() and generation == detailsGeneration and selected.callInfo == callInfo then
				showDetails("Copy Failed", tostring(copyError))
			end
		else
			setStatusSafely("Replay code copied")
		end
	end)
end

local function showArguments()
	if guardSelectedCall("Remote Arguments") then
		showDetails("Remote Arguments", describePackedValues("CAPTURED ARGUMENTS", selected.args or {}))
	end
end

local function showReturns()
	if not guardSelectedCall("Remote Returns") then
		return
	end

	local callInfo = selected.callInfo
	local text = describePackedValues("RETURN VALUES", callInfo.returns or {})

	if callInfo.blocked then
		text = "The call was blocked before the original method ran.\n\n" .. text
	elseif callInfo.error then
		text = "The original method raised an error:\n" .. tostring(callInfo.error) .. "\n\n" .. text
	end

	showDetails("Remote Returns", text)
end

local function showCallStack()
	if not guardSelectedCall("Remote Call Stack") then
		return
	end

	showDetails("Remote Call Stack", describeCallStack(selected.callInfo))
end

local function showDiagnostics()
	if guardSelectedCall("Capture Diagnostics") then
		showDetails("Capture Diagnostics", describeDiagnostics())
	end
end

local function showFunctionStack()
	showDetailsAsync("Remote Function Stack", "Inspecting captured stack functions ...", describeStackFunctions)
end

local function inspectCallingFunction()
	local func = selected.func
	showDetailsAsync("Calling Function", "Inspecting calling function ...", function(_callInfo, isAlive)
		return describeFunction(func, isAlive)
	end)
end

local function inspectCallingScript()
	local scriptInstance = selected.callingScript
	showDetailsAsync("Calling Script", "Decompiling calling script ...", function(_callInfo, isAlive)
		if not isAlive() then
			return "Inspection was cancelled."
		end

		return describeScript(scriptInstance, isAlive)
	end)
end

local function copyCallingScriptPath()
	if not guardSelectedCall("Calling Script") then
		return
	end

	if typeof(selected.callingScript) ~= "Instance" then
		return showDetails("Calling Script", "No calling script was captured for this call.")
	end

	local path = safeInstancePath(selected.callingScript)
	local copied, copyError = path and pcall(setClipboard, path)

	if not copied then
		showDetails("Copy Failed", tostring(copyError or "The calling script path is unavailable."))
	else
		setStatusSafely("Calling script path copied")
	end
end

local SpyHook = ClosureSpy.Hook
local function spyCallingFunction()
	if not guardSelectedCall("Spy Calling Function") then
		return
	end

	if type(selected.func) ~= "function" then
		return MessageBox.Show("Cannot hook", "No Lua closure was captured for this call", MessageType.OK)
	end

	local function installCallerHook()
		local selectedClosure = Closure.new(selected.func)
		local result, hookError = SpyHook.new(selectedClosure)

		if result == false then
			MessageBox.Show("Already hooked", "You are already spying " .. selectedClosure.Name, MessageType.OK)
		elseif result == nil then
			MessageBox.Show(
				"Cannot hook",
				hookError or ('Unable to hook "%s"'):format(selectedClosure.Name),
				MessageType.OK
			)
		else
			TabSelector.SelectTab("ClosureSpy")
		end
	end

	if type(withExecutorIdentity) == "function" then
		withExecutorIdentity(installCallerHook)
	else
		installCallerHook()
	end
end

local function repeatSelectedCall()
	if not guardSelectedCall("Repeat Call") then
		return
	end

	local remoteModel = selected.remoteLog.Remote
	local remoteInstance = remoteModel.Instance
	local callInfo = selected.callInfo
	local method = getRemoteMethod(remoteInstance, callInfo)
	local args = selected.args or {}
	local argCount = getArgCount(args)
	local callableRan, callable = pcall(function()
		return remoteInstance[method]
	end)

	if callInfo.replayable == false then
		return showDetails("Repeat Call Unavailable", "This call contains a truncated or unavailable captured value, so replay is disabled.")
	elseif not method or not callableRan or type(callable) ~= "function" then
		return showDetails("Repeat Call Failed", "No callable method was available for this remote.")
	elseif remoteModel.Blocked then
		return showDetails(
			"Remote Is Blocked",
			"Unblock this remote before replaying it; blocked calls intentionally do not reach the server."
		)
	end

	local replayStarted = false
	local confirmation = ("Run %s on %s with %d captured argument%s?\n\nReplaying a captured call can change game state."):format(
			method,
			remoteInstance.Name,
			argCount,
			argCount == 1 and "" or "s"
		)

	local function runReplay()
		if replayStarted or not pageIsActive() or selected.callInfo ~= callInfo then
			return
		elseif remoteModel.Blocked then
			return showDetails(
				"Remote Is Blocked",
				"Unblock this remote before replaying it; blocked calls intentionally do not reach the server."
			)
		end

		replayStarted = true
		showDetails("Replaying Remote Call", ("Calling %s on %s ..."):format(method, remoteInstance.Name))
		local generation = detailsGeneration
		local oldStatus = getStatusSafely()
		local replayStatus = "Replaying " .. remoteInstance.Name .. " ..."
		local statusSet = setStatusSafely(replayStatus)

		task.spawn(function()
			local results = table.pack(pcall(callable, remoteInstance, unpackValues(args, 1, argCount)))

			if statusSet and oldStatus ~= nil and getStatusSafely() == replayStatus then
				setStatusSafely(oldStatus)
			end

			if not pageIsActive() or selected.callInfo ~= callInfo or detailsGeneration ~= generation then
				return
			end

			if not results[1] then
				showDetails("Replay Call Failed", tostring(results[2]))
			elseif method == "InvokeServer" or method == "Invoke" then
				local returned = { n = math.max(0, results.n - 1) }

				for index = 2, results.n do
					returned[index - 1] = results[index]
				end

				showDetails("Replay Returns", describePackedValues("REPLAY RETURN VALUES", returned))
			else
				showDetails(
					"Replay Complete",
					("%s on %s reached the original remote callback."):format(method, remoteInstance.Name)
				)
			end
		end)
	end

	showDetails("Confirm Remote Replay", confirmation, {
		Actions = {
			{ Label = "Replay", Callback = runReplay },
			{ Label = "Cancel", Callback = TextViewer.HideDefault },
		},
	})
end

local function binaryLength(value)
	if type(value) == "string" then
		return #value
	elseif type(value) == "table" and value.__hydroxideCaptureMarker == true and type(value.Preview) == "string" then
		return #value.Preview
	elseif typeof(value) == "buffer" and buffer and type(buffer.len) == "function" then
		local ran, length = pcall(buffer.len, value)
		return ran and type(length) == "number" and length or nil
	end
end

local function binaryHex(value, maximumBytes)
	if type(value) == "table" and value.__hydroxideCaptureMarker == true and type(value.Preview) == "string" then
		local hex, readError = binaryHex(value.Preview, maximumBytes)

		if hex and value.Size then
			hex = hex .. (" ... (preview of %d-byte buffer)"):format(value.Size)
		end

		return hex, readError
	end

	local length = binaryLength(value)

	if not length then
		return nil, nil
	end

	local shown = math.min(length, maximumBytes)
	local parts = table.create and table.create(shown) or {}
	local ran, readError = pcall(function()
		for index = 1, shown do
			local byte

			if type(value) == "string" then
				byte = value:byte(index, index)
			else
				byte = buffer.readu8(value, index - 1)
			end

			parts[index] = string.format("%02X", byte)
		end
	end)

	if not ran then
		return nil, tostring(readError)
	end

	local hex = table.concat(parts, " ")

	if length > shown then
		hex = hex .. (" ... (%d/%d bytes shown)"):format(shown, length)
	end

	return hex, nil
end

local function describeStringValues(args, asHex)
	local lines = {
		asHex and "CAPTURED BINARY ARGUMENTS (HEX)" or "CAPTURED BINARY ARGUMENTS",
		"",
	}
	local maxHexBytes = getMaxHexBytes()
	local argCount = getArgCount(args)
	local found = false

	for index = 1, argCount do
		local value = args[index]

		if type(value) == "string"
			or typeof(value) == "buffer"
			or (type(value) == "table" and value.__hydroxideCaptureMarker == true and type(value.Preview) == "string")
		then
			found = true

			if asHex then
				local hex, hexError = binaryHex(value, maxHexBytes)
				lines[#lines + 1] = ("[%02d] %s"):format(index, hex or ("unreadable: " .. tostring(hexError)))
			else
				lines[#lines + 1] = ("[%02d] %s"):format(index, argumentSummary(value))
			end
		end
	end

	if not found then
		lines[#lines + 1] = "(no string or buffer arguments)"
	end

	return table.concat(lines, "\n")
end

local function toggleHexView()
	if not guardSelectedCall("Toggle Binary Hex View") or not selected.args then
		return
	end

	selected.hexViewEnabled = not selected.hexViewEnabled
	local callButton = selected.callPodButton

	if not (callButton and callButton.Instance and callButton.Instance.Parent) then
		return showDetails("Binary Arguments", describeStringValues(selected.args, selected.hexViewEnabled))
	end

	callButton.hexViewEnabled = selected.hexViewEnabled
	callButton.oldStrings = callButton.oldStrings or {}

	local maxHexBytes = getMaxHexBytes()
	local argCount = getArgCount(selected.args)

	for idx = 1, argCount do
		local arg = selected.args[idx]

		if type(arg) == "string"
			or typeof(arg) == "buffer"
			or (type(arg) == "table" and arg.__hydroxideCaptureMarker == true and type(arg.Preview) == "string")
		then
			local argRow = callButton.Instance.Contents:FindFirstChild(tostring(idx))
			local textObject = argRow and argRow.Label

			if textObject then
				if callButton.hexViewEnabled then
					callButton.oldStrings[idx] = arg
					local hexString, hexError = binaryHex(arg, maxHexBytes)
					textObject.Text = hexString or ("unreadable binary value: " .. tostring(hexError))
				else
					textObject.Text = argumentSummary(callButton.oldStrings[idx] or arg)
				end
			end
		end
	end
end

scriptContext:SetCallback(generateReplayScript)
copyScriptContext:SetCallback(copyReplayScript)
argumentsContext:SetCallback(showArguments)
returnsContext:SetCallback(showReturns)
callStackContext:SetCallback(showCallStack)
functionStackContext:SetCallback(showFunctionStack)
inspectFunctionContext:SetCallback(inspectCallingFunction)
inspectScriptContext:SetCallback(inspectCallingScript)
callingScriptContext:SetCallback(copyCallingScriptPath)
spyClosureContext:SetCallback(spyCallingFunction)
repeatCallContext:SetCallback(repeatSelectedCall)
viewAsHexContext:SetCallback(toggleHexView)
diagnosticsContext:SetCallback(showDiagnostics)

callInspector = ActionPanel.Install(LogsButtons, RemoteLogs.Results, {
	Columns = 7,
	MinimumCellWidth = 105,
	ButtonHeight = 21,
	Gap = 3,
	Actions = {
		{ Name = "ReplayCode", Label = "Code", Icon = icons.script, Callback = generateReplayScript },
		{ Name = "CopyCode", Label = "Copy Code", Icon = icons.copy, Callback = copyReplayScript },
		{ Name = "Arguments", Label = "Arguments", Icon = icons.arguments, Callback = showArguments },
		{ Name = "Returns", Label = "Returns", Icon = icons.results, Callback = showReturns },
		{ Name = "CallStack", Label = "Stack", Icon = icons.stack, Callback = showCallStack },
		{ Name = "FunctionStack", Label = "Fn Stack", Icon = icons.spy, Callback = showFunctionStack },
		{ Name = "Function", Label = "Caller Fn", Icon = icons.spy, Callback = inspectCallingFunction },
		{ Name = "ScriptSource", Label = "Script", Icon = icons.source, Callback = inspectCallingScript },
		{ Name = "ScriptPath", Label = "Copy Path", Icon = icons.copy, Callback = copyCallingScriptPath },
		{ Name = "SpyFunction", Label = "Spy Caller", Icon = icons.spy, Callback = spyCallingFunction },
		{ Name = "Repeat", Label = "Replay", Icon = icons.repeatCall, Callback = repeatSelectedCall },
		{ Name = "Hex", Label = "Hex", Icon = icons.hex, Callback = toggleHexView },
		{ Name = "Diagnostics", Label = "Diagnostics", Icon = icons.status, Callback = showDiagnostics },
	},
})
updateCallInspector()

removeConditionContext:SetCallback(function()
	selected.condition:Remove()
	selected.condition = nil
end)

removeConditionContextSelected:SetCallback(function()
	local targets = getSelectedConditions()
	clearListSelection(remoteConditions)
	selected.condition = nil

	for _, condition in ipairs(targets) do
		condition:Remove()
	end
end)

conditionStatus:SetCallback(function(_dropdown, selected)
	local iconCondition = (selected.Name == "Ignore" and icons.ignore) or icons.block
	local icon = NewConditionContent.Status.Icon

	icon.Image = iconCondition
	icon.Border.Image = iconCondition
end)

conditionType:SetCallback(function(_dropdown, selected)
	local icon = NewConditionContent.Type.Icon
	local typeIcons = oh.Constants.Types
	local iconCondition = typeIcons[selected.Name] or typeIcons["userdata"]

	icon.Image = iconCondition
	icon.Border.Image = iconCondition
end)

conditionValueType:SetCallback(function(_dropdown, selected)
	local iconCondition = (selected.Name == "Type" and icons.type) or oh.Constants.Types["integral"]
	local icon = NewConditionContent.ValueType.Icon

	icon.Image = iconCondition
	icon.Border.Image = iconCondition
	setConditionAssociation(selected.Name)
	prefillCondition(NewConditionIndex.Value.Input.Text, selected.Name == "Value")
end)

conditionStatus:SetSelected("Ignore")
conditionType:SetSelected("string")
conditionValueType:SetSelected("Type")

for remoteInstance, remote in pairs(currentRemotes) do
	if typeof(remoteInstance) == "Instance" and not removed[remoteInstance] and not currentLogs[remoteInstance] then
		local log = Log.new(remote)
		log.Button.Instance.Visible = remotesViewing[remoteInstance.ClassName]
		updateCountDisplay(log)
	end
end

remoteList:QueueRecalculate()

Methods.ConnectEvent(function(remoteInstance, callInfo)
	if pageIsAlive() and not removed[remoteInstance] then
		local remote = currentRemotes[remoteInstance]
		local log = currentLogs[remoteInstance]

		if not log and remote then
			log = Log.new(remote)
		end

		if log then
			log:IncrementCalls(callInfo)
		end
	end
end)

return RemoteSpy
