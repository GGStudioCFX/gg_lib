
gg.display = gg.display or {}

gg.display.webhook = function(webhook, payload)
    if type(webhook) ~= "string" or webhook == "" then return end
    if type(payload) ~= "table" then return end

    local resourceName = GetCurrentResourceName()

    local embed = {
        {
            ["color"] = payload.color or 16777215,
            ["title"] = "**" .. (payload.title or "No Title") .. "**",
            ["description"] = payload.description or "",
            ["footer"] = {
                ["text"] = (payload.footer or "Event Log") .. " • " .. resourceName,
            },
            ["timestamp"] = os.date("!%Y-%m-%dT%H:%M:%SZ")
        }
    }

    local body = {
        username = payload.username or ("Logger • " .. resourceName),
        avatar_url = payload.avatar_url,
        embeds = embed
    }

    PerformHttpRequest(webhook, function(err, text, headers)
        if err ~= 200 and err ~= 204 then
            print(("[^1ERROR^7] Webhook from %s failed. Code: %s | Message: %s")
                :format(resourceName, tostring(err), tostring(text)))
        end
    end, 'POST', json.encode(body), { ["Content-Type"] = "application/json" })
end
