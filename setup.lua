local state = require("core.state")

local CONFIG_FILE = "/data/config.json"
local DEFAULT_SERVER = "https://dancing-controls-rights-moses.trycloudflare.com"

local function ask(prompt, default)
    write(prompt)
    if default ~= nil then write(" [" .. tostring(default) .. "]") end
    write(": ")
    local value = read()
    if value == "" and default ~= nil then return tostring(default) end
    return value
end

local function askNumber(prompt, default)
    while true do
        local value = tonumber(ask(prompt, default))
        if value and value == math.floor(value) then return value end
        print("Please enter a whole number.")
    end
end

local function askYesNo(prompt, defaultYes)
    local hint = defaultYes and "Y/n" or "y/N"
    while true do
        write(prompt .. " (" .. hint .. "): ")
        local value = string.lower(read())
        if value == "" then return defaultYes end
        if value == "y" or value == "yes" then return true end
        if value == "n" or value == "no" then return false end
        print("Please answer y or n.")
    end
end

local function loadConfig()
    if not fs.exists(CONFIG_FILE) then return {} end
    local file = fs.open(CONFIG_FILE, "r")
    local data = textutils.unserializeJSON(file.readAll())
    file.close()
    return type(data) == "table" and data or {}
end

local function saveConfig(config)
    if not fs.exists("/data") then fs.makeDir("/data") end
    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serializeJSON(config))
    file.close()
end

local function testServer(serverURL)
    write("Checking server... ")
    local response, reason = http.get(serverURL .. "/bots", {
        ["Accept"] = "application/json"
    })
    if not response then
        print("FAILED")
        print(tostring(reason))
        return false
    end
    local code = response.getResponseCode()
    response.close()
    if code >= 200 and code < 300 then
        print("CONNECTED")
        return true
    end
    print("HTTP " .. tostring(code))
    return false
end

term.clear()
term.setCursorPos(1, 1)
print("=== Turtle Command Center Setup ===")
print()

if not turtle then
    print("This installer must run on a turtle.")
    return
end

if not fs.exists("/core/state.lua") or not fs.exists("/main.lua") then
    print("Missing program files.")
    print("Copy core, network, and main.lua first.")
    return
end

local bot = state.load()
local config = loadConfig()

if config.setup_complete == true then
    print("Existing bot: " .. tostring(bot.name))
    print("ID: " .. tostring(bot.id))
    if not askYesNo("Change its setup", false) then
        print("Setup left unchanged.")
        return
    end
end

print("Computer ID: " .. tostring(bot.id))
bot.name = ask("Bot name", bot.name)
if bot.name == "" then bot.name = "Turtle " .. tostring(bot.id) end

print()
print("Enter the turtle's current Minecraft coordinates.")
bot.position = {
    x = askNumber("X", bot.position and bot.position.x or 0),
    y = askNumber("Y", bot.position and bot.position.y or 0),
    z = askNumber("Z", bot.position and bot.position.z or 0)
}

print()
print("Facing: 0 North, 1 East, 2 South, 3 West")
while true do
    bot.facing = askNumber("Direction", bot.facing or 0)
    if bot.facing >= 0 and bot.facing <= 3 then break end
    print("Direction must be 0, 1, 2, or 3.")
end

bot.home = {
    x = bot.position.x,
    y = bot.position.y,
    z = bot.position.z,
    facing = bot.facing
}
bot.task = "Idle"
bot.mode = "manual"
bot.locations = bot.locations or {}
state.save(bot)

local serverURL = ask("Server address", config.server_url or DEFAULT_SERVER)
serverURL = string.gsub(serverURL, "/+$", "")
config.server_url = serverURL
config.setup_complete = true
saveConfig(config)

print()
print("Saved " .. bot.name .. " (ID " .. tostring(bot.id) .. ")")
print("Home: " .. bot.position.x .. ", " .. bot.position.y .. ", " .. bot.position.z)

local connected = testServer(serverURL)
if not connected then
    print("Setup is saved. Check HTTP access and the server address.")
end

if askYesNo("Start the turtle now", connected) then
    shell.run("/main.lua")
else
    print("Run 'main' when ready.")
end
