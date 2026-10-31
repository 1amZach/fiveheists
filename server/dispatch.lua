-- Called once when a robbery starts. Swap the body for your dispatch script.
--   data.type    'store', 'atm', 'fleeca' or 'jewelry'
--   data.id      the location, like 'fleeca:legion'
--   data.label   'Fleeca Legion Square'
--   data.coords  where it started
--   data.src     the robber's server id
function Config.dispatch(data)
    for _, src in ipairs(Framework.police()) do
        TriggerClientEvent('fiveheists:alert', src, data)
    end
end

--[[ ps-dispatch (v2)

function Config.dispatch(data)
    TriggerEvent('ps-dispatch:server:notify', {
        message = data.label,
        codeName = 'storerobbery',
        code = '10-90',
        icon = 'fas fa-mask',
        priority = 2,
        coords = data.coords,
        jobs = { 'leo' },
    })
end
]]

--[[ cd_dispatch

function Config.dispatch(data)
    TriggerClientEvent('cd_dispatch:AddNotification', -1, {
        job_table = Config.policeJobs,
        coords = data.coords,
        title = '10-90 - ' .. data.label,
        message = 'Robbery in progress at ' .. data.label,
        flash = 0,
        unique_id = data.id .. ':' .. os.time(),
        sound = 1,
        blip = { sprite = 161, scale = 1.2, colour = 1, flashes = true, text = data.label, time = 5, radius = 0 },
    })
end
]]
