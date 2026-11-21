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
    local s={n=n,p=p,r=r,source=source(moment),calls={},receipt=nil,reports=0,autoAccept=false,completable=false,preferences={}}
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
    t.loadModule("Integration/Dialogue.lua",n,env)
    t.loadModule("Integration/QuestPresentation.lua",n,env)
    s.c=n.ConversationController.New({GetModel=function() return s.source end,IsEnabled=function() return not s.disabled end,
        GetPreferences=function() return s.preferences end,
        Prepare=function(model)
            if not model.quest then return n.Conversation.Build(model) end
            return n.QuestPresentation.Build(model,n.QuestPlatform.ReadState(model),s.receipt)
        end,
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
        s.c.Refresh(); assert(s.reports==0,s.fault and s.fault.message); equal(s.root().shown,true); equal(s.p.env.QuestFrame.alpha,0)
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
        equal(s.root().shown,true); equal(s.p.env.QuestFrame.alpha,0); equal(s.reports,0)
        s.c.Close(); equal(s.root().shown,false)
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
    s.c.Refresh(); equal(s.p.env.QuestFrame.alpha,0)
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
    c.flush(); equal(count,1); equal(ui.visible,false)
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
    equal(#s.r.fontCalls,4); s.r.drain(); s.c.Refresh()
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

local function conversationScene(many)
    local n=core(); local r=t.surfaces.renderer(n)
    local model={moment="GOSSIP",npc={name="Estalajadeiro Fábio",title="Hospedagem",faction="Alliance"},
        location={zone="Floresta de Elwynn",subZone="Estalagem do Leão Orgulhoso"},
        text="Bem-vinda à minha estalagem, viajante cansada. O que posso fazer por você?",options={}}
    local texts={"O que posso fazer numa estalagem?","Vincule sua pedra de regresso a esta estalagem.",
        "Quero ver o que você tem à venda."}
    for index=1,many or 3 do
        model.options[index]={index=index,optionID=8000+index,text=texts[(index-1)%3+1]}
    end
    local s={n=n,r=r,source=model}
    s.view=n.ConversationView.New({Error=function(fault) error(fault.message) end})
    function s.open() assert(s.view.Show(assert(n.Conversation.Build(model)))); return r.frames[1] end
    return s
end

test("três opções do Fábio cabem inteiras e fala cede espaço em todas as escalas",function()
    for _,size in ipairs({{1920,1080},{2560,1440},{3440,1440},{5120,1440}}) do
        for _,scale in ipairs({.64,.8,1,1.25}) do
            local s=conversationScene(); s.r.parent:SetSize(size[1]/scale,size[2]/scale)
            local root=s.open(); s.view.Complete(); root.scripts.OnUpdate(root,1)
            local speechScroll,options=s.r.frames[2],s.r.frames[4]
            equal(options:GetVerticalScrollRange(),0)
            assert(options.height>=options.child.height)
            assert(options.points[1][5]>=0)
            assert(options.points[1][5]+options.height<speechScroll.points[1][5]-speechScroll.height)
            assert(s.r.regions[2].height<=size[2]/scale*.38+.01)
            s.view.Hide()
        end
    end
end)

test("muitas opções conservam viewport na barra e indicação própria até o fim da lista",function()
    for _,size in ipairs({{1920,1080},{3440,1440},{5120,1440}}) do
        local s=conversationScene(80); s.r.parent:SetSize(size[1],size[2]); s.source.text=string.rep(s.source.text,80)
        local root=s.open(); s.view.Complete(); root.scripts.OnUpdate(root,1)
        local speechScroll,options=s.r.frames[2],s.r.frames[4]
        local hint
        for _,region in ipairs(s.r.regions) do if region.text==s.n.Text.cinemaOptionsMore then hint=region end end
        assert(hint); assert(options:GetVerticalScrollRange()>0); assert(speechScroll:GetVerticalScrollRange()>0)
        assert(options.points[1][5]+options.height<s.r.regions[2].height)
        assert(hint.points[1][5]+hint.height<=options.points[1][5])
        options.scripts.OnMouseWheel(options,-10000)
        equal(options:GetVerticalScroll(),options:GetVerticalScrollRange())
        equal(hint.text,s.n.Text.cinemaOptionsPrevious); equal(speechScroll:GetVerticalScroll(),0)
        s.view.Hide()
    end
end)

test("objetivos conservam contagem embutida uma vez e campos separados quando necessária",function()
    local n=core()
    for _,text in ipairs({"0/8 Vela Grande","Vela Grande: 0/8","Vela Grande: 0 / 8","|cffffffff0/8|r Vela Grande"}) do
        local objective={text=text,fulfilled=0,required=8}; local before=t.serialize(objective)
        local caption,count=n.QuestPresentation.Objective(objective)
        equal(caption,text); equal(count,""); equal(t.serialize(objective),before)
    end
    local caption,count=n.QuestPresentation.Objective({text="Vela Grande",fulfilled=0,required=8})
    equal(caption,"Vela Grande"); equal(count,"0/8")
    caption,count=n.QuestPresentation.Objective({text="Acenda 8 velas",required=8})
    equal(caption,"Acenda 8 velas"); equal(count,"")
end)

test("renderer não duplica fração de objetivo nem reduz largura sem contagem lateral",function()
    local s=scene("PROGRESS")
    s.source.objectives={{index=1,text="0/8 Vela Grande",fulfilled=0,required=8}}
    s.c.Refresh(); equal(s.reports,0); assert(s.text("0/8 Vela Grande")); equal(s.text("0/8"),nil)
    local width=s.text("0/8 Vela Grande").width
    s.source.objectives[1].text="Vela Grande"; s.c.Handle("QUEST_LOG_UPDATE")
    assert(s.text("0/8")); assert(s.text("Vela Grande").width<width); s.c.Close()
end)

test("folha cresce com conteúdo e limita altura com rodapé fixo nos três momentos",function()
    local fields={OFFER="description",PROGRESS="progressText",COMPLETE="rewardText"}
    for _,moment in ipairs({"OFFER","PROGRESS","COMPLETE"}) do
        for _,size in ipairs({{1920,1080},{3440,1440},{5120,1440}}) do
            for _,scale in ipairs({.64,.8,1,1.25}) do
                local s=scene(moment); s.r.parent:SetSize(size[1]/scale,size[2]/scale)
                s.source.objectives={}; s.source.requiredItems={}; s.source.rewards={choices={},fixed={}}
                s.source.quest.objectiveText=nil; s.source.quest[fields[moment]]="Você chegou."
                s.c.Refresh(); equal(s.reports,0)
                local action=s.button(moment=="OFFER" and "Aceitar" or moment=="PROGRESS" and "Continuar" or "Concluir")
                local footer,paper=action.parent,action.parent.parent
                local unit=size[2]/scale/720; local shortHeight=paper.height
                assert(shortHeight>=360*unit and shortHeight<size[2]/scale*.82)
                equal(footer.points[1][2],paper); equal(footer.points[1][3],"BOTTOMLEFT")
                s.source.quest[fields[moment]]=string.rep("Uma história extensa de Elwynn para ler. ",180)
                s.c.Handle("QUEST_ITEM_UPDATE"); equal(s.reports,0)
                equal(paper.height,size[2]/scale*.82)
                assert(paper.height>shortHeight)
                local scrolling
                for _,frame in ipairs(s.r.frames) do if frame.parent==paper and frame.kind=="ScrollFrame" then scrolling=frame end end
                assert(scrolling:GetVerticalScrollRange()>0)
                equal(scrolling.height+140*unit,paper.height)
                equal(footer.height,87*unit); s.c.Close()
            end
        end
    end
end)

test("reflow da altura conserva prefixo da fala e tempo da abertura sem piscar",function()
    local s=scene("PROGRESS"); s.c.Refresh(); local root=s.root(); root.scripts.OnUpdate(root,.22)
    local action=s.button("Continuar"); local paper=action.parent.parent
    local before=paper.parent.height/paper.height; local alpha=root.alpha
    local first=s.text("Ainda sinto o"); assert(first)
    s.source.requiredItems[2]={index=2,name="Outra página",itemID=600,quantity=8}
    s.c.Handle("QUEST_ITEM_UPDATE"); equal(s.reports,0)
    assert(math.abs(paper.parent.height/paper.height-before)<.000001)
    equal(first.text,"Ainda sinto o"); equal(root.alpha,alpha); s.c.Close()
end)

test("dica oferece só ações disponíveis para conversa oferta progresso e recompensa",function()
    local n=core()
    for _,moment in ipairs({"OFFER","PROGRESS","COMPLETE"}) do
        local view=build(n,source(moment))
        for _,typing in ipairs({false,true}) do
            local hint=n.Conversation.Hint(view,typing)
            equal(hint:find("Espaço",1,true)~=nil,typing or moment=="OFFER")
            equal(hint:find("recompensa",1,true)~=nil,moment=="COMPLETE")
            assert(hint:find("Esc",1,true))
        end
    end
    local view=build(n,source("COMPLETE")); for _,entry in ipairs(view.entries) do entry.enabled=false end
    equal(n.Conversation.Hint(view,false),n.Text.cinemaHintExit)
    local talk=assert(n.Conversation.Build({moment="GOSSIP",text="Olá"}))
    equal(n.Conversation.Hint(talk,false),n.Text.cinemaHintExit)
    talk.entries={{enabled=true}}; assert(n.Conversation.Hint(talk,false):find("escolher opção",1,true))
end)

test("dica se atualiza ao completar fala por espaço ou pelo tempo",function()
    for _,manual in ipairs({false,true}) do
        local s=scene("OFFER"); s.c.Refresh()
        local hint=s.text(s.n.Conversation.Hint(build(s.n,s.source),true)); assert(hint)
        if manual then s.root().scripts.OnKeyDown(s.root(),"SPACE")
        else s.root().scripts.OnUpdate(s.root(),10) end
        equal(hint.text,s.n.Conversation.Hint(build(s.n,s.source),false)); s.c.Close()
    end
end)

test("cartão exigido expõe quantidade e posse com fonte segura e sem alterar fotografia",function()
    local s=scene("PROGRESS"); local before=t.serialize(s.source)
    s.source.requiredItems[1].quantity=8; before=t.serialize(s.source)
    s.r.env.C_Item={GetItemCount=function(id) equal(id,503); return 0 end}
    s.c.Refresh(); equal(s.reports,0); assert(s.text("Em posse: 0/8")); equal(t.serialize(s.source),before)
    s.r.env.C_Item.GetItemCount=function() return 9 end
    s.c.Handle("QUEST_LOG_UPDATE"); assert(s.text("Em posse: 9/8")); equal(t.serialize(s.source),before)
    local name=s.text("Tomo chamuscado"); local count=s.text("Em posse: 9/8")
    assert(name.parent.height>=name.height+count.height+16); s.c.Close()
end)

test("quantidade exigida não inventa posse quando ausente restrita ou API falha",function()
    for _,mode in ipairs({"missing","secret","error","fractional"}) do
        local s=scene("PROGRESS"); local secret={}
        s.r.env.issecretvalue=function(value) return value==secret end
        if mode~="missing" then
            s.r.env.C_Item={GetItemCount=function()
                if mode=="error" then error("contagem indisponível") end
                return mode=="secret" and secret or .5
            end}
        end
        s.c.Refresh(); equal(s.reports,0); assert(s.text("Exigidos: 3")); equal(s.text("Em posse: 0/3"),nil); s.c.Close()
    end
    local n=core()
    equal(n.QuestPresentation.ItemCount({quantity=1},true),"Exigidos: 1")
    equal(n.QuestPresentation.ItemCount({},true),"")
    equal(n.QuestPresentation.ItemCount({quantity=8,owned=0},false),"")
end)

local function titleLines(name,title)
    return {{type=2,leftText=name},{type=0,leftText=title},{type=47,leftText="Nível 30"},{type=0,leftText="Ventobravo"}}
end
local function titleProbe(c)
    for _,entry in ipairs(c.diagnostics().entries) do if entry.code=="npc_title_unavailable" then return entry end end
end
test("título simples tolera tipos ausentes e separadores antes do nível sem adivinhar linha dois",function()
    for _,name in ipairs({"Estalajadeiro Fábio","Ferreiro Argus"}) do
        local c=t.client(); c.start(); c.npc.name=name
        local title=name=="Ferreiro Argus" and "Treinamento de Ferraria" or "Hospedagem"
        c.unitTooltip={guid=c.npc.guid,lines={{type=1,leftText=""},{type=2,leftText=name},{leftText=title},
            {type=1,leftText=""},{type=47,leftText="Nível 30"}}}
        c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent().npc.title,title)
        equal(titleProbe(c),nil)
        c.fire("QUEST_DETAIL"); equal(c.namespace.QuestDialogs.GetCurrent().npc.title,title)
    end
end)

test("tooltip de token resolvido só é usado quando GUID é idêntico ao NPC",function()
    for _,mode in ipairs({"other","same","secret_token","secret_guid"}) do
        local matches=mode=="same"
        local c=t.client(); c.start(); c.npc.name="Ferreiro Argus"
        local old=c.env.UnitGUID; local calls=0
        c.env.UnitTokenFromGUID=function(guid) equal(guid,c.npc.guid); return mode=="secret_token" and c.secret or "mouseover" end
        c.env.UnitGUID=function(unit)
            if unit=="mouseover" then return mode=="secret_guid" and c.secret or matches and c.npc.guid or "Creature-0-1-0-0-999-000" end
            return old(unit)
        end
        c.env.C_TooltipInfo.GetUnit=function(unit)
            if unit=="npc" then return nil end
            equal(unit,"mouseover"); calls=calls+1; return {guid=c.npc.guid,lines=titleLines(c.npc.name,"Treinamento de Ferraria")}
        end
        c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent().npc.title,matches and "Treinamento de Ferraria" or nil)
        equal(calls,matches and 1 or 0)
        if matches then equal(titleProbe(c),nil)
        else equal(titleProbe(c).message,"data_unavailable"); assert(not titleProbe(c).message:find(c.npc.guid,1,true)) end
    end
end)

test("tooltip nativo já aberto fornece título por GUID sem ser alterado",function()
    for _,mode in ipairs({"other","same","secret"}) do
        local matches=mode=="same"
        local c=t.client(); c.start(); c.npc.name="Estalajadeiro Fábio"
        c.env.C_TooltipInfo.GetUnit=function() return nil end
        c.env.GameTooltip.GetPrimaryTooltipData=function() return {guid=mode=="secret" and c.secret or matches and c.npc.guid or "outra criatura",
            lines=titleLines(c.npc.name,"Hospedagem")} end
        local before=t.serialize(c.tooltip)
        c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent().npc.title,matches and "Hospedagem" or nil)
        equal(t.serialize(c.tooltip),before)
    end
end)

test("diagnóstico do título registra só falhas uma vez por NPC sem texto bruto nem diário",function()
    local c=t.client(); c.start(); c.npc.name="Ferreiro Argus"
    c.unitTooltip={lines={{type=2,leftText=c.npc.name},{type=0,leftText="não gravar esta linha"}}}
    c.fire("GOSSIP_SHOW"); local sequence=c.saved().nextSequence
    c.fire("GOSSIP_SHOW"); c.fire("GOSSIP_SHOW"); equal(c.saved().nextSequence,sequence)
    local count=0
    for _,entry in ipairs(c.diagnostics().entries) do if entry.code=="npc_title_unavailable" then count=count+1; equal(entry.count,1) end end
    equal(count,1)
    local probe=titleProbe(c)
    equal(probe.context.stage,"npc_title"); equal(probe.context.creatureID,777)
    equal(probe.message,"level_boundary_missing"); equal(probe.stack,nil)
    assert(not probe.message:find("não gravar",1,true))
    c.npc.guid="Creature-0-1-0-0-778-000"; c.fire("GOSSIP_SHOW")
    count=0; for _,entry in ipairs(c.diagnostics().entries) do if entry.code=="npc_title_unavailable" then count=count+1 end end
    equal(count,2)
end)

test("título rejeita tipo identidade facção e secretos inclusive em dados aninhados",function()
    for _,mode in ipairs({"guid","data","lines","line","text","type","faction","level","race","args","missing_name","missing_header"}) do
        local c=t.client(); c.start(); c.npc.name="Ferreiro Argus"
        local data={guid=c.npc.guid,lines=titleLines(c.npc.name,"Treinamento de Ferraria")}
        local secret=c.secret
        if mode=="guid" then data.guid=secret
        elseif mode=="data" then data=secret
        elseif mode=="lines" then data.lines=secret
        elseif mode=="line" then data.lines[2]=secret
        elseif mode=="text" then data.lines[2].leftText=secret
        elseif mode=="type" then data.lines[2].type=secret
        elseif mode=="faction" then data.lines[2].leftText="Alliance"
        elseif mode=="level" then data.lines[2]={type=47,leftText="<Nível 30>"}
        elseif mode=="race" then data.lines[2]={type=48,leftText="Humanoide"}
        elseif mode=="args" then data.lines[2]={type=0,args=secret}
        elseif mode=="missing_name" then c.npc.name=nil; data.lines[1].leftText=nil
        elseif mode=="missing_header" then data.lines[1].leftText=nil end
        c.unitTooltip=data; c.fire("GOSSIP_SHOW")
        equal(c.namespace.GossipDialogs.GetCurrent().npc.title,nil)
        local probe=titleProbe(c)
        if mode=="level" then equal(probe,nil)
        else assert(probe); assert(not probe.message:find("não gravar",1,true)); assert(#probe.message<40) end
    end
end)

test("falhas de título têm limite por sessão e texto extenso nunca entra no diagnóstico",function()
    local c=t.client(); c.start(); c.npc.name="Ferreiro Argus"
    c.unitTooltip={lines=titleLines(c.npc.name,string.rep("História ",900))}
    c.fire("GOSSIP_SHOW"); equal(titleProbe(c),nil)
    c.unitTooltip={lines={{type=2,leftText=c.npc.name}}}
    c.namespace.DialogueAPI.ReadNPC(c.namespace.DialogueAPI.Reader())
    equal(titleProbe(c).message,"level_boundary_missing")
    for index=1,140 do
        c.npc.guid="Creature-0-1-0-0-"..(2000+index).."-000"
        c.unitTooltip={lines={{type=2,leftText=c.npc.name},{type=0,leftText=string.rep("não gravar ",900)}}}
        c.namespace.DialogueAPI.ReadNPC(c.namespace.DialogueAPI.Reader())
    end
    local latest=c.diagnostics().entries[#c.diagnostics().entries]
    equal(latest.context.creatureID,2127); equal(#c.diagnostics().entries,50)
end)

test("evento oculta nativa antes do defer e troca conversa missão conversa sob fonte pendente",function()
    local s=scene("OFFER",true); s.p.env.C_Timer.After=s.r.after
    local quest=s.source
    local gossip={moment="GOSSIP",text="Bem-vinda à vila.",npc=quest.npc,location=quest.location,
        availableQuests={{index=1,questID=101,title=quest.quest.title}},options={}}
    s.source=gossip; s.c.Handle("GOSSIP_SHOW")
    equal(s.p.root.alpha,0); equal(s.p.env.QuestFrame.alpha,.75); equal(s.root().shown,true)
    s.r.advance(0); s.root().scripts.OnUpdate(s.root(),1)
    local top,bottom=s.r.regions[1],s.r.regions[2]; local topHeight=top.height
    s.r.fontBehavior=function(path,size)
        if path:find("Cinzel-Bold",1,true) and size==27 then return {delay=.45} end
    end
    local gossipStart=#s.p.root.alphaHistory+1
    s.c.Choose(1); equal(s.p.root.alpha,0); equal(s.p.action,"SelectAvailableQuest")
    s.source=nil; s.c.Handle("GOSSIP_CLOSED")
    s.source=quest; s.c.Handle("QUEST_DETAIL")
    equal(s.p.env.QuestFrame.alpha,0) -- before any rendering callback.
    local questStart=#s.p.env.QuestFrame.alphaHistory
    s.r.advance(0); equal(s.root().shown,true); equal(s.root().alpha,1)
    equal(top.height,topHeight); assert(bottom.height>0); equal(s.button("Aceitar").enabled,true)
    s.p.root.alpha=.75; s.p.root.scripts.OnShow()
    equal(s.p.root.alpha,0) -- synchronous suppression, child work remains deferred.
    for _=1,12 do s.r.advance(.1) end
    equal(s.reports,0); equal(s.p.env.QuestFrame.alpha,0); assert(s.button("Aceitar"))
    equal(top.height,topHeight)
    s.source=nil; s.c.Handle("QUEST_FINISHED")
    s.source=gossip; s.c.Handle("GOSSIP_SHOW"); s.r.advance(0); s.r.advance(.2)
    equal(s.root().shown,true); equal(s.p.root.alpha,0); equal(s.p.env.QuestFrame.alpha,0)
    for index=gossipStart,#s.p.root.alphaHistory do equal(s.p.root.alphaHistory[index],0) end
    for index=questStart,#s.p.env.QuestFrame.alphaHistory do equal(s.p.env.QuestFrame.alphaHistory[index],0) end
    s.r.advance(2); equal(s.reports,0) -- obsolete deadlines cannot release the new moment.
    s.c.Close(); equal(s.p.root.alpha,.75); equal(s.p.env.QuestFrame.alpha,.75)
    equal(s.p.root.mouse,true); equal(s.p.child.keyboard,true); s.r.drain()
end)

test("progresso conclusão mantém barras e escolha até fechar sem restauração intermediária",function()
    local s=scene("PROGRESS",true); s.p.env.C_Timer.After=s.r.after
    s.completable=true; s.c.Handle("QUEST_PROGRESS"); equal(s.p.env.QuestFrame.alpha,0)
    s.r.advance(0); s.root().scripts.OnUpdate(s.root(),1)
    local height=s.r.regions[1].height; local start=#s.p.env.QuestFrame.alphaHistory+1
    s.c.Action("CONTINUE"); equal(s.calls[1].key,"CompleteQuest")
    equal(s.c.Action("CONTINUE"),false); equal(s.root().shown,true)
    s.source=source("COMPLETE"); s.c.Handle("QUEST_COMPLETE"); equal(s.p.env.QuestFrame.alpha,0)
    s.r.advance(0); equal(s.r.regions[1].height,height)
    equal(s.button("Concluir").enabled,false); s.c.Key("2"); equal(s.button("Concluir").enabled,true)
    for index=start,#s.p.env.QuestFrame.alphaHistory do equal(s.p.env.QuestFrame.alphaHistory[index],0) end
    s.r.advance(3); equal(s.reports,0); equal(s.root().shown,true)
    s.source=nil; s.c.Handle("QUEST_FINISHED"); s.r.advance(.1)
    equal(s.root().shown,false); equal(s.p.env.QuestFrame.alpha,.75); s.r.drain()
end)

test("preparação tem prazo total de dois segundos e abre fallback sem restaurar Blizzard",function()
    local s=scene("OFFER",true); s.p.env.C_Timer.After=s.r.after
    s.r.fontBehavior=function(path)
        if path:find("NerdWow\\Fonts\\",1,true) then return {delay=8} end
    end
    s.c.Handle("QUEST_DETAIL"); s.r.advance(0)
    s.r.advance(.8); s.c.Handle("QUEST_ITEM_UPDATE"); s.r.advance(0)
    s.r.advance(.8); s.c.Handle("QUEST_DETAIL"); s.r.advance(0)
    equal(s.reports,0); equal(s.p.env.QuestFrame.alpha,0); equal(s.root().shown,true)
    s.r.advance(.41); equal(s.reports,0); equal(s.fault,nil)
    equal(s.p.env.QuestFrame.alpha,0); equal(s.root().shown,true); equal(s.root().keyboard,true)
    assert(s.button("Aceitar")); s.r.drain(); equal(s.root().shown,true); equal(s.reports,0)
    s.c.Close()
end)

test("espera de transição pode sair por Esc desligamento combate ou falha real",function()
    for _,mode in ipairs({"escape","off","combat","error"}) do
        local s=scene("OFFER",true); s.p.env.C_Timer.After=s.r.after
        s.r.fontBehavior=function(path) if path:find("NerdWow\\Fonts\\",1,true) then return {delay=.8} end end
        s.c.Handle("QUEST_DETAIL"); s.r.advance(0)
        local old=s.root().scripts.OnKeyDown
        if mode=="escape" then old(s.root(),"ESCAPE"); equal(s.p.action,"closeQuest")
        elseif mode=="off" then s.disabled=true; s.c.Toggle()
        elseif mode=="combat" then s.p.combat=true; s.c.Handle("PLAYER_REGEN_DISABLED")
        else s.c.Fail("preparação indisponível","test") end
        equal(s.root().shown,false); equal(s.root().keyboard,false); equal(s.p.env.QuestFrame.alpha,.75)
        s.r.drain(); equal(s.root().shown,false); equal(s.reports,mode=="error" and 1 or 0)
    end
end)

test("arquivo de fonte pronto não espera novamente por tamanho com SetFont false",function()
    local s=scene("OFFER",true); local r=s.r; s.p.env.C_Timer.After=r.after
    r.fontBehavior=function() return {delay=0,identityNow=true,factor=1} end
    s.n.FontAPI.Preload(); r.advance(.1)
    -- Each new profile still returns false, but identity and positive metrics
    -- are already available for the same loaded files at every requested size.
    s.c.Handle("QUEST_DETAIL"); r.advance(0)
    equal(s.reports,0); assert(s.button("Aceitar")); equal(s.p.env.QuestFrame.alpha,0)
    equal(s.root().shown,true); equal(r.now,.1)
    local path,ready=s.n.FontAPI.Apply(r.parent:CreateFontString(nil,"OVERLAY","GameFontNormal"),"Cinzel-Bold",63)
    equal(ready,true); assert(path:find("Cinzel-Bold",1,true))
    s.c.Close(); r.drain()
end)

test("arquivo pronto dispensa sonda por tamanho e verifica identidade da região com fallback",function()
    for _,mode in ipairs({"identity","metric"}) do
        local s=scene("OFFER",true); local r=s.r; s.p.env.C_Timer.After=r.after
        s.n.FontAPI.Preload(); r.advance(.1)
        r.fontBehavior=function(path,size)
            if not path:find("NerdWow\\Fonts\\",1,true) then return end
            if size==27 then return {delay=.5,identityNow=mode=="metric",factor=0} end
        end
        s.c.Handle("QUEST_DETAIL"); r.advance(0)
        equal(s.p.env.QuestFrame.alpha,0)
        -- No new-size probe can defer the entire presentation. Actual zero text
        -- metrics still receive the renderer's bounded layout retry.
        equal(s.n.FontAPI.Prepare("Cinzel-Bold",27),true)
        for _=1,17 do r.advance(.1) end
        equal(s.reports,0); assert(s.button("Aceitar")); s.c.Close(); r.drain()
    end
end)

test("tooltips reais da Erma Delegado e Remy usam nível localizado de tipo zero",function()
    for _,npc in ipairs({{6749,"Erma","Mestre de Estábulo"},{240,"Delegado Durão"},{241,'Remy "Duas Vezes"'}}) do
        local c=t.client(); c.start(); c.npc.name=npc[2]; c.npc.guid="Creature-0-1-0-0-"..npc[1].."-000"
        local lines={{type=2,leftText=npc[2]}}
        if npc[3] then lines[#lines+1]={type=0,leftText=npc[3]} end
        for _,text in ipairs({"Nível 30","Ventobravo","JxJ"}) do lines[#lines+1]={type=0,leftText=text} end
        c.unitTooltip={lines=lines}; c.fire("GOSSIP_SHOW")
        equal(c.namespace.GossipDialogs.GetCurrent().npc.title,npc[3]); equal(titleProbe(c),nil)
        c.fire("QUEST_DETAIL"); equal(c.namespace.QuestDialogs.GetCurrent().npc.title,npc[3]); equal(titleProbe(c),nil)
    end
end)

test("limite de nível segue formato localizado cores e placeholders posicionais do cliente",function()
    for _,sample in ipairs({{"Level %s","Level 30"},{"Stufe %d","Stufe 30"},{"Niveau %1$s","Niveau 30"},
        {"[%s] Stufe","[30] Stufe"},{"Nivel %s %s","Nivel 30 Humanoide"}}) do
        local c=t.client(); c.start(); c.npc.name="Erma"; c.env.TOOLTIP_UNIT_LEVEL=sample[1]
        c.unitTooltip={lines={{type=2,leftText="Erma"},{type=0,leftText="|cffffffff<Mestre de Estábulo>|r"},
            {type=0,leftText="|cffaaaaaa"..sample[2].."|r"},{type=0,leftText="Outra facção"},{type=0,leftText="PvP"}}}
        c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent().npc.title,"Mestre de Estábulo")
        equal(titleProbe(c),nil)
    end
end)

test("sem padrão localizado seguro nem nível não inventa título por linha dois",function()
    for _,template in ipairs({false,"%s","Incompatível %q","Level %s"}) do
        local c=t.client(); c.start(); c.npc.name="Erma"; c.env.TOOLTIP_UNIT_LEVEL=template
        c.unitTooltip={lines={{type=2,leftText="Erma"},{type=0,leftText="Mestre de Estábulo"},{type=0,leftText="Nível 30"}}}
        c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent().npc.title,nil); assert(titleProbe(c))
        c.unitTooltip.lines[3].type=47; c.fire("GOSSIP_SHOW")
        equal(c.namespace.GossipDialogs.GetCurrent().npc.title,"Mestre de Estábulo") -- typed clients still work.
    end
end)

test("título ignora linhas posteriores ao primeiro nível inclusive facção PvP e secretos",function()
    local c=t.client(); c.start(); c.npc.name="Erma"
    c.unitTooltip={lines={{type=2,leftText="Erma"},{type=0,leftText="Mestre de Estábulo"},
        {type=0,leftText="Nível 30"},{type=0,leftText=c.secret},c.secret}}
    c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent().npc.title,"Mestre de Estábulo")
    equal(titleProbe(c),nil)
    c.unitTooltip.lines[2]={type=0,leftText="Nível 30"}; c.unitTooltip.lines[3]={type=0,leftText="Hospedagem"}
    c.fire("GOSSIP_SHOW"); equal(c.namespace.GossipDialogs.GetCurrent().npc.title,nil); equal(titleProbe(c),nil)
end)

test("capitulares M W e acentuadas reservam largura medida sem sobrepor corpo em todas escalas",function()
    for _,letter in ipairs({"M","W","Á","É","Ç","Ü"}) do
        for _,size in ipairs({{1280,720},{3440/.8,1440/.8},{5120/1.25,1440/1.25}}) do
            local s=scene("OFFER"); s.r.parent:SetSize(size[1],size[2])
            s.r.glyphWidths={[letter]=1.35}
            s.source.quest.description=letter.."ísthica, você chegou para ouvir esta história."
            s.c.Refresh(); equal(s.reports,0)
            local cap,body
            for _,region in ipairs(s.r.regions) do
                if region.shown and region.alpha~=0 then
                    if region.text==letter then cap=region end
                    if region.text=="ísthica, você chegou para ouvir esta história." then body=region end
                end
            end
            assert(cap); equal(cap.wrap,false); equal(cap.nonSpaceWrap,false)
            assert(cap.width>=cap:GetUnboundedStringWidth()); assert(cap.height>=cap:GetStringHeight())
            assert(body)
            assert(body.points[1][4]>=cap.points[1][4]+cap.width+7*(size[2]/720)-.01)
            s.c.Close()
        end
    end
end)

test("capitular insegura deixa primeiro parágrafo integral sem perda nem reticência",function()
    for _,mode in ipairs({"wide","zero","error","combining","markup","symbol","malformed"}) do
        local s=scene("OFFER"); local text="Místhica, você chegou."
        if mode=="combining" then text="A\204\129urea memória."
        elseif mode=="markup" then text="|cffffffffMísthica|r, você chegou."
        elseif mode=="symbol" then text="“Místhica, você chegou.”"
        elseif mode=="malformed" then text="\196A memória."
        else s.r.glyphWidths={M=mode=="wide" and 9 or 0} end
        if mode=="error" then
            -- All descendants use the renderer's regions; wrap only the cap meter.
            local apply=s.n.FontAPI.Apply
            s.n.FontAPI.Apply=function(object,name,size)
                local a,b=apply(object,name,size)
                if name=="Cinzel-Bold" and size==48 then object.GetUnboundedStringWidth=function() error("cap metric unavailable") end end
                return a,b
            end
        end
        s.source.quest.description=text; s.c.Refresh(); equal(s.reports,0)
        local paragraph=s.text(text); assert(paragraph and paragraph.shown)
        equal(paragraph.points[1][4],0); equal(paragraph.wrap,true); equal(paragraph.nonSpaceWrap,true)
        s.c.Close()
    end
end)

test("Espaço completa fala primeiro e só depois aciona principal de cada momento",function()
    for _,sample in ipairs({{"OFFER",false,"AcceptQuest"},{"OFFER",true,"AcknowledgeAutoAcceptQuest"},
        {"PROGRESS",false,"CompleteQuest"},{"COMPLETE",false,"GetQuestReward"}}) do
        local s=scene(sample[1]); s.autoAccept=sample[2]; s.completable=true
        s.preferences.numberHotkeys=false; s.c.Refresh()
        if sample[1]=="COMPLETE" then s.c.Choose(2) end
        equal(s.c.Key("SPACE"),true); equal(#s.calls,0)
        local expected=build(s.n,s.source,{questID=101,autoAccept=s.autoAccept,canComplete=true,choiceCount=2})
        expected.numberHotkeys=false
        if sample[1]=="COMPLETE" then expected.selected=2 end
        assert(s.text(s.n.Conversation.Hint(expected,false)))
        equal(s.c.Key("SPACE"),true); equal(#s.calls,1); equal(s.calls[1].key,sample[3])
        if sample[1]=="COMPLETE" then equal(s.calls[1].index,2) end
        s.c.Key("SPACE"); equal(#s.calls,1); s.c.Close()
    end
end)

test("Espaço ignora principal desabilitado e dica acompanha recompensa e progresso",function()
    for _,moment in ipairs({"PROGRESS","COMPLETE"}) do
        local s=scene(moment); s.c.Refresh(); s.c.Key("SPACE")
        equal(s.c.Key("SPACE"),true); equal(#s.calls,0)
        local oldHint=s.n.Conversation.Hint(build(s.n,s.source),false)
        local hint=assert(s.text(oldHint)); assert(not hint.text:find("Espaço",1,true))
        if moment=="COMPLETE" then s.c.Key("2")
        else s.completable=true; s.c.Update() end
        assert(hint.text:find("Espaço",1,true)); equal(#s.calls,0)
        s.c.Key("SPACE"); equal(#s.calls,1); s.c.Close()
    end
end)

test("Espaço conclui missão sem escolha e revalida mudança do cliente antes da API",function()
    local s=scene("COMPLETE"); s.source.rewards.choices={}; s.c.Refresh(); s.c.Complete()
    equal(s.c.Key("SPACE"),true); equal(s.calls[1].key,"GetQuestReward"); s.c.Close()
    s=scene("PROGRESS"); s.completable=true; s.c.Refresh(); s.c.Complete(); s.completable=false
    s.c.Key("SPACE"); equal(#s.calls,0); equal(s.reports,1); equal(s.p.env.QuestFrame.alpha,.75)
end)
test("recuperação de fonte na missão conserva fala seleção e animação",function()
    local s=scene("COMPLETE",true); s.n.FontAPI.Preload(); s.r.advance(.2)
    s.source.quest.rewardText="A memória dos nomes que você trouxe será preservada nos tomos da biblioteca. Obrigada por retornar."
    local blocked=true
    s.r.rejectFont=function(path,size) return blocked and size==27 and path:find("Cinzel-Bold",1,true)~=nil end
    s.c.Refresh(); s.c.Choose(2)
    local root=s.root(); root.scripts.OnUpdate(root,.15)
    local before={}
    for _,region in ipairs(s.r.regions) do
        local parent,visible=region,true
        while parent do if not parent.shown or parent.alpha==0 then visible=false end; parent=parent.parent end
        if visible then before[region]=region.text end
    end
    local update,alpha=root.scripts.OnUpdate,root.alpha
    blocked=false; s.r.advance(1.1)
    equal(root.scripts.OnUpdate,update); equal(root.alpha,alpha); equal(s.button("Concluir").enabled,true)
    for region,text in pairs(before) do equal(region.text,text) end
    assert(s.text(s.source.quest.title).font:find("Cinzel-Bold.ttf",1,true))
    equal(s.p.env.QuestFrame.alpha,0); equal(s.reports,0); equal(#s.calls,0)
    s.c.Close(); s.r.drain()
end)
return {scene=scene,source=source,conversationScene=conversationScene}
