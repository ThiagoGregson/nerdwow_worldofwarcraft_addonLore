local addonName, addon = ...
local Wow, Text = addon.Wow, addon.Text
local journal, blockedCode, currentCharacterKey
local settings, minimap
local pendingEvents = 0
local inWorld = false
local initialized = false
local warnings = {}

local function reason(code)
    return Text.errors[code] or code
end

local function warn(code)
    if code == "duplicate_location" or warnings[code] then
        return
    end
    warnings[code] = true
    Wow.Print(string.format(Text.captureFailed, reason(code)))
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

Wow.Listen(function(event, loadedName)
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
