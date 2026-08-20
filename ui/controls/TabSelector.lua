local TweenService = game:GetService("TweenService")

local ControlUtil = import("ui/ControlUtil")
local Theme = (oh and oh.Theme) or import("ui/Theme")

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
	RemoteSpy = import("modules/RemoteSpy").RequiredMethods,
}

local constants = {
	tabSelected = Theme.Colors.ControlHover,
	iconSelected = Theme.Colors.Text,
	tabUnselected = Theme.Colors.Background,
	iconUnselected = Theme.Colors.TextDisabled,
}

local selectedTab
local selectedPage = Pages.Home
local boundTabs = setmetatable({}, { __mode = "k" })
local animationCache = setmetatable({}, { __mode = "k" })
local explorerDock
local explorerDefaultVisible
local originalPagesPosition = Pages.Position
local originalPagesSize = Pages.Size

local function tween(object, properties)
	return TweenService:Create(
		object,
		TweenInfo.new(ControlUtil.MotionDuration(Theme.Motion.Normal)),
		properties
	)
end

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
		dock.Visible = not scannerMode and explorerDefaultVisible ~= false
	end

	if scannerMode then
		Pages.Position = originalPagesPosition
		Pages.Size = UDim2.new(
			1,
			-math.max(0, originalPagesPosition.X.Offset),
			originalPagesSize.Y.Scale,
			originalPagesSize.Y.Offset
		)
	else
		Pages.Position = originalPagesPosition
		Pages.Size = originalPagesSize
	end
end

local function methodsCheck(methods)
	local globalMethods = (oh and oh.Methods) or {}
	local missing = {}

	for methodName in pairs(methods or {}) do
		if type(globalMethods[methodName]) ~= "function" then
			missing[#missing + 1] = methodName
		end
	end

	table.sort(missing)
	return #missing > 0 and table.concat(missing, ", ") or nil
end

local function displayName(name)
	return tostring(name or ""):gsub("^%l", string.upper):gsub("(%l)(%u)", "%1 %2")
end

local function setTabVisual(tab, selected)
	local animations = animationCache[tab]

	if animations then
		animations[selected and "selected" or "unselected"]:Play()
		animations[selected and "iconSelected" or "iconUnselected"]:Play()
	end
end

local function selectTab(tabName)
	local methods = requiredMethods[tabName]
	local missingMethods = methods and methodsCheck(methods)

	if missingMethods then
		MessageBox.Show(
			"Section unavailable",
			"The current runtime is missing the following required APIs: " .. missingMethods,
			MessageType.OK
		)
		return false
	end

	local tab = Tabs:FindFirstChild(tabName)
	local page = Pages:FindFirstChild(tabName)

	if not tab or not page or not tab:IsA("GuiButton") or not page:IsA("GuiObject") then
		return false
	end

	TextViewer.HideDefault()

	if selectedTab and selectedTab ~= tab then
		setTabVisual(selectedTab, false)
	end

	if selectedPage and selectedPage ~= page then
		selectedPage.Visible = false
	end

	page.Visible = true
	setTabVisual(tab, true)
	applyPageLayout(tabName)

	if oh and type(oh.setStatus) == "function" then
		pcall(oh.setStatus, displayName(page.Name))
	end

	selectedTab = tab
	selectedPage = page
	return true
end

local function bindTab(tab)
	if not tab:IsA("GuiButton") or boundTabs[tab] then
		return
	end

	local icon = tab:FindFirstChild("Icon")

	if not icon or not (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
		return
	end

	boundTabs[tab] = true
	tab.Selectable = true
	local visualProperty = tab:IsA("ImageButton") and "ImageColor3" or "BackgroundColor3"
	animationCache[tab] = {
		selected = tween(tab, { [visualProperty] = constants.tabSelected }),
		unselected = tween(tab, { [visualProperty] = constants.tabUnselected }),
		iconSelected = tween(icon, { ImageColor3 = constants.iconSelected }),
		iconUnselected = tween(icon, { ImageColor3 = constants.iconUnselected }),
	}

	ControlUtil.ConnectActivated(tab, function()
		if selectedTab ~= tab and tab.Parent == Tabs then
			selectTab(tab.Name)
		end
	end)

	ControlUtil.TrackConnection(tab.MouseEnter:Connect(function()
		if selectedPage ~= Pages:FindFirstChild(tab.Name) then
			setTabVisual(tab, true)
		end
	end))

	ControlUtil.TrackConnection(tab.MouseLeave:Connect(function()
		if selectedPage ~= Pages:FindFirstChild(tab.Name) then
			setTabVisual(tab, false)
		end
	end))
end

for _, tab in ipairs(Tabs:GetChildren()) do
	bindTab(tab)
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

function TabSelector.GetSelectedTab()
	return selectedTab and selectedTab.Name or nil
end

return TabSelector
