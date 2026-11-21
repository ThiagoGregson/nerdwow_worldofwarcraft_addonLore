local t=...
local test,equal=t.test,t.equal
local function clone(value) return t.roundtrip(value) end
local function near(a,b) assert(math.abs(a-b)<.00001,tostring(a).." ~= "..tostring(b)) end
local original={test_cameraTargetFocusInteractEnable="0",test_cameraTargetFocusInteractStrengthPitch="0.42",
    test_cameraTargetFocusInteractStrengthYaw="0.67",test_cameraOverShoulder="-0.8",test_cameraHeadMovementStrength="0.25",
    CameraKeepCharacterCentered="1",CameraReduceUnexpectedMovement="1"}
local OWNER="Player-1-ABCDEF"
local function fixture(namespace,preferences)
    local n=namespace or t.core()
    local s={n=n,vars=clone(original),zoom=18.75,originalZoom=18.75,frames={},records={},now=0,calls={},
        prefs={dialogEnabled=true,cameraEnabled=true,cameraIntensity=3,hideGameUI=true},
        guid="Creature-0-1-2-3-777-000001",owner=OWNER,modelHeight=2.1,modelAt=0,modelRequests=0,visible=true,secret={}}
    local env=setmetatable({},{__index=_G}); env._G=env
    env.issecretvalue=function(value) return value==s.secret end
    env.GetServerTime=function() return 1795200000 end
    env.C_AddOns={GetAddOnMetadata=function() return "0.10.0" end}
    local function frame(name,native)
        local f={name=name,alpha=1,shown=true,scripts={},native=native,protected=native,history={}}
        function f:GetAlpha() if s.secretAlpha==self then return s.secret end; return self.alpha end
        function f:SetAlpha(value)
            assert(type(value)=="number" and value>=0 and value<=1)
            if s.failAlpha==self then error("original_alpha_error") end
            self.alpha=value; self.history[#self.history+1]=value
        end
        function f:IsForbidden() return self.forbidden==true end
        function f:IsProtected() return self.protected==true end
        function f:IsShown() return self.shown end
        function f:SetShown(value) assert(not self.native,"Show/Hide nativo proibido"); self.shown=value end
        function f:Hide() self:SetShown(false) end
        function f:SetSize() end
        function f:SetPoint() end
        function f:SetAllPoints() end
        function f:SetFrameStrata(strata) self.strata=strata end
        function f:EnableMouse(enabled) assert(not self.native,"mouse nativo proibido"); self.mouse=enabled end
        function f:SetScript(name,callback) assert(not self.native,"script nativo proibido"); self.scripts[name]=callback end
        function f:CreateActor()
            local actor={}
            function actor:SetModelByUnit(unit) equal(unit,"npc"); s.modelRequests=s.modelRequests+1; return not s.noModel end
            function actor:GetActiveBoundingBox()
                if s.noModel or s.now<s.modelAt then return nil end
                return -.5,-.4,0,.5,.4,s.modelHeight
            end
            function actor:ClearModel() end
            return actor
        end
        return f
    end
    env.UIParent=frame("UIParent",true)
    env.WorldFrame=frame("WorldFrame",true); env.StaticPopup1=frame("StaticPopup1",true)
    env.AlertFrame=frame("AlertFrame",true); env.NamePlateDriverFrame=frame("NamePlateDriverFrame",true)
    env.NerdWowTestFrame=frame("NerdWowTestFrame",false)
    for _,name in ipairs({"MainActionBar","MainMenuBar","MicroMenu","MinimapCluster","ObjectiveTrackerFrame","ChatFrame1","ChatFrame1Tab","PlayerFrame"}) do
        env[name]=frame(name,true); env[name].alpha=.73
    end
    env.InCombatLockdown=function() return s.combat==true end
    env.UnitInVehicle=function() return s.vehicle==true end
    env.UnitHasVehicleUI=function() return s.vehicle==true end
    env.UnitOnTaxi=function() return s.taxi==true end
    env.UnitExists=function(unit) equal(unit,"npc"); return s.guid~=nil end
    env.UnitIsVisible=function(unit) equal(unit,"npc"); return s.visible end
    env.UnitGUID=function(unit) return unit=="player" and s.owner or s.guid end
    env.GetCameraZoom=function() return s.zoom end
    local function move(diff)
        assert(s.store,"câmera mudou antes de guardar recuperação")
        s.calls[#s.calls+1]={zoom=s.zoom+diff}; s.zoom=s.zoom+diff
    end
    env.CameraZoomIn=function(distance) move(-distance) end
    env.CameraZoomOut=function(distance) move(distance) end
    env.C_CVar={GetCVar=function(name) return s.vars[name] end,
        GetCVarInfo=function(name) return s.vars[name],"1",false,false,s.locked==name,s.secure==name,s.readOnly==name end,
        SetCVar=function(name,value)
            assert(s.store,"CVar mudou antes de guardar recuperação")
            assert(original[name],"CVar fora da lista explícita")
            s.calls[#s.calls+1]={name=name,value=value}
            if s.refused==name then return false end
            s.vars[name]=value; return true
        end}
    env.CreateFrame=function(kind,name,parent)
        assert(kind=="Frame" or kind=="ModelScene"); equal(name,nil); equal(parent,env.UIParent)
        local f=frame(kind,false); s.frames[#s.frames+1]=f; return f
    end
    n.database={ReadCinematicRecovery=function() return s.store end,
        BindCinematicRecovery=function(value) if s.failSave then error("original_save_error") end; s.store=value end}
    if not n.Text then t.loadModule("Locales/ptBR.lua",n,env) end
    t.loadModule("Integration/Diagnostics.lua",n,env)
    n.DiagnosticAPI.Bind(function(entry) s.records[#s.records+1]=entry end)
    t.loadModule("Integration/Cinematic.lua",n,env)
    s.ui=n.CinematicIntegration.New({Preferences=preferences or function() return clone(s.prefs) end})
    s.env=env
    function s.tick(duration)
        local steps=math.max(1,math.ceil(duration/.025))
        for _=1,steps do
            s.now=s.now+duration/steps
            for _,f in ipairs(s.frames) do if f.scripts.OnUpdate then f.scripts.OnUpdate(f,duration/steps) end end
        end
    end
    function s.enter() s.ui.Enter({npc={creatureID=777}}) end
    function s.restored()
        equal(s.store,nil); near(s.zoom,s.originalZoom)
        for name,value in pairs(original) do near(tonumber(s.vars[name]),tonumber(value)) end
        for _,name in ipairs({"MainActionBar","MainMenuBar","MicroMenu","MinimapCluster","ObjectiveTrackerFrame","ChatFrame1","ChatFrame1Tab","PlayerFrame"}) do near(env[name].alpha,.73) end
        equal(env.UIParent.alpha,1); equal(env.WorldFrame.alpha,1); equal(env.StaticPopup1.alpha,1)
        equal(env.AlertFrame.alpha,1); equal(env.NerdWowTestFrame.alpha,1); equal(env.NamePlateDriverFrame.alpha,1)
        for _,f in ipairs(s.frames) do if f.mouse then equal(f.shown,false) end end
    end
    return s
end
local function flow(moment)
    local s=fixture(); local n=s.n; local native=t.surfaces.platform(n)
    local state={enabled=true,typing=true,visible=false,queued={},source=t.parchment.source(moment or "OFFER")}
    state.source.npc.creatureID=777
    local view={Hide=function() state.visible=false end,Transition=function() state.visible=true end,
        Complete=function() state.typing=false end,IsTyping=function() return state.typing end,Selection=function() end}
    function view.Show(model)
        state.model=model; state.visible=true
        if state.wait then return false,"font_pending" end
        return true
    end
    view.Refresh=view.Show
    native.api.Defer=function(callback,delay) if delay~=2 then state.queued[#state.queued+1]=callback end; return true end
    native.api.QuestAction=function(_,key,selected,retained)
        assert(native.api.CanPresent(retained)); state.action=key; state.selected=selected
    end
    state.controller=n.ConversationController.New({GetModel=function() return state.source end,
        IsEnabled=function() return state.enabled end,GetPreferences=function() return s.prefs end,
        Prepare=function(model)
            if not model.quest then return n.Conversation.Build(model) end
            return n.QuestPresentation.Build(model,{questID=model.quest.id,autoAccept=false,canComplete=true,choiceCount=2})
        end,
        View={New=function(callbacks) state.callbacks=callbacks; return view end},Platform=native.api,Effects=s.ui,
        Report=function() state.reports=(state.reports or 0)+1 end})
    function state.flush() local q=state.queued; state.queued={}; for _,fn in ipairs(q) do fn() end end
    state.native=native; state.effects=s
    return state
end

test("câmera registra campos declarativos e livro ativo preserva Personagem em breve",function()
    local n=t.core(); local h,root,issues=n.Settings.Open({schemaVersion=1,minimapAngle=39,extension=true})
    equal(#issues,0); equal(root.cameraEnabled,true); equal(root.hideGameUI,true); equal(root.cameraIntensity,3)
    for i=1,5 do assert(h.Set("cameraIntensity",i)) end
    for _,i in ipairs({0,6,1.5,"3",false}) do equal(h.Set("cameraIntensity",i),nil) end
    local book=n.ConfigurationBook.New({Registry=n.ConfigurationCatalog,Settings=h})
    book.Select("camera"); local snapshot=book.Snapshot(); assert(not snapshot.header.soon)
    for _,spec in ipairs(snapshot.options) do equal(spec.enabled,true); assert(spec.field) end
    h.Set("cameraEnabled",false); h.Set("hideGameUI",false)
    root.cinematicRecovery={keep=true}; h.Reset(n.ConfigurationCatalog.Fields())
    equal(root.cameraIntensity,3); equal(root.cameraEnabled,true); equal(root.hideGameUI,true)
    equal(root.minimapAngle,39); equal(root.cinematicRecovery.keep,true)
end)

test("intensidade aproxima progressivamente pela altura sem primeira pessoa ou afastamento",function()
    local n=t.core()
    for _,height in ipairs({.8,2.1,5,12}) do
        local before=100
        for i=1,5 do local zoom=n.Cinematic.Target(i,height,18); assert(zoom<=before and zoom<=18 and zoom>=1.2); before=zoom end
    end
    for _,height in ipairs({0,-1,math.huge,0/0,21}) do equal(n.Cinematic.Target(3,height,18),nil) end
end)

test("política pura exige dados seguros explícitos antes de permitir efeitos",function()
    local n=t.core(); local p={dialogEnabled=true,cameraEnabled=true,cameraIntensity=3,hideGameUI=true}
    local context={creature=true,hasUI=true}
    equal(n.Cinematic.Plan(p,context).camera,false); equal(n.Cinematic.Plan(p,context).hide,false)
    context.combat=false; context.vehicle=false; context.taxi=false; context.cinematic=false
    equal(n.Cinematic.Plan(p,context).camera,true); equal(n.Cinematic.Plan(p,context).hide,true)
end)

test("snapshot completo antecede setters e saída restaura valores não padrão sem tocar alertas",function()
    local s=fixture(); s.enter(); equal(s.store.version,1); equal(s.store.characterKey,OWNER)
    equal(s.store.zoom,18.75); equal(t.serialize(s.store.cvars),t.serialize(original)); s.tick(1)
    assert(s.zoom<18.75); equal(s.env.MainMenuBar.alpha,0); equal(s.env.MinimapCluster.alpha,0)
    equal(s.env.MainActionBar.alpha,0); equal(s.env.MicroMenu.alpha,0); equal(s.env.ChatFrame1Tab.alpha,0)
    equal(s.env.UIParent.alpha,1); equal(s.env.AlertFrame.alpha,1)
    s.ui.Leave(); s.tick(1); s.restored(); equal(#s.records,0)
end)

test("retorno no meio da transição parte do estado atual e não deixa atualização presa",function()
    local s=fixture(); s.enter(); s.tick(.13); assert(s.env.MainMenuBar.alpha>0 and s.env.MainMenuBar.alpha<.73)
    local alpha=s.env.MainMenuBar.alpha; s.ui.Leave(); near(s.env.MainMenuBar.alpha,alpha)
    s.tick(.1); assert(s.env.MainMenuBar.alpha>alpha); s.tick(1); s.restored()
    for _,f in ipairs(s.frames) do equal(f.scripts.OnUpdate,nil) end
end)

test("modelo tardio inicia câmera uma vez e nunca faz o HUD piscar de volta",function()
    local s=fixture(); s.modelAt=.5; s.enter(); equal(s.store,nil); s.tick(.3); equal(s.env.MainMenuBar.alpha,0)
    s.tick(.3); assert(s.store); equal(s.env.MainMenuBar.alpha,0); equal(s.modelRequests,1)
    s.tick(1); s.ui.Leave(true); s.restored()
end)

test("objetos itens sem NPC modelo invisível ou ausente não alteram câmera",function()
    for _,kind in ipairs({"object","item","invisible","model"}) do
        local s=fixture()
        if kind=="object" then s.guid="GameObject-0-1-2-3-777-000001"
        elseif kind=="item" then s.guid=nil
        elseif kind=="invisible" then s.visible=false
        else s.noModel=true end
        s.enter(); s.tick(2); equal(#s.calls,0); equal(s.store,nil)
        s.ui.Leave(true); s.restored()
    end
end)

test("veículo táxi combate e cinematics preservam câmera e controles na abertura",function()
    for _,kind in ipairs({"vehicle","taxi","combat","cinematic"}) do
        local s=fixture()
        if kind=="cinematic" then s.env.CinematicFrame={IsShown=function() return true end} else s[kind]=true end
        s.enter(); s.tick(2); equal(#s.calls,0); s.restored()
    end
end)

test("opções desligadas e cinema desligado impedem seus efeitos independentemente",function()
    for _,key in ipairs({"cameraEnabled","hideGameUI","dialogEnabled"}) do
        local s=fixture(); s.prefs[key]=false; s.enter(); s.tick(1)
        if key=="cameraEnabled" or key=="dialogEnabled" then equal(#s.calls,0) end
        if key=="hideGameUI" or key=="dialogEnabled" then near(s.env.MainMenuBar.alpha,.73) end
        s.ui.Leave(true); s.restored()
    end
end)

test("preferências permanecem congeladas até a próxima abertura e modos não reiniciam efeitos",function()
    local s=fixture(); s.enter(); s.tick(.3); local snapshot=t.serialize(s.store); local calls=#s.calls
    s.prefs.cameraIntensity=5; s.prefs.cameraEnabled=false; s.prefs.hideGameUI=false
    s.ui.Enter({npc={creatureID=777},moment="COMPLETE"}); equal(t.serialize(s.store),snapshot); equal(#s.calls,calls)
    s.tick(1); equal(s.env.MainMenuBar.alpha,0); near(s.zoom,2.1*1.75)
    s.ui.Leave(); s.tick(1); s.enter(); s.tick(1); s.restored()
end)

test("combate durante entrada ou saída restaura tudo e não reaplica na mesma sessão",function()
    for _,when in ipairs({.1,1}) do for _,leaving in ipairs({false,true}) do
        local s=fixture(); s.enter(); s.tick(when); if leaving then s.ui.Leave(); s.tick(.1) end
        s.combat=true; s.ui.Handle("PLAYER_REGEN_DISABLED"); s.restored()
        s.combat=false; s.ui.Handle("PLAYER_REGEN_ENABLED"); s.tick(1); s.restored()
    end end
end)

test("reload simulado restaura recuperação antes de novo enquadramento e limpa só após sucesso",function()
    local s=fixture(); s.enter(); s.tick(1)
    local next=fixture(); next.store=clone(s.store); next.vars=clone(s.vars); next.zoom=s.zoom
    next.ui.Recover(); next.tick(1); next.restored(); equal(#next.records,0)
end)

test("recuperação inválida ou de outro personagem é preservada sem executar CVars arbitrárias",function()
    local s=fixture(); s.enter(); local saved=clone(s.store)
    for _,kind in ipairs({"other","unknown","invalid","secret","future"}) do
        local next=fixture(); next.store=clone(saved)
        if kind=="other" then next.store.characterKey="Player-2-OTHER"
        elseif kind=="unknown" then next.store.cvars.UnitNameNPC="0"
        elseif kind=="invalid" then next.store.zoom=-1
        elseif kind=="future" then next.store.version=2
        else next.store.cvars.test_cameraOverShoulder=next.secret end
        local originalStore=next.store; next.ui.Recover(); next.ui.Recover()
        equal(next.store,originalStore); equal(#next.calls,0)
        if kind~="other" then equal(#next.records,1) end
    end
    s.ui.Leave(true); s.restored()
end)

test("CVar bloqueada segura ou readonly impede transação sem mutação parcial",function()
    for _,field in ipairs({"locked","secure","readOnly"}) do
        local s=fixture(); s[field]="test_cameraOverShoulder"; s.enter(); s.tick(1)
        equal(#s.calls,0); equal(s.store,nil); equal(#s.records,1)
        s.ui.Leave(true); s.restored()
    end
end)

test("recusa de setter tenta todos os valores preserva recuperação e permite nova tentativa",function()
    local s=fixture(); s.enter(); s.tick(1); s.refused="test_cameraOverShoulder"; s.ui.Leave(true); s.tick(3)
    assert(s.store); assert(#s.records>=1)
    near(tonumber(s.vars.test_cameraHeadMovementStrength),tonumber(original.test_cameraHeadMovementStrength))
    local count=#s.records; s.tick(3); equal(#s.records,count)
    s.refused=nil; s.ui.Leave(true); s.restored()
    s.enter(); s.tick(1); assert(s.zoom<s.originalZoom); s.ui.Leave(true); s.restored()
end)

test("aplicação parcial recusada recompõe câmera e não deixa erro permanente na próxima abertura",function()
    local s=fixture(); s.refused="CameraKeepCharacterCentered"; s.enter(); s.tick(1)
    equal(s.store,nil); equal(#s.records,1)
    for name,value in pairs(original) do near(tonumber(s.vars[name]),tonumber(value)) end
    s.refused=nil; s.ui.Leave(true); s.enter(); s.tick(1); assert(s.store)
    s.ui.Leave(true); s.restored()
end)

test("falha ao guardar recuperação nunca aplica câmera e alpha secreto não é serializado",function()
    local s=fixture(); s.failSave=true; s.enter(); s.tick(1); equal(#s.calls,0); equal(s.store,nil)
    s.failSave=false; s.ui.Leave(true); s.restored()
    s=fixture(); s.secretAlpha=s.env.MainMenuBar; s.enter(); s.tick(1)
    equal(s.env.MainMenuBar.alpha,.73); assert(#s.records>0)
    s.secretAlpha=nil; s.ui.Leave(true); s.restored()
end)

test("modelo secreto aborta câmera sem persistir o valor ou afetar interface nativa",function()
    local s=fixture(); s.modelHeight=s.secret; s.enter(); s.tick(2)
    equal(#s.calls,0); equal(s.store,nil); near(s.env.MainMenuBar.alpha,.73); equal(#s.records,1)
end)

test("container carregado durante diálogo herda fade sem perder alpha original",function()
    local s=fixture(); s.enter(); s.tick(1)
    local fresh={alpha=.41}; function fresh:GetAlpha() return self.alpha end; function fresh:SetAlpha(a) self.alpha=a end
    s.env.MultiBar7=fresh; s.ui.Handle("ADDON_LOADED","Blizzard_Test"); equal(fresh.alpha,0)
    s.ui.Handle("ADDON_LOADED","Blizzard_Test"); s.ui.Leave(true); near(fresh.alpha,.41); s.restored()
end)

test("reexibição nativa de chat ou tracker permanece recolhida até sair do diálogo",function()
    local s=fixture(); s.enter(); s.tick(1)
    s.env.ChatFrame1.alpha=1; s.env.ObjectiveTrackerFrame.alpha=1
    s.tick(.2); equal(s.env.ChatFrame1.alpha,0); equal(s.env.ObjectiveTrackerFrame.alpha,0)
    s.ui.Leave(); s.tick(1); s.restored()
end)

test("aviso experimental nativo permanece visível e nenhum evento global é desregistrado",function()
    local s=fixture()
    function s.env.UIParent:UnregisterEvent() error("evento experimental não pode ser desregistrado") end
    s.env.StaticPopup1.shown=false
    local setter=s.env.C_CVar.SetCVar
    s.env.C_CVar.SetCVar=function(name,value)
        s.env.StaticPopup1.shown=true
        return setter(name,value)
    end
    s.enter(); s.tick(1); equal(s.env.StaticPopup1.alpha,1); equal(s.env.StaticPopup1.shown,true)
    equal(#s.records,0); s.ui.Leave(true); s.restored()
end)

test("trocas de momentos com fonte pendente conservam câmera HUD e recuperação",function()
    local f=flow(); f.controller.Refresh(); f.effects.tick(.3); local saved=t.serialize(f.effects.store)
    local zoom=f.effects.zoom
    for _,moment in ipairs({"PROGRESS","COMPLETE","OFFER"}) do
        f.source=t.parchment.source(moment); f.source.npc.creatureID=777; f.wait=true
        f.controller.Refresh(); equal(f.visible,true); equal(t.serialize(f.effects.store),saved); equal(f.effects.zoom,zoom)
        f.wait=false; f.callbacks.Ready(); f.flush(); equal(t.serialize(f.effects.store),saved)
    end
    f.controller.Close(); f.effects.tick(1); f.effects.restored()
end)

test("diálogo aberto continua utilizável em combate com câmera e HUD restaurados",function()
    for _,moment in ipairs({"OFFER","PROGRESS","COMPLETE"}) do
        local f=flow(moment); f.controller.Refresh(); f.effects.tick(1)
        f.effects.combat=true; f.native.combat=true; f.effects.ui.Handle("PLAYER_REGEN_DISABLED"); f.controller.Handle("PLAYER_REGEN_DISABLED")
        f.effects.restored(); equal(f.visible,true)
        assert(f.native.api.KeyAllowed(true)); f.controller.Key("SPACE"); equal(f.typing,false)
        if moment=="COMPLETE" then f.controller.Key("2") end
        f.controller.Key("SPACE"); equal(f.action,moment=="OFFER" and "ACCEPT" or moment=="PROGRESS" and "CONTINUE" or "FINISH")
        equal(f.reports,nil); f.controller.Close(); equal(f.visible,false); f.effects.restored()
    end
end)

test("falha da view desligamento e saída restauram efeitos sem deixar missão sem tela",function()
    for _,kind in ipairs({"failure","toggle","world"}) do
        local f=flow(); f.controller.Refresh(); f.effects.tick(1)
        if kind=="failure" then f.controller.Fail("render_error")
        elseif kind=="toggle" then f.enabled=false; f.controller.Toggle()
        else f.effects.ui.Handle("PLAYER_LEAVING_WORLD"); f.controller.Handle("PLAYER_LEAVING_WORLD") end
        f.effects.tick(1); f.effects.restored(); equal(f.visible,false); equal(f.native.root.alpha,.75)
    end
end)

test("conversa nova em combate permanece nativa e frames protegidos continuam recusados",function()
    local f=flow(); f.native.combat=true; f.effects.combat=true; f.controller.Refresh()
    equal(f.visible,false); equal(#f.effects.calls,0); equal(f.native.root.alpha,.75)
    f=flow(); f.controller.Refresh(); f.effects.tick(1)
    f.native.combat=true; f.effects.combat=true; f.controller.Handle("PLAYER_REGEN_DISABLED")
    f.native.env.QuestFrame.protected=true; f.controller.Refresh()
    f.effects.restored(); equal(f.visible,false); assert(f.reports)
end)

test("novos eventos de efeitos na composição não acrescentam capturas ao diário",function()
    local c=t.client(); c.start(); local before=t.serialize(c.saved())
    for _,event in ipairs({"PLAYER_LOGOUT","UNIT_ENTERED_VEHICLE","PLAYER_CONTROL_LOST","CINEMATIC_START","PLAY_MOVIE"}) do c.fire(event,"player") end
    equal(t.serialize(c.saved()),before)
end)

test("primeira pessoa preserva câmera e valores secretos de CVar não entram na recuperação",function()
    local s=fixture(); s.zoom=0; s.originalZoom=0; s.enter(); s.tick(1)
    equal(#s.calls,0); s.ui.Leave(true); s.restored()
    s=fixture(); s.vars.test_cameraOverShoulder=s.secret; s.enter(); s.tick(1)
    equal(#s.calls,0); equal(s.store,nil); equal(#s.records,1)
end)

test("erro de alpha restaura os demais controles e uma nova saída repete o valor pendente",function()
    local s=fixture(); s.enter(); s.tick(1); s.failAlpha=s.env.MainMenuBar
    s.ui.Leave(true); equal(s.env.MinimapCluster.alpha,.73); equal(s.store,nil)
    equal(s.env.MainMenuBar.alpha,0); equal(#s.records,1)
    s.failAlpha=nil; s.ui.Leave(true); s.restored()
end)

test("falha ao criar animação restaura imediatamente em vez de deixar a câmera aplicada",function()
    local s=fixture(); local create=s.env.CreateFrame
    s.env.CreateFrame=function(kind,...)
        if kind=="Frame" and #s.frames>=2 then error("update_frame_failed") end
        return create(kind,...)
    end
    s.enter(); s.restored(); equal(#s.records,1)
end)

test("Bootstrap recupera snapshot persistido do mesmo personagem antes da primeira conversa",function()
    local saved={schemaVersion=1,cinematicRecovery={version=1,characterKey=t.A,zoom=18.75,cvars=clone(original)}}
    local c=t.client(nil,saved); local vars={}; for key in pairs(original) do vars[key]="0" end
    local zoom=3
    c.env.C_CVar={GetCVar=function(name) return vars[name] end,GetCVarInfo=function() end,
        SetCVar=function(name,value) assert(original[name]); vars[name]=value; return true end}
    c.env.GetCameraZoom=function() return zoom end
    c.env.CameraZoomIn=function(diff) zoom=zoom-diff end
    c.env.CameraZoomOut=function(diff) zoom=zoom+diff end
    c.start(); equal(c.settings().cinematicRecovery,nil); near(zoom,18.75)
    equal(t.serialize(vars),t.serialize(original)); equal(#c.saved().events,2)
end)

test("área de recuperação distingue false inválido de ausência e Reset não a apaga",function()
    local c=t.client(nil,{schemaVersion=1,cinematicRecovery=false}); c.start()
    equal(c.namespace.database.ReadCinematicRecovery(),false); equal(c.settings().cinematicRecovery,false)
    local count=0; for _,entry in ipairs(c.diagnostics().entries) do if entry.code=="camera_recovery_invalid" then count=count+1 end end
    equal(count,1)
end)

test("Bootstrap liga efeitos ao diálogo e combate sem gravar eventos ou acionar câmera com cinema desligado",function()
    local c=t.client(); local surface=t.surfaces.wire(c); local log={}
    c.namespace.ConversationPlatform.CanPresent=function(retained) return not c.inCombat or retained==true end
    local create=c.namespace.CinematicIntegration.New
    c.namespace.CinematicIntegration.New=function(options)
        local actual=create(options); local proxy={}
        for _,key in ipairs({"Enter","Leave","Suspend","Recover","Handle"}) do
            local method=key
            proxy[method]=function(...)
                log[#log+1]=method
                return actual[method](...)
            end
        end
        return proxy
    end
    c.start(); c.fire("GOSSIP_SHOW"); c.flush(); equal(surface.visible,true)
    local enters=0; for _,key in ipairs(log) do if key=="Enter" then enters=enters+1 end end
    assert(enters>0); c.inCombat=true; c.fire("PLAYER_REGEN_DISABLED"); equal(surface.visible,true)
    local before=t.serialize(c.saved()); c.command("dialogo"); equal(surface.visible,false)
    equal(t.serialize(c.saved()),before)
    enters=0; for _,key in ipairs(log) do if key=="Enter" then enters=enters+1 end end
    c.fire("GOSSIP_SHOW"); c.flush()
    local after=0; for _,key in ipairs(log) do if key=="Enter" then after=after+1 end end; equal(after,enters)
    local leave=false; for _,key in ipairs(log) do if key=="Leave" then leave=true end end; assert(leave)
end)

test("capítulo ativo usa widgets reais e alterações só afetam próxima abertura dos efeitos",function()
    local book=t.configuration.scene(); book.open(); book.select("Câmera e interface")
    local camera=book.control("camera","Button"); local zoom=book.control("zoom","Slider"); local hud=book.control("interface","Button")
    equal(camera.enabled,true); equal(hud.enabled,true); equal(zoom.minimum,1); equal(zoom.maximum,5)
    zoom:SetValue(5); equal(book.root.cameraIntensity,5); camera.scripts.OnClick(camera); equal(book.root.cameraEnabled,false)
    hud.scripts.OnClick(hud); equal(book.root.hideGameUI,false)
    book.select("Restaurar padrões"); book.select("Restaurar")
    equal(book.root.cameraEnabled,true); equal(book.root.hideGameUI,true); equal(book.root.cameraIntensity,3)
    book.n.ConfigurationUI.Close()
end)

return {fixture=fixture,flow=flow}
