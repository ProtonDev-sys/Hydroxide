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
local LocalScriptModel = import("objects/LocalScript")

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
local detailLoadGeneration = 0
local detailRenderGeneration = 0
local scanGeneration = 0
local scanInitialized = false
local scanLoading = false
local pendingScanQuery
local resetSummaryQueue
local sourceViewer
local alive = true
local icons = {
	LocalScript = "rbxassetid://4800244808",
	Script = "rbxassetid://4800244808",
}

local constants = {
	fadeLength = TweenInfo.new(0.15),
	textWidth = Vector2.new(133742069, 20),
	maxPreviewRows = 250,
	maxScannedEntries = 4096,
	maxScriptRows = math.max(
		50,
		math.min(2000, math.floor(tonumber(oh.Settings and oh.Settings.MaxScriptRows) or 750))
	),
	rowBatch = 20,
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

local function showSource(title, source, errorMessage, activate)
	if activate ~= false and showSectionByName then
		showSectionByName("Source")
	end

	local generation = functionInspectionGeneration
	sourceViewer = TextViewer.Show(title, source or ("Source unavailable:\n" .. tostring(errorMessage or "unknown error")), {
		Parent = InfoSource,
		OnHide = function()
			if generation == functionInspectionGeneration then
				functionInspectionGeneration = functionInspectionGeneration + 1
				selected.sourceView = nil
			end
		end,
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

	local generation = functionInspectionGeneration
	sourceViewer = TextViewer.Show(title, tostring(text or ""), {
		Parent = InfoSource,
		OnHide = function()
			if generation == functionInspectionGeneration then
				functionInspectionGeneration = functionInspectionGeneration + 1
				selected.sourceView = nil
			end
		end,
	})
end

local function visibleSectionName()
	for _, section in ipairs(InfoSections:GetChildren()) do
		if section:IsA("GuiObject") and section.Visible then
			return section.Name
		end
	end

	return "Source"
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

local function makeEntries(values, limit, matches, isCurrent)
	local entries = {}
	local total = 0
	local matched = 0
	local scanLimited = false

	if type(values) ~= "table" then
		return entries, total, matched
	end

	for key, value in next, values do
		total = total + 1

		if total > constants.maxScannedEntries then
			scanLimited = true
			break
		end

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

		if total % 128 == 0 then
			task.wait()

			if not isCurrent() then
				return nil, total, matched, scanLimited, true
			end
		end
	end

	table.sort(entries, function(left, right)
		return left.Sort < right.Sort
	end)
	return entries, total, matched, scanLimited
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

	selected.sourceView = "function"
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
					IsAlive = function()
						return generation == functionInspectionGeneration
							and selected.scriptLog == log
							and alive
							and Page.Parent ~= nil
							and Page.Visible
					end,
					MaxOutputBytes = 131072,
					MaxSourceBytes = 32768,
					Decompile = function(target)
						return log.LocalScript:Decompile(target, 32768)
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

	selected.sourceView = "value"

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

local function renderTable(list, statusLabel, values, errorMessage, query, matches, createRow, isCurrent)
	if not isCurrent() then
		return
	end

	list:Clear()
	statusLabel.Text = ""

	if not values then
		statusLabel.Text = tostring(errorMessage or "Unavailable")
		return
	end

	local entries, total, matched, scanLimited, cancelled = makeEntries(
		values,
		constants.maxPreviewRows,
		function(index, value)
			return matches(index, value, query)
		end,
		isCurrent
	)

	if cancelled or not isCurrent() then
		return
	end

	local shown = 0
	local entryIndex = 1

	while entryIndex <= #entries do
		if not isCurrent() then
			return
		end

		local lastIndex = math.min(#entries, entryIndex + constants.rowBatch - 1)
		list:BeginBatch()

		for index = entryIndex, lastIndex do
			local entry = entries[index]

			if createRow(entry.Key, entry.Value) then
				shown = shown + 1
			end
		end

		list:EndBatch()
		entryIndex = lastIndex + 1

		if entryIndex <= #entries then
			task.wait()
		end
	end

	if not isCurrent() then
		return
	end

	if scanLimited then
		statusLabel.Text = ("Showing %d matches from the first %d entries (scan safety limit)."):format(shown, total - 1)
	elseif matched > #entries then
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

	sectionName = sectionName or visibleSectionName()
	detailRenderGeneration = detailRenderGeneration + 1
	local generation = detailRenderGeneration
	local function isCurrent()
		return generation == detailRenderGeneration
			and selected.scriptLog == log
			and alive
			and Page.Parent ~= nil
			and Page.Visible
			and ScriptInfo.Visible
			and visibleSectionName() == sectionName
	end

	task.spawn(function()
		if not isCurrent() then
			return
		end

		if sectionName == "Protos" then
			renderTable(
				protosList,
				ProtosResultsStatus,
				log.Protos,
				log.ProtosError or (not log.MetadataLoaded and "Loading protos ..." or nil),
				getSearchText(ProtosQuery),
				protoMatches,
				createProto,
				isCurrent
			)
		elseif sectionName == "Constants" then
			renderTable(
				constantsList,
				ConstantsResultsStatus,
				log.Constants,
				log.ConstantsError or (not log.MetadataLoaded and "Loading constants ..." or nil),
				getSearchText(ConstantsQuery),
				constantMatches,
				createConstant,
				isCurrent
			)
		elseif sectionName == "Environment" then
			renderTable(
				environmentList,
				EnvironmentResultsStatus,
				log.Environment,
				log.EnvironmentError or (not log.DetailsLoaded and "Loading environment ..." or nil),
				getSearchText(EnvironmentQuery),
				environmentMatches,
				createEnvironment,
				isCurrent
			)
		end
	end)
end

local function clearDetailLists()
	environmentList:Clear()
	protosList:Clear()
	constantsList:Clear()
	EnvironmentResultsStatus.Text = ""
	ProtosResultsStatus.Text = ""
	ConstantsResultsStatus.Text = ""
end

local function updateSummaryCounts(log)
	local button = log.Button and log.Button.Instance

	if not (button and button.Parent) then
		return
	end

	button.Protos.Text = log.Protos and #log.Protos or "!"
	button.Constants.Text = log.Constants and #log.Constants or "!"
end

ensureMetadata = function(log, isCurrent)
	while log.MetadataLoading do
		task.wait()

		if type(isCurrent) == "function" and not isCurrent() then
			return false, "cancelled"
		end
	end

	if log.MetadataLoaded then
		return true
	end

	log.MetadataLoading = true
	local loaded, loadError = pcall(function()
		runPrivileged(function()
			log.Protos, log.ProtosError = log.LocalScript:LoadProtos()
		end)

		task.wait()

		if type(isCurrent) == "function" and not isCurrent() then
			return
		end

		runPrivileged(function()
			log.Constants, log.ConstantsError = log.LocalScript:LoadConstants()
		end)
	end)

	if type(isCurrent) == "function" and not isCurrent() then
		log.MetadataLoading = false
		return false, "cancelled"
	end

	if not loaded then
		local message = "Metadata inspection failed: " .. tostring(loadError)
		log.ProtosError = log.ProtosError or message
		log.ConstantsError = log.ConstantsError or message
	end

	log.MetadataLoading = false
	log.MetadataLoaded = true
	updateSummaryCounts(log)
	return true
end

-- Log Object
local Log = {}

function Log.new(localScript, generation)
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
		selected.sourceView = "script"
		selected.protoFunction = nil
		selected.constantValue = nil
		selected.constantIndex = nil
		selected.environmentValue = nil
		selected.environmentIndex = nil
		functionInspectionGeneration = functionInspectionGeneration + 1
		detailLoadGeneration = detailLoadGeneration + 1
		log.DetailsOpenGeneration = detailLoadGeneration

		ScriptList.Visible = false
		ScriptInfo.Visible = true

		if showSectionByName then
			showSectionByName("Source")
		end

		local nameLength = TextService:GetTextSize(scriptName, 18, "SourceSans", constants.textWidth).X + 20

		InfoScript.Icon.Image = icons[scriptInstance.ClassName] or icons.LocalScript
		InfoScript.Label.Text = scriptName
		InfoScript.Label.Size = UDim2.new(0, nameLength, 0, 20)
		InfoScript.Position = UDim2.new(1, -nameLength, 0, 0)

		if log.Source or log.SourceError then
			showSource(scriptName .. " Source", log.Source, log.SourceError)
		else
			showSourceText("Loading Source", "Decompiling " .. scriptName .. " ...")
		end
		clearDetailLists()

		if log.DetailsLoaded or log.DetailsLoading then
			return
		end

		log.DetailsLoading = true

		task.spawn(function()
			local function requestIsCurrent()
				return log.DetailsOpenGeneration == detailLoadGeneration
					and selected.scriptLog == log
					and log.Generation == scanGeneration
					and log.Button
					and log.Button.Instance
					and log.Button.Instance.Parent ~= nil
					and alive
					and Page.Parent ~= nil
					and Page.Visible
			end

			local metadataRan, metadataLoaded, metadataError = pcall(ensureMetadata, log, requestIsCurrent)

			if not metadataRan then
				local message = "Metadata inspection failed: " .. tostring(metadataLoaded)
				log.ProtosError = log.ProtosError or message
				log.ConstantsError = log.ConstantsError or message
				log.MetadataLoading = false
				log.MetadataLoaded = true
			elseif not metadataLoaded then
				log.DetailsLoading = false
				return
			end

			if requestIsCurrent() then
				local sectionName = visibleSectionName()

				if sectionName == "Protos" or sectionName == "Constants" then
					renderSelectedSection(sectionName)
				end
			end

			if not requestIsCurrent() then
				log.DetailsLoading = false
				return
			end

			task.wait()

			if not requestIsCurrent() then
				log.DetailsLoading = false
				return
			end

			local environmentLoaded, environmentLoadError = pcall(function()
				runPrivileged(function()
					log.Environment, log.EnvironmentError = localScript:LoadEnvironment()
				end)
			end)

			if not environmentLoaded then
				local message = "Environment inspection failed: " .. tostring(environmentLoadError)
				log.EnvironmentError = log.EnvironmentError or message
			end

			if requestIsCurrent() and visibleSectionName() == "Environment" then
				renderSelectedSection("Environment")
			end

			if not requestIsCurrent() then
				log.DetailsLoading = false
				return
			end

			task.wait()

			if not requestIsCurrent() then
				log.DetailsLoading = false
				return
			end

			local sourceLoaded, sourceLoadError = pcall(function()
				runPrivileged(function()
					log.Source, log.SourceError = localScript:Decompile()
				end)
			end)

			if not sourceLoaded then
				log.SourceError = log.SourceError or ("Source inspection failed: " .. tostring(sourceLoadError))
			end

			log.DetailsLoading = false
			log.DetailsLoaded = true
			updateSummaryCounts(log)

			if requestIsCurrent() then
				if selected.sourceView == "script" then
					showSource(scriptName .. " Source", log.Source, log.SourceError, false)
				end

				local sectionName = visibleSectionName()

				if sectionName ~= "Source" then
					renderSelectedSection(sectionName)
				end
			end
		end)
	end

	listButton:SetCallback(openLog)

	listButton:SetRightCallback(function()
		selected.logContext = log
	end)

	scriptLogs[scriptInstance] = log

	log.LocalScript = localScript
	log.Generation = generation or scanGeneration
	log.Button = listButton
	log.Open = openLog
	log.SummaryQueued = false

	if queueSummaryLoad and Page.Visible then
		queueSummaryLoad(log)
	end

	return log
end

do
	local summaryQueue = {}
	local summaryHead = 1
	local summaryTail = 0
	local activeWorkers = 0
	local workerLimit = 2
	local queueGeneration = 0
	local pumpQueue

	local function processSummaryQueue(workerGeneration)
		while alive and Page.Parent ~= nil and workerGeneration == queueGeneration and Page.Visible do
			local log = summaryQueue[summaryHead]

			if not log then
				break
			end

			summaryQueue[summaryHead] = nil
			summaryHead = summaryHead + 1
			log.SummaryQueued = false

			if
				log.Generation == scanGeneration
				and not log.SummaryLoaded
				and log.Button
				and log.Button.Instance
				and log.Button.Instance.Parent
			then
				local function requestIsCurrent()
					return alive
						and Page.Parent ~= nil
						and Page.Visible
						and workerGeneration == queueGeneration
						and log.Generation == scanGeneration
						and log.Button
						and log.Button.Instance
						and log.Button.Instance.Parent ~= nil
				end
				local loaded, completed = pcall(ensureMetadata, log, requestIsCurrent)
				log.SummaryLoaded = loaded and completed == true and log.MetadataLoaded == true

				if not loaded then
					local message = "Metadata worker failed: " .. tostring(completed)
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
		pumpQueue()
	end

	pumpQueue = function()
		while alive and Page.Parent ~= nil and Page.Visible and activeWorkers < workerLimit and summaryHead <= summaryTail do
			activeWorkers = activeWorkers + 1
			task.defer(processSummaryQueue, queueGeneration)
		end
	end

	resetSummaryQueue = function()
		queueGeneration = queueGeneration + 1
		summaryQueue = {}
		summaryHead = 1
		summaryTail = 0
	end

	queueSummaryLoad = function(log)
		if not alive or Page.Parent == nil then
			return
		elseif log.SummaryQueued or log.SummaryLoaded then
			pumpQueue()
			return
		end

		log.SummaryQueued = true
		summaryTail = summaryTail + 1
		summaryQueue[summaryTail] = log
		pumpQueue()
	end
end

-- UI Functionality

local function rowComesBefore(left, right)
	if left.Sort == right.Sort then
		return left.Stable < right.Stable
	end

	return left.Sort < right.Sort
end

local function addBoundedRow(rows, row)
	if #rows < constants.maxScriptRows then
		rows[#rows + 1] = row
		local child = #rows

		while child > 1 do
			local parent = math.floor(child / 2)

			if not rowComesBefore(rows[parent], rows[child]) then
				break
			end

			rows[parent], rows[child] = rows[child], rows[parent]
			child = parent
		end

		return
	elseif not rowComesBefore(row, rows[1]) then
		return
	end

	rows[1] = row
	local parent = 1

	while true do
		local left = parent * 2
		local right = left + 1
		local greatest = parent

		if left <= #rows and rowComesBefore(rows[greatest], rows[left]) then
			greatest = left
		end

		if right <= #rows and rowComesBefore(rows[greatest], rows[right]) then
			greatest = right
		end

		if greatest == parent then
			break
		end

		rows[parent], rows[greatest] = rows[greatest], rows[parent]
		parent = greatest
	end
end

local function clearModelSourceCaches()
	for _, log in pairs(scriptLogs) do
		local model = log and log.LocalScript

		if model and type(model.ClearFunctionSourceCache) == "function" then
			pcall(model.ClearFunctionSourceCache, model)
		end
	end
end

local function addScripts(query)
	pendingScanQuery = query
	scanInitialized = true
	scanLoading = true
	scanGeneration = scanGeneration + 1
	local generation = scanGeneration
	resetSummaryQueue()
	scriptList:Clear()
	protosList:Clear()
	constantsList:Clear()
	environmentList:Clear()
	clearModelSourceCaches()
	scriptLogs = {}
	selected.scriptLog = nil
	selected.logContext = nil
	selected.sourceView = nil
	functionInspectionGeneration = functionInspectionGeneration + 1
	detailLoadGeneration = detailLoadGeneration + 1
	detailRenderGeneration = detailRenderGeneration + 1

	task.spawn(function()
		local rows = {}
		local scanned, total, cancelled = pcall(Methods.Enumerate, query, function(instance)
			addBoundedRow(rows, {
				Instance = instance,
				Sort = tostring(instance.Name or instance):lower(),
				Stable = tostring(instance),
			})
		end, {
			IsCancelled = function()
				return generation ~= scanGeneration or not alive or Page.Parent == nil or not Page.Visible
			end,
			YieldEvery = 128,
		})

		if not scanned then
			if generation == scanGeneration and Page.Visible then
				scanLoading = false
				oh.setStatus("Script scan failed: " .. tostring(total))
			end

			return
		end

		if cancelled or generation ~= scanGeneration or not Page.Visible then
			if generation == scanGeneration then
				scanLoading = false
				scanInitialized = false
			end

			return
		end

		table.sort(rows, rowComesBefore)

		local shown = #rows
		local index = 1

		while index <= shown do
			if generation ~= scanGeneration or not alive or Page.Parent == nil or not Page.Visible then
				if generation == scanGeneration then
					scanLoading = false
					scanInitialized = false
				end

				return
			end

			local lastIndex = math.min(shown, index + constants.rowBatch - 1)
			scriptList:BeginBatch()
			local created, createError = pcall(function()
				for rowIndex = index, lastIndex do
					Log.new(LocalScriptModel.new(rows[rowIndex].Instance), generation)
				end
			end)
			scriptList:EndBatch()

			if not created then
				if generation == scanGeneration and Page.Visible then
					scanLoading = false
					oh.setStatus("Script rows could not be created: " .. tostring(createError))
				end

				return
			end

			index = lastIndex + 1

			if index <= shown then
				task.wait()
			end
		end

		if generation == scanGeneration and Page.Visible then
			scanLoading = false
			scanInitialized = true

			if total > shown then
				oh.setStatus(("Showing %d of %d running scripts (row safety limit)."):format(shown, total))
			else
				oh.setStatus(("Script Scanner - %d running script%s"):format(total, total == 1 and "" or "s"))
			end
		end
	end)
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
	functionInspectionGeneration = functionInspectionGeneration + 1
	detailLoadGeneration = detailLoadGeneration + 1
	detailRenderGeneration = detailRenderGeneration + 1
	TextViewer.Hide(sourceViewer)
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
			functionInspectionGeneration = functionInspectionGeneration + 1
			TextViewer.Hide(sourceViewer)
			showSectionByName(sectionButton.Name)

			if selected.scriptLog then
				if sectionButton.Name == "Source" then
					local log = selected.scriptLog
					selected.sourceView = "script"
					showSource(log.LocalScript.Instance.Name .. " Source", log.Source, log.SourceError, false)
				else
					renderSelectedSection(sectionButton.Name)
				end
			end
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

Page:GetPropertyChangedSignal("Visible"):Connect(function()
	if not alive then
		return
	end

	if not Page.Visible then
		if scanLoading then
			scanGeneration = scanGeneration + 1
			scanLoading = false
			scanInitialized = false
			resetSummaryQueue()
		end

		functionInspectionGeneration = functionInspectionGeneration + 1
		detailLoadGeneration = detailLoadGeneration + 1
		detailRenderGeneration = detailRenderGeneration + 1
		TextViewer.Hide(sourceViewer)
		return
	end

	if not scanInitialized and not scanLoading then
		addScripts(pendingScanQuery)
	end

	for _, log in pairs(scriptLogs) do
		queueSummaryLoad(log)
	end

	local log = selected.scriptLog

	if ScriptInfo.Visible and log and log.Open then
		log.Open()
	end
end)

if Page.Visible and not scanInitialized then
	addScripts()
end

Page.Destroying:Connect(function()
	alive = false
	scanGeneration = scanGeneration + 1
	functionInspectionGeneration = functionInspectionGeneration + 1
	detailLoadGeneration = detailLoadGeneration + 1
	detailRenderGeneration = detailRenderGeneration + 1
	clearModelSourceCaches()
	resetSummaryQueue()
	TextViewer.Hide(sourceViewer)
end)

return ScriptScanner
