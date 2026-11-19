local addonName, addon = ...
local Wow = {}
addon.Wow = Wow

local function secret(value)
    return issecretvalue and issecretvalue(value)
end

local function readCharacter()
    local name, realm = UnitName("player")
    if secret(name) then return nil, "secret_value", "payload.name" end
    if secret(realm) then return nil, "secret_value", "payload.realm" end
    if realm == nil or realm == "" then
        realm = GetRealmName()
    end
    local raceName, race, raceID = UnitRace("player")
    local className, class, classID = UnitClass("player")
    local payload = {
        guid = UnitGUID("player"), name = name, realm = realm,
        raceName = raceName, race = race, raceID = raceID,
        className = className, class = class, classID = classID,
        level = UnitLevel("player"), faction = UnitFactionGroup("player"),
    }
    for field, value in pairs(payload) do
        if secret(value) then
            return nil, "secret_value", "payload." .. field
        end
    end
    for _, field in ipairs({ "guid", "name", "realm", "raceName", "race", "raceID",
        "className", "class", "classID", "level", "faction" }) do
        if payload[field] == nil or payload[field] == "" then return nil, "api_unavailable", "payload." .. field end
    end
    return payload
end

local function readLocation()
    local payload = {
        mapID = C_Map.GetBestMapForUnit("player"),
        zone = GetZoneText(), subZone = GetSubZoneText(),
    }
    for field, value in pairs(payload) do
        if secret(value) then
            return nil, "secret_value", "payload." .. field
        end
    end
    if payload.zone == nil or payload.zone == "" then return nil, "api_unavailable", "payload.zone" end
    if payload.subZone == nil then return nil, "api_unavailable", "payload.subZone" end
    return payload
end

local function readSafely(reader)
    local ok, value, code, field = addon.DiagnosticAPI.Try(reader)
    if not ok then
        return nil, "api_error", nil, value
    end
    return value, code, field
end

function Wow.ReadCharacter()
    return readSafely(readCharacter)
end

function Wow.ReadLocation()
    return readSafely(readLocation)
end

function Wow.ServerTime()
    local ok, value = addon.DiagnosticAPI.Try(GetServerTime)
    if not ok then
        return nil, "api_error", "timestamp", value
    end
    if secret(value) then
        return nil, "secret_value", "timestamp"
    end
    if value == nil then
        return nil, "api_unavailable", "timestamp"
    end
    return value
end

function Wow.Version()
    return C_AddOns.GetAddOnMetadata(addonName, "Version") or addon.Text.unavailable
end

function Wow.FormatTime(timestamp)
    local ok, formatted = pcall(date, "!%Y-%m-%d %H:%M:%S UTC", timestamp)
    if ok and type(formatted) == "string" then
        return formatted
    end
    return addon.Text.unavailable
end

function Wow.Print(message)
    DEFAULT_CHAT_FRAME:AddMessage(addon.Text.prefix .. message)
end

function Wow.RegisterCommand(callback)
    SLASH_NERDWOW1 = "/nerdwow"
    SlashCmdList.NERDWOW = callback
end

local function canSync()
    if InCombatLockdown() then
        Wow.Print(addon.Text.syncCombat)
        return false
    end
    return true
end

StaticPopupDialogs.NERDWOW_SYNC = {
    text = addon.Text.syncConfirmation,
    button1 = addon.Text.syncAccept,
    button2 = addon.Text.syncCancel,
    OnAccept = function()
        -- O combate pode ter começado enquanto a confirmação estava aberta.
        if canSync() then
            C_UI.Reload()
        end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function Wow.RequestSync()
    if canSync() and not StaticPopup_Show("NERDWOW_SYNC") then
        Wow.Print(addon.Text.syncUnavailable)
    end
end

-- Global exigida pelo AddonCompartmentFunc; o restante permanece no namespace privado.
function NerdWow_OnAddonCompartmentClick()
    Wow.RequestSync()
end

function Wow.Listen(callback, dialogueEvents)
    -- Frame sem nome e sem elementos visuais; usado apenas como receptor de eventos.
    local frame = CreateFrame("Frame")
    frame:SetScript("OnEvent", function(_, event, ...)
        callback(event, ...)
    end)
    for _, event in ipairs({ "ADDON_LOADED", "PLAYER_ENTERING_WORLD",
        "PLAYER_LEAVING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
        "ZONE_CHANGED_NEW_AREA" }) do
        frame:RegisterEvent(event)
    end
    for _, event in ipairs(dialogueEvents or {}) do frame:RegisterEvent(event) end
end
