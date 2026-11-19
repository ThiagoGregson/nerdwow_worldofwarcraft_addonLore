local _, addon = ...
local API = {}
addon.GossipAPI = API
local Shared = addon.DialogueAPI
local function list(r, fn, convert)
    local raw = r.Table(r.Call(fn))
    if not raw then return nil end
    local count, maximum = 0, 0
    for key in pairs(raw) do
        key = r.Number(key, 1, addon.GossipDialogue.MAX_ENTRIES)
        if not key then r.Fail("api_unavailable"); return nil end
        count, maximum = count + 1, math.max(maximum, key)
    end
    if count ~= maximum then r.Fail("api_unavailable"); return nil end
    local result = {}
    for index = 1, count do
        local value = r.Table(raw[index])
        if value then result[#result + 1] = convert(r, value, index) end
    end
    return result
end
local function texture(r, value)
    local result = r.Number(value, 1) or r.String(value)
    if result ~= "" then return result end
end
local function option(r, value, index)
    return { index = index, optionID = r.Number(value.gossipOptionID, 1), orderIndex = r.Number(value.orderIndex, 0),
        text = r.String(value.name), icon = texture(r, value.icon), overrideIconID = texture(r, value.overrideIconID),
        status = r.Number(value.status, 0, 3), flags = r.Number(value.flags, 0), spellID = r.Number(value.spellID, 1) }
end
local function quest(r, value, index)
    return { index = index, questID = r.Number(value.questID, 1), title = r.String(value.title),
        isComplete = r.Boolean(value.isComplete), level = r.Number(value.questLevel, 0),
        isTrivial = r.Boolean(value.isTrivial), frequency = r.Number(value.frequency, 0),
        isRepeatable = r.Boolean(value.repeatable), isLegendary = r.Boolean(value.isLegendary),
        isIgnored = r.Boolean(value.isIgnored), isImportant = r.Boolean(value.isImportant),
        isMeta = r.Boolean(value.isMeta), questInfoID = r.Number(value.questInfoID, 0) }
end
local function greetingQuests(r, active)
    local count = r.Number(r.Call(active and GetNumActiveQuests or GetNumAvailableQuests), 0,
        addon.GossipDialogue.MAX_ENTRIES)
    if count == nil then return nil end
    local result = {}
    for index = 1, count do
        local value = { index = index }
        if active then
            local title, complete = r.Call(GetActiveTitle, index)
            value.title, value.isComplete = r.String(title), r.Boolean(complete)
            value.questID = r.Number(r.Call(GetActiveQuestID, index), 1)
            value.isTrivial = r.Boolean(r.Call(IsActiveQuestTrivial, index))
        else
            local trivial, frequency, repeatable, legendary, questID, important, meta, infoID = r.Call(GetAvailableQuestInfo, index)
            value.title, value.questID = r.String(r.Call(GetAvailableTitle, index)), r.Number(questID, 1)
            value.isTrivial, value.frequency = r.Boolean(trivial), r.Number(frequency, 0)
            value.isRepeatable, value.isLegendary = r.Boolean(repeatable), r.Boolean(legendary)
            value.isImportant, value.isMeta = r.Boolean(important), r.Boolean(meta)
            value.questInfoID = r.Number(infoID, 0)
        end
        result[#result + 1] = value
    end
    return result
end
local function read(moment)
    local r = Shared.Reader()
    local result = { moment = moment, npc = Shared.ReadNPC(r), location = API.Location() }
    if moment == "GOSSIP" then
        if type(C_GossipInfo) ~= "table" then return nil, "api_unavailable" end
        result.text = r.String(r.Call(C_GossipInfo.GetText))
        result.options = list(r, C_GossipInfo.GetOptions, option)
        result.availableQuests = list(r, C_GossipInfo.GetAvailableQuests, quest)
        result.activeQuests = list(r, C_GossipInfo.GetActiveQuests, quest)
    elseif moment == "GREETING" then
        result.text = r.String(r.Call(GetGreetingText))
        result.availableQuests = greetingQuests(r, false)
        result.activeQuests = greetingQuests(r, true)
    else return nil, "invalid_gossip" end
    if result.text == nil and result.options == nil and result.availableQuests == nil
        and result.activeQuests == nil then
        local code, detail = r.Issue()
        return nil, code or "api_unavailable", detail
    end
    return result, r.Issue()
end
function API.Read(moment)
    local ok, result, code, detail = addon.DiagnosticAPI.Try(read, moment)
    if not ok then return nil, "api_error", result end
    return result, code, detail
end
function API.Location() return addon.QuestAPI.Location() end
function API.Defer(callback)
    if type(C_Timer) ~= "table" or type(C_Timer.After) ~= "function" then return false, "api_unavailable" end
    if not pcall(C_Timer.After, 0, callback) then return nil, "api_error" end
    return true
end
function API.ObserveSelection(callback)
    if type(C_GossipInfo) ~= "table" or type(hooksecurefunc) ~= "function" then return false end
    local installed = false
    local function observe(method)
        return function(value, _, confirmed)
            local r = Shared.Reader()
            value, confirmed = r.Number(value, method == "ID" and 1 or 0), r.Boolean(confirmed)
            if r.Issue() then callback(nil, nil, r.Issue()); return end
            local ok, npc = pcall(Shared.ReadNPC, r)
            if not ok then callback(nil, nil, "api_error"); return end
            if not value then callback(nil, nil, r.Issue() or "api_unavailable"); return end
            callback({ method = method, value = value, confirmed = confirmed }, npc, r.Issue())
        end
    end
    for _, spec in ipairs({ { "SelectOption", "ID" }, { "SelectOptionByIndex", "INDEX" } }) do
        if type(C_GossipInfo[spec[1]]) == "function" then
            if not pcall(hooksecurefunc, C_GossipInfo, spec[1], observe(spec[2])) then return nil, "api_error" end
            installed = true
        end
    end
    return installed
end
