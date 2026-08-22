local state = {}

local identity = require("core.identity")

local STATE_FILE = "/data/bot.json"

local function save(data)
    if not fs.exists("/data") then
        fs.makeDir("/data")
    end
    local file = fs.open(STATE_FILE, "w")

    file.write(textutils.serializeJSON(data))
    file.close()
end

function state.load()
    if fs.exists(STATE_FILE) then
        local file = fs.open(STATE_FILE, "r")
        local contents = file.readAll()
        file.close()

        local loaded = textutils.unserializeJSON(contents)

        if type(loaded) == "table" then
            loaded.task = loaded.task or "Idle"
            loaded.mode = loaded.mode or "manual"
            loaded.position = loaded.position or { x = 0, y = 0, z = 0 }
            loaded.facing = loaded.facing or 0
            loaded.home = loaded.home or {
                x = loaded.position.x,
                y = loaded.position.y,
                z = loaded.position.z,
                facing = loaded.facing
            }
            loaded.locations = loaded.locations or {}
            save(loaded)
            return loaded
        end
    end

    local new_state = {
        id = identity.getID(),
        name = identity.generateName(),

        task = "Idle",
        mode = "manual",

        position = {
            x = 0,
            y = 0,
            z = 0
        },

        facing = 0,

        home = {
            x = 0,
            y = 0,
            z = 0,
            facing = 0
        },
        locations = {}
    }

    save(new_state)

    return new_state
end

function state.setHome(data)
    data.home = {
        x = data.position.x,
        y = data.position.y,
        z = data.position.z,
        facing = data.facing
    }
    save(data)
end

function state.setLocation(data, name)
    data.locations = data.locations or {}
    data.locations[name] = {
        x = data.position.x,
        y = data.position.y,
        z = data.position.z,
        facing = data.facing
    }
    save(data)
end

function state.save(data)
    save(data)
end

return state
