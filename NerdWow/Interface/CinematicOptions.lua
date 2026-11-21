local _,addon=...
addon.CinematicOptions={Register=function(r)
    addon.Settings.Register("cameraEnabled",{type="boolean",default=true})
    addon.Settings.Register("cameraIntensity",{type="number",default=3,min=1,max=5,step=1})
    addon.Settings.Register("hideGameUI",{type="boolean",default=true})
    r.RegisterChapter({id="camera",order=3,title="Câmera e interface",description="O enquadramento de cinema durante a conversa. Mudanças valem na próxima abertura."})
    r.RegisterOption("camera",{id="camera",order=1,kind="switch",field="cameraEnabled",title="Aproximar a câmera do NPC",
        description="Enquadra o rosto de quem está falando. O jogo pode exibir um aviso de câmera experimental."})
    r.RegisterOption("camera",{id="zoom",order=2,kind="slider",field="cameraIntensity",title="Intensidade do zoom",
        description="De um enquadramento discreto até um close no rosto. A câmera anterior é restaurada ao terminar."})
    r.RegisterOption("camera",{id="interface",order=3,kind="switch",field="hideGameUI",title="Ocultar a interface do jogo",
        description="Recolhe barras, minimapa, objetivos, chat e quadros. Nomes e alertas permanecem; combate restaura tudo."})
end}
