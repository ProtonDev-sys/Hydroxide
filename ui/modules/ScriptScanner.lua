local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local ScriptScanner = {}
local Methods = import("modules/ScriptScanner")

if not hasMethods(Methods.RequiredMethods) then
	return ScriptScanner
end

local List, ListButton = import("ui/controls/List")
local ContextMenu, ContextMenuButton = import("ui/controls/ContextMenu")
local TextViewer = import("ui/controls/TextViewer")
local FunctionInspector = import("ui/controls/FunctionInspector")

local Page = import("rbxassetid://11389137937").Base.Body.Pages.ScriptScanner
local Assets = import("rbxassetid://5042114982").ScriptScanner

local ScriptList = Page.List
local ScriptInfo = Page.Info

local ListQuery = ScriptList.Query
local ListSearch = ListQuery.Search
local ListRefresh = ListQuery.Refresh
local ListResults = ScriptList.Results.Clip.Content

local InfoScript = ScriptInfo.ScriptObject
local InfoBack = ScriptInfo.Back
local InfoOptions = ScriptInfo.Options.Clip.Content
local InfoSections = ScriptInfo.Sections

local InfoSource = InfoSections.Source
local InfoEnvironment = InfoSections.Environment
local InfoProtos = InfoSections.Protos
local InfoConstants = InfoSections.Constants

local EnvironmentQuery = InfoEnvironment.Query
local EnvironmentResultsClip = InfoEnvironment.Results.Clip
local EnvironmentResultsStatus = EnvironmentResultsClip.ResultStatus
local EnvironmentResults = EnvironmentResultsClip.Content

local ConstantsQuery = InfoConstants.Query
local ConstantsResultsClip = InfoConstants.Results.Clip
local ConstantsResultsStatus = ConstantsResultsClip.ResultStatus
local ConstantsResults = ConstantsResultsClip.Content

local ProtosQuery = InfoProtos.Query
local ProtosResultsClip = InfoProtos.Results.Clip
local ProtosResultsStatus = ProtosResultsClip.ResultStatus
local ProtosResults = ProtosResultsClip.Content

local scriptList = List.new(ListResults)
local environmentList = List.new(EnvironmentResults)
local protosList = List.new(ProtosResults)
local constantsList = List.new(ConstantsResults)

local scriptLogs = {}
local selected = {}
local queueSummaryLoad
local showSectionByName
local renderSelectedSection
local ensureMetadata
local functionInspectionGeneration = 0
local icons = {
	LocalScript = "rbxassetid://4800244808",
}

local constants = {
	fadeLength = TweenInfo.new(0.15),
	textWidth = Vector2.new(133742069, 20),
	maxPreviewRows = 500,
}

local pathContext = ContextMenuButton.new("rbxassetid://4891705738", "Get Script Path")
local sourceContext = ContextMenuButton.new("rbxassetid://4800244808", "View Script Source")
local protoSourceContext = ContextMenuButton.new("rbxassetid://4800244808", "Inspect Function")
local constantSourceContext = ContextMenuButton.new("rbxassetid://4800244808", "Inspect Constant")
local environmentSourceContext = ContextMenuButton.new("rbxassetid://4800244808", "Inspect Environment Value")

scriptList:BindContextMenu(ContextMenu.new({ pathContext, sourceContext }))
protosList:BindContextMenu(ContextMenu.new({ protoSourceContext }))
constantsList:BindContextMenu(ContextMenu.new({ constantSourceContext }))
environmentList:BindContextMenu(ContextMenu.new({ environmentSourceContext }))

local function runPrivileged(callback)
	if type(withExecutorIdentity) == "function" then
		withExecutorIdentity(callback)
	else
		callback()
	end
end

local function safeSummary(value)
	if type(summarizeValue) == "function" then
		local ran, summary = pcall(summarizeValue, value, 240)

		if ran and type(summary) == "string" then
			return summary
		end
	end

	if type(argumentSummary) == "function" then
		local ran, summary = pcall(argumentSummary, value)

		if ran and type(summary) == "string" then
			return summary
		end
	end

	if type(toString) == "function" then
		local ran, summary = pcall(toString, value)

		if ran and type(summary) == "string" then
			return summary
		end
	end

	local ran, summary = pcall(tostring, value)
	return ran and summary or "<unprintable>"
end

local function safeTypeof(value)
	if type(typeof) == "function" then
		local ran, valueType = pcall(typeof, value)
		return ran and valueType or type(value)
	end

	return type(value)
end

local function metricText(loaded, values, errorMessage)
	if not loaded then
		return "..."
	elseif errorMessage then
		return "!"
	end

	return #(values or {})
end

local function showSource(title, source, errorMessage)
	if showSectionByName then
		showSectionByName("Source")
	end

	TextViewer.Show(title, source or ("Source unavailable:\n" .. tostring(errorMessage or "unknown error")), {
		Parent = InfoSource,
	})
end

local function safeInstancePath(instance)
	if safeTypeof(instance) ~= "Instance" then
		return nil
	end

	local ran, path = pcall(getInstancePath, instance)
	return ran and path or nil
end

local function showSourceText(title, text)
	if showSectionByName then
		showSectionByName("Source")
	end

	TextViewer.Show(title, tostring(text or ""), {
		Parent = InfoSource,
	})
end

local function getSearchText(query)
	if query:IsA("TextBox") then
		return query.Text:lower()
	end

	local search = query:FindFirstChild("Search", true)
	if search and search:IsA("TextBox") then
		return search.Text:lower()
	end

	for _, descendant in ipairs(query:GetDescendants()) do
		if descendant:IsA("TextBox") then
			return descendant.Text:lower()
		end
	end

	return ""
end

local function bindQuery(query, callback)
	local boxes = {}

	if query:IsA("TextBox") then
		boxes[#boxes + 1] = query
	end

	for _, descendant in ipairs(query:GetDescendants()) do
		if descendant:IsA("TextBox") then
			boxes[#boxes + 1] = descendant
		end
	end

	for _, box in ipairs(boxes) do
		box.FocusLost:Connect(function(returned)
			if returned then
				callback()
			end
		end)
	end
end

local function textMatches(query, ...)
	if query == "" then
		return true
	end

	for index = 1, select("#", ...) do
		local value = tostring(select(index, ...) or ""):lower()

		if value:find(query, 1, true) then
			return true
		end
	end

	return false
end

local function makeEntries(values, limit, matches)
	local entries = {}
	local total = 0
	local matched = 0

	if type(values) ~= "table" then
		return entries, total, matched
	end

	for key, value in next, values do
		total = total + 1
		local entryMatches = not matches or matches(key, value)

		if entryMatches then
			matched = matched + 1
		end

		if entryMatches and matched <= limit then
			entries[#entries + 1] = {
				Key = key,
				Value = value,
				Sort = type(key) == "number" and ("0:%020.6f"):format(key) or "1:" .. safeSummary(key),
			}
		end
	end

	table.sort(entries, function(left, right)
		return left.Sort < right.Sort
	end)
	return entries, total, matched
end

local function configureRow(information, index, value, labelText, valueType)
	local indexText = tostring(index)
	local indexWidth = TextService:GetTextSize(indexText, 18, "SourceSans", constants.textWidth).X + 8
	valueType = valueType or safeTypeof(value)

	information.Index.Text = indexText
	information.Label.Text = tostring(labelText or safeSummary(value))
	information.Label.TextColor3 = oh.Constants.Syntax[valueType] or oh.Constants.Syntax["userdata"]
	information.Icon.Image = oh.Constants.Types[valueType] or oh.Constants.Types["userdata"]

	information.Index.Size = UDim2.new(0, indexWidth, 0, 20)
	information.Label.Size = UDim2.new(1, -(indexWidth + 20), 1, 0)
	information.Icon.Position = UDim2.new(0, indexWidth, 0, 2)
	information.Label.Position = UDim2.new(0, indexWidth + 20, 0, 0)
end

local function describeFunctionName(func)
	local ran, info = pcall(getInfo, func, "n")
	local name = ran and type(info) == "table" and info.name or ""

	if name == "" or name == nil then
		return "Unnamed function", "unnamed_function"
	end

	return name, "function"
end

local function viewFunctionSource(func)
	local log = selected.scriptLog

	if not log or type(func) ~= "function" then
		return showSource("Function Source", nil, "No function is selected")
	end

	functionInspectionGeneration = functionInspectionGeneration + 1
	local generation = functionInspectionGeneration
	showSource("Function Inspector", "Inspecting function metadata, environment, constants, protos, and source ...")

	task.spawn(function()
		local description
		local inspected, inspectError = pcall(function()
			runPrivileged(function()
				description = FunctionInspector.DescribeFunction(func, {
					Summarize = safeSummary,
					GetPath = safeInstancePath,
					Decompile = function(target)
						return log.LocalScript:Decompile(target)
					end,
				})
			end)
		end)

		if not inspected then
			description = "Function inspection failed:\n" .. tostring(inspectError)
		end

		if generation == functionInspectionGeneration and selected.scriptLog == log then
			showSource("Function Inspector", description or "No function information was returned.")
		end
	end)
end

local function viewValue(title, index, value)
	if type(value) == "function" then
		return viewFunctionSource(value)
	end

	local valueType = safeTypeof(value)
	local lines = {
		tostring(title or "Captured Value"):upper(),
		"Index: " .. safeSummary(index),
		"Type: " .. tostring(valueType),
		"Value: " .. safeSummary(value),
	}

	if valueType == "Instance" then
		lines[#lines + 1] = "Path: " .. tostring(safeInstancePath(value) or "unavailable")
	elseif type(value) == "table" then
		lines[#lines + 1] = ""
		lines[#lines + 1] = "First-level entries:"
		local emitted = 0
		local key

		while emitted < 64 do
			local advanced, nextKey, nextValue = pcall(next, value, key)

			if not advanced or nextKey == nil then
				if not advanced then
					lines[#lines + 1] = "  <enumeration failed: " .. tostring(nextKey) .. ">"
				end

				break
			end

			key = nextKey
			emitted = emitted + 1
			lines[#lines + 1] = ("  [%s] = %s"):format(safeSummary(nextKey), safeSummary(nextValue))
		end

		if emitted == 64 then
			lines[#lines + 1] = "  ... preview limited to 64 entries ..."
		end
	end

	showSourceText(title or "Captured Value", table.concat(lines, "\n"))
end

local function createEnvironment(index, value)
	local instance = Assets.ConstantPod:Clone()
	local button = ListButton.new(instance, environmentList)

	configureRow(instance.Information, index, value)

	button:SetCallback(function()
		selected.environmentValue = value
		selected.environmentIndex = index
		viewValue("Environment Value", index, value)
	end)

	button:SetRightCallback(function()
		selected.environmentValue = value
		selected.environmentIndex = index
	end)

	return true
end

local function createProto(index, value)
	local functionName, syntaxKey = describeFunctionName(value)

	local instance = Assets.ProtoPod:Clone()
	local information = instance.Information
	local button = ListButton.new(instance, protosList)

	configureRow(information, index, value, functionName, syntaxKey)

	button:SetCallback(function()
		selected.protoFunction = value
		viewFunctionSource(value)
	end)

	button:SetRightCallback(function()
		selected.protoFunction = value
	end)

	return true
end

local function createConstant(index, value)
	local label = safeSummary(value)
	local syntaxKey = safeTypeof(value)

	if type(value) == "function" then
		label, syntaxKey = describeFunctionName(value)
	end

	local instance = Assets.ConstantPod:Clone()
	local button = ListButton.new(instance, constantsList)

	configureRow(instance.Information, index, value, label, syntaxKey)

	button:SetCallback(function()
		selected.constantValue = value
		selected.constantIndex = index
		viewValue("Constant", index, value)
	end)

	button:SetRightCallback(function()
		selected.constantValue = value
		selected.constantIndex = index
	end)

	return true
end

local function environmentMatches(index, value, query)
	return textMatches(query, index, safeTypeof(value), safeSummary(value))
end

local function protoMatches(index, value, query)
	local functionName = describeFunctionName(value)
	return textMatches(query, index, functionName, safeSummary(value))
end

local function constantMatches(index, value, query)
	local label = safeSummary(value)
	local syntaxKey = safeTypeof(value)

	if type(value) == "function" then
		label, syntaxKey = describeFunctionName(value)
	end

	return textMatches(query, index, syntaxKey, label)
end

local function renderTable(list, statusLabel, values, errorMessage, query, matches, createRow)
	list:Clear()
	statusLabel.Text = ""

	if not values then
		statusLabel.Text = tostring(errorMessage or "Unavailable")
		return
	end

	local entries, total, matched = makeEntries(values, constants.maxPreviewRows, function(index, value)
		return matches(index, value, query)
	end)
	local shown = 0

	list:BeginBatch()

	for _, entry in ipairs(entries) do
		if createRow(entry.Key, entry.Value) then
			shown = shown + 1
		end
	end

	list:EndBatch()

	if matched > #entries then
		statusLabel.Text = ("Showing %d of %d matches (%d total entries)."):format(shown, matched, total)
	elseif matched == 0 then
		statusLabel.Text = "No entries matched the current filter."
	end
end

renderSelectedSection = function(sectionName)
	local log = selected.scriptLog

	if not log then
		return
	end

	if not sectionName or sectionName == "Protos" then
		renderTable(
			protosList,
			ProtosResultsStatus,
			log.Protos,
			log.ProtosError or (not log.MetadataLoaded and "Loading protos ..." or nil),
			getSearchText(ProtosQuery),
			protoMatches,
			createProto
		)
	end

	if not sectionName or sectionName == "Constants" then
		renderTable(
			constantsList,
			ConstantsResultsStatus,
			log.Constants,
			log.ConstantsError or (not log.MetadataLoaded and "Loading constants ..." or nil),
			getSearchText(ConstantsQuery),
			constantMatches,
			createConstant
		)
	end

	if not sectionName or sectionName == "Environment" then
		renderTable(
			environmentList,
			EnvironmentResultsStatus,
			log.Environment,
			log.EnvironmentError or (not log.DetailsLoaded and "Loading environment ..." or nil),
			getSearchText(EnvironmentQuery),
			environmentMatches,
			createEnvironment
		)
	end
end

local function updateSummaryCounts(log)
	local button = log.Button and log.Button.Instance

	if not (button and button.Parent) then
		return
	end

	button.Protos.Text = log.Protos and #log.Protos or "!"
	button.Constants.Text = log.Constants and #log.Constants or "!"
end

ensureMetadata = function(log)
	while log.MetadataLoading do
		task.wait()
	end

	if log.MetadataLoaded then
		return
	end

	log.MetadataLoading = true
	local loaded, loadError = pcall(function()
		runPrivileged(function()
			log.Protos, log.ProtosError = log.LocalScript:LoadProtos()
			log.Constants, log.ConstantsError = log.LocalScript:LoadConstants()
		end)
	end)

	if not loaded then
		local message = "Metadata inspection failed: " .. tostring(loadError)
		log.ProtosError = log.ProtosError or message
		log.ConstantsError = log.ConstantsError or message
	end

	log.MetadataLoading = false
	log.MetadataLoaded = true
	updateSummaryCounts(log)
end

-- Log Object
local Log = {}

function Log.new(localScript)
	local log = {}
	local scriptInstance = localScript.Instance
	local button = Assets.ScriptLog:Clone()
	local listButton = ListButton.new(button, scriptList)
	local scriptName = scriptInstance.Name

	button.Name = scriptName
	button:FindFirstChild("Name").Text = scriptName
	button.Protos.Text = metricText(localScript.LoadedProtos, localScript.Protos, localScript.ProtosError)
	button.Constants.Text = metricText(localScript.LoadedConstants, localScript.Constants, localScript.ConstantsError)

	local function openLog()
		selected.scriptLog = log
		selected.logContext = log
		selected.protoFunction = nil
		selected.constantValue = nil
		selected.constantIndex = nil
		selected.environmentValue = nil
		selected.environmentIndex = nil
		functionInspectionGeneration = functionInspectionGeneration + 1

		ScriptList.Visible = false
		ScriptInfo.Visible = true

		if showSectionByName then
			showSectionByName("Source")
		end

		local nameLength = TextService:GetTextSize(scriptName, 18, "SourceSans", constants.textWidth).X + 20

		InfoScript.Icon.Image = icons.LocalScript
		InfoScript.Label.Text = scriptName
		InfoScript.Label.Size = UDim2.new(0, nameLength, 0, 20)
		InfoScript.Position = UDim2.new(1, -nameLength, 0, 0)

		if log.Source or log.SourceError then
			showSource(scriptName .. " Source", log.Source, log.SourceError)
		else
			showSourceText("Loading Source", "Decompiling " .. scriptName .. " ...")
		end
		renderSelectedSection()

		if log.DetailsLoaded or log.DetailsLoading then
			return
		end

		log.DetailsLoading = true

		task.spawn(function()
			local metadataLoaded, metadataError = pcall(ensureMetadata, log)

			if not metadataLoaded then
				local message = "Metadata inspection failed: " .. tostring(metadataError)
				log.ProtosError = log.ProtosError or message
				log.ConstantsError = log.ConstantsError or message
				log.MetadataLoading = false
				log.MetadataLoaded = true
			end

			local loaded, loadError = pcall(function()
				runPrivileged(function()
					log.Environment, log.EnvironmentError = localScript:LoadEnvironment()
					log.Source, log.SourceError = localScript:Decompile()
				end)
			end)

			if not loaded then
				local message = "Script inspection failed: " .. tostring(loadError)
				log.EnvironmentError = log.EnvironmentError or message
				log.SourceError = log.SourceError or message
			end

			log.DetailsLoading = false
			log.DetailsLoaded = true
			updateSummaryCounts(log)

			if selected.scriptLog == log then
				showSource(scriptName .. " Source", log.Source, log.SourceError)
				renderSelectedSection()
			end
		end)
	end

	listButton:SetCallback(openLog)

	listButton:SetRightCallback(function()
		selected.logContext = log
	end)

	scriptLogs[scriptInstance] = log

	log.LocalScript = localScript
	log.Button = listButton
	log.Open = openLog

	if queueSummaryLoad then
		queueSummaryLoad(log)
	end

	return log
end

do
	local summaryQueue = {}
	local summaryRunning = false
	local summaryIndex = 1
	local activeWorkers = 0
	local workerLimit = 3

	local function processSummaryQueue()
		while true do
			local log = summaryQueue[summaryIndex]

			if not log then
				break
			end

			summaryIndex = summaryIndex + 1

			if not log.SummaryLoaded and log.Button and log.Button.Instance and log.Button.Instance.Parent then
				local loaded, loadError = pcall(ensureMetadata, log)
				log.SummaryLoaded = true

				if not loaded then
					local message = "Metadata worker failed: " .. tostring(loadError)
					log.ProtosError = log.ProtosError or message
					log.ConstantsError = log.ConstantsError or message
					log.MetadataLoading = false
					log.MetadataLoaded = true
					updateSummaryCounts(log)
				end
			end

			task.wait()
		end

		activeWorkers = activeWorkers - 1

		if activeWorkers == 0 then
			table.clear(summaryQueue)
			summaryIndex = 1
			summaryRunning = false
		end
	end

	queueSummaryLoad = function(log)
		summaryQueue[#summaryQueue + 1] = log

		if not summaryRunning then
			summaryRunning = true
			activeWorkers = workerLimit

			for _ = 1, workerLimit do
				task.defer(processSummaryQueue)
			end
		end
	end
end

-- UI Functionality

local function addScripts(query)
	scriptList:Clear()
	protosList:Clear()
	constantsList:Clear()
	environmentList:Clear()
	scriptLogs = {}
	selected.scriptLog = nil
	selected.logContext = nil
	functionInspectionGeneration = functionInspectionGeneration + 1
	scriptList:BeginBatch()

	for _instance, localScript in pairs(Methods.Scan(query)) do
		Log.new(localScript)
	end

	scriptList:EndBatch()
end

ListSearch.FocusLost:Connect(function(returned)
	if returned then
		addScripts(ListSearch.Text)
		ListSearch.Text = ""
	end
end)

ListRefresh.MouseButton1Click:Connect(function()
	addScripts()
end)

addScripts()

pathContext:SetCallback(function()
	local log = selected.logContext

	if not log then
		return
	end

	local path = safeInstancePath(log.LocalScript.Instance)
	local copied = path and pcall(setClipboard, path)
	oh.setStatus(copied and "Script path copied" or "Script path unavailable")
end)

sourceContext:SetCallback(function()
	local log = selected.logContext

	if log and log.Open then
		log.Open()
	end
end)

protoSourceContext:SetCallback(function()
	viewFunctionSource(selected.protoFunction)
end)

constantSourceContext:SetCallback(function()
	viewValue("Constant", selected.constantIndex, selected.constantValue)
end)

environmentSourceContext:SetCallback(function()
	viewValue("Environment Value", selected.environmentIndex, selected.environmentValue)
end)

InfoBack.MouseButton1Click:Connect(function()
	ScriptInfo.Visible = false
	ScriptList.Visible = true
end)

bindQuery(EnvironmentQuery, function()
	if selected.scriptLog then
		renderSelectedSection("Environment")
	end
end)

bindQuery(ProtosQuery, function()
	if selected.scriptLog then
		renderSelectedSection("Protos")
	end
end)

bindQuery(ConstantsQuery, function()
	if selected.scriptLog then
		renderSelectedSection("Constants")
	end
end)

local selectedSection
local selectedSectionButton
local animationCache = {}

showSectionByName = function(sectionName)
	local section = InfoSections:FindFirstChild(sectionName)
	local sectionButton = InfoOptions:FindFirstChild(sectionName)

	if not section or not sectionButton then
		return
	end

	if selectedSection ~= section then
		if animationCache[selectedSectionButton] then
			animationCache[selectedSectionButton].leave:Play()
		end

		selectedSection = section
		selectedSectionButton = sectionButton

		if animationCache[selectedSectionButton] then
			animationCache[selectedSectionButton].enter:Play()
		end
	end

	for _, candidate in ipairs(InfoSections:GetChildren()) do
		if candidate:IsA("GuiObject") then
			candidate.Visible = candidate == section
		end
	end
end

for _i, sectionButton in pairs(InfoOptions:GetChildren()) do
	if sectionButton:IsA("TextButton") then
		local label = sectionButton.Label
		local enterAnimation = TweenService:Create(label, constants.fadeLength, { TextTransparency = 0 })
		local leaveAnimation = TweenService:Create(label, constants.fadeLength, { TextTransparency = 0.2 })

		sectionButton.MouseButton1Click:Connect(function()
			showSectionByName(sectionButton.Name)
		end)

		sectionButton.MouseEnter:Connect(function()
			if selectedSectionButton ~= sectionButton then
				enterAnimation:Play()
			end
		end)

		sectionButton.MouseLeave:Connect(function()
			if selectedSectionButton ~= sectionButton then
				leaveAnimation:Play()
			end
		end)

		animationCache[sectionButton] = {
			enter = enterAnimation,
			leave = leaveAnimation,
		}
	end
end

showSectionByName("Source")

return ScriptScanner
