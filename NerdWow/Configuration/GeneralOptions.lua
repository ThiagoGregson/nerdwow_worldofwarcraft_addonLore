local _,addon=...
addon.GeneralOptions={Register=function(r)
    local s=addon.Settings
    s.Register("minimapHidden",{type="boolean",default=false})
    s.Register("minimapAngle",{type="number",default=225,min=0,max=360,exclusiveMax=true})
    s.Register("theme",{type="string",default="auto",values={
        {value="auto",text="Automático"},{value="quelthalas",text="Quel'Thalas"},
        {value="alliance",text="Aliança"},{value="horde",text="Horda"},{value="neutral",text="Neutro"}}})
    r.RegisterChapter({id="general",order=1,title="Geral",description="Como o NerdWow aparece no seu jogo."})
    r.RegisterOption("general",{id="minimap",order=1,kind="switch",field="minimapHidden",inverted=true,title="Botão no minimapa",
        description="Mostra o livro na borda do minimapa. Clique esquerdo sincroniza; botão direito abre estas configurações."})
    r.RegisterOption("general",{id="theme",order=2,kind="select",field="theme",title="Tema das janelas",
        description="Automático escolhe pela zona, depois pela facção do NPC. Neste livro, usa a facção do personagem."})
    r.RegisterOption("general",{id="scale",order=3,kind="slider",soon=true,title="Escala das janelas",value=100,min=80,max=130,step=1,suffix="%",
        description="Aumenta ou diminui a conversa, o pergaminho e este livro."})
end}
