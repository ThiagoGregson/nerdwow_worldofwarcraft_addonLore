local t=...
local test,equal,core,client=t.test,t.equal,t.core,t.client
local function model(moment)
    return { moment=moment or "GOSSIP", text="Você sente o cheiro, não sente? Cinza velha.",
        npc={name="Arquivista Velann",title="Guardiã dos registros",faction="Horde",creatureID=777},
        location={mapID=2395,zone="Floresta do Canto Eterno",subZone="Corredor dos Arquivistas"},
        activeQuests={{index=1,questID=201,title="Um registro incompleto",isComplete=false},
            {index=2,questID=202,title="Os nomes recuperados",isComplete=true}},
        availableQuests={{index=1,questID=203,title="Os nomes nas margens"}},
        options={{index=1,optionID=7001,orderIndex=0,text="Conte-me sua história.",icon=134400,status=0}} }
end
local function controller(n)
    n=n or core()
    local state={enabled=true,canPresent=true,source=model(),queued={},selected={},reports=0,visible=false,native=false,reads=0}
    local view={}
    function view.Hide() state.visible=false; state.typing=false; state.keyboard=false end
    function view.Show(value)
        if state.failRender then error("render failure") end
        state.view=value; state.visible=true; state.typing=true; state.keyboard=true
    end
    function view.Complete() state.typing=false end
    function view.IsTyping() if state.failTyping then error("typing failure") end; return state.typing end
    local platform={}
    function platform.CanPresent() return state.canPresent end
    function platform.Defer(callback) state.queued[#state.queued+1]=callback; return not state.noDefer end
    function platform.RestoreNative() state.native=false; if state.failRestore then error("restore failure") end end
    function platform.TakeNative(moment)
        state.native=true; state.nativeMoment=moment
        if state.failTake then error("partial native failure") end
    end
    function platform.Close(moment) state.closed=moment end
    function platform.Select(entry,moment)
        if state.failAction then error("action failure") end
        state.nativeAtSelect=state.native
        state.selected[#state.selected+1]={entry=entry,moment=moment}
    end
    local opts={GetModel=function() state.reads=state.reads+1; return state.source end,
        IsEnabled=function() return state.enabled end, Platform=platform,
        View={New=function(callbacks) state.callbacks=callbacks; return view end},
        Report=function() state.reports=state.reports+1 end}
    state.options=opts; state.ctrl=n.ConversationController.New(opts)
    function state.flush() local q=state.queued; state.queued={}; for _, callback in ipairs(q) do callback() end end
    return state
end
local function nativeFrame(children)
    local f={alpha=.75,mouse=true,keyboard=false,children=children or {},scripts={}}
    local function writable()
        f.setterCalls=(f.setterCalls or 0)+1
        assert(not f.protected and not f.forbidden and not f.stateLocked,"setter nativo restrito")
    end
    function f:IsProtected() return self.protected or false end
    function f:IsForbidden() return self.forbidden or false end
    function f:CanChangeProtectedState() return not self.protected and not self.forbidden and not self.stateLocked end
    function f:GetAlpha() return self.alpha end
    function f:SetAlpha(value) writable(); self.alpha=value end
    function f:IsMouseEnabled() return self.mouse end
    function f:EnableMouse(value) writable(); if self.failDisable and not value then error("mouse failure") end; self.mouse=value end
    function f:IsKeyboardEnabled() return self.keyboard end
    function f:EnableKeyboard(value) writable(); self.keyboard=value end
    function f:GetChildren() return unpack(self.children) end
    function f:HookScript(name,callback) writable(); self.scripts[name]=callback end
    return f
end
local function platform(n)
    local state={combat=false,focus=false,ctrl=false,alt=false,shift=false,secret={}}
    local child=nativeFrame(); child.keyboard=true
    local sibling=nativeFrame(); sibling.mouse=false
    local root=nativeFrame({child,sibling})
    local env={type=type,ipairs=ipairs,pcall=pcall,error=error,
        UIParent={},GossipFrame=root,QuestFrame=nativeFrame(),C_Timer={After=function(_,callback) callback() end},
        issecretvalue=function(value) return value==state.secret end,
        InCombatLockdown=function() return state.combat end,
        GetCurrentKeyBoardFocus=function() return state.focus end,
        IsControlKeyDown=function() return state.ctrl end,IsAltKeyDown=function() return state.alt end,
        IsShiftKeyDown=function() return state.shift end,C_GossipInfo={}}
    for _, name in ipairs({"SelectOption","SelectOptionByIndex","SelectAvailableQuest","SelectActiveQuest","CloseGossip"}) do
        local key=name; env.C_GossipInfo[key]=function(value) state.action=key; state.value=value end
    end
    env.SelectAvailableQuest=function(value) state.action="greetingAvailable"; state.value=value end
    env.SelectActiveQuest=function(value) state.action="greetingActive"; state.value=value end
    env.CloseQuest=function() state.action="closeQuest" end
    t.loadModule("Integration/Conversation.lua",n,env)
    state.api=n.ConversationPlatform; state.root=root; state.child=child; state.sibling=sibling; state.env=env
    return state
end

test("temas priorizam UiMapID depois facção do NPC e Neutro sem ler APIs",function()
    local themes=core().DialogueThemes
    for _, mapID in ipairs({94,95,110,122,2393,2395,2424,2432,2443,2537,2565,2566,2594,2605}) do
        equal(themes.Resolve({mapID=mapID},{faction="Alliance"}).key,"quelthalas")
    end
    equal(themes.Resolve({mapID=84},{faction="Alliance"}).key,"alliance")
    equal(themes.Resolve(nil,{faction="Horde"}).key,"horde")
    equal(themes.Resolve(nil,nil).key,"neutral")
    equal(themes.Resolve({zone="Lua-prata"},{faction="Neutral"}).key,"neutral")
    equal(themes.Resolve({mapID=1267},{faction="Alliance"}).key,"alliance")
    local theme=themes.Resolve({mapID=2395}); equal(theme.accent,"e0a33f"); equal(theme.glow,"ffd38a")
    theme.accent="000000"; equal(themes.Resolve({mapID=2395}).accent,"e0a33f")
end)

test("apresentação distingue tipos e identifica ações sem alterar o modelo",function()
    local n=core(); local source=model(); local before=t.serialize(source)
    local view=assert(n.Conversation.Build(source))
    equal(view.entries[1].kind,"active"); equal(view.entries[2].kind,"complete")
    equal(view.entries[3].kind,"available"); equal(view.entries[4].kind,"conversation")
    equal(view.entries[1].value,201); equal(view.entries[4].value,7001); equal(view.entries[4].action,"OPTION_ID")
    equal(view.entries[4].number,4); equal(view.theme.key,"quelthalas")
    equal(t.serialize(source),before)
    view=assert(n.Conversation.Build(model("GREETING")))
    equal(view.entries[3].value,1); equal(view.entries[1].value,1); equal(view.entries[4].enabled,false)
end)

test("opções ordenam identificadores reais e desabilitam entradas ambíguas",function()
    local n=core(); local source=model()
    source.options={{index=1,orderIndex=7,text="Sétima"},{index=2,orderIndex=0,text="Primeira"},
        {index=3,optionID=9,text="Sem ordem"},{index=4,optionID=10,text="Bloqueada",status=2}}
    local view=n.Conversation.Build(source)
    equal(view.entries[4].text,"Primeira"); equal(view.entries[4].value,0); equal(view.entries[4].action,"OPTION_INDEX")
    equal(view.entries[5].value,7); equal(view.entries[7].enabled,false)
    source.options={{index=1,optionID=7,orderIndex=0,text="A"},{index=2,optionID=7,orderIndex=0,text="B"}}
    view=n.Conversation.Build(source); equal(view.entries[4].enabled,false); equal(view.entries[5].enabled,false)
    source.options={{index=1,optionID=7},{index=2,text="Sem ID"}}
    view=n.Conversation.Build(source); equal(view.entries[4].enabled,false); equal(view.entries[5].enabled,false)
end)

test("teclas reservadas mapeiam números espaço em fala e Escape",function()
    local map=core().Conversation.Key
    for index=1,9 do local action,value=map(tostring(index),false); equal(action,"choose"); equal(value,index) end
    equal(map("SPACE",true),"complete"); equal(map("SPACE",false),nil); equal(map("ESCAPE",false),"close")
    for _, key in ipairs({"0","A","ENTER","NUMPAD1","F1","SHIFT"}) do equal(map(key,true),nil) end
end)

test("fala avança UTF-8 com pausas sem bytes parciais e completa sem regressão",function()
    local speech=assert(core().Conversation.NewSpeech("Olá 世界"))
    equal(speech.GetText(),""); equal(speech.IsComplete(),false)
    equal(speech.Advance(.02),"O"); equal(speech.Advance(.02),"Ol"); equal(speech.Advance(.02),"Olá")
    local before=speech.GetText(); local _,changed=speech.Advance(0); equal(changed,false); equal(speech.GetText(),before)
    equal(speech.Complete(),"Olá 世界"); equal(speech.IsComplete(),true)
    equal(speech.Advance(.001),"Olá 世界")
    equal(core().Conversation.NewSpeech(5),nil)
    equal(core().Conversation.NewSpeech("").IsComplete(),true)
end)

test("fala preserva marcações WoW e evita revelar textura ou hyperlink pela metade",function()
    local text="|cffff0000Olá|r |T123:16|t |Hitem:123|h[Item]|h"
    local speech=core().Conversation.NewSpeech(text)
    for _=1,100 do
        local visible=speech.Advance(.02)
        if visible:find("|T",1,true) then assert(visible:find("|t",1,true)) end
        if visible:find("|H",1,true) then assert(visible:find("[Item]|h",1,true)) end
    end
    equal(speech.GetText(),text)
    local _,changed=speech.Advance(math.huge); equal(changed,false)
    _,changed=speech.Advance(-1); equal(changed,false)
end)

test("fala longa atualiza só quando há caracteres novos sem truncamento",function()
    local text=string.rep("Lore ",10000)
    local speech=core().Conversation.NewSpeech(text)
    local changes=0
    for _=1,1000 do local _,changed=speech.Advance(.001); if changed then changes=changes+1 end end
    assert(changes<=60); assert(#speech.GetText()<=60)
    equal(speech.Complete(),text)
end)

test("layout mantém proporções e texto legível em resoluções e escalas diferentes",function()
    local c=core().Conversation
    for _, dimensions in ipairs({{1280,720},{1920,1080},{2560,1440},{3440,1440},{1366/.8,768/.8}}) do
        local layout=assert(c.Layout(dimensions[1],dimensions[2]))
        assert(layout.speechSize>=22); assert(layout.contentWidth<dimensions[1])
        equal(layout.top,dimensions[2]*.09); assert(layout.maximumBottom<=dimensions[2]*.5)
    end
    equal(c.Layout(0,720),nil); equal(c.Layout(math.huge,720),nil)
end)

test("configuração de diálogo recupera apenas campo inválido e preserva escolha persistida",function()
    local n=core()
    for _, invalid in ipairs({"true",1,{}}) do
        local root={schemaVersion=1,minimapHidden=true,minimapAngle=40,dialogEnabled=invalid,extra="guardar"}
        local settings,returned,repaired=n.Settings.Open(root)
        equal(returned,root); equal(#repaired,1); equal(repaired[1],"dialogEnabled")
        equal(settings.Get().dialogEnabled,true); equal(root.extra,"guardar"); equal(root.minimapAngle,40)
    end
    local root={schemaVersion=1,minimapHidden=false,minimapAngle=20}
    local settings,_,repaired=n.Settings.Open(root); equal(#repaired,0)
    equal(settings.ToggleDialog(),false)
    local resumed=n.Settings.Open(t.roundtrip(root)); equal(resumed.Get().dialogEnabled,false)
    local copy=resumed.Get(); copy.dialogEnabled=true; equal(resumed.Get().dialogEnabled,false)
end)

test("controlador só lê modelo pronto e libera a apresentação sem fechar APIs ao desligar",function()
    local s=controller()
    s.ctrl.Handle("GOSSIP_SHOW"); equal(s.visible,false); equal(s.reads,0)
    s.flush(); equal(s.visible,true); equal(s.native,true); equal(s.reads,1)
    equal(s.view.text,s.source.text)
    s.enabled=false; s.ctrl.Toggle(); equal(s.visible,false); equal(s.native,false); equal(s.closed,nil)
    s.enabled=true; s.ctrl.Toggle(); s.flush(); equal(s.visible,true)
end)

test("modelo vazio deixa a Blizzard disponível e nova fotografia pode abrir cinema",function()
    local s=controller(); s.source={moment="GOSSIP",text=" \n",options={}}
    s.ctrl.Refresh(); equal(s.visible,false); equal(s.native,false); equal(s.reports,0)
    s.source={moment="GOSSIP",text="Uma história sem outros campos disponíveis."}
    s.ctrl.Refresh(); equal(s.visible,true); equal(s.view.npc,nil); equal(s.view.location,nil)
end)

test("clique e número escolhem a mesma entrada uma vez e missão devolve nativa antes da ação",function()
    local s=controller(); s.ctrl.Refresh()
    s.callbacks.Choose(4); s.callbacks.Choose(4)
    equal(#s.selected,1); equal(s.selected[1].entry.action,"OPTION_ID")
    s.ctrl.Refresh(); equal(s.ctrl.Key("4"),true); equal(#s.selected,2)
    s.ctrl.Refresh(); s.ctrl.Choose(3)
    equal(s.nativeAtSelect,false); equal(s.visible,false); equal(s.selected[3].entry.value,203)
    s.ctrl.Refresh(); s.ctrl.Key("SPACE"); equal(s.typing,false)
    equal(s.ctrl.Key("SPACE"),false); equal(s.ctrl.Key("F"),false)
    s.ctrl.Key("ESCAPE"); equal(s.closed,"GOSSIP"); equal(s.visible,false); equal(s.keyboard,false)
end)

test("mudança de modelo invalida cliques e callbacks adiados antigos",function()
    local s=controller(); s.ctrl.Refresh(); local old=s.callbacks
    s.ctrl.Handle("GOSSIP_SHOW"); s.source=model("GREETING")
    old.Choose(4); equal(#s.selected,0)
    s.ctrl.Handle("QUEST_DETAIL"); s.flush(); equal(s.visible,false)
    s.ctrl.Refresh(); equal(s.view.moment,"GREETING")
    old.Close(); equal(s.closed,nil)
end)

test("missões popups combate e saída encerram cinema sem encerrar conversa indevidamente",function()
    local s=controller()
    for _, event in ipairs({"QUEST_DETAIL","QUEST_PROGRESS","QUEST_COMPLETE","GOSSIP_CONFIRM","GOSSIP_ENTER_CODE",
        "GOSSIP_CLOSED","QUEST_FINISHED","PLAYER_LEAVING_WORLD","PLAYER_REGEN_DISABLED"}) do
        s.ctrl.Refresh(); s.ctrl.Handle(event); equal(s.visible,false); equal(s.native,false); equal(s.closed,nil)
    end
    s.canPresent=false; s.ctrl.Handle("GOSSIP_SHOW"); s.flush(); equal(s.visible,false); equal(s.reports,0)
end)

test("falha de renderização ou substituição parcial restaura nativa e avisa só uma vez",function()
    for _, field in ipairs({"failRender","failTake","noDefer"}) do
        local s=controller(); s[field]=true
        s.ctrl.Handle("GOSSIP_SHOW"); s.flush()
        equal(s.visible,false); equal(s.native,false); equal(s.reports,1)
        s[field]=false; s.ctrl.Handle("GOSSIP_SHOW"); s.flush(); equal(s.visible,false); equal(s.reports,1)
        s.ctrl.Toggle(); s.flush(); equal(s.visible,true)
        s.failRender=true; s.ctrl.Refresh(); equal(s.reports,1)
    end
end)

test("erros de ação e de progressão não escapam e devolvem a conversa à Blizzard",function()
    local s=controller(); s.ctrl.Refresh(); s.failAction=true; s.ctrl.Choose(4)
    equal(s.reports,1); equal(s.visible,false); equal(s.native,false)
    s=controller(); s.ctrl.Refresh(); s.failTyping=true
    equal(s.ctrl.Key("SPACE"),false); equal(s.visible,false); equal(s.reports,1)
    s=controller(); s.ctrl.Refresh(); s.failRestore=true; s.ctrl.Handle("GOSSIP_CLOSED")
    equal(s.visible,false); equal(s.reports,1)
end)

test("substituição nativa preserva estados de filhos sem esconder ou trocar scripts",function()
    local p=platform(core()); local shows=0
    p.api.TakeNative("GOSSIP",function() shows=shows+1 end)
    equal(p.root.alpha,0); equal(p.root.mouse,false); equal(p.child.mouse,false); equal(p.child.keyboard,false)
    p.root.scripts.OnShow(); equal(shows,1)
    p.api.RestoreNative(); equal(p.root.alpha,.75); equal(p.root.mouse,true)
    equal(p.child.mouse,true); equal(p.child.keyboard,true); equal(p.sibling.mouse,false)
    p.root.scripts.OnShow(); equal(shows,1)
end)

test("substituição recusa protegido proibido e combate antes de alterar qualquer filho",function()
    for _, field in ipairs({"protected","forbidden"}) do
        local p=platform(core()); p.child[field]=true
        equal(pcall(p.api.TakeNative,"GOSSIP"),false)
        equal(p.root.alpha,.75); equal(p.root.mouse,true); equal(p.child.mouse,true)
    end
    local p=platform(core()); p.combat=true
    equal(p.api.CanPresent(),false); equal(pcall(p.api.TakeNative,"GOSSIP"),false); equal(p.root.alpha,.75)
end)

test("falha parcial da API nativa mantém transação restaurável",function()
    local p=platform(core()); p.child.failDisable=true
    equal(pcall(p.api.TakeNative,"GOSSIP"),false); equal(p.root.mouse,false)
    p.api.RestoreNative(); equal(p.root.mouse,true); equal(p.child.mouse,true); equal(p.root.alpha,.75)
end)

test("adaptador usa APIs oficiais distintas de gossip e saudação e respeita foco do chat",function()
    local p=platform(core())
    for _, spec in ipairs({{"OPTION_ID","SelectOption"},{"OPTION_INDEX","SelectOptionByIndex"},
        {"AVAILABLE","SelectAvailableQuest"},{"ACTIVE","SelectActiveQuest"}}) do
        p.api.Select({action=spec[1],value=7},"GOSSIP"); equal(p.action,spec[2]); equal(p.value,7)
    end
    p.api.Select({action="AVAILABLE",value=2},"GREETING"); equal(p.action,"greetingAvailable")
    p.api.Select({action="ACTIVE",value=3},"GREETING"); equal(p.action,"greetingActive")
    p.api.Close("GREETING"); equal(p.action,"closeQuest"); p.api.Close("GOSSIP"); equal(p.action,"CloseGossip")
    equal(p.api.KeyAllowed(),true)
    for _, field in ipairs({"focus","ctrl","alt","shift","combat"}) do
        p[field]=true; equal(p.api.KeyAllowed(),false); p[field]=false
    end
    p.focus=p.secret; equal(pcall(p.api.KeyAllowed),false)
end)

local function wire(c)
    local s={visible=false}
    c.namespace.ConversationPlatform.CanPresent=function() return not c.inCombat end
    c.namespace.ConversationPlatform.TakeNative=function() s.native=true end
    c.namespace.ConversationPlatform.RestoreNative=function() s.native=false end
    c.namespace.ConversationView.New=function(callbacks)
        s.callbacks=callbacks
        return {Show=function(view) s.view=view; s.visible=true end,Hide=function() s.visible=false end,
            Complete=function() end,IsTyping=function() return true end}
    end
    return s
end
test("comando diálogo persiste preferência e atualiza interface sem inserir eventos",function()
    local c=client(); local ui=wire(c)
    c.command("dialogo"); assert(c.messages[#c.messages]:find("não inicializada",1,true))
    c.start(); c.fire("GOSSIP_SHOW"); c.flush(); equal(ui.visible,true)
    local count=#c.saved().events
    c.command("dialogo"); equal(c.settings().dialogEnabled,false); equal(ui.visible,false); equal(ui.native,false)
    c.command("dialogo"); c.flush(); equal(c.settings().dialogEnabled,true); equal(ui.visible,true)
    equal(#c.saved().events,count)
    c.command("ajuda"); assert(c.messages[#c.messages]:find("/nerdwow dialogo",1,true))
end)

test("composição consome modelo capturado e seleção permanece no observador existente",function()
    local c=client(); local ui=wire(c); c.start(); c.fire("GOSSIP_SHOW"); c.flush()
    equal(ui.view.text,c.namespace.GossipDialogs.GetCurrent().text)
    ui.callbacks.Choose(3)
    equal(c.saved().events[#c.saved().events].type,"GOSSIP_OPTION_SELECTED")
    c.fire("QUEST_DETAIL"); equal(ui.visible,false); equal(ui.native,false)
    equal(c.saved().events[#c.saved().events].type,"QUEST_OFFERED")
end)

test("diário suspenso não impede cinema e erro visual não impede captura posterior",function()
    local damaged={schemaVersion=99,events={}}
    local before=t.serialize(damaged); local c=client(damaged); local ui=wire(c)
    c.start(); c.fire("GOSSIP_SHOW"); c.flush(); equal(ui.visible,true); equal(t.serialize(damaged),before)
    c=client(); ui=wire(c)
    c.namespace.ConversationView.New=function() error("visual failure") end
    c.start(); c.fire("GOSSIP_SHOW"); c.flush()
    equal(c.saved().events[#c.saved().events].type,"GOSSIP_VIEWED")
    c.fire("QUEST_DETAIL"); equal(c.saved().events[#c.saved().events].type,"QUEST_OFFERED")
    local errors=0
    for _, message in ipairs(c.messages) do if message:find("devolveu",1,true) then errors=errors+1 end end
    equal(errors,1)
end)

-- Superfície estrita para executar o renderizador Lua real sem o cliente.
-- Métricas de texto aproximadas: verifica ciclo de vida/ações, não acabamento.
local function renderer(n,asynchronous)
    local state={frames={},regions={},fontCalls={},badFont=false,now=0,timers={},loaded={},metricReads={}}
    function state.after(delay,callback) state.timers[#state.timers+1]={at=state.now+delay,callback=callback} end
    function state.advance(delta)
        state.now=state.now+delta
        local count=0
        while true do
            local found
            for index,timer in ipairs(state.timers) do if timer.at<=state.now then found=index; break end end
            if not found then break end
            local timer=table.remove(state.timers,found); timer.callback()
            count=count+1; assert(count<10000,"timer sem limite")
        end
    end
    function state.drain()
        for _=1,2000 do if #state.timers==0 then return end; state.advance(.1) end
        error("fontes não encerraram os timers")
    end
    local make
    make=function(kind,parent)
        local f={kind=kind,parent=parent,shown=true,scripts={},alpha=1}
        function f:SetSize(w,h) self.width,self.height=w,h end
        function f:SetWidth(w) self.width=w end
        function f:SetHeight(h) self.height=h end
        function f:GetWidth()
            if self.kind=="Frame" and self.parent and self.parent.kind=="UIParent" and not self.shown then return 0 end
            return self.width or (self.all and self.all:GetWidth()) or (self.parent and self.parent:GetWidth()) or 0
        end
        function f:GetHeight()
            if self.kind=="Frame" and self.parent and self.parent.kind=="UIParent" and not self.shown then return 0 end
            if self.kind=="FontString" and not self.height and not self.all then return 0 end
            return self.height or (self.all and self.all:GetHeight()) or (self.parent and self.parent:GetHeight()) or 0
        end
        function f:SetAllPoints(target) self.all=target or self.parent end
        function f:ClearAllPoints() self.points={} end
        function f:SetPoint(...) self.points=self.points or {}; self.points[#self.points+1]={...} end
        function f:SetAlpha(value) self.alpha=value end
        function f:SetFrameStrata(value) self.strata=value end
        function f:GetFrameLevel() return self.level or (self.parent and self.parent:GetFrameLevel()+1) or 0 end
        function f:SetFrameLevel(value) self.level=value end
        function f:EnableMouse(value) self.mouse=value end
        local function keyboardFrame()
            assert(kind=="Frame" or kind=="Button" or kind=="ScrollFrame","teclado exige frame")
        end
        function f:EnableKeyboard(value) keyboardFrame(); assert(type(value)=="boolean"); self.keyboard=value end
        function f:SetPropagateKeyboardInput(value) keyboardFrame(); assert(type(value)=="boolean"); self.propagate=value end
        function f:EnableMouseWheel(value) self.wheel=value end
        function f:RegisterForClicks(value) self.clicks=value end
        function f:SetEnabled(value) self.enabled=value end
        function f:SetScript(name,callback) self.scripts[name]=callback end
        function f:GetScript(name) return self.scripts[name] end
        function f:Show()
            local wasShown=self.shown; self.shown=true
            if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function f:Hide()
            local shown=self.shown; self.shown=false
            if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function f:CreateTexture(_,layer) local object=make("Texture",self); object.layer=layer; return object end
        function f:CreateMaskTexture() return make("Mask",self) end
        function f:CreateFontString(_,_,template)
            local value=make("FontString",self)
            if template then
                assert(template=="GameFontNormal","modelo de fonte não simulado")
                value.font,value.size="Fonts\\FRIZQT__.TTF",12
            end
            return value
        end
        function f:SetTexture(value)
            assert(kind=="Texture" or kind=="Mask","SetTexture exige textura")
            assert(value==nil or type(value)=="string" or type(value)=="number","asset de textura inválido")
            self.texture=value; return true
        end
        function f:SetAtlas(value) self.atlas=value end
        function f:SetRotation(value) self.rotation=value end
        function f:SetTexCoord(...) self.texCoord={...} end
        function f:SetColorTexture(...) assert(kind=="Texture"); self.fill={...} end
        function f:SetGradient(orientation,from,to)
            assert(kind=="Texture" and (orientation=="HORIZONTAL" or orientation=="VERTICAL"))
            assert(from.kind=="Color" and to.kind=="Color","gradiente exige objetos de cor")
            self.gradient={orientation,from,to}
        end
        function f:SetVertexColor(...) self.tint={...} end
        function f:AddMaskTexture(value)
            assert(kind=="Texture" and value.kind=="Mask","máscara exige MaskTexture")
            assert(self.parent==value.parent,"superfície de teste exige o mesmo pai para máscara")
            self.mask=value
        end
        function f:SetFont(path,size,flags)
            assert(kind=="FontString" and type(path)=="string" and path~="")
            assert(type(size)=="number" and size>0 and size<math.huge)
            assert(flags==nil or flags=="" or flags=="OUTLINE","flags não simuladas")
            state.fontCalls[#state.fontCalls+1]={path=path,size=size,flags=flags}
            if state.badFont or (state.rejectFont and state.rejectFont(path,size,flags)) then return false end
            self.fontRequest=(self.fontRequest or 0)+1
            local token=self.fontRequest
            local response=state.fontBehavior and state.fontBehavior(path,size,flags,self)
            if response then
                if response.identityNow then self.font,self.size,self.flags=path,size,flags; self.metricFactor=response.factor or .3 end
                state.after(response.delay,function()
                    if token~=self.fontRequest then return end
                    self.font,self.size,self.flags=path,size,flags; self.metricFactor=1; state.loaded[path]=true
                end)
                return response.success==true
            end
            self.font,self.size,self.flags=path,size,flags; return true
        end
        function f:GetFont()
            if state.getFont then return state.getFont(self) end
            return self.font,self.size,self.flags or ""
        end
        function f:SetFontObject() self.font,self.size,self.flags="Fonts\\FRIZQT__.TTF",12,"" end
        function f:SetText(value)
            if self.kind=="FontString" and not self.font then error("FontString:SetText(): Font not set") end
            self.text=value
        end
        function f:GetText() return self.text end
        function f:SetTextColor(...) self.textColor={...} end
        function f:SetShadowColor(...) self.shadow={...} end
        function f:SetShadowOffset(...) self.shadowOffset={...} end
        function f:SetJustifyH(value) self.justifyH=value end
        function f:SetJustifyV(value) self.justifyV=value end
        function f:SetWordWrap(value) self.wrap=value end
        function f:SetNonSpaceWrap(value) self.nonSpaceWrap=value end
        function f:SetSpacing(value) self.spacing=value end
        local function measurable(self)
            if state.zeroMetrics or (not self.all and not (self.points and self.points[1])) then return false end
            local ancestor=self
            while ancestor do if not ancestor.shown then return false end; ancestor=ancestor.parent end
            return true
        end
        local function naturalWidth(text)
            local _,characters=(text or ""):gsub("[^\128-\191]","")
            local ratio=f.font and f.font:find("Cinzel",1,true) and .58 or .45
            return characters*(f.size or 16)*ratio*(f.metricFactor or 1)
        end
        function f:GetUnboundedStringWidth()
            state.metricReads[#state.metricReads+1]={path=self.font,size=self.size,text=self.text,at=state.now,factor=self.metricFactor}
            if not measurable(self) then return 0 end
            local width=0
            for part in ((self.text or "").."\n"):gmatch("([^\n]*)\n") do width=math.max(width,naturalWidth(part)) end
            return width
        end
        function f:GetStringWidth() return math.min(self:GetUnboundedStringWidth(),self:GetWidth()) end
        function f:GetStringHeight()
            if not measurable(self) then return 0 end
            local lines=0
            for part in ((self.text or "").."\n"):gmatch("([^\n]*)\n") do
                lines=lines+(self.wrap==false and 1 or math.max(1,math.ceil(naturalWidth(part)/math.max(1,self:GetWidth()))))
            end
            return (lines*(self.size or 16)*1.4+math.max(0,lines-1)*(self.spacing or 0))*(self.metricFactor or 1)
        end
        function f:SetScrollChild(value) self.child=value end
        function f:SetVerticalScroll(value) self.scroll=value end
        function f:GetVerticalScroll() return self.scroll or 0 end
        function f:UpdateScrollChildRect() self.scrollRange=math.max(0,self.child:GetHeight()-self:GetHeight()) end
        function f:GetVerticalScrollRange() return self.scrollRange or 0 end
        if kind=="FontString" or kind=="Texture" then state.regions[#state.regions+1]=f end
        return f
    end
    local parent=make("UIParent"); parent:SetSize(1280,720)
    state.parent=parent
    local env={type=type,pairs=pairs,ipairs=ipairs,math=math,string=string,tonumber=tonumber,tostring=tostring,
        pcall=pcall,error=error,assert=assert,UIParent=parent,xpcall=xpcall,unpack=unpack,select=select,setmetatable=setmetatable,table=table,
        debugstack=function() return debug.traceback("stack",2) end,
        CreateColor=function(...) local color={...}; color.kind="Color"; return color end,
        CreateFrame=function(kind,_,frameParent)
            local frame=make(kind,frameParent); state.frames[#state.frames+1]=frame; return frame
        end}
    if asynchronous then env.C_Timer={After=state.after} end
    state.env=env
    t.loadModule("Locales/ptBR.lua",n,{})
    t.loadModule("Integration/Diagnostics.lua",n,env)
    t.loadModule("Integration/Fonts.lua",n,env)
    t.loadModule("Integration/QuestView.lua",n,env)
    t.loadModule("Integration/ConversationView.lua",n,env)
    return state
end

local function dialogRoot(r)
    for _,frame in ipairs(r.frames) do if frame.strata=="DIALOG" then return frame end end
end
local function delayed(r,delay,identityNow,factor)
    r.fontBehavior=function(path)
        if path:find("NerdWow\\Fonts\\",1,true) and not r.loaded[path] then
            return {delay=delay,identityNow=identityNow,factor=factor}
        end
    end
end

test("false com GetFont embutido confirmado não é recusa nem dispara alternativa",function()
    local n=core(); local r=renderer(n,true); local records={}
    delayed(r,.5,true,1)
    n.DiagnosticAPI.Bind(function(value) records[#records+1]=value end)
    local object=r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    local path,ready=n.FontAPI.Apply(object,"Cinzel-Bold",21)
    equal(path,nil); equal(ready,false)
    r.advance(.1)
    path,ready=n.FontAPI.Apply(object,"Cinzel-Bold",21)
    equal(ready,true); equal(object:GetFont(),path); assert(path:find("Cinzel-Bold.ttf",1,true))
    r.drain(); equal(#records,0)
    for _,call in ipairs(r.fontCalls) do assert(call.path:find("NerdWow\\Fonts\\",1,true)) end
end)

test("pré carregamento invisível aplica quatro fontes antes da conversa e termina os timers",function()
    local n=core(); local r=renderer(n,true)
    delayed(r,.5,false)
    n.FontAPI.Preload(); n.FontAPI.Preload()
    equal(#r.fontCalls,4); equal(#r.frames,1); equal(r.frames[1].alpha,0); equal(r.frames[1].mouse,false)
    equal(r.frames[1].keyboard,nil); equal(r.frames[1].scripts.OnUpdate,nil)
    r.drain(); equal(#r.fontCalls,4); equal(#r.timers,0)
    for _,region in ipairs(r.regions) do assert(region.font:find("NerdWow\\Fonts\\",1,true)) end
    local view=n.ConversationView.New({Error=function() error("view failure") end})
    equal(view.Show(assert(n.Conversation.Build(model()))),true)
end)

test("conversa espera aplicação tardia sem suprimir Blizzard nem medir com fonte anterior",function()
    local n=core(); local r=renderer(n,true); local p=platform(n); local reports=0
    delayed(r,.6,false); n.FontAPI.Preload()
    local source=model(); source.npc.name="Major Belmonte"; source.npc.title=""
    source.location={zone="Vila Norte",subZone="Vale de Vila Norte"}
    local c=n.ConversationController.New({GetModel=function() return source end,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); equal(dialogRoot(r).shown,false); equal(p.root.alpha,.75)
    equal(dialogRoot(r).keyboard,false)
    r.drain(); equal(reports,0); equal(dialogRoot(r).shown,true); equal(p.root.alpha,0)
    for _,read in ipairs(r.metricReads) do
        if read.text==source.npc.name or read.text==source.location.zone or read.text==source.location.subZone then
            assert(read.path:find("NerdWow\\Fonts\\",1,true),"texto medido com a fonte anterior")
        end
    end
    dialogRoot(r).scripts.OnUpdate(dialogRoot(r),1)
    local found={}
    for _,region in ipairs(r.regions) do if region.alpha~=0 and region.text then found[region.text]=region end end
    assert(found["Major Belmonte"] and found["Vila Norte"] and found["Vale de Vila Norte"])
    c.Close(); equal(dialogRoot(r).keyboard,false)
end)

test("métrica tardia refaz layout aberto sem reiniciar fala entrada alpha ou rolagem",function()
    local n=core(); local r=renderer(n,true); local p=platform(n)
    delayed(r,1.5,true,.45); n.FontAPI.Preload(); r.advance(.1)
    local source=model(); source.text=string.rep("Uma memória completa para contar. ",100)
    source.npc.name="Major Belmonte"; source.npc.title=""; source.location={zone="Vila Norte",subZone="Vale de Vila Norte"}
    local created=0; local original=n.Conversation.NewSpeech
    n.Conversation.NewSpeech=function(text) created=created+1; return original(text) end
    local reports=0
    local c=n.ConversationController.New({GetModel=function() return source end,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh()
    for _=1,12 do if dialogRoot(r).shown then break end; r.advance(.1) end
    local root=dialogRoot(r); equal(root.shown,true); assert(r.now<1.5)
    root.scripts.OnUpdate(root,.95)
    local speechScroll
    for _,frame in ipairs(r.frames) do if frame.kind=="ScrollFrame" then speechScroll=frame; break end end
    speechScroll.scripts.OnMouseWheel(speechScroll,-1)
    local beforeScroll=speechScroll:GetVerticalScroll(); assert(beforeScroll>0)
    local prefix,optionWidth,nameWidth
    for _,region in ipairs(r.regions) do
        if region.alpha~=0 and region.text and source.text:sub(1,#region.text)==region.text and #region.text>1 then prefix=region.text end
        if region.parent.kind=="Button" and region.text=="Conte-me sua história." then optionWidth=region.parent.width end
        if region.alpha~=0 and region.text=="Major Belmonte" then nameWidth=region.width end
    end
    assert(prefix and #prefix<#source.text)
    local beforeCreated,beforeAlpha,update=created,root.alpha,root.scripts.OnUpdate
    r.drain()
    equal(reports,0); equal(created,beforeCreated); equal(root.alpha,beforeAlpha); equal(root.scripts.OnUpdate,update)
    equal(speechScroll:GetVerticalScroll(),beforeScroll)
    local found=false
    for _,region in ipairs(r.regions) do
        if region.text==prefix then found=true end
        if region.alpha~=0 and region.text=="Major Belmonte" then assert(region.width>nameWidth); assert(region.width>=region:GetUnboundedStringWidth()) end
        if region.parent.kind=="Button" and region.text=="Conte-me sua história." then assert(region.parent.width>optionWidth) end
    end
    assert(found); c.Complete(); equal(root.shown,true)
    local all=false; for _,region in ipairs(r.regions) do if region.text==source.text then all=true end end
    assert(all); c.Close()
end)

test("GetFont correto com métricas zero aguarda a métrica final sem fallback nativo",function()
    local n=core(); local r=renderer(n,true); local p=platform(n); local reports=0
    delayed(r,.8,true,0)
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); r.advance(.4)
    equal(p.root.alpha,.75); equal(dialogRoot(r).shown,false)
    r.drain(); equal(reports,0); equal(p.root.alpha,0)
    for _,call in ipairs(r.fontCalls) do assert(call.path:find("NerdWow\\Fonts\\",1,true)) end
    c.Close()
end)

test("não aplicação persistente usa alternativa só depois da janela de verificação",function()
    local n=core(); local r=renderer(n,true); local records={}
    r.rejectFont=function(path) return path:find("NerdWow\\Fonts\\",1,true)~=nil end
    n.DiagnosticAPI.Bind(function(value) records[#records+1]=value end)
    local object=r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    local path,ready=n.FontAPI.Apply(object,"EBGaramond-Regular",21)
    equal(path,nil); equal(ready,false)
    for _=1,40 do r.advance(.1) end
    equal(#records,0); equal(#r.fontCalls,1)
    r.drain()
    path,ready=n.FontAPI.Apply(object,"EBGaramond-Regular",21)
    equal(path,"Fonts\\ARIALN.TTF"); equal(ready,true); equal(object:GetFont(),path)
    equal(#records,1); equal(records[1].code,"font_fallback")
    assert(records[1].message:find("; applied=false",1,true))
    r.drain(); equal(#r.timers,0)
end)

test("recusa embutida e nativa após espera continua falha explícita sem fonte inventada",function()
    local n=core(); local r=renderer(n,true); local records={}; r.badFont=true
    n.DiagnosticAPI.Bind(function(value) records[#records+1]=value end)
    local object=r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    equal(select(2,n.FontAPI.Apply(object,"Cinzel-Bold",21)),false)
    r.drain()
    local ok,err=pcall(n.FontAPI.Apply,object,"Cinzel-Bold",21)
    equal(ok,false); assert(err:find("font_unavailable",1,true))
    equal(#records,1); equal(records[1].code,"font_fallback_failed")
end)

test("fechar ou trocar conversa invalida notificação de fonte pendente",function()
    for _,action in ipairs({"close","replace"}) do
        local n=core(); local r=renderer(n,true); local p=platform(n); local reports=0
        delayed(r,.7,false)
        local source=model()
        local c=n.ConversationController.New({GetModel=function() return source end,IsEnabled=function() return true end,
            View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
        c.Refresh(); equal(dialogRoot(r).shown,false)
        if action=="replace" then source=nil; c.Refresh() else c.Handle("GOSSIP_CLOSED") end
        r.drain(); equal(dialogRoot(r).shown,false); equal(dialogRoot(r).keyboard,false)
        equal(p.root.alpha,.75); equal(reports,0)
    end
end)

test("número e círculo seguem proporção do mockup com centros comuns em escalas distintas",function()
    for _,size in ipairs({{1280,720},{3440,1440},{5120/.8,1440/.8}}) do
        local n=core(); local r=renderer(n); r.parent:SetSize(size[1],size[2])
        local view=n.ConversationView.New({Error=function() error("view failure") end})
        equal(view.Show(assert(n.Conversation.Build(model()))),true)
        local number,label
        for _,region in ipairs(r.regions) do
            if region.text=="4" then number=region end
            if region.text=="Conte-me sua história." then label=region end
        end
        assert(number and label); equal(number.size,label.size*.78); equal(number.width,number.size*1.6)
        equal(number.height,number.width); equal(number.justifyH,"CENTER"); equal(number.justifyV,"MIDDLE")
        local anchor=number.points[1]; equal(anchor[1],"CENTER"); equal(anchor[3],"CENTER")
        equal(anchor[2].width,number.width); equal(anchor[2].height,number.height)
    end
end)

test("fallback adiado conclui o cinema sem ciclo de retry e nova conversa recupera embutidas",function()
    local n=core(); local r=renderer(n,true); local p=platform(n); local records={}; local reports=0
    r.rejectFont=function(path) return path:find("NerdWow\\Fonts\\",1,true)~=nil end
    n.DiagnosticAPI.Bind(function(value) records[#records+1]=value end)
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); equal(p.root.alpha,.75)
    for _=1,55 do r.advance(.1) end
    equal(reports,0); equal(dialogRoot(r).shown,true); equal(p.root.alpha,0); equal(#records,4)
    for _,region in ipairs(r.regions) do
        if region.kind=="FontString" then assert(region.font=="Fonts\\FRIZQT__.TTF" or region.font=="Fonts\\ARIALN.TTF") end
    end
    r.drain(); equal(#r.timers,0)
    r.rejectFont=nil; c.Refresh(); r.drain()
    equal(reports,0); equal(dialogRoot(r).shown,true); equal(#records,4)
    for _,region in ipairs(r.regions) do
        if region.kind=="FontString" then assert(region.font:find("NerdWow\\Fonts\\",1,true)) end
    end
    c.Close()
end)

test("fonte tardia mantém Major zona e subzona completas nas quatro resoluções e escalas",function()
    for _,size in ipairs({{1920,1080},{2560,1440},{3440,1440},{5120,1440}}) do
        for _,scale in ipairs({.64,.8,1,1.25}) do
            local n=core(); local r=renderer(n,true); r.parent:SetSize(size[1]/scale,size[2]/scale)
            delayed(r,.5,false); n.FontAPI.Preload(); r.drain()
            local source=model(); source.npc.name="Major Belmonte"; source.npc.title=""
            source.location={zone="Vila Norte",subZone="Vale de Vila Norte"}
            local view=n.ConversationView.New({Error=function() error("view failure") end})
            equal(view.Show(assert(n.Conversation.Build(source))),true)
            dialogRoot(r).scripts.OnUpdate(dialogRoot(r),1)
            for _,text in ipairs({source.npc.name,source.location.zone,source.location.subZone}) do
                local found=false
                for _,region in ipairs(r.regions) do
                    if region.alpha~=0 and region.text==text then
                        found=true; assert(region.width>=region:GetUnboundedStringWidth())
                        assert(region.height>=region:GetStringHeight()); assert(region.wrap==false)
                    end
                end
                assert(found,"texto cortado com espaço disponível: "..text)
            end
            view.Hide(); r.drain()
        end
    end
end)

test("GetFont restrito não é sucesso nem prova de recusa e conserva a causa",function()
    local n=core(); local r=renderer(n,true); local secret={}
    r.env.issecretvalue=function(value) return value==secret end
    r.getFont=function() return secret,21,"" end
    local object=r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    equal(select(2,n.FontAPI.Apply(object,"Cinzel-Regular",21)),false)
    r.drain()
    local ok,fault=n.DiagnosticAPI.Try(n.FontAPI.Apply,object,"Cinzel-Regular",21)
    equal(ok,false); assert(fault.message:find("restricted_font_result",1,true)); assert(fault.stack)
    for _,call in ipairs(r.fontCalls) do assert(call.path:find("NerdWow\\Fonts\\",1,true)) end
end)

test("identidade compara caminho normalizado tamanho e flags em vez de confiar em true",function()
    local n=core(); local r=renderer(n,true)
    r.getFont=function(object) return object.font:gsub("\\","/"):upper(),object.size,object.flags or "" end
    local object=r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    local path,ready=n.FontAPI.Apply(object,"Cinzel-Regular",21)
    equal(ready,true); assert(path:find("Cinzel-Regular.ttf",1,true))
    r.drain()
    n=core(); r=renderer(n,true)
    r.getFont=function(object) return object.font,12,"OUTLINE" end
    object=r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    path,ready=n.FontAPI.Apply(object,"Cinzel-Regular",21)
    equal(ready,false); equal(path,nil)
    r.drain(); equal(pcall(n.FontAPI.Apply,object,"Cinzel-Regular",21),false)
end)

test("renderizador real limita teclado animação e fala ao ciclo da conversa",function()
    local n=core(); local p=platform(n); local r=renderer(n); local reports=0
    local source=model()
    local c=n.ConversationController.New({GetModel=function() return source end,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); equal(reports,0); equal(p.root.alpha,0)
    local frame=r.frames[1]; equal(frame.keyboard,true); equal(frame.mouse,false)
    assert(frame.scripts.OnUpdate)
    frame.scripts.OnKeyDown(frame,"A"); equal(frame.propagate,true)
    p.focus=true; frame.scripts.OnKeyDown(frame,"4"); equal(frame.propagate,true); equal(p.action,nil)
    p.focus=false; frame.scripts.OnKeyDown(frame,"SPACE"); equal(frame.propagate,false)
    frame.scripts.OnUpdate(frame,1); equal(frame.scripts.OnUpdate,nil)
    frame.scripts.OnKeyDown(frame,"4"); equal(p.action,"SelectOption"); equal(p.value,7001)
    local count=#r.frames
    c.Refresh(); equal(#r.frames,count) -- Reaproveita frames e botões ao renovar o modelo.
    frame.scripts.OnKeyDown(frame,"ESCAPE")
    equal(frame.shown,false); equal(frame.keyboard,false); equal(frame.scripts.OnUpdate,nil)
    equal(p.action,"CloseGossip"); equal(p.root.alpha,.75)
    equal(reports,0)
end)

test("frame oculto com retângulo zero apresenta usando viewport válido",function()
    local n=core(); local r=renderer(n); local errors=0
    local view=n.ConversationView.New({Error=function() errors=errors+1 end})
    local frame=r.frames[1]
    equal(frame.shown,false); equal(frame:GetWidth(),0); equal(frame:GetHeight(),0)
    local ready,code,dimensions=view.Show(assert(n.Conversation.Build(model())))
    equal(ready,true); equal(code,nil); equal(errors,0)
    equal(dimensions.viewportWidth,1280); equal(dimensions.viewportHeight,720)
    equal(frame.shown,true); equal(frame.keyboard,true)
    view.Hide(); equal(frame:GetWidth(),0); equal(frame.keyboard,false)
end)

test("viewport indisponível adia três vezes sem tomar controle e registra limite",function()
    local n=core(); local p=platform(n); local r=renderer(n); local queued,failures={},{}
    p.api.Defer=function(callback) queued[#queued+1]=callback; return true end
    r.parent:SetSize(0,0)
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Try=n.DiagnosticAPI.Try,
        Diagnose=function(fault,context,source) failures[#failures+1]={fault=fault,context=context,source=source} end,
        Report=function() end})
    c.Handle("GOSSIP_SHOW")
    local attempts=0
    while #queued>0 do
        local current=queued; queued={}
        for _, callback in ipairs(current) do callback(); attempts=attempts+1; assert(attempts<=4) end
        equal(p.root.alpha,.75)
    end
    equal(attempts,4); equal(#failures,1)
    local failure=failures[1]
    assert(failure.fault.message:find("layout_unavailable",1,true)); assert(failure.fault.stack)
    equal(failure.context.viewportWidth,0); equal(failure.context.viewportHeight,0)
    equal(failure.context.gameEvent,"GOSSIP_SHOW"); equal(failure.source.npc.creatureID,777)
    local frame=r.frames[1]
    equal(frame.shown,false); equal(frame.keyboard,false); equal(frame.scripts.OnUpdate,nil)
    r.parent:SetSize(1920,1080); c.Toggle()
    for _, callback in ipairs(queued) do callback() end
    equal(p.root.alpha,0); equal(frame.keyboard,true)
    c.Close(); equal(p.root.alpha,.75)
end)

test("viewport resolvido na próxima tentativa retoma sem falha ou chat",function()
    local n=core(); local p=platform(n); local r=renderer(n); local queued={}; local reports=0
    p.api.Defer=function(callback) queued[#queued+1]=callback; return true end
    r.parent:SetSize(0,0)
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Try=n.DiagnosticAPI.Try,Report=function() reports=reports+1 end})
    c.Refresh(); equal(#queued,1); equal(p.root.alpha,.75)
    r.parent:SetSize(1280,720); queued[1]()
    equal(reports,0); equal(p.root.alpha,0); equal(r.frames[1].keyboard,true)
end)

test("fallback síncrono dentro de Show impede retomada de teclado e supressão nativa",function()
    local s=controller(); local diagnosed=0; local took=0
    s.options.Platform.TakeNative=function() took=took+1 end
    s.options.Diagnose=function(fault,context)
        equal(fault,"onshow_original"); equal(context.stage,"OnShow"); diagnosed=diagnosed+1
    end
    s.options.View.New=function(callbacks)
        return {Hide=function() s.visible=false; s.keyboard=false end,
            Show=function()
                s.visible=true; s.keyboard=true
                callbacks.Error("onshow_original","OnShow")
                return true
            end}
    end
    s.ctrl.Refresh()
    equal(diagnosed,1); equal(took,0); equal(s.reports,1)
    equal(s.keyboard,false); equal(s.visible,false)
end)

test("erro real de callback guarda mensagem stack e dimensões sem propagar",function()
    local n=core(); local p=platform(n); local r=renderer(n); local captured
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Try=n.DiagnosticAPI.Try,
        Diagnose=function(fault,context) captured={fault=fault,context=context} end,Report=function() end})
    c.Handle("GOSSIP_SHOW")
    r.regions[1].SetHeight=function() error("render_callback_original") end
    local frame=r.frames[1]
    equal(pcall(frame.scripts.OnUpdate,frame,.1),true)
    assert(captured.fault.message:find("render_callback_original",1,true)); assert(captured.fault.stack)
    equal(captured.context.gameEvent,"GOSSIP_SHOW"); equal(captured.context.stage,"OnUpdate")
    equal(captured.context.viewportWidth,1280); equal(captured.context.frameHeight,720)
    equal(frame.keyboard,false); equal(frame.shown,false); equal(p.root.alpha,.75)
end)

test("falha de restauração conserva erro original e ainda restaura os demais estados",function()
    local n=core(); local p=platform(n); renderer(n)
    p.api.TakeNative("GOSSIP",function() end)
    local original=p.root.SetAlpha
    p.root.SetAlpha=function(self,value)
        if value==.75 then error("restore_alpha_original") end
        original(self,value)
    end
    local ok,fault=n.DiagnosticAPI.Try(p.api.RestoreNative)
    equal(ok,false); equal(n.DiagnosticAPI.Code(fault),"native_restore_failed")
    assert(fault.message:find("restore_alpha_original",1,true)); assert(fault.stack)
    equal(p.root.mouse,true); equal(p.child.mouse,true); equal(p.child.keyboard,true)
    p.root.SetAlpha=original
    p.api.RestoreNative(); equal(p.root.alpha,.75)
end)

test("regra do cliente rejeita texto sem fonte e aceita fonte base desde a criação",function()
    local r=renderer(core())
    local without=r.parent:CreateFontString(nil,"OVERLAY")
    local ok,err=pcall(without.SetText,without,"×")
    equal(ok,false); assert(err:find("FontString:SetText(): Font not set",1,true))
    local initialized=r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    equal(pcall(initialized.SetText,initialized,"×"),true)
end)

test("todos os rótulos inclusive fechar têm fonte antes do primeiro texto e mantêm fontes do tema",function()
    local n=core(); local r=renderer(n)
    local view=n.ConversationView.New({Error=function(fault) error(fault.message) end})
    local exitLabel
    for _, region in ipairs(r.regions) do
        if region.kind=="FontString" then
            assert(region.font,"FontString sem fonte na criação")
            if region.text=="×" then exitLabel=region end
        end
    end
    assert(exitLabel,"botão de fechar deve preservar o glifo aprovado")
    equal(view.Show(assert(n.Conversation.Build(model()))),true)
    assert(exitLabel.font:find("Cinzel-Regular.ttf",1,true))
    for _, region in ipairs(r.regions) do
        if region.kind=="FontString" then assert(region.font:find("NerdWow\\Fonts\\",1,true)) end
    end
    view.Hide(); equal(view.Show(assert(n.Conversation.Build(model("GREETING")))),true)
end)

test("simulação rejeita máscara e teclado de tipos errados sem fingir renderização real",function()
    local r=renderer(core())
    local texture=r.parent:CreateTexture()
    equal(pcall(texture.AddMaskTexture,texture,r.parent:CreateTexture()),false)
    equal(pcall(texture.EnableKeyboard,texture,true),false)
    equal(pcall(texture.SetGradient,texture,"HORIZONTAL",{},{}),false)
    local mask=r.parent:CreateMaskTexture()
    equal(pcall(texture.AddMaskTexture,texture,mask),true)
    equal(pcall(texture.SetTexture,texture,{}),false)
end)

test("substituição recusa estado imutável mesmo fora de combate sem chamar setters",function()
    local p=platform(core()); p.child.stateLocked=true
    equal(pcall(p.api.TakeNative,"GOSSIP"),false)
    equal(p.root.setterCalls,nil); equal(p.child.setterCalls,nil); equal(p.root.alpha,.75)
    p.child.stateLocked=false; p.child.CanChangeProtectedState=function() return p.secret end
    equal(pcall(p.api.TakeNative,"GOSSIP"),false); equal(p.root.setterCalls,nil)
end)

test("proteção que muda após inspeção impede setter e permite rollback das alterações anteriores",function()
    local p=platform(core()); local original=p.root.EnableMouse
    p.root.EnableMouse=function(self,value) original(self,value); if not value then p.child.protected=true end end
    equal(pcall(p.api.TakeNative,"GOSSIP"),false)
    equal(p.child.setterCalls,nil); equal(p.root.mouse,false)
    p.api.RestoreNative(); equal(p.root.mouse,true); equal(p.root.alpha,.75)
    equal(p.child.mouse,true); equal(p.child.setterCalls,nil)
end)

test("restauração adia estado agora protegido sem chamar setter e tenta os demais",function()
    local p=platform(core()); p.api.TakeNative("GOSSIP",function() end)
    local calls=p.child.setterCalls
    p.child.protected=true
    equal(pcall(p.api.RestoreNative),false)
    equal(p.child.setterCalls,calls); equal(p.root.alpha,.75); equal(p.root.mouse,true)
    p.child.protected=false; p.api.RestoreNative()
    equal(p.child.mouse,true); equal(p.child.keyboard,true)
end)

test("estados nativos já desligados não recebem setters desnecessários nem hooks repetidos",function()
    local p=platform(core()); p.api.TakeNative("GOSSIP",function() end)
    equal(p.sibling.setterCalls,nil)
    p.api.RestoreNative(); equal(p.sibling.setterCalls,nil)
    local hook=p.root.scripts.OnShow
    p.api.TakeNative("GOSSIP",function() end); equal(p.root.scripts.OnShow,hook)
    p.api.RestoreNative()
end)

test("pós-hook nativo só agenda sem executar transação dentro do handler Blizzard",function()
    local s=controller(); s.ctrl.Refresh()
    local reads=s.reads; local callback=s.callbacks.NativeShown
    callback()
    equal(s.reads,reads); equal(s.native,true); equal(#s.queued,1)
    s.flush(); equal(s.reads,reads+1); equal(s.native,true)
    callback(); equal(#s.queued,0) -- geração antiga não reaplica a interface.
end)

test("layout aplica fontes sem contorno com flags nil e não faz aquecimento automático",function()
    local n=core(); local r=renderer(n)
    equal(#r.fontCalls,0)
    local view=n.ConversationView.New({Error=function() error("view failure") end})
    equal(#r.fontCalls,0)
    equal(view.Show(assert(n.Conversation.Build(model()))),true)
    local found=false
    for _,call in ipairs(r.fontCalls) do
        if call.path=="Interface\\AddOns\\NerdWow\\Fonts\\Cinzel-Bold.ttf" and call.size==21 then found=true end
    end
    assert(found)
    for _, call in ipairs(r.fontCalls) do equal(call.flags,nil); assert(call.size>=8) end
end)

test("recusa só de Cinzel Bold troca o nome pela fonte nativa e preserva as demais",function()
    local n=core(); local r=renderer(n); local records={}
    n.DiagnosticAPI.Bind(function(entry) records[#records+1]=entry end)
    r.rejectFont=function(path) return path:find("Cinzel-Bold.ttf",1,true)~=nil end
    local view=n.ConversationView.New({Error=function() error("view failure") end})
    equal(view.Show(assert(n.Conversation.Build(model()))),true)
    local found=false
    for _, region in ipairs(r.regions) do
        if region.text=="Arquivista Velann" then equal(region.font,"Fonts\\FRIZQT__.TTF"); found=true end
        if region.text=="Guardiã dos registros" then assert(region.font:find("EBGaramond-Italic.ttf",1,true)) end
    end
    assert(found); equal(#records,1); equal(records[1].code,"font_fallback")
    assert(records[1].message:find("success=false; fallback=Fonts\\FRIZQT__.TTF; fallbackSuccess=true",1,true))
end)

test("recusa de todos os TTF embutidos mantém cinema teclado fala e seleção com fontes nativas",function()
    local n=core(); local p=platform(n); local r=renderer(n); local reports=0
    r.rejectFont=function(path) return path:find("NerdWow\\Fonts\\",1,true)~=nil end
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); equal(reports,0); equal(p.root.alpha,0); equal(r.frames[1].shown,true)
    equal(r.frames[1].keyboard,true)
    local titleFound,bodyFound=false,false
    for _, region in ipairs(r.regions) do
        if region.kind=="FontString" then
            assert(region.font=="Fonts\\FRIZQT__.TTF" or region.font=="Fonts\\ARIALN.TTF")
            if region.text=="Arquivista Velann" then equal(region.font,"Fonts\\FRIZQT__.TTF"); titleFound=true end
            if region.text=="Conte-me sua história." then equal(region.font,"Fonts\\ARIALN.TTF"); bodyFound=true end
        end
    end
    assert(titleFound and bodyFound)
    r.frames[1].scripts.OnKeyDown(r.frames[1],"SPACE"); equal(r.frames[1].propagate,false)
    r.frames[1].scripts.OnKeyDown(r.frames[1],"4"); equal(p.action,"SelectOption"); equal(p.value,7001)
    c.Close(); equal(r.frames[1].keyboard,false); equal(p.root.alpha,.75); equal(reports,0)
end)

test("fallback é registrado uma vez por arquivo na sessão sem impedir nova tentativa da fonte",function()
    local n=core(); local r=renderer(n); local records={}
    n.DiagnosticAPI.Bind(function(entry) records[#records+1]=entry end)
    r.rejectFont=function(path) return path:find("NerdWow\\Fonts\\",1,true)~=nil end
    local view=n.ConversationView.New({Error=function() error("view failure") end})
    for _=1,3 do equal(view.Show(assert(n.Conversation.Build(model()))),true); view.Hide() end
    equal(#records,4)
    r.rejectFont=nil
    equal(view.Show(assert(n.Conversation.Build(model()))),true)
    for _, region in ipairs(r.regions) do
        if region.kind=="FontString" then assert(region.font:find("NerdWow\\Fonts\\",1,true)) end
    end
    equal(#records,4)
end)

test("exceção na fonte embutida usa alternativa e conserva a causa e a pilha",function()
    local n=core(); local r=renderer(n); local records={}
    n.DiagnosticAPI.Bind(function(entry) records[#records+1]=entry end)
    r.rejectFont=function(path) if path:find("Cinzel-Bold.ttf",1,true) then error("font_asset_error") end end
    local view=n.ConversationView.New({Error=function() error("view failure") end})
    equal(view.Show(assert(n.Conversation.Build(model()))),true)
    equal(#records,1); equal(records[1].code,"font_fallback")
    assert(records[1].message:find("font_asset_error",1,true)); assert(records[1].stack)
end)

test("fallback mantém altura proporcional e mínimo de oito com flags nil",function()
    local n=core(); local r=renderer(n)
    r.rejectFont=function(path) return path:find("NerdWow\\Fonts\\",1,true)~=nil end
    local object=r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    for _, size in ipairs({4,21,31.5}) do
        n.FontAPI.Apply(object,"EBGaramond-Regular",size)
        equal(object.font,"Fonts\\ARIALN.TTF"); equal(object.size,math.max(8,size))
        local requested,native=r.fontCalls[#r.fontCalls-1],r.fontCalls[#r.fontCalls]
        equal(requested.size,native.size); equal(requested.flags,nil); equal(native.flags,nil)
    end
end)

test("teste de fontes durante cinema não altera texto teclado animação nem diário",function()
    local clientState=client(); clientState.start()
    local n=clientState.namespace; local p=platform(n); local r=renderer(n)
    n.DiagnosticAPI.Bind(assert(n.Diagnostics.Open(clientState.diagnostics())).Append)
    local reports=0
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); local root=r.frames[1]; local update=root.scripts.OnUpdate
    local before=t.serialize(clientState.saved()); local originalFonts={}
    for index,region in ipairs(r.regions) do originalFonts[index]={font=region.font,text=region.text} end
    clientState.command("fontes")
    equal(root.shown,true); equal(root.keyboard,true); equal(root.scripts.OnUpdate,update); equal(p.root.alpha,0)
    local invisible=false
    for _,frame in ipairs(r.frames) do if frame.alpha==0 and frame.mouse==false then invisible=true end end
    assert(invisible)
    for index,original in ipairs(originalFonts) do
        equal(r.regions[index].font,original.font); equal(r.regions[index].text,original.text)
    end
    equal(t.serialize(clientState.saved()),before); equal(#clientState.diagnostics().entries,36)
    equal(reports,0); c.Close(); equal(p.root.alpha,.75)
end)

test("coluna medida tem setenta e dois caracteres e independe da proporção e escala UI",function()
    local c=core().Conversation
    local _,characters=c.LINE_SAMPLE:gsub("[^\128-\191]",""); equal(characters,72)
    for _,size in ipairs({{1920,1080},{2560,1440},{3440,1440},{5120,1440}}) do
        for _,uiScale in ipairs({.64,.8,1,1.25}) do
            local width,height=size[1]/uiScale,size[2]/uiScale
            local base=assert(c.Layout(width,height))
            local measured=72*base.speechSize*.45
            local layout=assert(c.Layout(width,height,measured))
            equal(layout.textWidth,measured); equal(layout.textLeft+layout.textWidth/2,width/2)
            equal(layout.maximumBottom,height*.38)
            assert(layout.textLeft>=84*layout.scale)
        end
    end
end)

test("barra conserva vinte e sete por cento e limita texto extenso a trinta e oito",function()
    local c=core().Conversation
    for _,size in ipairs({{1920,1080},{2560,1440},{3440,1440},{5120,1440}}) do
        local layout=c.Layout(size[1],size[2]); local s=layout.scale
        local short=c.Arrange(layout,30*s,44*s,28*s)
        equal(short.bottom,layout.bottom)
        local long=c.Arrange(layout,30*s,10000*s,28*s)
        equal(long.bottom,layout.maximumBottom)
        assert(long.speechHeight>44*s)
        equal(long.speechTop+8*s+30*s,long.headerTop)
        assert(long.speechBottom>long.optionBottom+long.optionHeight)
    end
end)

test("parágrafos preservam offsets texto original quebras simples e UTF-8",function()
    local c=core().Conversation
    local original="Primeira linha\nAinda aqui.\n\n  \nVocê chegou.\r\n\r\nÚltima fala."
    local parts=c.Paragraphs(original); equal(#parts,3)
    equal(parts[1].text,"Primeira linha\nAinda aqui.")
    equal(parts[2].text,"Você chegou."); equal(parts[3].text,"Última fala.")
    for _,part in ipairs(parts) do equal(original:sub(part.first,part.last),part.text) end
    equal(#c.Paragraphs(""),0)
end)

test("superfície não mede FontString oculto ou sem âncora e distingue largura sem limite",function()
    local r=renderer(core()); local object=r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    object:SetText("Texto muito mais largo que a caixa"); object:SetSize(20,50)
    equal(object:GetStringWidth(),0); equal(object:GetStringHeight(),0)
    object:SetPoint("TOPLEFT",r.parent,"TOPLEFT",0,0)
    assert(object:GetUnboundedStringWidth()>object:GetStringWidth())
    object:Hide(); equal(object:GetStringWidth(),0); equal(object:GetStringHeight(),0)
    object:Show(); assert(object:GetUnboundedStringWidth()>20)
end)

test("nome longo não quebra e fala respeita cabeçalho nas quatro resoluções e escalas",function()
    for _,size in ipairs({{1920,1080},{2560,1440},{3440,1440},{5120,1440}}) do
        for _,uiScale in ipairs({.64,.8,1,1.25}) do
            local n=core(); local r=renderer(n); r.parent:SetSize(size[1]/uiScale,size[2]/uiScale)
            local source=model(); source.npc.name=string.rep("Arquivista Áurea de Quel'Thalas ",12)
            source.npc.title="Guardiã dos registros"
            local original=source.npc.name
            local view=n.ConversationView.New({Error=function() error("layout failure") end})
            equal(view.Show(assert(n.Conversation.Build(source))),true); view.Complete()
            r.frames[1].scripts.OnUpdate(r.frames[1],1)
            local nameLabel,titleLabel
            for _,region in ipairs(r.regions) do
                if region.kind=="FontString" and region.alpha~=0 then
                    if region.text and region.text:find("...",1,true) then nameLabel=region end
                    if region.text==source.npc.title then titleLabel=region end
                end
            end
            assert(nameLabel and titleLabel); equal(nameLabel.wrap,false); equal(nameLabel.nonSpaceWrap,false)
            assert(nameLabel.size>=14*(size[2]/uiScale/720))
            local speechScroll=r.frames[2]
            local headerTop=nameLabel.points[1][5]
            assert(speechScroll.points[1][5]<=headerTop-nameLabel.height)
            assert(speechScroll.points[1][5]<=headerTop-titleLabel.height-3*(size[2]/uiScale/720))
            equal(source.npc.name,original)
        end
    end
end)

test("zona subzona e dica ocupam caixas centradas e faixas sem conflito inclusive com fonte nativa",function()
    for _,size in ipairs({{1920,1080},{2560,1440},{3440,1440},{5120,1440}}) do
        local n=core(); local r=renderer(n); r.parent:SetSize(size[1],size[2])
        r.rejectFont=function(path) return path:find("NerdWow\\Fonts\\",1,true)~=nil end
        local view=n.ConversationView.New({Error=function() error("layout failure") end})
        equal(view.Show(assert(n.Conversation.Build(model()))),true); view.Complete()
        r.frames[1].scripts.OnUpdate(r.frames[1],1)
        local zoneLabel,subLabel,hintLabel
        for _,region in ipairs(r.regions) do
            if region.kind=="FontString" and region.alpha~=0 then
                if region.text=="Floresta do Canto Eterno" then zoneLabel=region end
                if region.text=="Corredor dos Arquivistas" then subLabel=region end
                if region.text==n.Text.cinemaHint then hintLabel=region end
                if region.text and region.text~="" and region.shown then assert(region:GetWidth()>0 and region:GetHeight()>0) end
            end
        end
        assert(zoneLabel and subLabel and hintLabel)
        local s=size[2]/720
        local zoneLeft=zoneLabel.points[1][4]
        local total=zoneLabel.width+12*s+subLabel.width
        assert(math.abs(zoneLeft+total/2-size[1]/2)<.001)
        local hintTop=-hintLabel.points[1][5]
        assert(hintTop>6*s+zoneLabel.height)
        assert(hintTop>9*s+subLabel.height)
        assert(hintTop+hintLabel.height<=size[2]*.09)
    end
end)

test("medidor mostrado e fallback de métricas zero mantêm opções completas com caixas positivas",function()
    for _,zero in ipairs({false,true}) do
        local n=core(); local r=renderer(n); r.zeroMetrics=zero
        local source=model(); source.options[1].text=string.rep("História completa de Azeroth ",20)
        local view=n.ConversationView.New({Error=function() error("layout failure") end})
        equal(view.Show(assert(n.Conversation.Build(source))),true); view.Complete()
        r.frames[1].scripts.OnUpdate(r.frames[1],1)
        local optionLabel,numberLabel,measure
        for _,region in ipairs(r.regions) do
            if region.kind=="FontString" then
                if region.alpha==0 and region.width==100000 then measure=region end
                if region.alpha~=0 and region.text==source.options[1].text then optionLabel=region end
                if region.text=="4" then numberLabel=region end
            end
        end
        assert(measure and measure.shown and measure.points[1])
        assert(optionLabel and numberLabel)
        equal(optionLabel.text,source.options[1].text); assert(optionLabel.width>500)
        assert(optionLabel.height>optionLabel.size*1.4)
        assert(optionLabel.parent.height>=optionLabel.height+8)
        equal(numberLabel.width,18*.78*1.6); equal(numberLabel.height,numberLabel.width)
        equal(optionLabel.parent.parent,r.frames[5])
    end
end)

test("fala extensa rola sem mover opções e mostra indicação discreta dentro do limite",function()
    local n=core(); local r=renderer(n)
    local source=model(); source.text=string.rep("Uma história extensa para contar. ",200)
    local view=n.ConversationView.New({Error=function() error("layout failure") end})
    equal(view.Show(assert(n.Conversation.Build(source))),true); view.Complete()
    local root,speechScroll,optionScroll=r.frames[1],r.frames[2],r.frames[4]
    root.scripts.OnUpdate(root,1)
    equal(r.regions[2].height,720*.38)
    local beforeX,beforeY=optionScroll.points[1][4],optionScroll.points[1][5]
    speechScroll.scripts.OnMouseWheel(speechScroll,-1)
    assert(speechScroll:GetVerticalScroll()>0); equal(optionScroll:GetVerticalScroll(),0)
    equal(optionScroll.points[1][4],beforeX); equal(optionScroll.points[1][5],beforeY)
    local indication=false
    for _,region in ipairs(r.regions) do if region.text==n.Text.cinemaMore then indication=true end end
    assert(indication)
    assert(optionScroll.points[1][5]+optionScroll.height<speechScroll.points[1][5]-speechScroll.height)
end)

test("muitas opções têm rolagem própria sem truncar texto nem alterar atalhos",function()
    local n=core(); local r=renderer(n); local source=model()
    source.availableQuests={}; source.activeQuests={}; source.options={}
    for index=1,30 do source.options[index]={index=index,optionID=7000+index,text="Conte toda a história "..index,status=0} end
    local view=n.ConversationView.New({Error=function() error("layout failure") end})
    equal(view.Show(assert(n.Conversation.Build(source))),true); view.Complete()
    r.frames[1].scripts.OnUpdate(r.frames[1],1)
    local speechScroll,optionScroll=r.frames[2],r.frames[4]
    assert(optionScroll:GetVerticalScrollRange()>0)
    optionScroll.scripts.OnMouseWheel(optionScroll,-1)
    assert(optionScroll:GetVerticalScroll()>0); equal(speechScroll:GetVerticalScroll(),0)
    local found=0
    for _,region in ipairs(r.regions) do
        if region.alpha~=0 and region.text and region.text:find("Conte toda a história ",1,true) then found=found+1 end
    end
    equal(found,30)
    local action,index=n.Conversation.Key("9",false); equal(action,"choose"); equal(index,9)
end)

test("parágrafos têm intervalo menor que linha vazia sem mudar modelo ou animação",function()
    local n=core(); local r=renderer(n); local source=model()
    source.text="Pela Luz, é você mesmo?\n\nMas vejam só!\n\nMuito bem!"
    local original=source.text
    local view=n.ConversationView.New({Error=function() error("layout failure") end})
    equal(view.Show(assert(n.Conversation.Build(source))),true); view.Complete()
    local a,b
    for _,region in ipairs(r.regions) do
        if region.alpha~=0 and region.text=="Pela Luz, é você mesmo?" then a=region end
        if region.alpha~=0 and region.text=="Mas vejam só!" then b=region end
    end
    assert(a and b)
    local gap=-b.points[1][5]-(-a.points[1][5]+a.height)
    assert(gap>0 and gap<a.size)
    equal(source.text,original); equal(view.IsTyping(),false)
end)

test("fonte que não carrega aciona fallback antes de suprimir apresentação nativa",function()
    local n=core(); local p=platform(n); local r=renderer(n); r.badFont=true
    local reports=0; local records={}
    n.DiagnosticAPI.Bind(function(entry) records[#records+1]=entry end)
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); equal(reports,1); equal(p.root.alpha,.75)
    equal(r.frames[1].shown,false); equal(r.frames[1].keyboard,false)
    equal(r.frames[1].scripts.OnUpdate,nil)
    equal(#records,4)
    for _,record in ipairs(records) do equal(record.code,"font_fallback_failed") end
    assert(records[1].message:find("fallbackSuccess=false",1,true))
end)

test("erro de animação é contido e restaura interface sem deixar teclado ativo",function()
    local n=core(); local p=platform(n); local r=renderer(n); local reports=0
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); equal(p.root.alpha,0)
    r.regions[1].SetHeight=function() error("animation failure") end
    local frame=r.frames[1]
    equal(pcall(frame.scripts.OnUpdate,frame,.1),true)
    equal(reports,1); equal(frame.shown,false); equal(frame.keyboard,false); equal(frame.scripts.OnUpdate,nil)
    equal(p.root.alpha,.75)
end)

test("redimensionar e ocultar o pai preservam modelo e retomam apenas animação necessária",function()
    local n=core(); local p=platform(n); local r=renderer(n); local reports=0
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); local frame=r.frames[1]
    frame:Hide(); equal(frame.keyboard,false); equal(frame.scripts.OnUpdate,nil)
    r.parent:SetSize(1920,1080)
    frame:Show(); equal(frame.keyboard,true); assert(frame.scripts.OnUpdate)
    frame.scripts.OnUpdate(frame,1); equal(frame.scripts.OnUpdate,nil)
    frame.scripts.OnSizeChanged(frame,1920,1080)
    equal(r.regions[1].height,1080*.09); equal(reports,0)
    frame:Hide(); frame:Show(); equal(frame.scripts.OnUpdate,nil)
    c.Close(); equal(frame.keyboard,false)
end)
return {renderer=renderer,platform=platform,wire=wire}
