local TextService = game:GetService("TextService")

local ConstantScanner = {}
local ClosureSpy = import("modules/ClosureSpy")
local Methods = import("modules/ConstantScanner")

if not hasMethods(Methods.RequiredMethods) then
    return ConstantScanner
end

local Constant = import("objects/Constant")

local List, ListButton = import("ui/controls/List")
local MessageBox, MessageType = import("ui/controls/MessageBox")
local ContextMenu, ContextMenuButton = import("ui/controls/ContextMenu")
local TabSelector = import("ui/controls/TabSelector")
local TextViewer = import("ui/controls/TextViewer")
local FunctionInspector = import("ui/controls/FunctionInspector")

local Page = import("rbxassetid://11389137937").Base.Body.Pages.ConstantScanner
local Assets = import("rbxassetid://5042114982").ConstantScanner

local Query = Page.Query
local Search = Query.Search
local SearchBox = Query.Query
 
local constantList = List.new(Page.Results.Clip.Content)
local constantLogs = {}
local selectedLog 
local inspectGeneration = 0

local spyClosureContext = ContextMenuButton.new("rbxassetid://4666593447", "Spy Closure")
local inspectFunctionContext = ContextMenuButton.new("rbxassetid://4800244808", "Inspect Function")
local viewConstantsContext = ContextMenuButton.new("rbxassetid://5179169654", "View All Constants")
local getScriptContext = ContextMenuButton.new("rbxassetid://4891705738", "Get Script Path")

local constants = {
    tempConstantColor = Color3.fromRGB(40, 20, 20),
    tempBorderColor = Color3.fromRGB(20, 0, 0)
}

constantList:BindContextMenu(ContextMenu.new({ inspectFunctionContext, spyClosureContext, viewConstantsContext, getScriptContext }))

local function inspectSelectedFunction()
    if not selectedLog then
        return
    end

    inspectGeneration = inspectGeneration + 1
    local generation = inspectGeneration
    local log = selectedLog
    TextViewer.Show("Function Inspector", "Inspecting function metadata, constants, upvalues, protos, environment, and source ...")

    task.spawn(function()
        local text
        local inspected, inspectError = pcall(function()
            local function inspect()
                text = FunctionInspector.DescribeFunction(log.Closure.Data, {
                    GetPath = function(instance)
                        return getInstancePath(instance)
                    end
                })
            end

            if type(withExecutorIdentity) == "function" then
                withExecutorIdentity(inspect)
            else
                inspect()
            end
        end)

        if generation == inspectGeneration and selectedLog == log then
            TextViewer.Show(
                "Function Inspector",
                inspected and (text or "No function information was returned.") or ("Function inspection failed:\n" .. tostring(inspectError))
            )
        end
    end)
end

local function addConstant(constant, temporary)
    local constantLog = Assets.Constant:Clone()
    local index = constant.Index
    local value = constant.Value
    local valueType = type(value)
    local valueText = toString(value)

    if temporary then
        constantLog.ImageColor3 = constants.tempConstantColor
        constantLog.Border.ImageColor3 = constants.tempBorderColor
    end

    if valueType == "function" then
        local ran, info = pcall(getInfo, value, "n")
        local closureName = ran and info and info.name or ''
        constantLog.Value.Text = (closureName == '' and "Unnamed function") or closureName
    else
        constantLog.Value.Text = toString(value)
    end

    constantLog.Name = index
    constantLog.Index.Text = index
    constantLog.Value.TextColor3 = oh.Constants.Syntax[valueType]
    constantLog.Icon.Image = oh.Constants.Types[valueType]

    -- constantLog.MouseButton1Click:Connect(function()
    --     selectedConstant = constant
    --     selectedConstantLog = constantLog
    -- end)

    return constantLog
end

-- Log Object
local Log = {}

function Log.new(closure)
    local log = {}
    local button = Assets.ClosureLog:Clone()
    local listButton = ListButton.new(button, constantList) 
    local constants = closure.Constants
    local logHeight = 30

    for _i, constant in pairs(constants) do
        local constantLog = addConstant(constant)
        constantLog.Parent = button.Constants

        logHeight = logHeight + constantLog.AbsoluteSize.Y + 5
    end

    if closure.Name == "Unnamed function" then
        button:FindFirstChild("Name").TextColor3 = Color3.fromRGB(127, 127, 127)
    end

    button:FindFirstChild("Name").Text = closure.Name
    button.Size = UDim2.new(1, 0, 0, logHeight)

    listButton:SetRightCallback(function()
        selectedLog = log
    end)

    listButton:SetCallback(function()
        selectedLog = log
        inspectSelectedFunction()
    end)

    constantLogs[closure.Data] = log

    log.Closure = closure
    log.Constants = constants
    log.Button = listButton
    return log
end

-- UI Functinoality
local function addConstants()
    local query = SearchBox.Text

    if query:gsub(' ', '') ~= '' then
        if not tonumber(query) and query:len() <= 1 then
            return
        end

        constantList:Clear()
        constantLogs = {}

        for _i, closure in pairs(Methods.Scan(query)) do
            Log.new(closure)
        end

        constantList:Recalculate()
    else
        MessageBox.Show("Invalid query", "Your query is too short", MessageType.OK)
    end

    SearchBox.Text = ''
end

local SpyHook = ClosureSpy.Hook
spyClosureContext:SetCallback(function()
    if not selectedLog then
        return
    end

    local selectedClosure = selectedLog.Closure

    if TabSelector.SelectTab("ClosureSpy") then
        local result, hookError = SpyHook.new(selectedClosure)

        if result == false then
            MessageBox.Show("Already hooked", "You are already spying " .. selectedClosure.Name)
        elseif result == nil then
            MessageBox.Show("Cannot hook", hookError or ('Unable to hook "%s"'):format(selectedClosure.Name))
        end
    end
end)

inspectFunctionContext:SetCallback(inspectSelectedFunction)

viewConstantsContext:SetCallback(function()
    if selectedLog then
        local temporaryConstants = selectedLog.TemporaryConstants 
        local instance = selectedLog.Button.Instance
        local newHeight = 0

        if temporaryConstants then
            for _i, constantLog in pairs(temporaryConstants) do
                newHeight = newHeight - (constantLog.AbsoluteSize.Y + 5)
                constantLog:Destroy()
            end

            selectedLog.TemporaryConstants = nil
            selectedLog.Closure.TemporaryConstants = {}
        else
            local closure = selectedLog.Closure

            temporaryConstants = {}

            for i,v in pairs(getConstants(closure.Data)) do
                if not closure.Constants[i] then
                    local constant = Constant.new(closure, i, v) 

                    local constantLog = addConstant(constant, true)
                    constantLog.Parent = instance.Constants
                    
                    newHeight = newHeight + constantLog.AbsoluteSize.Y + 5
                    temporaryConstants[i] = constantLog
                    closure.TemporaryConstants[i] = constant
                end
            end

            selectedLog.TemporaryConstants = temporaryConstants
        end

        newHeight = UDim2.new(0, 0, 0, newHeight)

        instance.Constants.Size = instance.Constants.Size + newHeight
        instance.Size = instance.Size + newHeight

        constantList:Recalculate()
    end
end)

getScriptContext:SetCallback(function()
    if selectedLog then
        local script = safeGetClosureScript(selectedLog.Closure.Data)
            
        if typeof(script) == "Instance" then
            setClipboard(getInstancePath(script))
        end
    end
end)

Search.MouseButton1Click:Connect(addConstants)
SearchBox.FocusLost:Connect(function(returned)
    if returned then
        addConstants()
    end
end)

return ConstantScanner
