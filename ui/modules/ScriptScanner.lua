local TextService = game:GetService("TextService")
local TweenService = game:GetService("TweenService")

local ScriptScanner = {}
local Methods = import("modules/ScriptScanner")

if not hasMethods(Methods.RequiredMethods) then
	return ScriptScanner
end

local List, ListButton = import("ui/controls/List")
local MessageBox, MessageType = import("ui/controls/MessageBox")
local ContextMenu, ContextMenuButton = import("ui/controls/ContextMenu")
local TextViewer = import("ui/controls/TextViewer")
local InlineViewer = import("ui/controls/InlineViewer")

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
local sourceViewer
local queueSummaryLoad
local showSectionByName
local icons = {
	LocalScript = "rbxassetid://4800244808",
}

local constants = {
	fadeLength = TweenInfo.new(0.15),
	textWidth = Vector2.new(133742069, 20),
}

local pathContext = ContextMenuButton.new("rbxassetid://4891705738", "Get Script Path")
local sourceContext = ContextMenuButton.new("rbxassetid://4800244808", "View Script Source")
local protoSourceContext = ContextMenuButton.new("rbxassetid://4800244808", "View Function Source")
local constantSourceContext = ContextMenuButton.new("rbxassetid://4800244808", "View Function Source")

scriptList:BindContextMenu(ContextMenu.new({ pathContext, sourceContext }))
protosList:BindContextMenu(ContextMenu.new({ protoSourceContext }))
constantsList:BindContextMenu(ContextMenu.new({ constantSourceContext }))

pathContext:SetCallback(function()
	local selectedInstance = selected.logContext.LocalScript.Instance

	setClipboard(getInstancePath(selectedInstance))
	MessageBox.Show(
		"Success",
		("%s's path was copied to your clipboard."):format(selectedInstance.Name),
		MessageType.OK
	)
end)

local function runPrivileged(callback)
	if withExecutorIdentity then
		withExecutorIdentity(callback)
	else
		callback()
	end
end

local function showSource(title, source, errorMessage)
	if source then
		if showSectionByName then
			showSectionByName("Source")
		end

		if sourceViewer then
			sourceViewer:Show(title, source)
		else
			TextViewer.Show(title, source, { Parent = ScriptInfo })
		end
	else
		MessageBox.Show("Cannot view source", errorMessage or "Source is unavailable", MessageType.OK)
	end
end

local function createEnvironment(index, value)
	local instance = Assets.ConstantPod:Clone()
	local information = instance.Information
	local valueType = typeof(value)
	local indexText = tostring(index)
	local indexWidth = TextService:GetTextSize(indexText, 18, "SourceSans", constants.textWidth).X + 8

	information.Index.Text = indexText
	information.Label.Text = argumentSummary and argumentSummary(value) or toString(value)
	information.Label.TextColor3 = oh.Constants.Syntax[valueType] or oh.Constants.Syntax["userdata"]
	information.Icon.Image = oh.Constants.Types[valueType] or oh.Constants.Types["userdata"]

	information.Index.Size = UDim2.new(0, indexWidth, 0, 20)
	information.Label.Size = UDim2.new(1, -(indexWidth + 20), 1, 0)
	information.Icon.Position = UDim2.new(0, indexWidth, 0, 2)
	information.Label.Position = UDim2.new(0, indexWidth + 20, 0, 0)

	ListButton.new(instance, environmentList)
end

local function createProto(index, value)
	local instance = Assets.ProtoPod:Clone()
	local information = instance.Information
	local ran, info = pcall(getInfo, value, "n")
	local functionName = ran and info and info.name or ""
	local indexWidth = TextService:GetTextSize(index, 18, "SourceSans", constants.textWidth).X + 8

	if functionName == "" then
		functionName = "Unnamed function"
		information.Label.TextColor3 = oh.Constants.Syntax["unnamed_function"]
	end

	information.Index.Text = index
	information.Label.Text = functionName

	information.Index.Size = UDim2.new(0, indexWidth, 0, 20)
	information.Label.Size = UDim2.new(1, -(indexWidth + 20), 1, 0)
	information.Icon.Position = UDim2.new(0, indexWidth, 0, 2)
	information.Label.Position = UDim2.new(0, indexWidth + 20, 0, 0)

	local button = ListButton.new(instance, protosList)

	button:SetCallback(function()
		selected.protoFunction = value
	end)

	button:SetRightCallback(function()
		selected.protoFunction = value
	end)
end

local function createConstant(index, value)
	local instance = Assets.ConstantPod:Clone()
	local information = instance.Information
	local valueType = type(value)
	local indexWidth = TextService:GetTextSize(index, 18, "SourceSans", constants.textWidth).X + 8

	information.Index.Text = index

	information.Index.Size = UDim2.new(0, indexWidth, 0, 20)
	information.Label.Size = UDim2.new(1, -(indexWidth + 20), 1, 0)
	information.Icon.Position = UDim2.new(0, indexWidth, 0, 2)
	information.Label.Position = UDim2.new(0, indexWidth + 20, 0, 0)

	if valueType == "function" then
		local ran, info = pcall(getInfo, value, "n")
		local functionName = ran and info and info.name or ""

		if functionName == "" then
			functionName = "Unnamed function"
			information.Label.TextColor3 = oh.Constants.Syntax["unnamed_function"]
		end

		information.Label.Text = functionName
	else
		information.Label.Text = toString(value)
	end

	local button = ListButton.new(instance, constantsList)

	button:SetCallback(function()
		selected.constantValue = value
	end)

	button:SetRightCallback(function()
		selected.constantValue = value
	end)
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
	button.Protos.Text = "..."
	button.Constants.Text = "..."

	local function openLog()
		protosList:Clear()
		constantsList:Clear()
		environmentList:Clear()
		selected.protoFunction = nil
		selected.constantValue = nil
		ProtosResultsStatus.Text = ""
		ConstantsResultsStatus.Text = ""
		EnvironmentResultsStatus.Text = ""

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

		if sourceViewer then
			sourceViewer:Show("Loading Source", "Decompiling " .. scriptName .. " ...")
		end

		runPrivileged(function()
			local protos, protosError = localScript:LoadProtos()
			local constantsListData, constantsError = localScript:LoadConstants()
			local environment, environmentError = localScript:LoadEnvironment()
			local source, sourceError = localScript:Decompile()

			button.Protos.Text = protos and #protos or "!"
			button.Constants.Text = constantsListData and #constantsListData or "!"

			if protos then
				protosList:BeginBatch()

				for i, v in pairs(protos) do
					createProto(i, v)
				end

				protosList:EndBatch()
			elseif protosError then
				ProtosResultsStatus.Text = protosError
			end

			if constantsListData then
				constantsList:BeginBatch()

				for i, v in pairs(constantsListData) do
					createConstant(i, v)
				end

				constantsList:EndBatch()
			elseif constantsError then
				ConstantsResultsStatus.Text = constantsError
			end

			if environment then
				local emitted = 0
				environmentList:BeginBatch()

				for i, v in pairs(environment) do
					emitted = emitted + 1

					if emitted > 500 then
						EnvironmentResultsStatus.Text = "Environment truncated at 500 entries"
						break
					end

					createEnvironment(i, v)
				end

				environmentList:EndBatch()
			elseif environmentError then
				EnvironmentResultsStatus.Text = environmentError
			end

			showSource(scriptName .. " Source", source, sourceError)
		end)

		selected.scriptLog = log
	end

	listButton:SetCallback(function()
		openLog()
	end)

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

	local function processSummaryQueue()
		while summaryIndex <= #summaryQueue do
			local log = summaryQueue[summaryIndex]
			summaryIndex = summaryIndex + 1

			if log and not log.SummaryLoaded and log.Button and log.Button.Instance and log.Button.Instance.Parent then
				log.SummaryLoaded = true

				runPrivileged(function()
					local protos = log.LocalScript:LoadProtos()
					local constantsListData = log.LocalScript:LoadConstants()
					local button = log.Button.Instance

					if button and button.Parent then
						button.Protos.Text = protos and #protos or "!"
						button.Constants.Text = constantsListData and #constantsListData or "!"
					end
				end)
			end

			if task and task.wait then
				task.wait()
			end
		end

		table.clear(summaryQueue)
		summaryIndex = 1
		summaryRunning = false
	end

	queueSummaryLoad = function(log)
		summaryQueue[#summaryQueue + 1] = log

		if not summaryRunning then
			summaryRunning = true
			task.defer(processSummaryQueue)
		end
	end
end

-- UI Functionality

sourceViewer = InlineViewer.Install(InfoSource, { HeightScale = 1, TopScale = 0 })

local function addScripts(query)
	scriptList:Clear()
	scriptLogs = {}
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

sourceContext:SetCallback(function()
	local log = selected.logContext

	if not log then
		return
	elseif log.Open then
		log.Open()
		return
	end

	runPrivileged(function()
		local source, sourceError = log.LocalScript:Decompile()
		showSource(log.LocalScript.Instance.Name .. " Source", source, sourceError)
	end)
end)

protoSourceContext:SetCallback(function()
	local log = selected.scriptLog

	if not log or type(selected.protoFunction) ~= "function" then
		return MessageBox.Show("Cannot view source", "No function is selected", MessageType.OK)
	end

	runPrivileged(function()
		local source, sourceError = log.LocalScript:Decompile(selected.protoFunction)
		showSource("Function Source", source, sourceError)
	end)
end)

constantSourceContext:SetCallback(function()
	local log = selected.scriptLog

	if not log or type(selected.constantValue) ~= "function" then
		return MessageBox.Show("Cannot view source", "The selected constant is not a function", MessageType.OK)
	end

	runPrivileged(function()
		local source, sourceError = log.LocalScript:Decompile(selected.constantValue)
		showSource("Function Source", source, sourceError)
	end)
end)

InfoBack.MouseButton1Click:Connect(function()
	ScriptInfo.Visible = false
	ScriptList.Visible = true
end)

local selectedSection = InfoProtos
local selectedSectionButton = InfoOptions.Protos
local animationCache = {}

showSectionByName = function(sectionName)
	local section = InfoSections:FindFirstChild(sectionName)
	local sectionButton = InfoOptions:FindFirstChild(sectionName)

	if not section or not sectionButton or selectedSection == section then
		return
	end

	if animationCache[selectedSectionButton] then
		animationCache[selectedSectionButton].leave:Play()
	end

	selectedSection.Visible = false
	section.Visible = true
	selectedSection = section
	selectedSectionButton = sectionButton

	if animationCache[selectedSectionButton] then
		animationCache[selectedSectionButton].enter:Play()
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

return ScriptScanner
