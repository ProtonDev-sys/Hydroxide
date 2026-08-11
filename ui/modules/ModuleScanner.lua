local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local ModuleScanner = {}
local Methods = import("modules/ModuleScanner")

if not hasMethods(Methods.RequiredMethods) then
	return ModuleScanner
end

local List, ListButton = import("ui/controls/List")
local ContextMenu, ContextMenuButton = import("ui/controls/ContextMenu")
local TextViewer = import("ui/controls/TextViewer")
local FunctionInspector = import("ui/controls/FunctionInspector")
local ModuleScriptModel = import("objects/ModuleScript")

local Interface = import("rbxassetid://11389137937")
local Pages = Interface.Base.Body.Pages
local Page = Pages.ModuleScanner
local Assets = import("rbxassetid://5042114982").ModuleScanner

local Query = Page.Query
local Search = Query.Search
local Refresh = Query.Refresh
local ResultsFrame = Page.Results
local Results = ResultsFrame.Clip.Content

Query.Size = UDim2.new(1, -8, Query.Size.Y.Scale, Query.Size.Y.Offset)
ResultsFrame.Size = UDim2.new(1, -8, ResultsFrame.Size.Y.Scale, ResultsFrame.Size.Y.Offset)

local function numberSetting(names, defaultValue, minimum, maximum)
	local settings = oh and oh.Settings or {}
	local value

	for _, name in ipairs(names) do
		value = tonumber(settings[name])

		if value then
			break
		end
	end

	if not value or value ~= value or value == math.huge or value == -math.huge then
		value = defaultValue
	end

	return math.clamp(math.floor(value), minimum, maximum)
end

local limits = {
	inspectorBytes = numberSetting({ "MaxInspectorBytes", "maxInspectorBytes" }, 524288, 32768, 524288),
	metadataWorkers = numberSetting({ "MaxConcurrentImports", "maxConcurrentImports" }, 2, 1, 2),
	moduleRows = numberSetting({ "MaxModuleRows", "MaxScannerRows" }, 750, 50, 2000),
	outputScanEntries = 4096,
	perFunctionBytes = 65536,
	perFunctionSourceBytes = 16384,
	previewEntries = 500,
	rowBatch = 20,
}

limits.sourceBytes = math.min(limits.inspectorBytes, 262144)
limits.perFunctionBytes = math.min(limits.perFunctionBytes, limits.inspectorBytes)
limits.perFunctionSourceBytes = math.min(limits.perFunctionSourceBytes, limits.perFunctionBytes)

local moduleList = List.new(Results)
local moduleLogs = {}
local selectedLog
local currentSection
local resumeSection = "Source"
local detailViewer
local scanGeneration = 0
local detailGeneration = 0
local alive = true
local scanInitialized = false
local scanLoading = false
local pendingScanQuery
local addModules

local metadataQueue = {}
local metadataQueueHead = 1
local metadataQueueTail = 0
local metadataQueueGeneration = 0
local metadataWorkers = 0
local pumpMetadataQueue
local queueMetadata
local resetMetadataQueue

local pathContext = ContextMenuButton.new("rbxassetid://4891705738", "Copy Module Path")
local sourceContext = ContextMenuButton.new("rbxassetid://4800244808", "Inspect Module")
moduleList:BindContextMenu(ContextMenu.new({ pathContext, sourceContext }))

local sectionOrder = { "Source", "Environment", "Functions", "Protos", "Constants" }
local inspectorIcon = "rbxassetid://4800244808"
local functionIcon = "rbxassetid://4666593447"
local fadeLength = TweenInfo.new(0.15)
local textBounds = Vector2.new(133742069, 20)

-- Reuse the Script Scanner's detail shell so both scanners inherit the same
-- responsive split layout, icon rail, back button, spacing, and section sizes.
local Details = Pages.ScriptScanner.Info:Clone()
Details.Name = "HydroxideModuleInspector"
Details.Visible = false
Details.Parent = Page

local Back = Details.Back
local InfoModule = Details.ScriptObject
local Title = InfoModule.Label
local InfoOptions = Details.Options.Clip.Content
local InfoSections = Details.Sections

local function firstTextBox(parent)
	if parent:IsA("TextBox") then
		return parent
	end

	local search = parent:FindFirstChild("Search", true)

	if search and search:IsA("TextBox") then
		return search
	end

	for _, descendant in ipairs(parent:GetDescendants()) do
		if descendant:IsA("TextBox") then
			return descendant
		end
	end
end

local function setButtonLabel(button, text)
	local label = button:FindFirstChild("Label")

	if label and label:IsA("TextLabel") then
		label.Text = text
	else
		button.Text = text
	end
end

local function clearContainer(container)
	for _, child in ipairs(container:GetChildren()) do
		child:Destroy()
	end
end

local protoButton = InfoOptions.Protos
local functionsButton = protoButton:Clone()
functionsButton.Name = "Functions"
functionsButton.Parent = InfoOptions
setButtonLabel(functionsButton, "Functions")

local functionButtonIcon = functionsButton:FindFirstChild("Icon")

if functionButtonIcon and functionButtonIcon:IsA("ImageLabel") then
	functionButtonIcon.Image = functionIcon
	local border = functionButtonIcon:FindFirstChild("Border")

	if border and border:IsA("ImageLabel") then
		border.Image = functionIcon
	end
end

-- The shipped Script Scanner rail contains four explicitly sized entries.
-- Give the cloned module rail its own vertical layout so the fifth Functions
-- entry remains visible instead of extending beyond the clipped container.
local oldOptionLayout = InfoOptions:FindFirstChildWhichIsA("UIGridStyleLayout")

if oldOptionLayout then
	oldOptionLayout:Destroy()
end

InfoOptions.Size = UDim2.new(1, 0, 1, 0)

local optionLayout = Instance.new("UIListLayout")
optionLayout.FillDirection = Enum.FillDirection.Vertical
optionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
optionLayout.Padding = UDim.new(0, 2)
optionLayout.SortOrder = Enum.SortOrder.LayoutOrder
optionLayout.VerticalAlignment = Enum.VerticalAlignment.Top
optionLayout.Parent = InfoOptions

local functionsSection = InfoSections.Protos:Clone()
functionsSection.Name = "Functions"
functionsSection.Parent = InfoSections

local sectionButtons = {}
local sectionFrames = {}
local sectionHosts = {}
local sectionFilters = {}
local animationCache = {}
local selectedSectionButton

for index, name in ipairs(sectionOrder) do
	local button = InfoOptions:FindFirstChild(name)
	local section = InfoSections:FindFirstChild(name)

	button.LayoutOrder = index
	button.Size = UDim2.new(1, 0, 0, 24)
	section.LayoutOrder = index
	section.Visible = false
	button.Position = UDim2.new()

	local label = button:FindFirstChild("Label")

	if label and label:IsA("TextLabel") then
		animationCache[button] = {
			enter = TweenService:Create(label, fadeLength, { TextTransparency = 0 }),
			leave = TweenService:Create(label, fadeLength, { TextTransparency = 0.2 }),
		}
	end

	sectionButtons[name] = button
	sectionFrames[name] = section

	if name == "Source" then
		clearContainer(section)
		sectionHosts[name] = section
	else
		local query = section:FindFirstChild("Query")
		local results = section:FindFirstChild("Results")
		local filter = query and firstTextBox(query)

		if filter then
			filter.ClearTextOnFocus = false
			filter.PlaceholderText = "Filter by key, type, value, or function name; press Enter"
			filter.Text = ""
			sectionFilters[name] = filter
		end

		if not results then
			results = Instance.new("Frame")
			results.Name = "Results"
			results.BackgroundTransparency = 1
			results.Position = UDim2.new(0, 0, 0, query and 35 or 0)
			results.Size = UDim2.new(1, 0, 1, query and -35 or 0)
			results.Parent = section
		end

		clearContainer(results)
		sectionHosts[name] = results
	end
end

InfoModule.Icon.Image = inspectorIcon

local function runPrivileged(callback)
	if type(withExecutorIdentity) == "function" then
		withExecutorIdentity(callback)
	else
		callback()
	end
end

local function boundedText(value, maximum, suffix)
	value = tostring(value or "")

	if #value <= maximum then
		return value
	end

	suffix = tostring(suffix or "...")
	local prefixLength = math.max(maximum - #suffix, 0)
	return value:sub(1, prefixLength) .. suffix:sub(1, maximum - prefixLength)
end

local function safeSummary(value, maximum)
	maximum = math.max(16, tonumber(maximum) or 260)

	if type(summarizeValue) == "function" then
		local ran, summary = pcall(summarizeValue, value, maximum)

		if ran and type(summary) == "string" then
			return boundedText(summary, maximum)
		end
	end

	local ran, summary = pcall(tostring, value)
	return boundedText(ran and summary or "<unprintable>", maximum)
end

local function safeTypeof(value)
	if type(typeof) == "function" then
		local ran, valueType = pcall(typeof, value)
		return ran and valueType or type(value)
	end

	return type(value)
end

local function safePath(instance)
	local ran, path = pcall(getInstancePath, instance)
	return ran and path or nil
end

local function newOutputState()
	return {
		Bytes = 0,
		Lines = {},
		MaxBytes = limits.inspectorBytes,
		Truncated = false,
	}
end

local function appendBounded(state, line)
	if state.Truncated then
		return false
	end

	line = tostring(line or "")
	local required = #line + 1

	if state.Bytes + required <= state.MaxBytes then
		state.Bytes = state.Bytes + required
		state.Lines[#state.Lines + 1] = line
		return true
	end

	local marker = "... inspector output truncated by the safety limit ..."
	local remaining = state.MaxBytes - state.Bytes
	local prefixLength = math.max(remaining - #marker - 2, 0)

	if prefixLength > 0 then
		state.Lines[#state.Lines + 1] = line:sub(1, prefixLength)
		state.Bytes = state.Bytes + prefixLength + 1
	end

	if state.Bytes + #marker + 1 <= state.MaxBytes then
		state.Lines[#state.Lines + 1] = marker
		state.Bytes = state.Bytes + #marker + 1
	end

	state.Truncated = true
	return false
end

local function finishOutput(state)
	return table.concat(state.Lines, "\n")
end

local function isLogAlive(log)
	local moduleScript = log and log.ModuleScript
	local moduleInstance = moduleScript and moduleScript.Instance
	local button = log and log.Button and log.Button.Instance

	return alive
		and Page.Parent ~= nil
		and log ~= nil
		and log.Generation == scanGeneration
		and moduleInstance ~= nil
		and moduleLogs[moduleInstance] == log
		and button ~= nil
		and button.Parent ~= nil
end

local function collectSortedEntries(values, resultLimit, predicate, stillAlive)
	local entries = {}
	local scanned = 0
	local matched = 0
	local scanLimited = false

	if type(values) ~= "table" then
		return entries, scanned, matched, scanLimited
	end

	local key

	while scanned < limits.outputScanEntries do
		local advanced, nextKey, nextValue = pcall(next, values, key)

		if not advanced then
			scanLimited = true
			break
		end

		if nextKey == nil then
			break
		end

		key = nextKey
		scanned = scanned + 1

		if not predicate or predicate(nextValue, nextKey) then
			matched = matched + 1

			if #entries < resultLimit then
				entries[#entries + 1] = {
					Key = nextKey,
					Value = nextValue,
					Sort = safeSummary(nextKey),
				}
			end
		end

		if scanned % 256 == 0 then
			task.wait()

			if stillAlive and not stillAlive() then
				return entries, scanned, matched, true
			end
		end
	end

	if scanned == limits.outputScanEntries then
		local advanced, nextKey = pcall(next, values, key)
		scanLimited = not advanced or nextKey ~= nil
	end

	table.sort(entries, function(left, right)
		return left.Sort < right.Sort
	end)
	return entries, scanned, matched, scanLimited
end

local function valueMatchesQuery(value, key, query)
	if query == "" then
		return true
	end

	local fields = {
		safeSummary(key, 240),
		tostring(safeTypeof(value)),
		safeSummary(value, 240),
	}

	if type(value) == "function" and type(getInfo) == "function" then
		local ran, info = pcall(getInfo, value, "ns")

		if not ran then
			ran, info = pcall(getInfo, value)
		end

		if ran and type(info) == "table" then
			fields[#fields + 1] = tostring(info.name or "")
			fields[#fields + 1] = tostring(info.short_src or info.source or "")
		end
	end

	for _, field in ipairs(fields) do
		if field:lower():find(query, 1, true) then
			return true
		end
	end

	return false
end

local function describeValues(title, values, errorMessage, stillAlive, query)
	local output = newOutputState()
	appendBounded(output, title:upper())
	appendBounded(output, "")

	if errorMessage then
		appendBounded(output, "Unavailable: " .. safeSummary(errorMessage, 1024))
		return finishOutput(output)
	elseif type(values) ~= "table" then
		appendBounded(output, "Unavailable: no table was returned")
		return finishOutput(output)
	end

	query = tostring(query or ""):lower()
	local entries, scanned, matched, scanLimited = collectSortedEntries(
		values,
		limits.previewEntries,
		function(value, key)
			return valueMatchesQuery(value, key, query)
		end,
		stillAlive
	)
	local countText = scanLimited and (tostring(matched) .. "+ (scan bounded)") or tostring(matched)
	local shownSuffix = matched > #entries and (" (first " .. #entries .. " shown)") or ""
	appendBounded(output, ("Matches: %s%s | Entries scanned: %d"):format(countText, shownSuffix, scanned))
	appendBounded(output, "")

	for _, entry in ipairs(entries) do
		if
			not appendBounded(
				output,
				("[%s]  %-18s  %s"):format(
					safeSummary(entry.Key),
					tostring(safeTypeof(entry.Value)),
					safeSummary(entry.Value)
				)
			)
		then
			break
		end
	end

	return finishOutput(output)
end

local function truncateSource(source, maximum)
	if type(source) ~= "string" then
		return source
	end

	return boundedText(source, maximum, "\n-- ... source truncated by the safety limit ...")
end

local resourceLoaders = {
	Constants = function(moduleScript)
		return moduleScript:LoadConstants()
	end,
	Environment = function(moduleScript)
		return moduleScript:LoadEnvironment()
	end,
	Protos = function(moduleScript)
		return moduleScript:LoadProtos()
	end,
	Source = function(moduleScript)
		return moduleScript:Decompile(nil, limits.sourceBytes)
	end,
}

local function loadResource(log, name, requestIsCurrent)
	local state = log.Resources[name]

	if state.Loaded then
		return state.Value, state.Error
	elseif state.Loading then
		while state.Loading and isLogAlive(log) and (not requestIsCurrent or requestIsCurrent()) do
			task.wait()
		end

		if requestIsCurrent and not requestIsCurrent() then
			return nil, "Inspection was cancelled"
		end

		if state.Loaded then
			return state.Value, state.Error
		end

		return nil, "Inspection was cancelled"
	end

	while log.ResourceBusy and isLogAlive(log) and (not requestIsCurrent or requestIsCurrent()) do
		task.wait()
	end

	if not isLogAlive(log) then
		return nil, "Inspection was cancelled"
	elseif requestIsCurrent and not requestIsCurrent() then
		return nil, "Inspection was cancelled"
	elseif state.Loaded then
		return state.Value, state.Error
	elseif state.Loading then
		while state.Loading and isLogAlive(log) and (not requestIsCurrent or requestIsCurrent()) do
			task.wait()
		end

		if requestIsCurrent and not requestIsCurrent() then
			return nil, "Inspection was cancelled"
		end

		if state.Loaded then
			return state.Value, state.Error
		end

		return nil, "Inspection was cancelled"
	end

	state.Loading = true
	log.ResourceBusy = true
	local value, errorMessage
	local loaded, loadError = pcall(function()
		runPrivileged(function()
			value, errorMessage = resourceLoaders[name](log.ModuleScript)
		end)
	end)

	if not loaded then
		value = nil
		errorMessage = "Inspection failed: " .. safeSummary(loadError, 1024)
	end

	state.Value = value
	state.Error = errorMessage
	state.Loading = false
	state.Loaded = true
	log.ResourceBusy = false
	return value, errorMessage
end

local function describeFunctions(log, values, errorMessage, title, stillAlive, query)
	local output = newOutputState()
	appendBounded(output, title:upper())

	if errorMessage then
		appendBounded(output, "")
		appendBounded(output, "Unavailable: " .. safeSummary(errorMessage, 1024))
		return finishOutput(output)
	elseif type(values) ~= "table" then
		appendBounded(output, "")
		appendBounded(output, "Unavailable: no table was returned")
		return finishOutput(output)
	end

	query = tostring(query or ""):lower()
	local maximum = numberSetting({ "MaxModuleFunctions" }, 32, 1, 128)
	local functions, scanned, matched, scanLimited = collectSortedEntries(values, maximum, function(value, key)
		return type(value) == "function" and valueMatchesQuery(value, key, query)
	end, stillAlive)
	local countText = scanLimited and (tostring(matched) .. "+") or tostring(matched)
	local suffix = matched > #functions and (" (first " .. #functions .. " inspected)") or ""

	if scanLimited then
		suffix = suffix .. (" (first %d entries scanned)"):format(scanned)
	end

	appendBounded(output, ("Functions: %s%s"):format(countText, suffix))
	appendBounded(output, "")

	for _, entry in ipairs(functions) do
		if stillAlive and not stillAlive() then
			break
		end

		local remaining = output.MaxBytes - output.Bytes

		if remaining < 8192 then
			appendBounded(output, "... remaining functions omitted by the total output limit ...")
			break
		end

		appendBounded(output, ("========== %s =========="):format(safeSummary(entry.Key)))
		remaining = output.MaxBytes - output.Bytes

		local description
		local described, describeError = pcall(function()
			runPrivileged(function()
				description = FunctionInspector.DescribeFunction(entry.Value, {
					Summarize = safeSummary,
					GetPath = safePath,
					IsAlive = stillAlive,
					MaxOutputBytes = math.min(limits.perFunctionBytes, remaining),
					MaxSourceBytes = math.min(limits.perFunctionSourceBytes, remaining),
					Decompile = function(target)
						local source, sourceError = log.ModuleScript:Decompile(target, limits.perFunctionSourceBytes)
						return truncateSource(source, limits.perFunctionSourceBytes), sourceError
					end,
				})
			end)
		end)

		if not described then
			description = "Function inspection failed: " .. safeSummary(describeError, 1024)
		end

		if not appendBounded(output, description) then
			break
		end

		appendBounded(output, "")
		task.wait()
	end

	if #functions == 0 then
		appendBounded(output, "(none)")
	end

	return finishOutput(output)
end

local function setSelectedSection(name)
	local section = sectionFrames[name]
	local button = sectionButtons[name]

	if not (section and button) then
		return
	end

	if selectedSectionButton ~= button then
		if animationCache[selectedSectionButton] then
			animationCache[selectedSectionButton].leave:Play()
		end

		selectedSectionButton = button

		if animationCache[selectedSectionButton] then
			animationCache[selectedSectionButton].enter:Play()
		end
	end

	for sectionName, candidate in pairs(sectionFrames) do
		candidate.Visible = sectionName == name
	end
end

local function inspectionIsCurrent(log, sectionState)
	return isLogAlive(log)
		and selectedLog == log
		and Page.Visible
		and Details.Visible
		and currentSection == sectionState.Name
		and sectionState.RequestGeneration == detailGeneration
end

local function showSectionText(name, text)
	local generation = detailGeneration
	detailViewer = TextViewer.Show(name, text, {
		MaxBytes = limits.inspectorBytes,
		Parent = sectionHosts[name],
		OnHide = function()
			if generation == detailGeneration then
				detailGeneration = detailGeneration + 1
				currentSection = nil
			end
		end,
	})
end

local function inspectSection(log, name, stillCurrent, query)
	if not stillCurrent() then
		return nil, false
	end

	if name == "Source" then
		local source, sourceError = loadResource(log, "Source", stillCurrent)

		if not stillCurrent() then
			return nil, false
		end

		if source then
			return truncateSource(source, limits.sourceBytes), true
		end

		return "Source unavailable:\n" .. safeSummary(sourceError or "unknown error", 1024), true
	elseif name == "Environment" then
		local values, loadError = loadResource(log, "Environment", stillCurrent)

		if not stillCurrent() then
			return nil, false
		end

		local text = describeValues("Module Environment", values, loadError, stillCurrent, query)
		return text, stillCurrent()
	elseif name == "Functions" then
		local values, loadError = loadResource(log, "Environment", stillCurrent)

		if not stillCurrent() then
			return nil, false
		end

		local text = describeFunctions(log, values, loadError, "Module Environment Functions", stillCurrent, query)
		return text, stillCurrent()
	elseif name == "Protos" then
		local values, loadError = loadResource(log, "Protos", stillCurrent)

		if not stillCurrent() then
			return nil, false
		end

		local text = describeFunctions(log, values, loadError, "Module Prototypes", stillCurrent, query)
		return text, stillCurrent()
	elseif name == "Constants" then
		local values, loadError = loadResource(log, "Constants", stillCurrent)

		if not stillCurrent() then
			return nil, false
		end

		local text = describeValues("Module Constants", values, loadError, stillCurrent, query)
		return text, stillCurrent()
	end

	return "No inspection data was returned.", true
end

local function showSection(name)
	local log = selectedLog

	if not isLogAlive(log) then
		return
	end

	detailGeneration = detailGeneration + 1
	currentSection = name
	local generation = detailGeneration
	local filter = sectionFilters[name]
	local query = filter and filter.Text:lower():gsub("^%s+", ""):gsub("%s+$", "") or ""
	local sectionState = log.Sections[name]
	sectionState.Name = name
	sectionState.RequestGeneration = generation
	sectionState.RequestQuery = query
	setSelectedSection(name)

	if sectionState.Loaded and sectionState.Query == query then
		showSectionText(name, sectionState.Text)
		return
	end

	showSectionText(name, "Loading " .. name:lower() .. " ...")

	if sectionState.Loading then
		return
	end

	sectionState.Loading = true

	task.spawn(function()
		local text
		local complete
		local function stillCurrent()
			return isLogAlive(log)
				and selectedLog == log
				and Page.Visible
				and Details.Visible
				and currentSection == name
				and detailGeneration == generation
		end

		local inspected, inspectError = pcall(function()
			text, complete = inspectSection(log, name, stillCurrent, query)
		end)

		if not inspected then
			text = "Inspection failed:\n" .. safeSummary(inspectError, 1024)
			complete = true
		end

		sectionState.Loading = false

		if not isLogAlive(log) then
			return
		end

		if not complete then
			-- A newer request may have arrived while this section owned the
			-- single privileged-resource worker. Relaunch only that request.
			if inspectionIsCurrent(log, sectionState) then
				local requestedGeneration = sectionState.RequestGeneration

				task.defer(function()
					if
						sectionState.RequestGeneration == requestedGeneration
						and not sectionState.Loading
						and inspectionIsCurrent(log, sectionState)
					then
						showSection(name)
					end
				end)
			end

			return
		end

		sectionState.Text = boundedText(text or "No inspection data was returned.", limits.inspectorBytes)
		sectionState.Loaded = true
		sectionState.Query = query

		if inspectionIsCurrent(log, sectionState) then
			showSectionText(name, sectionState.Text)
		end
	end)
end

for name, button in pairs(sectionButtons) do
	local sectionName = name

	button.MouseButton1Click:Connect(function()
		showSection(sectionName)
	end)

	button.MouseEnter:Connect(function()
		if selectedSectionButton ~= button and animationCache[button] then
			animationCache[button].enter:Play()
		end
	end)

	button.MouseLeave:Connect(function()
		if selectedSectionButton ~= button and animationCache[button] then
			animationCache[button].leave:Play()
		end
	end)

	local filter = sectionFilters[sectionName]

	if filter then
		filter.FocusLost:Connect(function(returned)
			if returned and currentSection == sectionName and isLogAlive(selectedLog) then
				showSection(sectionName)
			end
		end)
	end
end

setSelectedSection("Source")

local function openInspector(log)
	if not isLogAlive(log) then
		return
	end

	selectedLog = log

	for _, filter in pairs(sectionFilters) do
		filter.Text = ""
	end

	local moduleName = log.ModuleScript.Instance.Name
	local nameLength = TextService:GetTextSize(moduleName, 18, "SourceSans", textBounds).X + 20
	Title.Text = moduleName
	Title.Size = UDim2.new(0, nameLength, 0, 20)
	InfoModule.Position = UDim2.new(1, -nameLength, 0, 0)
	Query.Visible = false
	ResultsFrame.Visible = false
	Details.Visible = true
	showSection("Source")
end

Back.MouseButton1Click:Connect(function()
	resumeSection = currentSection or resumeSection
	detailGeneration = detailGeneration + 1
	currentSection = nil
	TextViewer.Hide(detailViewer)
	Details.Visible = false
	Query.Visible = true
	ResultsFrame.Visible = true
end)

Page:GetPropertyChangedSignal("Visible"):Connect(function()
	if not alive then
		return
	end

	if not Page.Visible then
		if scanLoading then
			scanGeneration = scanGeneration + 1
			scanLoading = false
			scanInitialized = false
			resetMetadataQueue()
		end

		resumeSection = currentSection or resumeSection
		detailGeneration = detailGeneration + 1
		currentSection = nil
		TextViewer.Hide(detailViewer)
	else
		if not scanInitialized and not scanLoading then
			addModules(pendingScanQuery)
		end

		for _, log in pairs(moduleLogs) do
			queueMetadata(log)
		end

		pumpMetadataQueue()
	end

	if Page.Visible and Details.Visible and isLogAlive(selectedLog) then
		task.defer(function()
			if Page.Visible and Details.Visible and isLogAlive(selectedLog) then
				showSection(resumeSection or "Source")
			end
		end)
	end
end)

pathContext:SetCallback(function()
	local selectedInstance = selectedLog and selectedLog.ModuleScript.Instance

	if not selectedInstance then
		return
	end

	local path = safePath(selectedInstance)
	local copied = path and pcall(setClipboard, path)
	oh.setStatus(copied and "Module path copied" or "Module path unavailable")
end)

sourceContext:SetCallback(function()
	if selectedLog then
		openInspector(selectedLog)
	end
end)

local function metricText(resource)
	if not resource.Loaded then
		return "..."
	elseif resource.Error or type(resource.Value) ~= "table" then
		return "!"
	end

	return tostring(#resource.Value)
end

local function updateMetadataCounts(log)
	if not isLogAlive(log) then
		return
	end

	local button = log.Button.Instance
	button.Protos.Text = metricText(log.Resources.Protos)
	button.Constants.Text = metricText(log.Resources.Constants)
end

local function loadMetadata(log)
	if not alive or not Page.Visible or not isLogAlive(log) or log.MetadataLoaded then
		return
	end

	log.MetadataLoading = true
	loadResource(log, "Protos")

	if Page.Visible and isLogAlive(log) then
		task.wait()

		if Page.Visible and isLogAlive(log) then
			loadResource(log, "Constants")
		end
	end

	log.MetadataLoading = false
	log.MetadataLoaded = log.Resources.Protos.Loaded and log.Resources.Constants.Loaded
	updateMetadataCounts(log)
end

local function popMetadataQueue()
	if metadataQueueHead > metadataQueueTail then
		metadataQueue = {}
		metadataQueueHead = 1
		metadataQueueTail = 0
		return nil
	end

	local log = metadataQueue[metadataQueueHead]
	metadataQueue[metadataQueueHead] = nil
	metadataQueueHead = metadataQueueHead + 1
	return log
end

local function metadataWorker(workerGeneration)
	while alive and workerGeneration == metadataQueueGeneration do
		if Page.Parent == nil or not Page.Visible then
			break
		end

		local log = popMetadataQueue()

		if not log then
			break
		end

		log.MetadataQueued = false

		if isLogAlive(log) then
			local loaded, loadError = pcall(loadMetadata, log)

			if not loaded then
				log.MetadataLoading = false
				log.MetadataLoaded = true
				log.Resources.Protos.Error = log.Resources.Protos.Error
					or ("Metadata inspection failed: " .. safeSummary(loadError, 1024))
				log.Resources.Protos.Loaded = true
				log.Resources.Constants.Error = log.Resources.Constants.Error
					or ("Metadata inspection failed: " .. safeSummary(loadError, 1024))
				log.Resources.Constants.Loaded = true
				updateMetadataCounts(log)
			end
		end

		task.wait()
	end

	metadataWorkers = metadataWorkers - 1
	pumpMetadataQueue()
end

pumpMetadataQueue = function()
	while
		alive
		and Page.Parent ~= nil
		and Page.Visible
		and metadataWorkers < limits.metadataWorkers
		and metadataQueueHead <= metadataQueueTail
	do
		metadataWorkers = metadataWorkers + 1
		task.defer(metadataWorker, metadataQueueGeneration)
	end
end

queueMetadata = function(log)
	if not alive or Page.Parent == nil then
		return
	elseif log.MetadataQueued or log.MetadataLoading or log.MetadataLoaded then
		return
	end

	log.MetadataQueued = true
	metadataQueueTail = metadataQueueTail + 1
	metadataQueue[metadataQueueTail] = log
	pumpMetadataQueue()
end

local function resourceState(loaded, value, errorMessage)
	return {
		Error = errorMessage,
		Loaded = loaded == true,
		Loading = false,
		Value = value,
	}
end

local Log = {}

function Log.new(moduleScript, generation)
	local moduleInstance = moduleScript.Instance
	local log = {
		Generation = generation,
		MetadataLoaded = moduleScript.LoadedProtos == true and moduleScript.LoadedConstants == true,
		MetadataLoading = false,
		MetadataQueued = false,
		ModuleScript = moduleScript,
		ResourceBusy = false,
		Resources = {
			Constants = resourceState(
				moduleScript.LoadedConstants,
				moduleScript.Constants,
				moduleScript.ConstantsError
			),
			Environment = resourceState(
				moduleScript.LoadedEnvironment,
				moduleScript.Environment,
				moduleScript.EnvironmentError
			),
			Protos = resourceState(moduleScript.LoadedProtos, moduleScript.Protos, moduleScript.ProtosError),
			Source = resourceState(moduleScript.LoadedSource, moduleScript.Source, moduleScript.SourceError),
		},
		Sections = {},
	}

	for _, name in ipairs({ "Source", "Environment", "Functions", "Protos", "Constants" }) do
		log.Sections[name] = {
			Loaded = false,
			Loading = false,
			Name = name,
			Query = nil,
			RequestGeneration = 0,
			RequestQuery = nil,
			Text = nil,
		}
	end

	local button = Assets.ModuleLog:Clone()
	local listButton = ListButton.new(button, moduleList)
	log.Button = listButton

	button.Name = moduleInstance.Name
	button:FindFirstChild("Name").Text = moduleInstance.Name
	button.Protos.Text = metricText(log.Resources.Protos)
	button.Constants.Text = metricText(log.Resources.Constants)

	listButton:SetCallback(function()
		openInspector(log)
	end)

	listButton:SetRightCallback(function()
		if isLogAlive(log) then
			selectedLog = log
		end
	end)

	moduleLogs[moduleInstance] = log

	if Page.Visible then
		queueMetadata(log)
	end

	return log
end

resetMetadataQueue = function()
	metadataQueueGeneration = metadataQueueGeneration + 1
	metadataQueue = {}
	metadataQueueHead = 1
	metadataQueueTail = 0
end

local function rowComesBefore(left, right)
	if left.Sort == right.Sort then
		return left.Stable < right.Stable
	end

	return left.Sort < right.Sort
end

local function addBoundedRow(rows, row)
	if #rows < limits.moduleRows then
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
	for _, log in pairs(moduleLogs) do
		local model = log and log.ModuleScript

		if model and type(model.ClearFunctionSourceCache) == "function" then
			pcall(model.ClearFunctionSourceCache, model)
		end
	end
end

local function collectModuleRows(query, generation)
	local rows = {}
	local scanned, total, cancelled = pcall(Methods.Enumerate, query, function(moduleInstance)
		addBoundedRow(rows, {
			Instance = moduleInstance,
			Sort = tostring(moduleInstance.Name):lower(),
			Stable = tostring(moduleInstance),
		})
	end, {
		IsCancelled = function()
			return generation ~= scanGeneration or not alive or Page.Parent == nil or not Page.Visible
		end,
		YieldEvery = 128,
	})

	if not scanned then
		if generation == scanGeneration and Page.Visible then
			oh.setStatus("Module scan failed: " .. safeSummary(total, 240))
		end

		return {}, 0, false, total
	end

	if cancelled or generation ~= scanGeneration then
		return {}, total, true
	end

	table.sort(rows, rowComesBefore)
	return rows, total, false
end

addModules = function(query)
	pendingScanQuery = query
	scanInitialized = true
	scanLoading = true
	scanGeneration = scanGeneration + 1
	detailGeneration = detailGeneration + 1
	local generation = scanGeneration
	currentSection = nil
	TextViewer.Hide(detailViewer)
	Details.Visible = false
	Query.Visible = true
	ResultsFrame.Visible = true
	resetMetadataQueue()
	moduleList:Clear()
	clearModelSourceCaches()
	moduleLogs = {}
	selectedLog = nil

	task.spawn(function()
		local rows, total, cancelled, scanError = collectModuleRows(query, generation)

		if scanError then
			if generation == scanGeneration then
				scanLoading = false
				scanInitialized = true
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

		local index = 1

		while index <= #rows do
			if generation ~= scanGeneration or not alive or Page.Parent == nil or not Page.Visible then
				if generation == scanGeneration then
					scanLoading = false
					scanInitialized = false
				end

				return
			end

			local lastIndex = math.min(index + limits.rowBatch - 1, #rows)
			moduleList:BeginBatch()
			local created, createError = pcall(function()
				for rowIndex = index, lastIndex do
					Log.new(ModuleScriptModel.new(rows[rowIndex].Instance), generation)
				end
			end)
			moduleList:EndBatch()

			if not created then
				if generation == scanGeneration and Page.Visible then
					scanLoading = false
					oh.setStatus("Module rows could not be created: " .. safeSummary(createError, 240))
				end

				return
			end

			index = lastIndex + 1

			if index <= #rows then
				task.wait()
			end
		end

		if generation == scanGeneration and Page.Visible then
			scanLoading = false
			scanInitialized = true

			if total > #rows then
				oh.setStatus(("Showing %d of %d loaded modules (row safety limit)."):format(#rows, total))
			else
				oh.setStatus(("Module Scanner - %d loaded module%s"):format(total, total == 1 and "" or "s"))
			end
		end
	end)
end

Search.FocusLost:Connect(function(returned)
	if returned then
		addModules(Search.Text)
		Search.Text = ""
	end
end)

Page.Destroying:Connect(function()
	alive = false
	scanLoading = false
	scanGeneration = scanGeneration + 1
	detailGeneration = detailGeneration + 1
	clearModelSourceCaches()
	resetMetadataQueue()
	TextViewer.Hide(detailViewer)
end)

Refresh.MouseButton1Click:Connect(function()
	addModules()
end)

if Page.Visible and not scanInitialized then
	addModules()
end
return ModuleScanner
