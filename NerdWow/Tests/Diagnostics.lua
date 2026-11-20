local t=...
local test,equal,core,client=t.test,t.equal,t.core,t.client
local function entry(code)
    return {category="interface",code=code or "interface_error",message="original failure",stack="original stack",
        timestamp=1795101185,version="0.6.2",context={gameEvent="GOSSIP_SHOW",moment="GOSSIP",creatureID=197,stage="show"}}
end
local function recent(c) return c.diagnostics().entries[#c.diagnostics().entries] end
local function failureCount(c)
    local count=0
    for _,entry in ipairs(c.diagnostics().entries) do if entry.code~="npc_title_unavailable" then count=count+1 end end
    return count
end

test("diagnóstico tem raiz própria cópias públicas e compatibilidade sem apagar dados inválidos",function()
    local n=core(); local d,root=n.Diagnostics.Open(nil)
    equal(root.schemaVersion,1); equal(d.GetStatus().total,0)
    local source=entry(); assert(d.Append(source)); source.context.creatureID=999
    local view=d.Recent(5); equal(view[1].context.creatureID,197)
    view[1].message="alterada"; equal(d.Recent()[1].message,"original failure")
    local invalid={schemaVersion=9,entries={entry()},extra="guardar"}; local before=t.serialize(invalid)
    local handle,returned,code=n.Diagnostics.Open(invalid)
    equal(handle,nil); equal(returned,invalid); equal(code,"unsupported_diagnostics"); equal(t.serialize(invalid),before)
    equal(n.Diagnostics.Open(false),nil)
end)

test("diagnóstico retém cinquenta grupos e agrega repetição consecutiva sem crescimento",function()
    local d,root=core().Diagnostics.Open(nil)
    for i=1,55 do local value=entry("failure_"..i); value.timestamp=value.timestamp+i; assert(d.Append(value)) end
    equal(#root.entries,50); equal(root.entries[1].code,"failure_6")
    local same=entry("failure_55"); same.timestamp=same.timestamp+100
    for _=1,1000 do assert(d.Append(same)) end
    equal(#root.entries,50); equal(root.entries[50].count,1001)
    equal(root.entries[50].timestamp,1795101185+55); equal(root.entries[50].lastTimestamp,1795101185+100)
    root.entries[50].count=9007199254740991
    d.Append(same); equal(root.entries[50].count,9007199254740991)
    root.entries[50].count=1001 -- O serializador simplificado do harness usa tostring (14 dígitos).
    same.context.field="payload.name"; d.Append(same); equal(root.entries[50].count,1)
    local resumed=assert(core().Diagnostics.Open(t.roundtrip(root)))
    equal(resumed.Recent(1)[1].context.field,"payload.name")
end)

test("registro de diagnóstico rejeita dados inválidos e descarta extensões de novas entradas",function()
    local d,root=core().Diagnostics.Open(nil)
    local value=entry(); value.payload={secret="não copiar"}; value.context.extra="não copiar"
    assert(d.Append(value)); equal(root.entries[1].payload,nil); equal(root.entries[1].context.extra,nil)
    for _, field in ipairs({"code","message","stack","version"}) do
        value=entry(); value[field]={}
        local before=t.serialize(root)
        equal(d.Append(value),nil); equal(t.serialize(root),before)
    end
    value=entry(); value.context.creatureID=0; equal(d.Append(value),nil)
    value=entry(); value.context.viewportWidth=1280.5; assert(d.Append(value))
end)

test("barreira preserva mensagem textual e stack antes de desenrolar a pilha",function()
    local c=client(); c.start()
    local function original_site() error("original_message_061") end
    local ok,fault=c.namespace.DiagnosticAPI.Try(original_site)
    equal(ok,false); assert(fault.message:find("original_message_061",1,true))
    local originalLocation=assert(fault.message:match("^(.-): original_message_061"))
    assert(fault.stack:find(originalLocation,1,true),fault.stack)
    c.namespace.DiagnosticAPI.Record("interface","interface_error",fault,{gameEvent="GOSSIP_SHOW",stage="show"},
        {moment="GOSSIP",npc={creatureID=197}})
    local saved=recent(c)
    equal(saved.message,fault.message); equal(saved.stack,fault.stack); equal(saved.version,"0.7.2")
    equal(saved.context.gameEvent,"GOSSIP_SHOW"); equal(saved.context.moment,"GOSSIP"); equal(saved.context.creatureID,197)
    equal(saved.timestamp,c.time)
end)

test("erro secreto ou não textual nunca é convertido nem percorrido para persistir",function()
    local c=client(); c.start(); local api=c.namespace.DiagnosticAPI
    c.env.debugstack=function() return c.secret end
    local dangerous=setmetatable({password="não gravar"},{__tostring=function() error("tostring não permitido") end})
    for _, value in ipairs({c.secret,dangerous}) do
        local ok,fault=api.Try(function() error(value) end)
        equal(ok,false); equal(fault.message,nil); equal(fault.stack,nil); equal(fault.redacted,true)
        api.Record("interface","interface_error",fault,{gameEvent=c.secret,creatureID=c.secret,field=c.secret},
            {moment=c.secret,npc=c.secret})
    end
    local saved=recent(c)
    equal(saved.context.gameEvent,nil); equal(saved.context.creatureID,nil); equal(saved.context.moment,nil)
    assert(not t.serialize(c.diagnostics()):find("não gravar",1,true))
    equal(#c.diagnostics().entries,1); equal(saved.count,2)
end)

test("truncamento de erro e stack é limitado sem incluir payloads ou partir UTF-8",function()
    local c=client(); c.start(); local api=c.namespace.DiagnosticAPI
    c.env.debugstack=function() return string.rep("pilha á",2000) end
    local fault=api.Capture(string.rep("á",2000))
    api.Record("interface","interface_error",fault,{gameEvent="GOSSIP_SHOW",password="não copiar",payload={secret=true}})
    local saved=recent(c)
    assert(#saved.message<=2048 and #saved.stack<=8192)
    equal(saved.messageTruncated,true); equal(saved.stackTruncated,true)
    equal(#saved.message%2,0); equal(saved.context.password,nil); equal(saved.context.payload,nil)
end)

test("API de erro mantém aridade e retorno nil de funções observadas",function()
    local c=client(); c.start()
    local ok,a,b,d=c.namespace.DiagnosticAPI.Try(function(x,y) equal(x,5); equal(y,nil); return 1,nil,3 end,5,nil)
    equal(ok,true); equal(a,1); equal(b,nil); equal(d,3)
end)

test("relançamento interno conserva stack original sem confiar em tabelas de erro externas",function()
    local c=client(); c.start(); local api=c.namespace.DiagnosticAPI
    local _,fault=api.Try(function() error("restoration_original") end)
    local originalStack=fault.stack
    local ok,again=api.Try(function() api.Raise(fault,"native_restore_failed") end)
    equal(ok,false); equal(again,fault); equal(again.stack,originalStack)
    equal(api.Code(again),"native_restore_failed")
    local fake={message="não confiar",stack="não confiar"}
    _,again=api.Try(function() error(fake) end)
    equal(again.message,nil); equal(again.redacted,true)
end)

test("fila anterior ao carregamento é limitada e vinculação publica só dados sanitizados",function()
    local c=client(); local api=c.namespace.DiagnosticAPI
    for index=1,55 do api.Record("capture","queued_"..index,{message="erro",stack=c.secret},
        {gameEvent=c.secret,field="payload.name"}) end
    c.start()
    equal(#c.diagnostics().entries,50); equal(c.diagnostics().entries[1].code,"queued_6")
    equal(c.diagnostics().entries[50].code,"queued_55")
    equal(c.diagnostics().entries[1].stack,nil); equal(c.diagnostics().entries[1].context.gameEvent,nil)
end)

test("capturas rejeitadas persistem tipo campo evento e não consomem sequência",function()
    local c=client(); c.start(); local sequence=c.saved().nextSequence
    c.env.UnitLevel=function() return 1.5 end
    c.fire("PLAYER_ENTERING_WORLD")
    local saved=recent(c)
    equal(saved.category,"capture"); equal(saved.code,"invalid_input")
    equal(saved.context.captureType,"CHARACTER_CONTEXT"); equal(saved.context.field,"payload.level")
    equal(saved.context.gameEvent,"PLAYER_ENTERING_WORLD"); equal(c.saved().nextSequence,sequence)
    c.env.UnitLevel=function() return 80 end
    c.fire("ZONE_CHANGED"); equal(c.saved().nextSequence,sequence+1)
end)

test("contexto transitório incompleto vira indisponível com campo e tenta novamente depois",function()
    local c=client(); c.start(); local sequence=c.saved().nextSequence
    c.env.UnitRace=function() return nil,nil,nil end
    c.fire("PLAYER_ENTERING_WORLD")
    equal(c.saved().nextSequence,sequence)
    local saved=recent(c)
    equal(saved.code,"api_unavailable"); equal(saved.context.field,"payload.raceName")
    equal(saved.context.captureType,"CHARACTER_CONTEXT")
    c.env.UnitRace=function() return "Humano","Human",1 end
    c.fire("ZONE_CHANGED"); equal(c.saved().nextSequence,sequence+1)
    local diagnosticsBefore=t.serialize(c.diagnostics()); local messagesBefore=#c.messages
    c.zone=""; sequence=c.saved().nextSequence; c.fire("ZONE_CHANGED")
    equal(c.saved().nextSequence,sequence); equal(t.serialize(c.diagnostics()),diagnosticsBefore)
    equal(#c.messages,messagesBefore)
    c.zone="Zona recuperada"; c.fire("ZONE_CHANGED"); equal(c.saved().nextSequence,sequence+1)
end)

test("falha da API de captura retém erro original com stack e contexto do jogo",function()
    local c=client(); c.start()
    c.env.UnitName=function() error("unit_name_original_failure") end
    c.fire("PLAYER_ENTERING_WORLD")
    local saved=recent(c)
    equal(saved.code,"api_error"); assert(saved.message:find("unit_name_original_failure",1,true))
    assert(saved.stack and saved.stack~=""); equal(saved.context.captureType,"CHARACTER_CONTEXT")
    equal(saved.context.gameEvent,"PLAYER_ENTERING_WORLD")
end)

test("deduplicações normais do diário não geram falha de diagnóstico",function()
    local c=client(); c.start(); c.fire("ZONE_CHANGED"); c.fire("GOSSIP_SHOW"); c.fire("GOSSIP_SHOW")
    equal(failureCount(c),0)
    c.namespace.DiagnosticAPI.Record("capture","duplicate_quest",{message="não registrar"})
    equal(failureCount(c),0)
end)

test("validadores identificam caminhos de missão gossip e envelope sem alterar esquema",function()
    local n=core()
    local _,code,path=n.Schema.ValidateInput("CHARACTER_CONTEXT","bad",1,{})
    equal(code,"invalid_input"); equal(path,"characterKey")
    _,code,path=n.Schema.ValidateInput("GOSSIP_VIEWED","Player-1-ABC",0,{moment="GOSSIP",text="Olá"})
    equal(path,"timestamp")
    _,code,path=n.Schema.ValidateInput("QUEST_OFFERED","Player-1-ABC",1,{moment="OFFER",quest={id=10},
        rewards={choices={{index=1,quality=9}}}})
    equal(path,"payload.rewards.choices[1].quality")
    _,code,path=n.Schema.ValidateInput("GOSSIP_VIEWED","Player-1-ABC",1,{moment="GOSSIP",text="Olá",
        options={{index=1,optionID="bad"}}})
    equal(path,"payload.options[1].optionID")
    _,code,path=n.Schema.ValidateInput("GOSSIP_VIEWED","Player-1-ABC",1,{moment="GOSSIP",text="Olá",npc={creatureID=0}})
    equal(path,"payload.npc.creatureID")
    equal(n.Schema.VERSION,1)
end)

test("fala da Major sem opções e textos vazios opcionais continuam capturáveis",function()
    local c=client(); c.start()
    c.npc={guid="Creature-0-3886-0-22-197-00007C71E4",name="Major Belmonte",faction="Alliance"}
    c.gossip={text="Olá, cidadã! Você me parece bem forte.",options={},available={},active={}}
    c.fire("GOSSIP_SHOW")
    local event=c.saved().events[#c.saved().events]
    equal(event.type,"GOSSIP_VIEWED"); equal(event.payload.npc.creatureID,197)
    equal(failureCount(c),0)
    c.quest.description=""; c.quest.objectiveText=""; c.fire("QUEST_DETAIL")
    equal(c.saved().events[#c.saved().events].type,"QUEST_OFFERED"); equal(failureCount(c),0)
end)

test("novos campos ausentes são silenciosos mas valores presentes inválidos avisam",function()
    local c=client(nil,{schemaVersion=1,minimapHidden=true,minimapAngle=30})
    c.fire("ADDON_LOADED","NerdWow")
    equal(#c.messages,0); equal(c.settings().dialogEnabled,true); equal(c.settings().minimapHidden,true)
    c=client(nil,{schemaVersion=1,minimapHidden=true,minimapAngle=30,dialogEnabled="true"})
    c.fire("ADDON_LOADED","NerdWow")
    equal(#c.messages,1); assert(c.messages[1]:find("interface de conversa",1,true))
end)

test("comando diagnóstico mostra cinco grupos seguros e o aviso da interface continua único",function()
    local c=client(); c.start()
    for i=1,7 do c.namespace.DiagnosticAPI.Record("capture","test_"..i,{message="|Hfake|h[texto]|h\nfalha"},
        {gameEvent="GOSSIP_SHOW",captureType="GOSSIP_VIEWED",field="payload.text"}) end
    local before=#c.messages; c.command("diagnostico"); equal(#c.messages,before+6)
    assert(c.messages[before+2]:find("test_7",1,true)); assert(c.messages[before+6]:find("test_3",1,true))
    assert(c.messages[before+2]:find("||Hfake",1,true))
    c.command("ajuda"); assert(c.messages[#c.messages]:find("/nerdwow diagnostico",1,true))
end)

test("diagnóstico com esquema futuro é preservado e bloqueia apenas o próprio registro",function()
    local c=client(); local future={schemaVersion=99,entries={"guardar"}}; c.env.NerdWow_Diagnostics=future
    local before=t.serialize(future); c.start(); c.command("diagnostico")
    equal(c.env.NerdWow_Diagnostics,future); equal(t.serialize(future),before)
    equal(#c.saved().events,2); assert(c.messages[#c.messages]:find("não suportada",1,true))
end)

test("diagnóstico persiste cada falha de interface mesmo com aviso já emitido",function()
    local c=client(); c.start()
    c.namespace.ConversationPlatform.CanPresent=function() return true end
    c.namespace.ConversationView.New=function() error("render_original_061") end
    c.fire("GOSSIP_SHOW"); c.flush()
    local first=recent(c)
    equal(first.category,"interface"); equal(first.code,"interface_error")
    assert(first.message:find("render_original_061",1,true)); assert(first.stack)
    equal(first.context.gameEvent,"GOSSIP_SHOW"); equal(first.context.moment,"GOSSIP")
    equal(first.context.creatureID,777)
    c.command("dialogo"); c.command("dialogo"); c.flush()
    assert(#c.diagnostics().entries>=1)
    local total=0
    for _,record in ipairs(c.diagnostics().entries) do if record.code~="npc_title_unavailable" then total=total+record.count end end
    equal(total,2)
    local warnings=0
    for _, message in ipairs(c.messages) do
        if message:find("devolveu",1,true) then warnings=warnings+1; assert(message:find("/nerdwow diagnostico",1,true)) end
    end
    equal(warnings,1)
end)

test("zona vazia ou ausente na entrada do mundo é silenciosa e capturada no próximo evento",function()
    for _, mode in ipairs({"empty","nil"}) do
        local c=client(); c.zone=mode=="empty" and "" or nil
        c.start()
        equal(#c.saved().events,1); equal(c.saved().events[1].type,"CHARACTER_CONTEXT")
        equal(#c.messages,0); equal(#c.diagnostics().entries,0)
        local nextSequence=c.saved().nextSequence
        c.zone="Vila Norte"; c.fire("ZONE_CHANGED_NEW_AREA")
        equal(c.saved().nextSequence,nextSequence+1)
        equal(c.saved().events[2].type,"LOCATION_CHANGED"); equal(c.saved().events[2].payload.zone,"Vila Norte")
        equal(#c.messages,0); equal(#c.diagnostics().entries,0)
    end
end)

test("silêncio da zona não elimina histórico nem esconde erro real de captura posterior",function()
    local c=client(); c.start()
    c.namespace.DiagnosticAPI.Record("interface","interface_error",{message="FontString:SetText(): Font not set"})
    local before=t.serialize(c.diagnostics())
    c.zone=""; c.fire("ZONE_CHANGED"); equal(t.serialize(c.diagnostics()),before); equal(#c.messages,0)
    c.zone="Vila Norte"; c.subZone=nil; c.fire("ZONE_CHANGED")
    equal(recent(c).code,"api_unavailable"); equal(recent(c).context.field,"payload.subZone")
    equal(#c.messages,1)
    c.zone=c.secret; c.fire("ZONE_CHANGED")
    equal(recent(c).code,"secret_value"); equal(recent(c).context.field,"payload.zone")
    c.zone=false; c.subZone=""; c.fire("ZONE_CHANGED")
    equal(recent(c).code,"invalid_input"); equal(recent(c).context.field,"payload.zone")
    c.env.GetZoneText=function() error("location_original_error") end
    c.fire("ZONE_CHANGED")
    equal(recent(c).code,"api_error"); assert(recent(c).message:find("location_original_error",1,true))
    assert(recent(c).stack); equal(recent(c).context.captureType,"LOCATION_CHANGED")
end)

test("comando fontes cobre dezoito combinações e persiste resultados sem mudar diário ou configuração",function()
    local c=client(); c.start()
    local journal,settings=t.serialize(c.saved()),t.serialize(c.settings())
    c.command(" FONTES ")
    equal(#c.messages,7); equal(#c.fontCalls,22); equal(#c.diagnostics().entries,18)
    equal(#c.fontFrames,1); equal(c.fontFrames[1].alpha,0); equal(c.fontFrames[1].mouse,false)
    local paths,combinations={},{}
    for index,call in ipairs(c.fontCalls) do
        if index>4 then
        equal(call.size,21)
        local flags=call.flags==nil and "nil" or '"'..call.flags..'"'
        local key=call.path..":"..flags; assert(not combinations[key]); combinations[key]=true; paths[call.path]=true
        local entry=c.diagnostics().entries[index-4]
        equal(entry.code,"font_test"); equal(entry.category,"interface"); equal(entry.version,"0.7.2")
        equal(entry.context.gameEvent,"COMMAND_FONTES"); equal(entry.context.stage,"font_probe")
        assert(entry.message:find("font="..call.path.."; flags="..flags.."; size=21; success=true; phase=immediate",1,true))
        assert(entry.message:find("; applied=true",1,true))
        end
    end
    local count=0; for _ in pairs(paths) do count=count+1 end; equal(count,6)
    assert(paths["Fonts\\FRIZQT__.TTF"]); assert(paths["Fonts\\ARIALN.TTF"])
    for index=2,7 do assert(c.messages[index]:find('nil=OK | ""=OK | OUTLINE=OK',1,true)) end
    equal(t.serialize(c.saved()),journal); equal(t.serialize(c.settings()),settings)
    c.command("ajuda"); assert(c.messages[8]:find("/nerdwow fontes",1,true))
    local handle=assert(c.namespace.Diagnostics.Open(t.roundtrip(c.diagnostics())))
    equal(handle.GetStatus().total,18)
end)

test("teste de fontes distingue flags recusadas e exceções sem aplicar fallback ou interromper combinações",function()
    local c=client(); c.start()
    c.rejectFont=function(path,size,flags)
        if flags=="OUTLINE" and path:find("Cinzel-Bold",1,true) then error("probe_original_error") end
        return flags==""
    end
    c.command("fontes")
    equal(#c.fontCalls,22); equal(#c.diagnostics().entries,18)
    local rejected,exceptions=0,0
    for index,entry in ipairs(c.diagnostics().entries) do
        local call=c.fontCalls[index+4]
        if call.flags=="" then
            rejected=rejected+1; assert(entry.message:find('flags=""; size=21; success=false',1,true))
        elseif entry.message:find("probe_original_error",1,true) then
            exceptions=exceptions+1; assert(entry.stack); assert(entry.message:find("success=false",1,true))
        else assert(entry.message:find("success=true",1,true)) end
    end
    equal(rejected,6); equal(exceptions,1)
    assert(c.messages[3]:find('nil=OK | ""=false (verificando) | OUTLINE=erro',1,true))
end)

test("teste repete chamadas reais reutiliza probe oculto e respeita retenção existente",function()
    local c=client(); c.start()
    c.namespace.DiagnosticAPI.Record("interface","interface_error",{message="histórico preservado"})
    c.command("fontes"); equal(c.diagnostics().entries[1].message,"histórico preservado")
    c.command("fontes"); c.command("fontes")
    equal(#c.fontFrames,1); equal(#c.fontCalls,58); equal(#c.diagnostics().entries,50)
    equal(c.diagnostics().schemaVersion,1)
end)

test("diagnóstico bloqueado não impede teste de fontes nem altera raiz preservada",function()
    local c=client()
    c.env.NerdWow_Diagnostics={schemaVersion=9,entries={},extra="guardar"}
    local before=t.serialize(c.env.NerdWow_Diagnostics)
    c.start(); c.command("fontes")
    equal(#c.fontCalls,22); equal(t.serialize(c.env.NerdWow_Diagnostics),before)
    assert(c.messages[#c.messages]:find("Diagnóstico indisponível",1,true))
end)

test("comando fontes exige inicialização e funciona com diário suspenso",function()
    local c=client({schemaVersion=99})
    c.command("fontes"); equal(c.fontCalls,nil); assert(c.messages[1]:find("ainda não inicializado",1,true))
    c.start(); c.command("fontes")
    equal(#c.fontCalls,22); equal(c.saved().schemaVersion,99)
end)

test("fontes registra false imediato e identidade aplicada depois em dezoito probes independentes",function()
    local c=client(); c.deferFont=true; c.start()
    equal(#c.fontCalls,4) -- Preload no ADDON_LOADED, antes da primeira conversa.
    local journal,settings=t.serialize(c.saved()),t.serialize(c.settings())
    c.command("fontes"); equal(#c.fontCalls,22); equal(#c.diagnostics().entries,18); equal(#c.messages,7)
    local falseCount=0
    for _,record in ipairs(c.diagnostics().entries) do
        if record.message:find("NerdWow\\Fonts\\",1,true) then
            falseCount=falseCount+1; assert(record.message:find("success=false",1,true))
            assert(record.message:find("; applied=false",1,true))
        end
    end
    equal(falseCount,12)
    for _=1,52 do c.flush() end
    equal(#c.diagnostics().entries,36); equal(#c.messages,14)
    for index=19,36 do
        local record=c.diagnostics().entries[index]
        equal(record.code,"font_test_loaded"); equal(record.context.stage,"font_probe_loaded")
        assert(record.message:find("; ready=true",1,true)); assert(record.message:find("; applied=true",1,true))
        assert(record.message:find("; width=",1,true)); assert(record.message:find("; height=",1,true))
        if record.message:find("NerdWow\\Fonts\\",1,true) then assert(record.message:find("success=false",1,true)) end
    end
    for index=9,14 do assert(c.messages[index]:find('nil=aplicada | ""=aplicada | OUTLINE=aplicada',1,true)) end
    equal(t.serialize(c.saved()),journal); equal(t.serialize(c.settings()),settings); equal(#c.timers,0)
end)

test("repetir fontes cancela observações antigas e reutiliza probes sem resultado misturado",function()
    local c=client(); c.deferFont=true; c.start()
    c.command("fontes"); c.command("fontes")
    for _=1,52 do c.flush() end
    equal(#c.fontFrames,1); equal(#c.fontCalls,40); equal(#c.diagnostics().entries,50)
    local delayedCount=0
    for _,record in ipairs(c.diagnostics().entries) do
        if record.code=="font_test_loaded" then delayedCount=delayedCount+1; assert(record.message:find("; applied=true",1,true)) end
    end
    equal(delayedCount,18); equal(#c.messages,21); equal(#c.timers,0)
end)

test("diagnóstico tardio distingue não aplicação de fonte aplicada sem métrica",function()
    for _,zero in ipairs({false,true}) do
        local c=client(); c.start()
        if zero then
            c.namespace.FontAPI.Test(function() end)
            local font=c.fontFrames[1].label
            font.GetUnboundedStringWidth=function() return 0 end
            font.GetStringHeight=function() return 0 end
        else
            c.rejectFont=function(path) return path:find("NerdWow\\Fonts\\",1,true)~=nil end
            c.command("fontes")
        end
        for _=1,52 do c.flush() end
        local nonApplied,noMetrics=0,0
        for _,record in ipairs(c.diagnostics().entries) do
            if record.code=="font_test_loaded" then
                if record.message:find("; applied=false",1,true) then nonApplied=nonApplied+1 end
                if record.message:find("; applied=true",1,true) and record.message:find("; ready=false",1,true) then noMetrics=noMetrics+1 end
            end
        end
        if zero then equal(noMetrics,1); equal(nonApplied,0) else equal(nonApplied,12); equal(noMetrics,0) end
    end
end)
