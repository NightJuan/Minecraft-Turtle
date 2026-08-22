local jobs = {}

local movement = require("core.movement")

local function digForward()
    while turtle.detect() do
        if not turtle.dig() then return false, "Unable to dig forward" end
        sleep(0.1)
    end
    return true
end

local function digUp()
    if turtle.detectUp() and not turtle.digUp() then
        return false, "Unable to clear tunnel ceiling"
    end
    return true
end

local function digDown()
    if turtle.detectDown() and not turtle.digDown() then
        return false, "Unable to dig downward"
    end
    return true
end

local function gridActions(width, length)
    local actions = {}
    for row = 1, width do
        for _ = 2, length do actions[#actions + 1] = "forward" end
        if row < width then
            local turn = row % 2 == 1 and "turn_right" or "turn_left"
            actions[#actions + 1] = turn
            actions[#actions + 1] = "forward"
            actions[#actions + 1] = turn
        end
    end
    return actions
end

local function runActions(bot, actions, startIndex, destructive, callbacks)
    local functions = {
        forward = movement.forward,
        turn_left = movement.turnLeft,
        turn_right = movement.turnRight,
        down = movement.down
    }
    for index = startIndex + 1, #actions do
        if callbacks.shouldStop() then return false, "Cancelled", index - 1 end
        if callbacks.service then
            local serviced, serviceReason = callbacks.service(index - 1, #actions)
            if not serviced then
                return false, serviceReason or "Automatic service failed", index - 1
            end
        end
        local action = actions[index]
        if destructive and action == "forward" then
            local ok, reason = digForward()
            if not ok then return false, reason, index - 1 end
        elseif destructive and action == "down" then
            local ok, reason = digDown()
            if not ok then return false, reason, index - 1 end
        end
        local ok, reason = functions[action](bot)
        if not ok and not destructive and action == "forward" and
            (reason == "Vegetation in front" or reason == "Blocked in front") then
            ok, reason = movement.stepOver(bot)
        elseif not ok and not destructive and string.find(
            reason or "", "Temporary obstruction", 1, true
        ) then
            for _ = 1, 3 do
                sleep(1)
                if callbacks.shouldStop() then return false, "Cancelled", index - 1 end
                ok, reason = functions[action](bot)
                if ok then break end
            end
        end
        if not ok then return false, reason, index - 1 end
        callbacks.progress(index, #actions)
        callbacks.scan(destructive, action)
        sleep(0.1)
    end
    return true, nil, #actions
end

function jobs.tunnel(bot, length, startIndex, callbacks)
    local actions = {}
    for _ = 1, length do actions[#actions + 1] = "forward" end
    digUp()
    local wrapped = {
        shouldStop = callbacks.shouldStop,
        service = callbacks.service,
        progress = callbacks.progress,
        scan = function(full)
            digUp()
            callbacks.scan(full)
        end
    }
    return runActions(bot, actions, startIndex, true, wrapped)
end

function jobs.scanGrid(bot, width, length, startIndex, callbacks)
    callbacks.scan(true)
    return runActions(bot, gridActions(width, length), startIndex, false, callbacks)
end

function jobs.excavate(bot, width, length, depth, startIndex, callbacks)
    local layer = gridActions(width, length)
    local actions = {}
    for level = 1, depth do
        for _, action in ipairs(layer) do actions[#actions + 1] = action end
        if level < depth then
            actions[#actions + 1] = "down"
            actions[#actions + 1] = "turn_right"
            actions[#actions + 1] = "turn_right"
        end
    end
    return runActions(bot, actions, startIndex, true, callbacks)
end

return jobs
