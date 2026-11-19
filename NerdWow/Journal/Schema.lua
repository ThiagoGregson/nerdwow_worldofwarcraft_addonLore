local _, addon = ...

-- Contrato público: constantes, ValidateRoot e ValidateInput.
-- Lua puro: nenhuma leitura da API, de globals de dados ou de relógio.
local Schema = {
    VERSION = 1,
    MAX_EVENTS = 5000,
    MAX_SEQUENCE = 9007199254740991,
}
addon.Schema = Schema
local Quest = addon.QuestDialogue
local Gossip = addon.GossipDialogue

local payloadFields = {
    CHARACTER_CONTEXT = {
        "guid", "name", "realm", "raceID", "race", "raceName",
        "classID", "class", "className", "level", "faction",
    },
    LOCATION_CHANGED = { "mapID", "zone", "subZone" },
}

local function integer(value, minimum, maximum)
    return type(value) == "number" and value >= minimum
        and value <= maximum and value == math.floor(value)
end

local function text(value)
    return type(value) == "string" and value ~= ""
end

local function characterKey(value)
    return type(value) == "string" and value:match("^Player%-%d+%-%x+$") ~= nil
end

local function validPayload(kind, key, payload)
    if type(payload) ~= "table" then
        return false, "payload"
    end
    if kind == "CHARACTER_CONTEXT" then
        if payload.guid ~= key then return false, "payload.guid" end
        for _, field in ipairs({ "name", "realm", "race", "raceName", "class", "className" }) do
            if not text(payload[field]) then return false, "payload." .. field end
        end
        for _, field in ipairs({ "raceID", "classID", "level" }) do
            if not integer(payload[field], 1, Schema.MAX_SEQUENCE) then return false, "payload." .. field end
        end
        if payload.faction ~= "Alliance" and payload.faction ~= "Horde" and payload.faction ~= "Neutral" then
            return false, "payload.faction"
        end
        return true
    elseif kind == "LOCATION_CHANGED" then
        if payload.mapID ~= nil and not integer(payload.mapID, 1, Schema.MAX_SEQUENCE) then return false, "payload.mapID" end
        if not text(payload.zone) then return false, "payload.zone" end
        if type(payload.subZone) ~= "string" then return false, "payload.subZone" end
        return true
    elseif Gossip.IsEvent(kind) then
        local snapshot = Gossip.ValidateEvent(kind, payload)
        return snapshot ~= nil and (kind ~= "GOSSIP_OPTION_SELECTED"
            or Gossip.ReferenceKey(snapshot.conversationEventID) == key)
    elseif Quest.IsEvent(kind) then
        local snapshot = Quest.ValidateStoredEvent(kind, payload)
        return snapshot ~= nil and (kind ~= "QUEST_ACCEPTED" or not snapshot.offerEventID
            or snapshot.offerEventID:match("^(Player%-%d+%-%x+):") == key)
    end
    -- Leitura compatível com tipos futuros aditivos. Escrita é restrita abaixo.
    return true
end

local function validEnvelope(event)
    return type(event) == "table" and characterKey(event.characterKey)
        and integer(event.sequence, 1, Schema.MAX_SEQUENCE - 1)
        and event.id == event.characterKey .. ":" .. string.format("%.0f", event.sequence)
        and integer(event.timestamp, 1, Schema.MAX_SEQUENCE)
        and text(event.type) and validPayload(event.type, event.characterKey, event.payload)
end

-- Não altera nenhum dado, mesmo quando a falha ocorre no último evento.
function Schema.ValidateRoot(root)
    if type(root) ~= "table" then
        return nil, "invalid_root"
    end
    if root.schemaVersion ~= Schema.VERSION then
        return nil, "unsupported_schema"
    end
    if not integer(root.nextSequence, 1, Schema.MAX_SEQUENCE)
        or not integer(root.droppedEvents, 0, Schema.MAX_SEQUENCE) then
        return nil, "invalid_sequence"
    end
    if type(root.events) ~= "table" then
        return nil, "invalid_events"
    end
    -- # não detecta lacunas de arrays Lua de forma confiável.
    local count, maximum = 0, 0
    for index in pairs(root.events) do
        if not integer(index, 1, Schema.MAX_SEQUENCE) then
            return nil, "invalid_events"
        end
        count = count + 1
        maximum = math.max(maximum, index)
    end
    if count ~= maximum then
        return nil, "invalid_events"
    end
    local previous = 0
    for index = 1, count do
        local event = root.events[index]
        if not validEnvelope(event) then
            return nil, "invalid_event"
        end
        if event.sequence <= previous or event.sequence >= root.nextSequence then
            return nil, "invalid_sequence"
        end
        previous = event.sequence
    end
    return true
end

-- Retorna uma fotografia dos campos conhecidos; entradas inválidas não têm efeitos.
function Schema.ValidateInput(kind, key, timestamp, payload)
    if type(kind) ~= "string" or not (payloadFields[kind] or Quest.IsEvent(kind) or Gossip.IsEvent(kind)) then
        return nil, "unsupported_type", "type"
    end
    if not characterKey(key) then return nil, "invalid_input", "characterKey" end
    if not integer(timestamp, 1, Schema.MAX_SEQUENCE) then return nil, "invalid_input", "timestamp" end
    if Gossip.IsEvent(kind) then
        local snapshot, _, field = Gossip.ValidateEvent(kind, payload)
        if not snapshot then return nil, "invalid_input", field end
        if kind == "GOSSIP_OPTION_SELECTED" and Gossip.ReferenceKey(snapshot.conversationEventID) ~= key then
            return nil, "invalid_input", "payload.conversationEventID"
        end
        return snapshot
    elseif Quest.IsEvent(kind) then
        local snapshot, _, field = Quest.ValidateEvent(kind, payload)
        if snapshot and kind == "QUEST_ACCEPTED" and snapshot.offerEventID
            and snapshot.offerEventID:match("^(Player%-%d+%-%x+):") ~= key then
            return nil, "invalid_input", "payload.offerEventID"
        end
        if not snapshot then return nil, "invalid_input", field end
        return snapshot
    end
    local valid, field = validPayload(kind, key, payload)
    if not valid then return nil, "invalid_input", field end
    local snapshot = {}
    for _, field in ipairs(payloadFields[kind]) do
        snapshot[field] = payload[field]
    end
    return snapshot
end
