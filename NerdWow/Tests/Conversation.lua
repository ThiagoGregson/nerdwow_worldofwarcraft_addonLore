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
    function f:IsProtected() return self.protected or false end
    function f:IsForbidden() return self.forbidden or false end
    function f:GetAlpha() return self.alpha end
    function f:SetAlpha(value) self.alpha=value end
    function f:IsMouseEnabled() return self.mouse end
    function f:EnableMouse(value) if self.failDisable and not value then error("mouse failure") end; self.mouse=value end
    function f:IsKeyboardEnabled() return self.keyboard end
    function f:EnableKeyboard(value) self.keyboard=value end
    function f:GetChildren() return unpack(self.children) end
    function f:HookScript(name,callback) self.scripts[name]=callback end
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
    local settings,_,repaired=n.Settings.Open(root); equal(repaired[1],"dialogEnabled")
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
local function renderer(n)
    local state={frames={},regions={},badFont=false}
    local make
    make=function(kind,parent)
        local f={kind=kind,parent=parent,shown=true,scripts={},alpha=1}
        function f:SetSize(w,h) self.width,self.height=w,h end
        function f:SetWidth(w) self.width=w end
        function f:SetHeight(h) self.height=h end
        function f:GetWidth() return self.width or (self.all and self.all:GetWidth()) or (self.parent and self.parent:GetWidth()) or 0 end
        function f:GetHeight() return self.height or (self.all and self.all:GetHeight()) or (self.parent and self.parent:GetHeight()) or 0 end
        function f:SetAllPoints(target) self.all=target or self.parent end
        function f:ClearAllPoints() self.points={} end
        function f:SetPoint(...) self.points=self.points or {}; self.points[#self.points+1]={...} end
        function f:SetAlpha(value) self.alpha=value end
        function f:SetFrameStrata(value) self.strata=value end
        function f:EnableMouse(value) self.mouse=value end
        function f:EnableKeyboard(value) self.keyboard=value end
        function f:SetPropagateKeyboardInput(value) self.propagate=value end
        function f:EnableMouseWheel(value) self.wheel=value end
        function f:RegisterForClicks(value) self.clicks=value end
        function f:SetEnabled(value) self.enabled=value end
        function f:SetScript(name,callback) self.scripts[name]=callback end
        function f:Show()
            local wasShown=self.shown; self.shown=true
            if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function f:Hide()
            local shown=self.shown; self.shown=false
            if shown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function f:CreateTexture() return make("Texture",self) end
        function f:CreateMaskTexture() return make("Mask",self) end
        function f:CreateFontString() return make("FontString",self) end
        function f:SetTexture(value) self.texture=value; return true end
        function f:SetColorTexture(...) self.fill={...} end
        function f:SetGradient(...) self.gradient={...} end
        function f:SetVertexColor(...) self.tint={...} end
        function f:AddMaskTexture(value) self.mask=value end
        function f:SetFont(path,size)
            if state.badFont then return false end
            self.font,self.size=path,size; return true
        end
        function f:SetText(value) self.text=value end
        function f:SetTextColor(...) self.textColor={...} end
        function f:SetShadowColor(...) self.shadow={...} end
        function f:SetShadowOffset(...) self.shadowOffset={...} end
        function f:SetJustifyH(value) self.justifyH=value end
        function f:SetJustifyV(value) self.justifyV=value end
        function f:SetWordWrap(value) self.wrap=value end
        function f:SetSpacing(value) self.spacing=value end
        function f:GetStringWidth() return #(self.text or "")*(self.size or 16)*.45 end
        function f:GetStringHeight()
            return math.max(1,math.ceil(self:GetStringWidth()/math.max(1,self:GetWidth())))*(self.size or 16)*1.4
        end
        function f:SetScrollChild(value) self.child=value end
        function f:SetVerticalScroll(value) self.scroll=value end
        function f:GetVerticalScroll() return self.scroll or 0 end
        function f:GetVerticalScrollRange() return math.max(0,self.child:GetHeight()-self:GetHeight()) end
        if kind=="FontString" or kind=="Texture" then state.regions[#state.regions+1]=f end
        return f
    end
    local parent=make("UIParent"); parent:SetSize(1280,720)
    state.parent=parent
    local env={type=type,pairs=pairs,ipairs=ipairs,math=math,string=string,tonumber=tonumber,tostring=tostring,
        pcall=pcall,error=error,assert=assert,UIParent=parent,CreateColor=function(...) return {...} end,
        CreateFrame=function(kind,_,frameParent)
            local frame=make(kind,frameParent); state.frames[#state.frames+1]=frame; return frame
        end}
    t.loadModule("Locales/ptBR.lua",n,{})
    t.loadModule("Integration/ConversationView.lua",n,env)
    return state
end

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

test("fonte que não carrega aciona fallback antes de suprimir apresentação nativa",function()
    local n=core(); local p=platform(n); local r=renderer(n); r.badFont=true
    local reports=0
    local c=n.ConversationController.New({GetModel=model,IsEnabled=function() return true end,
        View=n.ConversationView,Platform=p.api,Report=function() reports=reports+1 end})
    c.Refresh(); equal(reports,1); equal(p.root.alpha,.75)
    equal(r.frames[1].shown,false); equal(r.frames[1].keyboard,false)
    equal(r.frames[1].scripts.OnUpdate,nil)
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
