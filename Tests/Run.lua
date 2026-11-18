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
local function client(saved)
    local state = { guid = A, mapID = 84, zone = "Ventobravo", subZone = "",
        time = TIME, messages = {}, registered = {}, secret = {} }
    local env = {
        NerdWow_Journal = saved, type = type, pairs = pairs, ipairs = ipairs,
        math = math, string = string, pcall = pcall,
        SlashCmdList = {}, date = os.date,
    }
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
    env.C_AddOns = { GetAddOnMetadata = function(name, key)
        equal(name, "NerdWow"); return metadata[key]
    end }
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, message)
        state.messages[#state.messages + 1] = message
    end }
    env.CreateFrame = function(frameType, name)
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
        if key == "NerdWow_Journal" then return nil end
        error("API não simulada: " .. key)
    end })
    local namespace = {}
    for _, path in ipairs(order) do loadModule(path, namespace, env) end
    state.fire = function(name, ...)
        assert(state.registered[name], "Evento não registrado: " .. name)
        state.callback(state.frame, name, ...)
    end
    state.command = function(argument) env.SlashCmdList.NERDWOW(argument or "") end
    state.start = function()
        state.fire("ADDON_LOADED", "NerdWow")
        state.fire("PLAYER_ENTERING_WORLD", true, false)
    end
    state.saved = function() return env.NerdWow_Journal end
    state.env = env
    state.namespace = namespace
    return state
end

test("metadados e carregamento real do TOC", function()
    equal(metadata.Interface, "120100")
    equal(metadata.Title, "NerdWow")
    equal(metadata.Author, "Greg")
    equal(metadata.Version, "0.1.0")
    equal(metadata.SavedVariables, "NerdWow_Journal")
    equal(#order, 6)
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
    assert(c.messages[1]:find("v0.1.0 | esquema 1 | 2 eventos", 1, true))
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

return string.format("%d cenários aprovados; runtime: %s / %s. Integração real no Retail pendente.",
    passed, _VERSION, jit and jit.version or "sem JIT")
