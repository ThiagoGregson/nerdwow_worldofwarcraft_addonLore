local _,addon=...
-- Composition of declarations; providers own their fields, chapters and options.
local registry=addon.ConfigurationRegistry.New(addon.Settings)
addon.ConfigurationCatalog=registry
for _,provider in ipairs({addon.GeneralOptions,addon.ConversationOptions,addon.CinematicOptions,addon.PlannedOptions,
    addon.JournalOptions,addon.DiagnosticOptions,addon.AboutOptions}) do provider.Register(registry) end
