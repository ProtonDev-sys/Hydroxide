local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local ClosureSpy = {}
local Methods = import("modules/ClosureSpy")

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
local LogsResults = ClosureLogs.Results.Clip.Content

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
}

local constants = {
	fadeLength = TweenInfo.new(0.15),
	textWidth = Vector2.new(1337420, 20),
	normalColor = Color3.new(1, 1, 1),
	blockedColor = Color3.fromRGB(170, 0, 0),
	ignoredColor = Color3.fromRGB(100, 100, 100),
}

oh.Settings = oh.Settings or {}
if type(oh.Settings.MaxRenderedLogs) ~= "number" and type(oh.Settings.maxRenderedLogs) ~= "number" then
	oh.Settings.MaxRenderedLogs = 100
end

local newClosureCondition = Prompt.new(NewClosureCondition)
local conditionStatus = Dropdown.new(NewConditionContent.Status)
local conditionType = Dropdown.new(NewConditionContent.Type)
local conditionValueType = Dropdown.new(NewConditionContent.ValueType)

local closureList = List.new(ListResults, true)
local hookLogs = List.new(LogsResults)
local closureConditions = List.new(ConditionsResults, true)

local currentLogs = {}
local removed = {}

local selected = {
	logs = {},
	conditions = {},
}

local conditionContext = ContextMenuButton.new("rbxassetid://4891633802", "Call Conditions")
local clearContext = ContextMenuButton.new("rbxassetid://4892169181", "Clear Calls")
local ignoreContext = ContextMenuButton.new("rbxassetid://4842578510", "Ignore Calls")
local blockContext = ContextMenuButton.new("rbxassetid://4891641806", "Block Calls")
local removeContext = ContextMenuButton.new("rbxassetid://4702831188", "Remove Log")

local callStackContext = ContextMenuButton.new("rbxassetid://4800244808", "View Call Stack")
local inspectFunctionContext = ContextMenuButton.new("rbxassetid://4666593447", "Inspect Calling Function")
local inspectScriptContext = ContextMenuButton.new("rbxassetid://4800244808", "Inspect Calling Script")
local callingScriptContext = ContextMenuButton.new("rbxassetid://4800244808", "Get Calling Script")
local spyClosureContext = ContextMenuButton.new("rbxassetid://4666593447", "Spy Calling Function")

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
	callStackContext,
	inspectFunctionContext,
	inspectScriptContext,
	callingScriptContext,
	spyClosureContext,
})
local closureConditionMenu = ContextMenu.new({ removeConditionContext })
local closureConditionMenuSelected = ContextMenu.new({ removeConditionContextSelected })

local queuedLogRenders = {}
local queuedCountUpdates = {}
local renderedCallLog
local renderedCallButtons = {}

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
	end

	selected.args = nil
	selected.callingScript = nil
	selected.func = nil
	selected.callInfo = nil
	selected.callPodButton = nil
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

local function describeFunction(func)
	if type(func) ~= "function" then
		return "No caller function was captured for this call."
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
	lines[#lines + 1] = "Path: " .. getInstancePath(scriptInstance)

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

local function describeCallStack(call)
	if not call then
		return "No call is selected."
	end

	local lines = {}
	lines[#lines + 1] = "Method: " .. tostring(call.method or "closure")
	lines[#lines + 1] = "Timestamp: " .. tostring(call.timestamp or "unknown")
	lines[#lines + 1] = "Off Thread: " .. tostring(call.offThread == true)
	lines[#lines + 1] = "Calling Script: "
		.. ((typeof(call.script) == "Instance" and getInstancePath(call.script)) or "unknown")
	lines[#lines + 1] = "Function: " .. argumentSummary(call.func)
	lines[#lines + 1] = ""

	if type(call.chain) == "table" and #call.chain > 0 then
		lines[#lines + 1] = "Call Chain:"

		for index, frame in ipairs(call.chain) do
			if type(frame) == "table" then
				local name = frame.name or frame.Name or frame.closureName or frame.ClosureName or "<anonymous>"
				local scriptInstance = frame.script or frame.Script
				local scriptPath = typeof(scriptInstance) == "Instance"
						and (" [" .. getInstancePath(scriptInstance) .. "]")
					or ""
				lines[#lines + 1] = ("%02d  %s%s"):format(index, tostring(name), scriptPath)
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

	lines[#lines + 1] = "Stack:"

	for index, frame in ipairs(stack) do
		if type(frame) == "table" then
			local name = frame.name or frame.Name or "<anonymous>"
			local source = frame.short_src or frame.shortSource or frame.source or frame.Source or "unknown"
			local line = frame.currentline or frame.line or frame.Line or "?"
			local scriptInstance = frame.script or frame.Script
			local scriptPath = typeof(scriptInstance) == "Instance" and (" [" .. getInstancePath(scriptInstance) .. "]")
				or ""
			lines[#lines + 1] = ("%02d  %s  %s:%s%s"):format(
				index,
				tostring(name),
				tostring(source),
				tostring(line),
				scriptPath
			)
		else
			lines[#lines + 1] = ("%02d  %s"):format(index, tostring(frame))
		end
	end

	return table.concat(lines, "\n")
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
function Condition.new(closure, status, index, value, type)
	local condition = {}
	local instance = Assets.ConditionPod:Clone()
	local content = instance.Content
	local identifiers = instance.Identifiers
	local button = ListButton.new(instance, closureConditions)
	local check = CheckBox.new(content.Toggle)
	local valueType = type or typeof(value)
	local typeIcons = oh.Constants.Types
	local branch = (status == "Ignore" and closure.IgnoredArgs[index]) or closure.BlockedArgs[index]

	condition.Branch = branch
	condition.Status = status
	condition.Index = index
	condition.Value = value
	condition.Type = type
	condition.Closure = closure
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
	local closure = condition.Closure
	local ignoredArgs = closure.IgnoredArgs[index]
	local blockedArgs = closure.BlockedArgs[index]
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

local function createConditions(hook)
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
	end

	for index, arg in pairs(hook.BlockedArgs) do
		for type in pairs(arg.types) do
			Condition.new(hook, "Block", index, nil, type)
		end

		for value in pairs(arg.values) do
			Condition.new(hook, "Block", index, value)
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

	listButton:SetSelectedCallback(function()
		if not table.find(selected.logs, log) then
			table.insert(selected.logs, log)
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

	button:SetRightCallback(function()
		selected.args = call.args
		selected.callingScript = call.script
		selected.func = call.func
		selected.callInfo = call
		selected.callPodButton = button
	end)

	button.Instance.Size = button.Instance.Size + UDim2.new(0, 0, 0, height)

	return button
end

renderLatestCalls = function(log, rebuild)
	hookLogs:BeginBatch()

	if rebuild or renderedCallLog ~= log then
		resetRenderedCalls()
		renderedCallLog = log
	end

	local logs = log.Hook.Logs
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
			button.Instance.Visible = selected.hookLog == log
		end
	end

	hookLogs:EndBatch()
	hookLogs:QueueRecalculate()
end

queueLogRender = function(log)
	if queuedLogRenders[log] then
		return
	end

	queuedLogRenders[log] = true
	task.defer(function()
		queuedLogRenders[log] = nil

		if selected.hookLog == log and ClosureLogs.Visible then
			renderLatestCalls(log)
		end
	end)
end

local function updateCountDisplay(log)
	local logInstance = log.Button.Instance
	local calls = log.Hook.Calls

	logInstance.Calls.Text = (calls < 10000 and calls) or "..."
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
	local removedHook, removeError = hook:Remove()

	if not removedHook then
		MessageBox.Show("Cannot unhook", removeError or "Unable to restore the original closure", MessageType.OK)
		return false
	end

	if selected.hookLog == log then
		resetRenderedCalls()
		selected.hookLog = nil
	end

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

LogsButtons.Block.MouseButton1Click:Connect(function()
	local selectedLog = selected.hookLog
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

LogsButtons.Clear.MouseButton1Click:Connect(function()
	selected.hookLog:Clear()
end)

LogsButtons.Conditions.MouseButton1Click:Connect(function()
	selected.conditionLog = selected.hookLog

	createConditions(selected.conditionLog.Hook)
end)

ConditionsBack.MouseButton1Click:Connect(function()
	ClosureConditions.Visible = false

	if selected.hookLog then
		ClosureLogs.Visible = true
	else
		ClosureList.Visible = true
	end
end)

ConditionsButtons.New.MouseButton1Click:Connect(function()
	newClosureCondition:Show()
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

	local selectedHook = selected.conditionLog.Hook
	local argIndex = tonumber(NewConditionIndex.Value.Input.Text)
	local byType = valueType == "Type"

	if status == "Block" then
		selectedHook:BlockArg(argIndex, value, byType)
	else
		selectedHook:IgnoreArg(argIndex, value, byType)
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
	for _i, log in pairs(selected.logs) do
		local hook = log.Hook

		if not hook.Ignored then
			hook:Ignore()
		end

		if log.Blocked then
			log:PlayBlock()
		elseif hook.Ignored then
			log:PlayIgnore()
		end
	end

	selected.logs = {}
end)

unignoreContextSelected:SetCallback(function()
	for _i, log in pairs(selected.logs) do
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

	selected.logs = {}
end)

blockContextSelected:SetCallback(function()
	for _i, log in pairs(selected.logs) do
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

	selected.logs = {}
end)

unblockContextSelected:SetCallback(function()
	for _i, log in pairs(selected.logs) do
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

	closureList:Recalculate()
	selected.logs = {}
end)

callStackContext:SetCallback(function()
	if not guardSelectedCall("Closure Call Stack") then
		return
	end

	TextViewer.Show("Closure Call Stack", describeCallStack(selected.callInfo))
end)

inspectFunctionContext:SetCallback(function()
	if not guardSelectedCall("Calling Function") then
		return
	end

	local func = selected.func or (selected.hookLog and selected.hookLog.Hook and selected.hookLog.Hook.Target)
	TextViewer.Show("Calling Function", describeFunction(func))
end)

inspectScriptContext:SetCallback(function()
	if not guardSelectedCall("Calling Script") then
		return
	end

	TextViewer.Show("Calling Script", describeScript(selected.callingScript))
end)

callingScriptContext:SetCallback(function()
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
end)

local SpyHook = Methods.Hook
spyClosureContext:SetCallback(function()
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
end)

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
	withExecutorIdentity(function()
		if not removed[hook] then
			local log = currentLogs[hook] or Log.new(hook)
			log:IncrementCalls(call)
		end
	end)
end)

return ClosureSpy
