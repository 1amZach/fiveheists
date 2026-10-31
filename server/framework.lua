-- Money, items and jobs from whichever framework is running. Items go through
-- ox_inventory when it's started, otherwise the framework's own inventory.

Framework = {}

local function started(name) return GetResourceState(name) == 'started' end

local qbCore, esx

local function player(src)
    if started('qbx_core') then return exports.qbx_core:GetPlayer(src), 'qb' end
    if started('qb-core') then
        qbCore = qbCore or exports['qb-core']:GetCoreObject()
        return qbCore.Functions.GetPlayer(src), 'qb'
    end
    if started('es_extended') then
        esx = esx or exports.es_extended:getSharedObject()
        return esx.GetPlayerFromId(src), 'esx'
    end
end

local function ox() return started('ox_inventory') end
-- newer qb-inventory took items off the player object
local function qbInv() return started('qb-inventory') end

function Framework.name()
    return started('qbx_core') and 'qbx' or started('qb-core') and 'qb' or started('es_extended') and 'esx' or nil
end

function Framework.count(src, name)
    if ox() then return exports.ox_inventory:GetItemCount(src, name) or 0 end
    local p, kind = player(src)
    if not p then return 0 end
    if kind == 'esx' then
        local item = p.getInventoryItem(name)
        return item and item.count or 0
    end
    if qbInv() then return exports['qb-inventory']:GetItemCount(src, name) or 0 end
    local item = p.Functions.GetItemByName(name)
    return item and (item.amount or item.count) or 0
end

function Framework.hasItem(src, name, count)
    return Framework.count(src, name) >= (count or 1)
end

function Framework.removeItem(src, name, count)
    count = count or 1
    if ox() then return exports.ox_inventory:RemoveItem(src, name, count) and true or false end
    local p, kind = player(src)
    if not p then return false end
    if kind == 'esx' then
        p.removeInventoryItem(name, count)
        return true
    end
    if qbInv() then return exports['qb-inventory']:RemoveItem(src, name, count, false, 'fiveheists') and true or false end
    return p.Functions.RemoveItem(name, count) and true or false
end

function Framework.addItem(src, name, count, meta)
    count = count or 1
    if ox() then
        if not exports.ox_inventory:CanCarryItem(src, name, count, meta) then return false end
        return exports.ox_inventory:AddItem(src, name, count, meta) and true or false
    end
    local p, kind = player(src)
    if not p then return false end
    if kind == 'esx' then
        if p.canCarryItem and not p.canCarryItem(name, count) then return false end
        p.addInventoryItem(name, count)
        return true
    end
    if qbInv() then
        if not exports['qb-inventory']:CanAddItem(src, name, count) then return false end
        return exports['qb-inventory']:AddItem(src, name, count, false, meta, 'fiveheists') and true or false
    end
    return p.Functions.AddItem(name, count, false, meta) and true or false
end

function Framework.addMoney(src, amount, reason)
    local m = Config.money
    if m.item then
        if m.worth then return Framework.addItem(src, m.item, 1, { worth = amount }) end
        return Framework.addItem(src, m.item, amount)
    end
    local p, kind = player(src)
    if not p then return false end
    if kind == 'esx' then
        p.addAccountMoney(m.account == 'cash' and 'money' or m.account, amount, reason)
    else
        p.Functions.AddMoney(m.account, amount, reason)
    end
    return true
end

-- job name and whether they're on duty
function Framework.job(src)
    local p, kind = player(src)
    if not p then return end
    if kind == 'esx' then
        local job = p.getJob() or {}
        return job.name, job.onDuty ~= false
    end
    local job = (p.PlayerData or p).job or {}
    return job.name, job.onduty ~= false
end

local function isPolice(job)
    for _, j in ipairs(Config.policeJobs) do
        if j == job then return true end
    end
    return false
end

-- every on-duty police player
function Framework.police()
    local out = {}
    local function add(src, job, duty)
        if duty and isPolice(job) then out[#out + 1] = tonumber(src) end
    end

    if started('qbx_core') or started('qb-core') then
        local list
        if started('qbx_core') then
            list = exports.qbx_core:GetQBPlayers()
        else
            qbCore = qbCore or exports['qb-core']:GetCoreObject()
            list = qbCore.Functions.GetQBPlayers()
        end
        for src, p in pairs(list or {}) do
            local d = p.PlayerData or p
            local job = d.job or {}
            add(d.source or src, job.name, job.onduty ~= false)
        end
    elseif started('es_extended') then
        esx = esx or exports.es_extended:getSharedObject()
        for _, x in pairs(esx.GetExtendedPlayers()) do
            local job = x.getJob() or {}
            add(x.source, job.name, job.onDuty ~= false)
        end
    end
    table.sort(out)
    return out
end

function Framework.label(name)
    if ox() then
        local item = exports.ox_inventory:Items(name)
        if item and item.label then return item.label end
    end
    return (name:gsub('_', ' '))
end
