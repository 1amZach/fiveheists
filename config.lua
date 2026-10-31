Config = {}

-- Jobs that count as police without fiveboard. On-duty players with one of
-- these get the dispatch alerts. With fiveboard running, its count for this
-- group is used instead so the board and the robberies agree.
Config.policeJobs = { 'police', 'lspd', 'bcso', 'sasp', 'sheriff' }
Config.fiveboardGroup = 'Police'

-- How robbery money is paid:
--   { account = 'cash' }                    framework cash (ESX 'money')
--   { account = 'black_money' }             ESX black money account
--   { item = 'black_money' }                that many of an item
--   { item = 'markedbills', worth = true }  one item with the amount as `worth` metadata (QBCore)
Config.money = { account = 'cash' }

-- Clear exploits (loot claimed without starting, from across the map, or
-- impossibly fast) are sent to warden as this kind. 'exploit' only logs on
-- warden's defaults; raise it in warden's config to kick or ban.
Config.flagCheaters = true
Config.flagKind = 'exploit'
Config.flagDistance = 30.0

-- Keep cooldowns in cooldowns.json so a restart doesn't reopen everything.
Config.saveCooldowns = true

-- Requests per player: milliseconds between starts, and starts per minute.
Config.rate = { gap = 750, perMinute = 30 }

-- Metres from a register, case or box a player can be. A step can finish
-- `slack` milliseconds early to allow for lag.
Config.reach = 2.5
Config.slack = 1500

-- The default dispatch alert (server/dispatch.lua).
Config.alert = { sprite = 161, color = 1, scale = 1.2, seconds = 120 }

-- Skill check difficulties are ox_lib's: 'easy', 'medium', 'hard', or
-- { areaSize = 50, speedMultiplier = 1 }. Durations are in milliseconds,
-- cooldowns and windows in seconds.
--
--   police    on duty to start one
--   cooldown  before the same location can be hit again
--   global    before any location of this type can be hit again
--   window    how long a robbery stays open once started
--   max       locations of this type robbed at the same time

Config.store = {
    police = 2,
    cooldown = 30 * 60,
    global = 3 * 60,
    window = 10 * 60,
    max = 3,

    register = {
        item = 'lockpick',
        breakChance = 0.5, -- when the skill check fails
        duration = 15000,
        checks = { 'easy', 'easy', 'medium' },
        cash = { 250, 600 },
        noteChance = 0.35, -- a note with the safe code under the till
    },

    safe = {
        code = { duration = 7000, tries = 3 },
        drill = { item = 'drill', breakChance = 0.25, duration = 60000, checks = { 'medium', 'medium', 'hard' } },
        cash = { 1500, 3500 },
        items = {
            { name = 'goldchain', chance = 0.3, count = { 1, 2 } },
        },
    },

    locations = {
        {
            id = 'grove', label = 'LTD Grove Street',
            registers = { vec3(-47.24, -1757.65, 29.53), vec3(-48.58, -1759.21, 29.59) },
            safe = vec3(-43.43, -1748.30, 29.42),
        },
        {
            id = 'innocence', label = '24/7 Innocence Boulevard',
            registers = { vec3(24.47, -1344.99, 29.49), vec3(24.45, -1347.37, 29.49) },
            safe = vec3(28.21, -1338.83, 29.50),
        },
        {
            id = 'littleseoul', label = 'LTD Little Seoul',
            registers = { vec3(-706.08, -915.42, 19.21), vec3(-706.16, -913.50, 19.21) },
            safe = vec3(-709.74, -904.15, 19.21),
        },
        {
            id = 'mirrorpark', label = 'LTD Mirror Park',
            registers = { vec3(1165.05, -324.49, 69.20), vec3(1164.70, -322.58, 69.20) },
            safe = vec3(1159.46, -314.05, 69.20),
        },
        {
            id = 'clinton', label = '24/7 Clinton Avenue',
            registers = { vec3(373.14, 328.62, 103.56), vec3(372.57, 326.42, 103.56) },
            safe = vec3(378.17, 333.44, 103.56),
        },
        {
            id = 'prosperity', label = "Rob's Liquor Prosperity Street",
            registers = { vec3(-1486.26, -378.00, 40.16) },
            safe = vec3(-1478.94, -375.50, 39.16),
        },
        {
            id = 'vespucci', label = "Rob's Liquor San Andreas Avenue",
            registers = { vec3(-1222.03, -908.32, 12.32) },
            safe = vec3(-1220.85, -916.05, 11.32),
        },
        {
            id = 'elrancho', label = "Rob's Liquor El Rancho",
            registers = { vec3(1134.15, -982.53, 46.41) },
            safe = vec3(1126.77, -980.10, 45.41),
        },
    },
}

Config.atm = {
    police = 1,
    cooldown = 45 * 60,
    global = 5 * 60,
    window = 3 * 60,
    max = 2,

    item = 'drill',
    breakChance = 0.2,
    duration = 30000,
    checks = { 'easy', 'medium', 'medium', 'hard' },
    cash = { 800, 2000 },

    -- Every ATM in the world instead of the list below. The server can't tell
    -- where map props are, so it has to trust the position the client sends
    -- (still within reach of the player). Leave off unless you need it.
    anyModel = false,
    models = { 'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm' },

    locations = {
        vec3(147.47, -1036.22, 29.34),
        vec3(145.84, -1035.63, 29.34),
        vec3(-1205.38, -326.53, 37.85),
        vec3(-2958.98, 487.31, 15.48),
        vec3(1171.52, 2702.48, 38.18),
        vec3(-846.65, -341.51, 38.67),
        vec3(-526.78, -1223.37, 18.45),
        vec3(-386.73, 6045.95, 31.50),
    },
}

Config.fleeca = {
    police = 4,
    cooldown = 90 * 60,
    global = 30 * 60,
    window = 15 * 60,
    max = 1,

    hack = {
        item = 'trojan_usb',
        remove = true, -- used up when the hack works
        breakChance = 0.5,
        duration = 12000,
        checks = { 'medium', 'medium', 'hard', 'hard' },
    },

    box = {
        duration = 10000,
        checks = { 'easy' },
        cash = { 2500, 5000 },
        items = {
            { name = 'goldbar', chance = 0.2, count = { 1, 1 } },
        },
    },

    door = 'v_ilev_gb_vauldr',

    banks = {
        {
            id = 'legion', label = 'Fleeca Legion Square',
            panel = vec3(146.92, -1046.11, 29.36),
            door = vec3(148.03, -1044.36, 29.51), closed = 249.85, open = 159.85,
            boxes = { vec3(149.84, -1044.92, 29.36), vec3(151.16, -1046.64, 29.36), vec3(147.16, -1047.72, 29.36), vec3(146.55, -1049.28, 29.36), vec3(150.00, -1050.67, 29.36) },
        },
        {
            id = 'hawick', label = 'Fleeca Hawick Avenue',
            panel = vec3(311.15, -284.49, 54.16),
            door = vec3(312.36, -282.73, 54.30), closed = 250.0, open = 160.0,
            boxes = { vec3(314.17, -283.28, 54.15), vec3(315.50, -285.00, 54.15), vec3(311.50, -286.09, 54.15), vec3(310.89, -287.65, 54.15), vec3(314.35, -289.03, 54.15) },
        },
        {
            id = 'burton', label = 'Fleeca Burton',
            panel = vec3(-353.82, -55.37, 49.03),
            door = vec3(-352.74, -53.57, 49.18), closed = 250.0, open = 160.0,
            boxes = { vec3(-350.92, -54.12, 49.03), vec3(-349.60, -55.84, 49.03), vec3(-353.59, -56.93, 49.03), vec3(-354.20, -58.49, 49.03), vec3(-350.75, -59.87, 49.03) },
        },
        {
            id = 'delperro', label = 'Fleeca Boulevard Del Perro',
            panel = vec3(-1210.77, -336.57, 37.78),
            door = vec3(-1211.26, -334.56, 37.92), closed = 296.86, open = 206.86,
            boxes = { vec3(-1209.62, -333.61, 37.77), vec3(-1207.46, -333.82, 37.77), vec3(-1209.40, -337.48, 37.77), vec3(-1208.67, -338.99, 37.77), vec3(-1205.30, -337.42, 37.77) },
        },
        {
            id = 'greatocean', label = 'Fleeca Great Ocean Highway',
            panel = vec3(-2956.55, 481.74, 15.69),
            door = vec3(-2958.54, 482.27, 15.84), closed = 357.54, open = 267.54,
            boxes = { vec3(-2958.56, 484.17, 15.69), vec3(-2957.32, 485.95, 15.69), vec3(-2955.08, 482.47, 15.69), vec3(-2953.41, 482.36, 15.69), vec3(-2953.13, 486.07, 15.69) },
        },
        {
            id = 'route68', label = 'Fleeca Route 68',
            panel = vec3(1175.96, 2712.87, 38.09),
            door = vec3(1175.54, 2710.86, 38.23), closed = 90.0, open = 0.0,
            boxes = { vec3(1173.65, 2710.76, 38.08), vec3(1171.82, 2711.92, 38.08), vec3(1175.20, 2714.31, 38.08), vec3(1175.23, 2715.98, 38.08), vec3(1171.52, 2716.10, 38.08) },
        },
    },
}

Config.jewelry = {
    police = 5,
    cooldown = 60 * 60,
    global = 0,
    window = 8 * 60,
    max = 1,

    case = {
        -- Weapon names that can smash a case, or true for anything but fists.
        weapons = true,
        duration = 5000,
        -- Each case gives one of these, picked by weight.
        loot = {
            { name = 'rolex', weight = 40, count = { 1, 2 } },
            { name = 'goldchain', weight = 40, count = { 1, 3 } },
            { name = 'diamond_ring', weight = 20, count = { 1, 1 } },
        },
    },

    stores = {
        {
            id = 'vangelico', label = 'Vangelico',
            cases = {
                vec3(-626.83, -235.35, 38.05), vec3(-625.81, -234.70, 38.05), vec3(-626.95, -233.14, 38.05),
                vec3(-628.00, -233.86, 38.05), vec3(-625.70, -237.80, 38.05), vec3(-626.70, -238.58, 38.05),
                vec3(-624.55, -231.06, 38.05), vec3(-623.13, -232.94, 38.05), vec3(-620.29, -234.44, 38.05),
                vec3(-619.15, -233.66, 38.05), vec3(-620.19, -233.44, 38.05), vec3(-617.63, -230.58, 38.05),
                vec3(-618.33, -229.55, 38.05), vec3(-619.70, -230.33, 38.05), vec3(-620.95, -228.60, 38.05),
                vec3(-619.79, -227.60, 38.05), vec3(-620.42, -226.60, 38.05), vec3(-623.94, -227.18, 38.05),
                vec3(-624.91, -227.87, 38.05), vec3(-623.94, -228.05, 38.05),
            },
        },
    },
}
