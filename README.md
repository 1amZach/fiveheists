# fiveheists

Store, ATM, Fleeca and jewelry store robberies. The client only asks; the server checks every step and decides what you get, so a cheat menu can't skip to the payout.

## Features

- Registers and safes in 24/7, LTD and Rob's Liquor stores, ATMs, the six Fleeca branches and Vangelico
- Skill checks and progress circles from ox_lib
- ox_target when it's running, otherwise walk up and press **E**
- Police needed per robbery type, and an alert with a map blip for on-duty police
- Cooldowns per location and per type, kept through restarts
- Qbox, QBCore and ESX. Items through ox_inventory when it's running, otherwise the framework's inventory
- Every start, step, payout, failure and refusal logged

### What the server checks

Each step is two calls: start and finish. On start the server checks the player is standing at the register, case or box, has the item, the place isn't on cooldown, enough police are on and nobody else is on the same target. On finish it checks the player started this exact step, is still there, still has the item, and that at least the step's duration has passed. Only then does it roll the reward and pay it. A case, box or register can only be emptied once per robbery.

Anything that can only be a cheat (finishing something never started, claiming loot from across the map, finishing in half the time) is refused and sent to warden. Walking away or a laggy finish is just refused.

## Robberies

| | Needs | Police | Gives |
|---|---|---|---|
| Store register | `lockpick`, may break on a failed check | 2 | $250 to $600, sometimes a note with the safe code |
| Store safe | the code, or a `drill` and a minute | 2 | $1,500 to $3,500, sometimes a `goldchain` |
| ATM | `drill`, may break | 1 | $800 to $2,000 |
| Fleeca | `trojan_usb` to hack the vault panel, used up when it works | 4 | $2,500 to $5,000 per deposit box, sometimes a `goldbar` |
| Vangelico | any weapon out, to smash the cases | 5 | `rolex`, `goldchain` or `diamond_ring` per case |

- **Stores:** each register and the safe once per robbery. A wrong safe code three times locks the keypad until the next one. The code changes every robbery.
- **Fleeca:** once the panel is hacked the vault door opens for everyone, then the five deposit boxes are emptied one at a time. The door closes when the robbery ends.
- **Vangelico:** 20 cases, each one once.

All numbers, items and locations are in `config.lua`.

## With the others

- **[fiveboard](https://github.com/1amZach/fiveboard):** the board shows each robbery type busy while one is going and the cooldown after. Its police count is used, so the board and the robberies always agree.
- **[fivelog](https://github.com/1amZach/fivelog):** everything goes in under the `heists` kind, with amounts.
- **[fivepanel](https://github.com/1amZach/fivepanel):** shows those logs.
- **[warden](https://github.com/1amZach/warden):** clear exploits are flagged as `teleport`, which only logs on warden's defaults. Set `Config.flagKind` to something harsher if you want kicks or bans.

## Install

Needs [ox_lib](https://github.com/overextended/ox_lib).

1. Drop `fiveheists` into your resources and add to `server.cfg` after ox_lib and your framework:

   ```
   ensure fiveheists
   ```

2. Let staff use `/heists`:

   ```
   add_ace group.admin fiveheists.admin allow
   ```

3. Add the items if you don't have them. QBCore ships with all of them.

   ox_inventory, `data/items.lua`:

   ```lua
   ['lockpick'] = { label = 'Lockpick', weight = 100 },
   ['drill'] = { label = 'Drill', weight = 3000, stack = false },
   ['trojan_usb'] = { label = 'Trojan USB', weight = 50 },
   ['rolex'] = { label = 'Rolex', weight = 150 },
   ['goldchain'] = { label = 'Gold chain', weight = 150 },
   ['diamond_ring'] = { label = 'Diamond ring', weight = 100 },
   ['goldbar'] = { label = 'Gold bar', weight = 1000 },
   ```

   QBCore, `qb-core/shared/items.lua`:

   ```lua
   lockpick = { name = 'lockpick', label = 'Lockpick', weight = 100, type = 'item', image = 'lockpick.png', unique = false, useable = false, shouldClose = false, description = 'Opens what it shouldn\'t' },
   drill = { name = 'drill', label = 'Drill', weight = 3000, type = 'item', image = 'drill.png', unique = false, useable = false, shouldClose = false, description = 'Heavy duty drill' },
   trojan_usb = { name = 'trojan_usb', label = 'Trojan USB', weight = 50, type = 'item', image = 'usb_device.png', unique = false, useable = false, shouldClose = false, description = 'Handy software to shut down some systems' },
   rolex = { name = 'rolex', label = 'Rolex', weight = 150, type = 'item', image = 'rolex.png', unique = false, useable = false, shouldClose = false, description = 'A golden watch' },
   goldchain = { name = 'goldchain', label = 'Gold chain', weight = 150, type = 'item', image = 'goldchain.png', unique = false, useable = false, shouldClose = false, description = 'A golden chain' },
   diamond_ring = { name = 'diamond_ring', label = 'Diamond ring', weight = 100, type = 'item', image = 'diamond_ring.png', unique = false, useable = false, shouldClose = false, description = 'A diamond ring' },
   goldbar = { name = 'goldbar', label = 'Gold bar', weight = 1000, type = 'item', image = 'goldbar.png', unique = false, useable = false, shouldClose = false, description = 'Looks pretty expensive' },
   ```

   ESX without ox_inventory:

   ```sql
   INSERT IGNORE INTO items (name, label, weight) VALUES
       ('lockpick', 'Lockpick', 1), ('drill', 'Drill', 3), ('trojan_usb', 'Trojan USB', 1),
       ('rolex', 'Rolex', 1), ('goldchain', 'Gold chain', 1), ('diamond_ring', 'Diamond ring', 1), ('goldbar', 'Gold bar', 1);
   ```

## Config

`config.lua`:

| | |
|---|---|
| `Config.policeJobs` | Jobs that count as police without fiveboard, and get alerts |
| `Config.fiveboardGroup` | The fiveboard group counted when it's running |
| `Config.money` | Paid as cash, an ESX account, an item count, or QBCore marked bills with `worth` |
| `Config.flagCheaters`, `flagKind` | Send clear exploits to warden, and as what |
| `Config.flagDistance` | How far off a finish has to be to count as an exploit |
| `Config.saveCooldowns` | Keep cooldowns in `cooldowns.json` |
| `Config.rate` | Milliseconds between starts, and starts per minute |
| `Config.reach`, `slack` | Metres from a target, and how early a step may finish for lag |
| `Config.alert` | Blip for the default alert |
| `Config.store`, `atm`, `fleeca`, `jewelry` | `police`, `cooldown`, `global`, `window`, `max`, then items, durations, skill checks, rewards and locations |

`cooldown` is per location, `global` for the whole type, `window` how long a robbery stays open once started, and `max` how many of a type can run at once.

`Config.atm.anyModel` lets every ATM on the map be drilled instead of the listed ones. The server can't see where map props are, so it has to trust the position the client sends, as long as it's next to the player. Leave it off unless you need it.

## Dispatch

`server/dispatch.lua` is called once when a robbery starts. By default every on-duty police player gets a notification and a flashing blip for two minutes. Replace the function with your dispatch script; the file has examples for ps-dispatch and cd_dispatch.

```lua
function Config.dispatch(data)
    -- data.type, data.id, data.label, data.coords, data.src
end
```

## For other resources

```lua
-- 'fleeca:legion' for one bank, or 'fleeca' for any of them
exports.fiveheists:isActive('fleeca')

-- seconds left, 0 when it's open
exports.fiveheists:getCooldown('store:grove')

-- a location, a type with all its locations, or 'all'
exports.fiveheists:resetCooldown('jewelry')
```

Server events:

```lua
AddEventHandler('fiveheists:started', function(id, kind, src) end)
AddEventHandler('fiveheists:finished', function(id, kind, reason) end) -- 'emptied' or 'time'
```

Staff and the console: `/heists` lists what's running and on cooldown, `/heists reset <id|type|all>` clears cooldowns.

## Testing

```
lua5.4 test/run.lua
```

Runs the server side against a fake FiveM server with Qbox, QBCore and ESX.

## Support

Made by **IamZach**. Questions, bugs or ideas: [discord.gg/agn](https://discord.gg/agn)

## License

MIT
