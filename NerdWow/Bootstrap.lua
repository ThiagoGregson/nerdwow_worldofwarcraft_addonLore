local addonName, addon = ...
local Wow, Text = addon.Wow, addon.Text
local journal, blockedCode, currentCharacterKey
local diagnostics, diagnosticCode, currentGameEvent
local settings, minimap
local pendingEvents = 0
local inWorld = false
local initialized = false
local interfaceInWorld = false
local cinema,questReceipt
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
local captureTypes={ GOSSIP_SHOW="GOSSIP_VIEWED", GOSSIP_OPTIONS_REFRESHED="GOSSIP_VIEWED", QUEST_GREETING="GOSSIP_VIEWED",
    QUEST_DETAIL="QUEST_OFFERED", QUEST_PROGRESS="QUEST_PROGRESS_VIEWED", QUEST_ACCEPTED="QUEST_ACCEPTED",
    QUEST_TURNED_IN="QUEST_COMPLETED" }
local function rejected(code,kind,field,detail,payload,stage)
    if code=="duplicate_location" or code=="duplicate_quest" or code=="duplicate_gossip" then return end
    detail=detail or addon.DiagnosticAPI.Capture(code)
    addon.DiagnosticAPI.Record("capture",code,detail,{gameEvent=currentGameEvent,
        captureType=kind or captureTypes[currentGameEvent],field=field,stage=stage or "append"},payload)
end
local function captureWarning(code,context)
    context=context or {}
    rejected(code,context.captureType,context.field,context.detail,context.model,"capture_read")
    warn(code)
end

local function append(kind, key, payload)
    local timestamp, code, field, detail = Wow.ServerTime()
    if timestamp == nil then
        rejected(code,kind,field,detail,payload,"timestamp")
        warn(code)
        return
    end
    local ok, id, failure, path = addon.DiagnosticAPI.Try(journal.Append,kind,key,timestamp,payload)
    if not ok then
        rejected("capture_error",kind,nil,id,payload)
        warn("capture_error")
        return
    end
    if not id then
        rejected(failure,kind,path,nil,payload)
        warn(failure)
    else
        pendingEvents = math.min(pendingEvents + 1, addon.Schema.MAX_EVENTS)
        if minimap then minimap.RefreshTooltip() end
    end
    return id,failure
end

local function captureContext()
    local payload, code, field, detail = Wow.ReadCharacter()
    if not payload then
        rejected(code,"CHARACTER_CONTEXT",field,detail,nil,"character_read")
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
    local payload, code, field, detail = Wow.ReadLocation()
    if not payload then
        -- A zona ainda não existe durante algumas transições; a próxima
        -- notificação de local repete a leitura sem inventar uma localização.
        if code=="api_unavailable" and field=="payload.zone" then return end
        rejected(code,"LOCATION_CHANGED",field,detail,nil,"location_read")
        warn(code)
        return
    end
    append("LOCATION_CHANGED", currentCharacterKey, payload)
end

local function appendDialogue(kind, model)
    if not journal or not inWorld then return end
    if not currentCharacterKey then captureContext() end
    if currentCharacterKey then
        local id,code=append(kind,currentCharacterKey,model)
        if model.quest and (id or code=="duplicate_quest") then
            questReceipt={questID=model.quest.id,kind=kind}
            if cinema then cinema.Recorded(kind,model.quest.id) end
        end
        return id
    end
end

local captures = {
    addon.QuestCapture.New({ Session = questDialogs, API = addon.QuestAPI,
        Append = appendDialogue, Warn = captureWarning, Issue = questIssue }),
    addon.GossipCapture.New({ Session = gossipDialogs, API = addon.GossipAPI,
        Append = appendDialogue, Warn = captureWarning,
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
dialogueEvents[#dialogueEvents + 1] = "QUEST_LOG_UPDATE"
cinema = addon.ConversationController.New({ GetModel = function() return questDialogs.GetCurrent() or gossipDialogs.GetCurrent() end,
    Prepare=function(model)
        if model.quest then return addon.QuestPresentation.Build(model,addon.QuestPlatform.ReadState(model),questReceipt) end
        return addon.Conversation.Build(model)
    end,
    IsEnabled = function() return interfaceInWorld and settings and settings.Get().dialogEnabled end,
    Platform = addon.ConversationPlatform, View = addon.ConversationView,
    Try = addon.DiagnosticAPI.Try,
    Diagnose = function(fault,context,model)
        addon.DiagnosticAPI.Record("interface",addon.DiagnosticAPI.Code(fault),fault,context,model)
    end,
    Report = function(fault) Wow.Print(string.format(Text.cinemaFailure,reason(addon.DiagnosticAPI.Code(fault)))) end })

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
    if argument == "fontes" then
        if not initialized then Wow.Print(Text.fontsNotReady); return end
        local ok,fault=addon.DiagnosticAPI.Try(addon.FontAPI.Test,Wow.Print)
        if not ok then
            addon.DiagnosticAPI.Record("interface","font_test_failed",fault,{gameEvent="COMMAND_FONTES",stage="font_probe"})
            Wow.Print(Text.fontsFailed)
        end
        if not diagnostics then Wow.Print(string.format(Text.diagnosticsBlocked,reason(diagnosticCode))) end
        return
    end
    if argument == "diagnostico" then
        if not diagnostics then Wow.Print(string.format(Text.diagnosticsBlocked,reason(diagnosticCode or "not_initialized"))); return end
        local recent=diagnostics.Recent(5)
        Wow.Print(string.format(Text.diagnosticsHeader,diagnostics.GetStatus().total))
        if #recent==0 then Wow.Print(Text.diagnosticsEmpty) end
        for _, entry in ipairs(recent) do
            local context=entry.context
            local function value(v) return addon.DiagnosticAPI.ChatText(v or Text.unavailable) end
            local description=addon.DiagnosticAPI.ChatText(entry.message or Text.diagnosticsRedacted)
            Wow.Print(string.format(Text.diagnosticsLine,entry.lastTimestamp and Wow.FormatTime(entry.lastTimestamp) or Text.noTime,
                value(entry.code),entry.count,value(context.gameEvent),value(context.captureType or context.moment),
                value(context.field or context.stage),context.creatureID and tostring(context.creatureID) or "?",
                value(entry.version),description))
        end
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
    currentGameEvent=event
    if event == "ADDON_LOADED" then
        if loadedName ~= addonName or initialized then
            return
        end
        initialized = true
        local diagnosticRoot
        diagnostics,diagnosticRoot,diagnosticCode=addon.Diagnostics.Open(addon.database.ReadDiagnostics())
        if diagnostics then
            addon.database.BindDiagnostics(diagnosticRoot)
            addon.DiagnosticAPI.Bind(diagnostics.Append)
        end
        local fontsOK,fontsFault=addon.DiagnosticAPI.Try(function()
            addon.FontAPI.Preload()
            local viewport=addon.DiagnosticAPI.Dimensions(UIParent)
            addon.QuestView.Preload(viewport.viewportWidth,viewport.viewportHeight)
        end)
        if not fontsOK then
            addon.DiagnosticAPI.Record("interface","font_preload_failed",fontsFault,{stage="font_preload"})
        end
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
            rejected(blockedCode,nil,"journal",nil,nil,"open")
            Wow.Print(string.format(Text.blocked, reason(blockedCode)))
        end
        minimap = addon.MinimapUI.Create({ GetSettings = settings.Get, SetAngle = settings.SetAngle,
            GetTooltip = tooltip, OnClick = Wow.RequestSync })
        return
    end
    if initialized then
        if event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE" or event=="QUEST_ITEM_UPDATE"
            or event=="PLAYER_LEAVING_WORLD" then questReceipt=nil end
        if event == "PLAYER_ENTERING_WORLD" then interfaceInWorld = true
        elseif event == "PLAYER_LEAVING_WORLD" then interfaceInWorld = false end
        local handled = false
        for _, capture in ipairs(captures) do
            handled = capture.Handle(event, loadedName, experience, money) or handled
        end
        handled = cinema.Handle(event,loadedName) or handled
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
