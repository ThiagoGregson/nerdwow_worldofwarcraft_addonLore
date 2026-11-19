local addonName, addon = ...
local Wow, Text = addon.Wow, addon.Text
local journal, blockedCode, currentCharacterKey
local settings, minimap
local pendingEvents = 0
local inWorld = false
local initialized = false
local warnings = {}
local questDialogs = addon.QuestSession.New()
addon.QuestDialogs = questDialogs
local questMoments = { QUEST_DETAIL = "OFFER", QUEST_PROGRESS = "PROGRESS", QUEST_COMPLETE = "COMPLETE" }

local function reason(code)
    return Text.errors[code] or code
end

local function warn(code)
    if code == "duplicate_location" or code == "duplicate_quest" or warnings[code] then
        return
    end
    warnings[code] = true
    Wow.Print(string.format(Text.captureFailed, reason(code)))
end

local function questIssue(code)
    if code and not warnings["quest_" .. code] then
        warnings["quest_" .. code] = true
        Wow.Print(string.format(Text.questPartial, reason(code)))
    end
end

local _, selectionCode = addon.QuestAPI.ObserveSelection(questDialogs.SelectReward)
questIssue(selectionCode)

local function append(kind, key, payload)
    local timestamp, code = Wow.ServerTime()
    if timestamp == nil then
        warn(code)
        return
    end
    local id, failure = journal.Append(kind, key, timestamp, payload)
    if not id then
        warn(failure)
    else
        pendingEvents = math.min(pendingEvents + 1, addon.Schema.MAX_EVENTS)
        if minimap then minimap.RefreshTooltip() end
    end
    return id
end

local function captureContext()
    local payload, code = Wow.ReadCharacter()
    if not payload then
        warn(code)
        return
    end
    if append("CHARACTER_CONTEXT", payload.guid, payload) then
        currentCharacterKey = payload.guid
    end
end

local function captureLocation()
    if not currentCharacterKey then
        captureContext()
    end
    if not currentCharacterKey then
        return
    end
    local payload, code = Wow.ReadLocation()
    if not payload then
        warn(code)
        return
    end
    append("LOCATION_CHANGED", currentCharacterKey, payload)
end

local function captureQuest(event, questID, experience, money)
    if event == "QUEST_FINISHED" then questDialogs.Close(); return true end
    local moment = questMoments[event]
    local expectedID
    if event == "QUEST_ITEM_UPDATE" then
        local current = questDialogs.GetCurrent()
        if not current then return true end
        moment = current.moment
        expectedID = current.quest.id
    end
    local kind, model, code
    if moment then
        local raw
        raw, code = addon.QuestAPI.Read(moment)
        questIssue(code)
        if raw and expectedID and raw.quest.id ~= expectedID then return true end
        if raw then model, code = questDialogs.Observe(raw) end
        if not model then questDialogs.Close(); warn(code or "api_unavailable"); return true end
        kind = moment == "OFFER" and "QUEST_OFFERED" or moment == "PROGRESS" and "QUEST_PROGRESS_VIEWED"
    elseif event == "QUEST_ACCEPTED" or event == "QUEST_TURNED_IN" then
        local info
        info, code = addon.QuestAPI.EventInfo(questID, experience, money)
        questIssue(code)
        if not info then warn(code or "api_unavailable"); return true end
        kind = event == "QUEST_ACCEPTED" and "QUEST_ACCEPTED" or "QUEST_COMPLETED"
        local fallback
        fallback, code = addon.QuestAPI.ReadLog(info.questID, addon.QuestDialogue.Moment(kind))
        questIssue(code)
        model, code = questDialogs.ForEvent(kind, info.questID, fallback,
            addon.QuestAPI.Location(), info.money, info.experience)
        if not model then warn(code or "invalid_dialogue"); return true end
    else
        return false
    end
    if kind and journal and inWorld then
        if not currentCharacterKey then captureContext() end
        if currentCharacterKey then append(kind, currentCharacterKey, model) end
    end
    return true
end

local function tooltip()
    local view = { version = Wow.Version() }
    if journal then
        local status = journal.GetStatus()
        view.totalEvents = status.totalEvents
        view.pendingEvents = math.min(pendingEvents, status.totalEvents)
        view.lastTime = status.lastTimestamp and Wow.FormatTime(status.lastTimestamp) or Text.noTime
    else
        view.blockedReason = reason(blockedCode or "not_initialized")
    end
    return addon.MinimapButton.Tooltip(view, Text)
end

Wow.RegisterCommand(function(message)
    local argument = (message or ""):match("^%s*(.-)%s*$"):lower()
    if argument == "sincronizar" then
        Wow.RequestSync()
        return
    end
    if argument == "botao" then
        if not settings then
            Wow.Print(Text.buttonNotReady)
            return
        end
        local hidden = settings.ToggleHidden()
        minimap.Refresh()
        Wow.Print(hidden and Text.buttonHidden or Text.buttonShown)
        return
    end
    if argument ~= "ajuda" and argument ~= "?" then
        if journal then
            local status = journal.GetStatus()
            local kind = status.lastType
            Wow.Print(string.format(Text.status, Wow.Version(), status.schemaVersion,
                status.totalEvents, Text.eventTypes[kind] or kind or Text.noEvent,
                status.lastTimestamp and Wow.FormatTime(status.lastTimestamp) or Text.noTime))
        else
            Wow.Print(string.format(Text.blocked, reason(blockedCode or "not_initialized")))
        end
    end
    Wow.Print(Text.help)
end)

Wow.Listen(function(event, loadedName, experience, money)
    if event == "ADDON_LOADED" then
        if loadedName ~= addonName or initialized then
            return
        end
        initialized = true
        local settingsRoot, repaired
        settings, settingsRoot, repaired = addon.Settings.Open(addon.database.ReadSettings())
        addon.database.BindSettings(settingsRoot)
        for _, field in ipairs(repaired) do
            Wow.Print(string.format(Text.settingsRecovered, Text.settingsFields[field]))
        end
        local saved = addon.database.Read()
        local root
        local droppedBefore = type(saved) == "table" and saved.droppedEvents or 0
        journal, root, blockedCode = addon.Journal.Open(saved)
        if journal then
            addon.database.Bind(root)
            local status = journal.GetStatus()
            if status.droppedEvents > droppedBefore then
                Wow.Print(string.format(Text.retention, status.droppedEvents, addon.Schema.MAX_EVENTS))
            end
        else
            Wow.Print(string.format(Text.blocked, reason(blockedCode)))
        end
        minimap = addon.MinimapUI.Create({ GetSettings = settings.Get, SetAngle = settings.SetAngle,
            GetTooltip = tooltip, OnClick = Wow.RequestSync })
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then questDialogs.Reset() end
    if initialized and captureQuest(event, loadedName, experience, money) then return end
    if not journal then
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then
        inWorld, currentCharacterKey = false, nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        inWorld, currentCharacterKey = true, nil
        captureContext()
        if currentCharacterKey then
            captureLocation()
        end
    elseif inWorld then
        captureLocation()
    end
end)
