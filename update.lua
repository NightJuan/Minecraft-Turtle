local INSTALLER_URL = "https://raw.githubusercontent.com/NightJuan/Minecraft-Turtle/main/install.lua"
local TEMP_INSTALLER = "/.turtle-installer.lua"
local RESULT_FILE = "/.turtle-install-result"

print("Checking GitHub for the latest turtle software...")

local response, reason, failedResponse = http.get(INSTALLER_URL, {
    ["Accept"] = "text/plain",
    ["User-Agent"] = "Minecraft-Turtle-Updater"
})

if not response then
    if failedResponse then failedResponse.close() end
    print("Update failed: " .. tostring(reason))
    return
end

local code = response.getResponseCode()
if code < 200 or code >= 300 then
    response.close()
    print("Update failed: HTTP " .. tostring(code))
    return
end

if fs.exists(TEMP_INSTALLER) then fs.delete(TEMP_INSTALLER) end
if fs.exists(RESULT_FILE) then fs.delete(RESULT_FILE) end
local file = fs.open(TEMP_INSTALLER, "w")
file.write(response.readAll())
file.close()
response.close()

local ok = shell.run(TEMP_INSTALLER, "--no-start")
if fs.exists(TEMP_INSTALLER) then fs.delete(TEMP_INSTALLER) end

local installed = false
if ok and fs.exists(RESULT_FILE) then
    local result = fs.open(RESULT_FILE, "r")
    installed = result.readAll() == "ok"
    result.close()
end
if fs.exists(RESULT_FILE) then fs.delete(RESULT_FILE) end

if not installed then
    print("The updater stopped before completion.")
    return
end

print("Update installed. Rebooting...")
sleep(1)
os.reboot()
