local Scanner = {}

function Scanner.checkpoint(options)
	options = type(options) == "table" and options or {}
	local isCancelled = type(options.IsCancelled) == "function" and options.IsCancelled or nil
	local yieldEvery = tonumber(options.YieldEvery)
	if not yieldEvery or yieldEvery ~= yieldEvery then
		yieldEvery = 128
	end
	yieldEvery = math.floor(math.max(16, math.min(4096, yieldEvery)))
	local wait = options.Yield ~= false and task and type(task.wait) == "function" and task.wait or nil
	local work = 0
	return function(checkOnly)
		if not checkOnly then
			work = work + 1
			if work % yieldEvery ~= 0 then
				return false
			end
			if wait then
				wait()
			end
		end
		return isCancelled and not not isCancelled() or false
	end
end

function Scanner.new(Model, methodName, resolveMethod, className)
	local scanner = { RequiredMethods = { [methodName] = true } }

	function scanner.Enumerate(query, callback, options)
		query = tostring(query or ""):lower()
		callback = type(callback) == "function" and callback or nil
		local checkpoint = Scanner.checkpoint(options)

		if checkpoint(true) then
			return 0, true
		end
		local method = resolveMethod()
		if type(method) ~= "function" then
			error(methodName .. " is not available in this executor", 0)
		end
		local ok, instances = pcall(method)
		if not ok then
			local printable, detail = pcall(tostring, instances)
			error(methodName .. " failed: " .. (printable and detail:sub(1, 2048) or "unprintable error"), 0)
		elseif type(instances) ~= "table" then
			error(methodName .. " did not return a table", 0)
		end
		-- A provider can yield; do not publish rows for a superseded request.
		if checkpoint(true) then
			return 0, true
		end

		local seen, matched = {}, 0
		for _, instance in next, instances do
			if typeof(instance) == "Instance" and not seen[instance] then
				seen[instance] = true
				if instance:IsA(className) and instance.Name:lower():find(query, 1, true) then
					matched = matched + 1
					if callback then
						callback(instance, matched)
					end
				end
			end
			if checkpoint() then
				return matched, true
			end
		end
		return matched, checkpoint(true)
	end

	function scanner.Scan(query)
		local models = {}
		scanner.Enumerate(query, function(instance)
			models[instance] = Model.new(instance)
		end, { Yield = false })
		return models
	end

	return scanner
end

return Scanner
