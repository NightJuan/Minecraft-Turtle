local OWNER = "NightJuan"
local REPOSITORY = "Minecraft-Turtle"
local BRANCH = "main"
local RAW_BASE = "https://raw.githubusercontent.com/" .. OWNER .. "/" ..
    REPOSITORY .. "/" .. BRANCH .. "/"

local FILES = {
    "install.lua",
    "update.lua",
    "startup.lua",
    "setup.lua",
    "main.lua",
    "core/identity.lua",
    "core/jobs.lua",
    "core/map.lua",
    "core/movement.lua",
    "core/navigation.lua",
    "core/pathfinder.lua",
    "core/scanner.lua",
    "core/state.lua",
    "network/client.lua"
}

local STAGE = "/.turtle-install-stage"
local BACKUP = "/.turtle-install-backup"

local function parent(path)
    return fs.getDir(path)
end

local function makeParent(path)
    local directory = parent(path)
    if directory ~= "" and not fs.exists(directory) then
        fs.makeDir(directory)
    end
end

local function remove(path)
    if fs.exists(path) then fs.delete(path) end
end

local function download(path)
    local url = RAW_BASE .. path
    local response, reason, failedResponse = http.get(url, {
        ["Accept"] = "text/plain",
        ["User-Agent"] = "Minecraft-Turtle-Installer"
    })
    if not response then
        if failedResponse then failedResponse.close() end
        return false, reason or "download failed"
    end

    local code = response.getResponseCode()
    if code < 200 or code >= 300 then
        response.close()
        return false, "HTTP " .. tostring(code)
    end

    local destination = fs.combine(STAGE, path)
    makeParent(destination)
    local file = fs.open(destination, "w")
    if not file then
        response.close()
        return false, "could not create staged file"
    end
    file.write(response.readAll())
    file.close()
    response.close()
    return true
end

local function rollback(applied)
    print("Restoring previous files...")
    for index = #applied, 1, -1 do
        local path = applied[index]
        local destination = "/" .. path
        local backup = fs.combine(BACKUP, path)
        remove(destination)
        if fs.exists(backup) then
            makeParent(destination)
            fs.move(backup, destination)
        end
    end
end

term.clear()
term.setCursorPos(1, 1)
print("=== Turtle Command Center Installer ===")
print("Source: " .. OWNER .. "/" .. REPOSITORY)
print()

if not http then
    print("HTTP is disabled. Enable it in the CC:Tweaked configuration.")
    return
end

local allowed, reason = http.checkURL(RAW_BASE .. "main.lua")
if not allowed then
    print("GitHub downloads are blocked:")
    print(tostring(reason))
    return
end

remove(STAGE)
remove(BACKUP)
fs.makeDir(STAGE)
fs.makeDir(BACKUP)

print("Downloading " .. #FILES .. " files...")
for index, path in ipairs(FILES) do
    write(index .. "/" .. #FILES .. " " .. path .. " ... ")
    local ok, failure = download(path)
    if not ok then
        print("FAILED")
        print(tostring(failure))
        remove(STAGE)
        remove(BACKUP)
        print("No installed files were changed.")
        return
    end
    print("OK")
end

local applied = {}
for _, path in ipairs(FILES) do
    local destination = "/" .. path
    local staged = fs.combine(STAGE, path)
    local backup = fs.combine(BACKUP, path)

    if fs.exists(destination) then
        makeParent(backup)
        fs.move(destination, backup)
    end

    makeParent(destination)
    local ok, failure = pcall(fs.move, staged, destination)
    table.insert(applied, path)
    if not ok then
        print("Install failed at " .. path .. ": " .. tostring(failure))
        rollback(applied)
        remove(STAGE)
        remove(BACKUP)
        return
    end
end

remove(STAGE)
remove(BACKUP)
print()
print("Installation complete. Saved /data was preserved.")

if not fs.exists("/data/config.json") then
    print("Starting first-time setup...")
    shell.run("/setup.lua")
else
    print("Starting turtle...")
    shell.run("/main.lua")
end
