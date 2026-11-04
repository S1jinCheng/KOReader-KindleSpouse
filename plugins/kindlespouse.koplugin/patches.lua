local logger = require("logger")
local Patches = { applied = {}, order = {} }

function Patches.wrap(id, target, name, replacement)
    assert(not Patches.applied[id], "KindleSpouse: duplicate patch " .. id)
    local original = target[name]
    assert(type(original) == "function", "KindleSpouse: missing upstream method " .. name)
    local entry = { target = target, name = name, original = original, own = rawget(target, name), active = true }
    entry.wrapper = function(...)
        if not entry.active then return original(...) end
        return replacement(original, ...)
    end
    target[name] = entry.wrapper
    Patches.applied[id] = entry
    Patches.order[#Patches.order+1] = id
    return entry.wrapper
end

function Patches.revert(id)
    local entry = Patches.applied[id]
    if not entry then return end
    entry.active = false
    if entry.target[entry.name] == entry.wrapper then entry.target[entry.name] = entry.own
    else logger.dbg("KindleSpouse:", "preserved later wrapper while disabling patch", id) end
    Patches.applied[id] = nil
    for index = #Patches.order, 1, -1 do if Patches.order[index] == id then table.remove(Patches.order, index) end end
end

function Patches.revertPrefix(prefix)
    for index = #Patches.order, 1, -1 do
        local id = Patches.order[index]
        if id:sub(1, #prefix) == prefix then Patches.revert(id) end
    end
end

function Patches.revertAll()
    for index = #Patches.order, 1, -1 do Patches.revert(Patches.order[index]) end
    Patches.order = {}
end

function Patches.scope(target) return "home:" .. tostring(target) .. ":" end
return Patches
