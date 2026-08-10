local ModuleScanner = {}
local Methods = import("modules/ModuleScanner")

if not hasMethods(Methods.RequiredMethods) then
    return ModuleScanner
end

local List, ListButton = import("ui/controls/List")
local ContextMenu, ContextMenuButton = import("ui/controls/ContextMenu")
local TextViewer = import("ui/controls/TextViewer")

local Page = import("rbxassetid://11389137937").Base.Body.Pages.ModuleScanner
local Assets = import("rbxassetid://5042114982").ModuleScanner

local Query = Page.Query
local Search = Query.Search
local Refresh = Query.Refresh
local Results = Page.Results.Clip.Content

local moduleList = List.new(Results)
local moduleLogs = {}
local selectedLog
local sourceLoads = setmetatable({}, { __mode = "k" })

local pathContext = ContextMenuButton.new("rbxassetid://4891705738", "Get Module Path")
local sourceContext = ContextMenuButton.new("rbxassetid://4800244808", "View Module Source")
moduleList:BindContextMenu(ContextMenu.new({ pathContext, sourceContext }))

pathContext:SetCallback(function()
	local selectedInstance = selectedLog and selectedLog.ModuleScript.Instance

	if not selectedInstance then
		return
	end

	local pathRan, path = pcall(getInstancePath, selectedInstance)
	local copied = pathRan and path and pcall(setClipboard, path)
	oh.setStatus(copied and "Module path copied" or "Module path unavailable")
end)

local function runPrivileged(callback)
    if withExecutorIdentity then
        withExecutorIdentity(callback)
    else
        callback()
    end
end

local function showSource(title, source, errorMessage)
	TextViewer.Show(title, source or ("Source unavailable:\n" .. tostring(errorMessage or "unknown error")))
end

local function viewModuleSource(moduleScript)
	local title = moduleScript.Instance.Name .. " Source"

	if moduleScript.LoadedSource then
		return showSource(title, moduleScript.Source, moduleScript.SourceError)
	end

	showSource(title, "Decompiling module ...")

	if sourceLoads[moduleScript] then
		return
	end

	sourceLoads[moduleScript] = true

	task.spawn(function()
		local source, sourceError
		local inspected, inspectError = pcall(function()
			runPrivileged(function()
				source, sourceError = moduleScript:Decompile()
			end)
		end)

		if not inspected then
			sourceError = "Module inspection failed: " .. tostring(inspectError)
		end

		sourceLoads[moduleScript] = nil

		if selectedLog and selectedLog.ModuleScript == moduleScript then
			showSource(title, source, sourceError)
		end
	end)
end

-- Log Object

local Log = {}

function Log.new(moduleScript)
    local log = {}
    local moduleInstance = moduleScript.Instance
    local button = Assets.ModuleLog:Clone()
    local listButton = ListButton.new(button, moduleList)
    
    button.Name = moduleInstance.Name
    button:FindFirstChild("Name").Text = moduleInstance.Name
    button.Protos.Text = "-"
    button.Constants.Text = "-"

	listButton:SetCallback(function()
		selectedLog = log
		viewModuleSource(moduleScript)
	end)

    listButton:SetRightCallback(function()
        selectedLog = log
    end)

    moduleLogs[moduleInstance] = log

    log.ModuleScript = moduleScript
    log.Button = listButton
    return log
end

sourceContext:SetCallback(function()
    if not selectedLog then
        return
    end

    viewModuleSource(selectedLog.ModuleScript)
end)

-- UI Functionality

local function addModules(query)
	moduleList:Clear()
	moduleLogs = {}
	selectedLog = nil
    moduleList:BeginBatch()

    for _moduleInstance, moduleScript in pairs(Methods.Scan(query)) do
        Log.new(moduleScript)
    end

    moduleList:EndBatch()
end

Search.FocusLost:Connect(function(returned)
    if returned then
        addModules(Search.Text)
        Search.Text = ""
    end
end)

Refresh.MouseButton1Click:Connect(function()
    addModules()
end)

addModules()

return ModuleScanner
