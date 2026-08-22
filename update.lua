local INSTALLER_URL = "https://raw.githubusercontent.com/NightJuan/Minecraft-Turtle/main/install.lua"
local TEMP_INSTALLER = "/.turtle-installer.lua"

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
local file = fs.open(TEMP_INSTALLER, "w")
file.write(response.readAll())
file.close()
response.close()

local ok = shell.run(TEMP_INSTALLER)
if fs.exists(TEMP_INSTALLER) then fs.delete(TEMP_INSTALLER) end

if not ok then
    print("The updater stopped before completion.")
end
