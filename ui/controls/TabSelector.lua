local TweenService = game:GetService("TweenService")
local Theme = oh.Theme or import("ui/Theme")

local TabSelector = {}

local Base = import("rbxassetid://11389137937").Base
local Tabs = Base.Tabs.Container
local Pages = Base.Body.Pages

local MessageBox, MessageType = import("ui/controls/MessageBox")
local TextViewer = import("ui/controls/TextViewer")

local requiredMethods = {
    ConstantScanner = import("modules/ConstantScanner").RequiredMethods,
    UpvalueScanner = import("modules/UpvalueScanner").RequiredMethods,
    ScriptScanner = import("modules/ScriptScanner").RequiredMethods,
    ModuleScanner = import("modules/ModuleScanner").RequiredMethods,
    ClosureSpy = import("modules/ClosureSpy").RequiredMethods,
    RemoteSpy = import("modules/RemoteSpy").RequiredMethods
}

local constants = {
    fadeLength = TweenInfo.new(0.15),
    tabSelected = Theme.Colors.ControlHover,
    iconSelected = Theme.Colors.Text,
    tabUnselected = Theme.Colors.Background,
    iconUnselected = Theme.Colors.TextDisabled
}

local selectedTab 
local selectedPage = Pages.Home
local boundTabs = setmetatable({}, { __mode = "k" })
local explorerDock
local explorerDefaultVisible
local originalPagesPosition = Pages.Position
local originalPagesSize = Pages.Size

local function findExplorerDock()
    if explorerDock and explorerDock.Parent then
        return explorerDock
    end

    local body = Base.Body

    for _, descendant in ipairs(body:GetDescendants()) do
        if descendant:IsA("TextBox")
            and tostring(descendant.PlaceholderText or ""):lower():find("filter explorer", 1, true)
        then
            local ancestor = descendant.Parent

            while ancestor and ancestor ~= body do
                if ancestor:IsA("GuiObject") and ancestor.Name:lower():find("explorer", 1, true) then
                    explorerDock = ancestor
                    explorerDefaultVisible = ancestor.Visible
                    return explorerDock
                end

                ancestor = ancestor.Parent
            end
        end
    end
end

local function applyPageLayout(tabName)
    local scannerMode = tabName == "ScriptScanner" or tabName == "ModuleScanner" or tabName == "RakNetSpy"
    local dock = findExplorerDock()

    if dock then
        dock.Visible = scannerMode and false or explorerDefaultVisible ~= false
    end

    if scannerMode then
        Pages.Position = UDim2.new(originalPagesPosition.X.Scale, originalPagesPosition.X.Offset, originalPagesPosition.Y.Scale, originalPagesPosition.Y.Offset)
        Pages.Size = UDim2.new(1, -math.max(0, originalPagesPosition.X.Offset), originalPagesSize.Y.Scale, originalPagesSize.Y.Offset)
    else
        Pages.Position = originalPagesPosition
        Pages.Size = originalPagesSize
    end
end

local function methodsCheck(methods)
    local globalMethods = oh.Methods
    local missingMethods = ""

    for methodName in pairs(methods) do
        if not globalMethods[methodName] then
            missingMethods = missingMethods .. methodName .. ", "
        end
    end

    return (missingMethods ~= "" and missingMethods:sub(1, -3)) or nil
end

local animationCache = {}
local function selectTab(tabName)
    local methodsFound = requiredMethods[tabName]
    local missingMethods = methodsFound and methodsCheck(methodsFound)

    if missingMethods then
        return MessageBox.Show(
            "Your exploit does not support this section",
            "The following functions are missing from your exploit: " .. missingMethods,
            MessageType.OK
        )
    end

    local tab = Tabs:FindFirstChild(tabName)
    local page = Pages:FindFirstChild(tabName)

    if not tab or not page then
        return false
    end

    TextViewer.HideDefault()

    if selectedTab then
        local tabAnimation = animationCache[selectedTab]
        tabAnimation.unselected:Play()
        tabAnimation.iconUnselected:Play()
    end

    selectedPage.Visible = false
    page.Visible = true
    tab.ImageColor3 = constants.tabSelected
    tab.Icon.ImageColor3 = constants.iconSelected

    applyPageLayout(tabName)

    oh.setStatus(page.Name:sub(1, 1) .. page.Name:sub(2):gsub('%u', function(c) return ' ' .. c end))
    
    selectedTab = tab
    selectedPage = page
    return true
end

local function bindTab(tab)
    if not tab:IsA("ImageButton") or boundTabs[tab] then
        return
    end

    boundTabs[tab] = true

    local selected = TweenService:Create(tab, constants.fadeLength, { ImageColor3 = constants.tabSelected })
    local unselected = TweenService:Create(tab, constants.fadeLength, { ImageColor3 = constants.tabUnselected })
    local iconSelected = TweenService:Create(tab.Icon, constants.fadeLength, { ImageColor3 = constants.iconSelected })
    local iconUnselected = TweenService:Create(tab.Icon, constants.fadeLength, { ImageColor3 = constants.iconUnselected })

    animationCache[tab] = {
        selected = selected,
        unselected = unselected,
        iconSelected = iconSelected,
        iconUnselected = iconUnselected
    }

    tab.MouseButton1Click:Connect(function()
        if selectedTab ~= tab and Tabs:FindFirstChild(tab.Name) then
            selectTab(tab.Name)
        end
    end)

    tab.MouseEnter:Connect(function()
        if selectedPage ~= Pages:FindFirstChild(tab.Name) then
            selected:Play()
            iconSelected:Play()
        end
    end)

    tab.MouseLeave:Connect(function()
        if selectedPage ~= Pages:FindFirstChild(tab.Name) then
            unselected:Play()
            iconUnselected:Play()
        end
    end)
end

for _i, tab in pairs(Tabs:GetChildren()) do
    if tab:IsA("ImageButton") then
        bindTab(tab)
    end
end

TabSelector.SelectTab = selectTab

function TabSelector.RegisterTab(name, tab, page, methods)
    if type(name) ~= "string" or name == "" or not tab or not page then
        return false
    end

    tab.Name = name
    page.Name = name
    tab.Parent = Tabs
    page.Parent = Pages
    page.Visible = false
    requiredMethods[name] = type(methods) == "table" and methods or nil
    bindTab(tab)
    return true
end

return TabSelector
