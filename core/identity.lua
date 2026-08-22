local identity = {}

local first_names = {
    "James",
    "Henry",
    "Oliver",
    "Mason",
    "Arthur",
    "Jack",
    "Thomas",
    "Samuel",
    "George",
    "Charlie"
}

local last_names = {
    "Walker",
    "Carter",
    "Reed",
    "Stone",
    "Miller",
    "Bennett",
    "Turner",
    "Hayes",
    "Cooper",
    "Morgan"
}

function identity.generateName()
    local first = first_names[math.random(#first_names)]
    local last = last_names[math.random(#last_names)]

    return first .. " " .. last
end

function identity.getID()
    return os.getComputerID()
end

return identity