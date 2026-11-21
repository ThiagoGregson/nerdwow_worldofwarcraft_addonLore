local t=...
local test,equal=t.test,t.equal
local resolutions={{1920,1080},{2560,1440},{3440,1440},{5120,1440},{3840,2160}}
local scales={.64,.8,1,1.25}
local percentages={80,100,140}
local function near(actual,expected) assert(math.abs(actual-expected)<.00001,tostring(actual).." ~= "..tostring(expected)) end
local function viewport(r,size,scale)
    r.uiScale=scale; r.parent:SetSize(size[1]/scale,size[2]/scale)
end
local function inView(object,root)
    while object do
        if not object.shown or object.alpha==0 then return false end
        if object==root then return true end
        object=object.parent
    end
    return false
end
local function readable(r,root,scale)
    for _,region in ipairs(r.regions) do
        if (region.kind=="FontString" or region.kind=="EditBox") and inView(region,root) and region.text and region.text~="" then
            assert(region.size*scale>=13-.00001,"texto abaixo do piso: "..region.text)
            if region.kind=="FontString" then
                assert(region:GetHeight()+.01>=region:GetStringHeight(),"altura corta texto: "..region.text)
            end
        end
    end
end
local function finish(root)
    if root.scripts.OnUpdate then root.scripts.OnUpdate(root,2) end
end
local function lineLimit(r,n,size)
    local meter=r.parent:CreateFontString()
    meter:SetPoint("TOPLEFT",r.parent,"TOPLEFT",0,0); meter:SetSize(100000,100000); meter:Show()
    n.FontAPI.Apply(meter,"EBGaramond-Regular",size)
    meter:SetText(n.Conversation.LINE_SAMPLE)
    return meter:GetUnboundedStringWidth()
end

test("escala pura por altura física mantém piso e proporções em cinco resoluções",function()
    local n=t.core()
    for _,size in ipairs(resolutions) do for _,scale in ipairs(scales) do for _,percent in ipairs(percentages) do
        local p=assert(n.Typography.Build(size[2],scale,percent))
        local body=(3+size[2]/72)*percent/100
        near(p.body*scale,body); near(p.note*scale,math.max(13,body*.85))
        near(p.heading/p.body,1.05); near(p.title/p.body,1.4); near(p.speech/p.body,1.1)
        near(p.initial/p.body,2); near(p.unit*18,p.body)
        for _,role in ipairs({"note","body","speech","heading","title","initial"}) do assert(p[role]*scale>=13-.00001) end
    end end end
    near(n.Typography.Build(1080,1).body,18); near(n.Typography.Build(1440,1).body,23)
    near(n.Typography.Build(2160,1).body,33)
    local low=n.Typography.Build(720,1,80); equal(low.body,13); equal(low.note,13)
end)

test("tipografia rejeita parâmetros inválidos sem consultar APIs globais",function()
    local n=t.core()
    for _,value in ipairs({0,-1,math.huge,0/0,"1080",false}) do equal(n.Typography.Build(value,1),nil); equal(n.Typography.Build(1080,value),nil) end
    for _,value in ipairs({79,141,102,math.huge,0/0,"100",false}) do equal(n.Typography.Build(1080,1,value),nil) end
end)

test("adaptador segue PixelUtil e tamanho físico não depende da largura ou escalaUI",function()
    local n=t.core(); local r=t.surfaces.renderer(n)
    for _,size in ipairs(resolutions) do for _,scale in ipairs(scales) do
        viewport(r,size,scale)
        near(r.parent:GetEffectiveScale(),scale*768/size[2])
        local p=n.FontAPI.Scale(100)
        equal(p.physicalHeight,size[2]); near(p.pixelsPerUIUnit,scale)
        near(p.body*scale,3+size[2]/72)
    end end
    local secret={}; r.env.issecretvalue=function(value) return value==secret end
    r.env.GetPhysicalScreenSize=function() return 3440,secret end
    local ok,fault=n.DiagnosticAPI.Try(n.FontAPI.Scale,100)
    equal(ok,false); assert(fault.message:find("restricted_font_result",1,true))
end)

test("textSize migra por campo valida passos e restaura somente campos do livro",function()
    local n=t.core(); local saved={schemaVersion=1,minimapAngle=37,theme="horde",extension="guardar"}
    local settings,root,repaired=n.Settings.Open(saved); equal(root,saved); equal(#repaired,0); equal(root.textSize,100)
    for value=80,140,5 do assert(settings.Set("textSize",value)); equal(settings.Read("textSize"),value) end
    for _,value in ipairs({79,141,101,82.5,"100",false,0/0}) do equal(settings.Set("textSize",value),nil); equal(root.textSize,140) end
    local _,restored=n.Settings.Open(t.roundtrip(root)); equal(restored.textSize,140)
    local spec=n.ConfigurationCatalog.Option("general","textSize")
    equal(spec.kind,"slider"); equal(spec.soon,false); equal(spec.field,"textSize")
    settings.Reset(n.ConfigurationCatalog.Fields()); equal(root.textSize,100); equal(root.minimapAngle,37); equal(root.extension,"guardar")
    root.textSize=103; local _,_,issues=n.Settings.Open(root); equal(#issues,1); equal(issues[1],"textSize"); equal(root.textSize,100)
end)

test("slider do livro altera o próprio texto sem fechar e Restaurar padrões inclui tamanho",function()
    local s=t.configuration.scene(); local root=s.open(); local originalFrame=root
    local control=assert(s.control("textSize","Slider")); equal(control.minimum,80); equal(control.maximum,140); equal(control.step,5)
    for _,percent in ipairs(percentages) do
        control.scripts.OnMouseDown(control); control:SetValue(percent)
        equal(s.root.textSize,percent); equal(s.frame(),originalFrame); equal(s.n.ConfigurationUI.IsOpen(),true)
        equal(control.output.text,percent.."%"); equal(control.feedback.focus,true)
        near(s.region("Tamanho do texto").size,s.n.FontAPI.Scale(percent).body)
        control.scripts.OnMouseUp(control)
    end
    s.root.minimapAngle=19; s.select("Restaurar padrões"); s.select("Restaurar")
    equal(s.root.textSize,100); equal(s.root.minimapAngle,19); equal(s.frame(),root); equal(#s.records,0)
    s.n.ConfigurationUI.Close()
end)

test("livro acomoda papéis e controles nos extremos em cinco resoluções e escalas",function()
    for _,size in ipairs(resolutions) do for _,scale in ipairs(scales) do for _,percent in ipairs(percentages) do
        local s=t.configuration.scene(); viewport(s.r,size,scale); s.settings.Set("textSize",percent)
        local root=s.open()
        local line=lineLimit(s.r,s.n,s.n.FontAPI.Scale(percent).note)
        for _,chapter in ipairs({"Geral","Diálogo","Personagem","Diário","Sobre"}) do
            s.select(chapter); readable(s.r,root,scale)
            for _,region in ipairs(s.r.regions) do
                if region.text and region.text:find("Mostra o livro",1,true) and inView(region,root) then
                    assert(region.width<=line+.01,"descrição ultrapassa a medida de leitura")
                end
                if region.text=="VII" and inView(region,root) then
                    assert(region.width>=region:GetUnboundedStringWidth())
                    assert(-region.points[1][5]+region.height<=region.parent.height)
                end
            end
            local close=assert(s.button("Fechar")); local restore=assert(s.button("Restaurar padrões"))
            assert(restore.points[1][4]+restore.width<=close.points[1][4])
            assert(close.points[1][5]+close.height<=close.parent.height)
        end
        equal(#s.records,0); s.n.ConfigurationUI.Close()
    end end end
end)

test("conversa usa os mesmos papéis e opções permanecem dentro da barra em80 a140",function()
    for _,size in ipairs(resolutions) do for _,scale in ipairs(scales) do for _,percent in ipairs(percentages) do
        local s=t.parchment.conversationScene(16); viewport(s.r,size,scale)
        local model=assert(s.n.Conversation.Build(s.source)); s.n.Conversation.Configure(model,{textSize=percent})
        assert(s.view.Show(model)); s.view.Complete(); local root=s.r.frames[1]; finish(root)
        readable(s.r,root,scale)
        local options=s.r.frames[4]; assert(options.points[1][5]>=0)
        assert(options.points[1][5]+options.height<=s.r.parent.height*.38)
        local p=s.n.FontAPI.Scale(percent); local found=false
        for _,region in ipairs(s.r.regions) do
            if region.text==s.source.options[1].text and inView(region,root) then near(region.size,p.body); found=true end
            if region.text=="1" and inView(region,root) then near(region.size,p.note); near(region.width,p.note*1.6) end
        end
        assert(found); s.view.Hide()
    end end end
end)

test("pergaminho mede textos maiores e conserva rodapé nos três momentos em80 a140",function()
    for _,moment in ipairs({"OFFER","PROGRESS","COMPLETE"}) do
        for _,size in ipairs(resolutions) do for _,scale in ipairs(scales) do for _,percent in ipairs(percentages) do
            local s=t.parchment.scene(moment); viewport(s.r,size,scale); s.preferences={textSize=percent}
            s.source.quest.title="PROCURA-SE: Tiago Ciríaco e os guardiões da estrada de Elwynn"
            local field=moment=="OFFER" and "description" or moment=="PROGRESS" and "progressText" or "rewardText"
            s.source.quest[field]=string.rep("As memórias de Azeroth acompanham cada passo da jornada. ",70)
            s.c.Refresh(); s.c.Complete(); if moment=="COMPLETE" then s.c.Choose(2) end
            finish(s.root()); equal(s.reports,0); readable(s.r,s.root(),scale)
            local p=s.n.FontAPI.Scale(percent); near(s.text(s.source.quest.title).size,p.title)
            local line=lineLimit(s.r,s.n,p.body)
            for _,region in ipairs(s.r.regions) do
                if region.text and region.text:find("memórias de Azeroth",1,true) and inView(region,s.root()) then
                    assert(region.width<=line+.01,"parágrafo ultrapassa a medida de leitura")
                end
            end
            local button=assert(s.button(moment=="OFFER" and "Aceitar" or moment=="PROGRESS" and "Continuar" or "Concluir"))
            local footer,paper=button.parent,button.parent.parent
            near(paper.parent.height,paper.height); assert(button.points[1][5]+button.height<=footer.height)
            near(button.label.size,p.heading)
            local scroll
            for _,frame in ipairs(s.r.frames) do if frame.parent==paper and frame.kind=="ScrollFrame" then scroll=frame end end
            assert(scroll and scroll:GetVerticalScrollRange()>0)
            scroll.scripts.OnMouseWheel(scroll,-9999); equal(scroll.scroll,scroll:GetVerticalScrollRange())
            s.c.Close()
        end end end
    end
end)

test("alterar tamanho durante fala mantém prefixo animação rolagem e recompensa",function()
    local s=t.parchment.scene("COMPLETE"); viewport(s.r,{3440,1440},.8); s.preferences={textSize=100}
    s.source.quest.rewardText=string.rep("Você trouxe os nomes que a cidade havia perdido. ",70)
    s.c.Refresh(); s.c.Choose(2); local root=s.root(); root.scripts.OnUpdate(root,.2)
    local prefix={}
    for _,region in ipairs(s.r.regions) do if inView(region,root) and region.text then prefix[region]=region.text end end
    local button=s.button("Concluir"); local paper=button.parent.parent
    local ratio=paper.parent.height/paper.height; local update=root.scripts.OnUpdate
    for _,percent in ipairs({140,80,100}) do
        s.preferences.textSize=percent; s.c.Configure()
        equal(root.scripts.OnUpdate,update); near(paper.parent.height/paper.height,ratio)
        equal(button.enabled,true); near(button.label.size,s.n.FontAPI.Scale(percent).heading)
        -- Full paper text can rewrap; the typewriter's visible prefix cannot restart.
        for region,text in pairs(prefix) do
            if text~="" and s.source.quest.rewardText:sub(1,#text)==text and #text<30 then equal(region.text,text) end
        end
    end
    equal(s.reports,0); s.c.Close()
end)

test("composição observa textSize sem capturar evento e restauração propaga na hora",function()
    local c=t.client(); local cinema=t.surfaces.wire(c); local callbacks,shown,confirm
    c.namespace.ConfigurationView.New=function(value)
        callbacks=value
        return {IsOpen=function() return shown end,Open=function() shown=true end,Hide=function() shown=false end,
            Render=function() return true end,Confirm=function(callback) confirm=callback end}
    end
    c.start(); c.fire("GOSSIP_SHOW"); c.flush(); local before=t.serialize(c.saved())
    c.command("config"); callbacks.Write("textSize",140)
    equal(cinema.view.textSize,140); equal(shown,true); equal(c.settings().textSize,140)
    callbacks.Reset(); equal(c.settings().textSize,140); confirm()
    equal(c.settings().textSize,100); equal(cinema.view.textSize,100); equal(shown,true)
    equal(t.serialize(c.saved()),before)
end)

test("brasão ícone de item e interruptor acompanham texto sem escalar a janela",function()
    local s=t.parchment.conversationScene(); viewport(s.r,{3440,1440},.8)
    local model=assert(s.n.Conversation.Build(s.source)); s.n.Conversation.Configure(model,{textSize=80})
    assert(s.view.Show(model)); s.view.Complete(); finish(s.r.frames[1])
    local crest
    for _,region in ipairs(s.r.regions) do if region.mask then crest=region end end
    assert(crest); local before=crest.width; local windowWidth=s.r.frames[1]:GetWidth()
    s.view.Configure({textSize=140}); near(crest.width/before,140/80); equal(s.r.frames[1]:GetWidth(),windowWidth); s.view.Hide()
    s=t.parchment.scene("COMPLETE"); viewport(s.r,{3440,1440},.8); s.preferences={textSize=80}
    s.c.Refresh(); local icon
    for _,frame in ipairs(s.r.frames) do if frame.item and frame.icon then icon=frame.icon end end
    assert(icon); before=icon.width; s.preferences.textSize=140; s.c.Configure(); near(icon.width/before,140/80); s.c.Close()
    s=t.configuration.scene(); viewport(s.r,{3440,1440},.8); s.settings.Set("textSize",80); s.open()
    local toggle=assert(s.control("minimap","Button")); before=toggle.wax.width
    s.settings.Set("textSize",140); near(toggle.wax.width/before,140/80); equal(toggle.enabled,true); s.n.ConfigurationUI.Close()
end)
