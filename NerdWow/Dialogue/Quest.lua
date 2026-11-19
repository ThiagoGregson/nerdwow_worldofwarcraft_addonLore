local _, addon = ...
local Quest = { MAX_ENTRIES = 256 }
addon.QuestDialogue = Quest
local MAX = 9007199254740991
local moments = { QUEST_OFFERED = "OFFER", QUEST_ACCEPTED = "OFFER",
    QUEST_PROGRESS_VIEWED = "PROGRESS", QUEST_COMPLETED = "COMPLETE" }
local function integer(value, minimum, maximum)
    return type(value) == "number" and value >= minimum and value <= maximum and value == math.floor(value)
end
local function positive(v) return integer(v, 1, MAX) end
local function count(v) return integer(v, 0, MAX) end
local function text(v) return type(v) == "string" end
local function nonempty(v) return text(v) and v ~= "" end
local function boolean(v) return type(v) == "boolean" end
local item = { _required = { index = true }, index = positive, itemID = positive,
    name = text, icon = function(v) return positive(v) or nonempty(v) end,
    quality = function(v) return integer(v, 0, 8) end, quantity = count }
local model = {
    _required = { moment = true, quest = true },
    moment = function(v) return v == "OFFER" or v == "PROGRESS" or v == "COMPLETE" end,
    quest = { _required = { id = true }, id = positive, title = text, description = text,
        objectiveText = text, progressText = text, rewardText = text },
    objectives = { _array = { _required = { index = true }, index = positive,
        text = text, kind = text, fulfilled = count, required = count, finished = boolean } },
    requiredItems = { _array = item },
    rewards = { choices = { _array = item }, fixed = { _array = item }, money = count, experience = count },
    npc = { guid = nonempty, creatureID = positive, name = text, title = text, faction = nonempty },
    location = { mapID = positive, zone = text, subZone = text },
    chosenReward = item,
}

local function copy(value, spec)
    if type(spec) == "function" then
        if spec(value) then return value end
        return nil
    end
    if type(value) ~= "table" then return nil end
    local result = {}
    if spec._array then
        local length, maximum = 0, 0
        for key in pairs(value) do
            if not integer(key, 1, Quest.MAX_ENTRIES) then return nil end
            length, maximum = length + 1, math.max(maximum, key)
        end
        if length ~= maximum then return nil end
        local indices = {}
        for index = 1, length do
            local entry = copy(value[index], spec._array)
            if not entry or indices[entry.index] then return nil end
            indices[entry.index] = true
            result[index] = entry
        end
    else
        for field, rule in pairs(spec) do
            if field ~= "_required" then
                local input = value[field]
                if input ~= nil then
                    local output = copy(input, rule)
                    if output == nil then return nil end
                    result[field] = output
                elseif spec._required and spec._required[field] then
                    return nil
                end
            end
        end
    end
    return result
end

local function equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do if not equal(value, right[key]) then return false end end
    for key in pairs(right) do if left[key] == nil then return false end end
    return true
end

function Quest.Snapshot(input)
    local snapshot = copy(input, model)
    if not snapshot then return nil, "invalid_dialogue" end
    if snapshot.chosenReward then
        if snapshot.moment ~= "COMPLETE" or not snapshot.chosenReward.itemID then
            return nil, "invalid_dialogue"
        end
        local matched = false
        for _, choice in ipairs(snapshot.rewards and snapshot.rewards.choices or {}) do
            if equal(choice, snapshot.chosenReward) then matched = true; break end
        end
        if not matched then return nil, "invalid_dialogue" end
    end
    return snapshot
end

function Quest.IsEvent(kind) return moments[kind] ~= nil end
function Quest.Moment(kind) return moments[kind] end
function Quest.ValidateEvent(kind, input)
    local snapshot, code = Quest.Snapshot(input)
    if not snapshot or snapshot.moment ~= moments[kind] then return nil, code or "invalid_dialogue" end
    return snapshot
end
function Quest.Equal(left, right)
    local first, second = Quest.Snapshot(left), Quest.Snapshot(right)
    return first ~= nil and second ~= nil and equal(first, second)
end
