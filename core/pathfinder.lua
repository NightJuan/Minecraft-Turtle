local pathfinder = {}

local DIRECTIONS = {
    [0] = { x = 0, z = -1 },
    [1] = { x = 1, z = 0 },
    [2] = { x = 0, z = 1 },
    [3] = { x = -1, z = 0 }
}

local function positionKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

local function stateKey(node)
    return positionKey(node.x, node.y, node.z) .. "," .. node.facing
end

local function distance(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y) + math.abs(a.z - b.z)
end

local function heapPush(heap, item)
    heap[#heap + 1] = item
    local index = #heap
    while index > 1 do
        local parent = math.floor(index / 2)
        if heap[parent].priority <= item.priority then break end
        heap[index] = heap[parent]
        index = parent
    end
    heap[index] = item
end

local function heapPop(heap)
    if #heap == 0 then return nil end
    local root = heap[1]
    local last = table.remove(heap)
    if #heap == 0 then return root end
    local index = 1
    while true do
        local left = index * 2
        local right = left + 1
        if left > #heap then break end
        local child = left
        if right <= #heap and heap[right].priority < heap[left].priority then child = right end
        if heap[child].priority >= last.priority then break end
        heap[index] = heap[child]
        index = child
    end
    heap[index] = last
    return root
end

local function isPassable(world, node, start, goal)
    if distance(node, start) == 0 or distance(node, goal) == 0 then return true end
    local block = world[positionKey(node.x, node.y, node.z)]
    return block ~= nil and block.empty == true
end

local function neighbors(node, world, start, goal)
    local direction = DIRECTIONS[node.facing]
    local candidates = {
        { action = "turn_left", x = node.x, y = node.y, z = node.z,
          facing = (node.facing - 1) % 4, cost = 0.35 },
        { action = "turn_right", x = node.x, y = node.y, z = node.z,
          facing = (node.facing + 1) % 4, cost = 0.35 },
        { action = "forward", x = node.x + direction.x, y = node.y,
          z = node.z + direction.z, facing = node.facing, cost = 1 },
        { action = "up", x = node.x, y = node.y + 1,
          z = node.z, facing = node.facing, cost = 1 },
        { action = "down", x = node.x, y = node.y - 1,
          z = node.z, facing = node.facing, cost = 1 }
    }

    local result = {}
    for _, candidate in ipairs(candidates) do
        local turning = candidate.action == "turn_left" or candidate.action == "turn_right"
        if turning or isPassable(world, candidate, start, goal) then
            result[#result + 1] = candidate
        end
    end
    return result
end

function pathfinder.find(world, start, goal)
    local first = {
        x = start.x, y = start.y, z = start.z,
        facing = start.facing or 0
    }
    local open = {}
    local firstKey = stateKey(first)
    local costs = { [firstKey] = 0 }
    local parents = {}
    local nodes = { [firstKey] = first }
    heapPush(open, { key = firstKey, priority = distance(first, goal) })

    while #open > 0 do
        local entry = heapPop(open)
        local current = nodes[entry.key]
        local currentCost = costs[entry.key]

        if current.x == goal.x and current.y == goal.y and current.z == goal.z then
            local actions = {}
            local route = { { x = current.x, y = current.y, z = current.z } }
            local key = entry.key
            while parents[key] do
                table.insert(actions, 1, parents[key].action)
                local parentNode = nodes[parents[key].key]
                table.insert(route, 1, {
                    x = parentNode.x, y = parentNode.y, z = parentNode.z
                })
                key = parents[key].key
            end
            return actions, route, currentCost
        end

        for _, nextNode in ipairs(neighbors(current, world, first, goal)) do
            local nextKey = stateKey(nextNode)
            local nextCost = currentCost + nextNode.cost
            if costs[nextKey] == nil or nextCost < costs[nextKey] then
                costs[nextKey] = nextCost
                nodes[nextKey] = nextNode
                parents[nextKey] = { key = entry.key, action = nextNode.action }
                heapPush(open, {
                    key = nextKey,
                    priority = nextCost + distance(nextNode, goal)
                })
            end
        end
    end

    return nil, nil, "No safe route through the discovered map"
end

return pathfinder
