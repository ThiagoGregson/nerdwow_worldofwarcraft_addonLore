local _, addon = ...
local Quest = addon.QuestDialogue
local Session = {}
addon.QuestSession = Session

function Session.New()
    local current, offer, completion, selected
    local session = {}
    function session.Observe(input)
        local snapshot, code = Quest.Snapshot(input)
        if not snapshot then return nil, code end
        current = snapshot
        if snapshot.moment == "OFFER" then
            offer, completion, selected = snapshot, nil, nil
        elseif snapshot.moment == "PROGRESS" then
            completion, selected = nil, nil
        else
            completion, selected = snapshot, nil
        end
        return Quest.Snapshot(snapshot)
    end
    function session.GetCurrent()
        if current then return Quest.Snapshot(current) end
    end
    function session.Close() current = nil end
    function session.Reset() current, offer, completion, selected = nil, nil, nil, nil end
    function session.SelectReward(questID, index)
        selected = nil
        if not completion or completion.quest.id ~= questID then return false end
        for _, choice in ipairs(completion.rewards and completion.rewards.choices or {}) do
            if choice.index == index and choice.itemID then
                selected = choice
                return true
            end
        end
        return false
    end
    function session.ForEvent(kind, questID, fallback, location, money, experience)
        local moment = Quest.Moment(kind)
        if not moment then return nil, "invalid_dialogue" end
        local cached = kind == "QUEST_ACCEPTED" and offer or kind == "QUEST_COMPLETED" and completion
        local result
        if cached and cached.quest.id == questID then result = Quest.Snapshot(cached)
        else result = { moment = moment, quest = { id = questID } } end
        if fallback then
            local fresh, code = Quest.Snapshot(fallback)
            if not fresh or fresh.quest.id ~= questID or fresh.moment ~= moment then
                return nil, code or "invalid_dialogue"
            end
            for field, value in pairs(fresh.quest) do result.quest[field] = value end
            for _, field in ipairs({ "objectives", "requiredItems", "npc" }) do
                if fresh[field] ~= nil then result[field] = fresh[field] end
            end
            if fresh.rewards then
                result.rewards = result.rewards or {}
                for field, value in pairs(fresh.rewards) do result.rewards[field] = value end
            end
        end
        result.location = location
        result.chosenReward = nil
        if kind == "QUEST_COMPLETED" then
            if money ~= nil or experience ~= nil then
                result.rewards = result.rewards or {}
                result.rewards.money = money or result.rewards.money
                result.rewards.experience = experience or result.rewards.experience
            end
            if cached and cached.quest.id == questID and selected then result.chosenReward = selected end
        end
        -- O aceite ainda carrega a lore disponível em memória; somente o diário
        -- sabe se há oferta retida e pode substituí-la por uma referência.
        local snapshot, code
        if kind == "QUEST_ACCEPTED" then snapshot, code = Quest.Snapshot(result)
        else snapshot, code = Quest.ValidateEvent(kind, result) end
        if snapshot and kind == "QUEST_COMPLETED" and offer and offer.quest.id == questID then offer = nil end
        return snapshot, code
    end
    return session
end
