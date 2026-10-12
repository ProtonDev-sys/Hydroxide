local ControlUtil = import("ui/ControlUtil")
local InspectUtil = import("ui/InspectUtil")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local UpvalueScanner = {}
local ClosureSpy = import("modules/ClosureSpy")
local Methods = import("modules/UpvalueScanner")
local Theme = oh.Theme or import("ui/Theme")

if not hasMethods(Methods.RequiredMethods) then
    return UpvalueScanner
end

local Upvalue = import("objects/Upvalue")

local Prompt = import("ui/controls/Prompt")
local CheckBox = import("ui/controls/CheckBox")
local Dropdown = import("ui/controls/Dropdown")
local List, ListButton = import("ui/controls/List")
local TabSelector = import("ui/controls/TabSelector")
local MessageBox, MessageType = import("ui/controls/MessageBox")
local TextViewer = import("ui/controls/TextViewer")
local FunctionInspector = import("ui/controls/FunctionInspector")
local ContextMenu, ContextMenuButton = import("ui/controls/ContextMenu")

local Base = import("rbxassetid://11389137937").Base
local Assets = import("rbxassetid://5042114982").UpvalueScanner

local Prompts = Base.Prompts
local Page = Base.Body.Pages.UpvalueScanner

local Query = Page.Query
local Search = Query.Search
local SearchBox = Query.Query
local Filters = Page.Filters
local ResultsClip = Page.Results.Clip
local ResultStatus = ResultsClip.ResultStatus

local modifyUpvalue = Prompt.new(Prompts.ModifyUpvalue)
local modifyElement = Prompt.new(Prompts.ModifyElement)
local deepSearch = CheckBox.new(Filters.SearchInTables)
local upvalueList = List.new(ResultsClip.Content)

local deepSearchFlag = false
local updateQueue = {}
local updateIndex = 1

local selectedLog
local selectedUpvalue
local selectedUpvalueLog
local selectedElement
local inspectGeneration = 0
local scanGeneration = 0
local elementKeys = setmetatable({}, { __mode = "k" })

local spyClosureContext = ContextMenuButton.new("rbxassetid://4666593447", "Spy Closure")
local inspectFunctionContext = ContextMenuButton.new("rbxassetid://4800244808", "Inspect Function")
local viewUpvaluesContext = ContextMenuButton.new("rbxassetid://5179169654", "View All Upvalues")
local changeUpvalueContext = ContextMenuButton.new("rbxassetid://5458573463", "Change Upvalue")
local changeTableContext = ContextMenuButton.new("rbxassetid://5458573463", "Change Upvalue")
local viewElementsContext = ContextMenuButton.new("rbxassetid://5179169654", "View All Elements")
local changeElementContext = ContextMenuButton.new("rbxassetid://5458573463", "Change Element")
local upvalueScriptContext = ContextMenuButton.new("rbxassetid://4800244808", "Generate Script")
local tableScriptContext = ContextMenuButton.new("rbxassetid://4800244808", "Generate Script")
local elementScriptContext = ContextMenuButton.new("rbxassetid://4800244808", "Generate Script")
local getScriptContext = ContextMenuButton.new("rbxassetid://4891705738", "Get Script Path")

local closureContextMenu = ContextMenu.new({ inspectFunctionContext, spyClosureContext, viewUpvaluesContext, getScriptContext })
local tableContextMenu = ContextMenu.new({ changeTableContext, viewElementsContext, tableScriptContext })
local upvalueContextMenu = ContextMenu.new({ changeUpvalueContext, upvalueScriptContext })
local elementContextMenu = ContextMenu.new({ changeElementContext, elementScriptContext })

local modifyUpvalueInner = modifyUpvalue.Instance.Inner
local modifyUpvalueContent = modifyUpvalueInner.Content
local modifyUpvalueButtons = modifyUpvalueInner.Buttons.SetCancel
local modifyUpvalueType = modifyUpvalueContent.Type
local modifyUpvalueValue = modifyUpvalueContent.Value.Input

local modifyElementInner = modifyElement.Instance.Inner
local modifyElementContent = modifyElementInner.Content
local modifyElementButtons = modifyElementInner.Buttons.SetCancel
local modifyElementType = modifyElementContent.Type
local modifyElementValue = modifyElementContent.Value.Input

local upvalueTypeDropdown = Dropdown.new(modifyUpvalueType)
local elementTypeDropdown = Dropdown.new(modifyElementType)

local constants = {
    tempElementColor = Theme.Colors.Selection,
    tempUpvalueColor = Theme.Colors.Selection,
    tempBorderColor = Theme.Colors.Danger
}

local function typeMismatchMessage()
    MessageBox.Show("Error", 
        "Value does not match selected type",
        MessageType.OK)
end

local function inspectSelectedFunction()
    if not selectedLog then
        return
    end

    inspectGeneration = inspectGeneration + 1
    local generation = inspectGeneration
    local log = selectedLog
    local function isCurrent()
        return generation == inspectGeneration and selectedLog == log and Page.Parent ~= nil and Page.Visible
    end
    local function cancelInspection()
        if generation == inspectGeneration then
            inspectGeneration = inspectGeneration + 1
        end
    end
    TextViewer.Show("Function Inspector", "Inspecting function metadata, upvalues, constants, protos, environment, and source ...", { OnHide = cancelInspection })

    task.spawn(function()
        local text
        local inspected, inspectError = pcall(function()
            local function inspect()
                text = FunctionInspector.DescribeFunction(log.Closure.Data, {
                    IsAlive = isCurrent,
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

        if isCurrent() then
            TextViewer.Show(
                "Function Inspector",
                inspected and (text or "No function information was returned.") or ("Function inspection failed:\n" .. tostring(inspectError)),
                { OnHide = cancelInspection }
            )
        end
    end)
end

local function addElement(upvalueLog, upvalue, index, value, temporary)
    local elementLog = Assets.Element:Clone()
    elementKeys[elementLog] = index
    local elementIndexType = type(index)
    local elementValueType = type(value)
    local indexText = toString(index)

    if temporary then
        elementLog.ImageColor3 = constants.tempElementColor
        elementLog.Border.ImageColor3 = constants.tempBorderColor
    end

    elementLog.Name = indexText
    elementLog.Index.Label.Text = indexText
    elementLog.Value.Label.Text = toString(value)
    elementLog.Index.Label.TextColor3 = oh.Constants.Syntax[elementIndexType]
    elementLog.Index.Icon.Image = oh.Constants.Types[elementIndexType]
    elementLog.Value.Label.TextColor3 = oh.Constants.Syntax[elementValueType]
    elementLog.Value.Icon.Image = oh.Constants.Types[elementValueType]

    ControlUtil.ConnectSecondary(elementLog, function()
        selectedUpvalue = upvalue
        selectedUpvalueLog = upvalueLog
        selectedElement = index
        elementTypeDropdown:SetSelected(typeof(value))
        elementContextMenu:Show()
    end)

    return elementLog
end

local function updateElement(upvalueLog, index, value, elementLog)
    local indexText = toString(index)
    local elementIndexType = type(index)
    local elementValueType = type(value)
    elementLog = elementLog or upvalueLog.Elements:FindFirstChild(indexText)
    if not elementLog then return end

    elementLog.Index.Label.Text = indexText
    elementLog.Value.Label.Text = toString(value)
    elementLog.Index.Label.TextColor3 = oh.Constants.Syntax[elementIndexType]
    elementLog.Value.Label.TextColor3 = oh.Constants.Syntax[elementValueType]
    elementLog.Index.Icon.Image = oh.Constants.Types[elementIndexType]
    elementLog.Value.Icon.Image = oh.Constants.Types[elementValueType]
    elementLog.Parent = upvalueLog.Elements
end

local function addUpvalue(upvalue, temporary)
    local upvalueLog
    local index = upvalue.Index
    local value = upvalue.Value
    local valueType = type(value)
    
    if valueType == "table" then
        upvalueLog = Assets.Table:Clone()
        local height = 25

        if temporary then
            upvalueLog.ImageColor3 = constants.tempUpvalueColor
            upvalueLog.Border.ImageColor3 = constants.tempBorderColor
        end

        if not temporary then
            for i, v in next, upvalue.Scanned or {} do
                local elementLog = addElement(upvalueLog, upvalue, i, v)
                elementLog.Parent = upvalueLog.Elements
                
                height = height + elementLog.AbsoluteSize.Y + 5
            end
        end

        upvalueLog.Size = UDim2.new(1, 0, 0, height)
    else
        upvalueLog = Assets.Upvalue:Clone()

        if temporary then
            upvalueLog.ImageColor3 = constants.tempUpvalueColor
            upvalueLog.Border.ImageColor3 = constants.tempBorderColor
        end

        if valueType == "function" then
            local ran, info = pcall(getInfo, value, "n")
            local closureName = ran and info and info.name or ''
            upvalueLog.Value.Text = (closureName == '' and "Unnamed function") or closureName
        else
            upvalueLog.Value.Text = toString(value)
        end
    end
    
    upvalueLog.Name = index
    upvalueLog.Index.Text = index
    upvalueLog.Value.TextColor3 = oh.Constants.Syntax[valueType]
    upvalueLog.Icon.Image = oh.Constants.Types[valueType]

    ControlUtil.ConnectSecondary(upvalueLog, function()
        selectedUpvalue = upvalue
        selectedUpvalueLog = upvalueLog
        upvalueTypeDropdown:SetSelected(typeof(upvalue.Value))

        if type(upvalue.Value) == "table" then
            tableContextMenu:Show()
        else
            upvalueContextMenu:Show()
        end
    end)

    return upvalueLog
end

local function updateUpvalue(closureLog, upvalue)
    local instance = closureLog.Instance
    local upvalueLog = instance.Upvalues:FindFirstChild(tostring(upvalue.Index))
    if not upvalueLog then return end
    local closure = upvalue.Closure
    local index = upvalue.Index
    local ok, newValue = pcall(getUpvalue, closure.Data, index)
    if not ok then return end
    local valueType = type(newValue)
    upvalue:Update(newValue)

    local elements = upvalueLog:FindFirstChild("Elements")
    if (valueType == "table") ~= (elements ~= nil) then
        upvalue.TemporaryElements = nil
        local replacement = addUpvalue(upvalue, closure.TemporaryUpvalues[index] ~= nil)
        local heightChange = UDim2.new(0, 0, 0, replacement.Size.Y.Offset - upvalueLog.Size.Y.Offset)
        replacement.LayoutOrder = upvalueLog.LayoutOrder
        replacement.Parent = instance.Upvalues
        if selectedUpvalueLog == upvalueLog then selectedUpvalueLog = replacement end
        if closureLog.TemporaryUpvalues and closureLog.TemporaryUpvalues[index] then
            closureLog.TemporaryUpvalues[index] = replacement
        else
            closureLog.Upvalues[index] = replacement
        end
        upvalueLog:Destroy()
        instance.Upvalues.Size = instance.Upvalues.Size + heightChange
        instance.Size = instance.Size + heightChange
        upvalueList:QueueRecalculate()
        return
    end

    if valueType == "function" then
        local ran, info = pcall(getInfo, newValue, "n")
        local closureName = ran and info and info.name or ''
        upvalueLog.Value.Text = (closureName == '' and "Unnamed function") or closureName
    elseif valueType == "table" then
        for _, element in ipairs(elements:GetChildren()) do
            local key = elementKeys[element]
            if key ~= nil then
                updateElement(upvalueLog, key, rawget(newValue, key), element)
            end
        end
    else
        upvalueLog.Value.Text = toString(newValue)
    end

    upvalueLog.Value.TextColor3 = oh.Constants.Syntax[valueType]
    upvalueLog.Icon.Image = oh.Constants.Types[valueType]

end

-- Log Object
local Log = {}

function Log.new(closure)
    local log = {}
    local instance = Assets.ClosureLog:Clone()
    local listButton = ListButton.new(instance, upvalueList)
    local logHeight = 30

    log.Instance = instance
    log.Closure = closure
    log.Upvalues = {}
    log.Update = Log.update

    for i, upvalue in pairs(closure.Upvalues) do
        local upvalueLog = addUpvalue(upvalue)
        upvalueLog.Parent = instance.Upvalues

        logHeight = logHeight + upvalueLog.AbsoluteSize.Y + 5
        log.Upvalues[i] = upvalueLog
    end

    instance.Size = UDim2.new(1, 0, 0, logHeight)
    instance:FindFirstChild("Name").Text = closure.Name
    
    listButton:SetRightCallback(function()
        selectedLog = log
    end)

    listButton:SetCallback(function()
        selectedLog = log
        inspectSelectedFunction()
    end)
    
    updateQueue[#updateQueue + 1] = log

    upvalueList:QueueRecalculate()
    return log
end

function Log.update(log)
    for _i, upvalue in pairs(log.Closure.Upvalues) do
        updateUpvalue(log, upvalue)
    end
    
    for _i, upvalue in pairs(log.Closure.TemporaryUpvalues) do
        updateUpvalue(log, upvalue)
    end
end

local function addUpvalues()
    local query = SearchBox.Text:match("^%s*(.-)%s*$") or ""
    if query == "" or (not tonumber(query) and #query <= 1) then
        MessageBox.Show("Invalid query", "Your query is too short", MessageType.OK)
        return
    end

    scanGeneration = scanGeneration + 1
    inspectGeneration = inspectGeneration + 1
    local generation = scanGeneration
    local scanTables = deepSearchFlag
    selectedLog = nil
    upvalueList:Clear()
    updateQueue = {}
    updateIndex = 1
    selectedUpvalue = nil
    selectedUpvalueLog = nil
    selectedElement = nil
    modifyUpvalue:Hide()
    modifyElement:Hide()
    SearchBox.Text = ""
    local function isCurrent()
        return generation == scanGeneration and Page.Parent ~= nil and Page.Visible
    end

    task.spawn(function()
        local ok, results, cancelled = pcall(Methods.Scan, query, scanTables, {
            IsCancelled = function() return not isCurrent() end,
        })
        if not isCurrent() or cancelled then return end
        if not ok then
            MessageBox.Show("Scan failed", tostring(results), MessageType.OK)
            return
        end

        local rows, unnamed = {}, {}
        for _, closure in pairs(results) do
            local destination = closure.Name == "Unnamed function" and unnamed or rows
            destination[#destination + 1] = closure
        end
        for _, closure in ipairs(unnamed) do rows[#rows + 1] = closure end
        local rendered, renderError = ControlUtil.RenderRows(upvalueList, rows, Log.new, isCurrent)
        if not rendered and isCurrent() then
            MessageBox.Show("Scan failed", tostring(renderError), MessageType.OK)
        end
        if isCurrent() then ResultStatus.Visible = #rows > 0 end
    end)
end

upvalueList:BindContextMenu(closureContextMenu)

deepSearch:SetCallback(function(enabled)
    deepSearchFlag = enabled
    
    if enabled then
        MessageBox.Show("Notice", "Deep searching may result in longer scan times!", MessageType.OK)
    end
end)

ControlUtil.ConnectActivated(Search, addUpvalues)
SearchBox.FocusLost:Connect(function(returned)
    if returned then
        addUpvalues()
    end
end)

local function setValue(valueText, dropdown)
    local raw = valueText
    local valueType = dropdown.Selected and dropdown.Selected.Name
    local newValue

    if valueType == "string" then
        newValue = raw
    elseif valueType == "nil" then
        return true, nil
    elseif valueType == "number" then
        local convert = tonumber(raw)

        if convert then
            newValue = convert
        else
            typeMismatchMessage()
            return false
        end
    elseif valueType == "boolean" then
        if raw == "true" then
            newValue = true
        elseif raw == "false" then
            newValue = false
        else
            typeMismatchMessage()
            return false
        end
    else
        local chunk = loadstring("return " .. raw)
        local success, result = pcall(chunk)
        
        if success then
            if typeof(result) == valueType then
                newValue = result
            else
                typeMismatchMessage()
                return false
            end
        else
            MessageBox.Show("Error",
                "There is an error in your input",
                MessageType.OK)
            return false
        end
    end

    return true, newValue
end

local function typeDropdownAdjust(dropdown, button)
    local instance = dropdown.Instance
    local icon = oh.Constants.Types[button.Name] or oh.Constants.Types["userdata"]

    instance.Icon.Image = icon
end

ControlUtil.ConnectActivated(modifyUpvalueButtons.Set, function()
    if not selectedUpvalue then
        return
    end

    local success, newValue = setValue(modifyUpvalueValue.Text, upvalueTypeDropdown)

    if success then
        local updated, updateError = pcall(selectedUpvalue.Set, selectedUpvalue, newValue)

        if not updated then
            MessageBox.Show("Cannot Update Upvalue", InspectUtil.BoundedText(updateError, 1024), MessageType.OK)
            return
        end

        modifyUpvalueValue.Text = ""
        modifyUpvalue:Hide()
    end
end)

ControlUtil.ConnectActivated(modifyUpvalueButtons.Cancel, function()
    modifyUpvalueValue.Text = ""
    modifyUpvalue:Hide()
end)

ControlUtil.ConnectActivated(modifyElementButtons.Set, function()
    if not selectedUpvalue or selectedElement == nil or type(selectedUpvalue.Value) ~= "table" then
        return
    end

    local upvalueValue = selectedUpvalue.Value
    
    local success, newValue = setValue(modifyElementValue.Text, elementTypeDropdown)

    if success then
        upvalueValue[selectedElement] = newValue

        modifyElementValue.Text = ""
        modifyElement:Hide()
    end
end)

ControlUtil.ConnectActivated(modifyElementButtons.Cancel, function()
    modifyElementValue.Text = ""
    modifyElement:Hide()
end)

upvalueTypeDropdown:SetCallback(typeDropdownAdjust)
elementTypeDropdown:SetCallback(typeDropdownAdjust)

local function generateScriptFormat()
    return [[-- Generated by Hydroxide Upvalue Scanner
-- Replace YOUR_NEW_VALUE_HERE, review the target details, then run.

local aux = assert(loadstring(httpget(%s), "Hydroxide/ohaux.lua"))()

local scriptPath = %s
local closureName = %s
local upvalueIndex = %d
local closureConstants = %s

local closure = assert(
    aux.searchClosure(scriptPath, closureName, upvalueIndex, closureConstants),
    "Hydroxide could not resolve the captured closure"
)
local value = YOUR_NEW_VALUE_HERE
%s
]]
end

local function generateScript(elementIndex)
    inspectGeneration = inspectGeneration + 1

    if not selectedUpvalue then
        return
    end

    local sourceReady, sourceURL = pcall(InspectUtil.SourceURL, oh and oh.Runtime, "ohaux")

    if not sourceReady then
        return TextViewer.Show("Edit Script Unavailable", InspectUtil.BoundedText(sourceURL, 1024))
    end

    local index = selectedUpvalue.Index
    local closure = selectedUpvalue.Closure
    local closureData = closure.Data
    local closureScript = safeGetClosureScript(closureData)
    local constantEntries = {}
    local currentIndex = 0

    if closureScript and not closureScript.Parent then
        closureScript = nil
    end

    local constantsRan, constants = pcall(getConstants, closureData)

    for idx, constant in pairs(constantsRan and constants or {}) do
        local constantType = type(constant)

        if currentIndex >= 6 then
            break 
        elseif constantType == "string" or constantType == "number" or constantType == "boolean" then
            constantEntries[#constantEntries + 1] = ("[%s] = %s"):format(dataToString(idx), dataToString(constant))
            currentIndex = currentIndex + 1
        end
    end

    local mutation

    if elementIndex ~= nil then
        local elementType = type(elementIndex)

        if elementType == "table" or elementType == "function" or elementType == "thread" then
            return TextViewer.Show(
                "Edit Script Unavailable",
                "Table, function, and thread keys cannot be reconstructed with the same identity safely."
            )
        end

        local serializedIndex = dataToString(elementIndex)

        if type(serializedIndex) ~= "string" or serializedIndex:find("^nil%s*%-%-%[%[") then
            return TextViewer.Show("Edit Script Unavailable", "This table key cannot be reconstructed safely.")
        end

        mutation = ([[
local getUpvalue = debug.getupvalue or getupvalue or getupval
assert(getUpvalue, "This environment does not expose debug.getupvalue")
local targetTable = getUpvalue(closure, upvalueIndex)
assert(type(targetTable) == "table", "The captured upvalue is no longer a table")
local elementIndex = %s
targetTable[elementIndex] = value]]):format(serializedIndex)
    else
        mutation = [[
local getUpvalue = debug.getupvalue or getupvalue or getupval
local setUpvalue = debug.setupvalue or setupvalue or setupval
assert(getUpvalue and setUpvalue, "This environment does not expose the Potassium upvalue APIs")
assert(
    typeof(value) == typeof(getUpvalue(closure, upvalueIndex)),
    "Potassium requires the replacement to match the captured upvalue type"
)
setUpvalue(closure, upvalueIndex, value)]]
    end

    local generatedScript = generateScriptFormat():format(
        string.format("%q", sourceURL),
        (closureScript and getInstancePath(closureScript)) or "nil",
        dataToString(closure.Name),
        index,
        "{ " .. table.concat(constantEntries, ", ") .. " }",
        mutation
    )
    local compileRan, compiled, compileError = pcall(loadstring, generatedScript, "Hydroxide/UpvalueEdit.lua")

    if not compileRan or not compiled then
        return TextViewer.Show("Edit Script Unavailable", tostring(compileError or compiled))
    end

    TextViewer.Show("Upvalue Edit Script", generatedScript)
end

upvalueScriptContext:SetCallback(function()
    generateScript()
end)

tableScriptContext:SetCallback(function()
    generateScript()
end)

elementScriptContext:SetCallback(function()
    generateScript(selectedElement)
end)

local SpyHook = ClosureSpy.Hook
spyClosureContext:SetCallback(function()
    if not selectedLog then
        return
    end

    local closure = selectedLog.Closure

    if TabSelector.SelectTab("ClosureSpy") then
        local result, hookError = SpyHook.new(closure)

        if result == false then
            MessageBox.Show("Already hooked", "You are already spying " .. closure.Name)
        elseif result == nil then
            MessageBox.Show("Cannot hook", hookError or ('Unable to hook "%s"'):format(closure.Name))
        end
    end
end)

inspectFunctionContext:SetCallback(inspectSelectedFunction)

viewUpvaluesContext:SetCallback(function()
    if selectedLog then
        local temporaryUpvalues = selectedLog.TemporaryUpvalues 
        local instance = selectedLog.Instance
        local newHeight = 0

        if temporaryUpvalues then
            for _i, upvalueLog in pairs(temporaryUpvalues) do
                newHeight = newHeight - (upvalueLog.AbsoluteSize.Y + 5)
                upvalueLog:Destroy()
            end

            selectedLog.TemporaryUpvalues = nil
            selectedLog.Closure.TemporaryUpvalues = {}
        else
            local closure = selectedLog.Closure
            
            temporaryUpvalues = {}

            for i,v in next, getUpvalues(closure.Data) do
                if not closure.Upvalues[i] then
                    local upvalue = Upvalue.new(closure, i, v)
                    
                    if type(v) == "table" then
                        upvalue.Scanned = {}
                    end
                    
                    local upvalueLog = addUpvalue(upvalue, true)
                    upvalueLog.Parent = instance.Upvalues
                    
                    newHeight = newHeight + upvalueLog.AbsoluteSize.Y + 5
                    temporaryUpvalues[i] = upvalueLog
                    closure.TemporaryUpvalues[i] = upvalue
                end
            end

            selectedLog.TemporaryUpvalues = temporaryUpvalues
        end

        newHeight = UDim2.new(0, 0, 0, newHeight)

        instance.Upvalues.Size = instance.Upvalues.Size + newHeight
        instance.Size = instance.Size + newHeight

        upvalueList:Recalculate()
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

viewElementsContext:SetCallback(function()
    if not selectedUpvalue or type(selectedUpvalue.Value) ~= "table"
        or not selectedUpvalueLog or not selectedUpvalueLog.Parent
        or not selectedUpvalueLog:FindFirstChild("Elements") then
        return
    end

    local temporaryElements = selectedUpvalue and selectedUpvalue.TemporaryElements
    local newHeight = 0

    if temporaryElements then
        for _, elementLog in pairs(temporaryElements) do
            newHeight = newHeight - (elementLog.AbsoluteSize.Y + 5)

            elementLog:Destroy()
        end

        selectedUpvalue.TemporaryElements = nil
    else
        local scanned = selectedUpvalue.Scanned or {}
        temporaryElements = {}

        for i,v in next, selectedUpvalue.Value do
            if scanned[i] == nil then
                local elementLog = addElement(selectedUpvalueLog, selectedUpvalue, i, v, true)
                elementLog.Parent = selectedUpvalueLog.Elements

                newHeight = newHeight + elementLog.AbsoluteSize.Y + 5
                temporaryElements[i] = elementLog
            end
        end 

        selectedUpvalue.TemporaryElements = temporaryElements
    end

    newHeight = UDim2.new(0, 0, 0, newHeight)

    selectedUpvalueLog.Size = selectedUpvalueLog.Size + newHeight
    selectedUpvalueLog.Parent.Parent.Size = selectedUpvalueLog.Parent.Parent.Size + newHeight
    upvalueList:Recalculate()
end)

local function changeUpvalue()
    if selectedUpvalue then
        local index = selectedUpvalue.Index
        local indexFrame = modifyUpvalueContent.Index
        local indexNumber = indexFrame.Number
        local indexWidth = TextService:GetTextSize(tostring(index), 18, "SourceSans", indexFrame.AbsoluteSize).X
        
        indexNumber.Text = index
        indexNumber.Size = UDim2.new(0, indexWidth, 0, 25)
        
        modifyUpvalue:Show()
    end
end

changeUpvalueContext:SetCallback(changeUpvalue)
changeTableContext:SetCallback(changeUpvalue)

changeElementContext:SetCallback(function()
    if selectedUpvalue and selectedElement ~= nil then
        local index = selectedElement
        local indexType = type(index)
        local indexFrame = modifyElementContent.Index
        local indexLabel = indexFrame.Data
        local indexText = tostring(index)
        local indexWidth = TextService:GetTextSize(indexText, 18, "SourceSans", indexFrame.AbsoluteSize).X
        
        indexLabel.Text = indexText
        indexLabel.TextColor3 = oh.Constants.Syntax[indexType]
        indexLabel.Size = UDim2.new(0, indexWidth, 0, 25)
        
        modifyElement:Show()
    end
end)

local updateAccumulator = 0
local updateInterval = 0.15
local maxLogsPerTick = 8

oh.Events.UpdateUpvalues = RunService.Heartbeat:Connect(function(deltaTime)
    if not Page.Visible or #updateQueue == 0 then
        updateAccumulator = 0
        return
    end

    updateAccumulator = updateAccumulator + (tonumber(deltaTime) or 0)

    if updateAccumulator < updateInterval then
        return
    end

    updateAccumulator = updateAccumulator % updateInterval

    for _ = 1, math.min(maxLogsPerTick, #updateQueue) do
        if updateIndex > #updateQueue then
            updateIndex = 1
        end

        local closureLog = updateQueue[updateIndex]
        updateIndex = updateIndex + 1

        if closureLog and closureLog.Instance and closureLog.Instance.Parent then
            closureLog:Update()
        end
    end
end)

Page:GetPropertyChangedSignal("Visible"):Connect(function()
    if not Page.Visible then
        scanGeneration = scanGeneration + 1
        inspectGeneration = inspectGeneration + 1
    end
end)
Page.Destroying:Connect(function()
    scanGeneration = scanGeneration + 1
    inspectGeneration = inspectGeneration + 1
end)

return UpvalueScanner 
