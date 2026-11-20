local _,addon=...
addon.JournalOptions={Register=function(r)
    r.RegisterAction("sync",function(services) return services.Sync() end)
    r.RegisterChapter({id="journal",order=5,title="Diário",description="O que o NerdWow guardou da sua jornada."})
    for index,spec in ipairs({{"total","Eventos no diário"},{"pending","Ainda não gravados"},{"last","Último registro (UTC)"}}) do
        r.RegisterOption("journal",{id=spec[1],order=index,kind="indicator",title=spec[2],valueKey="journal."..spec[1]})
    end
    r.RegisterOption("journal",{id="sync",order=4,kind="action",action="sync",protected=true,primary=true,title="Sincronizar agora",button="Sincronizar",
        description="Recarrega a interface para gravar o diário em disco. Indisponível em combate."})
    r.RegisterOption("journal",{id="limit",order=5,kind="info",title="Limite do diário",valueKey="journal.limit",
        description="Os eventos mais antigos são descartados quando o limite é atingido."})
end}
