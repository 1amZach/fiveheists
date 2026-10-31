local H = Heists

local function active(id)
    local s = H.sites[id]
    if s then return s.active end
    for _, site in pairs(H.sites) do
        if site.type == id and site.active then return true end
    end
    return false
end

-- 'fleeca:legion' or a whole type like 'fleeca'
exports('isActive', active)
exports('getCooldown', function(id) return H.cooldown(id) end)
exports('resetCooldown', function(id) return H.resetCooldown(id) end)

local function duration(s)
    if s >= 3600 then return ('%dh %dm'):format(s // 3600, s % 3600 // 60) end
    if s >= 60 then return ('%dm %ds'):format(s // 60, s % 60) end
    return ('%ds'):format(s)
end

RegisterCommand('heists', function(src, args)
    if src ~= 0 and not IsPlayerAceAllowed(src, 'fiveheists.admin') then return end
    local function say(text)
        if src == 0 then print(text) else TriggerClientEvent('chat:addMessage', src, { args = { 'fiveheists', text } }) end
    end

    if args[1] == 'reset' then
        local id = args[2]
        if not id then return say('Usage: heists reset <id|type|all>') end
        if H.resetCooldown(id) then
            say(('Cooldown reset: %s'):format(id))
            H.log(src ~= 0 and src or nil, ('Reset the %s cooldown'):format(id))
        else
            say(('No cooldown on %s'):format(id))
        end
        return
    end

    local lines = {}
    for id, s in pairs(H.sites) do
        if s.active then lines[#lines + 1] = ('%s  in progress, %s left'):format(id, duration(math.max(0, s.ends - H.now()))) end
    end
    for id in pairs(H.cooldowns) do
        local left = H.cooldown(id)
        if left > 0 then lines[#lines + 1] = ('%s  cooldown %s'):format(id, duration(left)) end
    end
    if #lines == 0 then return say('Nothing in progress or on cooldown.') end
    table.sort(lines)
    for _, line in ipairs(lines) do say(line) end
end, false)
