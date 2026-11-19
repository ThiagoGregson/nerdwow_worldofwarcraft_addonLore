local _, addon = ...
local Shared = {}
addon.DialogueAPI = Shared
local MAX = 9007199254740991

-- Toda comparação/conversão de retornos passa primeiro pela barreira de secretos.
function Shared.Reader()
    local failure, detail
    local r = {}
    function r.Plain(value)
        if issecretvalue and issecretvalue(value) then failure, detail = "secret_value", nil; return nil end
        return value
    end
    function r.Call(fn, ...)
        if type(fn) ~= "function" then return nil end
        local ok, a, b, c, d, e, f, g, h = addon.DiagnosticAPI.Try(fn, ...)
        if not ok then failure, detail = "api_error", a; return nil end
        return a, b, c, d, e, f, g, h
    end
    function r.Number(value, minimum, maximum)
        value = r.Plain(value)
        if type(value) == "number" and value >= minimum and value <= (maximum or MAX)
            and value == math.floor(value) then return value end
    end
    function r.String(value)
        value = r.Plain(value)
        if type(value) == "string" then return value end
    end
    function r.Boolean(value)
        value = r.Plain(value)
        if type(value) == "boolean" then return value end
    end
    function r.Table(value)
        value = r.Plain(value)
        if type(value) == "table" then return value end
    end
    function r.Issue() return failure, detail end
    function r.Fail(code) failure = failure or code end
    return r
end

function Shared.ReadNPC(r)
    if r.Boolean(r.Call(UnitExists, "npc")) ~= true then return nil end
    local guid = r.String(r.Call(UnitGUID, "npc"))
    local creatureID
    if guid then
        creatureID = r.Number(tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
            or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")), 1)
    end
    local result = { guid = guid, creatureID = creatureID, name = r.String(r.Call(UnitName, "npc")),
        faction = r.String(r.Call(UnitFactionGroup, "npc")) }
    if result.guid == "" then result.guid = nil end
    if result.faction == "" then result.faction = nil end
    if creatureID and type(C_TooltipInfo) == "table" then
        local data = r.Table(r.Call(C_TooltipInfo.GetUnit, "npc"))
        local lines = data and r.Table(data.lines)
        local line = lines and r.Table(lines[2])
        local subtitle = line and r.String(line.leftText)
        if subtitle then result.title = subtitle:match("^<([^<>]+)>$") end
    end
    if not result.guid and not result.name and not result.faction and not result.title then return nil end
    return result
end

