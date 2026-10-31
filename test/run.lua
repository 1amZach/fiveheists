-- lua5.4 test/run.lua
-- Runs the server side of fiveheists against a fake FiveM server.

local passed, failed = 0, 0
local function check(name, cond)
    if cond then passed = passed + 1 else failed = failed + 1; io.write('FAIL ', name, '\n') end
end

function vec3(x, y, z) return { x = x, y = y, z = z } end

-- Events, timers ------------------------------------------------------------------

local handlers, triggered, client, prints = {}, {}, {}, {}
function AddEventHandler(name, fn) handlers[name] = handlers[name] or {}; table.insert(handlers[name], fn) end
function TriggerEvent(name, ...)
    triggered[#triggered + 1] = { name = name, args = { ... } }
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
function TriggerClientEvent(name, target, ...) client[#client + 1] = { name = name, target = target, args = { ... } } end
local function fire(name, src, ...)
    source = src
    for _, fn in ipairs(handlers[name] or {}) do fn(...) end
end
local function events(name)
    local out = {}
    for _, t in ipairs(triggered) do if t.name == name then out[#out + 1] = t.args end end
    return out
end
local function sent(name)
    local out = {}
    for _, t in ipairs(client) do if t.name == name then out[#out + 1] = t end end
    return out
end

function CreateThread() end
function Wait() end
local realPrint = print
function print(...) prints[#prints + 1] = table.concat({ ... }, ' ') end

local clock, ms = 1000000, 50000
function GetGameTimer() return ms end
local function later(n) ms = ms + n end

function GetHashKey(s)
    local h = 0
    for c in s:lower():gmatch('.') do
        h = (h + c:byte()) & 0xFFFFFFFF
        h = (h + (h << 10)) & 0xFFFFFFFF
        h = h ~ (h >> 6)
    end
    h = (h + (h << 3)) & 0xFFFFFFFF
    h = h ~ (h >> 11)
    h = (h + (h << 15)) & 0xFFFFFFFF
    return h >= 0x80000000 and h - 0x100000000 or h
end

local stored, n = {}, 0
json = {
    encode = function(t) n = n + 1; local k = 'json#' .. n; stored[k] = t; return k end,
    decode = function(s) return assert(stored[s], 'bad json') end,
}
local files = {}
function SaveResourceFile(_, name, data) files[name] = data end
function LoadResourceFile(_, name) return files[name] end
function GetCurrentResourceName() return 'fiveheists' end
GlobalState = {}

local callbacks = {}
lib = { callback = { register = function(name, fn) callbacks[name] = fn end } }
local function call(name, src, ...) return callbacks[name](src, ...) end

local commands = {}
function RegisterCommand(name, fn) commands[name] = fn end
local aces = {}
function IsPlayerAceAllowed(src, ace) return aces[src .. ' ' .. ace] == true end

-- Players ----------------------------------------------------------------------------

local players, started = {}, { ox_lib = 'started' }
function GetResourceState(name) return started[name] or 'missing' end
function GetPlayerName(src) local p = players[tonumber(src)]; return p and p.name end
function GetPlayerPed(src) return players[tonumber(src)] and 1000 + tonumber(src) or 0 end
function GetEntityCoords(ped) return players[ped - 1000].pos end
function GetSelectedPedWeapon(ped) return players[ped - 1000].weapon or GetHashKey('WEAPON_UNARMED') end

local function addPlayer(src, name, pos, job, duty)
    players[src] = { name = name, pos = pos or vec3(0, 0, 0), job = job or 'unemployed', duty = duty ~= false, money = {}, items = {} }
end
local function at(src, c, dx) players[src].pos = vec3(c.x + (dx or 0), c.y, c.z) end
local function give(src, item, count) players[src].items[item] = (players[src].items[item] or 0) + (count or 1) end
local function has(src, item) return players[src].items[item] or 0 end
local function cash(src, account) return players[src].money[account or 'cash'] or 0 end

-- Frameworks --------------------------------------------------------------------------

local function qbPlayer(src)
    local p = players[src]
    if not p then return end
    return {
        PlayerData = { source = src, job = { name = p.job, onduty = p.duty } },
        Functions = {
            AddMoney = function(account, amount) p.money[account] = (p.money[account] or 0) + amount; return true end,
            GetItemByName = function(name) return (p.items[name] or 0) > 0 and { amount = p.items[name] } or nil end,
            RemoveItem = function(name, count)
                if (p.items[name] or 0) < count then return false end
                p.items[name] = p.items[name] - count
                return true
            end,
            AddItem = function(name, count, _, info)
                p.items[name] = (p.items[name] or 0) + count
                p.meta = info
                return true
            end,
        },
    }
end
local function qbList()
    local out = {}
    for src in pairs(players) do out[src] = qbPlayer(src) end
    return out
end

local esxPlayer = function(src)
    local p = players[src]
    if not p then return end
    return {
        source = src,
        getJob = function() return { name = p.job, onDuty = p.duty } end,
        addAccountMoney = function(account, amount) p.money[account] = (p.money[account] or 0) + amount end,
        getInventoryItem = function(name) return { count = p.items[name] or 0 } end,
        removeInventoryItem = function(name, count) p.items[name] = (p.items[name] or 0) - count end,
        addInventoryItem = function(name, count) p.items[name] = (p.items[name] or 0) + count end,
        canCarryItem = function() return not p.full end,
    }
end

local calls = { fivelog = {}, warden = {}, board = {}, boardCount = 0 }
local boardPolice = 0
local registered = {}
exports = setmetatable({}, {
    __call = function(_, name, fn) registered[name] = fn end,
    __index = function(_, res)
        if res == 'qbx_core' then return { GetPlayer = function(_, src) return qbPlayer(src) end, GetQBPlayers = function() return qbList() end } end
        if res == 'qb-core' then return { GetCoreObject = function() return { Functions = { GetPlayer = qbPlayer, GetQBPlayers = qbList } } end } end
        if res == 'es_extended' then return { getSharedObject = function() return {
            GetPlayerFromId = esxPlayer,
            GetExtendedPlayers = function() local out = {}; for src in pairs(players) do out[#out + 1] = esxPlayer(src) end; return out end,
        } end } end
        if res == 'ox_inventory' then return {
            GetItemCount = function(_, src, name) return players[src].items[name] or 0 end,
            RemoveItem = function(_, src, name, count)
                local p = players[src]
                if (p.items[name] or 0) < count then return false end
                p.items[name] = p.items[name] - count
                return true
            end,
            CanCarryItem = function(_, src) return not players[src].full end,
            AddItem = function(_, src, name, count, meta) local p = players[src]; p.items[name] = (p.items[name] or 0) + count; p.meta = meta; return true end,
            Items = function(_, name) return ({ lockpick = { label = 'Lockpick' }, rolex = { label = 'Rolex' } })[name] end,
        } end
        if res == 'fivelog' then return { add = function(_, kind, src, text, data) calls.fivelog[#calls.fivelog + 1] = { kind = kind, src = src, text = text, data = data } end } end
        if res == 'warden' then return { flag = function(_, src, kind, detail) calls.warden[#calls.warden + 1] = { src = src, kind = kind, detail = detail } end } end
        if res == 'fiveboard' then return {
            setActivity = function(_, id, state, seconds) calls.board[#calls.board + 1] = { id = id, state = state, seconds = seconds } end,
            getCount = function(_, group) calls.boardCount = calls.boardCount + 1; calls.boardGroup = group; return boardPolice end,
        } end
        error('export from a resource that is not running: ' .. tostring(res))
    end,
})

-- an earlier cooldown left on disk
files['cooldowns.json'] = json.encode({ ['store:elrancho'] = clock + 600, junk = 'x' })

for _, f in ipairs({ 'config.lua', 'server/framework.lua', 'server/dispatch.lua', 'server/main.lua', 'server/commands.lua' }) do dofile(f) end

local H = Heists
H.now = function() return clock end

-- predictable for most tests
Config.store.register.noteChance = 0
Config.store.register.breakChance = 0
Config.store.safe.items = {}

local grove = Config.store.locations[1]
local reg1, reg2, safe = grove.registers[1], grove.registers[2], grove.safe
local legion = Config.fleeca.banks[1]
local vangelico = Config.jewelry.stores[1]

local function begin(src, id, key, extra) later(1000); return call('fiveheists:begin', src, id, key, extra) end
local function finish(src, id, key, result) return call('fiveheists:finish', src, id, key, result or 'done') end
local function robbed(src, id, key, extra, wait)
    local ok, info = begin(src, id, key, extra)
    if not ok then return false, info end
    later(wait or info.duration)
    return finish(src, id, key)
end
local function lastLog() return calls.fivelog[#calls.fivelog] end
local function flags() return #calls.warden end

-- Tests -------------------------------------------------------------------------------

do -- loading
    check('sites built', H.sites['store:grove'] and H.sites['fleeca:legion'] and H.sites['jewelry:vangelico'] and H.sites['atm:1'])
    check('fleeca targets', H.sites['fleeca:legion'].targets.panel and H.sites['fleeca:legion'].targets.box5)
    check('saved cooldown loaded', H.cooldown('store:elrancho') == 600)
    check('junk in the file ignored', H.cooldowns.junk == nil)
    check('vaults closed at start', next(GlobalState['fiveheists:vaults']) == nil)
    check('callbacks registered', callbacks['fiveheists:begin'] and callbacks['fiveheists:finish'])
end

started.qbx_core, started.ox_inventory = 'started', 'started'
addPlayer(1, 'Robber', vec3(0, 0, 0))
addPlayer(2, 'Cop A', vec3(500, 500, 0), 'police')
addPlayer(3, 'Cop B', vec3(500, 500, 0), 'bcso', false)
at(1, reg1)

do -- police requirement, counted from the framework without fiveboard
    give(1, 'lockpick', 2)
    local ok, why = begin(1, 'store:grove', 'register1')
    check('one on duty is not enough', not ok and why == 'Not enough police in the city.')
    check('nothing started', not H.sites['store:grove'].active)
    check('off-duty police not counted', #Framework.police() == 1)
    players[3].duty = true
    check('on-duty police counted', H.police() == 2)
end

do -- fiveboard's count wins when it's running
    started.fiveboard = 'started'
    boardPolice = 0
    check('fiveboard count used', H.police() == 0 and calls.boardGroup == 'Police')
    boardPolice = 5
    check('fiveboard count', H.police() == 5)
    started.fiveboard = nil
end

do -- without fivelog, warden or fiveboard nothing is called
    local ok = begin(1, 'store:grove', 'register1')
    check('started without integrations', ok == true)
    check('no fivelog calls', #calls.fivelog == 0 and #calls.board == 0)
    later(Config.store.register.duration)
    check('loot without integrations', finish(1, 'store:grove', 'register1') == true)
    check('paid', cash(1) >= 250 and cash(1) <= 600)
    local before = #prints
    finish(1, 'store:grove', 'register1')
    check('flag without warden just prints', flags() == 0 and #prints == before + 1)
    H.stop(H.sites['store:grove'], 'test')
    H.resetCooldown('all')
    players[1].money = {}
end

started.fivelog, started.warden, started.fiveboard = 'started', 'started', 'started'
boardPolice = 2
calls.board = {}
H.boardState = {}

do -- a register, start to finish
    client = {}
    local ok, info = begin(1, 'store:grove', 'register1')
    check('begin ok', ok == true and info.duration == Config.store.register.duration and info.kind == 'register' and info.id == 'store:grove')
    check('skill checks sent', #info.checks == 3)
    check('site active', H.sites['store:grove'].active and H.sites['store:grove'].by == 1)
    local alerts = sent('fiveheists:alert')
    check('police alerted', #alerts == 2 and alerts[1].target == 2 and alerts[2].target == 3 and alerts[1].args[1].label == 'LTD Grove Street')
    check('robber not alerted', not (alerts[1].target == 1 or alerts[2].target == 1))
    check('started event', #events('fiveheists:started') == 2 and events('fiveheists:started')[2][1] == 'store:grove')
    check('board busy', calls.board[#calls.board].id == 'store' and calls.board[#calls.board].state == 'busy')
    check('start logged', calls.fivelog[1].kind == 'heists' and calls.fivelog[1].text == 'Started a robbery at LTD Grove Street')
    check('step logged', lastLog().text == 'Started on a register at LTD Grove Street')

    local again = { begin(1, 'store:grove', 'register2') }
    check('one step at a time', again[1] == false and again[2] == 'You are already doing something.')

    later(2000)
    local f = flags()
    local done, why = finish(1, 'store:grove', 'register1')
    check('too fast refused', done == false and why == 'That was too quick.')
    check('way too fast flagged', flags() == f + 1 and calls.warden[#calls.warden].kind == 'exploit' and calls.warden[#calls.warden].detail:find('^fiveheists: '))
    check('nothing paid', cash(1) == 0)
    check('register free again', H.sites['store:grove'].busy.register1 == nil)

    ok = begin(1, 'store:grove', 'register1')
    later(Config.store.register.duration - 1000)
    f = flags()
    done = finish(1, 'store:grove', 'register1')
    check('lag slack allowed', done == true and flags() == f)
    check('register paid by the server', cash(1) >= 250 and cash(1) <= 600)
    check('lockpick kept on success', has(1, 'lockpick') == 2)
    check('loot logged with amount', lastLog().text:find('^Took %$%d+ from a register') and lastLog().data.cash == cash(1))
    check('looted', H.sites['store:grove'].looted.register1)

    local r = { begin(1, 'store:grove', 'register1') }
    check('double loot refused', r[1] == false and r[2] == 'Already empty.')
    check('refusal logged', lastLog().text == 'Refused at LTD Grove Street: Already empty.')

    f = flags()
    r = { finish(1, 'store:grove', 'register1') }
    check('finish without begin refused', r[1] == false)
    check('finish without begin flagged', flags() == f + 1 and calls.warden[#calls.warden].detail:find('without starting'))
end

do -- the client can't pick the amount
    at(1, reg2)
    local before = cash(1)
    begin(1, 'store:grove', 'register2')
    later(Config.store.register.duration)
    callbacks['fiveheists:finish'](1, 'store:grove', 'register2', 'done', 999999, { cash = 999999 })
    check('extra arguments ignored', cash(1) - before <= 600)
end

do -- distance on begin and finish
    at(1, safe, 4)
    local f = flags()
    local ok, why = begin(1, 'store:grove', 'safe')
    check('too far to start', not ok and why == 'Too far away.' and flags() == f)

    give(1, 'drill')
    at(1, safe)
    ok = begin(1, 'store:grove', 'safe')
    check('drill mode', ok == true and H.players[1].pending.duration == Config.store.safe.drill.duration)
    later(Config.store.safe.drill.duration)
    at(1, safe, 6)
    local done, msg = finish(1, 'store:grove', 'safe')
    check('walked away refused, not flagged', done == false and msg == 'You moved away.' and flags() == f)

    at(1, safe)
    begin(1, 'store:grove', 'safe')
    later(Config.store.safe.drill.duration)
    at(1, safe, 200)
    done = finish(1, 'store:grove', 'safe')
    check('across the map flagged', done == false and flags() == f + 1 and calls.warden[#calls.warden].detail:find('200m away'))
    check('safe still full', not H.sites['store:grove'].looted.safe)
    at(1, safe)
end

do -- item checks and breaking
    players[1].items.drill = 0
    local ok, why = begin(1, 'store:grove', 'safe')
    check('needs the drill', not ok and why == 'You need a drill.')

    give(1, 'drill')
    begin(1, 'store:grove', 'safe')
    players[1].items.drill = 0
    later(Config.store.safe.drill.duration)
    local done = finish(1, 'store:grove', 'safe')
    check('item gone before finish refused', done == false)

    give(1, 'drill')
    Config.store.safe.drill.breakChance = 1
    begin(1, 'store:grove', 'safe')
    local _, msg = finish(1, 'store:grove', 'safe', 'failed')
    check('failed check breaks the drill', msg == 'Your drill broke.' and has(1, 'drill') == 0)
    check('fail logged', calls.fivelog[#calls.fivelog].text == 'Failed on the safe at LTD Grove Street')

    give(1, 'drill')
    begin(1, 'store:grove', 'safe')
    local r = { finish(1, 'store:grove', 'safe', 'cancel') }
    check('cancel costs nothing', r[1] == false and r[2] == nil and has(1, 'drill') == 1)
    Config.store.safe.drill.breakChance = 0.25
end

do -- safe codes
    local s = H.sites['store:grove']
    local wrong = s.code == '0000' and '1111' or '0000'
    local ok, why = begin(1, 'store:grove', 'safe', { code = wrong })
    check('wrong code', not ok and why == 'Wrong code.')
    begin(1, 'store:grove', 'safe', { code = wrong })
    begin(1, 'store:grove', 'safe', { code = wrong })
    ok, why = begin(1, 'store:grove', 'safe', { code = s.code })
    check('locked after three tries', not ok and why == 'The keypad is locked.')

    H.players[1].wrong['store:grove'] = nil
    players[1].items.drill = 0
    ok = begin(1, 'store:grove', 'safe', { code = s.code })
    check('right code needs no drill', ok == true and H.players[1].pending.duration == Config.store.safe.code.duration)
    later(Config.store.safe.code.duration)
    local before = cash(1)
    local done = finish(1, 'store:grove', 'safe')
    check('safe paid', done == true and cash(1) - before >= 1500 and cash(1) - before <= 3500)
end

do -- emptying a store ends it with cooldowns
    local s = H.sites['store:grove']
    check('store over when empty', not s.active and next(s.looted) == nil)
    check('finished event', events('fiveheists:finished')[#events('fiveheists:finished')][1] == 'store:grove')
    check('location cooldown', H.cooldown('store:grove') == Config.store.cooldown)
    check('type cooldown', H.cooldown('store') == Config.store.global)
    check('board cooldown', calls.board[#calls.board].state == 'cooldown' and calls.board[#calls.board].seconds == Config.store.global)
    check('cooldowns saved', stored[files['cooldowns.json']]['store:grove'] == clock + Config.store.cooldown)

    at(1, reg1)
    local ok, why = begin(1, 'store:grove', 'register1')
    check('same store refused', not ok and why == 'This place was hit recently.')
    local inno = Config.store.locations[2]
    at(1, inno.registers[1])
    ok, why = begin(1, 'store:innocence', 'register1')
    check('other store waits for the type cooldown', not ok and why == 'It is too hot right now. Try again later.')

    clock = clock + Config.store.global
    H.tick()
    check('board back to open', calls.board[#calls.board].state == nil and calls.board[#calls.board].id == 'store')
    ok = begin(1, 'store:innocence', 'register1')
    check('other store opens after', ok == true)
    later(Config.store.register.duration)
    finish(1, 'store:innocence', 'register1')
end

do -- the window runs out
    local s = H.sites['store:innocence']
    check('still open with a register left', s.active)
    at(1, Config.store.locations[2].registers[2])
    begin(1, 'store:innocence', 'register2')
    clock = clock + Config.store.window
    H.tick()
    check('ended by time', not s.active and events('fiveheists:finished')[#events('fiveheists:finished')][3] == 'time')
    later(Config.store.register.duration)
    local f = flags()
    local done, why = finish(1, 'store:innocence', 'register2')
    check('late finish is just too late', done == false and why == 'Too late, it is over.' and flags() == f)
end

do -- the register note gives the safe code
    clock = clock + 3600
    H.resetCooldown('all')
    Config.store.register.noteChance = 1
    local mp = Config.store.locations[4]
    at(1, mp.registers[1])
    local _, msg = robbed(1, 'store:mirrorpark', 'register1')
    local code = msg:match('note under the till: (%d+)')
    check('note shows the code', code == H.sites['store:mirrorpark'].code)
    Config.store.register.noteChance = 0
    H.stop(H.sites['store:mirrorpark'], 'test')
    H.resetCooldown('all')
end

do -- rate limits
    local p = H.players[1]
    at(1, reg1)
    later(1000)
    call('fiveheists:begin', 1, 'store:grove', 'nope')
    local ok, why = call('fiveheists:begin', 1, 'store:grove', 'register1')
    check('gap between starts', not ok and why == 'Slow down.')
    p.starts = {}
    for i = 1, Config.rate.perMinute do p.starts[i] = ms end
    ok, why = begin(1, 'store:grove', 'register1')
    check('per minute cap', not ok and why == 'Too many attempts, wait a minute.')
    p.starts = {}
end

do -- made-up targets
    local f = flags()
    local ok = begin(1, 'store:grove', 'register9')
    check('unknown target refused and flagged', not ok and flags() == f + 1)
    ok = begin(1, { 'x' }, 7)
    check('malformed refused and flagged', not ok and flags() == f + 2)
    ok = begin(1, 'atm:any', 'atm', { coords = players[1].pos })
    check('any ATM off by default', not ok and flags() == f + 3)
end

do -- flagging can be turned off
    Config.flagCheaters = false
    local f = flags()
    finish(1, 'store:grove', 'register1')
    check('no warden call with flagCheaters off', flags() == f)
    check('still logged', lastLog().text:find('^Flagged: '))
    Config.flagCheaters = true
end

do -- ATMs
    local c = Config.atm.locations[1]
    at(1, c)
    local ok, why = begin(1, 'atm:1', 'atm')
    check('ATM needs a drill', not ok and why == 'You need a drill.')
    give(1, 'drill')
    boardPolice = 0
    ok, why = begin(1, 'atm:1', 'atm')
    check('ATM needs police', not ok and why == 'Not enough police in the city.')
    boardPolice = 5
    local before = cash(1)
    local done = robbed(1, 'atm:1', 'atm')
    check('ATM paid', done == true and cash(1) - before >= 800 and cash(1) - before <= 2000)
    check('ATM over after one', not H.sites['atm:1'].active and H.cooldown('atm:1') == Config.atm.cooldown)

    Config.atm.anyModel = true
    H.resetCooldown('atm')
    at(1, vec3(900, 900, 30))
    ok = begin(1, 'atm:any', 'atm', { coords = vec3(950, 900, 30) })
    check('any ATM must be in reach', not ok)
    ok, why = begin(1, 'atm:any', 'atm', { coords = vec3(901, 900, 30) })
    check('any ATM site made', ok == true and why.id == 'atm:901_900' and H.sites['atm:901_900'].lazy)
    later(Config.atm.duration)
    check('any ATM loot', finish(1, why.id, 'atm') == true)
    H.resetCooldown('all')
    at(1, c)
    ok, why = begin(1, 'atm:any', 'atm', { coords = c })
    check('listed ATM reused', ok and why.id == 'atm:1')
    finish(1, 'atm:1', 'atm', 'cancel')
    H.stop(H.sites['atm:1'], 'test')
    Config.atm.anyModel = false
    H.resetCooldown('all')
    H.tick()
    check('made-up ATM forgotten after its cooldown', H.sites['atm:901_900'] == nil)
end

do -- Fleeca
    addPlayer(4, 'Partner', vec3(0, 0, 0))
    at(1, legion.boxes[1])
    local ok, why = begin(1, 'fleeca:legion', 'box1')
    check('boxes need the vault open', not ok and why == 'The vault is closed.')
    check('closed vault does not start it', not H.sites['fleeca:legion'].active)

    at(1, legion.panel)
    ok, why = begin(1, 'fleeca:legion', 'panel')
    check('panel needs the usb', not ok and why == 'You need a trojan usb.')
    boardPolice = 3
    give(1, 'trojan_usb', 2)
    ok, why = begin(1, 'fleeca:legion', 'panel')
    check('fleeca needs 4 police', not ok and why == 'Not enough police in the city.')
    boardPolice = 4

    Config.fleeca.hack.breakChance = 0
    begin(1, 'fleeca:legion', 'panel')
    finish(1, 'fleeca:legion', 'panel', 'failed')
    check('failed hack keeps the usb', has(1, 'trojan_usb') == 2 and not H.sites['fleeca:legion'].open)

    local done, msg = robbed(1, 'fleeca:legion', 'panel')
    check('hack opens the vault', done and msg == 'The vault door is opening.' and GlobalState['fiveheists:vaults'].legion == true)
    check('usb used up', has(1, 'trojan_usb') == 1)
    check('opening logged', calls.fivelog[#calls.fivelog].text == 'Opened the vault at Fleeca Legion Square')
    ok = begin(1, 'fleeca:legion', 'panel')
    check('panel once', not ok)

    at(1, legion.boxes[1])
    at(4, legion.boxes[1])
    ok = begin(1, 'fleeca:legion', 'box1')
    local r = { begin(4, 'fleeca:legion', 'box1') }
    check('one person per box', ok and r[1] == false and r[2] == 'Someone is already on it.')
    fire('playerDropped', 1)
    r = { begin(4, 'fleeca:legion', 'box1') }
    check('leaving frees the box', r[1] == true)
    addPlayer(1, 'Robber', vec3(0, 0, 0))

    Config.fleeca.box.items = { { name = 'goldbar', chance = 1, count = { 1, 1 } } }
    later(Config.fleeca.box.duration)
    finish(4, 'fleeca:legion', 'box1')
    check('box gives cash and gold', cash(4) >= 2500 and has(4, 'goldbar') == 1)

    players[4].full = true
    at(4, legion.boxes[2])
    local _, m = robbed(4, 'fleeca:legion', 'box2')
    check('no room is said', m:find('no room'))
    players[4].full = nil

    for i = 3, #legion.boxes do
        at(4, legion.boxes[i])
        robbed(4, 'fleeca:legion', 'box' .. i)
    end
    check('bank over when empty', not H.sites['fleeca:legion'].active)
    check('vault closes', GlobalState['fiveheists:vaults'].legion == nil)
    check('one fleeca at a time cooldown', H.cooldown('fleeca') == Config.fleeca.global)
end

do -- jewelry
    at(1, vangelico.cases[1])
    local ok, why = begin(1, 'jewelry:vangelico', 'case1')
    check('fists refused', not ok and why == 'You need something to smash it with.')
    players[1].weapon = GetHashKey('WEAPON_PISTOL') & 0xFFFFFFFF
    boardPolice = 4
    ok, why = begin(1, 'jewelry:vangelico', 'case1')
    check('jewelry needs 5 police', not ok and why == 'Not enough police in the city.')
    boardPolice = 5
    local done, msg = robbed(1, 'jewelry:vangelico', 'case1')
    local total = 0
    for _, name in ipairs({ 'rolex', 'goldchain', 'diamond_ring' }) do total = total + has(1, name) end
    check('case gives one kind of jewelry', done and total >= 1 and total <= 3 and msg:find('^You took %d+x '))
    ok, why = begin(1, 'jewelry:vangelico', 'case1')
    check('case once per heist', not ok and why == 'Already empty.')

    Config.jewelry.case.weapons = { 'WEAPON_BAT' }
    at(1, vangelico.cases[2])
    ok = begin(1, 'jewelry:vangelico', 'case2')
    check('weapon list respected', not ok)
    players[1].weapon = GetHashKey('WEAPON_BAT')
    ok = begin(1, 'jewelry:vangelico', 'case2')
    check('listed weapon works', ok == true)
    finish(1, 'jewelry:vangelico', 'case2', 'cancel')
    Config.jewelry.case.weapons = true
end

do -- exports and the command
    check('isActive site', registered.isActive('jewelry:vangelico') == true)
    check('isActive type', registered.isActive('jewelry') == true and registered.isActive('store') == false)
    check('getCooldown', registered.getCooldown('fleeca:legion') == Config.fleeca.cooldown)
    check('resetCooldown', registered.resetCooldown('fleeca:legion') == true and registered.getCooldown('fleeca:legion') == 0)
    check('resetCooldown nothing', registered.resetCooldown('fleeca:legion') == false)
    check('fleeca type cooldown kept', registered.getCooldown('fleeca') > 0)

    client = {}
    commands.heists(1, {})
    check('command needs the ace', #client == 0)
    aces['1 fiveheists.admin'] = true
    commands.heists(1, {})
    local lines = sent('chat:addMessage')
    local text = ''
    for _, l in ipairs(lines) do text = text .. l.args[1].args[2] .. '\n' end
    check('command lists', text:find('jewelry:vangelico  in progress') and text:find('fleeca  cooldown 30m 0s'))
    commands.heists(1, { 'reset', 'fleeca' })
    check('command reset', registered.getCooldown('fleeca') == 0 and sent('chat:addMessage')[#sent('chat:addMessage')].args[1].args[2] == 'Cooldown reset: fleeca')
    local before = #prints
    commands.heists(0, { 'reset' })
    check('console usage', prints[before + 1] == 'Usage: heists reset <id|type|all>')
end

do -- max at the same time
    H.stop(H.sites['jewelry:vangelico'], 'test')
    H.resetCooldown('all')
    Config.store.max = 1
    give(1, 'lockpick')
    at(1, Config.store.locations[3].registers[1])
    check('first store starts', begin(1, 'store:littleseoul', 'register1') == true)
    finish(1, 'store:littleseoul', 'register1', 'cancel')
    at(1, Config.store.locations[5].registers[1])
    local ok, why = begin(1, 'store:clinton', 'register1')
    check('max robberies of a type', not ok and why == 'It is too hot right now. Try again later.')
    H.stop(H.sites['store:littleseoul'], 'test')
    H.resetCooldown('all')
    Config.store.max = 3
end

do -- fiveboard restarting gets the state again
    H.cooldowns.atm = clock + 100
    H.tick()
    local n = #calls.board
    fire('onResourceStart', nil, 'fiveboard')
    check('board told again after restart', #calls.board == n + 1 and calls.board[#calls.board].state == 'cooldown')
    H.resetCooldown('all')
end

-- Framework bridge -----------------------------------------------------------------

local function bridge(name)
    started.qbx_core, started['qb-core'], started.es_extended, started.ox_inventory = nil, nil, nil, nil
    started[name] = 'started'
end

do -- Qbox with ox_inventory
    bridge('qbx_core'); started.ox_inventory = 'started'
    addPlayer(9, 'Q', vec3(0, 0, 0), 'police')
    check('qbx name', Framework.name() == 'qbx')
    Framework.addMoney(9, 100)
    check('qbx cash', cash(9, 'cash') == 100)
    Framework.addItem(9, 'rolex', 2)
    check('qbx ox add', has(9, 'rolex') == 2 and Framework.hasItem(9, 'rolex', 2) and not Framework.hasItem(9, 'rolex', 3))
    check('qbx ox remove', Framework.removeItem(9, 'rolex', 1) and has(9, 'rolex') == 1)
    check('ox label', Framework.label('rolex') == 'Rolex' and Framework.label('diamond_ring') == 'diamond ring')
    local job, duty = Framework.job(9)
    check('qbx job', job == 'police' and duty == true)
end

do -- QBCore with its own inventory and marked bills
    bridge('qb-core')
    players[9].items = {}
    check('qb name', Framework.name() == 'qb')
    Config.money = { item = 'markedbills', worth = true }
    Framework.addMoney(9, 4200)
    check('qb marked bills worth', has(9, 'markedbills') == 1 and players[9].meta.worth == 4200)
    Config.money = { account = 'cash' }
    Framework.addMoney(9, 50)
    check('qb cash', cash(9, 'cash') == 150)
    check('qb has', Framework.hasItem(9, 'markedbills') and not Framework.hasItem(9, 'drill'))
    check('qb remove', Framework.removeItem(9, 'markedbills', 1) and has(9, 'markedbills') == 0)
    check('qb police list', #Framework.police() >= 1)
end

do -- ESX
    bridge('es_extended')
    players[9].items = {}
    check('esx name', Framework.name() == 'esx')
    Framework.addMoney(9, 75)
    check('esx cash is money', cash(9, 'money') == 75)
    Config.money = { account = 'black_money' }
    Framework.addMoney(9, 30)
    check('esx black money', cash(9, 'black_money') == 30)
    Config.money = { item = 'black_money' }
    Framework.addMoney(9, 40)
    check('money as an item count', has(9, 'black_money') == 40)
    Config.money = { account = 'cash' }
    players[9].full = true
    check('esx full', Framework.addItem(9, 'rolex', 1) == false)
    players[9].full = nil
    Framework.addItem(9, 'rolex', 1)
    check('esx add and has', Framework.hasItem(9, 'rolex'))
    Framework.removeItem(9, 'rolex', 1)
    check('esx remove', not Framework.hasItem(9, 'rolex'))
    local job = Framework.job(9)
    check('esx job', job == 'police')
    started.fiveboard = nil
    check('esx police count', H.police() == #Framework.police() and H.police() >= 2)
end

do -- no framework at all
    bridge('none')
    check('no framework, no money', Framework.addMoney(9, 10) == false and Framework.count(9, 'rolex') == 0)
    check('no framework, no police', #Framework.police() == 0)
end

realPrint(('%d passed, %d failed'):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
