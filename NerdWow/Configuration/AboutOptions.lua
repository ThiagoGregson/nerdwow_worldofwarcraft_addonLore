local _,addon=...
addon.AboutOptions={Register=function(r)
    r.RegisterChapter({id="about",order=7,title="Sobre",description="NerdWow, para quem joga pela história."})
    r.RegisterOption("about",{id="version",order=1,kind="info",title="Versão",description="Retail · Midnight",valueKey="about.version"})
    r.RegisterOption("about",{id="project",order=2,kind="info",title="Projeto",valueKey="about.site",description="Código e downloads no GitHub."})
    r.RegisterOption("about",{id="github",order=3,kind="text",readOnly=true,title="GitHub",valueKey="about.github",fullWidth=true,
        description="Selecione o endereço e use Ctrl+C para copiar. O jogo não abre links."})
    r.RegisterOption("about",{id="credits",order=4,kind="info",title="Créditos",fullWidth=true,valueKey="about.credits"})
end}
