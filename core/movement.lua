local movement = {}

local state = require("core.state")

local NORTH = 0
local EAST = 1
local SOUTH = 2
local WEST = 3

local function save(bot)
    state.save(bot)
end

local function canMove()
    local fuel = turtle.getFuelLevel()
    return fuel == "unlimited" or fuel > 0
end

local function isVegetation(name)
    name = string.lower(name or "")
    if string.find(name, "grass_block", 1, true) then return false end
    local words = {
        "tall_grass", "short_grass", ":grass", "fern", "flower", "sapling", "bush",
        "wheat", "carrot", "potato", "beetroot", "crop"
    }
    for _, word in ipairs(words) do
        if string.find(name, word, 1, true) then return true end
    end
    return false
end

function movement.forward(bot)
    if not canMove() then return false, "Out of fuel" end
    local moved = turtle.forward()

    if not moved then
        local hasBlock, data = turtle.inspect()
        if hasBlock and isVegetation(data.name) then
            return false, "Vegetation in front"
        elseif not hasBlock then
            return false, "Temporary obstruction or entity in front"
        end
        return false, "Blocked in front"
    end

    if bot.facing == NORTH then
        bot.position.z = bot.position.z - 1

    elseif bot.facing == EAST then
        bot.position.x = bot.position.x + 1

    elseif bot.facing == SOUTH then
        bot.position.z = bot.position.z + 1

    elseif bot.facing == WEST then
        bot.position.x = bot.position.x - 1
    end

    save(bot)

    return true
end

function movement.back(bot)
    if not canMove() then return false, "Out of fuel" end
    local moved = turtle.back()

    if not moved then
        return false, "Blocked behind"
    end

    if bot.facing == NORTH then
        bot.position.z = bot.position.z + 1

    elseif bot.facing == EAST then
        bot.position.x = bot.position.x - 1

    elseif bot.facing == SOUTH then
        bot.position.z = bot.position.z - 1

    elseif bot.facing == WEST then
        bot.position.x = bot.position.x + 1
    end

    save(bot)

    return true
end

function movement.up(bot)
    if not canMove() then return false, "Out of fuel" end
    local moved = turtle.up()

    if not moved then
        return false, "Blocked above"
    end

    bot.position.y = bot.position.y + 1

    save(bot)

    return true
end

function movement.down(bot)
    if not canMove() then return false, "Out of fuel" end
    local moved = turtle.down()

    if not moved then
        return false, "Blocked below"
    end

    bot.position.y = bot.position.y - 1

    save(bot)

    return true
end

function movement.stepOver(bot)
    local fuel = turtle.getFuelLevel()
    if fuel ~= "unlimited" and fuel < 6 then return false, "Not enough fuel to step over" end
    if turtle.detectUp() then return false, "No clearance above vegetation" end

    local ok, reason = movement.up(bot)
    if not ok then return false, reason end

    if turtle.detectUp() then
        movement.down(bot)
        return false, "Two-block overhead clearance is required"
    end

    ok, reason = movement.up(bot)
    if not ok then
        movement.down(bot)
        return false, reason
    end

    ok, reason = movement.forward(bot)
    if not ok then
        movement.down(bot)
        movement.down(bot)
        return false, reason
    end

    ok, reason = movement.forward(bot)
    if not ok then
        movement.back(bot)
        movement.down(bot)
        movement.down(bot)
        return false, reason
    end

    ok, reason = movement.down(bot)
    if not ok then return false, "Stepped over vegetation but could not descend" end
    ok, reason = movement.down(bot)
    if not ok then return false, "Crossed obstacle but could not complete descent" end
    return true
end

function movement.turnRight(bot)
    local turned = turtle.turnRight()

    if not turned then
        return false
    end

    bot.facing = (bot.facing + 1) % 4

    save(bot)

    return true
end

function movement.turnLeft(bot)
    local turned = turtle.turnLeft()

    if not turned then
        return false
    end

    bot.facing = (bot.facing - 1) % 4

    save(bot)

    return true
end

return movement
