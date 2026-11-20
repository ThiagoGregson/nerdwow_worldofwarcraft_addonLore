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
    local faction,localizedFaction=r.Call(UnitFactionGroup,"npc")
    local result = { guid = guid, creatureID = creatureID, name = r.String(r.Call(UnitName, "npc")),
        faction = r.String(faction) }
    localizedFaction=r.String(localizedFaction)
    if result.guid == "" then result.guid = nil end
    if result.faction == "" then result.faction = nil end
    if creatureID and type(C_TooltipInfo) == "table" then
        local data = r.Table(r.Call(C_TooltipInfo.GetUnit, "npc"))
        local lines = data and r.Table(data.lines)
        local line = lines and r.Table(lines[2])
        local subtitle = line and r.String(line.leftText)
        if subtitle then
            local clean=subtitle:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):match("^%s*(.-)%s*$")
            local bracketed=clean:match("^<([^<>]+)>$")
            local lineType=line and r.Number(line.type,0)
            -- Retail explicitly tags level/type lines. Untyped legacy lines are
            -- accepted only with delimiters; a free-form line 2 is not proof.
            local types=type(Enum)=="table" and Enum.TooltipDataLineType
            local none=types and types.None or 0
            local header=lines and r.Table(lines[1])
            local headerText=header and r.String(header.leftText)
            local following=lines and r.Table(lines[3])
            local nextType=following and r.Number(following.type,0)
            local levelType=types and types.UnitLevel or 47
            local unitType=types and types.UnitType or 48
            if lineType~=levelType and lineType~=unitType and bracketed then result.title=bracketed
            elseif lineType==none and (nextType==levelType or nextType==unitType) and headerText and result.name
                and headerText:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")==result.name
                and clean~="" and clean~=result.name and clean~=result.faction and clean~=localizedFaction then
                result.title=clean
            end
        end
    end
    if not result.guid and not result.name and not result.faction and not result.title then return nil end
    return result
end

