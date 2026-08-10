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
local LogsResults = RemoteLogs.Results.Clip.Content

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

local remoteList = List.new(ListResults, true)
local remoteLogs = List.new(LogsResults)
local remoteConditions = List.new(ConditionsResults, true)

local currentLogs = {}
local removed = {}

local selected = {
	logs = {},
	conditions = {},
}
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
local inspectFunctionContext = ContextMenuButton.new(icons.spy, "Inspect Calling Function")
local inspectScriptContext = ContextMenuButton.new(icons.source, "Inspect Calling Script")
local callingScriptContext = ContextMenuButton.new(icons.copy, "Copy Calling Script Path")
local spyClosureContext = ContextMenuButton.new(icons.spy, "Spy Calling Function")
local repeatCallContext = ContextMenuButton.new(icons.repeatCall, "Replay Call")
local viewAsHexContext = ContextMenuButton.new(icons.hex, "Toggle String Hex View")

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
	inspectFunctionContext,
	inspectScriptContext,
	callingScriptContext,
	spyClosureContext,
	repeatCallContext,
	viewAsHexContext,
})
local remoteConditionMenu = ContextMenu.new({ removeConditionContext })
local remoteConditionMenuSelected = ContextMenu.new({ removeConditionContextSelected })

local queuedLogRenders = {}
local queuedCountUpdates = {}
local renderedCallLog
local renderedCallButtons = {}
local unpackValues = table.unpack or unpack

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
	return selected.callPodButton and selected.callPodButton.Instance and selected.callPodButton.Instance.Parent
end

local function guardSelectedCall(title)
	if selectedCallAlive() then
		return true
	end

	clearSelectedCall()
	TextViewer.Show(
		title or "Call No Longer Visible",
		"The selected call row is no longer in the rendered newest-call window."
	)
	return false
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

local function describeFunction(func)
	if type(func) ~= "function" then
		return "No Lua closure was captured for this call."
	end

	local lines = {}
	local ran, info = pcall(getInfo, func, "nSlu")
	info = ran and info or nil

	lines[#lines + 1] = "Function: " .. argumentSummary(func)
	lines[#lines + 1] = "Name: " .. tostring(info and info.name or "unknown")
	lines[#lines + 1] = "Source: " .. tostring(info and (info.short_src or info.source) or "unknown")
	lines[#lines + 1] = "Line Defined: " .. tostring(info and info.linedefined or "unknown")
	lines[#lines + 1] = "Current Line: " .. tostring(info and info.currentline or "unknown")
	lines[#lines + 1] = "Upvalues: " .. tostring(info and info.nups or "unknown")

	if type(decompile) == "function" then
		local decompiled, source = pcall(decompile, func)

		if decompiled and type(source) == "string" and source ~= "" then
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

local function describeScript(scriptInstance)
	if typeof(scriptInstance) ~= "Instance" then
		return "No calling script was captured for this call."
	end

	local lines = {}
	lines[#lines + 1] = "Name: " .. scriptInstance.Name
	lines[#lines + 1] = "Class: " .. scriptInstance.ClassName
	lines[#lines + 1] = "Path: " .. (safeInstancePath(scriptInstance) or "unavailable")

	if type(decompile) == "function" then
		local decompiled, source = pcall(decompile, scriptInstance)

		if decompiled and type(source) == "string" and source ~= "" then
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

	for index, frame in ipairs(stack) do
		if type(frame) == "table" then
			local name = frame.name or frame.Name or "anonymous"
			local source = cleanSource(frame.shortSource or frame.short_src or frame.source or frame.Source)
			local line = tonumber(frame.line or frame.currentline or frame.Line)
			local scriptInstance = frame.script or frame.Script
			local frameScriptPath = safeInstancePath(scriptInstance)
			lines[#lines + 1] = ("%02d  %s"):format(index, tostring(name))
			lines[#lines + 1] = ("    %s:%s%s"):format(
				source,
				line and tostring(math.floor(line)) or "?",
				frameScriptPath and ("  [" .. frameScriptPath .. "]") or ""
			)

			if index < #stack then
				lines[#lines + 1] = "    ↓"
			end
		else
			lines[#lines + 1] = ("%02d  %s"):format(index, tostring(frame))
		end
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
		if type(args[index]) == "string" then
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
		callInspector:SetEnabled("Function", false)
		callInspector:SetEnabled("ScriptSource", false)
		callInspector:SetEnabled("ScriptPath", false)
		callInspector:SetEnabled("SpyFunction", false)
		callInspector:SetEnabled("Repeat", false)
		callInspector:SetEnabled("Hex", false)
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
	callInspector:SetEnabled("ReplayCode", true)
	callInspector:SetEnabled("CopyCode", true)
	callInspector:SetEnabled("Arguments", true)
	callInspector:SetEnabled("Returns", callInfo.completed == true)
	callInspector:SetEnabled("CallStack", true)
	callInspector:SetEnabled("Function", type(selected.func) == "function")
	callInspector:SetEnabled("ScriptSource", typeof(selected.callingScript) == "Instance")
	callInspector:SetEnabled("ScriptPath", typeof(selected.callingScript) == "Instance")
	callInspector:SetEnabled("SpyFunction", type(selected.func) == "function")
	callInspector:SetEnabled("Repeat", method ~= nil and remoteInstance and remoteInstance[method] ~= nil)
	callInspector:SetEnabled("Hex", hasStringArg())
end

local function selectCall(log, button, callInfo)
	selected.args = callInfo.args
	selected.callingScript = callInfo.script
	selected.func = callInfo.func
	selected.callInfo = callInfo
	selected.callPodButton = button
	updateCallInspector()
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
function Condition.new(remote, status, index, value, type)
	local condition = {}
	local instance = Assets.ConditionPod:Clone()
	local content = instance.Content
	local identifiers = instance.Identifiers
	local button = ListButton.new(instance, remoteConditions)
	local check = CheckBox.new(content.Toggle)
	local valueType = type or typeof(value)
	local typeIcons = oh.Constants.Types
	local branch = (status == "Ignore" and remote.IgnoredArgs[index]) or remote.BlockedArgs[index]

	condition.Branch = branch
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

	check:SetCallback(function()
		condition:Toggle()
	end)

	button:SetRightCallback(function()
		selected.condition = condition
	end)

	button:SetSelectedCallback(function()
		if not table.find(selected.conditions, condition) then
			table.insert(selected.conditions, condition)
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
	local remote = condition.Remote
	local ignoredArgs = remote.IgnoredArgs[index]
	local blockedArgs = remote.BlockedArgs[index]
	local argStatus = (condition.Status == "Ignore" and ignoredArgs) or blockedArgs

	if value ~= nil then
		argStatus.values[value] = condition.Enabled or nil
	else
		argStatus.types[condition.Type] = condition.Enabled or nil
	end
end

function Condition.remove(condition)
	local branch = condition.Branch
	condition.Button:Remove()

	if condition.Value ~= nil then
		branch.values[condition.Value] = nil
	else
		branch.types[condition.Type] = nil
	end
end

local function createConditions(remote)
	remoteConditions:Clear()

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
	end

	for index, arg in pairs(remote.BlockedArgs) do
		for type in pairs(arg.types) do
			Condition.new(remote, "Block", index, nil, type)
		end

		for value in pairs(arg.values) do
			Condition.new(remote, "Block", index, value)
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

	listButton:SetSelectedCallback(function()
		if not table.find(selected.logs, log) then
			table.insert(selected.logs, log)
		end
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
	remoteLogs:BeginBatch()

	if rebuild or renderedCallLog ~= log then
		resetRenderedCalls()
		renderedCallLog = log
	end

	local logs = log.Remote.Logs
	local total = #logs
	local first = math.max(1, total - getMaxRenderedLogs() + 1)
	local desiredCalls = {}
	local desiredOrder = {}
	local layoutOrder = 0

	for index = first, total do
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

	for index = first, total do
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
end

queueLogRender = function(log)
	if queuedLogRenders[log] then
		return
	end

	queuedLogRenders[log] = true
	task.defer(function()
		queuedLogRenders[log] = nil

		if selected.remoteLog == log and RemoteLogs.Visible then
			renderLatestCalls(log)
		end
	end)
end

local function updateCountDisplay(log)
	local buttonInstance = log.Button.Instance
	local calls = log.Remote.Calls

	buttonInstance.Calls.Text = (calls < 10000 and calls) or "..."
	log:Adjust()
end

local function queueCountUpdate(log)
	if queuedCountUpdates[log] then
		return
	end

	queuedCountUpdates[log] = true
	task.defer(function()
		queuedCountUpdates[log] = nil

		if log.Button and log.Button.Instance and log.Button.Instance.Parent then
			updateCountDisplay(log)
		end
	end)
end

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

function Log.remove(log)
	local remoteInstance = log.Remote.Instance

	if selected.remoteLog == log then
		resetRenderedCalls()
		selected.remoteLog = nil
	end

	log.Button:Remove()
	currentLogs[remoteInstance] = nil
	removed[remoteInstance] = true
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
	local selectedRemote = selected.remoteLog.Remote

	selectedRemote:Ignore()

	checkCurrentIgnored()

	if selectedRemote.Blocked then
		selected.remoteLog:PlayBlock()
	elseif selectedRemote.Ignored then
		selected.remoteLog:PlayIgnore()
	else
		selected.remoteLog:PlayNormal()
	end
end)

LogsButtons.Block.MouseButton1Click:Connect(function()
	local selectedRemote = selected.remoteLog.Remote

	selectedRemote:Block()

	checkCurrentBlocked()

	if selectedRemote.Blocked then
		selected.remoteLog:PlayBlock()
	elseif selectedRemote.Ignored then
		selected.remoteLog:PlayIgnore()
	else
		selected.remoteLog:PlayNormal()
	end
end)

LogsButtons.Clear.MouseButton1Click:Connect(function()
	selected.remoteLog:Clear()
end)

LogsButtons.Conditions.MouseButton1Click:Connect(function()
	selected.conditionLog = selected.remoteLog

	createConditions(selected.conditionLog.Remote)
end)

ConditionsBack.MouseButton1Click:Connect(function()
	RemoteConditions.Visible = false

	if selected.remoteLog then
		RemoteLogs.Visible = true
	else
		RemoteList.Visible = true
	end
end)

ConditionsButtons.New.MouseButton1Click:Connect(function()
	newRemoteCondition:Show()
end)

NewConditionButtons.Add.MouseButton1Click:Connect(function()
	if not conditionStatus.Selected then
		return MessageBox.Show("Error", "Invalid condition status", MessageType.OK)
	end

	local status = conditionStatus.Selected.Name
	local type = conditionType.Selected.Name
	local valueType = conditionValueType.Selected.Name
	local value = NewConditionContent.Value.Input.Text

	if status ~= "Ignore" and status ~= "Block" then
		MessageBox.Show("Error", "Invalid condition status", MessageType.OK)
	elseif not oh.Constants.Types[type] and not isUserdata(type) then
		MessageBox.Show("Error", "Invalid condition type", MessageType.OK)
	elseif valueType ~= "Value" and valueType ~= "Type" then
		MessageBox.Show("Error", "Invalid condition value association", MessageType.OK)
	elseif valueType == "Value" then
		if type == "string" then
			value = toString(value)
		elseif type == "number" then
			value = tonumber(value)

			if not value then
				return MessageBox.Show("Error", "Your input does not match the type you selected", MessageType.OK)
			end
		elseif type == "boolean" then
			if value == "true" then
				value = true
			elseif value == "false" then
				value = false
			else
				return MessageBox.Show("Error", "Your input does not match the type you selected", MessageType.OK)
			end
		else
			local success, result = pcall(loadstring("return " .. value))

			if valueType == "Value" then
				if not success then
					return MessageBox.Show("Error", "There was an error interpreting your input value", MessageType.OK)
				elseif typeof(result) ~= type then
					return MessageBox.Show("Error", "Your input does not match the type you selected", MessageType.OK)
				else
					value = result
				end
			end
		end
	else
		value = type
	end

	local selectedRemote = selected.conditionLog.Remote
	local argIndex = tonumber(NewConditionIndex.Value.Input.Text)
	local byType = valueType == "Type"

	if status == "Block" then
		selectedRemote:BlockArg(argIndex, value, byType)
	else
		selectedRemote:IgnoreArg(argIndex, value, byType)
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
	local newIndex = tonumber(NewConditionIndex.Value.Input.Text) + 1
	NewConditionIndex.Value.Input.Text = newIndex
end)

NewConditionIndex.Sub.MouseButton1Click:Connect(function()
	local newIndex = tonumber(NewConditionIndex.Value.Input.Text) - 1
	NewConditionIndex.Value.Input.Text = (newIndex <= 0 and 1) or newIndex
end)

NewConditionIndex.Value.Input.FocusLost:Connect(function()
	local newIndex = tonumber(NewConditionIndex.Value.Input.Text)

	if not newIndex or newIndex <= 0 then
		NewConditionIndex.Value.Input.Text = 1
	end
end)

pathContext:SetCallback(function()
	local selectedInstance = selected.logContext.Remote.Instance
	local oldStatus = oh.getStatus()

	oh.setStatus("Copying " .. selectedInstance.Name .. "'s path")
	setClipboard(getInstancePath(selectedInstance))
	task.wait(0.25)
	oh.setStatus(oldStatus)
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

pathContextSelected:SetCallback(function()
	local paths = ""

	for _i, log in pairs(selected.logs) do
		paths = paths .. getInstancePath(log.Remote.Instance) .. "\n"
	end

	setClipboard(paths)
	selected.logs = {}
end)

ignoreContextSelected:SetCallback(function()
	for _i, log in pairs(selected.logs) do
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

	selected.logs = {}
end)

unignoreContextSelected:SetCallback(function()
	for _i, log in pairs(selected.logs) do
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

	selected.logs = {}
end)

blockContextSelected:SetCallback(function()
	for _i, log in pairs(selected.logs) do
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

	selected.logs = {}
end)

unblockContextSelected:SetCallback(function()
	for _i, log in pairs(selected.logs) do
		local remote = log.Remote

		remote:Unblock()

		if remote.Ignored then
			log:PlayIgnore()
		else
			log:PlayNormal()
		end
	end

	selected.logs = {}
end)

clearContextSelected:SetCallback(function()
	for _i, log in pairs(selected.logs) do
		log:Clear()
	end

	selected.logs = {}
end)

removeContextSelected:SetCallback(function()
	for _i, log in pairs(selected.logs) do
		log:Remove()
	end

	remoteList:Recalculate()
	selected.logs = {}
end)

local function getSelectedReplayScript()
	if not guardSelectedCall("Replay Code") then
		return nil
	elseif type(buildRemoteScript) ~= "function" then
		return nil, "The replay-script builder is unavailable."
	end

	local remoteInstance = selected.remoteLog.Remote.Instance
	local method = getRemoteMethod(remoteInstance, selected.callInfo)
	local ran, script, buildError = pcall(
		buildRemoteScript,
		remoteInstance,
		method,
		selected.args or {},
		selected.callInfo
	)

	if not ran then
		return nil, tostring(script)
	elseif type(script) ~= "string" or script == "" then
		return nil, tostring(buildError or "The captured values could not be serialized safely.")
	end

	return script
end

local function generateReplayScript()
	local oldStatus = oh.getStatus()
	oh.setStatus("Building replay code ...")

	local script, buildError = getSelectedReplayScript()
	oh.setStatus(oldStatus)

	if not script then
		if buildError then
			TextViewer.Show("Replay Code Unavailable", buildError)
		end

		return
	end

	TextViewer.Show("Remote Replay Code", script, { Editable = true })
end

local function copyReplayScript()
	local script, buildError = getSelectedReplayScript()

	if not script then
		if buildError then
			TextViewer.Show("Replay Code Unavailable", buildError)
		end

		return
	end

	local copied, copyError = pcall(setClipboard, script)

	if not copied then
		TextViewer.Show("Copy Failed", tostring(copyError))
	else
		oh.setStatus("Replay code copied")
	end
end

local function showArguments()
	if guardSelectedCall("Remote Arguments") then
		TextViewer.Show("Remote Arguments", describePackedValues("CAPTURED ARGUMENTS", selected.args or {}))
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

	TextViewer.Show("Remote Returns", text)
end

local function showCallStack()
	if not guardSelectedCall("Remote Call Stack") then
		return
	end

	TextViewer.Show("Remote Call Stack", describeCallStack(selected.callInfo))
end

local function inspectCallingFunction()
	if not guardSelectedCall("Calling Function") then
		return
	end

	TextViewer.Show("Calling Function", describeFunction(selected.func))
end

local function inspectCallingScript()
	if not guardSelectedCall("Calling Script") then
		return
	end

	TextViewer.Show("Calling Script", describeScript(selected.callingScript))
end

local function copyCallingScriptPath()
	if not guardSelectedCall("Calling Script") then
		return
	end

	if typeof(selected.callingScript) ~= "Instance" then
		return TextViewer.Show("Calling Script", "No calling script was captured for this call.")
	end

	local oldStatus = oh.getStatus()

	oh.setStatus("Copying " .. selected.callingScript.Name .. "'s path")
	setClipboard(getInstancePath(selected.callingScript))
	task.wait(0.25)
	oh.setStatus(oldStatus)
end

local SpyHook = ClosureSpy.Hook
local function spyCallingFunction()
	if not guardSelectedCall("Spy Calling Function") then
		return
	end

	if TabSelector.SelectTab("ClosureSpy") then
		if type(selected.func) ~= "function" then
			return MessageBox.Show("Cannot hook", "No Lua closure was captured for this call", MessageType.OK)
		end

		local selectedClosure = Closure.new(selected.func)
		local result, hookError = SpyHook.new(selectedClosure)

		if result == false then
			MessageBox.Show("Already hooked", "You are already spying " .. selectedClosure.Name)
		elseif result == nil then
			MessageBox.Show("Cannot hook", hookError or ('Unable to hook "%s"'):format(selectedClosure.Name))
		end
	end
end

local function repeatSelectedCall()
	if not guardSelectedCall("Repeat Call") then
		return
	end

	local remoteModel = selected.remoteLog.Remote
	local remoteInstance = remoteModel.Instance
	local method = getRemoteMethod(remoteInstance, selected.callInfo)
	local args = selected.args or {}
	local argCount = getArgCount(args)
	local callableRan, callable = pcall(function()
		return remoteInstance[method]
	end)

	if not method or not callableRan or type(callable) ~= "function" then
		return TextViewer.Show("Repeat Call Failed", "No callable method was available for this remote.")
	elseif remoteModel.Blocked then
		return MessageBox.Show(
			"Remote is blocked",
			"Unblock this remote before replaying it; blocked calls intentionally do not reach the server.",
			MessageType.OK
		)
	end

	MessageBox.Show(
		"Replay captured call?",
		("Run %s on %s with %d captured argument%s? This can change game state."):format(
			method,
			remoteInstance.Name,
			argCount,
			argCount == 1 and "" or "s"
		),
		MessageType.YesNo,
		function()
			local oldStatus = oh.getStatus()
			oh.setStatus("Replaying " .. remoteInstance.Name .. " ...")

			task.spawn(function()
				local results = table.pack(pcall(callable, remoteInstance, unpackValues(args, 1, argCount)))
				oh.setStatus(oldStatus)

				if not results[1] then
					TextViewer.Show("Replay Call Failed", tostring(results[2]))
				elseif method == "InvokeServer" or method == "Invoke" then
					local returned = { n = math.max(0, results.n - 1) }

					for index = 2, results.n do
						returned[index - 1] = results[index]
					end

					TextViewer.Show("Replay Returns", describePackedValues("REPLAY RETURN VALUES", returned))
				end
			end)
		end
	)
end

local function toggleHexView()
	if not guardSelectedCall("Toggle String Hex View") or not selected.args then
		return
	end

	selected.callPodButton.hexViewEnabled = not selected.callPodButton.hexViewEnabled
	if not selected.callPodButton.oldStrings then
		selected.callPodButton.oldStrings = {}
	end

	local maxHexBytes = getMaxHexBytes()
	local argCount = getArgCount(selected.args)

	for idx = 1, argCount do
		local arg = selected.args[idx]

		if type(arg) == "string" then
			local argRow = selected.callPodButton.Instance.Contents:FindFirstChild(tostring(idx))
			local textObject = argRow and argRow.Label

			if textObject then
				if selected.callPodButton.hexViewEnabled then
					selected.callPodButton.oldStrings[idx] = arg
					local parts = {}
					local bytes = math.min(#arg, maxHexBytes)

					for i = 1, bytes do
						parts[i] = string.format("%02X", arg:byte(i, i))
					end

					local hexString = table.concat(parts, " ")

					if #arg > bytes then
						hexString = hexString .. (" ... (%d/%d bytes shown)"):format(bytes, #arg)
					end

					textObject.Text = hexString
				else
					textObject.Text = argumentSummary(selected.callPodButton.oldStrings[idx])
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
inspectFunctionContext:SetCallback(inspectCallingFunction)
inspectScriptContext:SetCallback(inspectCallingScript)
callingScriptContext:SetCallback(copyCallingScriptPath)
spyClosureContext:SetCallback(spyCallingFunction)
repeatCallContext:SetCallback(repeatSelectedCall)
viewAsHexContext:SetCallback(toggleHexView)

callInspector = ActionPanel.Install(LogsButtons, RemoteLogs.Results, {
	Columns = 5,
	Actions = {
		{ Name = "ReplayCode", Label = "Code", Icon = icons.script, Callback = generateReplayScript },
		{ Name = "CopyCode", Label = "Copy Code", Icon = icons.copy, Callback = copyReplayScript },
		{ Name = "Arguments", Label = "Arguments", Icon = icons.arguments, Callback = showArguments },
		{ Name = "Returns", Label = "Returns", Icon = icons.results, Callback = showReturns },
		{ Name = "CallStack", Label = "Stack", Icon = icons.stack, Callback = showCallStack },
		{ Name = "Function", Label = "Function", Icon = icons.spy, Callback = inspectCallingFunction },
		{ Name = "ScriptSource", Label = "Script", Icon = icons.source, Callback = inspectCallingScript },
		{ Name = "ScriptPath", Label = "Copy Path", Icon = icons.copy, Callback = copyCallingScriptPath },
		{ Name = "SpyFunction", Label = "Spy Caller", Icon = icons.spy, Callback = spyCallingFunction },
		{ Name = "Repeat", Label = "Replay", Icon = icons.repeatCall, Callback = repeatSelectedCall },
		{ Name = "Hex", Label = "Hex", Icon = icons.hex, Callback = toggleHexView },
	},
})
updateCallInspector()

removeConditionContext:SetCallback(function()
	selected.condition:Remove()
	selected.condition = nil
end)

removeConditionContextSelected:SetCallback(function()
	for _i, condition in pairs(selected.conditions) do
		condition:Remove()
	end

	selected.conditions = {}
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
end)

for remoteInstance, remote in pairs(currentRemotes) do
	if typeof(remoteInstance) == "Instance" and not removed[remoteInstance] and not currentLogs[remoteInstance] then
		local log = Log.new(remote)
		log.Button.Instance.Visible = remotesViewing[remoteInstance.ClassName]
		updateCountDisplay(log)
	end
end

remoteList:QueueRecalculate()

Methods.ConnectEvent(function(remoteInstance, callInfo)
	if not removed[remoteInstance] then
		local remote = currentRemotes[remoteInstance]
		local log = currentLogs[remoteInstance] or Log.new(remote)

		log:IncrementCalls(callInfo)
	end
end)

return RemoteSpy
