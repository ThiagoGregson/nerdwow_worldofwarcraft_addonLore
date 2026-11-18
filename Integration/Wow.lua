local addonName, addon = ...
local Wow = {}
addon.Wow = Wow

local function secret(value)
    return issecretvalue and issecretvalue(value)
end

local function readCharacter()
    local name, realm = UnitName("player")
    if secret(name) or secret(realm) then
        return nil, "secret_value"
    end
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
    for _, value in pairs(payload) do
        if secret(value) then
            return nil, "secret_value"
        end
    end
    return payload
end

local function readLocation()
    local payload = {
        mapID = C_Map.GetBestMapForUnit("player"),
        zone = GetZoneText(), subZone = GetSubZoneText(),
    }
    for _, value in pairs(payload) do
        if secret(value) then
            return nil, "secret_value"
        end
    end
    return payload
end

local function readSafely(reader)
    local ok, value, code = pcall(reader)
    if not ok then
        return nil, "api_error"
    end
    return value, code
end

function Wow.ReadCharacter()
    return readSafely(readCharacter)
end

function Wow.ReadLocation()
    return readSafely(readLocation)
end

function Wow.ServerTime()
    local ok, value = pcall(GetServerTime)
    if not ok then
        return nil, "api_error"
    end
    if secret(value) then
        return nil, "secret_value"
    end
    if value == nil then
        return nil, "api_unavailable"
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

function Wow.Listen(callback)
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
end
