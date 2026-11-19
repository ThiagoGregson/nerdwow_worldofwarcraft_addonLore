local _, addon = ...
local Schema = addon.Schema
local Journal = {}
addon.Journal = Journal

local function retain(root)
    local count = #root.events
    local excess = count - Schema.MAX_EVENTS
    if excess <= 0 then
        return
    end
    for index = 1, Schema.MAX_EVENTS do
        root.events[index] = root.events[index + excess]
    end
    for index = Schema.MAX_EVENTS + 1, count do
        root.events[index] = nil
    end
    root.droppedEvents = math.min(Schema.MAX_SEQUENCE, root.droppedEvents + excess)
end

-- Única entrada para abrir o diário. A raiz pertence exclusivamente a este módulo.
function Journal.Open(saved)
    local root = saved
    if root == nil then
        root = { schemaVersion = Schema.VERSION, nextSequence = 1,
            droppedEvents = 0, events = {} }
    end
    local valid, code = Schema.ValidateRoot(root)
    if not valid then
        return nil, saved, code
    end
    retain(root)
    local journal = {}

    function journal.FindConversation(key, input)
        local model = addon.GossipDialogue.Snapshot(input)
        if not model or not model.npc or not model.npc.creatureID then return nil end
        for index = #root.events, 1, -1 do
            local event = root.events[index]
            if event.type == "GOSSIP_VIEWED" and event.characterKey == key
                and event.payload.npc and event.payload.npc.creatureID == model.npc.creatureID then
                if addon.GossipDialogue.EqualConversation(event.payload, model) then return event.id end
                return nil
            end
        end
    end

    function journal.Append(kind, key, timestamp, payload)
        local offer, reference, offerSequence
        if kind == "QUEST_ACCEPTED" then
            local source = addon.QuestDialogue.Snapshot(payload)
            if not source or source.moment ~= "OFFER" then return nil, "invalid_input" end
            -- A oferta mais antiga pode desaparecer na própria inserção do aceite.
            local firstRetained = math.max(1, #root.events - Schema.MAX_EVENTS + 2)
            for index = #root.events, 1, -1 do
                local previous = root.events[index]
                if previous.type == "QUEST_OFFERED" and previous.characterKey == key
                    and previous.payload.quest.id == source.quest.id then
                    local narrativeMatches = true
                    for _, field in ipairs({ "description", "objectiveText" }) do
                        if source.quest[field] ~= nil and source.quest[field] ~= previous.payload.quest[field] then
                            narrativeMatches = false
                        end
                    end
                    if narrativeMatches then
                        offer = previous.payload
                        offerSequence = previous.sequence
                        if index >= firstRetained then reference = previous.id end
                    end
                    break
                end
            end
            payload = addon.QuestDialogue.Acceptance(source, reference, offer)
            if not payload then return nil, "invalid_input" end
        end
        local snapshot, failure = Schema.ValidateInput(kind, key, timestamp, payload)
        if not snapshot then
            return nil, failure
        end
        if kind == "GOSSIP_VIEWED" then
            if journal.FindConversation(key, snapshot) then return nil, "duplicate_gossip" end
        elseif kind == "GOSSIP_OPTION_SELECTED" then
            local matched = false
            -- O alvo precisa estar presente e sobreviver à inserção do evento.
            local firstRetained = math.max(1, #root.events - Schema.MAX_EVENTS + 2)
            for index = #root.events, firstRetained, -1 do
                local event = root.events[index]
                if event.id == snapshot.conversationEventID and event.type == "GOSSIP_VIEWED"
                    and event.characterKey == key and event.payload.moment == "GOSSIP"
                    and event.payload.npc and snapshot.npc and snapshot.npc.creatureID
                    and snapshot.npc.creatureID == event.payload.npc.creatureID then
                    for _, option in ipairs(event.payload.options or {}) do
                        if addon.GossipDialogue.EqualOption(option, snapshot.option) then matched = true end
                    end
                    break
                end
            end
            if not matched then return nil, "uncorrelated_gossip" end
        elseif kind == "LOCATION_CHANGED" then
            for index = #root.events, 1, -1 do
                local previous = root.events[index]
                if previous.type == kind and previous.characterKey == key then
                    local last = previous.payload
                    if last.mapID == snapshot.mapID and last.zone == snapshot.zone
                        and last.subZone == snapshot.subZone then
                        return nil, "duplicate_location"
                    end
                    break
                end
            end
        elseif addon.QuestDialogue.IsEvent(kind) then
            for index = #root.events, 1, -1 do
                local previous = root.events[index]
                if previous.type == kind and previous.characterKey == key
                    and previous.payload.quest.id == snapshot.quest.id
                    and previous.payload.moment == snapshot.moment then
                    local previousPayload = previous.payload
                    if kind == "QUEST_ACCEPTED" then
                        local previousReference = previousPayload.offerEventID
                        if not previousReference and reference and offerSequence < previous.sequence then
                            previousReference = reference
                        end
                        previousPayload = addon.QuestDialogue.Acceptance(previousPayload, previousReference, offer)
                    end
                    if addon.QuestDialogue.EqualEvent(kind, previousPayload, snapshot) then
                        return nil, "duplicate_quest"
                    end
                    break
                end
            end
        end
        if root.nextSequence >= Schema.MAX_SEQUENCE then
            return nil, "sequence_exhausted"
        end
        local sequence = root.nextSequence
        local id = key .. ":" .. string.format("%.0f", sequence)
        root.events[#root.events + 1] = {
            id = id, sequence = sequence, timestamp = timestamp,
            type = kind, characterKey = key, payload = snapshot,
        }
        root.nextSequence = sequence + 1
        retain(root)
        return id
    end

    function journal.GetStatus()
        local last = root.events[#root.events]
        return {
            schemaVersion = root.schemaVersion, totalEvents = #root.events,
            droppedEvents = root.droppedEvents,
            lastType = last and last.type,
            lastTimestamp = last and last.timestamp,
        }
    end

    return journal, root
end
