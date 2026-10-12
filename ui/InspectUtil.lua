-- Shared, bounded presentation helpers for captured values and scanner rows.
local InspectUtil = {}

function InspectUtil.SourceURL(runtime, asset)
	runtime = runtime or {}
	assert(type(runtime) == "table", "Invalid Hydroxide source configuration")
	local owner = rawget(runtime, "Owner") or "ProtonDev-sys"
	local repository = rawget(runtime, "Repository") or "Hydroxide"
	local commit = rawget(runtime, "Commit")
	local ref = commit or rawget(runtime, "Branch") or "main"

	assert(type(owner) == "string" and owner:match("^[%w_-]+$"), "Invalid Hydroxide source owner")
	assert(type(repository) == "string" and repository:match("^[%w_.-]+$")
		and repository ~= "." and repository ~= "..", "Invalid Hydroxide source repository")
	assert(type(ref) == "string" and #ref > 0 and #ref <= 255, "Invalid Hydroxide source revision")

	if commit ~= nil then
		assert(type(commit) == "string" and #commit == 40 and commit:match("^%x+$"), "Invalid Hydroxide source commit")
		ref = commit:lower()
	end

	assert(not ref:find("^/") and not ref:find("/$") and not ref:find("//", 1, true), "Invalid Hydroxide source revision")
	for segment in ref:gmatch("[^/]+") do
		assert(segment ~= "." and segment ~= "..", "Invalid Hydroxide source revision")
	end

	assert(type(asset) == "string" and asset:match("^[%w_/-]+$")
		and not asset:find("^/") and not asset:find("/$") and not asset:find("//", 1, true), "Invalid Hydroxide source asset")
	ref = ref:gsub("[^%w%._~/-]", function(character)
		return ("%%%02X"):format(string.byte(character))
	end)
	return ("https://raw.githubusercontent.com/%s/%s/%s/%s.lua"):format(owner, repository, ref, asset)
end

local function boundedNumber(value, fallback, minimum, maximum)
	value = tonumber(value)

	if not value or value ~= value or value == math.huge or value == -math.huge then
		value = fallback
	end

	return math.max(minimum, math.min(maximum, math.floor(value)))
end

function InspectUtil.Typeof(value)
	if type(typeof) == "function" then
		local ok, result = pcall(typeof, value)

		if ok then
			return result
		end
	end

	return type(value)
end

function InspectUtil.BoundedText(value, maximum)
	local ok, text = pcall(tostring, value)
	text = ok and text or "<unprintable>"
	maximum = math.max(0, maximum)

	if #text > maximum then
		local marker = ("..."):sub(1, maximum)
		return text:sub(1, maximum - #marker) .. marker
	end

	return text
end

function InspectUtil.PackedCount(values)
	if type(values) ~= "table" then
		return 0
	end

	local count = rawget(values, "n")

	if count == nil then
		local ok, length = pcall(function()
			return #values
		end)
		count = ok and length or 0
	end

	return boundedNumber(count, 0, 0, 1000000)
end

function InspectUtil.InstancePath(value)
	if InspectUtil.Typeof(value) ~= "Instance" or type(getInstancePath) ~= "function" then
		return nil
	end

	local ok, path = pcall(getInstancePath, value)
	return ok and type(path) == "string" and InspectUtil.BoundedText(path, 8192) or nil
end

function InspectUtil.Summary(value)
	local settings = oh and oh.Settings or {}
	local maximum = boundedNumber(settings.MaxArgumentPreviewLength, 140, 40, 2000)

	if type(value) == "table" and rawget(value, "__hydroxideCaptureMarker") == true then
		return InspectUtil.BoundedText(
			InspectUtil.BoundedText(rawget(value, "Kind") or "value", maximum)
				.. " capture unavailable: "
				.. InspectUtil.BoundedText(rawget(value, "Detail") or "unknown reason", maximum),
			maximum
		)
	end

	if type(summarizeValue) == "function" then
		local ok, text = pcall(summarizeValue, value, maximum)

		if ok and type(text) == "string" then
			return InspectUtil.BoundedText(text, maximum)
		end
	end

	local rawType = type(value)
	local valueType = InspectUtil.Typeof(value)

	if rawType == "string" then
		local text = value:sub(1, maximum):gsub("[%c]", function(character)
			return ({ ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" })[character] or "?"
		end)
		return '"' .. InspectUtil.BoundedText(text, maximum - 2) .. '"'
	elseif rawType == "table" then
		local count = 0

		for _ in next, value do
			count = count + 1

			if count >= 100 then
				return "table (100+ entries)"
			end
		end

		return ("table (%d entries)"):format(count)
	elseif rawType == "function" then
		return "function"
	elseif valueType == "Instance" then
		local ok, fullName = pcall(function()
			return value:GetFullName()
		end)
		return InspectUtil.BoundedText(ok and fullName or "Instance", maximum)
	end

	return InspectUtil.BoundedText(value, maximum)
end

local function expandedValue(value, maximumBytes)
	local valueType = InspectUtil.Typeof(value)

	if type(formatValueTree) ~= "function"
		or type(value) ~= "table"
		or (valueType ~= "table" and valueType ~= "SharedTable")
		or rawget(value, "__hydroxideCaptureMarker") == true
	then
		return nil
	end

	local settings = oh and oh.Settings or {}
	local ok, text = pcall(formatValueTree, value, {
		MaxDepth = settings.MaxValueViewDepth or settings.maxValueViewDepth,
		MaxEntries = settings.MaxValueViewEntries or settings.maxValueViewEntries,
		MaxTableEntries = settings.MaxValueViewTableEntries or settings.maxValueViewTableEntries,
		MaxOutputBytes = maximumBytes,
	})

	if not ok then
		return "<table inspection failed: " .. InspectUtil.BoundedText(text, math.min(240, maximumBytes)) .. ">"
	elseif type(text) == "string" and text ~= "" then
		return InspectUtil.BoundedText(text, maximumBytes)
	end
end

function InspectUtil.DescribePackedValues(title, values)
	local settings = oh and oh.Settings or {}
	local maximum = boundedNumber(settings.MaxValueViewBytes or settings.maxValueViewBytes, 65536, 1, 1048576)
	local count = InspectUtil.PackedCount(values)
	local lines, bytes = {}, 0
	local stopped = false

	local function append(text)
		if stopped then
			return false
		end

		local separator = #lines > 0 and 1 or 0
		local remaining = maximum - bytes - separator

		if #text > remaining then
			stopped = true
			text = "... <value viewer output limit reached>"
			text = text:sub(1, math.max(0, remaining))
		end

		if remaining >= 0 then
			lines[#lines + 1] = text
			bytes = bytes + separator + #text
		end

		return not stopped
	end

	append(InspectUtil.BoundedText(title, maximum))
	append(("Count: %d"):format(count))
	append("")

	if count == 0 then
		append("(none)")
	end

	for index = 1, count do
		if stopped then
			break
		end

		local value = rawget(values, index)
		local valueType = InspectUtil.Typeof(value)
		local header = ("[%02d]  %s"):format(index, valueType)
		local remaining = maximum - bytes - #header - 3

		if remaining < 256 then
			append("... <value viewer output limit reached>")
			break
		end

		local expanded = expandedValue(value, remaining)

		if expanded then
			append(header)
			append(expanded)
			append("")
		else
			local detail = valueType == "Instance" and InspectUtil.InstancePath(value) or nil
			append(("%-24s  %s"):format(header, detail or InspectUtil.Summary(value)))
		end
	end

	return table.concat(lines, "\n")
end

function InspectUtil.Timestamp(timestamp)
	if type(timestamp) ~= "number" or timestamp ~= timestamp or math.abs(timestamp) == math.huge then
		return "unknown"
	end

	local rounded = math.floor(timestamp * 1000 + 0.5)
	local seconds = math.floor(rounded / 1000)
	local milliseconds = rounded - seconds * 1000
	local ok, formatted = pcall(os.date, "%Y-%m-%d %H:%M:%S", seconds)

	if ok and type(formatted) == "string" then
		return ("%s.%03d local"):format(formatted, milliseconds)
	end

	return ("%.3f"):format(timestamp)
end

function InspectUtil.CleanSource(source)
	return type(source) == "string" and source:gsub("^%s+", ""):gsub("%s+$", ""):gsub("^[@=]", "") or "unknown"
end

function InspectUtil.RowComesBefore(left, right)
	return left.Sort == right.Sort and left.Stable < right.Stable or left.Sort < right.Sort
end

function InspectUtil.AddBoundedRow(rows, row, limit)
	if #rows < limit then
		rows[#rows + 1] = row
		local child = #rows

		while child > 1 do
			local parent = math.floor(child / 2)

			if not InspectUtil.RowComesBefore(rows[parent], rows[child]) then
				break
			end

			rows[parent], rows[child] = rows[child], rows[parent]
			child = parent
		end

		return
	elseif limit <= 0 or not InspectUtil.RowComesBefore(row, rows[1]) then
		return
	end

	rows[1] = row
	local parent = 1

	while true do
		local left, right, greatest = parent * 2, parent * 2 + 1, parent

		if left <= #rows and InspectUtil.RowComesBefore(rows[greatest], rows[left]) then
			greatest = left
		end

		if right <= #rows and InspectUtil.RowComesBefore(rows[greatest], rows[right]) then
			greatest = right
		end

		if greatest == parent then
			return
		end

		rows[parent], rows[greatest] = rows[greatest], rows[parent]
		parent = greatest
	end
end

return InspectUtil
