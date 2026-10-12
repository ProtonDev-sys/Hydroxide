local Upvalue = {}

function Upvalue.new(closure, index, value)
    local upvalue = {}

    upvalue.Closure = closure
    upvalue.Index = index
    upvalue.Value = value
    upvalue.Set = Upvalue.set
    upvalue.Update = Upvalue.update

    return upvalue
end

function Upvalue.set(upvalue, value)
    setUpvalue(upvalue.Closure.Data, upvalue.Index, value)
    Upvalue.update(upvalue, value)
end

function Upvalue.update(upvalue, ...)
    local value
    if select("#", ...) > 0 then
        value = ...
    else
        value = getUpvalue(upvalue.Closure.Data, upvalue.Index)
    end
    local scanned = upvalue.Scanned

    upvalue.Value = value

    if type(value) ~= "table" and scanned then
        upvalue.Scanned = nil
    elseif scanned then
        for key in next, scanned do
            scanned[key] = rawget(value, key)
        end
    end
end

return Upvalue
