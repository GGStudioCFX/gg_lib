gg.dispatch = gg.dispatch or {}

gg.dispatch.alert = function(data)
    local dispatchData = {
        id = 0,
        event = 'NEW ALERT',
        title = data.message,
        description = data.message,
        code = data.code,
        codeName = (data.code or ''):lower():gsub('%W', ''),
        coords = data.coords,
        icon = data.icon or 'suspect',
        time = data.time or 10000,
        priority = data.priority or 1,
        img = "",
        street = data.street or 'Unknown',
        gender = data.gender or nil,
        recipientJobs = data.jobs
    }

    exports.dusa_dispatch:CustomDispatch(dispatchData)
end
