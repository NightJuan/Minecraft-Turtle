local manufacturing = {}
local movement = require("core.movement")

local IRON = { [1]=true,[2]=true,[3]=true,[5]=true,[7]=true,[9]=true,[11]=true }

local function item(slot) return turtle.getItemDetail(slot) end

local function findItem(pattern)
    for slot = 1, 16 do
        local detail = item(slot)
        if detail and string.find(detail.name, pattern, 1, true) then return slot end
    end
end

local function moveItem(from, destination)
    if from == destination then return true end
    turtle.select(from)
    return turtle.transferTo(destination)
end

local function validateRecipe()
    for slot = 1, 16 do
        local detail = item(slot)
        if IRON[slot] then
            if not detail or detail.name ~= "minecraft:iron_ingot" or detail.count ~= 1 then
                return false, "Put one iron ingot in slots 1,2,3,5,7,9,11"
            end
        elseif slot == 6 then
            if not detail or not string.find(detail.name, "computer", 1, true) then
                return false, "Put one Computer in slot 6"
            end
        elseif slot == 10 then
            if not detail or detail.name ~= "minecraft:chest" then
                return false, "Put one chest in slot 10"
            end
        elseif slot == 4 then
            if not detail or detail.name ~= "minecraft:crafting_table" then
                return false, "Put one crafting table in slot 4"
            end
        elseif detail then
            return false, "Slot " .. slot .. " must be empty"
        end
    end
    return true
end

local function validateLocker()
    local locker = peripheral.wrap("top")
    if not locker or type(locker.list) ~= "function" then
        return false, "Place a Tool Locker chest above the parent turtle"
    end
    local contents = locker.list()
    local pick = contents[1]
    if not pick or pick.name ~= "minecraft:diamond_pickaxe" or pick.count ~= 1 then
        return false, "Tool Locker slot 1 needs one child diamond pickaxe"
    end
    for slot, detail in pairs(contents) do
        if slot ~= 1 and detail.count > 0 then
            return false, "Tool Locker must contain only the child pick in slot 1"
        end
    end
    return true
end

local function bootstrapSource()
    return [[
local INSTALLER = "https://raw.githubusercontent.com/NightJuan/Minecraft-Turtle/main/install.lua"
local provisionFile = fs.open("/disk/provision.json", "r")
if not provisionFile then error("Missing commissioning data", 0) end
local provision = textutils.unserializeJSON(provisionFile.readAll())
provisionFile.close()
local response, reason = http.get(INSTALLER)
if not response then error("Installer download failed: " .. tostring(reason), 0) end
local installer = fs.open("/.child-install.lua", "w")
installer.write(response.readAll()); installer.close(); response.close()
if not shell.run("/.child-install.lua", "--no-start") then error("Installation failed", 0) end
fs.delete("/.child-install.lua")
if not fs.exists("/data") then fs.makeDir("/data") end
local id = os.getComputerID()
local bot = {
    id=id, name="Turtle " .. id, task="Awaiting Approval", mode="commissioning",
    position=provision.position, facing=provision.facing,
    home={x=provision.position.x,y=provision.position.y,z=provision.position.z,facing=provision.facing},
    locations={}, commissioning=true, parent_id=provision.parent_id
}
local stateFile = fs.open("/data/bot.json", "w")
stateFile.write(textutils.serializeJSON(bot)); stateFile.close()
local configFile = fs.open("/data/config.json", "w")
configFile.write(textutils.serializeJSON({server_url=provision.server_url,setup_complete=true})); configFile.close()
os.setComputerLabel(bot.name)
shell.run("/main.lua")
]]
end

local function prepareBootDisk(bot)
    if turtle.detect() then return false, "Child spawn block in front is occupied" end
    local moved, reason = movement.forward(bot)
    if not moved then return false, reason end
    local drive = peripheral.wrap("bottom")
    if not drive or peripheral.getType("bottom") ~= "drive" or not drive.hasData() then
        movement.back(bot)
        return false, "Place a disk drive with a writable floppy below the child spawn"
    end
    local mount = drive.getMountPath()
    if not mount then movement.back(bot); return false, "Bootstrap floppy has no data mount" end
    local configFile = fs.open("/data/config.json", "r")
    local config = configFile and textutils.unserializeJSON(configFile.readAll()) or {}
    if configFile then configFile.close() end
    if not config.server_url then movement.back(bot); return false, "Parent server address is not configured" end
    local provision = {
        parent_id=bot.id, server_url=config.server_url,
        position={x=bot.position.x,y=bot.position.y,z=bot.position.z},
        facing=(bot.facing + 2) % 4
    }
    local startup = fs.open("/" .. mount .. "/startup.lua", "w")
    local provisionFile = fs.open("/" .. mount .. "/provision.json", "w")
    if not startup or not provisionFile then
        if startup then startup.close() end
        if provisionFile then provisionFile.close() end
        movement.back(bot)
        return false, "Bootstrap floppy is not writable"
    end
    startup.write(bootstrapSource()); startup.close()
    provisionFile.write(textutils.serializeJSON(provision)); provisionFile.close()
    movement.back(bot)
    return true
end

local function restoreParentPick()
    local unequipSlot
    for slot = 1, 16 do if not item(slot) then unequipSlot = slot break end end
    if unequipSlot then turtle.select(unequipSlot); turtle.equipLeft() end
    for _ = 1, 3 do
        local target
        for slot = 1, 16 do if not item(slot) then target = slot break end end
        if not target then break end
        turtle.select(target)
        if not turtle.suckUp(1) then break end
        local detail = item(target)
        if detail and detail.name == "minecraft:diamond_pickaxe" then
            turtle.equipLeft()
            return true
        end
        turtle.dropUp()
    end
    return false
end

function manufacturing.buildChild(bot)
    local valid, reason = validateRecipe()
    if not valid then return false, reason end
    valid, reason = validateLocker()
    if not valid then return false, reason end
    valid, reason = prepareBootDisk(bot)
    if not valid then return false, reason end

    turtle.select(4)
    local equipped, equipReason = turtle.equipLeft()
    if not equipped or type(turtle.craft) ~= "function" then
        return false, equipReason or "Unable to equip crafting table"
    end
    if not turtle.dropUp(1) then turtle.equipLeft(); return false, "Tool Locker could not accept the parent pickaxe" end
    if not turtle.craft(0) or not turtle.craft(1) then
        restoreParentPick(); return false, "Base turtle recipe validation failed"
    end

    local turtleSlot = findItem("turtle")
    local emptySlot
    for slot = 1, 16 do if not item(slot) then emptySlot = slot break end end
    turtle.select(emptySlot)
    if not turtle.suckUp(1) then restoreParentPick(); return false, "Could not retrieve child pickaxe" end
    local childPick = findItem("diamond_pickaxe")
    moveItem(turtleSlot, 1); moveItem(childPick, 2)
    if not turtle.craft(0) or not turtle.craft(1) then
        restoreParentPick(); return false, "Mining turtle upgrade recipe failed"
    end

    if not restoreParentPick() then return false, "Child built, but parent pickaxe was not restored" end
    turtleSlot = findItem("turtle")
    if not turtleSlot then return false, "Crafted child turtle item is missing" end
    turtle.select(turtleSlot)
    local placed, placeReason = turtle.place()
    if not placed then return false, "Child placement failed: " .. tostring(placeReason) end
    sleep(0.5)
    local child = peripheral.wrap("front")
    if not child or type(child.turnOn) ~= "function" then
        return false, "Child placed but cannot be commissioned"
    end
    local childID = child.getID()
    child.turnOn()
    return true, "Child Turtle " .. tostring(childID) .. " started and awaits approval", childID
end

return manufacturing
