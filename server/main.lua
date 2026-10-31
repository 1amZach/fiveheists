-- The client only asks. Every robbery step is two calls: begin, which checks
-- everything and remembers what the player is doing, then finish, which checks
-- it again, makes sure enough time passed and pays out. Amounts never come from
-- the client.

Heists = { sites = {}, players = {}, cooldowns = {}, boardState = {} }
local H = Heists

local types = { store = Config.store, atm = Config.atm, fleeca = Config.fleeca, jewelry = Config.jewelry }
H.types = types

-- what each target needs and gives
local steps = {
    register = Config.store.register,
    safe = Config.store.safe,
    atm = Config.atm,
    panel = Config.fleeca.hack,
    box = Config.fleeca.box,
    case = Config.jewelry.case,
}

local what = {
    register = 'a register', safe = 'the safe', atm = 'an ATM',
    panel = 'the vault panel', box = 'a deposit box', case = 'a case',
}

local function started(name) return GetResourceState(name) == 'started' end

function H.ms() return GetGameTimer() end
function H.now() return os.time() end

local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

function H.distance(src, coords)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return math.huge end
    return dist(GetEntityCoords(ped), coords)
end

-- ------------------------------------------------------------------- suite

function H.log(src, text, data)
    if not started('fivelog') then return end
    pcall(function() exports.fivelog:add('heists', src, text, data) end)
end

function H.flag(src, detail)
    print(('^1[fiveheists]^7 %s (%s): %s'):format(GetPlayerName(src) or 'unknown', src, detail))
    H.log(src, 'Flagged: ' .. detail)
    if Config.flagCheaters and started('warden') then
        pcall(function() exports.warden:flag(src, Config.flagKind, 'fiveheists: ' .. detail) end)
    end
end

function H.police()
    if started('fiveboard') then
        local ok, n = pcall(function() return exports.fiveboard:getCount(Config.fiveboardGroup) end)
        if ok and tonumber(n) then return tonumber(n) end
    end
    return #Framework.police()
end

-- Tell fiveboard when a type goes busy, on cooldown or back to open. Only
-- changes are sent; the board counts the seconds down itself.
function H.board(kind)
    local state, seconds
    for _, s in pairs(H.sites) do
        if s.type == kind and s.active then state = 'busy' break end
    end
    if not state then
        local left = H.cooldown(kind)
        if left > 0 then state, seconds = 'cooldown', left end
    end
    if H.boardState[kind] == state then return end
    H.boardState[kind] = state
    if started('fiveboard') then
        pcall(function() exports.fiveboard:setActivity(kind, state, seconds) end)
    end
end

-- --------------------------------------------------------------- cooldowns

function H.cooldown(id)
    local t = H.cooldowns[id]
    if not t then return 0 end
    local left = t - H.now()
    if left > 0 then return left end
    H.cooldowns[id] = nil
    return 0
end

function H.save()
    if not Config.saveCooldowns then return end
    SaveResourceFile(GetCurrentResourceName(), 'cooldowns.json', json.encode(H.cooldowns), -1)
end

function H.load()
    if not Config.saveCooldowns then return end
    local raw = LoadResourceFile(GetCurrentResourceName(), 'cooldowns.json')
    local ok, list = pcall(json.decode, raw or '')
    if not ok or type(list) ~= 'table' then return end
    for id, t in pairs(list) do
        if type(id) == 'string' and tonumber(t) then H.cooldowns[id] = tonumber(t) end
    end
end

-- an id, a type (and every location of it), or 'all'
function H.resetCooldown(id)
    local any = false
    for key in pairs(H.cooldowns) do
        if id == 'all' or key == id or (types[id] and key:find('^' .. id .. ':')) then
            H.cooldowns[key] = nil
            any = true
        end
    end
    if any then
        H.save()
        for kind in pairs(types) do H.board(kind) end
    end
    return any
end

-- --------------------------------------------------------------- locations

function H.reset(s)
    s.active, s.by, s.ends, s.open = false, nil, nil, nil
    s.looted, s.busy = {}, {}
    s.code = ('%04d'):format(math.random(0, 9999))
end

local function add(kind, name, label, targets)
    local s = { id = kind .. ':' .. name, name = name, type = kind, label = label, targets = targets }
    H.reset(s)
    H.sites[s.id] = s
    return s
end

for _, l in ipairs(Config.store.locations) do
    local t = {}
    for i, c in ipairs(l.registers) do t['register' .. i] = { kind = 'register', coords = c } end
    if l.safe then t.safe = { kind = 'safe', coords = l.safe } end
    add('store', l.id, l.label, t)
end

for i, c in ipairs(Config.atm.locations) do
    add('atm', tostring(i), 'ATM', { atm = { kind = 'atm', coords = c } })
end

for _, b in ipairs(Config.fleeca.banks) do
    local t = { panel = { kind = 'panel', coords = b.panel } }
    for i, c in ipairs(b.boxes) do t['box' .. i] = { kind = 'box', coords = c, needs = 'open' } end
    add('fleeca', b.id, b.label, t)
end

for _, j in ipairs(Config.jewelry.stores) do
    local t = {}
    for i, c in ipairs(j.cases) do t['case' .. i] = { kind = 'case', coords = c } end
    add('jewelry', j.id, j.label, t)
end

-- With Config.atm.anyModel the client says where the ATM is. It has to be in
-- reach of the player, and one of the listed ATMs is used if it's close.
function H.anyAtm(src, c)
    if type(c) ~= 'table' then return end
    c = { x = tonumber(c.x), y = tonumber(c.y), z = tonumber(c.z) }
    if not (c.x and c.y and c.z) or H.distance(src, c) > Config.reach then return end
    for id, s in pairs(H.sites) do
        if s.type == 'atm' and dist(s.targets.atm.coords, c) < 1.5 then return id end
    end
    local name = ('%d_%d'):format(math.floor(c.x), math.floor(c.y))
    if not H.sites['atm:' .. name] then add('atm', name, 'ATM', { atm = { kind = 'atm', coords = c } }).lazy = true end
    return 'atm:' .. name
end

function H.syncVaults()
    local open = {}
    for _, s in pairs(H.sites) do
        if s.type == 'fleeca' and s.open then open[s.name] = true end
    end
    GlobalState['fiveheists:vaults'] = open
end

-- ----------------------------------------------------------------- players

local function player(src)
    local p = H.players[src]
    if not p then
        p = { starts = {}, wrong = {} }
        H.players[src] = p
    end
    return p
end

function H.release(src)
    local p = H.players[src]
    local pend = p and p.pending
    if not pend then return end
    p.pending = nil
    local s = H.sites[pend.site]
    if s and s.busy[pend.key] == src then s.busy[pend.key] = nil end
end

local function refuse(src, s, why)
    H.log(src, ('Refused at %s: %s'):format(s and s.label or 'unknown', why), s and { site = s.id } or nil)
    return false, why
end

local function u32(n) return math.tointeger(n) and n & 0xFFFFFFFF or 0 end
local unarmed = u32(GetHashKey('WEAPON_UNARMED'))

function H.armed(src)
    local w = u32(GetSelectedPedWeapon(GetPlayerPed(src)) or 0)
    if w == 0 or w == unarmed then return false end
    local allowed = Config.jewelry.case.weapons
    if allowed == true then return true end
    for _, name in ipairs(allowed or {}) do
        if u32(GetHashKey(name)) == w then return true end
    end
    return false
end

-- --------------------------------------------------------------- lifecycle

function H.canStart(s)
    local cfg = types[s.type]
    if H.cooldown(s.id) > 0 then return false, 'This place was hit recently.' end
    if H.cooldown(s.type) > 0 then return false, 'It is too hot right now. Try again later.' end
    local active = 0
    for _, other in pairs(H.sites) do
        if other.type == s.type and other.active then active = active + 1 end
    end
    if cfg.max and active >= cfg.max then return false, 'It is too hot right now. Try again later.' end
    if H.police() < cfg.police then return false, 'Not enough police in the city.' end
    return true
end

function H.start(s, src, coords)
    s.active, s.by, s.ends, s.since = true, src, H.now() + types[s.type].window, H.ms()
    H.log(src, ('Started a robbery at %s'):format(s.label), { site = s.id })

    local ok, err = pcall(Config.dispatch, { type = s.type, id = s.id, label = s.label, coords = coords, src = src })
    if not ok then print(('^1[fiveheists]^7 dispatch failed: %s'):format(err)) end

    TriggerEvent('fiveheists:started', s.id, s.type, src)
    H.board(s.type)
end

function H.stop(s, reason)
    if not s.active then return end
    local cfg, now, by, wasOpen = types[s.type], H.now(), s.by, s.open

    if cfg.cooldown > 0 then H.cooldowns[s.id] = now + cfg.cooldown end
    if cfg.global > 0 then H.cooldowns[s.type] = math.max(H.cooldowns[s.type] or 0, now + cfg.global) end

    -- anyone still mid-step gets "too late" when they finish
    for _, p in pairs(H.players) do p.wrong[s.id] = nil end

    H.reset(s)
    if wasOpen then H.syncVaults() end
    H.save()

    H.log(by, ('Robbery at %s is over (%s)'):format(s.label, reason), { site = s.id, reason = reason })
    TriggerEvent('fiveheists:finished', s.id, s.type, reason)
    H.board(s.type)
end

function H.tick()
    local now = H.now()
    for id, s in pairs(H.sites) do
        if s.active and now >= s.ends then H.stop(s, 'time') end
        if s.lazy and not s.active and H.cooldown(id) == 0 then H.sites[id] = nil end
    end
    for kind in pairs(types) do H.board(kind) end
end

-- ------------------------------------------------------------------ reward

local function pick(list)
    local total = 0
    for _, it in ipairs(list) do total = total + it.weight end
    local roll = math.random() * total
    for _, it in ipairs(list) do
        roll = roll - it.weight
        if roll <= 0 then return it end
    end
    return list[#list]
end

function H.reward(src, def)
    local got = { cash = 0, items = {} }
    if def.cash then
        local n = math.random(def.cash[1], def.cash[2])
        if Framework.addMoney(src, n, 'fiveheists') then got.cash = n else got.lost = true end
    end

    local function give(it)
        local count = math.random(it.count[1], it.count[2])
        if Framework.addItem(src, it.name, count) then
            got.items[it.name] = (got.items[it.name] or 0) + count
        else
            got.lost = true
        end
    end
    for _, it in ipairs(def.items or {}) do
        if math.random() < it.chance then give(it) end
    end
    if def.loot and #def.loot > 0 then give(pick(def.loot)) end
    return got
end

local function describe(got)
    local parts = {}
    if got.cash > 0 then parts[#parts + 1] = ('$%d'):format(got.cash) end
    local names = {}
    for name in pairs(got.items) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do parts[#parts + 1] = ('%dx %s'):format(got.items[name], Framework.label(name)) end
    if #parts == 0 then return 'nothing' end
    if #parts == 1 then return parts[1] end
    return table.concat(parts, ', ', 1, #parts - 1) .. ' and ' .. parts[#parts]
end

-- ------------------------------------------------------------------- steps

function H.begin(src, id, key, extra)
    local p, ms = player(src), H.ms()

    if p.last and ms - p.last < Config.rate.gap then return false, 'Slow down.' end
    local recent = {}
    for _, at in ipairs(p.starts) do
        if ms - at < 60000 then recent[#recent + 1] = at end
    end
    p.starts = recent
    if #recent >= Config.rate.perMinute then return refuse(src, nil, 'Too many attempts, wait a minute.') end
    recent[#recent + 1], p.last = ms, ms

    if type(id) ~= 'string' or type(key) ~= 'string' then
        H.flag(src, 'malformed request')
        return false, 'Nothing to rob here.'
    end
    extra = type(extra) == 'table' and extra or {}

    if id == 'atm:any' and Config.atm.anyModel then
        id = H.anyAtm(src, extra.coords)
        if not id then return refuse(src, nil, 'Too far away.') end
    end

    local s = H.sites[id]
    local t = s and s.targets[key]
    if not t then
        H.flag(src, ('asked to rob %s %s, which does not exist'):format(id, key))
        return false, 'Nothing to rob here.'
    end

    if p.pending then
        if ms - p.pending.at < p.pending.duration + 90000 then return false, 'You are already doing something.' end
        H.release(src)
    end

    if H.distance(src, t.coords) > Config.reach then return refuse(src, s, 'Too far away.') end
    if s.looted[key] then return refuse(src, s, 'Already empty.') end
    if s.busy[key] then return refuse(src, s, 'Someone is already on it.') end
    if t.needs == 'open' and not s.open then return refuse(src, s, 'The vault is closed.') end

    local step, mode = steps[t.kind], nil
    if t.kind == 'safe' then
        if extra.code ~= nil then
            mode, step = 'code', step.code
            local tries = p.wrong[s.id] or 0
            if tries >= step.tries then return refuse(src, s, 'The keypad is locked.') end
            if tostring(extra.code) ~= s.code then
                p.wrong[s.id] = tries + 1
                return refuse(src, s, 'Wrong code.')
            end
        else
            mode, step = 'drill', step.drill
        end
    end

    if t.kind == 'case' and not H.armed(src) then return refuse(src, s, 'You need something to smash it with.') end
    if step.item and not Framework.hasItem(src, step.item) then
        return refuse(src, s, ('You need a %s.'):format(Framework.label(step.item)))
    end

    if not s.active then
        local ok, why = H.canStart(s)
        if not ok then return refuse(src, s, why) end
        H.start(s, src, t.coords)
    end

    s.busy[key] = src
    p.pending = { site = s.id, key = key, at = ms, duration = step.duration, step = step }
    H.log(src, ('Started on %s at %s'):format(what[t.kind], s.label), { site = s.id, target = key, mode = mode })
    return true, { id = s.id, duration = step.duration, checks = step.checks, kind = t.kind, mode = mode }
end

-- result is 'done', 'failed' (skill check) or 'cancel'
function H.finish(src, id, key, result)
    local p = H.players[src]
    local pend = p and p.pending
    if not pend then
        H.flag(src, ('tried to finish %s %s without starting it'):format(tostring(id), tostring(key)))
        return false, 'Nothing to finish.'
    end
    if pend.site ~= id or pend.key ~= key then
        H.release(src)
        H.flag(src, ('started %s %s but finished %s %s'):format(pend.site, pend.key, tostring(id), tostring(key)))
        return false, 'Nothing to finish.'
    end

    H.release(src)
    local s = H.sites[id]
    if not s or not s.active or pend.at < (s.since or 0) then return refuse(src, s, 'Too late, it is over.') end
    local t, step = s.targets[key], pend.step

    if result ~= 'done' then
        if result == 'cancel' then return false end
        H.log(src, ('Failed on %s at %s'):format(what[t.kind], s.label), { site = s.id, target = key })
        if step.item and step.breakChance and math.random() < step.breakChance then
            Framework.removeItem(src, step.item, 1)
            return false, ('Your %s broke.'):format(Framework.label(step.item))
        end
        return false, 'You failed.'
    end

    local elapsed = H.ms() - pend.at
    if elapsed + Config.slack < pend.duration then
        if elapsed < pend.duration / 2 then
            H.flag(src, ('finished %s at %s in %dms, takes %dms'):format(what[t.kind], s.label, elapsed, pend.duration))
        end
        return refuse(src, s, 'That was too quick.')
    end
    if elapsed > pend.duration + 90000 then return refuse(src, s, 'That took too long.') end

    local d = H.distance(src, t.coords)
    if d > Config.reach then
        if d > Config.flagDistance then
            H.flag(src, ('claimed %s at %s from %dm away'):format(what[t.kind], s.label, math.floor(d)))
        end
        return refuse(src, s, 'You moved away.')
    end
    if step.item and not Framework.hasItem(src, step.item) then
        return refuse(src, s, ('You need a %s.'):format(Framework.label(step.item)))
    end

    s.looted[key] = true
    if step.remove then Framework.removeItem(src, step.item, 1) end

    local got, msg = H.reward(src, steps[t.kind]), nil
    if t.kind == 'panel' then
        s.open = true
        H.syncVaults()
        msg = 'The vault door is opening.'
        H.log(src, ('Opened the vault at %s'):format(s.label), { site = s.id })
    else
        local text = describe(got)
        msg = ('You took %s.'):format(text)
        if got.lost then msg = msg .. ' You had no room for some of it.' end
        if t.kind == 'register' and math.random() < (step.noteChance or 0) then
            msg = msg .. (' There is a note under the till: %s.'):format(s.code)
        end
        H.log(src, ('Took %s from %s at %s'):format(text, what[t.kind], s.label), { site = s.id, target = key, cash = got.cash, items = got.items })
    end

    local left = false
    for k in pairs(s.targets) do
        if not s.looted[k] then left = true break end
    end
    if not left then H.stop(s, 'emptied') end

    return true, msg
end

-- ------------------------------------------------------------------ wiring

lib.callback.register('fiveheists:begin', function(src, id, key, extra) return H.begin(src, id, key, extra) end)
lib.callback.register('fiveheists:finish', function(src, id, key, result) return H.finish(src, id, key, result) end)

AddEventHandler('playerDropped', function()
    local src = source
    H.release(src)
    H.players[src] = nil
end)

AddEventHandler('onResourceStart', function(name)
    if name ~= 'fiveboard' then return end
    H.boardState = {}
    for kind in pairs(types) do H.board(kind) end
end)

H.load()
H.syncVaults()

CreateThread(function()
    while true do
        Wait(1000)
        H.tick()
    end
end)
