local _, addon = ...
local Capture = { Events = { "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "QUEST_ACCEPTED",
    "QUEST_TURNED_IN", "QUEST_FINISHED", "QUEST_ITEM_UPDATE" } }
addon.QuestCapture = Capture
local moments = { QUEST_DETAIL = "OFFER", QUEST_PROGRESS = "PROGRESS", QUEST_COMPLETE = "COMPLETE" }
function Capture.New(options)
    local session, api = options.Session, options.API
    local _, code = api.ObserveSelection(session.SelectReward)
    options.Issue(code)
    local handle = {}
    function handle.Handle(event, questID, experience, money)
        if event == "PLAYER_LEAVING_WORLD" then session.Reset(); return false end
        if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then session.Close(); return false end
        if event == "QUEST_FINISHED" then session.Close(); return true end
        local moment, expectedID = moments[event]
        if event == "QUEST_ITEM_UPDATE" then
            local current = session.GetCurrent()
            if not current then return true end
            moment, expectedID = current.moment, current.quest.id
        end
        local kind, model, failure
        if moment then
            local raw
            raw, failure = api.Read(moment)
            options.Issue(failure)
            if raw and expectedID and raw.quest.id ~= expectedID then return true end
            if raw then model, failure = session.Observe(raw) end
            if not model then session.Close(); options.Warn(failure or "api_unavailable"); return true end
            kind = moment == "OFFER" and "QUEST_OFFERED" or moment == "PROGRESS" and "QUEST_PROGRESS_VIEWED"
        elseif event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
            local info
            info, failure = api.EventInfo(questID, experience, money)
            options.Issue(failure)
            if not info then options.Warn(failure or "api_unavailable"); return true end
            kind = event == "QUEST_ACCEPTED" and "QUEST_ACCEPTED" or "QUEST_COMPLETED"
            local fallback
            fallback, failure = api.ReadLog(info.questID, addon.QuestDialogue.Moment(kind))
            options.Issue(failure)
            model, failure = session.ForEvent(kind, info.questID, fallback, api.Location(), info.money, info.experience)
            if not model then options.Warn(failure or "invalid_dialogue"); return true end
        else return false end
        if kind then options.Append(kind, model) end
        return true
    end
    return handle
end
