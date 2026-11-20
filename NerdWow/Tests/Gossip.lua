-- Testes de conversa por contratos públicos e pelo carregamento real do TOC.
local t = ...
local test, equal, core, client = t.test, t.equal, t.core, t.client
local serialize, roundtrip, A, B, TIME = t.serialize, t.roundtrip, t.A, t.B, t.TIME
local function model(moment)
    return { moment = moment or "GOSSIP", text = "Uma história\n$N: 你好.",
        options = { { index = 1, optionID = 7001, orderIndex = 0, text = "Conte-me.", icon = 134400, status = 0, flags = 0 } },
        availableQuests = { { index = 1, questID = 101, title = "Os nomes nas margens", isImportant = true, questInfoID = 0 } },
        activeQuests = { { index = 1, questID = 202, title = "O arquivo", isComplete = false, isRepeatable = true } },
        npc = { guid = "Creature-0-1-0-84-777-ABC", creatureID = 777, name = "Arquivista", title = "Guardiã", faction = "Alliance" },
        location = { mapID = 84, zone = "Ventobravo", subZone = "" } }
end
local function last(c) return c.saved().events[#c.saved().events] end
local function show(c)
    c.fire("GOSSIP_SHOW"); c.flush()
    return last(c)
end
local function open()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    return n, journal, root
end
local function bind(n, source)
    local session = n.GossipSession.New()
    local _, token = session.Observe(source)
    session.Bind(A .. ":10"); session.Arm(token)
    return session
end

test("conversa modela GOSSIP e GREETING sem preencher campos indisponíveis", function()
    local g = core().GossipDialogue
    for _, moment in ipairs({ "GOSSIP", "GREETING" }) do
        local snapshot = assert(g.Snapshot({ moment = moment }))
        equal(snapshot.moment, moment); equal(snapshot.text, nil); equal(snapshot.options, nil)
        equal(snapshot.npc, nil); equal(snapshot.location, nil); equal(g.HasContent(snapshot), false)
    end
    equal(g.Snapshot({ moment = "OFFER" }), nil)
    local source = model()
    source.extra = true; source.options[1].extra = true
    local copy = assert(g.Snapshot(source))
    source.text = "alterado"; source.options[1].text = "alterado"
    equal(copy.text, "Uma história\n$N: 你好."); equal(copy.options[1].text, "Conte-me.")
    equal(copy.extra, nil); equal(copy.options[1].extra, nil)
    equal(g.Snapshot(roundtrip(copy)).activeQuests[1].isComplete, false)
end)

test("conversa valida arrays densos índices tipos números e limites", function()
    local g = core().GossipDialogue
    for _, field in ipairs({ "options", "availableQuests", "activeQuests" }) do
        local source = model(); source[field] = { [2] = { index = 2 } }; equal(g.Snapshot(source), nil)
        source[field] = { { index = 1 }, { index = 1 } }; equal(g.Snapshot(source), nil)
        source[field] = { { index = 1.5 } }; equal(g.Snapshot(source), nil)
        source[field] = { [257] = { index = 257 } }; equal(g.Snapshot(source), nil)
    end
    for _, value in ipairs({ -1, 0.5, math.huge, 0/0, "0" }) do
        local source = model(); source.options[1].orderIndex = value
        equal(g.Snapshot(source), nil)
    end
    local source = model(); source.activeQuests[1].isComplete = 0; equal(g.Snapshot(source), nil)
    source = model(); source.options[1].status = 4; equal(g.Snapshot(source), nil)
    source = model(); source.npc.creatureID = "777"; equal(g.Snapshot(source), nil)
    source = model(); source.location.mapID = -1; equal(g.Snapshot(source), nil)
end)

test("adaptador gossip preserva opções ícones marcas NPC e dados seguros", function()
    local c = client(); c.start()
    local o = c.gossip.options[1]
    o.overrideIconID, o.spellID = 134401, 123
    c.gossip.available[1].repeatable = true
    local raw, code = c.namespace.GossipAPI.Read("GOSSIP")
    equal(code, nil); equal(raw.options[1].optionID, 7001); equal(raw.options[1].orderIndex, 0)
    equal(raw.options[1].overrideIconID, 134401); equal(raw.options[1].spellID, 123)
    equal(raw.availableQuests[1].isRepeatable, true); equal(raw.availableQuests[1].isImportant, true)
    equal(raw.availableQuests[1].questInfoID, 0); equal(raw.activeQuests[1].isComplete, false)
    equal(raw.npc.creatureID, 777); equal(raw.npc.title, "Guardiã dos registros")
    equal(raw.npc.faction, "Alliance"); equal(raw.location.mapID, 84)
    assert(c.namespace.GossipDialogue.Snapshot(raw))
end)

test("saudação usa APIs de missões incluindo oito retornos e conclusão explícita", function()
    local c = client(); c.start()
    local q = c.gossip.available[1]
    q.isTrivial, q.frequency, q.repeatable, q.isLegendary, q.isMeta = false, 2, true, false, true
    c.gossip.active[1].isComplete = true
    c.fire("QUEST_GREETING")
    local event = last(c)
    equal(event.type, "GOSSIP_VIEWED"); equal(event.payload.moment, "GREETING")
    equal(event.payload.options, nil); equal(event.payload.availableQuests[1].questID, 101)
    equal(event.payload.availableQuests[1].questInfoID, 0); equal(event.payload.availableQuests[1].isMeta, true)
    equal(event.payload.availableQuests[1].isTrivial, false); equal(event.payload.availableQuests[1].frequency, 2)
    equal(event.payload.activeQuests[1].isComplete, true); equal(event.payload.activeQuests[1].isTrivial, true)
    c.gossip.active[1].isComplete = nil
    c.fire("QUEST_GREETING"); equal(last(c).payload.activeQuests[1].isComplete, nil)
end)

test("barreira omite secretos simples aninhados e preserva campos independentes", function()
    local c = client(); c.start()
    c.gossip.text, c.gossip.options[1].name = c.secret, c.secret
    c.gossip.options[1].icon, c.gossip.available[1].title = c.secret, c.secret
    c.gossip.active[1].isComplete, c.npc.subtitle = c.secret, c.secret
    local raw, code = c.namespace.GossipAPI.Read("GOSSIP")
    equal(code, "secret_value"); equal(raw.text, nil); equal(raw.options[1].text, nil)
    equal(raw.options[1].icon, nil); equal(raw.options[1].optionID, 7001)
    equal(raw.availableQuests[1].title, nil); equal(raw.availableQuests[1].questID, 101)
    equal(raw.activeQuests[1].isComplete, nil); equal(raw.npc.title, nil)
    c.fire("GOSSIP_SHOW"); equal(last(c).type, "GOSSIP_VIEWED")
    local messages = #c.messages; c.fire("GOSSIP_SHOW"); equal(#c.messages, messages)
    c.gossip.options, c.gossip.available = c.secret, { c.secret }
    raw, code = c.namespace.GossipAPI.Read("GOSSIP")
    equal(code, "secret_value"); equal(raw.options, nil); equal(#raw.availableQuests, 0)
end)

test("falha de API e coleção inválida têm diagnóstico sem substituir por coleção vazia", function()
    local c = client(); c.start()
    c.env.C_GossipInfo.GetText = function() error("falha") end
    local raw, code = c.namespace.GossipAPI.Read("GOSSIP")
    equal(code, "api_error"); equal(raw.text, nil); equal(#raw.options, 1)
    c.gossip.options = { [2] = c.gossip.options[1] }
    raw, code = c.namespace.GossipAPI.Read("GOSSIP")
    equal(raw.options, nil); assert(code)
    c.env.C_GossipInfo = false
    raw, code = c.namespace.GossipAPI.Read("GOSSIP")
    equal(raw, nil); equal(code, "api_unavailable")
    c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent(), nil)
end)

test("saudação protege retornos secretos sem transformar falso ou zero", function()
    local c = client(); c.start()
    local q = c.gossip.available[1]
    q.questID, q.questInfoID, q.isMeta, q.frequency = c.secret, c.secret, c.secret, 0
    c.gossip.active[1].isComplete = c.secret
    local raw, code = c.namespace.GossipAPI.Read("GREETING")
    equal(code, "secret_value"); equal(raw.availableQuests[1].questID, nil)
    equal(raw.availableQuests[1].questInfoID, nil); equal(raw.availableQuests[1].isMeta, nil)
    equal(raw.availableQuests[1].frequency, 0); equal(raw.activeQuests[1].isComplete, nil)
end)

test("conversa vazia não insere evento mas lista de missões é conteúdo", function()
    local c = client(); c.start()
    local count = #c.saved().events
    c.gossip = { text = " \n\t", options = {}, available = {}, active = {} }
    c.fire("GOSSIP_SHOW"); c.fire("QUEST_GREETING")
    equal(#c.saved().events, count)
    equal(c.namespace.GossipDialogs.GetCurrent().moment, "GREETING")
    c.gossip.available = { { questID = 123 } }
    c.fire("QUEST_GREETING"); equal(#c.saved().events, count + 1)
    equal(last(c).payload.text, " \n\t")
end)

test("deduplicação por criatura ignora GUID e local entre aparições e sessões", function()
    local n, j, root = open()
    local source = model()
    local id = assert(j.Append("GOSSIP_VIEWED", A, TIME, source))
    source.npc.guid = "Creature-0-2-0-84-777-DEF"; source.location.zone = "Outro lugar"
    local repeated, code = j.Append("GOSSIP_VIEWED", A, TIME+1, source)
    equal(repeated, nil); equal(code, "duplicate_gossip"); equal(root.nextSequence, 2)
    equal(j.FindConversation(A, source), id)
    j.Append("LOCATION_CHANGED", A, TIME, { zone = "Outra zona", subZone = "" })
    local resumed = assert(n.Journal.Open(roundtrip(root)))
    equal(resumed.FindConversation(A, source), id)
    repeated, code = resumed.Append("GOSSIP_VIEWED", A, TIME, source)
    equal(repeated, nil); equal(code, "duplicate_gossip")
end)

test("conteúdo alterado retorno A B A personagens e criaturas são distintos", function()
    local _, j, root = open()
    local source = model()
    assert(j.Append("GOSSIP_VIEWED", A, TIME, source))
    assert(j.Append("GOSSIP_VIEWED", B, TIME, source))
    source.npc.creatureID = 778; assert(j.Append("GOSSIP_VIEWED", A, TIME, source))
    source.npc.creatureID = 777; source.text = "Outra fala"
    assert(j.Append("GOSSIP_VIEWED", A, TIME, source))
    source.text = model().text; assert(j.Append("GOSSIP_VIEWED", A, TIME, source))
    source.options[1].text = "Nova opção"; assert(j.Append("GOSSIP_VIEWED", A, TIME, source))
    source.activeQuests[1].isComplete = true; assert(j.Append("GOSSIP_VIEWED", A, TIME, source))
    source.npc.title = "Outro título"; assert(j.Append("GOSSIP_VIEWED", A, TIME, source))
    equal(#root.events, 8)
end)

test("NPC sem identificação mantém lore sem deduplicar por nome ou GUID", function()
    local _, j, root = open()
    local source = model(); source.npc.creatureID = nil
    assert(j.Append("GOSSIP_VIEWED", A, TIME, source)); assert(j.Append("GOSSIP_VIEWED", A, TIME, source))
    equal(#root.events, 2); equal(j.FindConversation(A, source), nil)
    local c = client(); c.start(); c.npc = nil
    show(c); c.env.C_GossipInfo.SelectOption(7001)
    equal(last(c).type, "GOSSIP_VIEWED"); equal(last(c).payload.npc, nil)
end)

test("esquema aceita tipos aditivos e rejeita corrupção sem mutação", function()
    local n, j, root = open()
    local id = assert(j.Append("GOSSIP_VIEWED", A, TIME, model()))
    local source = assert(n.GossipDialogue.Selection(model(), id, model().options[1]))
    assert(j.Append("GOSSIP_OPTION_SELECTED", A, TIME, source))
    local saved = roundtrip(root); saved.events[1].payload.future = true
    assert(n.Schema.ValidateRoot(saved)); equal(saved.events[1].payload.future, true)
    saved.events[2].payload.conversationEventID = B .. ":1"
    local before = serialize(saved)
    equal(n.Schema.ValidateRoot(saved), nil); equal(serialize(saved), before)
    for _, reference in ipairs({ "x", A .. ":0", A .. ":01", A .. ":9007199254740991" }) do
        source.conversationEventID = reference
        equal(n.Schema.ValidateInput("GOSSIP_OPTION_SELECTED", A, TIME, source), nil)
    end
    equal(root.schemaVersion, 1); equal(n.Schema.MAX_EVENTS, 5000)
end)

test("inserção da escolha exige alvo retido criatura e opção correspondentes", function()
    local n, j, root = open()
    local id = assert(j.Append("GOSSIP_VIEWED", A, TIME, model()))
    local selection = assert(n.GossipDialogue.Selection(model(), id, model().options[1]))
    selection.option.text = "Não foi listada"
    equal(j.Append("GOSSIP_OPTION_SELECTED", A, TIME, selection), nil)
    selection.option.text = model().options[1].text; selection.npc.creatureID = 778
    equal(j.Append("GOSSIP_OPTION_SELECTED", A, TIME, selection), nil)
    selection.npc.creatureID = 777; selection.conversationEventID = A .. ":99"
    equal(j.Append("GOSSIP_OPTION_SELECTED", A, TIME, selection), nil)
    equal(#root.events, 1); equal(root.nextSequence, 2)
end)

test("retenção invalida escolha antes de descartar alvo e aceita leitura posterior sem alvo", function()
    local n, j, root = open()
    local id = assert(j.Append("GOSSIP_VIEWED", A, TIME, model()))
    local selection = assert(n.GossipDialogue.Selection(model(), id, model().options[1]))
    assert(j.Append("GOSSIP_OPTION_SELECTED", A, TIME, selection))
    for i = 1, 4998 do assert(j.Append("LOCATION_CHANGED", A, TIME, { zone = "Zona", subZone = tostring(i) })) end
    local before = serialize(root)
    local inserted, code = j.Append("GOSSIP_OPTION_SELECTED", A, TIME, selection)
    equal(inserted, nil); equal(code, "uncorrelated_gossip"); equal(serialize(root), before)
    assert(j.Append("LOCATION_CHANGED", A, TIME, { zone = "Zona", subZone = "descartar" }))
    assert(n.Schema.ValidateRoot(root)); equal(root.events[1].type, "GOSSIP_OPTION_SELECTED")
    equal(j.FindConversation(A, model()), nil)
    assert(j.Append("GOSSIP_VIEWED", A, TIME, model()))
end)

test("sessão pública fornece cópias e precisa de referência e ativação da geração", function()
    local n = core(); local session = n.GossipSession.New()
    local source = model()
    local copy, token = session.Observe(source)
    copy.text = "alterado"; source.options[1].text = "alterado"
    equal(session.GetCurrent().options[1].text, "Conte-me.")
    equal(session.Select({ method = "ID", value = 7001 }, model().npc), nil)
    session.Bind(A .. ":10"); session.Arm(token)
    local payload = assert(session.Select({ method = "ID", value = 7001 }, model().npc))
    equal(payload.conversationEventID, A .. ":10"); equal(payload.option.optionID, 7001)
    equal(session.Select({ method = "ID", value = 7001 }, model().npc), nil)
    session.Close(); session.Arm(token); equal(session.GetCurrent(), nil)
end)

test("correlação recusa ID duplicado ordem inferida status bloqueado e NPC diferente", function()
    local n = core()
    local source = model(); source.options[2] = { index = 2, optionID = 7001, text = "Outra" }
    equal(bind(n, source).Select({ method = "ID", value = 7001 }, source.npc), nil)
    source = model(); source.options[1].orderIndex = nil
    equal(bind(n, source).Select({ method = "INDEX", value = 1 }, source.npc), nil)
    source = model(); source.options[1].status = 2
    equal(bind(n, source).Select({ method = "ID", value = 7001 }, source.npc), nil)
    source = model(); local npc = model().npc; npc.guid = "Creature-outra-aparição"
    equal(bind(n, source).Select({ method = "ID", value = 7001 }, npc), nil)
    source.options[1].text = nil
    equal(bind(n, source).Select({ method = "ID", value = 7001 }, source.npc), nil)
    source = model("GREETING")
    equal(bind(n, source).Select({ method = "ID", value = 7001 }, source.npc), nil)
end)

test("hook por ID registra opção e referência sem textos digitados nem duplicar chamadas", function()
    local c = client(); c.start(); local viewed = show(c)
    local count = #c.saved().events
    c.env.C_GossipInfo.SelectOption(7001, "texto privado", true)
    local selected = last(c)
    equal(selected.type, "GOSSIP_OPTION_SELECTED"); equal(selected.payload.conversationEventID, viewed.id)
    equal(selected.payload.option.text, "Conte-me sua história."); equal(selected.payload.npc.creatureID, 777)
    equal(selected.payload.location.zone, "Ventobravo")
    assert(not serialize(selected):find("texto privado", 1, true))
    c.env.C_GossipInfo.SelectOption(7001); equal(#c.saved().events, count + 1)
end)

test("hook por orderIndex não usa posição do array nem identificador de missão", function()
    local c = client(); c.start()
    c.gossip.options[1].gossipOptionID = nil; c.gossip.options[1].orderIndex = 7
    show(c); local count = #c.saved().events
    c.env.C_GossipInfo.SelectOptionByIndex(1); equal(#c.saved().events, count)
    c.env.C_GossipInfo.SelectOptionByIndex(7)
    equal(last(c).type, "GOSSIP_OPTION_SELECTED"); equal(last(c).payload.option.orderIndex, 7)
    equal(last(c).payload.option.optionID, nil)
end)

test("hooks com parâmetros secretos não correlacionam nem persistem segredo", function()
    local c = client(); c.start(); show(c)
    local count = #c.saved().events
    c.env.C_GossipInfo.SelectOption(c.secret)
    c.env.C_GossipInfo.SelectOptionByIndex(c.secret)
    c.env.C_GossipInfo.SelectOption(7001, nil, c.secret)
    equal(#c.saved().events, count)
    c.npc.guid = c.secret; c.env.C_GossipInfo.SelectOption(7001)
    equal(#c.saved().events, count)
    assert(c.messages[#c.messages]:find("restritos", 1, true))
end)

test("hooks encadeados observam uma única seleção e nunca executam outra ação", function()
    local c = client(); c.start(); show(c)
    local count, calls = #c.saved().events, 0
    c.selectionEffect = function()
        calls = calls + 1
        c.selectionEffect = function() calls = calls + 1 end
        c.env.C_GossipInfo.SelectOption(7001)
    end
    c.env.C_GossipInfo.SelectOptionByIndex(0)
    equal(calls, 2); equal(#c.saved().events, count + 1)
    equal(last(c).type, "GOSSIP_OPTION_SELECTED")
end)

test("ordem ambígua e opção sem ID continuam visíveis sem escolha presumida", function()
    local c = client(); c.start()
    c.gossip.options[2] = { gossipOptionID = 7002, orderIndex = 0, name = "Outra pergunta" }
    show(c); local count = #c.saved().events
    c.env.C_GossipInfo.SelectOptionByIndex(0); equal(#c.saved().events, count)
    c.fire("GOSSIP_CLOSED", false)
    c.gossip.options = { { name = "Sem identificadores", icon = 134400 } }
    show(c); count = #c.saved().events
    c.env.C_GossipInfo.SelectOption(7001); c.env.C_GossipInfo.SelectOptionByIndex(1)
    equal(#c.saved().events, count)
    equal(c.namespace.GossipDialogs.GetCurrent().options[1].optionID, nil)
end)

test("confirmação e código só registram chamada confirmada e cancelamento não registra", function()
    local c = client(); c.start(); show(c)
    local count = #c.saved().events
    c.selectionEffect = function() c.fire("GOSSIP_CONFIRM", 7001, "Confirmar", 0) end
    c.env.C_GossipInfo.SelectOption(7001); equal(#c.saved().events, count)
    c.fire("GOSSIP_CONFIRM_CANCEL"); equal(#c.saved().events, count)
    c.fire("GOSSIP_ENTER_CODE", 7001)
    c.selectionEffect = nil
    c.env.C_GossipInfo.SelectOption(7001, "senha", c.secret); equal(#c.saved().events, count)
    c.env.C_GossipInfo.SelectOption(7001, "senha", true)
    equal(last(c).type, "GOSSIP_OPTION_SELECTED"); assert(not serialize(last(c)):find("senha", 1, true))
end)

test("fechamento síncrono antes do hook omite escolha sem atribuí-la a outra conversa", function()
    local c = client(); c.start(); show(c)
    local count = #c.saved().events
    c.selectionEffect = function() c.fire("GOSSIP_CLOSED", false) end
    c.env.C_GossipInfo.SelectOption(7001)
    equal(#c.saved().events, count); equal(c.namespace.GossipDialogs.GetCurrent(), nil)
end)

test("nova conversa síncrona não recebe escolha da anterior e callback antigo não arma geração nova", function()
    local c = client(); c.start(); show(c)
    c.selectionEffect = function()
        c.gossip.text = "Outra conversa com mesma opção"; c.fire("GOSSIP_SHOW")
    end
    c.env.C_GossipInfo.SelectOption(7001)
    equal(last(c).type, "GOSSIP_VIEWED"); equal(last(c).payload.text, "Outra conversa com mesma opção")
    c.selectionEffect = nil
    local count = #c.saved().events
    c.env.C_GossipInfo.SelectOption(7001); equal(#c.saved().events, count)
    c.fire("GOSSIP_CLOSED", false); c.flush(); c.env.C_GossipInfo.SelectOption(7001)
    equal(#c.saved().events, count)
    show(c); c.env.C_GossipInfo.SelectOption(7001); equal(last(c).type, "GOSSIP_OPTION_SELECTED")
end)

test("atualização de opções renova modelo e invalida seletor até o próximo turno", function()
    local c = client(); c.start(); show(c)
    c.gossip.options[1].name = "Nova pergunta"
    c.fire("GOSSIP_OPTIONS_REFRESHED")
    equal(last(c).payload.options[1].text, "Nova pergunta")
    local count = #c.saved().events
    c.env.C_GossipInfo.SelectOption(7001); equal(#c.saved().events, count)
    c.flush(); c.env.C_GossipInfo.SelectOption(7001)
    equal(last(c).payload.option.text, "Nova pergunta")
end)

test("visita deduplicada após reload referencia conversa retida e aceita nova seleção", function()
    local c = client(); c.start(); local viewed = show(c)
    local resumed = client(roundtrip(c.saved())); resumed.start()
    resumed.npc.guid = "Creature-0-333-0-84-777-DEF"
    local count = #resumed.saved().events
    show(resumed); equal(#resumed.saved().events, count)
    resumed.env.C_GossipInfo.SelectOption(7001)
    equal(last(resumed).payload.conversationEventID, viewed.id)
    equal(last(resumed).payload.npc.guid, resumed.npc.guid)
end)

test("abertura de missão a partir de gossip não duplica oferta aceite ou seleção", function()
    local c = client(); c.start(); show(c)
    c.fire("QUEST_DETAIL"); equal(last(c).type, "QUEST_OFFERED")
    equal(c.namespace.GossipDialogs.GetCurrent(), nil)
    c.fire("QUEST_ACCEPTED", 101); equal(last(c).type, "QUEST_ACCEPTED")
    c.fire("QUEST_COMPLETE"); c.env.GetQuestReward(2); c.fire("QUEST_TURNED_IN", 101, 450, 120)
    equal(last(c).type, "QUEST_COMPLETED"); equal(last(c).payload.chosenReward.itemID, 502)
    equal(last(c).payload.objectives, nil)
    local counts = {}
    for _, event in ipairs(c.saved().events) do counts[event.type] = (counts[event.type] or 0) + 1 end
    equal(counts.QUEST_OFFERED, 1); equal(counts.QUEST_ACCEPTED, 1); equal(counts.QUEST_COMPLETED, 1)
    equal(counts.GOSSIP_VIEWED, 1); equal(counts.GOSSIP_OPTION_SELECTED, nil)
end)

test("entrada em gossip fecha diálogo público de missão sem perder correlação da oferta", function()
    local c = client(); c.start(); c.fire("QUEST_DETAIL")
    assert(c.namespace.QuestDialogs.GetCurrent())
    show(c); equal(c.namespace.QuestDialogs.GetCurrent(), nil)
    c.fire("QUEST_ACCEPTED", 101)
    equal(last(c).type, "QUEST_ACCEPTED"); assert(last(c).payload.offerEventID)
end)

test("saída do mundo e diário bloqueado mantêm modelo sem inserir ou armar seleção", function()
    local c = client(); c.start(); show(c)
    c.fire("PLAYER_LEAVING_WORLD"); equal(c.namespace.GossipDialogs.GetCurrent(), nil)
    local count = #c.saved().events
    show(c); c.env.C_GossipInfo.SelectOption(7001); equal(#c.saved().events, count)
    local damaged = { schemaVersion = 99, events = {} }; local before = serialize(damaged)
    c = client(damaged); c.start(); show(c); c.env.C_GossipInfo.SelectOption(7001)
    assert(c.namespace.GossipDialogs.GetCurrent()); equal(serialize(damaged), before)
end)

test("sem defer disponível não presume escolha e preserva captura da conversa", function()
    local c = client(); c.start(); c.env.C_Timer = false
    show(c); c.env.C_GossipInfo.SelectOption(7001)
    equal(last(c).type, "GOSSIP_VIEWED")
    assert(c.messages[#c.messages]:find("indisponíveis", 1, true))
end)

test("novos nomes pt-BR aparecem no status e dica continua contando inserções", function()
    local c = client(); c.start(); show(c); c.command()
    assert(c.messages[#c.messages-1]:find("conversa vista", 1, true))
    c.env.C_GossipInfo.SelectOption(7001); c.command()
    assert(c.messages[#c.messages-1]:find("opção de conversa escolhida", 1, true))
    local tooltip = t.tooltipText(c)
    assert(tooltip:find("NerdWow v0.7.0", 1, true)); assert(tooltip:find("Eventos no diário: 4", 1, true))
    assert(tooltip:find("aguardando gravação: 4", 1, true))
    equal(c.registered.CHAT_MSG_MONSTER_SAY, nil); equal(c.registered.CHAT_MSG_MONSTER_YELL, nil)
end)
