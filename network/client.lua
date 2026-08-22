local client = {}

local SERVER_URL = "https://dancing-controls-rights-moses.trycloudflare.com"
local CONFIG_FILE = "/data/config.json"
if fs.exists(CONFIG_FILE) then
    local file = fs.open(CONFIG_FILE, "r")
    local config = textutils.unserializeJSON(file.readAll())
    file.close()
    if type(config) == "table" and type(config.server_url) == "string" and
        config.server_url ~= "" then
        SERVER_URL = string.gsub(config.server_url, "/+$", "")
    end
end
local OUTBOX_FILE = "/data/network_outbox.json"
local MAX_MAP_OUTBOX = 512
local connected = true
local flushing = false

local function safeClose(response)
    if response then
        pcall(function()
            response.close()
        end)
    end
end

local function loadOutbox()
    if not fs.exists(OUTBOX_FILE) then return { state = nil, map = {} } end
    local file = fs.open(OUTBOX_FILE, "r")
    local contents = file.readAll()
    file.close()
    local data = textutils.unserializeJSON(contents)
    if type(data) ~= "table" then return { state = nil, map = {} } end
    data.map = data.map or {}
    return data
end

local outbox = loadOutbox()

local function saveOutbox()
    local file = fs.open(OUTBOX_FILE, "w")
    file.write(textutils.serializeJSON(outbox))
    file.close()
end

local function postJSON(url, payload)
    local response = http.post(
        url,
        textutils.serializeJSON(payload),
        { ["Content-Type"] = "application/json" }
    )
    if not response then connected = false; return false end
    local code = response.getResponseCode()
    safeClose(response)
    connected = code >= 200 and code < 300
    return connected
end

local function queueMap(botID, blocks)
    local indexes = {}
    for index, entry in ipairs(outbox.map) do indexes[entry.key] = index end
    for _, block in ipairs(blocks) do
        local key = block.x .. "," .. block.y .. "," .. block.z
        local entry = { key = key, bot_id = botID, block = block }
        if indexes[key] then
            outbox.map[indexes[key]] = entry
        else
            outbox.map[#outbox.map + 1] = entry
            indexes[key] = #outbox.map
        end
    end
    while #outbox.map > MAX_MAP_OUTBOX do table.remove(outbox.map, 1) end
    saveOutbox()
end

function client.isConnected()
    return connected
end

function client.flushOutbox()
    if flushing then return false end
    flushing = true

    if outbox.state then
        if not postJSON(SERVER_URL .. "/bot/state", outbox.state) then
            flushing = false
            return false
        end
        outbox.state = nil
        saveOutbox()
    end

    while #outbox.map > 0 do
        local blocks = {}
        local count = math.min(#outbox.map, 100)
        local botID = outbox.map[1].bot_id
        for index = 1, count do blocks[index] = outbox.map[index].block end
        if not postJSON(SERVER_URL .. "/map/update", {
            bot_id = botID, blocks = blocks
        }) then
            flushing = false
            return false
        end
        for _ = 1, count do table.remove(outbox.map, 1) end
        saveOutbox()
    end

    flushing = false
    return true
end


function client.sendState(bot)
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then fuel = -1 end
    local inventory = {}
    for slot = 1, 16 do
        local detail = turtle.getItemDetail(slot)
        inventory[slot] = detail and {
            slot = slot, name = detail.name, count = detail.count
        } or { slot = slot, count = 0 }
    end

    local payload = {
        id = bot.id,
        name = bot.name,
        task = bot.task,
        mode = bot.mode,

        position = {
            x = bot.position.x,
            y = bot.position.y,
            z = bot.position.z
        },

        facing = bot.facing,
        fuel = fuel,
        fuel_limit = turtle.getFuelLimit(),
        inventory = inventory,
        home = bot.home,
        locations = bot.locations or {}
        ,software_version = bot.software_version or "unknown"
    }

    local body = textutils.serializeJSON(payload)

    local response, errorMessage = http.post(
        SERVER_URL .. "/bot/state",
        body,
        {
            ["Content-Type"] = "application/json"
        }
    )

    if not response then
        print("Failed to send bot state:")
        print(errorMessage)
        connected = false
        outbox.state = payload
        saveOutbox()
        return false
    end

    local responseCode = response.getResponseCode()
    safeClose(response)

    if responseCode < 200 or responseCode >= 300 then
        connected = false
        outbox.state = payload
        saveOutbox()
        return false
    end

    connected = true
    if outbox.state then
        outbox.state = nil
        saveOutbox()
    end

    return true
end


function client.getNextCommand(botID)
    local url =
        SERVER_URL ..
        "/bots/" ..
        tostring(botID) ..
        "/commands/next"

    local response, errorMessage = http.get(
        url,
        {
            ["Accept"] = "application/json"
        }
    )

    if not response then
        print("Failed to check commands:")
        print(errorMessage)
        return nil
    end

    local responseCode = response.getResponseCode()
    local body = response.readAll()

    safeClose(response)

    if responseCode ~= 200 then
        print("Command server returned:")
        print(responseCode)
        print(body)
        return nil
    end

    local success, data = pcall(
        textutils.unserializeJSON,
        body
    )

    if not success or type(data) ~= "table" then
        print("Invalid command response")
        return nil
    end

    return data.command
end

function client.reportCommandResult(
    botID,
    commandID,
    status,
    message,
    stepsCompleted
)
    local url =
        SERVER_URL ..
        "/bots/" ..
        tostring(botID) ..
        "/commands/" ..
        tostring(commandID) ..
        "/result"

    local payload = {
        status = status,
        message = message or "",
        steps_completed = stepsCompleted or 0
    }

    local response, errorMessage = http.post(
        url,
        textutils.serializeJSON(payload),
        {
            ["Content-Type"] = "application/json"
        }
    )

    if not response then
        print("Failed to report command result:")
        print(errorMessage)
        return false
    end

    local responseCode = response.getResponseCode()
    safeClose(response)

    if responseCode < 200 or responseCode >= 300 then
        print("Command result rejected:")
        print(responseCode)
        return false
    end

    return true
end

function client.reportCommandProgress(botID, commandID, stepsCompleted, message)
    local url = SERVER_URL .. "/bots/" .. tostring(botID) ..
        "/commands/" .. tostring(commandID) .. "/progress"
    local response = http.post(
        url,
        textutils.serializeJSON({
            steps_completed = stepsCompleted or 0,
            message = message or "Working"
        }),
        { ["Content-Type"] = "application/json" }
    )
    if not response then return false end
    local code = response.getResponseCode()
    safeClose(response)
    return code >= 200 and code < 300
end

function client.sendMapUpdate(botID, blocks)
    local payload = {
        bot_id = botID,
        blocks = blocks
    }

    local response, errorMessage = http.post(
        SERVER_URL .. "/map/update",
        textutils.serializeJSON(payload),
        {
            ["Content-Type"] = "application/json"
        }
    )

    if not response then
        print("Failed to send map update:")
        print(errorMessage)
        connected = false
        queueMap(botID, blocks)
        return false
    end

    local responseCode = response.getResponseCode()
    safeClose(response)

    if responseCode < 200 or responseCode >= 300 then
        connected = false
        queueMap(botID, blocks)
        return false
    end

    connected = true

    return true
end

function client.sendPlannedRoute(botID, points, cost)
    local response, errorMessage = http.post(
        SERVER_URL .. "/routes",
        textutils.serializeJSON({
            bot_id = botID,
            points = points,
            cost = cost or 0
        }),
        { ["Content-Type"] = "application/json" }
    )
    if not response then
        print("Failed to send planned route:")
        print(errorMessage)
        return false
    end
    safeClose(response)
    return true
end

function client.clearPlannedRoute(botID)
    local response, errorMessage = http.post(
        SERVER_URL .. "/routes/" .. tostring(botID) .. "/clear",
        "{}",
        { ["Content-Type"] = "application/json" }
    )
    if not response then
        print("Failed to clear planned route:")
        print(errorMessage)
        return false
    end
    safeClose(response)
    return true
end


function client.getEmergencyStop(botID)
    local url =
        SERVER_URL ..
        "/bots/" ..
        tostring(botID) ..
        "/emergency-stop"

    local response, errorMessage = http.get(
        url,
        {
            ["Accept"] = "application/json"
        }
    )

    if not response then
        print("Failed to check emergency stop:")
        print(errorMessage)
        return false
    end

    local body = response.readAll()
    safeClose(response)

    local success, data = pcall(
        textutils.unserializeJSON,
        body
    )

    if not success or type(data) ~= "table" then
        return false
    end

    return data.stop_requested == true
end

function client.getJobControl(botID, commandID)
    local url = SERVER_URL .. "/bots/" .. tostring(botID) ..
        "/jobs/" .. tostring(commandID) .. "/control"
    local response = http.get(url, { ["Accept"] = "application/json" })
    if not response then return "running" end
    local body = response.readAll()
    safeClose(response)
    local success, data = pcall(textutils.unserializeJSON, body)
    if success and type(data) == "table" and type(data.state) == "string" then
        return data.state
    end
    return "running"
end


function client.acknowledgeEmergencyStop(botID)
    local url =
        SERVER_URL ..
        "/bots/" ..
        tostring(botID) ..
        "/emergency-stop/ack"

    local response, errorMessage = http.post(
        url,
        "{}",
        {
            ["Content-Type"] = "application/json"
        }
    )

    if not response then
        print("Failed to acknowledge stop:")
        print(errorMessage)
        return false
    end

    safeClose(response)
    return true
end

return client
