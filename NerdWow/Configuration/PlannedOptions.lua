local _,addon=...
addon.PlannedOptions={Register=function(r)
    r.RegisterChapter({id="camera",order=3,title="Câmera e interface",description="O enquadramento de cinema durante a conversa.",soon=true})
    r.RegisterOption("camera",{id="camera",order=1,kind="switch",value=true,title="Aproximar a câmera do NPC",
        description="Enquadra quem está falando. A câmera volta à posição anterior quando a conversa termina."})
    r.RegisterOption("camera",{id="zoom",order=2,kind="slider",value=3,min=1,max=5,step=1,title="Intensidade do zoom",
        description="De um enquadramento discreto até um close no rosto."})
    r.RegisterOption("camera",{id="interface",order=3,kind="switch",value=true,title="Ocultar a interface do jogo",
        description="Esconde barras, minimapa e chat durante a conversa. Nunca acontece em combate."})
    r.RegisterChapter({id="character",order=4,title="Personagem",description="Como os NPCs e o diário chamam o seu personagem.",soon=true})
    r.RegisterOption("character",{id="name",order=1,kind="text",value="",placeholder="Nome de RP",title="Nome de RP",
        description="Um nome para as falas exibidas e a exportação. O diário mantém o texto original."})
    r.RegisterOption("character",{id="title",order=2,kind="text",value="",placeholder="Título do personagem",title="Título",
        description="Opcional, ao lado do nome na exportação."})
end}
