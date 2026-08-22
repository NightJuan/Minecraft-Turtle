local scanner = {}

local NORTH = 0
local EAST = 1
local SOUTH = 2
local WEST = 3

local function isVegetation(name)
    name = string.lower(name or "")
    if string.find(name, "grass_block", 1, true) then return false end
    for _, word in ipairs({
        "tall_grass", "short_grass", ":grass", "fern", "flower", "sapling", "bush",
        "wheat", "carrot", "potato", "beetroot", "crop"
    }) do
        if string.find(name, word, 1, true) then return true end
    end
    return false
end

local function getForwardPosition(bot)
    local x = bot.position.x
    local y = bot.position.y
    local z = bot.position.z

    if bot.facing == NORTH then
        z = z - 1

    elseif bot.facing == EAST then
        x = x + 1

    elseif bot.facing == SOUTH then
        z = z + 1

    elseif bot.facing == WEST then
        x = x - 1
    end

    return x, y, z
end

function scanner.inspectForward(bot)
    local x, y, z = getForwardPosition(bot)

    local has_block, data = turtle.inspect()

    if has_block then
        return {
            name = data.name,
            x = x,
            y = y,
            z = z,
            empty = isVegetation(data.name)
        }
    end

    return {
        name = "minecraft:air",
        x = x,
        y = y,
        z = z,
        empty = true
    }
end

function scanner.inspectUp(bot)
    local x = bot.position.x
    local y = bot.position.y + 1
    local z = bot.position.z

    local has_block, data = turtle.inspectUp()

    if has_block then
        return {
            name = data.name,
            x = x,
            y = y,
            z = z,
            empty = isVegetation(data.name)
        }
    end

    return {
        name = "minecraft:air",
        x = x,
        y = y,
        z = z,
        empty = true
    }
end

function scanner.inspectDown(bot)
    local x = bot.position.x
    local y = bot.position.y - 1
    local z = bot.position.z

    local has_block, data = turtle.inspectDown()

    if has_block then
        return {
            name = data.name,
            x = x,
            y = y,
            z = z,
            empty = isVegetation(data.name)
        }
    end

    return {
        name = "minecraft:air",
        x = x,
        y = y,
        z = z,
        empty = true
    }
end

function scanner.inspectAll(bot, movement)
    local blocks = { scanner.inspectUp(bot), scanner.inspectDown(bot) }
    for _ = 1, 4 do
        table.insert(blocks, scanner.inspectForward(bot))
        movement.turnRight(bot)
    end
    return blocks
end

return scanner
