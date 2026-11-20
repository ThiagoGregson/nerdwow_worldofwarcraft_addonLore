local _,addon=...
addon.DiagnosticOptions={Register=function(r)
    r.RegisterAction("diagnostics",function(services) return services.Diagnostics() end)
    r.RegisterAction("fonts",function(services) return services.Fonts() end)
    r.RegisterChapter({id="advanced",order=6,title="Avançado",description="Ferramentas para relatar problemas."})
    r.RegisterOption("advanced",{id="diagnostics",order=1,kind="action",action="diagnostics",title="Últimos registros do diagnóstico",button="Ver registros",
        description="Exibe neste livro os cinco registros mais recentes, sem alterar o histórico."})
    r.RegisterOption("advanced",{id="records",order=2,kind="info",title="Registros recentes",valueKey="diagnostics.records",visibleWhen="records",fullWidth=true})
    r.RegisterOption("advanced",{id="fonts",order=3,kind="action",action="fonts",title="Teste de fontes",button="Testar",
        description="Confere o retorno imediato e o estado depois do carregamento."})
    r.RegisterOption("advanced",{id="report",order=4,kind="info",title="Resultado do teste",valueKey="fonts.report",visibleWhen="fonts",fullWidth=true})
end}
