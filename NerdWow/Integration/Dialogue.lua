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
local function readTitle(r,npc,localizedFaction)
    local trace,decisions,redacted={},{},false
    local function raw(value)
        if issecretvalue and issecretvalue(value) then redacted=true; return "<secret>" end
        if type(value)=="string" then return string.format("%q",value) end
        if type(value)=="number" and value==value and math.abs(value)<=MAX then return tostring(value) end
        return "<"..type(value)..">"
    end
    local types=type(Enum)=="table" and Enum.TooltipDataLineType or {}
    local levelType,unitType=types.UnitLevel or 47,types.UnitType or 48
    local function inspect(data,source)
        trace[#trace+1]="source="..source
        local rawData=data
        data=r.Table(data)
        if not data then trace[#trace+1]="data="..raw(rawData); return nil,"data_unavailable" end
        -- A supplied identity is authoritative; never use a tooltip for another unit.
        local hiddenGUID=issecretvalue and issecretvalue(data.guid)
        local dataGUID=r.String(data.guid)
        local identityOK=not hiddenGUID and (dataGUID==nil and r.Plain(data.guid)==nil or dataGUID==npc.guid)
        if hiddenGUID then redacted=true end
        local lines=r.Table(data.lines)
        if not lines then trace[#trace+1]="lines="..raw(data.lines); return nil,"lines_unavailable" end
        local rows={}
        for index=1,12 do
            local rawLine=lines[index]
            if not (issecretvalue and issecretvalue(rawLine)) and rawLine==nil then break end
            local line=r.Table(rawLine)
            local row={}
            rows[index]=row
            if line then
                trace[#trace+1]=index..": type="..raw(line.type).." left="..raw(line.leftText).." right="..raw(line.rightText)
                    .." args="..raw(line.args)
                row.text=cleanText(r.String(line.leftText))
                row.kind=r.Number(line.type,0)
                row.blocked=issecretvalue and (issecretvalue(line.type) or issecretvalue(line.leftText))
                if r.Plain(line.type)~=nil and row.kind==nil then row.blocked=true end
                -- A secret/missing field cannot become a blank separator.
                row.blank=(row.kind==1 or row.text~=nil and row.text=="")
            else trace[#trace+1]=index..": line="..raw(rawLine) end
        end
        if not identityOK then return nil,hiddenGUID and "identity_restricted" or "identity_mismatch" end
        local function nextRow(position)
            for index=position,#rows do if not rows[index].blank then return rows[index],index end end
        end
        local header,index=nextRow(1)
        local row,subtitleIndex=nextRow((index or 0)+1)
        if not row then return nil,"subtitle_unavailable" end
        if row.blocked then return nil,"text_or_type_restricted" end
        if row.kind==levelType or row.kind==unitType then return nil,"level_or_creature_type" end
        if row.kind~=nil and row.kind~=(types.None or 0) then return nil,"unsupported_line_type" end
        local text=row.text
        if not text or text=="" then return nil,"text_unavailable_or_restricted" end
        if text==npc.name or text==npc.faction or text==localizedFaction then return nil,"name_or_faction" end
        if not npc.name or not header or not header.text or header.blocked or header.text~=npc.name
            or header.kind==levelType or header.kind==unitType then
            return nil,"header_mismatch_or_restricted"
        end
        local bracketed=text:match("^<([^<>]+)>$")
        if bracketed then return bracketed,"accepted_brackets" end
        local following=nextRow(subtitleIndex+1)
        if following and (following.kind==levelType or following.kind==unitType) then return text,"accepted_plain" end
        return nil,"no_typed_level_boundary"
    end
    local function probe(fn,source,...)
        if type(fn)~="function" then decisions[#decisions+1]=source..": api_unavailable"; return nil end
        local data=r.Call(fn,...)
        local value,reason=inspect(data,source)
        trace[#trace+1]="decision="..reason
        decisions[#decisions+1]=source..": "..reason
        return value
    end
    local title=probe(type(C_TooltipInfo)=="table" and C_TooltipInfo.GetUnit,"npc","npc")
    if not title and npc.guid and type(UnitTokenFromGUID)=="function" then
        local rawToken=r.Call(UnitTokenFromGUID,npc.guid)
        local hidden=issecretvalue and issecretvalue(rawToken)
        local token=r.String(rawToken)
        if hidden then redacted=true; decisions[#decisions+1]="resolved_unit: token_restricted"
        elseif token and token~="npc" and r.String(r.Call(UnitGUID,token))==npc.guid then
            title=probe(type(C_TooltipInfo)=="table" and C_TooltipInfo.GetUnit,"resolved_unit",token)
        else decisions[#decisions+1]="resolved_unit: unavailable_or_identity_mismatch" end
    end
    if not title and npc.guid and GameTooltip and type(GameTooltip.GetPrimaryTooltipData)=="function" then
        local data=r.Table(r.Call(GameTooltip.GetPrimaryTooltipData,GameTooltip))
        local hidden=data and issecretvalue and issecretvalue(data.guid)
        if hidden then redacted=true; decisions[#decisions+1]="native_tooltip: identity_restricted"
        elseif data and r.String(data.guid)==npc.guid then
            local reason
            title,reason=inspect(data,"native_tooltip"); trace[#trace+1]="decision="..reason
            decisions[#decisions+1]="native_tooltip: "..reason
        else decisions[#decisions+1]="native_tooltip: unavailable_or_identity_mismatch" end
    end
    if not titleSeen[npc.creatureID] and titleCount<128 then
        titleSeen[npc.creatureID]=true; titleCount=titleCount+1
        addon.DiagnosticAPI.Record("interface","npc_title_probe",{message="result="..(title and "applied" or "omitted")
            .."\n"..table.concat(decisions,"; ").."\n"..table.concat(trace,"\n"),redacted=redacted or nil},
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

