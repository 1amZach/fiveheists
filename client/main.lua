local labels = {
    register = 'Picking the register',
    code = 'Opening the safe',
    drill = 'Drilling the safe',
    atm = 'Drilling the ATM',
    panel = 'Hacking the panel',
    box = 'Emptying the deposit box',
    case = 'Smashing the case',
}

local drill = { model = 'hei_prop_heist_drill', bone = 57005, pos = vec3(0.14, 0.0, -0.01), rot = vec3(90.0, -90.0, 180.0) }

local anims = {
    register = { anim = { dict = 'veh@break_in@0h@p_m_one@', clip = 'low_force_entry_ds', flag = 1 } },
    code = { anim = { dict = 'mini@safe_cracking', clip = 'idle_base', flag = 1 } },
    drill = { anim = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle', flag = 1 }, prop = drill },
    atm = { anim = { dict = 'anim@heists@fleeca_bank@drilling', clip = 'drill_straight_idle', flag = 1 }, prop = drill },
    panel = { anim = { dict = 'mp_prison_break', clip = 'hack_loop', flag = 1 } },
    box = { anim = { dict = 'anim@heists@ornate_bank@grab_cash', clip = 'grab', flag = 1 } },
    case = { anim = { dict = 'missheist_jewel', clip = 'smash_case', flag = 0 } },
}

local function notify(text, kind)
    lib.notify({ description = text, type = kind })
end

-- Ask the server, play it out, tell the server how it went. The server
-- decides everything else.
local function rob(id, key, extra)
    if Interact.busy then return end
    Interact.busy = true

    local ok, info = lib.callback.await('fiveheists:begin', false, id, key, extra)
    if not ok then
        Interact.busy = false
        if info then notify(info, 'error') end
        return
    end

    local result = 'done'
    if info.checks and #info.checks > 0 and not lib.skillCheck(info.checks) then result = 'failed' end

    if result == 'done' then
        local look = anims[info.mode or info.kind] or {}
        local finished = lib.progressCircle({
            duration = info.duration,
            label = labels[info.mode or info.kind],
            position = 'bottom',
            canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = look.anim,
            prop = look.prop,
        })
        if not finished then result = 'cancel' end
    end

    local done, msg = lib.callback.await('fiveheists:finish', false, info.id, key, result)
    Interact.busy = false
    if msg then notify(msg, done and 'success' or 'error') end
end

-- ------------------------------------------------------------------ stores

for _, l in ipairs(Config.store.locations) do
    local id = 'store:' .. l.id
    for i, c in ipairs(l.registers) do
        Interact.add(id .. ':register' .. i, c, 'Register', {
            { label = 'Pick the register', icon = 'fa-solid fa-cash-register', onSelect = function() rob(id, 'register' .. i) end },
        })
    end
    if l.safe then
        Interact.add(id .. ':safe', l.safe, 'Safe', {
            { label = 'Enter a code', icon = 'fa-solid fa-keyboard', onSelect = function()
                local input = lib.inputDialog('Safe', { { type = 'input', label = 'Code', required = true, max = 8 } })
                if input and input[1] then rob(id, 'safe', { code = input[1] }) end
            end },
            { label = 'Drill the safe', icon = 'fa-solid fa-screwdriver', onSelect = function() rob(id, 'safe') end },
        })
    end
end

-- -------------------------------------------------------------------- ATMs

local atm = { { label = 'Drill the ATM', icon = 'fa-solid fa-money-bill', onSelect = function(entity)
    local c = GetEntityCoords(entity)
    rob('atm:any', 'atm', { coords = { x = c.x, y = c.y, z = c.z } })
end } }

if Config.atm.anyModel then
    Interact.models('atm', Config.atm.models, 'ATM', atm)
else
    for i, c in ipairs(Config.atm.locations) do
        Interact.add('atm:' .. i, c, 'ATM', {
            { label = 'Drill the ATM', icon = 'fa-solid fa-money-bill', onSelect = function() rob('atm:' .. i, 'atm') end },
        })
    end
end

-- ------------------------------------------------------------------ Fleeca

local function vaultOpen(bank) return (GlobalState['fiveheists:vaults'] or {})[bank] == true end

for _, b in ipairs(Config.fleeca.banks) do
    local id = 'fleeca:' .. b.id
    Interact.add(id .. ':panel', b.panel, 'Vault panel', {
        { label = 'Hack the panel', icon = 'fa-solid fa-laptop-code', canInteract = function() return not vaultOpen(b.id) end, onSelect = function() rob(id, 'panel') end },
    })
    for i, c in ipairs(b.boxes) do
        Interact.add(id .. ':box' .. i, c, 'Deposit box', {
            { label = 'Open the deposit box', icon = 'fa-solid fa-box-open', canInteract = function() return vaultOpen(b.id) end, onSelect = function() rob(id, 'box' .. i) end },
        })
    end
end

local doorModel = GetHashKey(Config.fleeca.door)

local function turn(from, to) return (to - from + 540.0) % 360.0 - 180.0 end

-- Doors stream in and out, so keep putting nearby ones where they should be.
CreateThread(function()
    while true do
        local open, pos = GlobalState['fiveheists:vaults'] or {}, GetEntityCoords(cache.ped)
        for _, b in ipairs(Config.fleeca.banks) do
            if #(pos - b.door) < 60.0 then
                local door = GetClosestObjectOfType(b.door.x, b.door.y, b.door.z, 2.0, doorModel, false, false, false)
                if door ~= 0 then
                    FreezeEntityPosition(door, true)
                    local from = GetEntityHeading(door)
                    local d = turn(from, open[b.id] and b.open or b.closed)
                    if math.abs(d) > 1.0 then
                        for i = 1, 60 do
                            SetEntityHeading(door, from + d * i / 60)
                            Wait(25)
                        end
                    end
                end
            end
        end
        Wait(1000)
    end
end)

-- ----------------------------------------------------------------- jewelry

local unarmed = GetHashKey('WEAPON_UNARMED')

for _, j in ipairs(Config.jewelry.stores) do
    local id = 'jewelry:' .. j.id
    for i, c in ipairs(j.cases) do
        Interact.add(id .. ':case' .. i, c, 'Case', {
            { label = 'Smash the case', icon = 'fa-solid fa-gem', canInteract = function() return GetSelectedPedWeapon(cache.ped) ~= unarmed end, onSelect = function() rob(id, 'case' .. i) end },
        })
    end
end

-- ---------------------------------------------------------------- dispatch

RegisterNetEvent('fiveheists:alert', function(data)
    local a, c = Config.alert, data.coords
    notify(('Robbery in progress: %s'):format(data.label), 'inform')
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', false)

    local blip = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(blip, a.sprite)
    SetBlipColour(blip, a.color)
    SetBlipScale(blip, a.scale)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(data.label)
    EndTextCommandSetBlipName(blip)
    SetTimeout(a.seconds * 1000, function() RemoveBlip(blip) end)
end)
