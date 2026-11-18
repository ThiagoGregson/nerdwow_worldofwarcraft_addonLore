local _, addon = ...

-- Catálogo único da entrega; não depende do idioma configurado no cliente.
addon.Text = {
    prefix = "|cff70c0ffNerdWow:|r ",
    status = "v%s | esquema %d | %d eventos | último: %s, %s",
    help = "Use /nerdwow para status ou /nerdwow ajuda para esta ajuda. Grave o diário com /reload.",
    noEvent = "nenhum",
    noTime = "sem horário",
    unavailable = "indisponível",
    blocked = "Gravação suspensa: %s. Os dados existentes foram preservados.",
    captureFailed = "Evento não registrado: %s.",
    retention = "Retenção aplicada; %d eventos descartados no total (limite: %d).",
    eventTypes = {
        CHARACTER_CONTEXT = "contexto do personagem",
        LOCATION_CHANGED = "mudança de local",
    },
    errors = {
        invalid_root = "raiz do diário ausente ou inválida",
        unsupported_schema = "versão de esquema não suportada",
        invalid_events = "coleção de eventos inválida",
        invalid_event = "evento persistido inválido",
        invalid_sequence = "sequência persistida inconsistente",
        invalid_input = "dados obrigatórios ausentes ou inválidos",
        unsupported_type = "tipo de evento não suportado",
        sequence_exhausted = "limite de identificadores atingido",
        api_error = "falha ao consultar a API do jogo",
        api_unavailable = "dados do jogo ainda indisponíveis",
        secret_value = "dados restritos do jogo indisponíveis para captura",
        not_initialized = "diário ainda não inicializado",
    },
}
