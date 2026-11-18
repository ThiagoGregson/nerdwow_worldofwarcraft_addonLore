-- Executado pelo harness; não é carregado pelo TOC nem depende de APIs reais.
local sources, toc = ...
assert(_VERSION == "Lua 5.1", "Os testes exigem runtime compatível com Lua 5.1")
local passed = 0
local function test(name, callback)
    local ok, failure = pcall(callback)
    assert(ok, name .. ": " .. tostring(failure))
    passed = passed + 1
end
local function equal(actual, expected)
    assert(actual == expected, "esperado " .. tostring(expected) .. ", obtido " .. tostring(actual))
end
local function loadModule(path, namespace, environment)
    local chunk = assert(loadstring(assert(sources[path], path), "@" .. path))
    setfenv(chunk, environment)
    chunk("NerdWow", namespace)
end
local function core()
    local namespace = {}
    local environment = setmetatable({ type = type, math = math, string = string,
        pairs = pairs, ipairs = ipairs }, {
        __index = function(_, key) error("Global proibida no núcleo: " .. key) end,
    })
    loadModule("Journal/Schema.lua", namespace, environment)
    loadModule("Journal/Journal.lua", namespace, environment)
    loadModule("Configuration/Settings.lua", namespace, environment)
    loadModule("Minimap/Button.lua", namespace, environment)
    return namespace
end
local A, B = "Player-1234-ABCDEF01", "Player-5678-ABCDEF02"
local TIME = 1795000000
local function context(key)
    return { guid = key or A, name = "Exemplo", realm = "Reino",
        raceID = 1, race = "Human", raceName = "Humano", classID = 8,
        class = "MAGE", className = "Mago", level = 80, faction = "Alliance" }
end
local function location(mapID, zone, subZone)
    return { mapID = mapID, zone = zone or "Ventobravo", subZone = subZone or "" }
end
local function serialize(value)
    if type(value) == "string" then return string.format("%q", value) end
    if type(value) ~= "table" then return tostring(value) end
    local fields = {}
    for key, field in pairs(value) do
        fields[#fields + 1] = "[" .. serialize(key) .. "]=" .. serialize(field)
    end
    table.sort(fields)
    return "{" .. table.concat(fields, ",") .. "}"
end
local function roundtrip(value)
    return assert(loadstring("return " .. serialize(value)))()
end
local function event(sequence, kind, key, payload)
    return { id = (key or A) .. ":" .. string.format("%.0f", sequence), sequence = sequence,
        timestamp = TIME, type = kind or "CHARACTER_CONTEXT", characterKey = key or A,
        payload = payload or context(key) }
end
local function rootWith(count)
    local root = { schemaVersion = 1, nextSequence = count + 1, droppedEvents = 0, events = {} }
    for index = 1, count do root.events[index] = event(index) end
    return root
end
local function rejectedUnchanged(namespace, value, expected)
    local before = serialize(value)
    local handle, returned, code = namespace.Journal.Open(value)
    equal(handle, nil)
    equal(returned, value)
    equal(code, expected)
    equal(serialize(value), before)
end

test("primeira abertura e núcleo sem globals do WoW", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    equal(root.schemaVersion, 1)
    equal(root.nextSequence, 1)
    equal(root.droppedEvents, 0)
    equal(journal.GetStatus().totalEvents, 0)
    assert(n.Schema.ValidateRoot(root))
end)

test("envelope e fotografia do contexto", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    local payload = context()
    payload.extra = { ignored = true }
    equal(journal.Append("CHARACTER_CONTEXT", A, TIME, payload), A .. ":1")
    payload.name = "Alterado"
    equal(root.events[1].payload.name, "Exemplo")
    equal(root.events[1].payload.extra, nil)
    equal(root.events[1].timestamp, TIME)
    local status = journal.GetStatus()
    status.totalEvents = 999
    equal(journal.GetStatus().totalEvents, 1)
end)

test("IDs persistem após serialização e relógio regressivo", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    local first = journal.Append("CHARACTER_CONTEXT", A, TIME, context())
    equal(journal.Append("CHARACTER_CONTEXT", A, TIME, context()), A .. ":2")
    local reloaded = roundtrip(root)
    local resumed = assert(core().Journal.Open(reloaded))
    equal(resumed.Append("CHARACTER_CONTEXT", B, TIME - 50, context(B)), B .. ":3")
    equal(reloaded.events[1].id, first)
    equal(resumed.GetStatus().lastTimestamp, TIME - 50)
end)

test("local igual ignora contextos e outros personagens entre sessões", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    assert(journal.Append("LOCATION_CHANGED", A, TIME, location(84)))
    assert(journal.Append("CHARACTER_CONTEXT", A, TIME, context()))
    assert(journal.Append("LOCATION_CHANGED", B, TIME, location(85)))
    local resumed = assert(n.Journal.Open(roundtrip(root)))
    local id, code = resumed.Append("LOCATION_CHANGED", A, TIME + 1, location(84))
    equal(id, nil)
    equal(code, "duplicate_location")
    equal(resumed.GetStatus().totalEvents, 3)
    equal(resumed.Append("LOCATION_CHANGED", A, TIME, location(85)), A .. ":4")
    equal(resumed.Append("LOCATION_CHANGED", A, TIME, location(84)), A .. ":5")
end)

test("igualdade de mapa, zona e subzona; mapa ausente é permitido", function()
    local journal = assert(core().Journal.Open(nil))
    assert(journal.Append("LOCATION_CHANGED", A, TIME, location(nil)))
    local _, code = journal.Append("LOCATION_CHANGED", A, TIME, location(nil))
    equal(code, "duplicate_location")
    assert(journal.Append("LOCATION_CHANGED", A, TIME, location(84)))
    assert(journal.Append("LOCATION_CHANGED", A, TIME, location(84, "Outra")))
    assert(journal.Append("LOCATION_CHANGED", A, TIME, location(84, "Outra", "Interior")))
    equal(journal.GetStatus().totalEvents, 4)
end)

test("entradas inválidas não consomem sequência nem alteram a raiz", function()
    local journal, root = core().Journal.Open(nil)
    local invalid = { { "LOCATION_CHANGED", A, TIME, location(0) },
        { "LOCATION_CHANGED", A, TIME, { zone = "", subZone = "" } },
        { "LOCATION_CHANGED", A, TIME, { zone = "Zona" } },
        { "CHARACTER_CONTEXT", B, TIME, context(A) },
        { "CHARACTER_CONTEXT", "nome-reino", TIME, context() },
        { "CHARACTER_CONTEXT", A, 0, context() },
        { "CHARACTER_CONTEXT", A, 0 / 0, context() },
        { "CHARACTER_CONTEXT", A, math.huge, context() },
        { "CHARACTER_CONTEXT", A, TIME + 0.5, context() } }
    local before = serialize(root)
    for _, input in ipairs(invalid) do
        local id, code = journal.Append(unpack(input))
        equal(id, nil)
        equal(code, "invalid_input")
        equal(serialize(root), before)
    end
    local _, code = journal.Append("QUEST_ACCEPTED", A, TIME, {})
    equal(code, "unsupported_type")
end)

test("contexto obrigatório e facção neutra", function()
    local journal = assert(core().Journal.Open(nil))
    for _, field in ipairs({ "guid", "name", "realm", "raceID", "race", "raceName",
        "classID", "class", "className", "level", "faction" }) do
        local payload = context()
        payload[field] = nil
        local _, code = journal.Append("CHARACTER_CONTEXT", A, TIME, payload)
        equal(code, "invalid_input")
    end
    local payload = context()
    payload.faction = "Neutral"
    assert(journal.Append("CHARACTER_CONTEXT", A, TIME, payload))
end)

test("raiz inválida e esquema futuro preservados", function()
    local n = core()
    rejectedUnchanged(n, false, "invalid_root")
    rejectedUnchanged(n, "danificado", "invalid_root")
    rejectedUnchanged(n, {}, "unsupported_schema")
    local root = rootWith(1)
    root.schemaVersion = 2
    root.future = "preservar"
    rejectedUnchanged(n, root, "unsupported_schema")
end)

test("campos obrigatórios da raiz não são reconstruídos silenciosamente", function()
    local n = core()
    for field, code in pairs({ nextSequence = "invalid_sequence", droppedEvents = "invalid_sequence",
        events = "invalid_events" }) do
        local root = rootWith(1)
        root[field] = nil
        rejectedUnchanged(n, root, code)
    end
end)

test("arrays esparsos e chaves indevidas são preservados e bloqueados", function()
    local n = core()
    local root = rootWith(3)
    root.events[2] = nil
    rejectedUnchanged(n, root, "invalid_events")
    for _, key in ipairs({ 0, -1, 1.5, "metadata" }) do
        root = rootWith(1)
        root.events[key] = event(1)
        rejectedUnchanged(n, root, "invalid_events")
    end
end)

test("corrupção parcial preserva inclusive eventos válidos", function()
    local n = core()
    for _, field in ipairs({ "id", "sequence", "timestamp", "type", "characterKey", "payload" }) do
        local root = rootWith(2)
        root.events[2][field] = false
        rejectedUnchanged(n, root, "invalid_event")
    end
    local root = rootWith(2)
    root.events[2].payload.realm = ""
    rejectedUnchanged(n, root, "invalid_event")
end)

test("contadores inconsistentes e sequências fora de ordem", function()
    local n = core()
    for _, counter in ipairs({ 1, 2, -1, 3.5, math.huge }) do
        local root = rootWith(2)
        root.nextSequence = counter
        rejectedUnchanged(n, root, "invalid_sequence")
    end
    local root = rootWith(2)
    root.events[2] = event(1)
    rejectedUnchanged(n, root, "invalid_sequence")
    root = rootWith(2)
    root.events[1], root.events[2] = root.events[2], root.events[1]
    rejectedUnchanged(n, root, "invalid_sequence")
end)

test("campos e tipos aditivos preservados sem novas escritas desconhecidas", function()
    local n = core()
    local root = rootWith(2)
    root.extension = { preserved = true }
    root.events[1].extra = "preservar"
    root.events[2].type = "FUTURE_EVENT"
    root.events[2].payload = { extra = { value = 1 } }
    local before = serialize(root)
    local journal = assert(n.Journal.Open(root))
    equal(serialize(root), before)
    equal(journal.GetStatus().lastType, "FUTURE_EVENT")
    local _, code = journal.Append("FUTURE_EVENT", A, TIME, {})
    equal(code, "unsupported_type")
end)

test("retenção descarta os mais antigos e preserva IDs e contador", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    for index = 1, n.Schema.MAX_EVENTS + 7 do
        assert(journal.Append("CHARACTER_CONTEXT", A, TIME, context()))
    end
    equal(#root.events, 5000)
    equal(root.events[1].id, A .. ":8")
    equal(root.events[5000].id, A .. ":5007")
    equal(root.nextSequence, 5008)
    equal(root.droppedEvents, 7)
    assert(n.Schema.ValidateRoot(root))
    local resumed = assert(n.Journal.Open(roundtrip(root)))
    equal(resumed.Append("CHARACTER_CONTEXT", A, TIME, context()), A .. ":5008")
end)

test("retenção só ocorre depois da validação completa", function()
    local n = core()
    local root = rootWith(n.Schema.MAX_EVENTS + 2)
    root.events[#root.events].payload.name = ""
    rejectedUnchanged(n, root, "invalid_event")
    root.events[#root.events].payload.name = "Exemplo"
    assert(n.Journal.Open(root))
    equal(#root.events, 5000)
    equal(root.events[1].sequence, 3)
    equal(root.droppedEvents, 2)
end)

test("histórico descartado permite nova base de local", function()
    local n = core()
    local root = rootWith(n.Schema.MAX_EVENTS)
    root.events[1] = event(1, "LOCATION_CHANGED", A, location(84))
    local journal = assert(n.Journal.Open(root))
    assert(journal.Append("CHARACTER_CONTEXT", B, TIME, context(B)))
    assert(journal.Append("LOCATION_CHANGED", A, TIME, location(84)))
end)

test("limite numérico, formato decimal e saturação de descartes", function()
    local n = core()
    local root = rootWith(0)
    root.nextSequence = n.Schema.MAX_SEQUENCE - 1
    local journal = assert(n.Journal.Open(root))
    equal(journal.Append("CHARACTER_CONTEXT", A, TIME, context()), A .. ":9007199254740990")
    local before = serialize(root)
    local _, code = journal.Append("CHARACTER_CONTEXT", A, TIME, context())
    equal(code, "sequence_exhausted")
    equal(serialize(root), before)
    assert(n.Schema.ValidateRoot(root))
    root = rootWith(n.Schema.MAX_EVENTS + 1)
    root.droppedEvents = n.Schema.MAX_SEQUENCE
    assert(n.Journal.Open(root))
    equal(root.droppedEvents, n.Schema.MAX_SEQUENCE)
end)

-- As integrações carregam os arquivos na ordem real do TOC em um ambiente isolado.
local metadata, order = {}, {}
for line in toc:gmatch("[^\r\n]+") do
    local key, value = line:match("^##%s*([^:]+):%s*(.+)$")
    if key then metadata[key] = value
    elseif line:match("%.lua$") then order[#order + 1] = line:gsub("\\", "/") end
end
local function client(saved, settings, absentSettings)
    local state = { guid = A, mapID = 84, zone = "Ventobravo", subZone = "",
        time = TIME, messages = {}, registered = {}, secret = {},
        inCombat = false, reloads = 0, popupRequests = 0,
        cursorX = 400, cursorY = 300, scale = 1, shape = "ROUND", tooltipLines = {} }
    if settings == nil and not absentSettings then
        settings = { schemaVersion = 1, minimapHidden = false, minimapAngle = 225 }
    end
    local env = {
        NerdWow_Journal = saved, NerdWow_Settings = settings, type = type, pairs = pairs, ipairs = ipairs,
        math = math, string = string, pcall = pcall,
        SlashCmdList = {}, date = os.date, StaticPopupDialogs = {},
    }
    env.InCombatLockdown = function() return state.inCombat end
    env.C_UI = { Reload = function() state.reloads = state.reloads + 1 end }
    env.StaticPopup_Show = function(which)
        assert(env.StaticPopupDialogs[which], "Confirmação não registrada")
        state.popupRequests = state.popupRequests + 1
        if state.popupUnavailable then return nil end
        state.popup = { which = which }
        return state.popup
    end
    env.issecretvalue = function(value) return value == state.secret end
    env.UnitName = function(unit) equal(unit, "player"); return "Exemplo", nil end
    env.GetRealmName = function() return "Reino" end
    env.UnitRace = function() return "Humano", "Human", 1 end
    env.UnitClass = function() return "Mago", "MAGE", 8 end
    env.UnitGUID = function() return state.guid end
    env.UnitLevel = function() return 80 end
    env.UnitFactionGroup = function() return "Alliance" end
    env.GetServerTime = function() return state.time end
    env.C_Map = { GetBestMapForUnit = function(unit)
        equal(unit, "player")
        return state.mapID
    end }
    env.GetZoneText = function() return state.zone end
    env.GetSubZoneText = function() return state.subZone end
    env.GetCursorPosition = function() return state.cursorX, state.cursorY end
    env.GetMinimapShape = function() return state.shape end
    env.Minimap = {
        GetFrameLevel = function() return 5 end,
        GetCenter = function() return 400, 300 end,
        GetWidth = function() return state.width or 198 end,
        GetHeight = function() return state.height or 198 end,
        GetEffectiveScale = function() return state.scale end,
        HookScript = function(_, name, callback)
            equal(name, "OnSizeChanged"); state.resize = callback
        end,
    }
    env.GameTooltip = {
        SetOwner = function(_, owner, anchor) state.tooltipOwner = owner; equal(anchor, "ANCHOR_LEFT") end,
        IsOwned = function(_, owner) return state.tooltipOwner == owner end,
        Hide = function() state.tooltipOwner = nil; state.tooltipVisible = false end,
        SetText = function(_, text) state.tooltipLines = { text } end,
        AddLine = function(_, text) state.tooltipLines[#state.tooltipLines + 1] = text end,
        Show = function() state.tooltipVisible = true end,
    }
    local function texture()
        local t = {}
        function t:SetTexture(path) self.path = path end
        function t:SetSize(width, height) self.width, self.height = width, height end
        function t:SetPoint(...) self.point = { ... } end
        function t:SetAllPoints(target) self.allPoints = target end
        function t:ClearAllPoints() self.point = nil end
        function t:SetColorTexture(...) self.color = { ... } end
        function t:AddMaskTexture(mask) self.mask = mask end
        function t:SetTexCoord(...) self.texCoord = { ... } end
        function t:SetVertexColor(...) self.vertexColor = { ... } end
        return t
    end
    env.C_AddOns = { GetAddOnMetadata = function(name, key)
        equal(name, "NerdWow"); return metadata[key]
    end }
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message)
        state.messages[#state.messages + 1] = message
    end }
    env.CreateFrame = function(frameType, name, parent)
        if frameType == "Button" then
            equal(name, nil); equal(parent, env.Minimap)
            local button = { scripts = {}, textures = {}, shown = true }
            function button:SetSize(width, height) self.width, self.height = width, height end
            function button:SetFrameLevel(level) self.level = level end
            function button:RegisterForClicks(value) equal(value, "LeftButtonUp") end
            function button:SetHitRectInsets(...) self.insets = { ... } end
            function button:CreateMaskTexture() self.mask = texture(); return self.mask end
            function button:CreateTexture(_, layer)
                local t = texture(); t.layer = layer; self.textures[#self.textures + 1] = t; return t
            end
            function button:SetHighlightTexture(path, mode)
                self.highlight = texture(); self.highlight.path = path; self.highlight.mode = mode
            end
            function button:GetHighlightTexture() return self.highlight end
            function button:SetPushedTexture(path) self.pushed = texture(); self.pushed.path = path end
            function button:GetPushedTexture() return self.pushed end
            function button:SetPoint(...) self.point = { ... } end
            function button:ClearAllPoints() self.point = nil end
            function button:SetScript(name, callback) self.scripts[name] = callback end
            function button:SetShown(shown)
                local wasShown = self.shown
                self.shown = shown
                if wasShown and not shown and self.scripts.OnHide then self.scripts.OnHide(self) end
            end
            state.button = button
            return button
        end
        equal(frameType, "Frame"); equal(name, nil)
        local frame = {}
        frame.SetScript = function(_, scriptType, callback)
            equal(scriptType, "OnEvent"); state.callback = callback
        end
        frame.RegisterEvent = function(_, name) state.registered[name] = true end
        state.frame = frame
        return frame
    end
    setmetatable(env, { __index = function(_, key)
        if key == "NerdWow_Journal" or key == "NerdWow_Settings" then return nil end
        error("API não simulada: " .. key)
    end })
    local namespace = {}
    for _, path in ipairs(order) do loadModule(path, namespace, env) end
    state.fire = function(name, ...)
        assert(state.registered[name], "Evento não registrado: " .. name)
        state.callback(state.frame, name, ...)
    end
    state.command = function(argument) env.SlashCmdList.NERDWOW(argument or "") end
    state.compartment = function(button)
        env[metadata.AddonCompartmentFunc]("NerdWow", button or "LeftButton")
    end
    state.respond = function(accept)
        local popup = assert(state.popup, "Confirmação não está aberta")
        state.popup = nil
        if accept then env.StaticPopupDialogs[popup.which].OnAccept(popup) end
    end
    state.start = function()
        state.fire("ADDON_LOADED", "NerdWow")
        state.fire("PLAYER_ENTERING_WORLD", true, false)
    end
    state.saved = function() return env.NerdWow_Journal end
    state.settings = function() return env.NerdWow_Settings end
    state.buttonEvent = function(name, ...)
        local callback = state.button.scripts[name]
        if callback then callback(state.button, ...) end
    end
    state.env = env
    state.namespace = namespace
    return state
end

test("metadados e carregamento real do TOC", function()
    equal(metadata.Interface, "120105")
    equal(metadata.Title, "NerdWow")
    equal(metadata.Author, "Greg")
    equal(metadata.Version, "0.3.0")
    equal(metadata.SavedVariables, "NerdWow_Journal, NerdWow_Settings")
    equal(#order, 9)
    for _, path in ipairs(order) do assert(not path:find("Tests/", 1, true)) end
    local c = client()
    equal(c.env.SLASH_NERDWOW1, "/nerdwow")
    equal(c.saved(), nil)
    equal(c.registered.QUEST_DETAIL, nil)
    equal(c.registered.COMBAT_LOG_EVENT_UNFILTERED, nil)
end)

test("SavedVariables só abrem no ADDON_LOADED correto", function()
    local c = client()
    c.fire("ADDON_LOADED", "OutroAddon")
    c.fire("PLAYER_ENTERING_WORLD")
    equal(c.saved(), nil)
    c.command()
    assert(c.messages[1]:find("ainda não inicializado", 1, true))
    c.fire("ADDON_LOADED", "NerdWow")
    equal(#c.saved().events, 0)
    c.fire("ZONE_CHANGED")
    equal(#c.saved().events, 0)
    c.fire("PLAYER_ENTERING_WORLD")
    equal(#c.saved().events, 2)
    c.fire("ADDON_LOADED", "NerdWow")
    equal(#c.saved().events, 2)
end)

test("entrada, status pt-BR e ajuda", function()
    local c = client()
    c.start()
    local events = c.saved().events
    equal(events[1].type, "CHARACTER_CONTEXT")
    equal(events[1].payload.realm, "Reino")
    equal(events[2].type, "LOCATION_CHANGED")
    equal(events[2].timestamp, TIME)
    c.command()
    assert(c.messages[1]:find("v0.3.0 | esquema 1 | 2 eventos", 1, true))
    assert(c.messages[1]:find("mudança de local", 1, true))
    assert(c.messages[1]:find("UTC", 1, true))
    assert(c.messages[2]:find("/reload", 1, true))
    c.command(" AJUDA ")
    equal(#c.messages, 3)
end)

test("reload preserva IDs e não duplica o local", function()
    local first = client()
    first.start()
    local c = client(roundtrip(first.saved()))
    c.start()
    equal(#c.saved().events, 3)
    equal(c.saved().events[1].id, first.saved().events[1].id)
    equal(c.saved().events[3].id, A .. ":3")
    equal(c.saved().events[3].type, "CHARACTER_CONTEXT")
end)

test("zonas, interiores, transição de mundo e retorno", function()
    local c = client()
    c.start()
    for _, name in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
        c.fire(name)
    end
    equal(#c.saved().events, 2)
    c.subZone = "Interior"
    c.fire("ZONE_CHANGED_INDOORS")
    equal(#c.saved().events, 3)
    c.fire("PLAYER_LEAVING_WORLD")
    c.zone = "Outra zona"
    c.mapID = 85
    c.fire("ZONE_CHANGED_NEW_AREA")
    equal(#c.saved().events, 3)
    c.fire("PLAYER_ENTERING_WORLD", false, false)
    equal(#c.saved().events, 5)
    c.zone, c.mapID, c.subZone = "Ventobravo", 84, ""
    c.fire("ZONE_CHANGED_NEW_AREA")
    equal(#c.saved().events, 6)
end)

test("conta compartilhada entre personagens", function()
    local first = client()
    first.start()
    local second = client(roundtrip(first.saved()))
    second.guid = B
    second.start()
    equal(#second.saved().events, 4)
    equal(second.saved().events[3].characterKey, B)
    equal(second.saved().events[3].id, B .. ":3")
    local resumed = client(roundtrip(second.saved()))
    resumed.start()
    equal(#resumed.saved().events, 5)
end)

test("dados corrompidos suspendem a captura com aviso e sem sobrescrever", function()
    local saved = rootWith(2)
    saved.events[2].payload = false
    local before = serialize(saved)
    local c = client(saved)
    c.start()
    c.fire("ZONE_CHANGED")
    c.command()
    equal(c.saved(), saved)
    equal(serialize(saved), before)
    assert(c.messages[1]:find("Gravação suspensa", 1, true))
    assert(c.messages[2]:find("Gravação suspensa", 1, true))
end)

test("valores secretos rejeitados e avisos limitados por sessão", function()
    local c = client()
    c.guid = c.secret
    c.start()
    c.fire("ZONE_CHANGED")
    equal(#c.saved().events, 0)
    equal(#c.messages, 1)
    c.guid = A
    c.fire("ZONE_CHANGED")
    equal(#c.saved().events, 2)
    c.mapID = c.secret
    c.fire("ZONE_CHANGED")
    equal(#c.saved().events, 2)
    equal(#c.messages, 1)
end)

test("mapa nil é preservado como ausente; zona inválida não é inventada", function()
    local c = client()
    c.mapID = nil
    c.start()
    equal(c.saved().events[2].payload.mapID, nil)
    c.zone = ""
    c.fire("ZONE_CHANGED")
    equal(#c.saved().events, 2)
    equal(#c.messages, 1)
    c.zone, c.mapID = "Outra zona", 85
    c.fire("ZONE_CHANGED_NEW_AREA")
    equal(#c.saved().events, 3)
end)

test("falhas de API e horário indisponível não produzem dados fictícios", function()
    local c = client()
    c.time = nil
    c.start()
    equal(#c.saved().events, 0)
    c.time = TIME
    c.env.C_Map.GetBestMapForUnit = function() error("API indisponível") end
    c.fire("ZONE_CHANGED")
    equal(#c.saved().events, 1)
    equal(c.saved().events[1].type, "CHARACTER_CONTEXT")
    equal(#c.messages, 2)
end)

test("status vazio, data não formatável e aviso de retenção", function()
    local c = client(rootWith(0))
    c.fire("ADDON_LOADED", "NerdWow")
    c.command()
    assert(c.messages[1]:find("nenhum, sem horário", 1, true))
    c.fire("PLAYER_ENTERING_WORLD")
    c.env.date = function() error("data fora do intervalo") end
    c.command()
    assert(c.messages[3]:find("indisponível", 1, true))
    local oversized = client(rootWith(5002))
    oversized.fire("ADDON_LOADED", "NerdWow")
    equal(#oversized.saved().events, 5000)
    assert(oversized.messages[1]:find("2 eventos descartados", 1, true))
end)

test("sincronizar pede confirmação pt-BR antes de recarregar", function()
    local c = client()
    c.start()
    local before = serialize(c.saved())
    c.command(" SINCRONIZAR ")
    equal(c.popupRequests, 1)
    equal(c.reloads, 0)
    equal(#c.messages, 0)
    local dialog = c.env.StaticPopupDialogs[c.popup.which]
    equal(dialog.text, c.namespace.Text.syncConfirmation)
    assert(dialog.text:find("interface será recarregada", 1, true))
    assert(dialog.text:find("gravar o diário", 1, true))
    equal(dialog.button1, "Sincronizar")
    equal(dialog.button2, "Cancelar")
    equal(dialog.hideOnEscape, true)
    equal(dialog.timeout, 0)
    c.respond(true)
    equal(c.reloads, 1)
    equal(serialize(c.saved()), before)
end)

test("cancelar sincronização não recarrega nem altera o diário", function()
    local c = client()
    c.start()
    local before = serialize(c.saved())
    c.command("sincronizar")
    c.respond(false)
    equal(c.reloads, 0)
    equal(serialize(c.saved()), before)
end)

test("TOC resolve callback do compartimento para a mesma confirmação", function()
    equal(metadata.AddonCompartmentFunc, "NerdWow_OnAddonCompartmentClick")
    for _, button in ipairs({ "LeftButton", "RightButton" }) do
        local c = client()
        c.start()
        local before = serialize(c.saved())
        equal(type(c.env[metadata.AddonCompartmentFunc]), "function")
        c.compartment(button)
        equal(c.popupRequests, 1)
        equal(c.reloads, 0)
        c.respond(true)
        equal(c.reloads, 1)
        equal(serialize(c.saved()), before)
        local count = 0
        for _ in pairs(c.registered) do count = count + 1 end
        equal(count, 6)
    end
end)

test("combate recusa comando e compartimento sem abrir confirmação", function()
    local c = client()
    c.start()
    local before = serialize(c.saved())
    c.inCombat = true
    c.command("sincronizar")
    c.compartment()
    equal(c.popupRequests, 0)
    equal(c.reloads, 0)
    equal(#c.messages, 2)
    for _, message in ipairs(c.messages) do
        assert(message:find(c.namespace.Text.syncCombat, 1, true))
    end
    equal(serialize(c.saved()), before)
end)

test("combate iniciado durante confirmação impede o reload sem agendamento", function()
    local c = client()
    c.start()
    local before = serialize(c.saved())
    c.compartment()
    c.inCombat = true
    c.respond(true)
    equal(c.reloads, 0)
    assert(c.messages[1]:find(c.namespace.Text.syncCombat, 1, true))
    c.inCombat = false
    equal(c.reloads, 0)
    equal(serialize(c.saved()), before)
    c.command("sincronizar")
    c.respond(true)
    equal(c.reloads, 1)
end)

test("ajuda cita sincronizar e comando não depende de diário válido", function()
    local c = client(false)
    c.start()
    c.command("ajuda")
    assert(c.messages[#c.messages]:find("/nerdwow sincronizar", 1, true))
    c.command("sincronizar")
    equal(c.reloads, 0)
    c.respond(true)
    equal(c.reloads, 1)
    equal(c.saved(), false)
end)

test("confirmação indisponível informa falha sem recarregar", function()
    local c = client()
    c.start()
    c.popupUnavailable = true
    c.command("sincronizar")
    equal(c.reloads, 0)
    equal(c.popup, nil)
    assert(c.messages[1]:find(c.namespace.Text.syncUnavailable, 1, true))
end)

local function near(actual, expected)
    assert(math.abs(actual - expected) < 0.000001,
        "esperado aproximadamente " .. tostring(expected) .. ", obtido " .. tostring(actual))
end
local function tooltipText(c)
    c.buttonEvent("OnEnter")
    return table.concat(c.tooltipLines, "\n")
end

test("configuração ausente ou de tipo errado recebe padrões sem API do jogo", function()
    local settings = core().Settings
    for _, value in ipairs({ false, 7, "inválida" }) do
        local handle, root, repaired = settings.Open(value)
        equal(root.schemaVersion, 1)
        equal(root.minimapHidden, false)
        equal(root.minimapAngle, 225)
        equal(#repaired, 1)
        equal(repaired[1], "root")
        equal(handle.Get().minimapAngle, 225)
    end
    local _, root, repaired = settings.Open(nil)
    equal(root.minimapAngle, 225)
    equal(repaired[1], "root")
end)

test("configuração válida preserva extras e Get devolve uma cópia", function()
    local root = { schemaVersion = 1, minimapHidden = true, minimapAngle = 12.5,
        extension = { keep = true } }
    local before = serialize(root)
    local handle, returned, repaired = core().Settings.Open(root)
    equal(returned, root)
    equal(#repaired, 0)
    equal(serialize(root), before)
    local snapshot = handle.Get()
    snapshot.minimapAngle = 300
    equal(root.minimapAngle, 12.5)
end)

test("recuperação da configuração é restrita ao campo inválido", function()
    for _, field in ipairs({ "schemaVersion", "minimapHidden", "minimapAngle" }) do
        local root = { schemaVersion = 1, minimapHidden = true, minimapAngle = 20, extra = "preservar" }
        root[field] = "inválido"
        local _, returned, repaired = core().Settings.Open(root)
        equal(returned, root)
        equal(#repaired, 1)
        equal(repaired[1], field)
        equal(root.extra, "preservar")
        equal(root.minimapHidden, field ~= "minimapHidden")
        equal(root.minimapAngle, field == "minimapAngle" and 225 or 20)
        equal(root.schemaVersion, 1)
    end
    local root = { schemaVersion = 99, minimapHidden = true, minimapAngle = 20 }
    local _, _, repaired = core().Settings.Open(root)
    equal(repaired[1], "schemaVersion")
    equal(root.minimapHidden, true)
    equal(root.minimapAngle, 20)
end)

test("campos ausentes e todos os limites de ângulo recuperam só o necessário", function()
    for _, angle in ipairs({ -1, 360, math.huge, -math.huge, 0 / 0, false }) do
        local root = { schemaVersion = 1, minimapHidden = true, minimapAngle = angle }
        local _, _, repaired = core().Settings.Open(root)
        equal(root.minimapAngle, 225)
        equal(root.minimapHidden, true)
        equal(#repaired, 1)
    end
    for _, field in ipairs({ "schemaVersion", "minimapHidden", "minimapAngle" }) do
        local root = { schemaVersion = 1, minimapHidden = true, minimapAngle = 0 }
        root[field] = nil
        local _, _, repaired = core().Settings.Open(root)
        equal(#repaired, 1)
        equal(repaired[1], field)
    end
    for _, angle in ipairs({ 0, 359.999 }) do
        local _, root, repaired = core().Settings.Open({ schemaVersion = 1, minimapHidden = false, minimapAngle = angle })
        equal(root.minimapAngle, angle)
        equal(#repaired, 0)
    end
end)

test("mutação da configuração valida entradas e persiste visibilidade e ângulo", function()
    local handle, root = core().Settings.Open(nil)
    for _, value in ipairs({ false, -1, 360, math.huge, 0 / 0 }) do
        local before = serialize(root)
        local ok, code = handle.SetAngle(value)
        equal(ok, nil); equal(code, "invalid_angle")
        equal(serialize(root), before)
    end
    equal(handle.SetAngle(nil), nil)
    assert(handle.SetAngle(90.5))
    equal(handle.ToggleHidden(), true)
    local resumed = core().Settings.Open(roundtrip(root))
    equal(resumed.Get().minimapAngle, 90.5)
    equal(resumed.Get().minimapHidden, true)
    equal(resumed.ToggleHidden(), false)
end)

test("posição circular usa borda e ângulo em todos os quadrantes", function()
    local geometry = core().MinimapButton
    for _, entry in ipairs({ { 0, 108, 0 }, { 90, 0, 108 }, { 180, -108, 0 }, { 270, 0, -108 } }) do
        local x, y = geometry.Position(entry[1], 200, 200, "ROUND")
        near(x, entry[2]); near(y, entry[3])
    end
    for angle = 0, 359 do
        local x, y = geometry.Position(angle, 200, 200, "ROUND")
        near(x * x + y * y, 108 * 108)
    end
end)

test("posição quadrada percorre lados e cantos sem virar um círculo", function()
    local geometry = core().MinimapButton
    for angle = 0, 359 do
        local x, y = geometry.Position(angle, 200, 200, "SQUARE")
        near(math.max(math.abs(x), math.abs(y)), 108)
    end
    local x, y = geometry.Position(45, 200, 200, "SQUARE")
    near(x, 108); near(y, 108)
    x, y = geometry.Position(225, 200, 200, "SQUARE")
    near(x, -108); near(y, -108)
end)

test("ângulo inverte a posição em tamanhos diferentes e formato desconhecido", function()
    local geometry = core().MinimapButton
    for _, shape in ipairs({ "ROUND", "SQUARE" }) do
        for angle = 1, 359 do
            local x, y = geometry.Position(angle, 300, 120, shape)
            near(geometry.Angle(x, y, 300, 120), angle)
        end
    end
    local x, y = geometry.Position(40, 200, 200, "UNKNOWN")
    local expectedX, expectedY = geometry.Position(40, 200, 200, "ROUND")
    near(x, expectedX); near(y, expectedY)
    equal(geometry.Angle(0, 0, 200, 200), nil)
end)

test("gesto diferencia clique, limiar de arrasto, retorno e cancelamento", function()
    local gesture = core().MinimapButton.NewGesture()
    equal(gesture.Release(), nil)
    equal(gesture.Move(20, 20), false)
    gesture.Press(0, 0)
    equal(gesture.Move(3, 0), false)
    equal(gesture.Release(), "click")
    gesture.Press(0, 0)
    equal(gesture.Move(4, 0), true)
    equal(gesture.Move(0, 0), true)
    equal(gesture.Release(), "drag")
    gesture.Press(10, 10)
    gesture.Move(30, 30)
    gesture.Cancel()
    equal(gesture.Release(), nil)
end)

test("botão tem máscara circular, moldura e estados nativos", function()
    local c = client()
    c.start()
    equal(c.button.width, 32); equal(c.button.height, 32)
    equal(c.button.level, 13)
    equal(c.button.mask.path, "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    equal(c.button.textures[2].path, "Interface\\Icons\\INV_Misc_Book_09")
    equal(c.button.textures[2].mask, c.button.mask)
    equal(c.button.textures[3].path, "Interface\\Minimap\\MiniMap-TrackingBorder")
    equal(c.button.highlight.path, "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    equal(c.button.highlight.mode, "ADD")
    equal(c.button.pushed.path, "Interface\\Buttons\\UI-Quickslot-Depress")
    equal(c.button.pushed.mask, c.button.mask)
    equal(c.button.scripts.OnUpdate, nil)
    c.buttonEvent("OnMouseDown", "LeftButton")
    equal(c.button.textures[2].vertexColor[1], 0.65)
    assert(c.button.scripts.OnUpdate)
    c.buttonEvent("OnMouseUp", "LeftButton")
    equal(c.button.textures[2].vertexColor[1], 1)
    equal(c.button.scripts.OnUpdate, nil)
end)

test("clique do botão usa Sincronizar e preserva bloqueio em combate", function()
    local c = client()
    c.start()
    local before = serialize(c.saved())
    c.buttonEvent("OnMouseDown", "LeftButton")
    c.buttonEvent("OnMouseUp", "LeftButton")
    equal(c.popupRequests, 1); equal(c.reloads, 0)
    c.respond(false)
    c.inCombat = true
    c.buttonEvent("OnMouseDown", "LeftButton")
    c.buttonEvent("OnMouseUp", "LeftButton")
    equal(c.popupRequests, 1); equal(c.reloads, 0)
    assert(c.messages[#c.messages]:find(c.namespace.Text.syncCombat, 1, true))
    c.buttonEvent("OnMouseDown", "RightButton")
    c.buttonEvent("OnMouseUp", "RightButton")
    equal(c.popupRequests, 1)
    c.inCombat = false
    c.buttonEvent("OnMouseDown", "LeftButton")
    c.buttonEvent("OnMouseUp", "LeftButton", false)
    equal(c.popupRequests, 1)
    equal(serialize(c.saved()), before)
end)

test("arrastar salva posição, não sincroniza e não modifica o diário", function()
    local c = client()
    c.start()
    local before = serialize(c.saved())
    c.buttonEvent("OnMouseDown", "LeftButton")
    c.cursorX, c.cursorY = 600, 300
    c.buttonEvent("OnUpdate")
    near(c.settings().minimapAngle, 0)
    c.buttonEvent("OnEnter")
    equal(c.tooltipVisible, nil)
    near(c.button.point[4], 107); near(c.button.point[5], 0)
    c.buttonEvent("OnMouseUp", "LeftButton")
    equal(c.popupRequests, 0)
    equal(c.button.scripts.OnUpdate, nil)
    equal(serialize(c.saved()), before)
    -- O clique seguinte continua funcionando depois do arrasto.
    c.buttonEvent("OnMouseDown", "LeftButton")
    c.buttonEvent("OnMouseUp", "LeftButton")
    equal(c.popupRequests, 1)
end)

test("arrastar respeita escala e borda quadrada; resize reposiciona", function()
    local c = client()
    c.scale = 2
    c.shape = "SQUARE"
    c.cursorX, c.cursorY = 800, 600
    c.start()
    c.buttonEvent("OnMouseDown", "LeftButton")
    c.cursorX, c.cursorY = 1000, 800
    c.buttonEvent("OnUpdate")
    near(c.settings().minimapAngle, 45)
    near(c.button.point[4], 107); near(c.button.point[5], 107)
    c.buttonEvent("OnMouseUp", "LeftButton")
    c.width, c.height = 300, 100
    c.resize()
    near(c.button.point[4], 158); near(c.button.point[5], 58)
    equal(c.popupRequests, 0)
end)

test("ausência de GetMinimapShape usa borda redonda", function()
    local c = client(nil, { schemaVersion = 1, minimapHidden = false, minimapAngle = 45 })
    c.env.GetMinimapShape = false
    c.start()
    near(c.button.point[4], 107 / math.sqrt(2))
    near(c.button.point[5], 107 / math.sqrt(2))
end)

test("botao alterna visibilidade salva e restaura posição no próximo carregamento", function()
    local c = client()
    c.command("botao")
    assert(c.messages[1]:find(c.namespace.Text.buttonNotReady, 1, true))
    c.start()
    local before = serialize(c.saved())
    c.command(" BOTAO ")
    equal(c.button.shown, false); equal(c.settings().minimapHidden, true)
    local nextClient = client(roundtrip(c.saved()), roundtrip(c.settings()))
    nextClient.start()
    equal(nextClient.button.shown, false)
    near(nextClient.button.point[4], c.button.point[4])
    near(nextClient.button.point[5], c.button.point[5])
    nextClient.command("botao")
    equal(nextClient.button.shown, true)
    equal(nextClient.settings().minimapHidden, false)
    c.command("ajuda")
    assert(c.messages[#c.messages]:find("/nerdwow botao", 1, true))
    equal(serialize(c.saved()), before)
end)

test("ocultar cancela arrasto, remove atualização e fecha apenas sua dica", function()
    local c = client()
    c.start()
    c.buttonEvent("OnEnter")
    equal(c.tooltipVisible, true)
    c.buttonEvent("OnMouseDown", "LeftButton")
    c.command("botao")
    equal(c.tooltipVisible, false)
    equal(c.button.scripts.OnUpdate, nil)
    c.command("botao")
    c.buttonEvent("OnMouseUp", "LeftButton")
    equal(c.popupRequests, 0)
    c.tooltipOwner, c.tooltipVisible = {}, true
    c.command("botao")
    equal(c.tooltipVisible, true)
end)

test("dica mostra versão, totais, pendentes, UTC e instruções em pt-BR", function()
    local c = client()
    c.start()
    local text = tooltipText(c)
    for _, expected in ipairs({ "NerdWow v0.3.0", "Eventos no diário: 2",
        "Novos desta sessão aguardando gravação: 2", "Último evento:", "UTC",
        "Clique esquerdo: sincronizar", "Arraste com o botão esquerdo" }) do
        assert(text:find(expected, 1, true), expected)
    end
    c.subZone = "Interior"
    c.fire("ZONE_CHANGED_INDOORS")
    assert(table.concat(c.tooltipLines, "\n"):find("Eventos no diário: 3", 1, true))
    assert(table.concat(c.tooltipLines, "\n"):find("aguardando gravação: 3", 1, true))
end)

test("dica de diário bloqueado mostra causa sem inventar contagens", function()
    local c = client(false)
    c.start()
    local text = tooltipText(c)
    assert(text:find("Gravação suspensa", 1, true))
    assert(text:find("raiz do diário ausente ou inválida", 1, true))
    assert(not text:find("Eventos no diário:", 1, true))
    assert(not text:find("aguardando gravação:", 1, true))
    assert(text:find("Clique esquerdo", 1, true))
end)

test("pendentes ignoram falhas e duplicatas e não zeram ao aceitar confirmação", function()
    local c = client()
    c.start()
    c.fire("ZONE_CHANGED")
    c.zone = ""
    c.fire("ZONE_CHANGED")
    assert(tooltipText(c):find("aguardando gravação: 2", 1, true))
    c.command("sincronizar")
    c.respond(true)
    assert(tooltipText(c):find("aguardando gravação: 2", 1, true))
    local resumed = client(roundtrip(c.saved()), roundtrip(c.settings()))
    resumed.start()
    local text = tooltipText(resumed)
    assert(text:find("Eventos no diário: 3", 1, true))
    assert(text:find("aguardando gravação: 1", 1, true))
end)

test("pendentes representam apenas os eventos novos ainda retidos", function()
    local c = client(rootWith(4999))
    c.start()
    assert(tooltipText(c):find("Eventos no diário: 5000", 1, true))
    assert(tooltipText(c):find("aguardando gravação: 2", 1, true))
    for index = 1, 5001 do
        c.subZone = tostring(index)
        c.fire("ZONE_CHANGED")
    end
    assert(tooltipText(c):find("aguardando gravação: 5000", 1, true))
    equal(c.saved().schemaVersion, 1)
end)

test("configuração inválida avisa e preserva diário e valores válidos", function()
    local root = { schemaVersion = 1, minimapHidden = true, minimapAngle = -1, extra = "guardar" }
    local saved = rootWith(3)
    local before = serialize(saved)
    local c = client(saved, root)
    c.fire("ADDON_LOADED", "NerdWow")
    equal(c.settings(), root)
    equal(root.minimapHidden, true)
    equal(root.minimapAngle, 225)
    equal(root.extra, "guardar")
    equal(#c.messages, 1)
    assert(c.messages[1]:find("posição do botão", 1, true))
    equal(serialize(saved), before)
    equal(c.button.shown, false)
    local first = client(nil, nil, true)
    first.fire("ADDON_LOADED", "NerdWow")
    equal(first.settings().schemaVersion, 1)
    equal(#first.messages, 1)
    assert(first.messages[1]:find("raiz", 1, true))
end)

return string.format("%d cenários aprovados; runtime: %s / %s. Integração real no Retail pendente.",
    passed, _VERSION, jit and jit.version or "sem JIT")
