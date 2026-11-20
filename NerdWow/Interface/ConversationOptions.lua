local _,addon=...
addon.ConversationOptions={Register=function(r)
    local s=addon.Settings
    s.Register("dialogEnabled",{type="boolean",default=true})
    s.Register("speechSpeed",{type="number",default=addon.Conversation.DEFAULT_SPEED,min=20,max=120,step=1})
    s.Register("numberHotkeys",{type="boolean",default=true})
    r.RegisterChapter({id="dialogue",order=2,title="Diálogo",description="A conversa em modo cinema e o pergaminho de missão."})
    r.RegisterOption("dialogue",{id="cinema",order=1,kind="switch",field="dialogEnabled",title="Modo cinema",
        description="Substitui as janelas de conversa e de missão da Blizzard. Desligado, o jogo usa as janelas originais."})
    r.RegisterOption("dialogue",{id="speed",order=2,kind="slider",field="speechSpeed",title="Velocidade da fala",
        description="Letras por segundo. Espaço sempre mostra a fala inteira."})
    r.RegisterOption("dialogue",{id="numbers",order=3,kind="switch",field="numberHotkeys",title="Atalhos 1 a 9",
        description="Escolhe opções e recompensas pelo teclado. Espaço e Esc continuam disponíveis."})
end}
