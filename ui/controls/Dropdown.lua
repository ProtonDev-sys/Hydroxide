local UserInput = game:GetService("UserInputService")

local Dropdown = {}
local dropdownCache = {}

local function bindOption(dropdown, button)
    button.MouseButton1Click:Connect(function()
        dropdown:Collapse(button.Name)
    end)
end

local function refreshCanvas(dropdown)
    local clip = dropdown.Instance.Selection.Clip
    local list = clip.List
    local layout = list:FindFirstChildWhichIsA("UIListLayout") or list:FindFirstChildWhichIsA("UIGridLayout")
    local scroller = list:IsA("ScrollingFrame") and list or (clip:IsA("ScrollingFrame") and clip)

    if scroller and layout then
        scroller.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 4)
        scroller.ScrollBarThickness = math.max(5, scroller.ScrollBarThickness)
    end
end

function Dropdown.new(instance)
    local dropdown = {}
    local selection = instance.Selection

    instance.Collapse.MouseButton1Click:Connect(function()
        local collapsed = not dropdown.Collapsed

        selection.Visible = not collapsed
        dropdown.Collapsed = collapsed
    end)

    for _i, v in pairs(instance.Selection.Clip.List:GetChildren()) do
        if v:IsA("TextButton") then
            bindOption(dropdown, v)
        end
    end

    dropdown.Collapse = Dropdown.collapse
    dropdown.Collapsed = true
    selection.Visible = false
    dropdown.Instance = instance
    dropdown.SetSelected = Dropdown.setSelected
    dropdown.SetCallback = Dropdown.setCallback
    dropdown.AddOption = Dropdown.addOption

    local layout = instance.Selection.Clip.List:FindFirstChildWhichIsA("UIListLayout")
        or instance.Selection.Clip.List:FindFirstChildWhichIsA("UIGridLayout")

    if layout then
        layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
            refreshCanvas(dropdown)
        end)
    end

    table.insert(dropdownCache, dropdown)

    return dropdown
end

function Dropdown.setSelected(dropdown, buttonName)
    local instance = dropdown.Instance
    local selection = instance.Selection.Clip.List
    local button = selection:FindFirstChild(buttonName)

    if button then
        instance.Label.Text = buttonName

        dropdown.Collapsed = true
        dropdown.Selected = button
        instance.Selection.Visible = false

        if dropdown.Callback then
            dropdown:Callback(button)
        end
    end
end

function Dropdown.collapse(dropdown, name)
    local instance = dropdown.Instance
    local selection = instance.Selection

    if name then
        local button = selection.Clip.List:FindFirstChild(name)

        if button then
            instance.Label.Text = button.Name

            dropdown.Selected = button

            if dropdown.Callback then
                dropdown:Callback(button)
            end
        end
    end

    selection.Visible = false
    dropdown.Collapsed = true
end

function Dropdown.addOption(dropdown, name, icon)
    name = tostring(name or "")

    if name == "" then
        return nil
    end

    local list = dropdown.Instance.Selection.Clip.List
    local existing = list:FindFirstChild(name)

    if existing and existing:IsA("TextButton") then
        return existing
    end

    local template = list:FindFirstChildWhichIsA("TextButton")

    if not template then
        return nil
    end

    local button = template:Clone()
    button.Name = name
    button.LayoutOrder = #list:GetChildren() + 1

    if button:IsA("TextButton") and button.Text ~= "" then
        button.Text = name
    end

    local label = button:FindFirstChild("Label", true)

    if label and (label:IsA("TextLabel") or label:IsA("TextButton")) then
        label.Text = name
    end

    local image = button:FindFirstChild("Icon", true)

    if icon and image and (image:IsA("ImageLabel") or image:IsA("ImageButton")) then
        image.Image = icon
        local border = image:FindFirstChild("Border")

        if border and (border:IsA("ImageLabel") or border:IsA("ImageButton")) then
            border.Image = icon
        end
    end

    button.Parent = list
    bindOption(dropdown, button)
    task.defer(function()
        refreshCanvas(dropdown)
    end)
    return button
end

function Dropdown.setCallback(dropdown, callback)
    if not dropdown.Callback then
        dropdown.Callback = callback
    end
end

-- oh.Events.DropdownCollapse = UserInput.InputEnded:Connect(function(input)
--     if input.UserInputType == Enum.UserInputType.MouseButton1 then
--         for _i, dropdown in pairs(dropdownCache) do
--             dropdown:Collapse()
--         end
--     end
-- end)

return Dropdown
