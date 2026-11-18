local _, addon = ...

-- Infraestrutura compartilhada (MOD-04). O jogo é responsável pelo flush em disco.
-- Somente a composição usa Read/Bind; o contrato e a raiz pertencem ao diário.
addon.database = {
    Read = function()
        return NerdWow_Journal
    end,
    Bind = function(root)
        NerdWow_Journal = root
    end,
}
