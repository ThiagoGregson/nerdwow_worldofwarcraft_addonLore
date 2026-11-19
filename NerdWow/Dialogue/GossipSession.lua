local _, addon = ...
local Gossip = addon.GossipDialogue
local Session = {}
addon.GossipSession = Session
function Session.New()
    local current, reference, armed, waiting
    local generation = 0
    local session = {}
    function session.Close()
        current, reference, armed, waiting = nil, nil, false, false
        generation = generation + 1
    end
    session.Reset = session.Close
    function session.Observe(input)
        session.Close()
        local snapshot, code = Gossip.Snapshot(input)
        if not snapshot then return nil, code end
        current = snapshot
        return Gossip.Snapshot(current), generation
    end
    function session.GetCurrent() if current then return Gossip.Snapshot(current) end end
    function session.Bind(id)
        reference = Gossip.ReferenceKey(id) and id or nil
    end
    function session.Arm(token)
        if token == generation and current and current.moment == "GOSSIP" then armed = true end
    end
    function session.ConfirmRequired() waiting = true end
    function session.CancelConfirmation() waiting = false end
    function session.Select(selection, npc)
        if not current or not reference or not armed or type(selection) ~= "table"
            or (waiting and selection.confirmed ~= true) then return nil, "uncorrelated_gossip" end
        if not current.npc or not current.npc.creatureID or not current.npc.guid or not npc
            or npc.creatureID ~= current.npc.creatureID or npc.guid ~= current.npc.guid then
            return nil, "uncorrelated_gossip"
        end
        local field = selection.method == "ID" and "optionID" or selection.method == "INDEX" and "orderIndex"
        if not field or type(selection.value) ~= "number" then return nil, "uncorrelated_gossip" end
        local found
        for _, option in ipairs(current.options or {}) do
            if option[field] == selection.value then
                if found then return nil, "uncorrelated_gossip" end
                found = option
            end
        end
        if not found or (found.status ~= nil and found.status ~= 0) then return nil, "uncorrelated_gossip" end
        local payload, code = Gossip.Selection(current, reference, found)
        if not payload then return nil, code end
        -- Consome a observação, inclusive quando dois hooks encadeados notificam a mesma ação.
        armed = false
        payload.npc = addon.QuestDialogue.SnapshotNPC(npc)
        return payload
    end
    return session
end
