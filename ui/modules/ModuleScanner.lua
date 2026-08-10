local ModuleScanner = {}
local Methods = import("modules/ModuleScanner")

if not hasMethods(Methods.RequiredMethods) then
    return ModuleScanner
end

local List, ListButton = import("ui/controls/List")
local MessageBox, MessageType = import("ui/controls/MessageBox")
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

local pathContext = ContextMenuButton.new("rbxassetid://4891705738", "Get Module Path")
local sourceContext = ContextMenuButton.new("rbxassetid://4800244808", "View Module Source")
moduleList:BindContextMenu(ContextMenu.new({ pathContext, sourceContext }))

pathContext:SetCallback(function()
    local selectedInstance = selectedLog.ModuleScript.Instance

    setClipboard(getInstancePath(selectedInstance))
    MessageBox.Show("Success", ("%s's path was copied to your clipboard."):format(selectedInstance.Name), MessageType.OK)
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
        TextViewer.Show(title, source)
    else
        MessageBox.Show("Cannot view source", errorMessage or "Source is unavailable", MessageType.OK)
    end
end

local function viewModuleSource(moduleScript)
    runPrivileged(function()
        local source, sourceError = moduleScript:Decompile()
        showSource(moduleScript.Instance.Name .. " Source", source, sourceError)
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
