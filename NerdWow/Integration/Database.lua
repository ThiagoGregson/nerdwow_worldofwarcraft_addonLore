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
    ReadSettings = function()
        return NerdWow_Settings
    end,
    BindSettings = function(root)
        NerdWow_Settings = root
    end,
    ReadCinematicRecovery = function()
        if type(NerdWow_Settings)=="table" then return NerdWow_Settings.cinematicRecovery end
    end,
    BindCinematicRecovery = function(value)
        if type(NerdWow_Settings)~="table" then error("settings_unavailable") end
        NerdWow_Settings.cinematicRecovery=value
    end,
    ReadDiagnostics = function()
        return NerdWow_Diagnostics
    end,
    BindDiagnostics = function(root)
        NerdWow_Diagnostics = root
    end,
}
