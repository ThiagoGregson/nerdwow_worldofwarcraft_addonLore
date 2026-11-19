-- Suíte externa de missões; recebe somente os helpers públicos do harness.
local t = ...
local test, equal, core, client = t.test, t.equal, t.core, t.client
local serialize, roundtrip = t.serialize, t.roundtrip
local A, B, TIME = t.A, t.B, t.TIME
local function model(moment, questID)
    return { moment = moment or "OFFER", quest = { id = questID or 101, title = "Os nomes nas margens" },
        location = { mapID = 84, zone = "Ventobravo", subZone = "" },
        rewards = { choices = { { index = 1, itemID = 501, name = "Pena", quantity = 1, quality = 3, icon = 1234 },
            { index = 2, itemID = 502, name = "Tinteiro", quantity = 2, quality = 4, icon = 1235 } },
            fixed = { { index = 1, itemID = 503, name = "Tomo", quantity = 1, quality = 2, icon = 1236 } },
            money = 120, experience = 450 } }
end
local function last(c) return c.saved().events[#c.saved().events] end
local function has(text, value) assert(text:find(value, 1, true), value) end

test("modelo de missão aceita três momentos sem inventar campos", function()
    local q = core().QuestDialogue
    for _, moment in ipairs({ "OFFER", "PROGRESS", "COMPLETE" }) do
        local snapshot = assert(q.Snapshot({ moment = moment, quest = { id = 101 } }))
        equal(snapshot.moment, moment); equal(snapshot.quest.id, 101)
        equal(snapshot.quest.title, nil); equal(snapshot.npc, nil); equal(snapshot.location, nil)
        equal(snapshot.objectives, nil); equal(snapshot.requiredItems, nil); equal(snapshot.rewards, nil)
    end
    equal(q.Snapshot({ moment = "GOSSIP", quest = { id = 101 } }), nil)
    equal(q.Snapshot({ moment = "OFFER", quest = {} }), nil)
end)

test("modelo fotografa dados aninhados e descarta somente extensões de novas escritas", function()
    local q = core().QuestDialogue
    local source = model()
    source.quest.description = "Memórias\n$N: 你好 — não truncar."
    source.extra = { hidden = true }
    source.quest.extra = "não exportar"
    local snapshot = assert(q.Snapshot(source))
    equal(snapshot.extra, nil); equal(snapshot.quest.extra, nil)
    source.rewards.choices[1].name = "Alterado"
    equal(snapshot.rewards.choices[1].name, "Pena")
    equal(snapshot.quest.description, "Memórias\n$N: 你好 — não truncar.")
    assert(q.Equal(snapshot, roundtrip(snapshot)))
end)

test("modelo rejeita números, arrays e estados inválidos sem efeitos", function()
    local q = core().QuestDialogue
    for _, value in ipairs({ -1, 0, math.huge, 0 / 0, 1.5, "101" }) do
        equal(q.Snapshot({ moment = "OFFER", quest = { id = value } }), nil)
    end
    for _, mutate in ipairs({
        function(m) m.rewards.money = -1 end,
        function(m) m.rewards.choices[1].quality = 9 end,
        function(m) m.objectives = { [2] = { index = 2 } } end,
        function(m) m.objectives = { { index = 1, finished = "true" } } end,
        function(m) m.rewards.choices[2].index = 1 end,
        function(m) m.requiredItems = { [0] = { index = 1 } } end,
    }) do
        local source = model()
        mutate(source)
        local before = serialize(source)
        equal(q.Snapshot(source), nil)
        equal(serialize(source), before)
    end
end)

test("modelo mantém zero, false, objetivos excedidos e arrays vazios conhecidos", function()
    local q = core().QuestDialogue
    local source = model("PROGRESS")
    source.rewards.money, source.rewards.experience = 0, 0
    source.objectives = { { index = 1, text = "", finished = false, fulfilled = 4, required = 3 } }
    source.requiredItems = {}
    local snapshot = assert(q.Snapshot(source))
    equal(snapshot.rewards.money, 0); equal(snapshot.objectives[1].finished, false)
    equal(snapshot.objectives[1].fulfilled, 4); equal(#snapshot.requiredItems, 0)
end)

test("escolha só é válida no momento COMPLETE e corresponde à opção exata", function()
    local q = core().QuestDialogue
    local source = model("COMPLETE")
    source.chosenReward = roundtrip(source.rewards.choices[2])
    assert(q.Snapshot(source))
    source.moment = "OFFER"
    equal(q.Snapshot(source), nil)
    source.moment = "COMPLETE"
    source.chosenReward.itemID = 999
    equal(q.Snapshot(source), nil)
    source.chosenReward = { index = 2, itemID = 502 }
    equal(q.Snapshot(source), nil)
end)

test("sessão pública retorna cópia, fecha e reinicia sem expor cache privado", function()
    local session = core().QuestSession.New()
    equal(session.GetCurrent(), nil)
    assert(session.Observe(model()))
    local snapshot = session.GetCurrent()
    snapshot.quest.title = "Alterado"
    equal(session.GetCurrent().quest.title, "Os nomes nas margens")
    session.Close()
    equal(session.GetCurrent(), nil)
    local accepted = assert(session.ForEvent("QUEST_ACCEPTED", 101))
    equal(accepted.quest.title, "Os nomes nas margens")
    session.Reset()
    accepted = assert(session.ForEvent("QUEST_ACCEPTED", 101))
    equal(accepted.quest.title, nil)
end)

test("sessão não associa NPC ou recompensa de outra missão", function()
    local session = core().QuestSession.New()
    local source = model("COMPLETE")
    source.npc = { name = "Arquivista", creatureID = 777 }
    session.Observe(source)
    assert(session.SelectReward(101, 2))
    local completed = assert(session.ForEvent("QUEST_COMPLETED", 202, nil, nil, 0, 0))
    equal(completed.npc, nil); equal(completed.chosenReward, nil)
    equal(completed.rewards.money, 0); equal(completed.rewards.experience, 0)
    completed = assert(session.ForEvent("QUEST_COMPLETED", 101, nil, nil, 5, 7))
    equal(completed.chosenReward.itemID, 502)
    equal(completed.rewards.money, 5); equal(completed.rewards.experience, 7)
end)

test("sessão invalida seleção em nova oferta e não reutiliza oferta concluída", function()
    local session = core().QuestSession.New()
    session.Observe(model("OFFER"))
    session.Observe(model("COMPLETE"))
    session.SelectReward(101, 1)
    assert(session.ForEvent("QUEST_COMPLETED", 101))
    equal(session.ForEvent("QUEST_ACCEPTED", 101).quest.title, nil)
    session.Observe(model("OFFER", 202))
    equal(session.SelectReward(101, 1), false)
    equal(session.ForEvent("QUEST_COMPLETED", 101).chosenReward, nil)
end)

test("adaptador lê oferta sem tocar em frames nem selecionar missão no log", function()
    local c = client(); c.start()
    local raw = assert(c.namespace.QuestAPI.Read("OFFER"))
    equal(raw.quest.id, 101); equal(raw.quest.description, "Recupere a história.")
    equal(raw.quest.objectiveText, "Traga três tomos.")
    equal(raw.quest.progressText, nil); equal(raw.quest.rewardText, nil)
    equal(raw.npc.creatureID, 777); equal(raw.npc.name, "Arquivista")
    equal(raw.npc.title, "Guardiã dos registros"); equal(raw.npc.faction, "Alliance")
    equal(raw.location.zone, "Ventobravo")
    equal(raw.objectives[1].fulfilled, 1); equal(raw.objectives[1].required, 3)
    equal(raw.rewards.choices[2].itemID, 502); equal(raw.rewards.fixed[1].itemID, 503)
    assert(c.namespace.QuestDialogue.Snapshot(raw))
end)

test("adaptador lê progresso e itens exigidos sem textos de outro momento", function()
    local c = client(); c.start()
    local raw = assert(c.namespace.QuestAPI.Read("PROGRESS"))
    equal(raw.quest.progressText, "Encontrou os tomos?")
    equal(raw.quest.description, nil); equal(raw.quest.rewardText, nil); equal(raw.rewards, nil)
    equal(raw.requiredItems[1].itemID, 504); equal(raw.requiredItems[1].quantity, 3)
    c.hiddenItem = 1
    raw = assert(c.namespace.QuestAPI.Read("PROGRESS"))
    equal(#raw.requiredItems, 0)
    c.hideRequired = true
    equal(c.namespace.QuestAPI.Read("PROGRESS").requiredItems, nil)
end)

test("adaptador lê conclusão e preserva qualidade, ícone, quantidades e dinheiro", function()
    local c = client(); c.start()
    local raw = assert(c.namespace.QuestAPI.Read("COMPLETE"))
    equal(raw.quest.rewardText, "Eles serão lembrados.")
    equal(raw.quest.description, nil); equal(raw.quest.progressText, nil)
    equal(raw.rewards.choices[2].quality, 4); equal(raw.rewards.choices[2].quantity, 2)
    equal(raw.rewards.fixed[1].icon, 1236)
    equal(raw.rewards.money, 120); equal(raw.rewards.experience, 450)
    equal(raw.chosenReward, nil)
end)

test("adaptador mantém campos indisponíveis ausentes e não usa o alvo como NPC", function()
    local c = client(); c.start()
    c.npc = nil
    c.quest.title, c.quest.description, c.quest.objectives = nil, nil, nil
    c.quest.choices, c.quest.fixed, c.quest.money, c.quest.experience = nil, nil, nil, nil
    c.env.GetQuestText = false
    c.env.UnitGUID = function(unit) assert(unit ~= "target"); return A end
    local raw = assert(c.namespace.QuestAPI.Read("OFFER"))
    equal(raw.npc, nil); equal(raw.quest.description, nil)
    equal(raw.objectives, nil); equal(raw.rewards, nil)
    assert(c.namespace.QuestDialogue.Snapshot(raw))
end)

test("adaptador omite secretos antes de converter números e textos aninhados", function()
    local c = client(); c.start()
    c.quest.title, c.npc.guid, c.npc.faction = c.secret, c.secret, c.secret
    c.quest.objectives[1].text = c.secret
    c.quest.objectives[1].finished = c.secret
    c.quest.choices[1].itemID = c.secret
    c.quest.choices[1].icon = c.secret
    c.quest.choices[1].name = c.secret
    c.quest.money = c.secret
    local raw, code = c.namespace.QuestAPI.Read("OFFER")
    equal(code, "secret_value")
    equal(raw.quest.title, nil); equal(raw.npc.guid, nil); equal(raw.npc.faction, nil)
    equal(raw.objectives[1].text, nil); equal(raw.objectives[1].finished, nil)
    equal(raw.rewards.choices[1].itemID, nil); equal(raw.rewards.choices[1].icon, nil)
    equal(raw.rewards.money, nil)
    assert(c.namespace.QuestDialogue.Snapshot(raw))
    c.quest.id = c.secret
    raw, code = c.namespace.QuestAPI.Read("OFFER")
    equal(raw, nil); equal(code, "secret_value")
end)

test("tabelas secretas de objetivos e ID de evento secreto não são indexados", function()
    local c = client(); c.start()
    c.quest.objectives = c.secret
    local raw, code = c.namespace.QuestAPI.Read("PROGRESS")
    equal(raw.objectives, nil); equal(code, "secret_value")
    local info
    info, code = c.namespace.QuestAPI.EventInfo(c.secret, 0, 0)
    equal(info, nil); equal(code, "secret_value")
end)

test("fallback de item por link é seguro e subtítulo não é inferido de nível", function()
    local c = client(); c.start()
    c.quest.fixed[1].itemID = nil
    c.quest.fixed[1].link = "|Hitem:503:0|h[Tomo]|h"
    c.npc.subtitle = "Nível 70 Humanoide"
    local raw = assert(c.namespace.QuestAPI.Read("COMPLETE"))
    equal(raw.rewards.fixed[1].itemID, 503); equal(raw.npc.title, nil)
    c.quest.fixed[1].link = c.secret
    raw = assert(c.namespace.QuestAPI.Read("COMPLETE"))
    equal(raw.rewards.fixed[1].itemID, nil)
end)

test("falha de API produz diagnóstico e preserva campos seguros disponíveis", function()
    local c = client(); c.start()
    c.env.GetQuestText = function() error("falha simulada") end
    c.fire("QUEST_DETAIL")
    equal(last(c).type, "QUEST_OFFERED")
    equal(last(c).payload.quest.description, nil)
    has(c.messages[#c.messages], "campos indisponíveis")
    c.env.GetQuestID = function() error("ID indisponível") end
    local before = #c.saved().events
    c.fire("QUEST_DETAIL")
    equal(#c.saved().events, before); equal(c.namespace.QuestDialogs.GetCurrent(), nil)
end)

test("aceitar e concluir a mesma missão são eventos distintos do diálogo de recompensa", function()
    local c = client(); c.start()
    c.fire("QUEST_DETAIL")
    equal(last(c).type, "QUEST_OFFERED")
    c.fire("QUEST_FINISHED")
    equal(c.namespace.QuestDialogs.GetCurrent(), nil)
    c.fire("QUEST_ACCEPTED", 101)
    equal(last(c).type, "QUEST_ACCEPTED")
    equal(last(c).payload.quest.description, nil)
    equal(last(c).payload.offerEventID, c.saved().events[3].id)
    equal(c.saved().events[3].payload.quest.description, "Recupere a história.")
    c.fire("QUEST_PROGRESS")
    equal(last(c).type, "QUEST_PROGRESS_VIEWED")
    local before = #c.saved().events
    c.fire("QUEST_COMPLETE")
    equal(#c.saved().events, before)
    equal(c.namespace.QuestDialogs.GetCurrent().moment, "COMPLETE")
    c.env.GetQuestReward(2)
    c.fire("QUEST_FINISHED")
    c.fire("QUEST_TURNED_IN", 101, 900, 240)
    equal(last(c).type, "QUEST_COMPLETED")
    equal(last(c).payload.chosenReward.itemID, 502)
    equal(last(c).payload.rewards.experience, 900); equal(last(c).payload.rewards.money, 240)
    equal(last(c).payload.quest.rewardText, "Eles serão lembrados.")
end)

test("sem oferta observada, aceite usa apenas dados por ID do log", function()
    local c = client(); c.start()
    c.fire("QUEST_ACCEPTED", 101)
    equal(last(c).payload.quest.title, "Os nomes nas margens")
    equal(last(c).payload.npc, nil); equal(last(c).payload.rewards, nil)
    equal(last(c).payload.quest.description, nil)
    equal(last(c).payload.objectives[1].required, 3)
end)

test("conclusão fora de ordem e escolha tardia ficam sem dados não correlacionados", function()
    local c = client(); c.start()
    c.fire("QUEST_TURNED_IN", 202, 0, 0)
    equal(last(c).payload.quest.id, 202)
    equal(last(c).payload.chosenReward, nil); equal(last(c).payload.npc, nil)
    equal(last(c).payload.rewards.experience, 0)
    c.fire("QUEST_COMPLETE")
    c.fire("QUEST_TURNED_IN", 101, 0, 0)
    local recorded = serialize(last(c))
    c.env.GetQuestReward(1)
    equal(serialize(last(c)), recorded)
    equal(last(c).payload.chosenReward, nil)
end)

test("escolha ausente, fora de faixa, secreta ou de outra missão nunca é inferida", function()
    for _, scenario in ipairs({ "absent", "out_of_range", "secret", "other_quest", "unknown_id", "single_choice" }) do
        local c = client(); c.start()
        if scenario == "single_choice" then c.quest.choices[2] = nil end
        if scenario == "unknown_id" then c.quest.choices[1].itemID = nil end
        c.fire("QUEST_COMPLETE")
        if scenario == "out_of_range" then c.env.GetQuestReward(999)
        elseif scenario == "secret" then c.env.GetQuestReward(c.secret)
        elseif scenario == "other_quest" then c.quest.id = 202; c.env.GetQuestReward(1); c.quest.id = 101
        elseif scenario == "unknown_id" then c.env.GetQuestReward(1) end
        c.fire("QUEST_TURNED_IN", 101, 0, 0)
        equal(last(c).payload.chosenReward, nil)
    end
end)

test("nova tentativa inválida de recompensa elimina a escolha anterior", function()
    local c = client(); c.start()
    c.fire("QUEST_COMPLETE")
    c.env.GetQuestReward(1)
    c.env.GetQuestReward(c.secret)
    c.fire("QUEST_TURNED_IN", 101, 0, 0)
    equal(last(c).payload.chosenReward, nil)
end)

test("secretos em dados reais de conclusão são omitidos sem bloquear o evento seguro", function()
    local c = client(); c.start()
    c.fire("QUEST_TURNED_IN", 101, c.secret, c.secret)
    equal(last(c).type, "QUEST_COMPLETED")
    equal(last(c).payload.rewards, nil)
    local count = #c.saved().events
    c.fire("QUEST_ACCEPTED", c.secret)
    equal(#c.saved().events, count)
    equal(last(c).payload.quest.title, "Os nomes nas margens")
end)

test("ausência ou falha do observador mantém funcionamento sem inventar escolha", function()
    local c = client(); c.start()
    c.env.hooksecurefunc = false
    equal(c.namespace.QuestAPI.ObserveSelection(function() error("não deveria chamar") end), false)
    c.env.hooksecurefunc = function() error("observação indisponível") end
    local ok, code = c.namespace.QuestAPI.ObserveSelection(function() end)
    equal(ok, nil); equal(code, "api_error")
end)

test("QUEST_ITEM_UPDATE renova somente o diálogo da mesma missão", function()
    local c = client(); c.start()
    c.fire("QUEST_DETAIL")
    local count = #c.saved().events
    c.fire("QUEST_ITEM_UPDATE")
    equal(#c.saved().events, count)
    c.quest.choices[1].name = "Nome agora disponível"
    c.fire("QUEST_ITEM_UPDATE")
    equal(#c.saved().events, count + 1)
    c.quest.id = 202
    c.fire("QUEST_ITEM_UPDATE")
    equal(#c.saved().events, count + 1)
    equal(c.namespace.QuestDialogs.GetCurrent().quest.id, 101)
    c.fire("QUEST_FINISHED")
    c.fire("QUEST_ITEM_UPDATE")
    equal(#c.saved().events, count + 1)
end)

test("novo evento de missão não gera LOCATION_CHANGED por passagem indevida", function()
    local c = client(); c.start()
    c.zone = "Outra zona"
    c.fire("QUEST_COMPLETE")
    equal(#c.saved().events, 2)
    c.fire("QUEST_TURNED_IN", 101, 450, 120)
    equal(#c.saved().events, 3)
    equal(last(c).payload.location.zone, "Outra zona")
end)

test("saída do mundo limpa associação e diário bloqueado não impede modelo atual", function()
    local c = client(); c.start()
    c.fire("QUEST_DETAIL")
    c.fire("PLAYER_LEAVING_WORLD")
    equal(c.namespace.QuestDialogs.GetCurrent(), nil)
    c.fire("PLAYER_ENTERING_WORLD")
    c.fire("QUEST_ACCEPTED", 101)
    equal(c.namespace.QuestDialogs.ForEvent("QUEST_ACCEPTED", 101).npc, nil)
    equal(last(c).payload.offerEventID, c.saved().events[3].id)
    equal(last(c).payload.npc.name, "Arquivista")
    local blocked = client(false); blocked.start()
    blocked.fire("QUEST_DETAIL")
    assert(blocked.namespace.QuestDialogs.GetCurrent())
    equal(blocked.saved(), false)
    blocked.fire("PLAYER_LEAVING_WORLD")
    equal(blocked.namespace.QuestDialogs.GetCurrent(), nil)
end)

test("status e dica mostram novos tipos em pt-BR sem zerar pendentes", function()
    local c = client(); c.start()
    c.fire("QUEST_DETAIL")
    c.command()
    has(c.messages[#c.messages - 1], "missão oferecida")
    has(t.tooltipText(c), "aguardando gravação: 3")
    for _, pair in ipairs({ { "QUEST_ACCEPTED", "missão aceita" },
        { "QUEST_PROGRESS_VIEWED", "progresso da missão visto" }, { "QUEST_COMPLETED", "missão concluída" } }) do
        equal(c.namespace.Text.eventTypes[pair[1]], pair[2])
    end
end)

test("quatro novos tipos validam esquema 1, envelope e momento", function()
    local n = core()
    for kind, moment in pairs({ QUEST_OFFERED = "OFFER", QUEST_ACCEPTED = "OFFER",
        QUEST_PROGRESS_VIEWED = "PROGRESS", QUEST_COMPLETED = "COMPLETE" }) do
        local journal, root = n.Journal.Open(nil)
        assert(journal.Append(kind, A, TIME, model(moment)))
        assert(n.Schema.ValidateRoot(root))
        equal(root.schemaVersion, 1)
        root.events[1].payload.quest.id = false
        local valid, code = n.Schema.ValidateRoot(root)
        equal(valid, nil); equal(code, "invalid_event")
        local input = model(moment == "OFFER" and "PROGRESS" or "OFFER")
        local before = serialize(root)
        equal(journal.Append(kind, A, TIME, input), nil)
        equal(serialize(root), before)
    end
end)

test("deduplicação distingue missão, tipo, personagem e conteúdo completo", function()
    local journal, root = core().Journal.Open(nil)
    local first = model("OFFER")
    assert(journal.Append("QUEST_OFFERED", A, TIME, first))
    local sequence = root.nextSequence
    local id, code = journal.Append("QUEST_OFFERED", A, TIME + 1, first)
    equal(id, nil); equal(code, "duplicate_quest"); equal(root.nextSequence, sequence)
    assert(journal.Append("QUEST_ACCEPTED", A, TIME, first))
    assert(journal.Append("QUEST_OFFERED", B, TIME, first))
    assert(journal.Append("QUEST_OFFERED", A, TIME, model("OFFER", 202)))
    equal(journal.Append("QUEST_OFFERED", A, TIME, first), nil)
    first.npc = { name = "Outra pessoa" }
    assert(journal.Append("QUEST_OFFERED", A, TIME, first))
    first.npc = nil
    assert(journal.Append("QUEST_OFFERED", A, TIME, first))
    first.location.subZone = "Interior"
    assert(journal.Append("QUEST_OFFERED", A, TIME, first))
    first.rewards.choices[1].quantity = 2
    assert(journal.Append("QUEST_OFFERED", A, TIME, first))
end)

test("deduplicação atravessa sessões e conserva extras persistidos", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    assert(journal.Append("QUEST_PROGRESS_VIEWED", A, TIME, model("PROGRESS")))
    root.events[1].payload.extra = { future = true }
    local saved = roundtrip(root)
    local resumed = assert(n.Journal.Open(saved))
    local id, code = resumed.Append("QUEST_PROGRESS_VIEWED", A, TIME + 9, model("PROGRESS"))
    equal(id, nil); equal(code, "duplicate_quest")
    equal(saved.events[1].payload.extra.future, true)
end)

test("missões também têm cópia defensiva e não alteram IDs ou retenção", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    local source = model()
    assert(journal.Append("QUEST_OFFERED", A, TIME, source))
    source.quest.title = "Modificado"; source.rewards.fixed[1].name = "Alterado"
    equal(root.events[1].payload.quest.title, "Os nomes nas margens")
    equal(root.events[1].payload.rewards.fixed[1].name, "Tomo")
    equal(root.events[1].id, A .. ":1"); equal(n.Schema.MAX_EVENTS, 5000)
end)

test("regressão 29078: modelo COMPLETE não expõe o objetivo antigo 0/6", function()
    local c = client(); c.start()
    c.quest.id = 29078
    c.quest.title = "É hora de reagir"
    c.quest.objectives = { { text = "0/6 Worg da Rocha Negra", type = "monster",
        numFulfilled = 0, numRequired = 6, finished = false } }
    c.fire("QUEST_DETAIL")
    equal(last(c).payload.objectives[1].fulfilled, 0)
    c.fire("QUEST_ACCEPTED", 29078)
    c.fire("QUEST_COMPLETE")
    equal(c.namespace.QuestDialogs.GetCurrent().objectives, nil)
    c.env.GetQuestReward(1)
    c.fire("QUEST_TURNED_IN", 29078, 378, 2000)
    equal(last(c).type, "QUEST_COMPLETED")
    equal(last(c).payload.objectives, nil)
    equal(last(c).payload.chosenReward.itemID, 501)
    equal(last(c).payload.rewards.experience, 378)
    equal(last(c).payload.quest.rewardText, "Eles serão lembrados.")
end)

test("regressão: fallback tardio 0/6 não substitui nem inventa conclusão 6/6", function()
    local q, session = core().QuestDialogue, core().QuestSession.New()
    local completed = model("COMPLETE")
    completed.objectives = { { index = 1, text = "6/6 Worgs", fulfilled = 6, required = 6, finished = true } }
    local before = serialize(completed)
    session.Observe(completed)
    equal(serialize(completed), before)
    equal(session.GetCurrent().objectives, nil)
    local fallback = { moment = "COMPLETE", quest = { id = 101 },
        objectives = { { index = 1, text = "0/6 Worgs", fulfilled = 0, required = 6, finished = false } } }
    local result = assert(session.ForEvent("QUEST_COMPLETED", 101, fallback))
    equal(result.objectives, nil)
    equal(q.Snapshot(fallback).objectives, nil)
    equal(fallback.objectives[1].fulfilled, 0)
end)

test("COMPLETE não consulta objetivos do log; oferta e progresso continuam consultando", function()
    local c = client(); c.start()
    local calls = 0
    c.env.C_QuestLog.GetQuestObjectives = function()
        calls = calls + 1
        return c.quest.objectives
    end
    assert(c.namespace.QuestAPI.Read("COMPLETE"))
    assert(c.namespace.QuestAPI.ReadLog(101, "COMPLETE"))
    equal(calls, 0)
    assert(c.namespace.QuestAPI.Read("OFFER").objectives)
    assert(c.namespace.QuestAPI.Read("PROGRESS").objectives)
    equal(calls, 2)
end)

test("aceite referencia oferta correspondente sem repetir narrativa ou recompensas", function()
    local c = client(); c.start()
    c.fire("QUEST_DETAIL")
    local offered = last(c)
    local before = serialize(offered)
    c.fire("QUEST_ACCEPTED", 101)
    local accepted = last(c).payload
    equal(accepted.offerEventID, offered.id)
    equal(accepted.quest.id, 101)
    equal(accepted.quest.title, c.quest.title)
    equal(accepted.quest.description, nil); equal(accepted.quest.objectiveText, nil)
    equal(accepted.rewards, nil); equal(accepted.requiredItems, nil); equal(accepted.chosenReward, nil)
    equal(accepted.npc.creatureID, 777); equal(accepted.location.mapID, 84)
    equal(accepted.objectives[1].fulfilled, 1)
    equal(serialize(offered), before)
    assert(#serialize(accepted) < #serialize(offered.payload))
end)

test("oferta retida após reload fornece referência e NPC sem cache de sessão", function()
    local first = client(); first.start(); first.fire("QUEST_DETAIL")
    local offeredID = last(first).id
    local c = client(roundtrip(first.saved())); c.start()
    equal(c.namespace.QuestDialogs.GetCurrent(), nil)
    c.npc = { name = "NPC sem relação" }
    c.fire("QUEST_ACCEPTED", 101)
    equal(last(c).payload.offerEventID, offeredID)
    equal(last(c).payload.npc.name, "Arquivista")
    equal(last(c).payload.quest.description, nil)
end)

test("referência do aceite distingue personagem, missão e oferta mais recente", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    assert(journal.Append("QUEST_OFFERED", A, TIME, model("OFFER", 101)))
    assert(journal.Append("QUEST_OFFERED", B, TIME, model("OFFER", 101)))
    assert(journal.Append("QUEST_OFFERED", A, TIME, model("OFFER", 202)))
    local _, code = journal.Append("QUEST_OFFERED", A, TIME, model("OFFER", 101))
    equal(code, "duplicate_quest")
    -- A oferta idêntica foi deduplicada: o último registro de A/101 é o primeiro.
    assert(journal.Append("QUEST_ACCEPTED", A, TIME, model("OFFER", 101)))
    equal(root.events[#root.events].payload.offerEventID, root.events[1].id)
    local changed = model("OFFER", 101); changed.quest.description = "Outra oferta"
    assert(journal.Append("QUEST_OFFERED", A, TIME, changed))
    local latest = root.events[#root.events].id
    assert(journal.Append("QUEST_ACCEPTED", A, TIME, changed))
    equal(root.events[#root.events].payload.offerEventID, latest)
end)

test("sem oferta retida o aceite preserva textos conhecidos e remove campos desnecessários", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    local source = model("OFFER")
    source.quest.description = "Única narrativa disponível"
    source.quest.objectiveText = "Recupere os tomos"
    source.npc = { name = "Arquivista" }
    assert(journal.Append("QUEST_ACCEPTED", A, TIME, source))
    local accepted = root.events[1].payload
    equal(accepted.offerEventID, nil)
    equal(accepted.quest.description, source.quest.description)
    equal(accepted.quest.objectiveText, source.quest.objectiveText)
    equal(accepted.rewards, nil); equal(accepted.npc.name, "Arquivista")
    local c = client(); c.start(); c.fire("QUEST_ACCEPTED", 101)
    equal(last(c).payload.offerEventID, nil)
    equal(last(c).payload.quest.description, nil)
    equal(last(c).payload.npc, nil)
end)

test("oferta descartada pela própria inserção do aceite não produz referência quebrada", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    local source = model("OFFER")
    source.quest.description = "Lore que não pode desaparecer"
    source.quest.objectiveText = "Objetivo original"
    assert(journal.Append("QUEST_OFFERED", A, TIME, source))
    for index = 1, 4999 do
        assert(journal.Append("LOCATION_CHANGED", A, TIME, { zone = "Zona", subZone = tostring(index) }))
    end
    assert(journal.Append("QUEST_ACCEPTED", A, TIME, { moment = "OFFER", quest = { id = 101 } }))
    local accepted = root.events[#root.events].payload
    equal(#root.events, 5000); equal(root.droppedEvents, 1)
    equal(accepted.offerEventID, nil)
    equal(accepted.quest.description, source.quest.description)
    equal(accepted.quest.objectiveText, source.quest.objectiveText)
end)

test("aceite não descarta narrativa nova que a oferta retida não contém", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    local old = model("OFFER"); old.quest.description = "Texto anterior"
    assert(journal.Append("QUEST_OFFERED", A, TIME, old))
    local current = model("OFFER"); current.quest.description = "Texto ainda não registrado"
    assert(journal.Append("QUEST_ACCEPTED", A, TIME, current))
    equal(root.events[2].payload.offerEventID, nil)
    equal(root.events[2].payload.quest.description, "Texto ainda não registrado")
end)

test("leitura histórica aceita aceites completos e objetivos contraditórios sem reescrever", function()
    local n = core()
    local accepted = model("OFFER")
    accepted.quest.description = "Descrição histórica"
    accepted.quest.objectiveText = "Mate 6 Worgs Rocha Negra."
    local completed = model("COMPLETE")
    completed.quest.id = 29078
    completed.objectives = { { index = 1, text = "0/6 Worg da Rocha Negra", kind = "monster",
        fulfilled = 0, required = 6, finished = false } }
    local root = { schemaVersion = 1, nextSequence = 3, droppedEvents = 0, events = {
        { id = A .. ":1", sequence = 1, timestamp = TIME, characterKey = A, type = "QUEST_ACCEPTED", payload = accepted },
        { id = A .. ":2", sequence = 2, timestamp = TIME, characterKey = A, type = "QUEST_COMPLETED", payload = completed },
    } }
    local before = serialize(root)
    assert(n.Schema.ValidateRoot(root))
    assert(n.Journal.Open(root))
    equal(serialize(root), before)
    equal(root.events[2].payload.objectives[1].fulfilled, 0)
    equal(root.events[1].payload.rewards.choices[1].itemID, 501)
end)

test("validador separa escrita enxuta de leitura antiga e verifica referência", function()
    local n = core()
    equal(n.Schema.ValidateInput("QUEST_ACCEPTED", A, TIME, model("OFFER")), nil)
    local accepted = assert(n.QuestDialogue.Acceptance(model("OFFER"), A .. ":38"))
    assert(n.Schema.ValidateInput("QUEST_ACCEPTED", A, TIME, accepted))
    accepted.quest.description = "Não repetir com referência"
    equal(n.Schema.ValidateInput("QUEST_ACCEPTED", A, TIME, accepted), nil)
    accepted.quest.description = nil
    for _, reference in ipairs({ false, 38, "invalid", A .. ":0", A .. ":01", A .. ":9007199254740991", B .. ":1" }) do
        accepted.offerEventID = reference
        equal(n.Schema.ValidateInput("QUEST_ACCEPTED", A, TIME, accepted), nil)
    end
end)

test("aceites novos deduplicam e uma repetição de aceite antigo não duplica o diário", function()
    local n = core()
    local journal, root = n.Journal.Open(nil)
    local source = model("OFFER")
    source.quest.description = "Descrição"
    assert(journal.Append("QUEST_OFFERED", A, TIME, source))
    assert(journal.Append("QUEST_ACCEPTED", A, TIME, source))
    local sequence = root.nextSequence
    local _, code = journal.Append("QUEST_ACCEPTED", A, TIME + 1, source)
    equal(code, "duplicate_quest"); equal(root.nextSequence, sequence)
    -- Reproduzir um aceite legado já armazenado pela 0.4.0.
    root.events[2].payload = roundtrip(source)
    local before = serialize(root)
    journal = assert(n.Journal.Open(root))
    _, code = journal.Append("QUEST_ACCEPTED", A, TIME + 2, source)
    equal(code, "duplicate_quest"); equal(serialize(root), before)
end)

local estimate
test("estimativa reproduzível de tamanho para fixtures sintéticas de missão", function()
    local sample = model("COMPLETE")
    sample.quest.description = string.rep("Os nomes e as memórias da família serão preservados. ", 60)
    sample.quest.objectiveText = string.rep("Recupere os tomos antes da chuva. ", 12)
    sample.quest.rewardText = string.rep("A arquivista lê os nomes em voz alta. ", 24)
    sample.npc = { guid = "Creature-0-123-0-84-777-ABC", creatureID = 777,
        name = "Arquivista", title = "Guardiã dos registros", faction = "Alliance" }
    sample.objectives = { { index = 1, text = "Recupere os tomos", fulfilled = 3, required = 3, finished = true },
        { index = 2, text = "Leia os nomes", fulfilled = 1, required = 1, finished = true } }
    sample = assert(core().QuestDialogue.Snapshot(sample))
    local event = { id = A .. ":1", sequence = 1, timestamp = TIME, type = "QUEST_COMPLETED", characterKey = A,
        payload = sample }
    local bytes = #serialize(event)
    assert(bytes > 5000 and bytes < 15000)
    local textBytes = #sample.quest.description + #sample.quest.objectiveText + #sample.quest.rewardText
    local c = client()
    c.quest.description, c.quest.objectiveText, c.quest.rewardText = sample.quest.description,
        sample.quest.objectiveText, sample.quest.rewardText
    c.quest.progressText = string.rep("Ainda faltam nomes nos tomos do arquivo. ", 24)
    c.start()
    local contextBytes, locationBytes = #serialize(c.saved().events[1]), #serialize(c.saved().events[2])
    c.fire("QUEST_DETAIL"); c.fire("QUEST_ACCEPTED", 101); c.fire("QUEST_PROGRESS")
    c.fire("QUEST_COMPLETE"); c.env.GetQuestReward(1); c.fire("QUEST_TURNED_IN", 101, 450, 120)
    local cycleBytes = 0
    for index = 3, 6 do cycleBytes = cycleBytes + #serialize(c.saved().events[index]) end
    local average = cycleBytes / 4
    local base = (contextBytes + locationBytes) / 2
    estimate = string.format("Fixtures compactas: contexto=%d B, local=%d B; ciclo de quatro eventos de missão=%d B (média=%.2f B).\n" ..
        "5000 eventos: mistura 20%% missões=%.2f MiB; 50%%=%.2f MiB; 100%%=%.2f MiB.\n" ..
        "Fixture enriquecida: %d B/evento (%d B de textos); 5000 semelhantes=%.2f MiB. Estimativas sintéticas; não medição do WoW.",
        contextBytes, locationBytes, cycleBytes, average, (1000 * average + 4000 * base) / 1048576,
        (2500 * average + 2500 * base) / 1048576, 5000 * average / 1048576,
        bytes, textBytes, bytes * 5000 / 1048576)
end)
return estimate
