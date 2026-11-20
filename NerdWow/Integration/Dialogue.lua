local _, addon = ...
local Shared = {}
addon.DialogueAPI = Shared
local MAX = 9007199254740991
local titleSeen,titleCount={},0

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

local function cleanText(text)
    return text and text:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r",""):match("^%s*(.-)%s*$")
end
-- Use the client's localized level template: Retail can report all detail
-- lines as None. Row two by itself is never evidence of an NPC title.
local function levelMatcher(template)
    template=cleanText(template)
    if not template then return end
    local pattern,literal,tokens={},false,0
    local position=1
    while position<=#template do
        local char=template:sub(position,position)
        if char=="%" then
            local tail=template:sub(position)
            local token=tail:match("^%%[1-9]%d*%$[sd]") or tail:match("^%%[sd]")
            if token then
                tokens=tokens+1; pattern[#pattern+1]=token:sub(-1)=="d" and "(%d+)" or "(.-)"
                position=position+#token
            elseif template:sub(position,position+1)=="%%" then
                pattern[#pattern+1]="%%"; literal=true; position=position+2
            else return end
        else
            pattern[#pattern+1]=char:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])","%%%1")
            if char:match("%S") then literal=true end
            position=position+1
        end
    end
    if not literal or tokens==0 or tokens>4 then return end
    local match="^"..table.concat(pattern).."$"
    return function(text)
        if not text then return false end
        local fields={text:match(match)}
        for _,value in ipairs(fields) do
            if value:match("^%d+$") or value:match("^%d+%s+%S") then return true end
        end
        return false
    end
end
local function readTitle(r,npc,localizedFaction)
    local types=type(Enum)=="table" and Enum.TooltipDataLineType or {}
    local levelType,unitType=types.UnitLevel or 47,types.UnitType or 48
    local matchesLevel=levelMatcher(r.String(TOOLTIP_UNIT_LEVEL))
    local function inspect(data)
        data=r.Table(data)
        if not data then return nil,"data_unavailable" end
        local dataGUID=r.String(data.guid)
        if issecretvalue and issecretvalue(data.guid) then return nil,"identity_restricted" end
        if r.Plain(data.guid)~=nil and dataGUID~=npc.guid then return nil,"identity_mismatch" end
        local lines=r.Table(data.lines)
        if not lines then return nil,"lines_unavailable" end
        local rows={}
        for index=1,12 do
            local value=r.Plain(lines[index])
            if value==nil then
                if issecretvalue and issecretvalue(lines[index]) then return nil,"line_restricted" end
                break
            end
            local line=r.Table(value)
            if not line then return nil,"invalid_line" end
            local text=cleanText(r.String(line.leftText))
            local kind=r.Number(line.type,0)
            if issecretvalue and (issecretvalue(line.type) or issecretvalue(line.leftText)) then return nil,"line_restricted" end
            if r.Plain(line.type)~=nil and kind==nil then return nil,"invalid_line_type" end
            if kind~=1 and text~="" then
                rows[#rows+1]={text=text,kind=kind}
                if #rows>1 and (kind==levelType or matchesLevel and matchesLevel(text)) then break end
            end
        end
        if not npc.name or not rows[1] or rows[1].text~=npc.name then return nil,"header_mismatch" end
        for index=2,#rows do
            local row=rows[index]
            if row.kind==levelType or matchesLevel and matchesLevel(row.text) then
                if index==2 then return nil,"no_title" end
                local candidate=rows[index-1]
                if not candidate.text or candidate.kind~=nil and candidate.kind~=(types.None or 0) then
                    return nil,"invalid_title_line"
                end
                local title=candidate.text:match("^<([^<>]+)>$") or candidate.text
                title=cleanText(title)
                if title=="" or title==npc.name or title==npc.faction or title==localizedFaction
                    or candidate.kind==unitType then return nil,"invalid_title_line" end
                return title,"applied"
            end
        end
        return nil,matchesLevel and "level_boundary_missing" or "localized_level_unavailable"
    end
    local title,reason=inspect(r.Call(type(C_TooltipInfo)=="table" and C_TooltipInfo.GetUnit,"npc"))
    if not title and reason~="no_title" and npc.guid and type(UnitTokenFromGUID)=="function" then
        local token=r.String(r.Call(UnitTokenFromGUID,npc.guid))
        if token and token~="npc" and r.String(r.Call(UnitGUID,token))==npc.guid then
            title,reason=inspect(r.Call(type(C_TooltipInfo)=="table" and C_TooltipInfo.GetUnit,token))
        end
    end
    if not title and reason~="no_title" and npc.guid and GameTooltip and type(GameTooltip.GetPrimaryTooltipData)=="function" then
        local data=r.Table(r.Call(GameTooltip.GetPrimaryTooltipData,GameTooltip))
        if data and r.String(data.guid)==npc.guid then title,reason=inspect(data) end
    end
    -- No routine raw probes: log only failures, once per NPC, without any text
    -- from the tooltip or any GUID/secret values.
    if not title and reason~="no_title" and not titleSeen[npc.creatureID] and titleCount<128 then
        titleSeen[npc.creatureID]=true; titleCount=titleCount+1
        addon.DiagnosticAPI.Record("interface","npc_title_unavailable",{message=reason},
            {stage="npc_title",creatureID=npc.creatureID})
    end
    return title
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
    if creatureID then result.title=readTitle(r,result,localizedFaction) end
    if not result.guid and not result.name and not result.faction and not result.title then return nil end
    return result
end

