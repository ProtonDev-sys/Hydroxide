local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local ClosureSpy = {}
local Methods = import("modules/ClosureSpy")
local Theme = oh.Theme or import("ui/Theme")

if not hasMethods(Methods.RequiredMethods) then
	return ClosureSpy
end

local Closure = import("objects/Closure")

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
local Assets = import("rbxassetid://5042114982").ClosureSpy

local Prompts = Base.Prompts
local Page = Base.Body.Pages.ClosureSpy

local ClosureList = Page.List
local ListQuery = ClosureList.Query
local ListSearch = ListQuery.Search
local ListRefresh = ListQuery.Refresh
local ListResults = ClosureList.Results.Clip.Content

local ClosureLogs = Page.Logs
local LogsButtons = ClosureLogs.Buttons
local LogsClosure = ClosureLogs.ClosureObject
local LogsBack = ClosureLogs.Back
local LogsClip = ClosureLogs.Results.Clip
local LogsResults = LogsClip.Content

local ClosureConditions = Page.Conditions
local ConditionsClosure = ClosureConditions.ClosureObject
local ConditionsButtons = ClosureConditions.Buttons
local ConditionsResults = ClosureConditions.Results.Clip.Content
local ConditionsBack = ClosureConditions.Back

local NewClosureCondition = Prompts.NewClosureCondition
local NewConditionInner = NewClosureCondition.Inner
local NewConditionButtons = NewConditionInner.Buttons
local NewConditionContent = NewConditionInner.Content
local NewConditionIndex = NewConditionContent.Index

local currentClosures = Methods.CurrentClosures

local icons = {
	type = "rbxassetid://4702850565",
	status = "rbxassetid://4909102841",
	valueType = "rbxassetid://4702850565",
	block = "rbxassetid://4891641806",
	unblock = "rbxassetid://4891642508",
	ignore = "rbxassetid://4842578510",
	unignore = "rbxassetid://4842578818",
	copy = "rbxassetid://4891705738",
	arguments = "rbxassetid://4666594276",
	results = "rbxassetid://4666593882",
	source = "rbxassetid://4891705738",
	spy = "rbxassetid://4666593447",
	stack = "rbxassetid://5179169654",
}

local constants = {
	fadeLength = TweenInfo.new(0.15),
	textWidth = Vector2.new(1337420, 20),
	normalColor = Theme.Colors.Text,
	blockedColor = Theme.Colors.Danger,
	ignoredColor = Theme.Colors.TextDisabled,
}

oh.Settings = oh.Settings or {}
if type(oh.Settings.MaxRenderedLogs) ~= "number" and type(oh.Settings.maxRenderedLogs) ~= "number" then
	oh.Settings.MaxRenderedLogs = 100
end

local newClosureCondition = Prompt.new(NewClosureCondition)
local conditionStatus = Dropdown.new(NewConditionContent.Status)
local conditionType = Dropdown.new(NewConditionContent.Type)
local conditionValueType = Dropdown.new(NewConditionContent.ValueType)

for _, valueType in ipairs({
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
}) do
	conditionType:AddOption(valueType, oh.Constants.Types[valueType] or oh.Constants.Types.userdata)
end

conditionStatus:AddOption("Ignore", icons.ignore)
conditionStatus:AddOption("Block", icons.block)
conditionValueType:AddOption("Type")
conditionValueType:AddOption("Value")

local closureList = List.new(ListResults, true)
local hookLogs = List.new(LogsResults)
local closureConditions = List.new(ConditionsResults, true)

local currentLogs = {}
local removed = {}

local selected = {}
local selectedLogTargets = {}
local selectedConditionTargets = {}
local updateCallInspector

local function collectSelectedLogs()
	local targets = {}
	local seen = {}

	for _, listButton in ipairs(closureList.Selected or {}) do
		local log = listButton.Log
		local instance = listButton.Instance

		if
			log
			and not seen[log]
			and instance
			and instance.Parent
			and closureList.Buttons[instance] == listButton
			and currentLogs[log.Hook] == log
		then
			seen[log] = true
			targets[#targets + 1] = log
		end
	end

	return targets
end

local function collectSelectedConditions()
	local targets = {}
	local seen = {}
	local currentHook = selected.conditionLog and selected.conditionLog.Hook

	for _, listButton in ipairs(closureConditions.Selected or {}) do
		local condition = listButton.Condition
		local instance = listButton.Instance

		if
			condition
			and not seen[condition]
			and currentHook
			and condition.Closure == currentHook
			and instance
			and instance.Parent
			and closureConditions.Buttons[instance] == listButton
		then
			seen[condition] = true
			targets[#targets + 1] = condition
		end
	end

	return targets
end

local function consumeSelectedLogs()
	local targets = selectedLogTargets
	selectedLogTargets = {}
	local valid = {}

	for _, log in ipairs(targets) do
		local button = log and log.Button
		local instance = button and button.Instance

		if
			instance
			and instance.Parent
			and closureList.Buttons[instance] == button
			and currentLogs[log.Hook] == log
		then
			valid[#valid + 1] = log
		end
	end

	return valid
end

local function consumeSelectedConditions()
	local targets = selectedConditionTargets
	selectedConditionTargets = {}
	local valid = {}
	local currentHook = selected.conditionLog and selected.conditionLog.Hook

	for _, condition in ipairs(targets) do
		local button = condition and condition.Button
		local instance = button and button.Instance

		if
			currentHook
			and condition.Closure == currentHook
			and instance
			and instance.Parent
			and closureConditions.Buttons[instance] == button
		then
			valid[#valid + 1] = condition
		end
	end

	return valid
end

local conditionContext = ContextMenuButton.new("rbxassetid://4891633802", "Call Conditions")
local clearContext = ContextMenuButton.new("rbxassetid://4892169181", "Clear Calls")
local ignoreContext = ContextMenuButton.new("rbxassetid://4842578510", "Ignore Calls")
local blockContext = ContextMenuButton.new("rbxassetid://4891641806", "Block Calls")
local removeContext = ContextMenuButton.new("rbxassetid://4702831188", "Remove Log")

local argumentsContext = ContextMenuButton.new(icons.arguments, "View Arguments")
local returnsContext = ContextMenuButton.new(icons.results, "View Returns")
local callStackContext = ContextMenuButton.new(icons.stack, "View Call Stack")
local functionStackContext = ContextMenuButton.new(icons.spy, "View Function Stack")
local inspectFunctionContext = ContextMenuButton.new(icons.spy, "Inspect Calling Function")
local inspectTargetContext = ContextMenuButton.new(icons.spy, "Inspect Target Function")
local inspectScriptContext = ContextMenuButton.new(icons.source, "Inspect Calling Script")
local callingScriptContext = ContextMenuButton.new(icons.copy, "Copy Calling Script Path")
local spyClosureContext = ContextMenuButton.new(icons.spy, "Spy Calling Function")

local removeConditionContext = ContextMenuButton.new("rbxassetid://4702831188", "Remove Condition")

local clearContextSelected = ContextMenuButton.new("rbxassetid://4892169181", "Clear Calls")
local ignoreContextSelected = ContextMenuButton.new("rbxassetid://4842578510", "Ignore Calls")
local blockContextSelected = ContextMenuButton.new("rbxassetid://4891641806", "Block Calls")
local unignoreContextSelected = ContextMenuButton.new("rbxassetid://4842578818", "Unignore Calls")
local unblockContextSelected = ContextMenuButton.new("rbxassetid://4891642508", "Unblock Calls")
local removeContextSelected = ContextMenuButton.new("rbxassetid://4702831188", "Remove Logs")

local removeConditionContextSelected = ContextMenuButton.new("rbxassetid://4702831188", "Remove Conditions")

local closureListMenu = ContextMenu.new({ conditionContext, clearContext, ignoreContext, blockContext, removeContext })
local closureListMenuSelected = ContextMenu.new({
	clearContextSelected,
	ignoreContextSelected,
	unignoreContextSelected,
	blockContextSelected,
	unblockContextSelected,
	removeContextSelected,
})
local hookLogsMenu = ContextMenu.new({
	argumentsContext,
	returnsContext,
	callStackContext,
	functionStackContext,
	inspectFunctionContext,
	inspectTargetContext,
	inspectScriptContext,
	callingScriptContext,
	spyClosureContext,
})
local closureConditionMenu = ContextMenu.new({ removeConditionContext })
local closureConditionMenuSelected = ContextMenu.new({ removeConditionContextSelected })

local queuedLogRenders = {}
local queuedCountUpdates = {}
local countUpdateQueued = false
local dirtyLogRenders = {}
local renderedCallLog
local renderedCallButtons = {}
local detailsGeneration = 0
local activeViewer
local alive = true

local function uiAlive()
	return alive and Page ~= nil and Page.Parent ~= nil
end

local lifecycle = {
	Connected = true,
}

function lifecycle:Disconnect()
	if not self.Connected then
		return
	end

	self.Connected = false
	alive = false
	detailsGeneration = detailsGeneration + 1
	selected.args = nil
	selected.callingScript = nil
	selected.func = nil
	selected.callInfo = nil
	selected.callPodButton = nil
	selected.hookLog = nil
	selected.logContext = nil
	selected.conditionLog = nil
	selected.condition = nil
	selectedLogTargets = {}
	selectedConditionTargets = {}
	queuedLogRenders = {}
	queuedCountUpdates = {}
	dirtyLogRenders = {}
	countUpdateQueued = false

	local viewer = activeViewer
	activeViewer = nil

	if viewer then
		pcall(TextViewer.Hide, viewer)
	end

	pcall(Methods.SetEvent, nil)
end

oh.Events[#oh.Events + 1] = lifecycle

local function getMaxRenderedLogs()
	local settings = oh.Settings or {}
	local value = tonumber(settings.MaxRenderedLogs or settings.maxRenderedLogs)

	if not value or value < 1 then
		return 100
	end

	return math.floor(value)
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

	if updateCallInspector then
		updateCallInspector()
	end
end

local function selectedCallAlive()
	return selected.callInfo ~= nil
end

local function guardSelectedCall(title)
	if uiAlive() and Page.Visible and selectedCallAlive() then
		return true
	end

	clearSelectedCall()
	detailsGeneration = detailsGeneration + 1

	if uiAlive() and Page.Visible then
		local generation = detailsGeneration
		local viewer
		viewer = TextViewer.Show(title or "No Call Selected", "Select a captured call to inspect.", {
			OnHide = function(hiddenViewer)
				if activeViewer == hiddenViewer then
					activeViewer = nil
				end

				if generation == detailsGeneration then
					detailsGeneration = detailsGeneration + 1
				end
			end,
		})
		activeViewer = viewer
	end

	return false
end

local function renderDetails(title, text, options)
	if not uiAlive() or not Page.Visible then
		return nil
	end

	local generation = detailsGeneration
	local viewerOptions = {}

	for name, value in pairs(type(options) == "table" and options or {}) do
		viewerOptions[name] = value
	end

	local onHide = viewerOptions.OnHide
	viewerOptions.OnHide = function(viewer)
		if activeViewer == viewer then
			activeViewer = nil
		end

		if generation == detailsGeneration then
			detailsGeneration = detailsGeneration + 1
		end

		if type(onHide) == "function" then
			pcall(onHide, viewer)
		end
	end
	local viewer = TextViewer.Show(title, text, viewerOptions)
	activeViewer = viewer
	return viewer
end

local function showDetails(title, text, options)
	if not uiAlive() or not Page.Visible then
		return nil
	end

	detailsGeneration = detailsGeneration + 1
	return renderDetails(title, text, options)
end

local function showDetailsAsync(title, loadingText, callback, options)
	if not guardSelectedCall(title) then
		return
	end

	detailsGeneration = detailsGeneration + 1
	local generation = detailsGeneration
	local call = selected.callInfo
	renderDetails(title, loadingText)
	local function requestIsActive()
		return uiAlive() and Page.Visible and generation == detailsGeneration and selected.callInfo == call
	end

	task.spawn(function()
		if not requestIsActive() then
			return
		end

		local text

		local function inspect()
			local ran, result = pcall(callback, call, requestIsActive)
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
	hookLogs:Clear()
end

local function getClosureMetric(method, closure)
	if type(method) ~= "function" then
		return "?"
	end

	local ran, values = pcall(method, closure)

	if ran and type(values) == "table" then
		return #values
	end

	return "!"
end

local function argumentSummary(value)
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
		local text = value:gsub("\n", "\\n")

		if #text > 120 then
			text = text:sub(1, 120) .. "... (" .. #value .. " chars)"
		end

		return '"' .. text .. '"'
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
	elseif rawType == "nil" then
		return "nil"
	end

	local text = tostring(value)

	if #text > 140 then
		text = text:sub(1, 140) .. "... (" .. #text .. " chars)"
	end

	return text
end

local function expandedValue(value, maximumBytes)
	local rawType = type(value)
	local valueType = typeof(value)

	if
		type(formatValueTree) ~= "function"
		or rawType ~= "table"
		or (valueType ~= "table" and valueType ~= "SharedTable")
		or rawget(value, "__hydroxideCaptureMarker") == true
	then
		return nil
	end

	local settings = oh.Settings or {}
	local ran, result = pcall(formatValueTree, value, {
		MaxDepth = settings.MaxValueViewDepth or settings.maxValueViewDepth,
		MaxEntries = settings.MaxValueViewEntries or settings.maxValueViewEntries,
		MaxTableEntries = settings.MaxValueViewTableEntries or settings.maxValueViewTableEntries,
		MaxOutputBytes = maximumBytes,
	})

	if ran and type(result) == "string" and result ~= "" then
		return result
	end

	return ran and nil or ("<table inspection failed: %s>"):format(tostring(result))
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
	local settings = oh.Settings or {}
	local maximumBytes =
		math.max(1024, math.floor(tonumber(settings.MaxValueViewBytes or settings.maxValueViewBytes) or 65536))
	local lines = { title, ("Count: %d"):format(count), "" }

	if count == 0 then
		lines[#lines + 1] = "(none)"
		return table.concat(lines, "\n")
	end

	local outputBytes = #title + 32

	for index = 1, count do
		local value = values[index]
		local valueType = typeof(value)
		local header = ("[%02d]  %s"):format(index, valueType)
		local remaining = maximumBytes - outputBytes - #header - 2

		if remaining < 256 then
			lines[#lines + 1] = "... <value viewer output limit reached>"
			break
		end

		local expanded = expandedValue(value, remaining)

		if expanded then
			lines[#lines + 1] = header
			lines[#lines + 1] = expanded
			lines[#lines + 1] = ""
			outputBytes = outputBytes + #header + #expanded + 2
		else
			local detail = valueType == "Instance" and safeInstancePath(value) or argumentSummary(value)
			local line = ("%-24s  %s"):format(header, detail or "unavailable")
			lines[#lines + 1] = line
			outputBytes = outputBytes + #line + 1
		end
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

local function describeStackFunctions(call, isAlive)
	return FunctionInspector.DescribeStack(call and call.stack, {
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
				math.min(
					8388608,
					math.floor(tonumber(settings.MaxInspectorBytes or settings.maxInspectorBytes) or 524288)
				)
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

local function describeCallStack(call)
	if not call then
		return "No call is selected."
	end

	local caller = type(call.caller) == "table" and call.caller or {}
	local state = call.blocked and "Blocked"
		or (call.error and "Forward error")
		or (call.forwarded and "Forwarded")
		or "Captured"
	local source = cleanSource(caller.shortSource or caller.source)
	local line = tonumber(caller.line)
	local lines = {
		"CLOSURE CALL TRACE",
		("Target: %s"):format(
			selected.hookLog and selected.hookLog.Hook and selected.hookLog.Hook.Closure.Name or "unknown"
		),
		("State: %s"):format(state),
		("Captured: %s"):format(formatTimestamp(call.timestamp)),
		("Duration: %s"):format(
			type(call.durationMs) == "number" and ("%.3f ms"):format(call.durationMs) or "not available"
		),
		("Calling script: %s"):format(safeInstancePath(call.script) or "unknown"),
		("Caller: %s"):format(tostring(caller.name or "anonymous")),
		("Location: %s:%s"):format(source, line and tostring(math.floor(line)) or "?"),
		("Arguments: %d | Returns: %d"):format(getArgCount(call.args), getArgCount(call.returns)),
		"",
	}

	if call.error then
		table.insert(lines, #lines, "Error: " .. tostring(call.error))
	end

	if caller.limitation then
		table.insert(lines, #lines, "Capture note: " .. tostring(caller.limitation))
	end

	if type(call.chain) == "table" and #call.chain > 0 then
		lines[#lines + 1] = ("Active spied-closure chain (%d):"):format(#call.chain)

		for index, frame in ipairs(call.chain) do
			if type(frame) == "table" then
				local name = frame.name or frame.Name or frame.closureName or frame.ClosureName or "anonymous"
				local scriptInstance = frame.script or frame.Script
				local scriptPath = safeInstancePath(scriptInstance)
				local frameSource = cleanSource(frame.source)
				local frameLine = tonumber(frame.line)
				lines[#lines + 1] = ("%02d  %s"):format(index, tostring(name))
				lines[#lines + 1] = ("    %s:%s%s"):format(
					frameSource,
					frameLine and tostring(math.floor(frameLine)) or "?",
					scriptPath and ("  [" .. scriptPath .. "]") or ""
				)
			else
				lines[#lines + 1] = ("%02d  %s"):format(index, tostring(frame))
			end
		end

		lines[#lines + 1] = ""
	end

	local stack = call.stack

	if type(stack) ~= "table" or #stack == 0 then
		lines[#lines + 1] = "No structured stack was captured for this call."
		return table.concat(lines, "\n")
	end

	lines[#lines + 1] = ("External VM call chain (%d frames; native and Hydroxide frames removed):"):format(#stack)
	lines[#lines + 1] = "First frame is closest to the closure call; arrows walk outward through the caller chain."

	for index, frame in ipairs(stack) do
		if type(frame) == "table" then
			local name = frame.name or frame.Name or "anonymous"
			local source = cleanSource(frame.short_src or frame.shortSource or frame.source or frame.Source)
			local line = tonumber(frame.currentline or frame.line or frame.Line)
			local scriptInstance = frame.script or frame.Script
			local scriptPath = safeInstancePath(scriptInstance)
			local func = frame.func or frame.Function or frame.functionValue
			lines[#lines + 1] = ("%02d  %s%s"):format(
				index,
				tostring(name),
				func and ("  [" .. tostring(func) .. "]") or ""
			)
			lines[#lines + 1] = ("    %s:%s%s"):format(
				source,
				line and tostring(math.floor(line)) or "?",
				scriptPath and ("  [" .. scriptPath .. "]") or ""
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

local callInspector

local function hasSelectedCall()
	return selected.callInfo ~= nil
end

updateCallInspector = function()
	if not uiAlive() or not callInspector then
		return
	end

	if not hasSelectedCall() or not selected.callInfo then
		callInspector:SetStatus("Select a captured call to inspect")
		callInspector:SetEnabled("Arguments", false)
		callInspector:SetEnabled("Returns", false)
		callInspector:SetEnabled("CallStack", false)
		callInspector:SetEnabled("FunctionStack", false)
		callInspector:SetEnabled("Function", false)
		callInspector:SetEnabled("Target", false)
		callInspector:SetEnabled("ScriptSource", false)
		callInspector:SetEnabled("ScriptPath", false)
		callInspector:SetEnabled("SpyFunction", false)
		return
	end

	local call = selected.callInfo
	local argCount = getArgCount(selected.args)
	local caller = typeof(call.script) == "Instance" and call.script.Name or "unknown script"
	local state = call.blocked and "blocked"
		or (call.error and "forward error")
		or (call.forwarded and "forwarded")
		or "captured"
	local duration = type(call.durationMs) == "number" and ("%.2f ms"):format(call.durationMs) or "no timing"
	local status = ("closure | %d args | %s | %s"):format(argCount, state, duration)

	callInspector:SetStatus(status, caller)
	callInspector:SetEnabled("Arguments", true)
	callInspector:SetEnabled("Returns", call.completed == true)
	callInspector:SetEnabled("CallStack", true)
	callInspector:SetEnabled("FunctionStack", type(call.stack) == "table" and #call.stack > 0)
	callInspector:SetEnabled("Function", type(selected.func) == "function")
	callInspector:SetEnabled("Target", selected.hookLog ~= nil)
	callInspector:SetEnabled("ScriptSource", typeof(selected.callingScript) == "Instance")
	callInspector:SetEnabled("ScriptPath", typeof(selected.callingScript) == "Instance")
	callInspector:SetEnabled("SpyFunction", type(selected.func) == "function")
end

local function selectCall(_log, button, call)
	selected.args = call.args
	selected.callingScript = call.script
	selected.func = call.func
	selected.callInfo = call
	selected.callPodButton = button
	updateCallInspector()
	showDetails("Closure Call Stack", describeCallStack(call))
end

local function checkCurrentIgnored()
	local selectedHook = (selected.hookLog or selected.logContext).Hook

	LogsButtons.Ignore.Label.Text = (selectedHook.Ignored and "Unignore") or "Ignore"
	LogsButtons.Ignore.Icon.Image = (selectedHook.Ignored and icons.unignore) or icons.ignore

	local newWidth = TextService:GetTextSize(
		(selectedHook.Ignored and "Unignore") or "Ignore",
		18,
		"SourceSans",
		constants.textWidth
	).X + 30

	LogsButtons.Ignore.Size = UDim2.new(0, newWidth, 0, 20)
end

local function checkCurrentBlocked()
	local selectedHook = (selected.hookLog or selected.logContext).Hook

	LogsButtons.Block.Label.Text = (selectedHook.Blocked and "Unblock") or "Block"
	LogsButtons.Block.Icon.Image = (selectedHook.Blocked and icons.unblock) or icons.block

	local newWidth = TextService:GetTextSize(
		(selectedHook.Blocked and "Unblock") or "Block",
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
	return branch and next(branch.types) == nil and next(branch.values) == nil and branch.nan ~= true
end

function Condition.new(closure, status, index, value, type)
	local condition = {}
	local instance = Assets.ConditionPod:Clone()
	local content = instance.Content
	local identifiers = instance.Identifiers
	local button = ListButton.new(instance, closureConditions)
	local check = CheckBox.new(content.Toggle)
	local valueType = type or typeof(value)
	local typeIcons = oh.Constants.Types
	local storage = status == "Ignore" and closure.IgnoredArgs or closure.BlockedArgs
	local branch = storage[index]

	condition.Branch = branch
	condition.Storage = storage
	condition.Status = status
	condition.Index = index
	condition.Value = value
	condition.Type = type
	condition.Closure = closure
	condition.Enabled = true
	condition.Instance = instance
	condition.Button = button
	button.Condition = condition
	condition.Toggle = Condition.toggle
	condition.Remove = Condition.remove

	check:SetCallback(function()
		condition:Toggle()
	end)

	button:SetRightCallback(function()
		selected.condition = condition
	end)

	instance.MouseButton2Click:Connect(function()
		if uiAlive() then
			selectedConditionTargets = collectSelectedConditions()
		end
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

local function createConditions(hook)
	selected.condition = nil
	selectedConditionTargets = {}
	closureConditions:Clear()

	ClosureList.Visible = false
	ClosureLogs.Visible = false
	ClosureConditions.Visible = true

	local nameLength = TextService:GetTextSize(hook.Closure.Name, 18, "SourceSans", constants.textWidth).X + 20

	ConditionsClosure.Icon.Image = oh.Constants.Types["function"]
	ConditionsClosure.Label.Text = hook.Closure.Name
	ConditionsClosure.Label.Size = UDim2.new(0, nameLength, 0, 20)
	ConditionsClosure.Position = UDim2.new(1, -nameLength, 0, 0)

	for index, arg in pairs(hook.IgnoredArgs) do
		for type in pairs(arg.types) do
			Condition.new(hook, "Ignore", index, nil, type)
		end

		for value in pairs(arg.values) do
			Condition.new(hook, "Ignore", index, value)
		end

		if arg.nan then
			Condition.new(hook, "Ignore", index, 0 / 0)
		end
	end

	for index, arg in pairs(hook.BlockedArgs) do
		for type in pairs(arg.types) do
			Condition.new(hook, "Block", index, nil, type)
		end

		for value in pairs(arg.values) do
			Condition.new(hook, "Block", index, value)
		end

		if arg.nan then
			Condition.new(hook, "Block", index, 0 / 0)
		end
	end
end

closureList:BindContextMenu(closureListMenu)
closureList:BindContextMenuSelected(closureListMenuSelected)
hookLogs:BindContextMenu(hookLogsMenu)
closureConditions:BindContextMenu(closureConditionMenu)
closureConditions:BindContextMenuSelected(closureConditionMenuSelected)

-- Log Object
local Log = {}
local ArgsLog = {}
local renderLatestCalls
local queueLogRender

function Log.new(hook)
	local log = {}
	local button = Assets.ClosureLog:Clone()
	local buttonName = button:FindFirstChild("Name")
	local buttonInfo = button.Information
	local listButton = ListButton.new(button, closureList)
	local closure = hook.Closure
	local original = closure.Data

	local normalAnimation =
		TweenService:Create(buttonName, constants.fadeLength, { TextColor3 = constants.normalColor })
	local blockAnimation =
		TweenService:Create(buttonName, constants.fadeLength, { TextColor3 = constants.blockedColor })
	local ignoreAnimation =
		TweenService:Create(buttonName, constants.fadeLength, { TextColor3 = constants.ignoredColor })

	buttonInfo.Protos.Text = "..."
	buttonInfo.Upvalues.Text = "..."
	buttonInfo.Constants.Text = "..."

	button.Name = closure.Name
	buttonName.Text = closure.Name

	local function viewLogs()
		selectedLogTargets = {}

		if selected.hookLog then
			resetRenderedCalls()
		end

		local nameLength = TextService:GetTextSize(closure.Name, 18, "SourceSans", constants.textWidth).X + 20

		selected.hookLog = log
		buttonInfo.Protos.Text = getClosureMetric(getProtos, original)
		buttonInfo.Upvalues.Text = getClosureMetric(getUpvalues, original)
		buttonInfo.Constants.Text = getClosureMetric(getConstants, original)

		renderLatestCalls(log, true)

		checkCurrentBlocked()
		checkCurrentIgnored()

		LogsClosure.Icon.Image = oh.Constants.Types["function"]
		LogsClosure.Label.Text = closure.Name
		LogsClosure.Label.Size = UDim2.new(0, nameLength, 0, 20)
		LogsClosure.Position = UDim2.new(1, -nameLength, 0, 0)
	end

	listButton:SetCallback(function()
		withExecutorIdentity(function()
			if selected.hookLog ~= log then
				viewLogs()
			end

			ClosureList.Visible = false
			ClosureLogs.Visible = true

			selected.hookLog = log

			if dirtyLogRenders[log] then
				queueLogRender(log)
			end
		end)
	end)

	listButton:SetRightCallback(function()
		withExecutorIdentity(function()
			ignoreContext:SetIcon((hook.Ignored and icons.unignore) or icons.ignore)
			ignoreContext:SetText((hook.Ignored and "Unignore Calls") or "Ignore Calls")
			blockContext:SetIcon((hook.Blocked and icons.unblock) or icons.block)
			blockContext:SetText((hook.Blocked and "Unblock Calls") or "Block Calls")

			selected.logContext = log
		end)
	end)

	button.MouseButton2Click:Connect(function()
		if uiAlive() then
			selectedLogTargets = collectSelectedLogs()
		end
	end)

	currentLogs[hook] = log

	log.Hook = hook
	log.Button = listButton
	log.BlockAnimation = blockAnimation
	log.IgnoreAnimation = ignoreAnimation
	log.NormalAnimation = normalAnimation
	log.Clear = Log.clear
	log.PlayBlock = Log.playBlock
	log.PlayIgnore = Log.playIgnore
	log.PlayNormal = Log.playNormal
	log.Adjust = Log.adjust
	log.IncrementCalls = Log.incrementCalls
	log.DecrementCalls = Log.decrementCalls
	listButton.Log = log

	return log
end

local function createArg(instance, index, value)
	local arg = Assets.Arg:Clone()
	local valueType = type(value)

	arg.Icon.Image = oh.Constants.Types[valueType]
	arg.Index.Text = index
	arg.Label.Text = argumentSummary(value)
	arg.Label.TextColor3 = oh.Constants.Syntax[valueType]
	arg.Parent = instance.Contents

	return arg.AbsoluteSize.Y + 5
end

function ArgsLog.new(log, call)
	local instance = Assets.CallPod:Clone()
	local args = call.args or {}

	if selected.hookLog ~= log then
		instance.Visible = false
	end

	local button = ListButton.new(instance, hookLogs)
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
		selectCall(log, button, call)
	end

	button:SetCallback(chooseCall)
	button:SetRightCallback(chooseCall)

	button.Instance.Size = button.Instance.Size + UDim2.new(0, 0, 0, height)

	return button
end

renderLatestCalls = function(log, rebuild)
	if not uiAlive() or not Page.Visible then
		if alive then
			dirtyLogRenders[log] = true
		end

		return
	end

	dirtyLogRenders[log] = nil
	local oldCanvasY = LogsResults.CanvasPosition.Y
	local followNewest = rebuild == true or oldCanvasY <= 6
	local anchorCall
	local anchorOrder

	if not followNewest and renderedCallLog == log then
		for call, button in pairs(renderedCallButtons) do
			local instance = button.Instance

			if instance and instance.Parent and instance.Visible then
				local order = instance.LayoutOrder
				local relativeBottom = instance.AbsolutePosition.Y
					- LogsResults.AbsolutePosition.Y
					+ instance.AbsoluteSize.Y

				if relativeBottom > 0 and (not anchorOrder or order < anchorOrder) then
					anchorCall = call
					anchorOrder = order
				end
			end
		end
	end

	hookLogs:BeginBatch()

	if rebuild or renderedCallLog ~= log then
		resetRenderedCalls()
		renderedCallLog = log
	end

	local logs = log.Hook.Logs
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
			button.Instance.Visible = selected.hookLog == log
		end
	end

	hookLogs:EndBatch()
	hookLogs:QueueRecalculate()

	task.defer(function()
		if
			not uiAlive()
			or not Page.Visible
			or not ClosureLogs.Visible
			or selected.hookLog ~= log
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

queueLogRender = function(log)
	if not uiAlive() then
		return
	end

	dirtyLogRenders[log] = true

	if not Page.Visible or not ClosureLogs.Visible or selected.hookLog ~= log or queuedLogRenders[log] then
		return
	end

	queuedLogRenders[log] = true
	task.defer(function()
		queuedLogRenders[log] = nil

		if uiAlive() and Page.Visible and ClosureLogs.Visible and selected.hookLog == log and dirtyLogRenders[log] then
			renderLatestCalls(log)
		end
	end)
end

local function updateCountDisplay(log)
	if not uiAlive() then
		return
	end

	local logInstance = log.Button.Instance
	local calls = log.Hook.Calls

	logInstance.Calls.Text = (calls < 10000 and calls) or "..."
	log:Adjust()
end

local function flushCountUpdates()
	countUpdateQueued = false

	if not uiAlive() or not Page.Visible then
		return
	end

	local pending = queuedCountUpdates
	queuedCountUpdates = {}

	for log in pairs(pending) do
		if not uiAlive() or not Page.Visible then
			queuedCountUpdates[log] = true
		else
			local button = log.Button
			local instance = button and button.Instance

			if instance and instance.Parent and currentLogs[log.Hook] == log then
				updateCountDisplay(log)
			end
		end
	end
end

local function scheduleCountUpdates()
	if countUpdateQueued or not uiAlive() or not Page.Visible or next(queuedCountUpdates) == nil then
		return
	end

	countUpdateQueued = true
	task.defer(function()
		if not uiAlive() then
			countUpdateQueued = false
			return
		end

		flushCountUpdates()
	end)
end

local function queueCountUpdate(log)
	if not uiAlive() then
		return
	end

	queuedCountUpdates[log] = true
	scheduleCountUpdates()
end

local visibleConnection = Page:GetPropertyChangedSignal("Visible"):Connect(function()
	if not uiAlive() then
		return
	end

	if Page.Visible then
		scheduleCountUpdates()

		local log = selected.hookLog

		if log and ClosureLogs.Visible and dirtyLogRenders[log] then
			queueLogRender(log)
		end
	else
		detailsGeneration = detailsGeneration + 1
		selectedLogTargets = {}
		selectedConditionTargets = {}
		local viewer = activeViewer
		activeViewer = nil

		if viewer then
			pcall(TextViewer.Hide, viewer)
		end
	end
end)
oh.Events[#oh.Events + 1] = visibleConnection

local destroyingConnection = Page.Destroying:Connect(function()
	lifecycle:Disconnect()
end)
oh.Events[#oh.Events + 1] = destroyingConnection

local ancestryConnection = Page.AncestryChanged:Connect(function()
	if alive and not Page:IsDescendantOf(game) then
		lifecycle:Disconnect()
	end
end)
oh.Events[#oh.Events + 1] = ancestryConnection

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
	local logInstance = log.Button.Instance
	local logIcon = logInstance.Icon
	local logName = logInstance:FindFirstChild("Name")

	local callWidth = TextService:GetTextSize(logInstance.Calls.Text, 18, "SourceSans", constants.textWidth).X + 10
	local labelWidth = callWidth + 21

	logInstance.Calls.Size = UDim2.new(0, callWidth, 0, 20)
	logIcon.Position = UDim2.new(0, callWidth, 0.5, -7)
	logName.Position = UDim2.new(0, labelWidth, 0, 0)
	logName.Size = UDim2.new(1, -labelWidth, 1, 0)
end

function Log.clear(log)
	local logInstance = log.Button.Instance

	log.Hook:Clear()

	if selected.hookLog == log then
		resetRenderedCalls()
	end

	logInstance.Calls.Text = 0
	log:Adjust()
end

function Log.incrementCalls(log, call)
	queueCountUpdate(log)

	if selected.hookLog == log then
		queueLogRender(log)
	end
end

function Log.decrementCalls(log, call)
	local hook = log.Hook

	hook:DecrementCalls(call)
	queueCountUpdate(log)
end

function Log.remove(log)
	local hook = log.Hook
	local returnToList = selected.hookLog == log or selected.conditionLog == log
	local removedHook, removeError = hook:Remove()

	if not removedHook then
		MessageBox.Show("Cannot unhook", removeError or "Unable to restore the original closure", MessageType.OK)
		return false
	end

	if selected.hookLog == log then
		resetRenderedCalls()
		selected.hookLog = nil
	end

	if selected.conditionLog == log then
		selected.conditionLog = nil
		selected.condition = nil
		selectedConditionTargets = {}
		closureConditions:Clear()
		newClosureCondition:Hide()
	end

	if returnToList then
		detailsGeneration = detailsGeneration + 1
		TextViewer.Hide(activeViewer)
		activeViewer = nil
		ClosureLogs.Visible = false
		ClosureConditions.Visible = false
		ClosureList.Visible = true
	end

	queuedLogRenders[log] = nil
	dirtyLogRenders[log] = nil
	queuedCountUpdates[log] = nil
	log.Button:Remove()
	currentLogs[hook] = nil
	removed[hook] = true
	return true
end

-- UI Functionality
ListSearch.FocusLost:Connect(function(returned)
	if returned then
		local query = ListSearch.Text:lower()

		for hook, log in pairs(currentLogs) do
			local instance = log.Button.Instance
			instance.Visible = hook.Closure.Name:lower():find(query, 1, true) ~= nil
		end

		closureList:Recalculate()
		ListSearch.Text = ""
	end
end)

ListRefresh.MouseButton1Click:Connect(function()
	closureList:Recalculate()
end)

LogsBack.MouseButton1Click:Connect(function()
	ClosureLogs.Visible = false
	ClosureList.Visible = true
end)

LogsButtons.Ignore.MouseButton1Click:Connect(function()
	local selectedLog = selected.hookLog
	local hook = selectedLog and selectedLog.Hook

	if not hook or currentLogs[hook] ~= selectedLog then
		return
	end

	hook:Ignore()

	checkCurrentIgnored()

	if hook.Blocked then
		selectedLog:PlayBlock()
	elseif hook.Ignored then
		selectedLog:PlayIgnore()
	else
		selectedLog:PlayNormal()
	end
end)

LogsButtons.Block.MouseButton1Click:Connect(function()
	local selectedLog = selected.hookLog
	local hook = selectedLog and selectedLog.Hook

	if not hook or currentLogs[hook] ~= selectedLog then
		return
	end

	hook:Block()

	checkCurrentBlocked()

	if hook.Blocked then
		selectedLog:PlayBlock()
	elseif hook.Ignored then
		selectedLog:PlayIgnore()
	else
		selectedLog:PlayNormal()
	end
end)

LogsButtons.Clear.MouseButton1Click:Connect(function()
	local selectedLog = selected.hookLog
	local hook = selectedLog and selectedLog.Hook

	if hook and currentLogs[hook] == selectedLog then
		selectedLog:Clear()
	end
end)

LogsButtons.Conditions.MouseButton1Click:Connect(function()
	local selectedLog = selected.hookLog
	local hook = selectedLog and selectedLog.Hook

	if not hook or currentLogs[hook] ~= selectedLog then
		return
	end

	selected.conditionLog = selectedLog

	createConditions(hook)
end)

ConditionsBack.MouseButton1Click:Connect(function()
	ClosureConditions.Visible = false

	if selected.hookLog then
		ClosureLogs.Visible = true
	else
		ClosureList.Visible = true
	end
end)

local function conditionBufferLimit()
	return tonumber(oh.Settings and oh.Settings.MaxConditionBufferBytes) or 4096
end

local function parseConditionHexBuffer(text)
	if not buffer or type(buffer.create) ~= "function" or type(buffer.writeu8) ~= "function" then
		return nil, "buffer creation is unavailable"
	end

	local bytes = {}
	local maximum = conditionBufferLimit()

	for token in text:gmatch("%S+") do
		if not token:match("^%x%x$") then
			return nil, "Hex buffers must use two-digit bytes such as DE AD BE EF"
		end

		bytes[#bytes + 1] = tonumber(token, 16)

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

local function parseConditionNumber(text)
	local normalized = text:lower():gsub("^%s+", ""):gsub("%s+$", "")

	if normalized == "nan" or normalized == "0/0" then
		return 0 / 0
	elseif normalized == "inf" or normalized == "+inf" or normalized == "infinity" or normalized == "math.huge" then
		return math.huge
	elseif normalized == "-inf" or normalized == "-infinity" or normalized == "-math.huge" then
		return -math.huge
	end

	return tonumber(normalized)
end

local function validateConditionBuffer(value)
	if not buffer or type(buffer.len) ~= "function" then
		return false, "buffer length inspection is unavailable"
	end

	local measured, length = pcall(buffer.len, value)
	local maximum = conditionBufferLimit()

	if not measured then
		return false, "The buffer length could not be read"
	elseif length > maximum then
		return false, ("Buffer conditions are limited to %d bytes"):format(maximum)
	end

	return true
end

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

	if selected.hookLog ~= selected.conditionLog or not args or index < 1 or index > count then
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
	local maximum = conditionBufferLimit()

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
	populateValue = populateValue == true

	local value, present = selectedArgument(index)
	local input = NewConditionContent.Value.Input

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

ConditionsButtons.New.MouseButton1Click:Connect(function()
	conditionStatus:SetSelected(conditionStatus.Selected and conditionStatus.Selected.Name or "Ignore")
	conditionValueType:SetSelected(conditionValueType.Selected and conditionValueType.Selected.Name or "Type")
	prefillCondition(
		NewConditionIndex.Value.Input.Text,
		conditionValueType.Selected and conditionValueType.Selected.Name == "Value"
	)
	setConditionAssociation(conditionValueType.Selected and conditionValueType.Selected.Name or "Type")
	newClosureCondition:Show()
end)

NewConditionButtons.Add.MouseButton1Click:Connect(function()
	local status = conditionStatus.Selected and conditionStatus.Selected.Name
	local selectedType = conditionType.Selected and conditionType.Selected.Name
	local valueType = conditionValueType.Selected and conditionValueType.Selected.Name
	local value = NewConditionContent.Value.Input.Text
	local argIndex = validConditionIndex(NewConditionIndex.Value.Input.Text)
	local conditionLog = selected.conditionLog
	local selectedHook = conditionLog and conditionLog.Hook

	if not selectedHook or currentLogs[selectedHook] ~= conditionLog then
		newClosureCondition:Hide()
		pcall(oh.setStatus, "Condition target is no longer available")
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
	elseif valueType == "Value" then
		if
			selectedType == "nil"
			or selectedType == "table"
			or selectedType == "function"
			or selectedType == "thread"
		then
			return MessageBox.Show("Error", "Use a Type condition for " .. selectedType .. " arguments", MessageType.OK)
		elseif selectedType == "string" then
			value = value
		elseif selectedType == "number" then
			value = parseConditionNumber(value)

			if value == nil then
				return MessageBox.Show("Error", "Your input does not match the type you selected", MessageType.OK)
			end
		elseif selectedType == "boolean" then
			local lowered = value:lower():gsub("^%s+", ""):gsub("%s+$", "")

			if lowered == "true" then
				value = true
			elseif lowered == "false" then
				value = false
			else
				return MessageBox.Show("Error", "Your input does not match the type you selected", MessageType.OK)
			end
		elseif selectedType == "buffer" and value:match("^%s*[%x][%x%s]*%s*$") then
			local parsed, parseError = parseConditionHexBuffer(value)

			if not parsed then
				return MessageBox.Show("Error", tostring(parseError), MessageType.OK)
			end

			value = parsed
		else
			local chunk, compileError = loadstring("return " .. value)

			if not chunk then
				return MessageBox.Show("Error", tostring(compileError), MessageType.OK)
			end

			local success, result = pcall(chunk)

			if not success then
				return MessageBox.Show("Error", tostring(result), MessageType.OK)
			elseif typeof(result) ~= selectedType then
				return MessageBox.Show("Error", "Your input does not match the type you selected", MessageType.OK)
			end

			value = result

			if selectedType == "buffer" then
				local valid, bufferError = validateConditionBuffer(value)

				if not valid then
					return MessageBox.Show("Error", tostring(bufferError), MessageType.OK)
				end
			end
		end
	else
		value = selectedType
	end

	local byType = valueType == "Type"
	local added, addError

	if status == "Block" then
		added, addError = selectedHook:BlockArg(argIndex, value, byType)
	else
		added, addError = selectedHook:IgnoreArg(argIndex, value, byType)
	end

	if not added then
		return MessageBox.Show(
			"Condition Not Added",
			tostring(addError or "That condition already exists"),
			MessageType.OK
		)
	end

	if byType then
		Condition.new(selectedHook, status, argIndex, nil, value)
	else
		Condition.new(selectedHook, status, argIndex, value)
	end

	newClosureCondition:Hide()
end)

NewConditionButtons.Cancel.MouseButton1Click:Connect(function()
	newClosureCondition:Hide()
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

conditionContext:SetCallback(function()
	selected.conditionLog = selected.logContext or selected.hookLog

	createConditions(selected.conditionLog.Hook)
end)

clearContext:SetCallback(function()
	selected.logContext:Clear()
end)

ignoreContext:SetCallback(function()
	local selectedLog = selected.logContext
	local hook = selectedLog.Hook

	hook:Ignore()

	checkCurrentIgnored()

	if hook.Blocked then
		selectedLog:PlayBlock()
	elseif hook.Ignored then
		selectedLog:PlayIgnore()
	else
		selectedLog:PlayNormal()
	end
end)

blockContext:SetCallback(function()
	local selectedLog = selected.logContext
	local hook = selectedLog.Hook

	hook:Block()

	checkCurrentBlocked()

	if hook.Blocked then
		selectedLog:PlayBlock()
	elseif hook.Ignored then
		selectedLog:PlayIgnore()
	else
		selectedLog:PlayNormal()
	end
end)

removeContext:SetCallback(function()
	selected.logContext:Remove()
end)

ignoreContextSelected:SetCallback(function()
	for _, log in ipairs(consumeSelectedLogs()) do
		local hook = log.Hook

		if not hook.Ignored then
			hook:Ignore()
		end

		if hook.Blocked then
			log:PlayBlock()
		elseif hook.Ignored then
			log:PlayIgnore()
		end
	end
end)

unignoreContextSelected:SetCallback(function()
	for _, log in ipairs(consumeSelectedLogs()) do
		local hook = log.Hook

		if hook.Ignored then
			hook:Ignore()
		end

		if hook.Blocked then
			log:PlayBlock()
		else
			log:PlayNormal()
		end
	end
end)

blockContextSelected:SetCallback(function()
	for _, log in ipairs(consumeSelectedLogs()) do
		local hook = log.Hook

		if not hook.Blocked then
			hook:Block()
		end

		if hook.Blocked then
			log:PlayBlock()
		elseif hook.Ignored then
			log:PlayIgnore()
		end
	end
end)

unblockContextSelected:SetCallback(function()
	for _, log in ipairs(consumeSelectedLogs()) do
		local hook = log.Hook

		if hook.Blocked then
			hook:Block()
		end

		if hook.Ignored then
			log:PlayIgnore()
		else
			log:PlayNormal()
		end
	end
end)

clearContextSelected:SetCallback(function()
	for _, log in ipairs(consumeSelectedLogs()) do
		log:Clear()
	end
end)

removeContextSelected:SetCallback(function()
	for _, log in ipairs(consumeSelectedLogs()) do
		log:Remove()
	end

	closureList:Recalculate()
end)

local function showArguments()
	if guardSelectedCall("Closure Arguments") then
		showDetails("Closure Arguments", describePackedValues("CAPTURED ARGUMENTS", selected.args or {}))
	end
end

local function showReturns()
	if not guardSelectedCall("Closure Returns") then
		return
	end

	local call = selected.callInfo
	local text = describePackedValues("RETURN VALUES", call.returns or {})

	if call.blocked then
		text = "The call was blocked before the target closure ran.\n\n" .. text
	elseif call.error then
		text = "The target closure raised an error:\n" .. tostring(call.error) .. "\n\n" .. text
	end

	showDetails("Closure Returns", text)
end

local function showCallStack()
	if not guardSelectedCall("Closure Call Stack") then
		return
	end

	showDetails("Closure Call Stack", describeCallStack(selected.callInfo))
end

local function showFunctionStack()
	showDetailsAsync("Closure Function Stack", "Inspecting captured stack functions ...", describeStackFunctions)
end

local function inspectCallingFunction()
	local func = selected.func
	showDetailsAsync("Calling Function", "Inspecting calling function ...", function(_call, isAlive)
		return describeFunction(func, isAlive)
	end)
end

local function inspectTargetFunction()
	local func = selected.hookLog and selected.hookLog.Hook and selected.hookLog.Hook.Target
	showDetailsAsync("Target Function", "Inspecting target function ...", function(_call, isAlive)
		return describeFunction(func, isAlive)
	end)
end

local function inspectCallingScript()
	local scriptInstance = selected.callingScript
	showDetailsAsync("Calling Script", "Decompiling calling script ...", function(_call, isAlive)
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
		oh.setStatus("Calling script path copied")
	end
end

local SpyHook = Methods.Hook
local function spyCallingFunction()
	if not guardSelectedCall("Spy Calling Function") then
		return
	end

	if type(selected.func) ~= "function" then
		return MessageBox.Show("Cannot hook", "No Lua closure was captured for this call", MessageType.OK)
	end

	withExecutorIdentity(function()
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
	end)
end

argumentsContext:SetCallback(showArguments)
returnsContext:SetCallback(showReturns)
callStackContext:SetCallback(showCallStack)
functionStackContext:SetCallback(showFunctionStack)
inspectFunctionContext:SetCallback(inspectCallingFunction)
inspectTargetContext:SetCallback(inspectTargetFunction)
inspectScriptContext:SetCallback(inspectCallingScript)
callingScriptContext:SetCallback(copyCallingScriptPath)
spyClosureContext:SetCallback(spyCallingFunction)

callInspector = ActionPanel.Install(LogsButtons, ClosureLogs.Results, {
	Columns = 5,
	MinimumCellWidth = 110,
	ButtonHeight = 21,
	Gap = 3,
	Actions = {
		{ Name = "Arguments", Label = "Arguments", Icon = icons.arguments, Callback = showArguments },
		{ Name = "Returns", Label = "Returns", Icon = icons.results, Callback = showReturns },
		{ Name = "CallStack", Label = "Stack", Icon = icons.stack, Callback = showCallStack },
		{ Name = "FunctionStack", Label = "Fn Stack", Icon = icons.spy, Callback = showFunctionStack },
		{ Name = "Function", Label = "Caller Fn", Icon = icons.spy, Callback = inspectCallingFunction },
		{ Name = "Target", Label = "Target Fn", Icon = icons.spy, Callback = inspectTargetFunction },
		{ Name = "ScriptSource", Label = "Script", Icon = icons.source, Callback = inspectCallingScript },
		{ Name = "ScriptPath", Label = "Copy Path", Icon = icons.copy, Callback = copyCallingScriptPath },
		{ Name = "SpyFunction", Label = "Spy Caller", Icon = icons.spy, Callback = spyCallingFunction },
	},
})
updateCallInspector()

removeConditionContext:SetCallback(function()
	selected.condition:Remove()
	selected.condition = nil
end)

removeConditionContextSelected:SetCallback(function()
	for _, condition in ipairs(consumeSelectedConditions()) do
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

closureList:BeginBatch()

for _closure, hook in pairs(currentClosures) do
	if type(hook) == "table" and hook.Record and hook.Record.Active ~= false and not currentLogs[hook] then
		local log = Log.new(hook)
		local calls = hook.Calls or 0

		log.Button.Instance.Calls.Text = (calls < 10000 and calls) or "..."
		log:Adjust()
	end
end

closureList:EndBatch()

Methods.SetEvent(function(hook, call)
	if not uiAlive() then
		return
	end

	withExecutorIdentity(function()
		if uiAlive() and not removed[hook] then
			local log = currentLogs[hook] or Log.new(hook)
			log:IncrementCalls(call)
		end
	end)
end)

return ClosureSpy
