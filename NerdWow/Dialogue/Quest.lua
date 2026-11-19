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
local function eventID(value)
    if type(value) ~= "string" then return false end
    local sequence = value:match("^Player%-%d+%-%x+:([1-9]%d*)$")
    return sequence ~= nil and (#sequence < 16 or (#sequence == 16 and sequence <= "9007199254740990"))
end
local accepted = { _required = { moment = true, quest = true },
    moment = model.moment, quest = model.quest, npc = model.npc, location = model.location,
    objectives = model.objectives, offerEventID = eventID }

local function copy(value, spec, path)
    path = path or "payload"
    if type(spec) == "function" then
        if spec(value) then return value end
        return nil, path
    end
    if type(value) ~= "table" then return nil, path end
    local result = {}
    if spec._array then
        local length, maximum = 0, 0
        for key in pairs(value) do
            if not integer(key, 1, Quest.MAX_ENTRIES) then return nil, path end
            length, maximum = length + 1, math.max(maximum, key)
        end
        if length ~= maximum then return nil, path end
        local indices = {}
        for index = 1, length do
            local entry, field = copy(value[index], spec._array, path .. "[" .. index .. "]")
            if not entry then return nil, field end
            if indices[entry.index] then return nil, path .. "[" .. index .. "].index" end
            indices[entry.index] = true
            result[index] = entry
        end
    else
        for field, rule in pairs(spec) do
            if field ~= "_required" then
                local input = value[field]
                if input ~= nil then
                    local output, failure = copy(input, rule, path .. "." .. field)
                    if output == nil then return nil, failure end
                    result[field] = output
                elseif spec._required and spec._required[field] then
                    return nil, path .. "." .. field
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
    local snapshot, field = copy(input, model)
    if not snapshot then return nil, "invalid_dialogue", field end
    -- O log da missão não é fonte confiável de progresso após a entrega.
    -- Não se transforma uma contagem antiga em uma conclusão inventada.
    if snapshot.moment == "COMPLETE" then snapshot.objectives = nil end
    if snapshot.chosenReward then
        if snapshot.moment ~= "COMPLETE" or not snapshot.chosenReward.itemID then
            return nil, "invalid_dialogue", "payload.chosenReward"
        end
        local matched = false
        for _, choice in ipairs(snapshot.rewards and snapshot.rewards.choices or {}) do
            if equal(choice, snapshot.chosenReward) then matched = true; break end
        end
        if not matched then return nil, "invalid_dialogue", "payload.chosenReward" end
    end
    return snapshot
end

function Quest.IsEvent(kind) return moments[kind] ~= nil end
function Quest.Moment(kind) return moments[kind] end
function Quest.SnapshotNPC(input) return copy(input, model.npc, "payload.npc") end
function Quest.SnapshotLocation(input) return copy(input, model.location, "payload.location") end
function Quest.ValidateEvent(kind, input)
    local snapshot, code, field
    if kind == "QUEST_ACCEPTED" then
        snapshot, field = copy(input, accepted)
        if snapshot then
            for _, name in ipairs({ "rewards", "requiredItems", "chosenReward" }) do
                if input[name] ~= nil then return nil, "invalid_dialogue", "payload." .. name end
            end
            for _, name in ipairs({ "progressText", "rewardText", "description", "objectiveText" }) do
                if snapshot.quest[name] ~= nil and (name=="progressText" or name=="rewardText" or snapshot.offerEventID) then
                    return nil, "invalid_dialogue", "payload.quest." .. name
                end
            end
        end
    else
        snapshot, code, field = Quest.Snapshot(input)
    end
    if not snapshot then return nil, code or "invalid_dialogue", field end
    if snapshot.moment ~= moments[kind] then return nil, "invalid_dialogue", "payload.moment" end
    return snapshot
end
-- Leitura compatível com os aceites completos e objetivos históricos da 0.4.0.
-- A validação produz cópia; o diário nunca reescreve os eventos carregados.
function Quest.ValidateStoredEvent(kind, input)
    local snapshot, code = Quest.Snapshot(input)
    if not snapshot or snapshot.moment ~= moments[kind] then return nil, code or "invalid_dialogue" end
    if kind == "QUEST_ACCEPTED" and input.offerEventID ~= nil then
        if not eventID(input.offerEventID) then return nil, "invalid_dialogue" end
        snapshot.offerEventID = input.offerEventID
    end
    return snapshot
end
function Quest.Acceptance(input, reference, offered)
    local source, code = Quest.Snapshot(input)
    if not source or source.moment ~= "OFFER" then return nil, code or "invalid_dialogue" end
    local offer = offered and Quest.Snapshot(offered)
    if offer and (offer.quest.id ~= source.quest.id or offer.moment ~= "OFFER") then offer = nil end
    local result = { moment = "OFFER", quest = { id = source.quest.id,
        title = source.quest.title or (offer and offer.quest.title) }, offerEventID = reference,
        npc = source.npc or (offer and offer.npc), location = source.location, objectives = source.objectives }
    if not reference then
        result.quest.description = source.quest.description or (offer and offer.quest.description)
        result.quest.objectiveText = source.quest.objectiveText or (offer and offer.quest.objectiveText)
    end
    return Quest.ValidateEvent("QUEST_ACCEPTED", result)
end
function Quest.Equal(left, right)
    local first, second = Quest.Snapshot(left), Quest.Snapshot(right)
    return first ~= nil and second ~= nil and equal(first, second)
end
function Quest.EqualEvent(kind, left, right)
    if kind ~= "QUEST_ACCEPTED" then return Quest.Equal(left, right) end
    local first, second = Quest.ValidateStoredEvent(kind, left), Quest.ValidateStoredEvent(kind, right)
    return first ~= nil and second ~= nil and equal(first, second)
end
