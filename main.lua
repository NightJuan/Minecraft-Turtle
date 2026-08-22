math.randomseed(os.epoch("utc"))

local state = require("core.state")
local movement = require("core.movement")
local navigation = require("core.navigation")
local pathfinder = require("core.pathfinder")
local jobs = require("core.jobs")
local scanner = require("core.scanner")
local map = require("core.map")
local client = require("network.client")

local bot = state.load()
local world = map.load()
local emergencyStopRequested = false
local FUEL_RESERVE = 20

local versionFile = fs.open("/version.json", "r")
if versionFile then
    local versionData = textutils.unserializeJSON(versionFile.readAll())
    versionFile.close()
    bot.software_version = type(versionData) == "table" and
        versionData.version or "unknown"
else
    bot.software_version = "unknown"
end

bot.task = "Idle"
bot.mode = "manual"
state.save(bot)


print("Bot Online")
print("ID:", bot.id)
print("Name:", bot.name)
print(
    "Position:",
    bot.position.x,
    bot.position.y,
    bot.position.z
)

local function scanAndShare(fullRotation)
    local blocks

    if fullRotation then
        blocks = scanner.inspectAll(bot, movement)
    else
        blocks = {
            scanner.inspectForward(bot),
            scanner.inspectUp(bot),
            scanner.inspectDown(bot)
        }
    end

    table.insert(blocks, {
        name = "minecraft:air",
        x = bot.position.x,
        y = bot.position.y,
        z = bot.position.z,
        empty = true
    })

    for _, block in ipairs(blocks) do
        map.record(world, block)
    end

    if client.sendMapUpdate(bot.id, blocks) then
        print("Map updated")
    end
end

local function beginCommand(command)
    if bot.active_command and bot.active_command.command and
        bot.active_command.command.id == command.id then
        return bot.active_command.steps_completed or 0
    end
    bot.active_command = {
        command = command,
        steps_completed = 0
    }
    state.save(bot)
    return 0
end

local function saveCommandProgress(completed)
    if bot.active_command then
        bot.active_command.steps_completed = completed
        state.save(bot)
    end
end

local rawReportCommandResult = client.reportCommandResult
local executeCommand

local function reportCommandResult(botID, commandID, status, message, completed)
    local reported = rawReportCommandResult(
        botID, commandID, status, message, completed
    )
    if reported and bot.active_command and
        bot.active_command.command.id == commandID then
        bot.active_command = nil
        state.save(bot)
    elseif not reported and bot.active_command then
        bot.active_command.pending_result = {
            bot_id = botID,
            command_id = commandID,
            status = status,
            message = message,
            completed = completed
        }
        state.save(bot)
    end
    return reported
end

local function recoverActiveCommand()
    if not bot.active_command or not bot.active_command.command then return false end
    local pending = bot.active_command.pending_result
    if pending then
        reportCommandResult(
            pending.bot_id, pending.command_id, pending.status,
            pending.message, pending.completed
        )
    else
        executeCommand(bot.active_command.command)
    end
    return true
end

local function refuelTo(targetFuel)
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" or fuel >= targetFuel then return true end
    local selected = turtle.getSelectedSlot()
    for slot = 1, 16 do
        turtle.select(slot)
        while turtle.getItemCount(slot) > 0 and turtle.refuel(0)
            and turtle.getFuelLevel() < targetFuel do
            turtle.refuel(1)
        end
        if turtle.getFuelLevel() >= targetFuel then break end
    end
    turtle.select(selected)
    return turtle.getFuelLevel() >= targetFuel
end

local function routeFuelNeeded(destination)
    local actions = pathfinder.find(world, {
        x = bot.position.x, y = bot.position.y, z = bot.position.z,
        facing = bot.facing
    }, destination)
    if not actions then return nil end
    local needed = 0
    for _, action in ipairs(actions) do
        if action == "forward" or action == "back" or
            action == "up" or action == "down" then
            needed = needed + 1
        end
    end
    return needed
end

local function shouldReturnForFuel()
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" or not bot.home then return false end
    local needed = routeFuelNeeded(bot.home)
    if not needed or needed == 0 then return false end
    local target = needed + FUEL_RESERVE
    if fuel <= target then refuelTo(target + FUEL_RESERVE) end
    return turtle.getFuelLevel() <= target
end

local function navigate(destination, taskName)
    bot.task = taskName
    bot.mode = "auto"
    state.save(bot)
    local successful, reason = navigation.navigateTo(
        bot, world, destination,
        function() return emergencyStopRequested end,
        function() scanAndShare(false) end,
        function(route, cost)
            client.sendPlannedRoute(bot.id, route, cost)
        end
    )
    client.clearPlannedRoute(bot.id)
    bot.task = "Idle"
    bot.mode = "manual"
    state.save(bot)
    return successful, reason
end

local function hasContainerInFront()
    local container = peripheral.wrap("front")
    if container and type(container.size) == "function" then
        return true
    end

    local present, data = turtle.inspect()
    if not present or not data then return false end

    local words = {
        "chest", "barrel", "shulker", "crate",
        "drawer", "cabinet", "storage", "container"
    }
    local name = string.lower(data.name or "")
    for _, word in ipairs(words) do
        if string.find(name, word, 1, true) then return true end
    end

    for tag, enabled in pairs(data.tags or {}) do
        if enabled then
            local lowered = string.lower(tag)
            for _, word in ipairs(words) do
                if string.find(lowered, word, 1, true) then return true end
            end
        end
    end

    return false
end

local function depositInventory()
    if not hasContainerInFront() then
        return 0, "No recognized inventory container directly in front"
    end

    local selected = turtle.getSelectedSlot()
    local deposited = 0
    for slot = 1, 16 do
        turtle.select(slot)
        local count = turtle.getItemCount(slot)
        if count > 0 and not turtle.refuel(0) then
            turtle.drop()
            deposited = deposited + count - turtle.getItemCount(slot)
        end
    end
    turtle.select(selected)
    if deposited == 0 then
        return 0, "Container may be full or there are only fuel items"
    end
    return deposited, nil
end

local function retrieveAndRefuel()
    if not hasContainerInFront() then
        return false, "No recognized fuel container directly in front"
    end

    local limit = turtle.getFuelLimit()
    local target = type(limit) == "number" and math.min(limit, 200) or 200
    local pulled = 0
    for _ = 1, 16 do
        if turtle.getFuelLevel() == "unlimited" or turtle.getFuelLevel() >= target then break end
        if not turtle.suck(64) then break end
        pulled = pulled + 1
        refuelTo(target)
    end
    local refueled = turtle.getFuelLevel() == "unlimited" or
        turtle.getFuelLevel() >= target
    return refueled,
        refueled and nil or "Container has no usable fuel"
end

local function emptyInventorySlots()
    local empty = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then empty = empty + 1 end
    end
    return empty
end

executeCommand = function(command)
    local action = command.action
    local steps = command.steps or 1
    local commandID = command.id
    local fuel = turtle.getFuelLevel()
    local home = bot.home or bot.position
    local distanceHome = math.abs(bot.position.x - home.x)
        + math.abs(bot.position.y - home.y)
        + math.abs(bot.position.z - home.z)
    local recoveredSteps = beginCommand(command)

    print(
        "Command:",
        action,
        "x" .. tostring(steps)
    )

    local movementFunction = nil

    if action == "update_software" then
        bot.task = "Installing Update"
        state.save(bot)
        client.sendState(bot)
        reportCommandResult(bot.id, commandID, "completed",
            "Software update started", 1)
        shell.run("/update.lua")
        return true
    elseif action == "set_home" then
        state.setHome(bot)
        reportCommandResult(bot.id, commandID, "completed", "Home position saved", 1)
        return true
    elseif action == "set_storage" or action == "set_fuel_station" then
        local locationName = action == "set_storage" and "storage" or "fuel_station"
        state.setLocation(bot, locationName)
        client.sendState(bot)
        reportCommandResult(bot.id, commandID, "completed",
            locationName == "storage" and "Storage location saved"
                or "Fuel station location saved", 1)
        return true
    elseif action == "deposit" then
        local location = bot.locations and bot.locations.storage
        if not location then
            reportCommandResult(bot.id, commandID, "failed",
                "Set a storage location first", 0)
            return false
        end
        local arrived, reason = navigate(location, "Going to Storage")
        if not arrived then
            reportCommandResult(bot.id, commandID, "blocked", reason, 0)
            return false
        end
        bot.task = "Depositing Items"
        state.save(bot)
        local deposited, depositReason = depositInventory()
        bot.task = "Idle"
        state.save(bot)
        client.sendState(bot)
        reportCommandResult(bot.id, commandID,
            deposited > 0 and "completed" or "failed",
            deposited > 0 and ("Deposited " .. deposited .. " items; fuel preserved")
                or depositReason,
            deposited > 0 and 1 or 0)
        return deposited > 0
    elseif action == "retrieve_fuel" then
        local location = bot.locations and bot.locations.fuel_station
        if not location then
            reportCommandResult(bot.id, commandID, "failed",
                "Set a fuel station location first", 0)
            return false
        end
        local arrived, reason = navigate(location, "Going to Fuel Station")
        if not arrived then
            reportCommandResult(bot.id, commandID, "blocked", reason, 0)
            return false
        end
        bot.task = "Retrieving Fuel"
        state.save(bot)
        local refueled, refuelReason = retrieveAndRefuel()
        bot.task = "Idle"
        state.save(bot)
        client.sendState(bot)
        reportCommandResult(bot.id, commandID,
            refueled and "completed" or "failed",
            refueled and "Fuel supply retrieved" or refuelReason, 0)
        return refueled
    elseif action == "return_home" then
        refuelTo(distanceHome + FUEL_RESERVE)
        if fuel ~= "unlimited" and turtle.getFuelLevel() < distanceHome then
            reportCommandResult(bot.id, commandID, "failed",
                "Not enough fuel to reach home", 0)
            return false
        end
        local successful, reason = navigate(bot.home, "Returning Home")
        reportCommandResult(bot.id, commandID,
            successful and "completed" or (emergencyStopRequested and "cancelled" or "blocked"),
            successful and "Returned home" or reason, 0)
        return successful
    elseif action == "go_to" then
        if not command.destination then
            reportCommandResult(bot.id, commandID, "failed", "Missing destination", 0)
            return false
        end
        local needed = routeFuelNeeded(command.destination)
        if not needed then
            reportCommandResult(bot.id, commandID, "blocked",
                "No safe route through the discovered map", 0)
            return false
        end
        refuelTo(needed + FUEL_RESERVE)
        if turtle.getFuelLevel() ~= "unlimited" and
            turtle.getFuelLevel() < needed + FUEL_RESERVE then
            reportCommandResult(bot.id, commandID, "failed",
                "Destination would use the protected fuel reserve", 0)
            return false
        end
        local successful, reason = navigate(command.destination, "Navigating")
        reportCommandResult(bot.id, commandID,
            successful and "completed" or (emergencyStopRequested and "cancelled" or "blocked"),
            successful and "Destination reached" or reason, 0)
        return successful
    elseif action == "explore" then
        refuelTo(distanceHome + FUEL_RESERVE + steps)
        local lowFuelReturn = false
        local exploredCompleted = recoveredSteps
        bot.task = "Exploring"
        bot.mode = "auto"
        state.save(bot)
        local successful, reason, completed = navigation.explore(
            bot, math.max(steps - recoveredSteps, 0),
            function()
                lowFuelReturn = shouldReturnForFuel()
                return emergencyStopRequested or lowFuelReturn
            end,
            function()
                exploredCompleted = exploredCompleted + 1
                saveCommandProgress(exploredCompleted)
                scanAndShare(true)
            end
        )
        completed = recoveredSteps + completed
        bot.task = "Idle"
        bot.mode = "manual"
        state.save(bot)
        if lowFuelReturn and not emergencyStopRequested then
            local homeSuccessful, homeReason = navigate(
                bot.home, "Returning Home - Low Fuel"
            )
        reportCommandResult(bot.id, commandID,
                homeSuccessful and "cancelled" or "blocked",
                homeSuccessful and "Exploration stopped; returned home due to low fuel"
                    or ("Low fuel return failed: " .. tostring(homeReason)), completed)
            return homeSuccessful
        end
        reportCommandResult(bot.id, commandID,
            successful and "completed" or (emergencyStopRequested and "cancelled" or "blocked"),
            successful and "Exploration complete" or reason, completed)
        return successful
    elseif action == "job_tunnel" or action == "job_excavate" or
        action == "job_scan_grid" then
        local width = tonumber(command.width) or 1
        local length = tonumber(command.length) or steps
        local depth = tonumber(command.depth) or 1
        local destructive = action ~= "job_scan_grid"
        local withinLimits = action == "job_tunnel" and
                width == 1 and depth == 1 and length >= 1 and length <= 64
            or action == "job_excavate" and
                width >= 1 and width <= 16 and length >= 1 and length <= 16 and
                depth >= 1 and depth <= 16
            or action == "job_scan_grid" and
                width >= 1 and width <= 32 and length >= 1 and length <= 32 and
                depth == 1
        if not withinLimits or (destructive and command.confirmed ~= true) then
            reportCommandResult(bot.id, commandID, "failed",
                "Job rejected: invalid limits or missing confirmation", 0)
            return false
        end
        local jobName = action == "job_tunnel" and "Tunnel"
            or action == "job_excavate" and "Excavation" or "Grid Scan"
        local jobCancelled = false
        local function jobShouldStop()
            while not emergencyStopRequested do
                local control = client.getJobControl(bot.id, commandID)
                if control == "cancelled" then
                    jobCancelled = true
                    return true
                end
                if control ~= "paused" then return false end
                bot.task = jobName .. " paused"
                state.save(bot)
                sleep(1)
            end
            return true
        end

        local function jobNavigate(destination, taskName)
            bot.task = taskName
            state.save(bot)
            local successful, reason = navigation.navigateTo(
                bot, world, destination, jobShouldStop,
                function() scanAndShare(false) end,
                function(route, cost)
                    client.sendPlannedRoute(bot.id, route, cost)
                end
            )
            client.clearPlannedRoute(bot.id)
            return successful, reason
        end

        local function waitForLocation(name, label)
            while not (bot.locations and bot.locations[name]) do
                if jobShouldStop() then return nil, "Cancelled" end
                bot.task = jobName .. " paused - set " .. label
                state.save(bot)
                sleep(3)
            end
            return bot.locations[name]
        end

        local function serviceJob(done, total)
            local needsDeposit = destructive and emptyInventorySlots() <= 1
            local fuel = turtle.getFuelLevel()
            local needsFuel = false
            if fuel ~= "unlimited" then
                refuelTo(100)
                fuel = turtle.getFuelLevel()
                local station = bot.locations and bot.locations.fuel_station
                local routeToFuel = station and routeFuelNeeded(station) or nil
                local safeMinimum = (routeToFuel or 20) + FUEL_RESERVE
                needsFuel = fuel <= safeMinimum
            end

            if not needsDeposit and not needsFuel then return true end

            local workPosition = {
                x = bot.position.x, y = bot.position.y, z = bot.position.z,
                facing = bot.facing
            }
            bot.active_command.service_return = workPosition
            bot.active_command.service_reason = needsDeposit and "inventory" or "fuel"
            state.save(bot)

            if needsDeposit then
                local storage, locationReason = waitForLocation("storage", "Storage")
                if not storage then return false, locationReason end
                local fuelToStorage = routeFuelNeeded(storage)
                if fuelToStorage then refuelTo(fuelToStorage + FUEL_RESERVE) end
                local arrived, travelReason = jobNavigate(storage, "Servicing - Storage")
                if not arrived then return false, "Cannot reach Storage: " .. tostring(travelReason) end

                local deposited, depositReason = depositInventory()
                while deposited == 0 do
                    if jobShouldStop() then return false, "Cancelled" end
                    bot.task = jobName .. " paused - Storage blocked/full"
                    state.save(bot)
                    sleep(3)
                    deposited, depositReason = depositInventory()
                end
            end

            fuel = turtle.getFuelLevel()
            if fuel ~= "unlimited" then
                refuelTo(200)
                needsFuel = turtle.getFuelLevel() < 100
            else
                needsFuel = false
            end

            if needsFuel then
                local station, locationReason = waitForLocation("fuel_station", "Fuel Station")
                if not station then return false, locationReason end
                local arrived, travelReason = jobNavigate(station, "Servicing - Fuel")
                if not arrived then return false, "Cannot reach Fuel Station: " .. tostring(travelReason) end

                local refueled, refuelReason = retrieveAndRefuel()
                while not refueled do
                    if jobShouldStop() then return false, "Cancelled" end
                    bot.task = jobName .. " paused - Fuel unavailable"
                    state.save(bot)
                    sleep(3)
                    refueled, refuelReason = retrieveAndRefuel()
                end
            end

            local returned, returnReason = jobNavigate(
                workPosition, "Returning to " .. jobName
            )
            if not returned then
                return false, "Cannot return to job: " .. tostring(returnReason)
            end

            bot.active_command.service_return = nil
            bot.active_command.service_reason = nil
            bot.task = jobName .. " " .. done .. "/" .. total
            state.save(bot)
            return true
        end
        bot.task = jobName
        bot.mode = "auto"
        state.save(bot)
        local lastProgressReport = 0
        local callbacks = {
            shouldStop = jobShouldStop,
            service = serviceJob,
            progress = function(done, total)
                bot.task = jobName .. " " .. done .. "/" .. total
                saveCommandProgress(done)
                state.save(bot)
                local now = os.epoch("utc")
                if done == total or done % 5 == 0 or
                    now - lastProgressReport >= 1000 then
                    client.reportCommandProgress(
                        bot.id, commandID, done, bot.task
                    )
                    lastProgressReport = now
                end
            end,
            scan = function(_, movementAction)
                scanAndShare(
                    action == "job_scan_grid" and
                    movementAction == "forward"
                )
            end
        }

        if bot.active_command.service_return then
            local savedWork = bot.active_command.service_return
            local serviceReason = bot.active_command.service_reason
            local serviceSuccessful = true
            local serviceFailure = nil

            if serviceReason == "inventory" then
                local storage
                storage, serviceFailure = waitForLocation("storage", "Storage")
                if storage then
                    serviceSuccessful, serviceFailure = jobNavigate(
                        storage, "Recovering - Storage"
                    )
                else
                    serviceSuccessful = false
                end
                if serviceSuccessful then
                    local deposited
                    repeat
                        deposited, serviceFailure = depositInventory()
                        if deposited == 0 then
                            bot.task = jobName .. " paused - Storage blocked/full"
                            state.save(bot)
                            sleep(3)
                        end
                    until deposited > 0 or jobShouldStop()
                    serviceSuccessful = deposited > 0
                end
            elseif serviceReason == "fuel" then
                local station
                station, serviceFailure = waitForLocation("fuel_station", "Fuel Station")
                if station then
                    serviceSuccessful, serviceFailure = jobNavigate(
                        station, "Recovering - Fuel"
                    )
                else
                    serviceSuccessful = false
                end
                if serviceSuccessful then
                    local refueled
                    repeat
                        refueled, serviceFailure = retrieveAndRefuel()
                        if not refueled then
                            bot.task = jobName .. " paused - Fuel unavailable"
                            state.save(bot)
                            sleep(3)
                        end
                    until refueled or jobShouldStop()
                    serviceSuccessful = refueled == true
                end
            end

            if serviceSuccessful then
                serviceSuccessful, serviceFailure = jobNavigate(
                    savedWork, "Recovering Job Position"
                )
            end

            if not serviceSuccessful then
                bot.task = "Idle"
                bot.mode = "manual"
                state.save(bot)
                reportCommandResult(bot.id, commandID,
                    (jobCancelled or emergencyStopRequested) and "cancelled" or "blocked",
                    "Job service recovery failed: " .. tostring(serviceFailure),
                    recoveredSteps)
                return false
            end

            bot.active_command.service_return = nil
            bot.active_command.service_reason = nil
            state.save(bot)
        end

        local successful, reason, completed
        if action == "job_tunnel" then
            successful, reason, completed = jobs.tunnel(
                bot, length, recoveredSteps, callbacks
            )
        elseif action == "job_excavate" then
            successful, reason, completed = jobs.excavate(
                bot, width, length, depth, recoveredSteps, callbacks
            )
        else
            successful, reason, completed = jobs.scanGrid(
                bot, width, length, recoveredSteps, callbacks
            )
        end
        bot.task = "Idle"
        bot.mode = "manual"
        state.save(bot)
        reportCommandResult(bot.id, commandID,
            successful and "completed" or
                ((emergencyStopRequested or jobCancelled) and "cancelled" or "blocked"),
            successful and (jobName .. " complete") or
                (jobCancelled and (jobName .. " cancelled") or reason),
            completed or 0)
        return successful
    elseif action == "forward" then
        movementFunction = movement.forward

    elseif action == "back" then
        movementFunction = movement.back

    elseif action == "up" then
        movementFunction = movement.up

    elseif action == "down" then
        movementFunction = movement.down

    elseif action == "turn_left" then
        movementFunction = movement.turnLeft

    elseif action == "turn_right" then
        movementFunction = movement.turnRight
    end

    if not movementFunction then
        local message =
            "Unknown command: " .. tostring(action)

        print(message)

        reportCommandResult(
            bot.id,
            commandID,
            "failed",
            message,
            0
        )

        return false
    end

    bot.task = "Manual: " .. action
    state.save(bot)

    local usesFuel = action == "forward" or action == "back"
        or action == "up" or action == "down"
    if usesFuel and fuel ~= "unlimited" and fuel < steps then
        bot.task = "Idle"
        state.save(bot)
        reportCommandResult(bot.id, commandID, "failed",
            "Not enough fuel: need " .. steps .. ", have " .. fuel, 0)
        return false
    end

    local stepsCompleted = recoveredSteps

    for step = recoveredSteps + 1, steps do
        if emergencyStopRequested then
            local message =
                "Cancelled by emergency stop"

            print(message)

            bot.task = "Idle"
            state.save(bot)

        reportCommandResult(
                bot.id,
                commandID,
                "cancelled",
                message,
                stepsCompleted
            )

            emergencyStopRequested = false
            return false
        end

        local successful, movementReason =
            movementFunction(bot)

        if not successful and action == "forward" and
            movementReason == "Vegetation in front" then
            successful, movementReason = movement.stepOver(bot)
        elseif not successful and string.find(
            movementReason or "", "Temporary obstruction", 1, true
        ) then
            for _ = 1, 3 do
                sleep(1)
                if emergencyStopRequested then break end
                successful, movementReason = movementFunction(bot)
                if successful then break end
            end
        end

        if not successful then
            local message =
                (movementReason or "Blocked") ..
                " at step " .. tostring(step)

            print(message)

            bot.task = "Idle"
            state.save(bot)

        reportCommandResult(
                bot.id,
                commandID,
                "blocked",
                message,
                stepsCompleted
            )

            return false
        end

        stepsCompleted = stepsCompleted + 1
        saveCommandProgress(stepsCompleted)
        scanAndShare(
            action == "forward" or
            action == "back"
        )
        sleep(0.1)
    end

    bot.task = "Idle"
    state.save(bot)

    print("Command complete")

        reportCommandResult(
        bot.id,
        commandID,
        "completed",
        "Command completed",
        stepsCompleted
    )

    return true
end


local function heartbeat()
    local wasConnected = true
    while true do
        local sent = client.sendState(bot)
        if sent then client.flushOutbox() end
        local isConnected = client.isConnected()
        if isConnected ~= wasConnected then
            print(isConnected and "Server connection restored" or
                "Server offline - updates queued")
            wasConnected = isConnected
        elseif not isConnected then
            print("Reconnecting...")
        end
        sleep(isConnected and 1 or 3)
    end
end


local function commandLoop()
    while true do
        if emergencyStopRequested then
            bot.task = "Idle"
            state.save(bot)
            emergencyStopRequested = false
        elseif recoverActiveCommand() then
            print("Recovered active command")
        elseif shouldReturnForFuel() then
            print("Low fuel reserve reached")
            navigate(bot.home, "Returning Home - Low Fuel")
        else
            local command = client.getNextCommand(bot.id)
            if command then executeCommand(command) end
        end

        sleep(1)
    end
end


local function emergencyStopLoop()
    while true do
        if client.getEmergencyStop(bot.id) then
            emergencyStopRequested = true
            bot.task = "Emergency Stop"
            state.save(bot)

            print("EMERGENCY STOP")

            client.acknowledgeEmergencyStop(
                bot.id
            )
        end

        sleep(0.25)
    end
end

if bot.active_command and bot.active_command.command then
    print("Recovering interrupted command")
    recoverActiveCommand()
end

client.sendState(bot)
scanAndShare(false)

parallel.waitForAll(
    heartbeat,
    commandLoop,
    emergencyStopLoop
)
