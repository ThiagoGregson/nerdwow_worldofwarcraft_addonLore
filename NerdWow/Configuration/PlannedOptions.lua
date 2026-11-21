local _,addon=...
addon.PlannedOptions={Register=function(r)
    r.RegisterChapter({id="character",order=4,title="Personagem",description="Como os NPCs e o diário chamam o seu personagem.",soon=true})
    r.RegisterOption("character",{id="name",order=1,kind="text",value="",placeholder="Nome de RP",title="Nome de RP",
        description="Um nome para as falas exibidas e a exportação. O diário mantém o texto original."})
    r.RegisterOption("character",{id="title",order=2,kind="text",value="",placeholder="Título do personagem",title="Título",
        description="Opcional, ao lado do nome na exportação."})
end}
