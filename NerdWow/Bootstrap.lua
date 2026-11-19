local addonName, addon = ...
local Wow, Text = addon.Wow, addon.Text
local journal, blockedCode, currentCharacterKey
local settings, minimap
local pendingEvents = 0
local inWorld = false
local initialized = false
local interfaceInWorld = false
local warnings = {}
local questDialogs = addon.QuestSession.New()
addon.QuestDialogs = questDialogs
local gossipDialogs = addon.GossipSession.New()
addon.GossipDialogs = gossipDialogs

local function reason(code)
    return Text.errors[code] or code
end

local function warn(code)
    if code == "duplicate_location" or code == "duplicate_quest" or code == "duplicate_gossip" or code == "uncorrelated_gossip" or warnings[code] then
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

local function appendDialogue(kind, model)
    if not journal or not inWorld then return end
    if not currentCharacterKey then captureContext() end
    if currentCharacterKey then return append(kind, currentCharacterKey, model) end
end

local captures = {
    addon.QuestCapture.New({ Session = questDialogs, API = addon.QuestAPI,
        Append = appendDialogue, Warn = warn, Issue = questIssue }),
    addon.GossipCapture.New({ Session = gossipDialogs, API = addon.GossipAPI,
        Append = appendDialogue, Warn = warn,
        Issue = function(code)
            if code and not warnings["gossip_" .. code] then
                warnings["gossip_" .. code] = true
                Wow.Print(string.format(Text.gossipPartial, reason(code)))
            end
        end,
        FindConversation = function(model)
            if journal and inWorld and currentCharacterKey then
                return journal.FindConversation(currentCharacterKey, model)
            end
        end }),
}
local dialogueEvents = {}
for _, module in ipairs({ addon.QuestCapture, addon.GossipCapture }) do
    for _, event in ipairs(module.Events) do dialogueEvents[#dialogueEvents + 1] = event end
end
dialogueEvents[#dialogueEvents + 1] = "PLAYER_REGEN_DISABLED"
local cinema = addon.ConversationController.New({ GetModel = gossipDialogs.GetCurrent,
    IsEnabled = function() return interfaceInWorld and settings and settings.Get().dialogEnabled end,
    Platform = addon.ConversationPlatform, View = addon.ConversationView,
    Report = function(code) Wow.Print(string.format(Text.cinemaFailure,reason(code))) end })

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
    if argument == "dialogo" then
        if not settings then Wow.Print(Text.dialogNotReady); return end
        local enabled = settings.ToggleDialog()
        cinema.Toggle()
        Wow.Print(enabled and Text.dialogEnabled or Text.dialogDisabled)
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
    if initialized then
        if event == "PLAYER_ENTERING_WORLD" then interfaceInWorld = true
        elseif event == "PLAYER_LEAVING_WORLD" then interfaceInWorld = false end
        local handled = false
        for _, capture in ipairs(captures) do
            handled = capture.Handle(event, loadedName, experience, money) or handled
        end
        handled = cinema.Handle(event) or handled
        if handled then return end
    end
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
end, dialogueEvents)
