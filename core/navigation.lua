local navigation = {}

local movement = require("core.movement")
local pathfinder = require("core.pathfinder")

local function turnTo(bot, facing, shouldStop)
    while bot.facing ~= facing do
        if shouldStop and shouldStop() then return false, "Cancelled" end
        local difference = (facing - bot.facing) % 4
        if difference == 3 then movement.turnLeft(bot) else movement.turnRight(bot) end
    end
    return true
end

local function moveMany(bot, move, count, shouldStop, onMove)
    for _ = 1, count do
        if shouldStop and shouldStop() then return false, "Cancelled" end
        local ok, reason = move(bot)
        if not ok then return false, reason end
        if onMove then onMove(move) end
        sleep(0.1)
    end
    return true
end

function navigation.navigateTo(bot, world, destination, shouldStop, onMove, onPlan)
    if not destination then return false, "No destination provided" end

    local actionFunctions = {
        forward = movement.forward,
        back = movement.back,
        up = movement.up,
        down = movement.down,
        turn_left = movement.turnLeft,
        turn_right = movement.turnRight
    }

    for attempt = 1, 8 do
        if shouldStop and shouldStop() then return false, "Cancelled" end

        local actions, route, cost = pathfinder.find(world, {
            x = bot.position.x, y = bot.position.y, z = bot.position.z,
            facing = bot.facing
        }, destination)

        if not actions then return false, cost end
        if onPlan then onPlan(route, cost) end

        local fuelNeeded = 0
        for _, action in ipairs(actions) do
            if action == "forward" or action == "back" or
               action == "up" or action == "down" then
                fuelNeeded = fuelNeeded + 1
            end
        end
        local fuel = turtle.getFuelLevel()
        if fuel ~= "unlimited" and fuel < fuelNeeded then
            return false, "Planned route needs " .. fuelNeeded ..
                " fuel, but only " .. fuel .. " remains"
        end

        local blocked = false
        for _, action in ipairs(actions) do
            if shouldStop and shouldStop() then return false, "Cancelled" end
            local move = actionFunctions[action]
            local ok, reason = move(bot)
            local forceReplan = false
            if not ok and action == "forward" and
                reason == "Vegetation in front" then
                ok, reason = movement.stepOver(bot)
                forceReplan = ok
            elseif not ok and string.find(
                reason or "", "Temporary obstruction", 1, true
            ) then
                for _ = 1, 3 do
                    sleep(1)
                    if shouldStop and shouldStop() then return false, "Cancelled" end
                    ok, reason = move(bot)
                    if ok then break end
                end
            end
            if onMove then onMove(move, ok) end
            if not ok then
                blocked = true
                if reason == "Out of fuel" then return false, reason end
                break
            end
            if forceReplan then
                blocked = true
                break
            end
            sleep(0.1)
        end

        if not blocked then
            if destination.facing ~= nil then
                return turnTo(bot, destination.facing, shouldStop)
            end
            return true
        end
    end

    return false, "Unable to find a clear route after replanning"
end

function navigation.returnHome(bot, world, shouldStop, onMove, onPlan)
    if not bot.home then return false, "No home position saved" end
    return navigation.navigateTo(
        bot, world, bot.home, shouldStop, onMove, onPlan
    )
end

function navigation.explore(bot, steps, shouldStop, onMove)
    local completed = 0
    for _ = 1, steps do
        if shouldStop and shouldStop() then return false, "Cancelled", completed end
        local moved = false
        for _ = 1, 4 do
            if not turtle.detect() then
                local ok, reason = movement.forward(bot)
                if not ok then return false, reason, completed end
                moved = true
                completed = completed + 1
                if onMove then onMove() end
                break
            end
            movement.turnRight(bot)
        end
        if not moved then return false, "Surrounded by blocks", completed end
        sleep(0.1)
    end
    return true, nil, completed
end

return navigation
