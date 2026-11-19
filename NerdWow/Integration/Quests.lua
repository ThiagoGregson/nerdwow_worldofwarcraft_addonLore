local _, addon = ...
local API = {}
addon.QuestAPI = API
local MAX = 9007199254740991

-- Toda comparação/conversão de retornos passa primeiro pela barreira de secretos.
local function reader()
    local failure
    local r = {}
    function r.Plain(value)
        if issecretvalue and issecretvalue(value) then failure = "secret_value"; return nil end
        return value
    end
    function r.Call(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, a, b, c, d, e, f = pcall(fn, ...)
        if not ok then failure = "api_error"; return nil end
        return a, b, c, d, e, f
    end
    function r.Number(value, minimum, maximum)
        value = r.Plain(value)
        if type(value) == "number" and value >= minimum and value <= (maximum or MAX)
            and value == math.floor(value) then return value end
    end
    function r.String(value)
        value = r.Plain(value)
        if type(value) == "string" then return value end
    end
    function r.Boolean(value)
        value = r.Plain(value)
        if type(value) == "boolean" then return value end
    end
    function r.Table(value)
        value = r.Plain(value)
        if type(value) == "table" then return value end
    end
    function r.Issue() return failure end
    return r
end

local function objectives(r, questID)
    local raw = r.Table(r.Call(C_QuestLog.GetQuestObjectives, questID))
    if not raw or #raw > addon.QuestDialogue.MAX_ENTRIES then return nil end
    local result = {}
    for index = 1, #raw do
        local entry = r.Table(raw[index])
        if entry then
            result[#result + 1] = { index = index, text = r.String(entry.text), kind = r.String(entry.type),
                fulfilled = r.Number(entry.numFulfilled, 0), required = r.Number(entry.numRequired, 0),
                finished = r.Boolean(entry.finished) }
        end
    end
    return result
end

local function items(r, kind, countFunction)
    local count = r.Number(r.Call(countFunction), 0, addon.QuestDialogue.MAX_ENTRIES)
    if count == nil then return nil end
    local result = {}
    for index = 1, count do
        local hidden = kind == "required" and r.Boolean(r.Call(IsQuestItemHidden, index))
        if not hidden then
            local name, icon, quantity, quality, _, itemID = r.Call(GetQuestItemInfo, kind, index)
            itemID = r.Number(itemID, 1)
            if not itemID then
                local link = r.String(r.Call(GetQuestItemLink, kind, index))
                if link then itemID = r.Number(tonumber(link:match("item:(%d+)")), 1) end
            end
            local texture = r.Number(icon, 1) or r.String(icon)
            if texture == "" then texture = nil end
            result[#result + 1] = { index = index, itemID = itemID, name = r.String(name),
                icon = texture, quantity = r.Number(quantity, 0), quality = r.Number(quality, 0, 8) }
        end
    end
    return result
end

local function npc(r)
    if r.Boolean(r.Call(UnitExists, "npc")) ~= true then return nil end
    local guid = r.String(r.Call(UnitGUID, "npc"))
    local creatureID
    if guid then
        creatureID = r.Number(tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
            or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")), 1)
    end
    local result = { guid = guid, creatureID = creatureID, name = r.String(r.Call(UnitName, "npc")),
        faction = r.String(r.Call(UnitFactionGroup, "npc")) }
    if result.guid == "" then result.guid = nil end
    if result.faction == "" then result.faction = nil end
    if creatureID and type(C_TooltipInfo) == "table" then
        local data = r.Table(r.Call(C_TooltipInfo.GetUnit, "npc"))
        local lines = data and r.Table(data.lines)
        local line = lines and r.Table(lines[2])
        local subtitle = line and r.String(line.leftText)
        if subtitle then result.title = subtitle:match("^<([^<>]+)>$") end
    end
    if not result.guid and not result.name and not result.faction and not result.title then return nil end
    return result
end

function API.Location()
    local value = addon.Wow.ReadLocation()
    return value
end

function API.Read(moment)
    local r = reader()
    local questID = r.Number(r.Call(GetQuestID), 1)
    if not questID then return nil, r.Issue() or "api_unavailable" end
    local result = { moment = moment, quest = { id = questID, title = r.String(r.Call(GetTitleText)) },
        npc = npc(r), location = API.Location() }
    if moment ~= "COMPLETE" then result.objectives = objectives(r, questID) end
    if moment == "OFFER" then
        result.quest.description = r.String(r.Call(GetQuestText))
        result.quest.objectiveText = r.String(r.Call(GetObjectiveText))
    elseif moment == "PROGRESS" then
        result.quest.progressText = r.String(r.Call(GetProgressText))
        local hidden = type(C_QuestOffer) == "table" and r.Boolean(r.Call(C_QuestOffer.GetHideRequiredItems))
        if not hidden then result.requiredItems = items(r, "required", GetNumQuestItems) end
    elseif moment == "COMPLETE" then
        result.quest.rewardText = r.String(r.Call(GetRewardText))
    end
    if moment == "OFFER" or moment == "COMPLETE" then
        result.rewards = { choices = items(r, "choice", GetNumQuestChoices),
            fixed = items(r, "reward", GetNumQuestRewards),
            money = r.Number(r.Call(GetRewardMoney), 0), experience = r.Number(r.Call(GetRewardXP), 0) }
        if not result.rewards.choices and not result.rewards.fixed
            and result.rewards.money == nil and result.rewards.experience == nil then result.rewards = nil end
    end
    return result, r.Issue()
end

function API.ReadLog(questID, moment)
    local r = reader()
    questID = r.Number(questID, 1)
    if not questID then return nil, r.Issue() or "api_unavailable" end
    local result = { moment = moment, quest = { id = questID,
        title = r.String(r.Call(C_QuestLog.GetTitleForQuestID, questID)) } }
    if moment ~= "COMPLETE" then result.objectives = objectives(r, questID) end
    return result, r.Issue()
end

function API.EventInfo(questID, experience, money)
    local r = reader()
    questID = r.Number(questID, 1)
    if not questID then return nil, r.Issue() or "api_unavailable" end
    return { questID = questID, experience = r.Number(experience, 0), money = r.Number(money, 0) }, r.Issue()
end

function API.ObserveSelection(callback)
    if type(hooksecurefunc) ~= "function" or type(GetQuestReward) ~= "function" then return false end
    local ok = pcall(hooksecurefunc, "GetQuestReward", function(index)
        local r = reader()
        index = r.Number(index, 1, addon.QuestDialogue.MAX_ENTRIES)
        local questID = r.Number(r.Call(GetQuestID), 1)
        -- Uma tentativa restrita/ambígua também invalida a escolha observada antes.
        callback(questID, index)
    end)
    if not ok then return nil, "api_error" end
    return true
end
