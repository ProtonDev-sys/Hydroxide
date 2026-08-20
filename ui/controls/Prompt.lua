local UserInputService = game:GetService("UserInputService")

local ControlUtil = import("ui/ControlUtil")
local Theme = (oh and oh.Theme) or import("ui/Theme")
local Prompts = import("rbxassetid://11389137937").Base.Prompts

local Prompt = {}
local currentPrompt

local function firstFocusable(root)
	local descendants = root:GetDescendants()

	for _, descendant in ipairs(descendants) do
		if descendant:IsA("TextBox") and descendant.Visible then
			return descendant
		end
	end

	for _, descendant in ipairs(descendants) do
		if descendant:IsA("GuiButton") and descendant.Visible and descendant.Selectable then
			return descendant
		end
	end
end

function Prompt.new(instance)
	assert(instance and instance:IsA("GuiObject"), "Prompt.new expects a GuiObject")

	local prompt = {
		Instance = instance,
		Visible = false,
	}

	prompt.Show = Prompt.show
	prompt.Hide = Prompt.hide
	prompt.SetOnShow = Prompt.setOnShow
	prompt.SetOnHide = Prompt.setOnHide
	prompt.Destroy = Prompt.destroy

	Theme.Apply(instance)
	instance.Visible = false
	return prompt
end

function Prompt.show(prompt)
	if currentPrompt and currentPrompt ~= prompt then
		currentPrompt:Hide()
	end

	currentPrompt = prompt
	prompt.Visible = true
	Prompts.PromptShadow.Visible = true
	prompt.Instance.Visible = true
	local focusObject = firstFocusable(prompt.Instance)

	if focusObject and focusObject:IsA("TextBox") then
		pcall(function()
			focusObject:CaptureFocus()
		end)
	else
		ControlUtil.SetSelectedObject(focusObject)
	end

	ControlUtil.RunCallback("Prompt show callback failed", prompt.OnShow, prompt)
	return true
end

function Prompt.hide(prompt)
	if not prompt then
		return false
	end

	prompt.Visible = false

	if prompt.Instance then
		prompt.Instance.Visible = false
	end

	if currentPrompt == prompt then
		currentPrompt = nil
		Prompts.PromptShadow.Visible = false
	end

	ControlUtil.RunCallback("Prompt hide callback failed", prompt.OnHide, prompt)
	return true
end

function Prompt.setOnShow(prompt, callback)
	assert(callback == nil or type(callback) == "function", "Prompt OnShow must be a function or nil")
	prompt.OnShow = callback
	return prompt
end

function Prompt.setOnHide(prompt, callback)
	assert(callback == nil or type(callback) == "function", "Prompt OnHide must be a function or nil")
	prompt.OnHide = callback
	return prompt
end

function Prompt.destroy(prompt)
	prompt:Hide()
	prompt.Instance = nil
	prompt.OnShow = nil
	prompt.OnHide = nil
end

ControlUtil.TrackConnection(UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and currentPrompt and input.KeyCode == Enum.KeyCode.Escape then
		currentPrompt:Hide()
	end
end))

return Prompt
