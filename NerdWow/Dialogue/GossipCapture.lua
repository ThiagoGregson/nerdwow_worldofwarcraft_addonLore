local _, addon = ...
local Capture = { Events = { "GOSSIP_SHOW", "GOSSIP_CLOSED", "GOSSIP_OPTIONS_REFRESHED", "QUEST_GREETING",
    "GOSSIP_CONFIRM", "GOSSIP_ENTER_CODE", "GOSSIP_CONFIRM_CANCEL" } }
addon.GossipCapture = Capture
function Capture.New(options)
    local api, session = options.API, options.Session
    local function selectOption(selection, npc, code)
        options.Issue(code)
        if not selection then return end
        local payload = session.Select(selection, npc)
        if payload then
            payload.location = api.Location()
            options.Append("GOSSIP_OPTION_SELECTED", payload)
        end
    end
    local available, failure = api.ObserveSelection(selectOption)
    options.Issue(failure)
    local handle = {}
    function handle.Handle(event)
        if event == "PLAYER_LEAVING_WORLD" or event == "QUEST_FINISHED" or event == "QUEST_DETAIL"
            or event == "QUEST_PROGRESS" or event == "QUEST_COMPLETE" then session.Close(); return false end
        if event == "GOSSIP_CLOSED" then session.Close(); return true end
        if event == "GOSSIP_CONFIRM" or event == "GOSSIP_ENTER_CODE" then session.ConfirmRequired(); return true end
        if event == "GOSSIP_CONFIRM_CANCEL" then session.CancelConfirmation(); return true end
        local moment = event == "QUEST_GREETING" and "GREETING" or event == "GOSSIP_SHOW" and "GOSSIP"
        if event == "GOSSIP_OPTIONS_REFRESHED" then
            local current = session.GetCurrent()
            if not current or current.moment ~= "GOSSIP" then return true end
            moment = "GOSSIP"
        end
        if not moment then return false end
        local raw, code = api.Read(moment)
        options.Issue(code)
        if not raw then session.Close(); options.Warn(code or "api_unavailable"); return true end
        local model, token = session.Observe(raw)
        if not model then options.Warn(token); return true end
        if addon.GossipDialogue.HasContent(model) then
            local id = options.Append("GOSSIP_VIEWED", model)
            if not id then id = options.FindConversation(model) end
            session.Bind(id)
            if available and id then
                local deferred, issue = api.Defer(function() session.Arm(token) end)
                if not deferred then options.Issue(issue or "api_unavailable") end
            end
        end
        return true
    end
    return handle
end
