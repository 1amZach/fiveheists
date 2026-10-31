-- ox_target when it's running, otherwise an ox_lib zone with text UI and E.
-- options: { { label, icon, onSelect, canInteract }, ... }

Interact = {}

local useTarget = GetResourceState('ox_target') == 'started'
local shown

local function usable(options, entity)
    local list = {}
    for _, o in ipairs(options) do
        if not o.canInteract or o.canInteract(entity) then list[#list + 1] = o end
    end
    return list
end

local function choose(title, options, entity)
    local list = usable(options, entity)
    if #list == 0 then return end
    if #list == 1 then return list[1].onSelect(entity) end
    local menu = {}
    for i, o in ipairs(list) do
        menu[i] = { title = o.label, icon = o.icon, onSelect = function() o.onSelect(entity) end }
    end
    lib.registerContext({ id = 'fiveheists:choose', title = title, options = menu })
    lib.showContext('fiveheists:choose')
end

local function show(title)
    if shown == title then return end
    shown = title
    lib.showTextUI(('[E] %s'):format(title))
end

local function hide()
    if not shown then return end
    shown = nil
    lib.hideTextUI()
end

local function targetOptions(name, options)
    local out = {}
    for i, o in ipairs(options) do
        out[i] = {
            name = ('%s:%d'):format(name, i),
            label = o.label,
            icon = o.icon,
            distance = Config.reach,
            canInteract = o.canInteract and function(entity) return o.canInteract(entity) end,
            onSelect = function(data) o.onSelect(data.entity) end,
        }
    end
    return out
end

function Interact.add(name, coords, title, options)
    if useTarget then
        return exports.ox_target:addSphereZone({ coords = coords, radius = 0.6, options = targetOptions(name, options) })
    end
    lib.zones.sphere({
        coords = coords,
        radius = 1.0,
        inside = function()
            if Interact.busy or #usable(options) == 0 then return hide() end
            show(title)
            if IsControlJustReleased(0, 38) then
                hide()
                choose(title, options)
            end
        end,
        onExit = hide,
    })
end

-- Any prop of these models, like every ATM on the map.
function Interact.models(name, models, title, options)
    local hashes = {}
    for i, m in ipairs(models) do hashes[i] = type(m) == 'string' and GetHashKey(m) or m end

    if useTarget then
        return exports.ox_target:addModel(hashes, targetOptions(name, options))
    end

    CreateThread(function()
        while true do
            local pos, found = GetEntityCoords(cache.ped), 0
            for _, h in ipairs(hashes) do
                found = GetClosestObjectOfType(pos.x, pos.y, pos.z, 1.5, h, false, false, false)
                if found ~= 0 then break end
            end
            if found == 0 or Interact.busy then
                if shown == title then hide() end
                Wait(500)
            else
                show(title)
                if IsControlJustReleased(0, 38) then
                    hide()
                    choose(title, options, found)
                end
                Wait(0)
            end
        end
    end)
end
