local ValueSnapshot = {}

-- Each spy owns its diagnostics and budget; capture semantics stay identical.
function ValueSnapshot.new(limits, diagnostics)
    local maxCapturedCallBytes = limits.Bytes
    local maxCapturedArguments = limits.Arguments
    local maxCapturedBufferBytes = limits.BufferBytes
    local maxCapturedTableEntries = limits.TableEntries
    local maxCapturedTableDepth = limits.TableDepth
    local maxCapturedBufferPreviewBytes = limits.PreviewBytes

    local function makeCaptureMarker(kind, detail)
        return {
            __hydroxideCaptureMarker = true,
            Kind = kind,
            Detail = detail
        }
    end

    local function readBufferPreview(value, length, maximum)
        if not buffer or type(buffer.readu8) ~= "function" then
            return nil
        end

        local shown = math.min(length, maximum or maxCapturedBufferPreviewBytes)
        local parts = {}
        local ran = pcall(function()
            for offset = 0, shown - 1 do
                parts[offset + 1] = string.char(buffer.readu8(value, offset))
            end
        end)

        return ran and table.concat(parts) or nil
    end

    local function reserveCaptureBytes(state, amount)
        amount = math.max(0, math.floor(tonumber(amount) or 0))

        if state.Bytes + amount > maxCapturedCallBytes then
            state.Replayable = false
            state.Truncated = true
            return false
        end

        state.Bytes = state.Bytes + amount
        return true
    end

    local function addBoundedBufferPreview(marker, value, length, state)
        local remaining = math.max(0, maxCapturedCallBytes - state.Bytes)
        local shown = math.min(length, maxCapturedBufferPreviewBytes, remaining)

        if shown > 0 then
            marker.Preview = readBufferPreview(value, length, shown)

            if marker.Preview then
                reserveCaptureBytes(state, #marker.Preview)
            end
        end
    end

    local function snapshotBuffer(value, state)
        if not buffer
            or type(buffer.len) ~= "function"
            or type(buffer.tostring) ~= "function"
            or type(buffer.fromstring) ~= "function"
        then
            diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
            state.Replayable = false
            return makeCaptureMarker("buffer", "Buffer copy APIs are unavailable")
        end

        local measured, length = pcall(buffer.len, value)

        if not measured
            or type(length) ~= "number"
            or length ~= length
            or length < 0
            or length == math.huge
            or length % 1 ~= 0
        then
            diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
            state.Replayable = false
            return makeCaptureMarker("buffer", "Buffer length could not be read")
        elseif length > maxCapturedBufferBytes then
            diagnostics.BufferSnapshotsTruncated = diagnostics.BufferSnapshotsTruncated + 1
            state.Replayable = false
            state.Truncated = true
            local marker = makeCaptureMarker(
                "buffer",
                ("%d-byte buffer exceeds the %d-byte capture limit"):format(length, maxCapturedBufferBytes)
            )
            marker.Size = length
            addBoundedBufferPreview(marker, value, length, state)
            return marker
        elseif not reserveCaptureBytes(state, length) then
            diagnostics.BufferSnapshotsTruncated = diagnostics.BufferSnapshotsTruncated + 1
            local marker = makeCaptureMarker(
                "buffer",
                ("Aggregate call capture exceeds the %d-byte limit"):format(maxCapturedCallBytes)
            )
            marker.Size = length
            addBoundedBufferPreview(marker, value, length, state)
            return marker
        end

        local copied, bytes = pcall(buffer.tostring, value)

        if not copied or type(bytes) ~= "string" or #bytes ~= length then
            diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
            state.Replayable = false
            return makeCaptureMarker("buffer", "Buffer contents could not be copied")
        end

        local rebuilt, snapshot = pcall(buffer.fromstring, bytes)

        if not rebuilt or typeof(snapshot) ~= "buffer" then
            diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
            state.Replayable = false
            return makeCaptureMarker("buffer", "Buffer snapshot could not be created")
        end

        local measuredSnapshot, snapshotLength = pcall(buffer.len, snapshot)

        if not measuredSnapshot or snapshotLength ~= length then
            diagnostics.BufferSnapshotFailures = diagnostics.BufferSnapshotFailures + 1
            state.Replayable = false
            return makeCaptureMarker("buffer", "Buffer snapshot length did not match the source")
        end

        diagnostics.BuffersSnapshotted = diagnostics.BuffersSnapshotted + 1
        return snapshot
    end

    local function snapshotPackedValues(values, initialBytes)
        local state = {
            Replayable = true,
            Entries = 0,
            Bytes = math.min(
                maxCapturedCallBytes,
                math.max(0, math.floor(tonumber(initialBytes) or 0))
            ),
            Truncated = false
        }
        local seen = {}

        local clone
        clone = function(value, depth)
            local valueType = typeof(value)

            if valueType == "buffer" then
                if not seen[value] then
                    seen[value] = snapshotBuffer(value, state)
                end
                return seen[value]
            elseif type(value) == "string" then
                if reserveCaptureBytes(state, #value) then
                    return value
                end

                local marker = makeCaptureMarker(
                    "string",
                    ("Aggregate call capture exceeds the %d-byte limit"):format(maxCapturedCallBytes)
                )
                marker.Size = #value
                local remaining = math.max(0, maxCapturedCallBytes - state.Bytes)
                local shown = math.min(#value, maxCapturedBufferPreviewBytes, remaining)

                if shown > 0 then
                    marker.Preview = value:sub(1, shown)
                    reserveCaptureBytes(state, #marker.Preview)
                end

                return marker
            elseif type(value) ~= "table" then
                return value
            elseif seen[value] then
                return seen[value]
            elseif depth >= maxCapturedTableDepth then
                state.Replayable = false
                state.Truncated = true
                return makeCaptureMarker("table", "Nested table exceeds the capture depth limit")
            end

            local copy = {}
            seen[value] = copy

            for key, nestedValue in next, value do
                state.Entries = state.Entries + 1

                if state.Entries > maxCapturedTableEntries then
                    state.Replayable = false
                    state.Truncated = true
                    copy.__hydroxideCaptureLimit = "Additional entries were omitted by the capture limit"
                    break
                end

                copy[clone(key, depth + 1)] = clone(nestedValue, depth + 1)
            end

            return copy
        end

        local originalCount = type(values) == "table" and tonumber(rawget(values, "n")) or nil

        if not originalCount
            or originalCount ~= originalCount
            or originalCount == math.huge
            or originalCount == -math.huge
        then
            originalCount = type(values) == "table" and #values or 0
        end

        originalCount = math.max(0, math.floor(originalCount))
        local count = math.min(originalCount, maxCapturedArguments)
        local snapshot = { n = count }

        for index = 1, count do
            snapshot[index] = clone(rawget(values, index), 0)
        end

        if originalCount > count then
            state.Replayable = false
            state.Truncated = true
            snapshot.n = count + 1
            snapshot[count + 1] = makeCaptureMarker(
                "arguments",
                ("%d additional arguments were omitted by the capture limit"):format(originalCount - count)
            )
        end

        if state.Truncated then
            diagnostics.CallSnapshotsTruncated = diagnostics.CallSnapshotsTruncated + 1
        end

        return snapshot, state.Replayable, state.Bytes
    end

    return snapshotPackedValues
end

return ValueSnapshot
