local map = {}

local MAP_FILE = "/data/map.json"

local function getKey(x, y, z)
    return x .. "," .. y .. "," .. z
end

function map.load()
    if not fs.exists(MAP_FILE) then
        return {}
    end

    local file = fs.open(MAP_FILE, "r")
    local contents = file.readAll()
    file.close()

    local world = textutils.unserializeJSON(contents) or {}

    for _, block in pairs(world) do
        if block.name and string.find(
            string.lower(block.name),
            "grass_block",
            1,
            true
        ) then
            block.empty = false
        end
    end

    map.save(world)
    return world
end

function map.save(world)
    local file = fs.open(MAP_FILE, "w")
    file.write(textutils.serializeJSON(world))
    file.close()
end

function map.record(world, block)
    local key = getKey(block.x, block.y, block.z)

    world[key] = block

    map.save(world)
end

return map
