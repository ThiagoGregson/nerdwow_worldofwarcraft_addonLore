local t=...
local test,equal=t.test,t.equal
local function visible(object)
    while object do if not object.shown or object.alpha==0 then return false end; object=object.parent end
    return true
end
local function scene(asynchronous)
    local n=t.core(); local r=t.surfaces.renderer(n,asynchronous)
    local s={n=n,r=r,messages={},records={},sync=0,version="test-toc",map=84,faction="Alliance",nativeCategories=0}
    local settings,root=n.Settings.Open(nil); s.settings,s.root=settings,root
    n.Wow={Version=function() return s.version end,Print=function(message) s.messages[#s.messages+1]=message end,
        FormatTime=function(timestamp) return "2026-11-20 18:25:43 UTC" end,RequestSync=function() s.sync=s.sync+1 end}
    r.env.InCombatLockdown=function() return s.combat==true end
    r.env.GetCurrentKeyBoardFocus=function() return r.focus end
    r.env.C_Map={GetBestMapForUnit=function() return s.map end}
    r.env.UnitFactionGroup=function() return s.faction end
    r.env.C_AddOns={}
    r.env.Settings={RegisterCanvasLayoutCategory=function(canvas,name)
        equal(name,"NerdWow"); s.canvas=canvas; return {id="native-nerdwow"}
    end,RegisterAddOnCategory=function(category) equal(category.id,"native-nerdwow"); s.nativeCategories=s.nativeCategories+1 end}
    r.env.C_Texture={GetAtlasInfo=function() return {} end}
    t.loadModule("Integration/Dialogue.lua",n,r.env)
    t.loadModule("Integration/ConfigurationView.lua",n,r.env)
    t.loadModule("Integration/Configuration.lua",n,r.env)
    n.ConversationPlatform={Defer=function(callback,delay) if asynchronous then r.after(delay or 0,callback) end; return true end}
    n.DiagnosticAPI.Bind(function(entry) s.records[#s.records+1]=entry end)
    s.info={['journal.total']=1284,['journal.pending']=37,['journal.last']="18:25:43 UTC",['journal.limit']="5000"}
    s.diagnostics={}
    n.ConfigurationUI.Initialize({Settings=settings,ReadInfo=function(key) return s.info[key] end,
        Diagnostics=function() return s.diagnostics end})
    settings.Subscribe(function() n.ConfigurationUI.Refresh() end)
    function s.region(text)
        for _,region in ipairs(r.regions) do if region.text==text and visible(region) then return region end end
    end
    function s.button(text)
        for _,region in ipairs(r.regions) do if region.text==text and region.parent.kind=="Button" and visible(region) then return region.parent end end
    end
    function s.frame()
        for index=#r.frames,1,-1 do if r.frames[index].strata=="DIALOG" then return r.frames[index] end end
    end
    function s.open()
        local opened=n.ConfigurationUI.Open()
        assert(opened,t.serialize(s.records).." / "..table.concat(s.messages,"; ")); equal(s.nativeCategories,1)
        if asynchronous then r.advance(.2) end
        local root=s.frame(); if root.scripts.OnUpdate then root.scripts.OnUpdate(root,1) end
        return root
    end
    function s.select(title)
        local button=assert(s.button(title)); button.scripts.OnClick(button)
    end
    function s.control(id,kind)
        for _,frame in ipairs(r.frames) do if frame.kind==kind and frame.parent.spec and frame.parent.spec.id==id and visible(frame) then return frame end end
    end
    return s
end

test("esquema declarativo migra valores 0.7.2 sem avisar campos ausentes nem perder extras",function()
    local n=t.core(); local legacy={schemaVersion=1,minimapHidden=true,minimapAngle=358.5,dialogEnabled=false,extension={keep="sim"}}
    local h,root,repaired=n.Settings.Open(legacy)
    equal(root,legacy); equal(#repaired,0); equal(h.Read("theme"),"auto"); equal(h.Read("speechSpeed"),60); equal(h.Read("numberHotkeys"),true)
    equal(root.minimapHidden,true); equal(root.minimapAngle,358.5); equal(root.dialogEnabled,false); equal(root.extension.keep,"sim")
    local _,resumed,issues=n.Settings.Open(t.roundtrip(root)); equal(t.serialize(resumed),t.serialize(root)); equal(#issues,0)
end)
test("descritores validam todos os limites escolhas e booleanos sem mutação inválida",function()
    local n=t.core(); local h,root=n.Settings.Open(nil)
    for _,pair in ipairs({{"speechSpeed",19},{"speechSpeed",121},{"speechSpeed",60.5},{"speechSpeed",0/0},
        {"speechSpeed",math.huge},{"speechSpeed","60"},{"theme","automatic"},{"theme",false},{"numberHotkeys",1},{"dialogEnabled","false"}}) do
        local before=t.serialize(root); local ok,code=h.Set(pair[1],pair[2]); equal(ok,nil); equal(code,"invalid_setting"); equal(t.serialize(root),before)
    end
    for _,speed in ipairs({20,60,120}) do assert(h.Set("speechSpeed",speed)); equal(h.Read("speechSpeed"),speed) end
    for _,key in ipairs({"auto","quelthalas","alliance","horde","neutral"}) do assert(h.Set("theme",key)) end
    local before=t.serialize(root); equal(h.Set("unknown",true),nil); equal(h.Toggle("speechSpeed"),nil); equal(t.serialize(root),before)
end)
test("recuperação genérica altera somente campo inválido com padrão descrito uma vez",function()
    local n=t.core()
    for _,key in ipairs({"theme","speechSpeed","numberHotkeys"}) do
        local _,root=n.Settings.Open(nil); root.minimapAngle=17; root.dialogEnabled=false; root[key]={}
        local h,_,issues=n.Settings.Open(root); equal(#issues,1); equal(issues[1],key)
        equal(h.Read(key),n.Settings.Describe(key).default); equal(root.minimapAngle,17); equal(root.dialogEnabled,false)
    end
    local spec=n.Settings.Describe("theme"); spec.values[1].value="corromper"; equal(n.Settings.Describe("theme").values[1].value,"auto")
end)
test("novos campos recebem validação texto e restauração pela mesma via sem código de janela",function()
    local n=t.core(); local s=n.Settings
    assert(s.Register("note",{type="string",default="",maxLength=12,validate=function(value) return not value:find("|",1,true) end}))
    equal(s.Register("note",{type="string",default=""}),nil)
    equal(s.Register("bad",{type="number",default=60,min=20,max=40}),nil)
    local h,root=s.Open(nil); assert(h.Set("note","Memória")); equal(h.Set("note",string.rep("x",13)),nil); equal(h.Set("note","|texto"),nil)
    local changed=0; local unsubscribe=h.Subscribe(function(keys) changed=changed+1; equal(keys[1],"note"); equal(h.Read("note"),"") end)
    assert(h.Reset({"note"})); equal(changed,1); unsubscribe(); h.Set("note","Fim"); equal(changed,1)
    local before=t.serialize(root); equal(h.Reset({"note","unknown"}),nil); equal(t.serialize(root),before)
end)
test("registro ordena capítulos opções e entrega cópias com vínculos válidos",function()
    local n=t.core(); local r=n.ConfigurationRegistry.New(n.Settings)
    assert(r.RegisterChapter({id="b",order=2,title="B",description="Segundo"}))
    assert(r.RegisterChapter({id="a",order=1,title="A",description="Primeiro"}))
    assert(r.RegisterOption("a",{id="second",order=2,kind="switch",field="dialogEnabled",title="Cinema"}))
    assert(r.RegisterOption("a",{id="first",order=1,kind="slider",field="speechSpeed",title="Velocidade"}))
    equal(r.Chapters()[1].id,"a"); equal(r.Options("a")[1].id,"first")
    local copy=r.Options("a"); copy[1].field="unknown"; equal(r.Options("a")[1].field,"speechSpeed")
    equal(r.RegisterChapter({id="a",order=1,title="A",description=""}),nil)
    equal(r.RegisterOption("a",{id="bad",order=3,kind="slider",field="dialogEnabled",title="Tipo"}),nil)
    equal(r.RegisterOption("unknown",{id="bad"}),nil)
    equal(r.RegisterOption("a",{id="missing",order=3,kind="switch",field="unknown",title="Ausente"}),nil)
    equal(r.RegisterOption("a",{id="missing",order=3,kind="action",title="Ação"}),nil)
end)
test("catálogo contém sete capítulos e placeholders inativos sem campos de etapas futuras",function()
    local n=t.core(); local r=n.ConfigurationCatalog; local chapters=r.Chapters()
    equal(#chapters,7); equal(chapters[1].id,"general"); equal(chapters[7].id,"about")
    for _,id in ipairs({"camera","character"}) do for _,spec in ipairs(r.Options(id)) do equal(spec.soon,true); equal(spec.field,nil) end end
    equal(n.Settings.Describe("windowScale"),nil); equal(n.Settings.Describe("rpName"),nil)
    local fields=r.Fields(); equal(#fields,6)
    for _,field in ipairs(fields) do assert(field~="minimapAngle" and field~="schemaVersion") end
end)
test("livro revalida ações em combate e nunca escreve ou executa opção em breve",function()
    local n=t.core(); local h,root=n.Settings.Open(nil); local combat,calls=false,0
    local b=n.ConfigurationBook.New({Registry=n.ConfigurationCatalog,Settings=h,CanAct=function() return not combat end,
        ReadInfo=function() return 1 end,IsVisible=function() return false end,Action=function() calls=calls+1; return true end,ConfirmReset=function() end})
    b.Select("camera"); equal(b.Write("camera",false),nil); equal(root.camera,nil)
    b.Select("journal"); equal(b.Snapshot().options[4].enabled,true); combat=true
    equal(b.Activate("sync"),nil); equal(calls,0); equal(b.Snapshot().options[4].enabled,false)
    combat=false; assert(b.Activate("sync")); equal(calls,1)
end)
test("restaurar exige confirmação e afeta só campos editáveis do livro preservando posição extras e diário",function()
    local n=t.core(); local h,root=n.Settings.Open(nil); root.minimapAngle=17; root.extension="guardar"
    h.Set("theme","horde"); h.Set("speechSpeed",20); h.Set("numberHotkeys",false); h.Set("minimapHidden",true)
    local confirm; local batches=0
    local b=n.ConfigurationBook.New({Registry=n.ConfigurationCatalog,Settings=h,ConfirmReset=function(callback) confirm=callback end})
    h.Subscribe(function(keys) batches=batches+1; equal(#keys,4) end)
    local before=t.serialize(root); b.RequestReset(); equal(t.serialize(root),before); assert(confirm)
    confirm(); equal(batches,1); equal(root.minimapAngle,17); equal(root.extension,"guardar")
    equal(root.theme,"auto"); equal(root.speechSpeed,60); equal(root.numberHotkeys,true); equal(root.minimapHidden,false)
end)
test("temas fixos prevalecem e automático mantém zona facção e neutro por contexto",function()
    local themes=t.core().DialogueThemes
    for _,fixed in ipairs({"alliance","horde","quelthalas","neutral"}) do equal(themes.Resolve({mapID=2395},{faction="Horde"},fixed).key,fixed) end
    equal(themes.Resolve({mapID=2395},{faction="Alliance"},"auto").key,"quelthalas")
    equal(themes.Resolve({mapID=84},{faction="Alliance"},"auto").key,"alliance")
    equal(themes.Resolve(nil,{faction="Horde"},"auto").key,"horde"); equal(themes.Resolve(nil,nil,"auto").key,"neutral")
end)
test("velocidade declarada altera fala e mudança durante reprodução preserva prefixo e fração",function()
    local n=t.core(); local text=string.rep("Memorias de Azeroth. ",100)
    local speech=n.Conversation.NewSpeech(text,20); local a=speech.Advance(.525); equal(#a,10)
    assert(speech.SetSpeed(120)); equal(speech.GetText(),a)
    local b=speech.Advance(.05); equal(#b,16); equal(b:sub(1,#a),a)
    equal(speech.SetSpeed(0),nil); equal(speech.SetSpeed(math.huge),nil)
    local fast=n.Conversation.NewSpeech(text,120); local slow=n.Conversation.NewSpeech(text,20)
    assert(#fast.Advance(.1)>#slow.Advance(.1)); equal(n.Conversation.NewSpeech(text,0),nil)
end)
test("atalhos numéricos desligados preservam espaço Esc clique e dicas de ação",function()
    local n=t.core(); local r=t.surfaces.renderer(n); local p=t.surfaces.platform(n)
    local m={moment="GOSSIP",text="Uma memória antiga de Azeroth que ainda precisa ser contada.",options={{index=1,optionID=7,text="Conte mais."}}}
    local c=n.ConversationController.New({GetModel=function() return m end,GetPreferences=function() return {numberHotkeys=false,speechSpeed=20,theme="horde"} end,
        IsEnabled=function() return true end,View=n.ConversationView,Platform=p.api,Report=function() error("falha") end})
    c.Refresh(); equal(c.Key("1"),false); equal(p.action,nil); equal(c.Key("SPACE"),true)
    c.Choose(1); equal(p.action,"SelectOption"); c.Refresh(); equal(c.Key("ESCAPE"),true); equal(p.action,"CloseGossip")
    local view=assert(n.Conversation.Build(m)); view.numberHotkeys=false
    assert(not n.Conversation.Hint(view,false):find("1–9",1,true))
end)
test("renderer abre livro fiel com dois papéis índice romanos rodapé e sete capítulos navegáveis",function()
    local s=scene(); local root=s.open(); equal(root.keyboard,true)
    assert(s.region("NerdWow")); assert(s.region("Configurações")); assert(s.region("Capítulo I")); assert(s.region("Configurações salvas automaticamente."))
    for _,id in ipairs({"Diálogo","Câmera e interface","Personagem","Diário","Avançado","Sobre","Geral"}) do s.select(id); assert(s.n.ConfigurationUI.IsOpen()) end
    root.scripts.OnKeyDown(root,"DOWN"); assert(s.region("Capítulo II")); equal(root.propagate,false)
    root.scripts.OnKeyDown(root,"UP"); assert(s.region("Capítulo I"))
    root.scripts.OnKeyDown(root,"ESCAPE"); equal(s.n.ConfigurationUI.IsOpen(),false); equal(root.keyboard,false)
end)
test("controles do livro alteram os campos genéricos e seleção de tema atualiza imediatamente",function()
    local s=scene(); s.open()
    local toggle=s.control("minimap","Button"); toggle.scripts.OnClick(toggle); equal(s.root.minimapHidden,true)
    s.select("Diálogo"); local speed=s.control("speed","Slider"); speed.scripts.OnValueChanged(speed,95)
    equal(s.root.speechSpeed,95); equal(speed.output.text,"95"); equal(speed.mouse,true)
    local keys=s.control("numbers","Button"); keys.scripts.OnClick(keys); equal(s.root.numberHotkeys,false)
    s.select("Geral"); local select=s.control("theme","Button"); select.scripts.OnClick(select)
    local horde=s.button("Horda"); horde.scripts.OnClick(horde); equal(s.root.theme,"horde")
    equal(#s.records,0)
end)
test("restauração visual confirma ou cancela sem tocar ângulo e controles futuros ficam inativos",function()
    local s=scene(); s.root.minimapAngle=76; s.settings.Set("speechSpeed",100); s.open()
    s.select("Restaurar padrões"); assert(s.region("Restaurar padrões?")); s.select("Cancelar"); equal(s.root.speechSpeed,100)
    s.select("Restaurar padrões"); s.select("Restaurar"); equal(s.root.speechSpeed,60); equal(s.root.minimapAngle,76)
    s.select("Câmera e interface"); local camera=s.control("camera","Button"); equal(camera.enabled,false); camera.scripts.OnClick(camera); equal(s.root.camera,nil)
    s.select("Personagem"); equal(s.control("name","EditBox").enabled,false)
end)
test("indicadores são reais e atualizam sem reabrir ou reiniciar animação e sincronizar revalida combate",function()
    local s=scene(); s.open(); s.select("Diário"); assert(s.region("1284")); assert(s.region("37")); assert(s.region("18:25:43 UTC")); assert(s.region("5000"))
    local update=s.frame().scripts.OnUpdate; s.info['journal.total']=1285; s.info['journal.pending']=38; s.n.ConfigurationUI.RefreshInfo()
    assert(s.region("1285")); assert(s.region("38")); equal(s.frame().scripts.OnUpdate,update)
    local sync=s.button("Sincronizar"); s.combat=true; sync.scripts.OnClick(sync); equal(s.sync,0)
    s.n.ConfigurationUI.RefreshInfo(); equal(sync.enabled,false); s.combat=false; s.n.ConfigurationUI.RefreshInfo()
    equal(sync.enabled,true); sync.scripts.OnClick(sync); equal(s.sync,1); equal(s.n.ConfigurationUI.IsOpen(),false)
end)
test("Sobre usa versão do TOC e GitHub selecionável para copiar sem abrir links",function()
    local s=scene(); s.open(); s.select("Sobre"); assert(s.region(s.version)); assert(s.region("gregson.com.br"))
    local edit=s.control("github","EditBox"); equal(edit.enabled,true); assert(edit.text:find("https://github.com/ThiagoGregson/",1,true))
    edit:SetFocus(); equal(edit.highlighted,true); edit:SetText("não alterar"); edit.scripts.OnTextChanged(edit,true)
    assert(edit.text:find("https://github.com/",1,true)); equal(s.root.github,nil)
    edit.scripts.OnEscapePressed(edit); equal(s.n.ConfigurationUI.IsOpen(),false)
end)
test("Avançado exibe registros seguros no livro e teste de fontes conserva as duas fases",function()
    local s=scene(true); s.diagnostics={{lastTimestamp=1,code="interface_error",count=2,version="0.7.2",message="causa original",context={stage="show"}}}
    s.open(); s.select("Avançado"); s.select("Ver registros")
    local found=false; for _,region in ipairs(s.r.regions) do if region.text and visible(region) and region.text:find("causa original",1,true) then found=true end end; assert(found)
    s.select("Testar"); s.r.drain()
    local loaded=false; for _,region in ipairs(s.r.regions) do if region.text and visible(region) and region.text:find("após verificação",1,true) then loaded=true end end; assert(loaded)
    equal(s.n.ConfigurationUI.IsOpen(),true); s.n.ConfigurationUI.Close()
end)
test("livro funciona em três proporções quatro escalas com texto extenso e rodapé fixo",function()
    for _,size in ipairs({{1920,1080},{3440,1440},{5120,1440}}) do for _,scale in ipairs({.64,.8,1,1.25}) do
        local s=scene(); s.r.parent:SetSize(size[1]/scale,size[2]/scale)
        s.diagnostics={{lastTimestamp=1,code="interface_error",count=1,version="0.7.2",message=string.rep("Uma mensagem extensa para ler com calma. ",100),context={}}}
        s.open(); s.select("Avançado"); local close=assert(s.button("Fechar")); local pos=close.points[1][4]
        s.select("Ver registros"); local scroll
        for _,frame in ipairs(s.r.frames) do if frame.kind=="ScrollFrame" and frame:GetVerticalScrollRange()>0 then scroll=frame end end
        assert(scroll); scroll.scripts.OnMouseWheel(scroll,-50); assert(scroll:GetVerticalScroll()>0)
        equal(close.points[1][4],pos); equal(#s.records,0)
        local l=assert(s.n.ConfigurationBook.Layout(size[1]/scale,size[2]/scale)); assert(l.width<size[1]/scale and l.height<size[2]/scale)
        s.n.ConfigurationUI.Close()
    end end
end)
test("espera por fonte do livro preserva observador e prazo abre fallback recuperável",function()
    local s=scene(true); local cinemaChanges=0
    s.n.FontAPI.Watch(function() cinemaChanges=cinemaChanges+1 end)
    s.r.fontBehavior=function(path) if path:find("NerdWow\\Fonts\\",1,true) and not s.r.loaded[path] then return {delay=.4} end end
    s.n.ConfigurationUI.Open(); equal(s.n.ConfigurationUI.IsOpen(),true); s.r.drain(); assert(cinemaChanges>0)
    if s.frame().scripts.OnUpdate then s.frame().scripts.OnUpdate(s.frame(),1) end
    assert(s.region("Geral")); equal(#s.records,0)
    s.n.ConfigurationUI.Close()
    s=scene(true); s.r.fontBehavior=function(path)
        if path:find("NerdWow\\Fonts\\",1,true) and not s.r.loaded[path] then return {delay=8} end
    end
    s.n.ConfigurationUI.Open(); s.r.advance(2.1); equal(s.n.ConfigurationUI.IsOpen(),true)
    if s.frame().scripts.OnUpdate then s.frame().scripts.OnUpdate(s.frame(),1) end
    assert(s.region("Geral")); assert(not s.region(s.n.Text.configLoading)); equal(s.frame().keyboard,true)
    for _,record in ipairs(s.records) do equal(record.code,"font_fallback") end
    s.r.drain(); equal(s.n.ConfigurationUI.IsOpen(),true)
    assert(s.region("Geral").font:find("NerdWow\\Fonts\\",1,true)); equal(#s.r.timers,0)
end)
test("entrada nativa usa API Settings e abre o mesmo livro sem duplicar categoria",function()
    local s=scene(); equal(s.nativeCategories,1); s.n.ConfigurationUI.Register(); equal(s.nativeCategories,1)
    s.canvas.scripts.OnShow(s.canvas); equal(s.n.ConfigurationUI.IsOpen(),true)
    s.n.ConfigurationUI.Close(); local openButton
    for _,f in ipairs(s.r.frames) do if f.parent==s.canvas and f.kind=="Button" then openButton=f end end
    openButton.scripts.OnClick(openButton); equal(s.n.ConfigurationUI.IsOpen(),true)
end)
test("comando e botão direito abrem Configurações e esquerdo conserva Sincronizar",function()
    local c=t.client(); local opens=0; c.namespace.ConfigurationUI.Open=function() opens=opens+1 end
    c.command("config"); equal(opens,1); c.start(); local before=t.serialize(c.saved())
    c.command(" CONFIG "); c.buttonEvent("OnMouseUp","RightButton",true); equal(opens,3); equal(c.popupRequests,0)
    c.buttonEvent("OnMouseDown","LeftButton"); c.buttonEvent("OnMouseUp","LeftButton",true); equal(c.popupRequests,1)
    equal(t.serialize(c.saved()),before); c.command("ajuda"); assert(c.messages[#c.messages]:find("/nerdwow config",1,true))
    c.buttonEvent("OnEnter"); assert(table.concat(c.tooltipLines,"\n"):find("Botão direito",1,true))
end)

test("preferências atualizam pergaminho aberto sem reiniciar fala animação ou recompensa",function()
    local s=t.parchment.scene("COMPLETE"); s.preferences={theme="horde",speechSpeed=20,numberHotkeys=false}
    s.c.Refresh(); local root=s.root(); root.scripts.OnUpdate(root,.3)
    equal(s.c.Key("2"),false); equal(s.button("Concluir").enabled,false)
    s.c.Choose(2); equal(s.button("Concluir").enabled,true)
    local update,alpha=root.scripts.OnUpdate,root.alpha
    local prefix
    for _,region in ipairs(s.r.regions) do
        if visible(region) and region.text and #region.text>1 and s.source.quest.rewardText:sub(1,#region.text)==region.text then prefix=region.text end
    end
    assert(prefix)
    local fill=s.button("Concluir").fill.fill; assert(math.abs(fill[1]-122/255)<.001)
    s.preferences={theme="alliance",speechSpeed=120,numberHotkeys=true}; s.c.Configure()
    equal(root.scripts.OnUpdate,update); equal(root.alpha,alpha); equal(s.button("Concluir").enabled,true)
    local same=false; for _,region in ipairs(s.r.regions) do if region.text==prefix then same=true end end; assert(same)
    equal(s.c.Key("1"),true); equal(s.button("Concluir").enabled,true)
    root.scripts.OnUpdate(root,.2); equal(s.reports,0); s.c.Close()
end)

test("tema automático do livro acompanha zona e facção e tema fixo ignora mudanças de contexto",function()
    local s=scene(); s.open()
    local function seal()
        local toggle=s.control("minimap","Button"); return toggle.wax.tint
    end
    local first=seal(); s.map=2395; s.n.ConfigurationUI.RefreshInfo(); local zone=seal(); assert(zone[1]~=first[1])
    s.map=84; s.faction="Horde"; s.n.ConfigurationUI.RefreshInfo(); local faction=seal(); assert(faction[1]~=zone[1])
    s.settings.Set("theme","neutral"); local fixed=t.serialize(seal()); s.map=2395; s.n.ConfigurationUI.RefreshInfo(); equal(t.serialize(seal()),fixed)
    s.n.ConfigurationUI.Close()
end)

test("opção de texto nova funciona sem alterar renderer e edição mantém foco e posição",function()
    local s=scene(); local n=s.n
    assert(n.Settings.Register("note",{type="string",default="",maxLength=40}))
    assert(n.ConfigurationCatalog.RegisterOption("general",{id="note",order=4,kind="text",title="Nota",field="note"}))
    s.open(); local edit=s.control("note","EditBox"); assert(edit); edit:SetFocus(); edit:SetText("Uma memória"); edit.cursor=7
    edit.scripts.OnTextChanged(edit,true); equal(s.root.note,"Uma memória"); equal(edit:HasFocus(),true); equal(edit.cursor,7)
    s.n.ConfigurationUI.Close()
end)

test("livro impede consumo concorrente das teclas pelo cinema e reativa ao fechar",function()
    local n=t.core(); local p=t.surfaces.platform(n); local open=true
    n.ConfigurationUI={IsOpen=function() return open end}; equal(p.api.KeyAllowed(),false)
    open=false; equal(p.api.KeyAllowed(),true)
end)

test("evento de fim de combate não insere captura e comandos usam mesma observação genérica",function()
    local c=t.client(); local ui=t.surfaces.wire(c); c.start(); c.fire("GOSSIP_SHOW"); c.flush()
    local before=t.serialize(c.saved()); c.fire("PLAYER_REGEN_ENABLED"); equal(t.serialize(c.saved()),before)
    c.command("dialogo"); equal(c.settings().dialogEnabled,false); equal(ui.visible,false)
    c.command("botao"); equal(c.settings().minimapHidden,true); equal(c.button.shown,false)
end)

test("ações registradas pelo próprio módulo funcionam sem mudar adaptador e recusam duplicatas",function()
    local s=scene(); local r=s.n.ConfigurationCatalog; local calls=0
    assert(r.RegisterAction("module.action",function() calls=calls+1; return true end))
    equal(r.RegisterAction("module.action",function() end),nil)
    equal(r.RegisterOption("general",{id="missingAction",order=4,kind="action",action="absent",title="Ausente"}),nil)
    assert(r.RegisterOption("general",{id="moduleAction",order=4,kind="action",action="module.action",title="Ação do módulo",button="Executar"}))
    s.open(); s.select("Executar"); equal(calls,1); equal(#s.records,0)
end)

test("limites de descritor tipos e campos interativos sem vínculo são rejeitados antes de registrar",function()
    local n=t.core(); local schema=n.Settings; local r=n.ConfigurationCatalog
    for _,spec in ipairs({{type="boolean",default=true,min=1},{type="string",default="",step=1},
        {type="number",default=1,maxLength=5},{type="number",default=1,min=2,max=1},
        {type="number",default=1,step=0},{type="string",default="x",values={{value="x",text="X"},{value="x",text="Outra"}}}}) do
        equal(schema.Register("bad",spec),nil); equal(schema.Describe("bad"),nil)
    end
    equal(r.RegisterOption("general",{id="bad",order=4,kind="switch",title="Sem campo",value=true}),nil)
    equal(r.RegisterOption("general",{id="bad",order=4,kind="switch",title="Tipo incorreto",field="dialogEnabled",protected="false"}),nil)
    assert(schema.Register("mustStay",{type="boolean",default=true,validate=function(value) return value end}))
    local settings=schema.Open(nil); equal(settings.Toggle("mustStay"),nil); equal(settings.Read("mustStay"),true)
end)

test("seleção numérica e informação estática podem ser acrescentadas por declaração",function()
    local s=scene(); local n=s.n
    assert(n.Settings.Register("interval",{type="number",default=1,values={{value=1,text="Uma vez"},{value=2,text="Duas vezes"}}}))
    assert(n.ConfigurationCatalog.RegisterOption("general",{id="interval",order=4,kind="select",title="Intervalo",field="interval"}))
    assert(n.ConfigurationCatalog.RegisterOption("general",{id="static",order=5,kind="info",title="Informação",value="Uma informação do módulo."}))
    assert(n.ConfigurationCatalog.RegisterOption("general",{id="readOnly",order=6,kind="info",title="Campo somente leitura",field="minimapHidden"}))
    s.open(); assert(s.region("Uma informação do módulo.")); local select=s.control("interval","Button"); select.scripts.OnClick(select)
    s.select("Duas vezes"); equal(s.root.interval,2); assert(s.region("false"))
end)

test("acesso real da composição aplica preferências e lê contadores sem alterar diário",function()
    local c=t.client(nil,{schemaVersion=1,minimapAngle=76,minimapHidden=false,dialogEnabled=true})
    local cinema=t.surfaces.wire(c); local callbacks,shown,snapshot,theme,confirm
    c.namespace.ConfigurationView.New=function(value)
        callbacks=value
        return {IsOpen=function() return shown==true end,Open=function() shown=true end,Hide=function() shown=false end,
            Render=function(input,newTheme) snapshot,theme=input,newTheme; return true end,
            Confirm=function(callback) confirm=callback end}
    end
    c.start(); c.fire("GOSSIP_SHOW"); c.flush(); local before=t.serialize(c.saved())
    c.command("config"); equal(shown,true)
    callbacks.Select("dialogue"); callbacks.Write("speed",100); equal(c.settings().speechSpeed,100); equal(cinema.view.speechSpeed,100)
    callbacks.Write("numbers",false); equal(cinema.view.numberHotkeys,false)
    callbacks.Select("general"); callbacks.Write("theme","horde"); equal(theme.key,"horde"); equal(cinema.view.theme.key,"horde")
    callbacks.Write("minimap",false); equal(c.button.shown,false)
    callbacks.Select("journal"); equal(snapshot.options[1].value,#c.saved().events); equal(snapshot.options[2].value,#c.saved().events)
    callbacks.Reset(); equal(c.settings().theme,"horde"); confirm(); equal(c.settings().theme,"auto"); equal(c.settings().minimapAngle,76)
    equal(t.serialize(c.saved()),before)
    callbacks.Action("sync"); equal(shown,false); equal(c.popupRequests,1); c.respond(false); equal(c.reloads,0)
    c.command("config"); equal(shown,true); c.fire("PLAYER_LEAVING_WORLD"); equal(shown,false)
end)

test("falha de textura do livro registra causa fecha teclado e não impede nova tentativa",function()
    local s=scene(); local color=s.r.env.CreateColor; s.r.env.CreateColor=function() error("book_texture_original") end
    equal(s.n.ConfigurationUI.Open(),false); equal(s.n.ConfigurationUI.IsOpen(),false)
    local record=s.records[#s.records]; equal(record.code,"configuration_error"); assert(record.message:find("book_texture_original",1,true)); assert(record.stack)
    equal(s.frame().keyboard,false)
    s.r.env.CreateColor=color; s.open(); equal(s.n.ConfigurationUI.IsOpen(),true)
end)

test("tamanho novo sem confirmação não inutiliza livro ao navegar capítulos",function()
    local s=scene(true); s.n.FontAPI.Preload(); s.r.advance(.2)
    local blocked=true
    s.r.rejectFont=function(path,size) return blocked and size~=21 and path:find("NerdWow\\Fonts\\",1,true)~=nil end
    s.open(); assert(s.region("Geral")); assert(not s.region(s.n.Text.configLoading))
    s.r.advance(5.2); s.select("Diálogo"); s.select("Sobre")
    assert(s.region("Sobre")); assert(s.control("github","EditBox")); equal(s.n.ConfigurationUI.IsOpen(),true)
    for _,record in ipairs(s.records) do equal(record.code,"font_fallback") end
    assert(#s.records>0 and #s.records<=4)
    blocked=false; s.select("Geral")
    assert(s.region("Geral").font:find("NerdWow\\Fonts\\",1,true))
    s.n.ConfigurationUI.Close(); s.open(); assert(s.region("Geral")); s.r.drain(); equal(#s.r.timers,0)
end)

test("botão direito reabre renderer real após verificação terminal sem reload",function()
    local c=t.client(); local s=scene(true); s.n.FontAPI.Preload(); s.r.advance(.2)
    local blocked=true
    s.r.rejectFont=function(path,size) return blocked and size==s.n.FontAPI.Scale().title and path:find("NerdWow\\Fonts\\",1,true)~=nil end
    c.namespace.ConfigurationUI.Open=s.n.ConfigurationUI.Open
    c.start()
    c.buttonEvent("OnMouseUp","RightButton",true); s.r.advance(5.2)
    local root=s.frame(); if root.scripts.OnUpdate then root.scripts.OnUpdate(root,1) end
    equal(s.n.ConfigurationUI.IsOpen(),true); assert(s.region("Geral"))
    s.n.ConfigurationUI.Close(); blocked=false
    c.buttonEvent("OnMouseUp","RightButton",true); root=s.frame(); if root.scripts.OnUpdate then root.scripts.OnUpdate(root,1) end
    equal(s.n.ConfigurationUI.IsOpen(),true); assert(s.region("Geral").font:find("Cinzel-Bold.ttf",1,true))
    equal(c.reloads,0); equal(c.popupRequests,0); s.r.drain(); equal(#s.r.timers,0)
end)

test("falha real de Render descarta view e próxima abertura cria livro limpo",function()
    local s=scene(); s.open(); local old=s.frame()
    s.r.getFont=function() error("book_region_original") end
    -- A chapter with a new EditBox forces verification on an actual region.
    s.select("Sobre"); equal(s.n.ConfigurationUI.IsOpen(),false)
    equal(old.keyboard,false); equal(old.shown,false)
    local last=s.records[#s.records]; equal(last.code,"configuration_error")
    assert(last.message:find("book_region_original",1,true)); assert(last.stack)
    s.r.getFont=nil; s.open(); assert(s.frame()~=old); assert(s.control("github","EditBox"))
    assert(not s.region(s.n.Text.configLoading)); equal(s.n.ConfigurationUI.IsOpen(),true)
end)

test("hover de índice linhas botões e interruptores tem contraste nos quatro temas",function()
    for _,theme in ipairs({"alliance","horde","quelthalas","neutral"}) do
        local s=scene(); s.settings.Set("theme",theme); s.open()
        local chosen=s.button("Geral"); local nextChapter=s.button("Diálogo")
        equal(chosen.feedback.selected,true); equal(nextChapter.feedback.selected,false)
        nextChapter.scripts.OnEnter(nextChapter)
        equal(nextChapter.feedback.fill.fill[4],.24); equal(nextChapter.feedback.marker.fill[4],.95)
        equal(chosen.feedback.fill.fill[4],0); equal(chosen.fill.fill[4],.12)
        chosen.scripts.OnEnter(chosen); equal(chosen.feedback.fill.fill[4],.32)
        nextChapter.scripts.OnLeave(nextChapter); equal(nextChapter.feedback.fill.fill[4],0)
        local toggle=s.control("minimap","Button"); local row=toggle.parent
        local textColor=t.serialize(row.title.textColor)
        toggle.scripts.OnEnter(toggle); equal(toggle.feedback.fill.fill[4],.24)
        equal(row.feedback.fill.fill[4],.24); equal(t.serialize(row.title.textColor),textColor)
        toggle.scripts.OnLeave(toggle); equal(row.feedback.fill.fill[4],0)
        local close=s.button("Fechar"); close.scripts.OnEnter(close)
        equal(close.alpha,1); equal(close.feedback.fill.fill[4],.24)
        assert(close.label.textColor[1]>.9); close.scripts.OnLeave(close)
        local root=s.frame(); root.scripts.OnKeyDown(root,"DOWN")
        equal(nextChapter.feedback.focus,true); equal(nextChapter.feedback.fill.fill[4],.32)
        local slider=s.control("speed","Slider"); slider.scripts.OnMouseDown(slider)
        equal(slider.feedback.focus,true); equal(slider.parent.feedback.fill.fill[4],.24)
        slider.scripts.OnMouseUp(slider); equal(slider.feedback.focus,false)
        s.select("Sobre"); local edit=s.control("github","EditBox"); edit:SetFocus()
        equal(edit.feedback.fill.fill[4],.24); equal(edit.parent.feedback.fill.fill[4],.24)
        edit:ClearFocus(); equal(edit.feedback.fill.fill[4],0)
        s.n.ConfigurationUI.Close()
    end
end)

test("hover não habilita em breve e seleção sublinhada conserva destaque",function()
    local s=scene(); s.open(); local select=s.control("theme","Button")
    select.scripts.OnEnter(select); equal(select.feedback.fill.fill[4],.24)
    select.scripts.OnClick(select); local choice=s.button("Neutro"); choice.scripts.OnEnter(choice)
    equal(choice.feedback.fill.fill[4],.24); choice.scripts.OnClick(choice); equal(s.root.theme,"neutral")
    s.select("Câmera e interface")
    for _,frame in ipairs(s.r.frames) do
        if frame.parent.spec and frame.parent.spec.soon and frame.feedback and visible(frame) then
            frame.scripts.OnEnter(frame); equal(frame.enabled,false)
            assert(frame.feedback.fill.fill[4]<.24)
        end
    end
    s.n.ConfigurationUI.Close()
end)
test("Personagem e Sobre abrem com EB Garamond em EditBox estrita em proporções e escalas",function()
    for _,size in ipairs({{1920,1080},{3440,1440},{5120,1440},{6400/3,1200}}) do
        for _,scale in ipairs({.64,.8,1,1.25}) do
            local s=scene(); s.r.parent:SetSize(size[1]/scale,size[2]/scale)
            local before=t.serialize(s.root); s.open()
            for _,chapter in ipairs({"Personagem","Sobre","Personagem","Sobre"}) do
                s.select(chapter); equal(s.n.ConfigurationUI.IsOpen(),true)
                local ids=chapter=="Personagem" and {"name","title"} or {"github"}
                for _,id in ipairs(ids) do
                    local edit=assert(s.control(id,"EditBox"))
                    assert(edit.font:find("EBGaramond-Regular.ttf",1,true)); equal(edit.flags,"")
                    equal(edit.enabled,chapter=="Sobre"); equal(edit.size,s.n.FontAPI.Scale().body)
                    assert(edit:GetText()~=""); assert(visible(edit))
                end
                assert(not s.region(s.n.Text.configLoading))
            end
            equal(#s.records,0); equal(t.serialize(s.root),before); s.n.ConfigurationUI.Close()
        end
    end
end)

test("GitHub recebe foco seleção e Ctrl C nativo sem aceitar edição nem fechar livro",function()
    local s=scene(); s.open(); s.select("Sobre")
    local edit=assert(s.control("github","EditBox")); local expected=edit:GetText(); local root=s.frame()
    equal(edit.enabled,true); edit:SetFocus(); equal(edit:HasFocus(),true); equal(edit.highlighted,true)
    root.scripts.OnKeyDown(root,"C"); equal(root.propagate,true); equal(s.r.focus,edit)
    equal(edit:GetText(),expected); assert(expected:find("https://github.com/ThiagoGregson/",1,true))
    edit:SetText("edição indevida"); edit.scripts.OnTextChanged(edit,true); equal(edit:GetText(),expected)
    equal(edit.highlighted,true); equal(s.n.ConfigurationUI.IsOpen(),true)
    s.select("Personagem")
    for _,id in ipairs({"name","title"}) do
        local future=s.control(id,"EditBox"); equal(future.enabled,false); equal(future.parent.spec.soon,true)
        future.scripts.OnTextChanged(future,true); equal(s.root[id],nil)
    end
    equal(#s.records,0); s.n.ConfigurationUI.Close()
end)

test("recusa de fonte embutida em EditBox usa Arial com flags válidas e capítulo aberto",function()
    local s=scene()
    s.r.rejectFont=function(path,_,_,object)
        return object.kind=="EditBox" and path:find("NerdWow\\Fonts\\",1,true)~=nil
    end
    s.open(); s.select("Personagem"); s.select("Sobre")
    local edit=s.control("github","EditBox")
    equal(edit.font,"Fonts\\ARIALN.TTF"); equal(edit.flags,""); equal(edit.enabled,true)
    equal(s.n.ConfigurationUI.IsOpen(),true); equal(#s.records,1); equal(s.records[1].code,"font_fallback")
    for _,call in ipairs(s.r.fontCalls) do equal(call.flags,"") end
    s.n.ConfigurationUI.Close()
end)

test("ambas fontes recusadas ou com erro conservam capítulos por objeto nativo e recuperam",function()
    for _,mode in ipairs({"false","error"}) do
        local s=scene(true); s.n.FontAPI.Preload(); s.r.advance(.2)
        local rejected=true
        s.r.rejectFont=function(_,_,_,object)
            if rejected and object.kind=="EditBox" then
                if mode=="error" then error("editbox_font_original") end
                return true
            end
        end
        s.open(); s.select("Personagem")
        for _,id in ipairs({"name","title"}) do
            local future=assert(s.control(id,"EditBox")); equal(future.fontObject,s.r.env.GameFontNormal)
            equal(future.enabled,false); assert(future.text~="")
        end
        s.select("Sobre"); local edit=assert(s.control("github","EditBox"))
        equal(edit.fontObject,s.r.env.GameFontNormal); equal(edit.enabled,true); edit:SetFocus(); equal(edit.highlighted,true)
        equal(#s.records,1); equal(s.records[1].code,"font_fallback_failed")
        assert(s.records[1].message:find("recovered=true",1,true))
        if mode=="error" then assert(s.records[1].message:find("editbox_font_original",1,true)); assert(s.records[1].stack) end
        equal(s.n.ConfigurationUI.IsOpen(),true); assert(not s.region(s.n.Text.configLoading))
        local text=edit:GetText(); rejected=false; s.r.advance(1.1)
        assert(edit.font:find("EBGaramond-Regular.ttf",1,true)); equal(edit:GetText(),text); equal(edit:HasFocus(),true)
        s.select("Personagem"); assert(s.control("name","EditBox").font:find("EBGaramond-Regular.ttf",1,true))
        s.n.ConfigurationUI.Close(); s.open(); s.select("Sobre"); equal(s.n.ConfigurationUI.IsOpen(),true)
        equal(#s.records,1); s.r.drain(); equal(#s.r.timers,0)
    end
end)
test("SetFont false em EditBox com identidade EB Garamond confirmada não usa fallback",function()
    local s=scene(true); s.n.FontAPI.Preload(); s.r.advance(.2)
    s.r.fontBehavior=function(path,_,flags,object)
        if object.kind=="EditBox" and path:find("NerdWow\\Fonts\\",1,true) then
            equal(flags,""); return {delay=.3,identityNow=true,factor=1}
        end
    end
    s.open(); s.select("Personagem")
    for _,id in ipairs({"name","title"}) do
        local field=assert(s.control(id,"EditBox")); assert(field.font:find("EBGaramond-Regular.ttf",1,true))
        equal(field.enabled,false); equal(field.fontObject,nil)
    end
    s.select("Sobre"); local field=assert(s.control("github","EditBox"))
    assert(field.font:find("EBGaramond-Regular.ttf",1,true)); equal(field.enabled,true)
    s.r.drain(); equal(#s.records,0); equal(s.n.ConfigurationUI.IsOpen(),true)
    s.n.ConfigurationUI.Close()
end)
return {scene=scene,visible=visible}
