local _, addon = ...
local Gossip = { MAX_ENTRIES = 256 }
addon.GossipDialogue = Gossip
local Quest = addon.QuestDialogue
local MAX = 9007199254740991
local function integer(value, minimum, maximum)
    return type(value) == "number" and value >= minimum and value <= (maximum or MAX)
        and value == math.floor(value)
end
local function positive(v) return integer(v, 1) end
local function count(v) return integer(v, 0) end
local function text(v) return type(v) == "string" end
local function boolean(v) return type(v) == "boolean" end
local function icon(v) return positive(v) or (text(v) and v ~= "") end
local optionFields = { index = positive, optionID = positive, orderIndex = count, text = text,
    icon = icon, overrideIconID = icon, status = function(v) return integer(v, 0, 3) end,
    flags = count, spellID = positive }
local questFields = { index = positive, questID = positive, title = text, isComplete = boolean,
    level = count, isTrivial = boolean, frequency = count, isRepeatable = boolean,
    isLegendary = boolean, isIgnored = boolean, isImportant = boolean, isMeta = boolean, questInfoID = count }
local function entry(input, fields)
    if type(input) ~= "table" or not positive(input.index) then return nil end
    local result = {}
    for name, validate in pairs(fields) do
        local value = input[name]
        if value ~= nil then
            if not validate(value) then return nil end
            result[name] = value
        end
    end
    return result
end
local function array(input, fields)
    if type(input) ~= "table" then return nil end
    local length, maximum = 0, 0
    for key in pairs(input) do
        if not integer(key, 1, Gossip.MAX_ENTRIES) then return nil end
        length, maximum = length + 1, math.max(maximum, key)
    end
    if length ~= maximum then return nil end
    local result, indices = {}, {}
    for index = 1, length do
        local value = entry(input[index], fields)
        if not value or indices[value.index] then return nil end
        indices[value.index], result[index] = true, value
    end
    return result
end
local function equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
local function nonblank(value) return type(value) == "string" and value:find("%S") ~= nil end
function Gossip.Snapshot(input)
    if type(input) ~= "table" or (input.moment ~= "GOSSIP" and input.moment ~= "GREETING") then
        return nil, "invalid_gossip"
    end
    local result = { moment = input.moment }
    if input.text ~= nil then
        if not text(input.text) then return nil, "invalid_gossip" end
        result.text = input.text
    end
    for field, fields in pairs({ options = optionFields, availableQuests = questFields, activeQuests = questFields }) do
        if input[field] ~= nil then
            result[field] = array(input[field], fields)
            if not result[field] then return nil, "invalid_gossip" end
        end
    end
    if input.npc ~= nil then
        result.npc = Quest.SnapshotNPC(input.npc)
        if not result.npc then return nil, "invalid_gossip" end
    end
    if input.location ~= nil then
        result.location = Quest.SnapshotLocation(input.location)
        if not result.location then return nil, "invalid_gossip" end
    end
    return result
end
function Gossip.HasContent(model)
    if nonblank(model.text) then return true end
    for _, option in ipairs(model.options or {}) do
        if nonblank(option.text) or option.optionID then return true end
    end
    for _, field in ipairs({ "availableQuests", "activeQuests" }) do
        for _, quest in ipairs(model[field] or {}) do
            if nonblank(quest.title) or quest.questID then return true end
        end
    end
    return false
end
function Gossip.EqualConversation(left, right)
    local first, second = Gossip.Snapshot(left), Gossip.Snapshot(right)
    if not first or not second then return false end
    first.location, second.location = nil, nil
    if first.npc then first.npc.guid = nil end
    if second.npc then second.npc.guid = nil end
    return equal(first, second)
end
function Gossip.EqualOption(left, right)
    local first, second = entry(left, optionFields), entry(right, optionFields)
    return first ~= nil and second ~= nil and equal(first, second)
end
function Gossip.IsEvent(kind) return kind == "GOSSIP_VIEWED" or kind == "GOSSIP_OPTION_SELECTED" end
function Gossip.ReferenceKey(value)
    if type(value) ~= "string" then return nil end
    local key, sequence = value:match("^(Player%-%d+%-%x+):([1-9]%d*)$")
    if sequence and (#sequence < 16 or (#sequence == 16 and sequence <= "9007199254740990")) then return key end
end
function Gossip.ValidateEvent(kind, input)
    if kind == "GOSSIP_VIEWED" then
        local snapshot = Gossip.Snapshot(input)
        if snapshot and Gossip.HasContent(snapshot) then return snapshot end
    elseif kind == "GOSSIP_OPTION_SELECTED" and type(input) == "table" then
        local option = entry(input.option, optionFields)
        if not Gossip.ReferenceKey(input.conversationEventID) or not option or not nonblank(option.text)
            or (not option.optionID and option.orderIndex == nil) then return nil, "invalid_gossip" end
        local result = { conversationEventID = input.conversationEventID, option = option }
        if input.npc ~= nil then
            result.npc = Quest.SnapshotNPC(input.npc)
            if not result.npc then return nil, "invalid_gossip" end
        end
        if input.location ~= nil then
            result.location = Quest.SnapshotLocation(input.location)
            if not result.location then return nil, "invalid_gossip" end
        end
        return result
    end
    return nil, "invalid_gossip"
end
function Gossip.Selection(model, reference, option)
    return Gossip.ValidateEvent("GOSSIP_OPTION_SELECTED", { conversationEventID = reference,
        option = option, npc = model.npc, location = model.location })
end
