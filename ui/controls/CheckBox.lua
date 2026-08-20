local ControlUtil = import("ui/ControlUtil")

local CheckBox = {}

local function render(checkBox)
	if checkBox.Label then
		checkBox.Label.Text = checkBox.Enabled and "✓" or ""
	end

	pcall(function()
		checkBox.Instance:SetAttribute("Checked", checkBox.Enabled)
	end)
end

function CheckBox.new(instance)
	assert(instance, "CheckBox.new requires an instance")

	local toggle = instance:FindFirstChild("Toggle") or instance
	assert(toggle:IsA("GuiButton"), "CheckBox toggle must be a GuiButton")

	local label = toggle:FindFirstChild("Label")
	assert(label and (label:IsA("TextLabel") or label:IsA("TextButton")), "CheckBox toggle requires a Label")

	local checkBox = {
		Enabled = label.Text == "✓",
		Instance = instance,
		Label = label,
		ToggleButton = toggle,
	}

	checkBox.SetCallback = CheckBox.setCallback
	checkBox.SetEnabled = CheckBox.setEnabled
	checkBox.Toggle = CheckBox.toggle
	checkBox.Destroy = CheckBox.destroy

	checkBox.Connection = ControlUtil.ConnectActivated(toggle, function()
		checkBox:Toggle(true)
	end)

	render(checkBox)
	return checkBox
end

function CheckBox.setCallback(checkBox, callback)
	assert(callback == nil or type(callback) == "function", "CheckBox callback must be a function or nil")
	checkBox.Callback = callback
	return checkBox
end

function CheckBox.setEnabled(checkBox, enabled, notify)
	enabled = enabled == true

	if checkBox.Enabled == enabled then
		render(checkBox)
		return false
	end

	checkBox.Enabled = enabled
	render(checkBox)

	if notify and checkBox.Callback then
		ControlUtil.RunCallback("CheckBox callback failed", checkBox.Callback, enabled)
	end

	return true
end

function CheckBox.toggle(checkBox, notify)
	return checkBox:SetEnabled(not checkBox.Enabled, notify ~= false)
end

function CheckBox.destroy(checkBox)
	if checkBox.Connection then
		pcall(function()
			checkBox.Connection:Disconnect()
		end)
		checkBox.Connection = nil
	end

	checkBox.Callback = nil
end

return CheckBox
