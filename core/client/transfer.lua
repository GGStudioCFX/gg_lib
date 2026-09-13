
local function forward(name)
    return function(data, cb)
        local ok, result = GGCallback.await(name, {
            resource = data and data.resource,
            changes  = data and data.changes,
            text     = data and data.text,
        })

        cb({ ok = ok == true, result = ok and result or nil, errors = ok and nil or result })
    end
end

RegisterNUICallback("settings_check", forward("gg_lib:settings:check"))
RegisterNUICallback("settings_export_file", forward("gg_lib:settings:export_file"))
RegisterNUICallback("settings_import_file", forward("gg_lib:settings:import_file"))
