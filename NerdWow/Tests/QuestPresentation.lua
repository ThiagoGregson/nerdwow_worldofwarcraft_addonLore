local t=...
local test,equal=t.test,t.equal
local function source(moment)
    return {moment=moment or "OFFER",quest={id=101,title="Os nomes nas margens",
        description="Áurea é a memória destes tomos. Centenas de nomes esperam por uma voz.\n\nTraga os tomos antes que a umidade termine o trabalho do fogo.",
        objectiveText="Recupere os três tomos chamuscados.",progressText="Ainda sinto o cheiro da umidade. Encontrou os tomos?",
        rewardText="Anaris. Telenor. Myriel Corvaprata… Ouviu? Estão de volta."},
        npc={name="Arquivista Velann",title="Guardiã dos Tomos Queimados",faction="Alliance",creatureID=777},
        location={zone="Lua-prata",subZone="Corredor dos Arquivistas",mapID=2393},
        objectives={{index=1,text="Tomos chamuscados",fulfilled=2,required=3,finished=false},
            {index=2,text="Leia os nomes no memorial",fulfilled=1,required=1,finished=true}},
        requiredItems={{index=1,itemID=503,name="Tomo chamuscado",icon=1236,quantity=3,quality=1}},
        rewards={choices={{index=1,itemID=501,name="Tinteiro da Vigília",icon=1234,quantity=1,quality=3},
            {index=2,itemID=502,name="Pena de Myriel",icon=1235,quantity=2,quality=4}},
            fixed={{index=1,itemID=504,name="Memórias do arquivo",icon=1237,quantity=3,quality=2}},money=120040,experience=550}}
end
local function core()
    local n=t.core(); t.loadModule("Locales/ptBR.lua",n,{})
    return n
end
local function build(n,model,state,receipt)
    state=state or {questID=model.quest.id,autoAccept=false,canComplete=false,choiceCount=#model.rewards.choices}
    return assert(n.QuestPresentation.Build(model,state,receipt))
end
local function scene(moment,async)
    local n=core(); local p=t.surfaces.platform(n); local r=t.surfaces.renderer(n,async)
    local s={n=n,p=p,r=r,source=source(moment),calls={},receipt=nil,reports=0,autoAccept=false,completable=false}
    local env=r.env
    env.GetQuestID=function() return s.actualID or s.source.quest.id end
    env.QuestGetAutoAccept=function() return s.autoAccept end
    env.IsQuestCompletable=function() return s.completable end
    env.QuestFlagsPVP=function() return s.pvp==true end
    env.GetQuestMoneyToGet=function() return s.cost or 0 end
    env.GetNumQuestChoices=function() return #s.source.rewards.choices end
    env.GetQuestItemInfo=function(_,index)
        local item=s.source.rewards.choices[index]
        return item.name,item.icon,item.quantity,item.quality,true,item.itemID
    end
    for _,name in ipairs({"AcceptQuest","AcknowledgeAutoAcceptQuest","CompleteQuest","CloseQuest","GetQuestReward"}) do
        local key=name
        env[name]=function(index)
            if s.actionError then error("quest_action_original") end
            s.calls[#s.calls+1]={key=key,index=index}
        end
    end
    env.GameTooltip={SetOwner=function(_,owner,anchor) s.owner=owner; equal(anchor,"ANCHOR_RIGHT") end,
        SetQuestItem=function(_,kind,index) s.tip={kind=kind,index=index} end,
        Show=function() s.tipShown=true end,IsOwned=function(_,owner) return owner==s.owner end,
        Hide=function() s.owner=nil; s.tipShown=false end}
    env.C_Texture={GetAtlasInfo=function() return {} end}
    t.loadModule("Integration/QuestPresentation.lua",n,env)
    s.c=n.ConversationController.New({GetModel=function() return s.source end,IsEnabled=function() return not s.disabled end,
        Prepare=function(model) return n.QuestPresentation.Build(model,n.QuestPlatform.ReadState(model),s.receipt) end,
        View=n.ConversationView,Platform=p.api,Try=n.DiagnosticAPI.Try,
        Diagnose=function(fault,context) s.fault=fault; s.stage=context.stage end,
        Report=function() s.reports=s.reports+1 end})
    function s.root()
        for _,f in ipairs(r.frames) do if f.strata=="DIALOG" then return f end end
    end
    function s.button(text)
        for _,region in ipairs(r.regions) do
            if region.text==text and region.parent.kind=="Button" then return region.parent end
        end
    end
    function s.text(text)
        for _,region in ipairs(r.regions) do if region.text==text then return region end end
    end
    return s
end

test("pergaminho projeta três momentos sem alterar modelo ou texto integral",function()
    local n=core()
    for _,moment in ipairs({"OFFER","PROGRESS","COMPLETE"}) do
        local model=source(moment); local before=t.serialize(model); local view=build(n,model)
        equal(view.kind,"quest"); equal(view.quest.id,101); equal(view.theme.key,"quelthalas")
        equal(view.text,n.QuestPresentation.Short(view.paper.text)); equal(t.serialize(model),before)
        assert(#view.text<#view.paper.text or moment~="OFFER")
        if moment=="COMPLETE" then equal(#view.paper.objectives,0); equal(#view.entries,2) end
    end
    local drop,rest=n.QuestPresentation.Drop("Áurea memória."); equal(drop,"Á"); equal(drop..rest,"Áurea memória.")
    equal(n.QuestPresentation.Drop("|cffff0000Texto|r"),nil)
    equal(n.QuestPresentation.Short(string.rep("á",300)),string.rep("á",110).."…")
end)

test("ações de missão distinguem autoaceite progresso e escolha obrigatória única ou ausente",function()
    local n=core(); local model=source(); local view=build(n,model)
    local actions=n.QuestPresentation.Actions(view); equal(actions[1].key,"ACCEPT"); equal(actions[2].key,"DECLINE")
    view=build(n,model,{questID=101,autoAccept=true}); actions=n.QuestPresentation.Actions(view)
    equal(#actions,1); equal(actions[1].key,"CONFIRM")
    model=source("PROGRESS"); view=build(n,model); equal(n.QuestPresentation.Actions(view)[1].enabled,false)
    view.state.canComplete=true; equal(n.QuestPresentation.Actions(view)[1].enabled,true)
    model=source("COMPLETE"); view=build(n,model); equal(n.QuestPresentation.Actions(view)[1].enabled,false)
    equal(n.QuestPresentation.Actions(view,2)[1].enabled,true)
    model.rewards.choices[2]=nil; view=build(n,model); equal(view.selected,1)
    model.rewards.choices={}; view=build(n,model); equal(n.QuestPresentation.Actions(view)[1].enabled,true)
    equal(n.QuestPresentation.Build(model,{questID=101,choiceCount=1}),nil)
end)

test("legenda e pergaminho nunca se cruzam nas proporções e escalas suportadas",function()
    local n=core()
    for _,size in ipairs({{1920,1080},{3440,1440},{5120,1440}}) do
        for _,scale in ipairs({.64,.8,1,1.25}) do
            local l=assert(n.QuestPresentation.Layout(size[1]/scale,size[2]/scale))
            assert(l.textLeft-84*l.scale>0)
            assert(l.textLeft+l.textWidth+25*l.scale<l.paperLeft)
            assert(l.paperLeft+l.paperWidth<size[1]/scale)
            assert(l.paperTop+l.paperHeight<size[2]/scale)
            assert(l.textWidth>180*l.scale)
        end
    end
end)

test("renderer do pergaminho exibe papel capitular itens rodapé e nota real nos três momentos",function()
    for _,moment in ipairs({"OFFER","PROGRESS","COMPLETE"}) do
        local s=scene(moment); s.receipt={questID=101,kind=moment=="OFFER" and "QUEST_OFFERED" or "QUEST_PROGRESS_VIEWED"}
        s.c.Refresh(); equal(s.reports,0); equal(s.root().shown,true); equal(s.p.env.QuestFrame.alpha,0)
        s.root().scripts.OnUpdate(s.root(),1)
        assert(s.text(s.source.quest.title)); assert(s.text("Arquivista Velann · Guardiã dos Tomos Queimados"))
        if moment=="OFFER" then assert(s.text("Á")); assert(s.button("Aceitar")); assert(s.button("Recusar")) end
        if moment=="PROGRESS" then assert(s.text("Tomo chamuscado")); equal(s.button("Continuar").enabled,false) end
        if moment=="COMPLETE" then assert(s.text("Pena de Myriel")); equal(s.button("Concluir").enabled,false) end
        local paper=false; for _,region in ipairs(s.r.regions) do if region.atlas=="QuestBG-Parchment" then paper=true end end
        assert(paper); s.c.Close(); equal(s.root().keyboard,false); equal(s.root().scripts.OnUpdate,nil)
        equal(s.p.env.QuestFrame.alpha,.75)
    end
end)

test("clique e atalhos de recompensa habilitam concluir e chamam índice oficial uma vez",function()
    for _,byKey in ipairs({false,true}) do
        local s=scene("COMPLETE"); s.c.Refresh(); equal(s.c.Action("FINISH"),false); equal(#s.calls,0)
        if byKey then s.root().scripts.OnKeyDown(s.root(),"2")
        else local b=s.button("Pena de Myriel"); b.scripts.OnClick(b) end
        equal(s.button("Concluir").enabled,true)
        local finish=s.button("Concluir"); finish.scripts.OnClick(finish); finish.scripts.OnClick(finish)
        equal(#s.calls,1); equal(s.calls[1].key,"GetQuestReward"); equal(s.calls[1].index,2)
        equal(s.root().shown,false); equal(s.reports,0)
    end
end)

test("ações pelas APIs oficiais respeitam autoaceite e progresso revalidado",function()
    local s=scene("OFFER"); s.r.env.GetQuestMoneyToGet=function() error("oferta não consulta custo de entrega") end
    s.c.Refresh(); s.c.Action("ACCEPT"); equal(s.calls[1].key,"AcceptQuest")
    s=scene("OFFER"); s.autoAccept=true; s.c.Refresh(); assert(not s.button("Aceitar"))
    s.c.Action("CONFIRM"); equal(s.calls[1].key,"AcknowledgeAutoAcceptQuest")
    s=scene("PROGRESS"); s.c.Refresh(); equal(s.c.Action("CONTINUE"),false); equal(#s.calls,0)
    s.completable=true; s.c.Handle("QUEST_LOG_UPDATE"); equal(s.button("Continuar").enabled,true)
    s.completable=false; s.c.Action("CONTINUE"); equal(#s.calls,0); equal(s.reports,1)
    equal(s.root().shown,false); equal(s.p.env.QuestFrame.alpha,.75)
    s=scene("COMPLETE"); s.r.env.GetQuestMoneyToGet=function() return nil end
    s.c.Refresh(); s.c.Choose(2); s.c.Action("FINISH"); equal(s.calls[1].key,"GetQuestReward")
end)

test("tooltip de item usa fonte e índice nativos e não oculta tooltip de outro dono",function()
    local s=scene("COMPLETE"); s.c.Refresh()
    local b=s.button("Memórias do arquivo"); b.scripts.OnEnter(b)
    equal(s.tip.kind,"reward"); equal(s.tip.index,1); equal(s.tipShown,true)
    s.owner={}; b.scripts.OnLeave(b); equal(s.tipShown,true)
    s.owner=b; b.scripts.OnLeave(b); equal(s.tipShown,false)
    s.c.Close()
end)

test("falha de ação ou identidade alterada restaura Blizzard com causa sem executar entrega",function()
    for _,mode in ipairs({"error","quest","item","combat"}) do
        local s=scene("COMPLETE"); s.c.Refresh(); s.c.Choose(2)
        if mode=="error" then s.actionError=true
        elseif mode=="quest" then s.actualID=999
        elseif mode=="item" then s.source.rewards.choices[2].itemID=999
        else s.p.combat=true end
        s.c.Action("FINISH"); equal(#s.calls,0); equal(s.root().shown,false); equal(s.p.env.QuestFrame.alpha,.75)
        if mode~="combat" then equal(s.reports,1); assert(s.fault.message); assert(s.fault.stack) end
    end
end)

test("nota de diário exige resultado real e título simples respeita metadados de tooltip",function()
    local n=core(); local view=build(n,source("COMPLETE"))
    equal(n.QuestPresentation.Note(view),n.Text.questWillRecord)
    view.recorded="QUEST_COMPLETED"; equal(n.QuestPresentation.Note(view),n.Text.questRecorded.QUEST_COMPLETED)
    local c=t.client(); c.start()
    c.npc.name="Erma"; c.npc.subtitle=nil
    for _,value in ipairs({"Mestre de Estábulo","<Mestre de Estábulo>"}) do
        c.unitTooltip={lines={{type=2,leftText="Erma"},{type=0,leftText=value},{type=47,leftText="Nível 30"}}}
        c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent().npc.title,"Mestre de Estábulo")
    end
    for _,line in ipairs({{type=47,leftText="Nível 30"},{type=48,leftText="Humanoide"},{type=0,leftText="Alliance"}}) do
        c.unitTooltip={lines={{type=2,leftText="Erma"},line,{type=47,leftText="Nível 30"}}}
        c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent().npc.title,nil)
    end
end)

test("atualização de itens preserva escolha válida e invalida opção que mudou",function()
    local s=scene("COMPLETE"); s.c.Refresh(); s.c.Choose(2)
    s.c.Handle("QUEST_ITEM_UPDATE"); equal(s.button("Concluir").enabled,true)
    s.source.rewards.choices[2].itemID=999
    s.c.Handle("QUEST_ITEM_UPDATE"); equal(s.button("Concluir").enabled,false)
    s.c.Close()
end)

test("conversa pendente de fonte entra em missão sem polling permanente e pode ser desligada",function()
    local s=scene("OFFER",true)
    s.r.fontBehavior=function(path)
        if path:find("NerdWow\\Fonts\\",1,true) and not s.r.loaded[path] then return {delay=.4} end
    end
    s.c.Refresh(); equal(s.p.env.QuestFrame.alpha,.75)
    s.r.drain(); equal(s.reports,0); equal(s.root().shown,true); equal(s.p.env.QuestFrame.alpha,0)
    s.disabled=true; s.c.Toggle(); equal(s.root().shown,false); equal(s.root().keyboard,false)
    s.r.drain(); equal(#s.r.timers,0); equal(s.p.env.QuestFrame.alpha,.75)
end)

test("ações do pergaminho mantêm captura oficial e chosenReward sem duplicar eventos",function()
    local c=t.client(); local ui=t.surfaces.wire(c); c.start()
    c.env.AcceptQuest=function() c.fire("QUEST_ACCEPTED",101); c.fire("QUEST_FINISHED") end
    c.env.CloseQuest=function() c.fire("QUEST_FINISHED") end
    c.env.AcknowledgeAutoAcceptQuest=function() c.fire("QUEST_FINISHED") end
    c.env.CompleteQuest=function() c.fire("QUEST_COMPLETE") end
    c.fire("QUEST_DETAIL"); c.flush()
    equal(ui.view.kind,"quest"); equal(ui.view.recorded,"QUEST_OFFERED")
    ui.callbacks.Action("ACCEPT")
    equal(c.saved().events[#c.saved().events].type,"QUEST_ACCEPTED")
    c.fire("QUEST_PROGRESS"); c.flush(); equal(ui.view.recorded,"QUEST_PROGRESS_VIEWED")
    c.completable=true; c.fire("QUEST_PROGRESS"); c.flush(); ui.callbacks.Action("CONTINUE"); c.flush()
    equal(ui.view.moment,"COMPLETE")
    ui.callbacks.Choose(2); ui.callbacks.Action("FINISH")
    c.fire("QUEST_TURNED_IN",101,450,120); c.fire("QUEST_FINISHED")
    local count=0
    for _,event in ipairs(c.saved().events) do
        if event.type=="QUEST_COMPLETED" then count=count+1; equal(event.payload.chosenReward.itemID,502) end
    end
    equal(count,1); equal(ui.visible,false)
end)

test("diário bloqueado e evento não gravado não recebem nota de sucesso",function()
    local c=t.client({schemaVersion=99}); local ui=t.surfaces.wire(c); c.start()
    c.fire("QUEST_DETAIL"); c.flush(); equal(ui.view.kind,"quest"); equal(ui.view.recorded,nil)
    equal(c.namespace.QuestPresentation.Note(ui.view),"")
    local n=core(); local view=build(n,source("COMPLETE"),nil,{questID=101,kind="QUEST_PROGRESS_VIEWED"})
    equal(n.QuestPresentation.Note(view),n.Text.questWillRecord)
end)

test("texto longo rola no papel com rodapé fixo e animação termina sem reiniciar em atualização",function()
    local s=scene("COMPLETE"); s.source.quest.rewardText=string.rep("Uma memória antiga que ainda precisa ser contada. ",180)
    s.c.Refresh(); local root=s.root(); root.scripts.OnUpdate(root,.4)
    s.c.Choose(2)
    local beforeUpdate=root.scripts.OnUpdate; local beforeAlpha=root.alpha
    local finish=s.button("Concluir"); local x,y=finish.points[1][4],finish.points[1][5]
    local item=s.button("Pena de Myriel"); local scroll=item.parent.parent
    assert(scroll:GetVerticalScrollRange()>0); scroll.scripts.OnMouseWheel(scroll,-2)
    local offset=scroll:GetVerticalScroll(); assert(offset>0)
    s.c.Handle("QUEST_ITEM_UPDATE")
    equal(root.scripts.OnUpdate,beforeUpdate); equal(root.alpha,beforeAlpha)
    equal(scroll:GetVerticalScroll(),offset); equal(finish.enabled,true)
    equal(finish.points[1][4],x); equal(finish.points[1][5],y)
    root.scripts.OnUpdate(root,1)
    equal(root.scripts.OnUpdate,nil); equal(s.reports,0); s.c.Close()
end)

test("teclas de missão respeitam foco modificadores espaço e fechamento oficial",function()
    local offer=scene("OFFER"); offer.c.Refresh()
    offer.root().scripts.OnKeyDown(offer.root(),"1"); equal(offer.root().propagate,true); offer.c.Close()
    local s=scene("COMPLETE"); s.c.Refresh(); local root=s.root()
    s.p.focus=true; root.scripts.OnKeyDown(root,"2"); equal(root.propagate,true); equal(s.button("Concluir").enabled,false)
    s.p.focus=false; s.p.ctrl=true; root.scripts.OnKeyDown(root,"2"); equal(root.propagate,true)
    s.p.ctrl=false; root.scripts.OnKeyDown(root,"SPACE"); equal(root.propagate,false)
    root.scripts.OnKeyDown(root,"ESCAPE"); equal(root.shown,false); equal(s.p.env.QuestFrame.alpha,.75)
    equal(s.p.action,"closeQuest")
    s=scene("COMPLETE"); s.source.rewards.choices={}
    for index=1,10 do s.source.rewards.choices[index]={index=index,itemID=500+index,name="Memória "..index,icon=1234} end
    s.c.Refresh(); s.root().scripts.OnKeyDown(s.root(),"9"); s.c.Action("FINISH")
    equal(s.calls[1].index,9)
end)

test("confirmação especial permanece nativa sem suspender outras missões e tipo usa API",function()
    local s=scene("OFFER"); s.pvp=true; s.c.Refresh()
    equal(s.p.env.QuestFrame.alpha,.75); equal(s.reports,0); equal(s.stage,"quest_native_required")
    s.pvp=false
    s.r.env.Enum={QuestClassification={Campaign=7}}
    s.r.env.C_QuestInfoSystem={GetQuestClassification=function(id) equal(id,101); return 7 end}
    s.c.Refresh(); equal(s.reports,0); equal(s.root().shown,true)
    assert(s.text("Campanha · Oferta")); s.c.Close()
end)

test("título ambíguo facção e dados secretos são omitidos sem confundir nível",function()
    local c=t.client(); c.start(); c.npc.name="Erma"
    for _,lines in ipairs({
        {{type=2,leftText="Erma"},{type=0,leftText="Ventobravo"}},
        {{type=2,leftText="Outro nome"},{type=0,leftText="Mestre de Estábulo"},{type=47,leftText="Nível 30"}},
        {{type=2,leftText="Erma"},{type=47,leftText="<Nível 30>"}},
        {{type=2,leftText="Erma"},{type=0,leftText=c.secret},{type=47,leftText="Nível 30"}}}) do
        c.unitTooltip={lines=lines}; c.fire("GOSSIP_SHOW")
        equal(c.namespace.GossipDialogs.GetCurrent().npc.title,nil)
    end
end)

test("falhas de desenho tooltip e frame protegido mantêm missão utilizável na Blizzard",function()
    for _,mode in ipairs({"draw","tooltip","protected"}) do
        local s=scene("OFFER")
        if mode=="draw" then s.r.env.CreateColor=function() error("quest_skin_original") end
        elseif mode=="protected" then s.p.env.QuestFrame.protected=true end
        s.c.Refresh()
        if mode=="tooltip" then
            s.r.env.GameTooltip.SetQuestItem=function() error("quest_tooltip_original") end
            local b=s.button("Pena de Myriel"); b.scripts.OnEnter(b)
        end
        equal(s.reports,1); equal(s.p.env.QuestFrame.alpha,.75)
        if s.root() then equal(s.root().shown,false); equal(s.root().keyboard,false); equal(s.root().scripts.OnUpdate,nil) end
        assert(s.fault.message); assert(s.fault.stack)
    end
end)

test("papel e botões permanecem utilizáveis nos três momentos em todas as proporções",function()
    for _,moment in ipairs({"OFFER","PROGRESS","COMPLETE"}) do
        for _,size in ipairs({{1920,1080},{3440,1440},{5120,1440}}) do
            for _,scale in ipairs({.64,.8,1,1.25}) do
                local s=scene(moment); s.r.parent:SetSize(size[1]/scale,size[2]/scale)
                s.c.Refresh(); equal(s.reports,0); s.root().scripts.OnUpdate(s.root(),1)
                local action=s.button(moment=="OFFER" and "Aceitar" or moment=="PROGRESS" and "Continuar" or "Concluir")
                assert(action.width>100); assert(action.height>20)
                local paper=action.parent.parent
                assert(paper.width<size[1]/scale*.4); assert(paper.height<size[2]/scale*.9)
                assert(s.text(s.source.quest.title).height>0)
                s.c.Close()
            end
        end
    end
end)

test("pré carregamento do papel prepara tamanhos sem abrir janela e moedas são nativas",function()
    local s=scene("OFFER",true)
    s.n.QuestView.Preload(1280,720); equal(s.root(),nil)
    assert(#s.r.fontCalls>=8); s.r.drain(); s.c.Refresh()
    equal(s.reports,0); assert(s.text("12 ouro")); assert(s.text("40 cobre")); assert(s.text("550 de experiência"))
    local gold,copper=false,false
    for _,region in ipairs(s.r.regions) do
        if region.texture=="Interface\\MoneyFrame\\UI-GoldIcon" then gold=true end
        if region.texture=="Interface\\MoneyFrame\\UI-CopperIcon" then copper=true end
    end
    assert(gold and copper); s.c.Close(); s.r.drain()
end)

test("reexibição nativa agenda atualização e viewport inválido devolve missão sem estado pendente",function()
    local s=scene("COMPLETE"); s.c.Refresh(); s.c.Choose(2)
    local root=s.root(); root.scripts.OnUpdate(root,.4)
    local update=root.scripts.OnUpdate
    local queued={}
    s.p.env.C_Timer.After=function(_,callback) queued[#queued+1]=callback end
    s.p.env.QuestFrame.scripts.OnShow()
    equal(#queued,1); equal(root.scripts.OnUpdate,update)
    queued[1](); equal(s.button("Concluir").enabled,true); equal(root.scripts.OnUpdate,update)
    s.r.parent:SetSize(0,0); s.c.Handle("QUEST_ITEM_UPDATE")
    equal(s.reports,1); equal(root.shown,false); equal(root.keyboard,false); equal(root.scripts.OnUpdate,nil)
    equal(s.p.env.QuestFrame.alpha,.75)
end)

test("estado restrito ou autoaceite alterado não executa ação antiga",function()
    local s=scene("OFFER"); s.c.Refresh(); s.autoAccept=true
    s.c.Action("DECLINE"); equal(#s.calls,0); equal(s.reports,1); equal(s.root().shown,false)
    s=scene("OFFER"); s.c.Refresh()
    local secret={}; s.r.env.issecretvalue=function(value) return value==secret end
    s.actualID=secret; s.c.Action("ACCEPT")
    equal(#s.calls,0); equal(s.reports,1); equal(s.root().shown,false)
    assert(s.fault.message:find("restricted_interface",1,true)); assert(s.fault.stack)
end)

return {scene=scene,source=source}
