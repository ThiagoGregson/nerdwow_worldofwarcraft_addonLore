local addonName, addon = ...
local API = {}
addon.DiagnosticAPI = API
local sink, queued=nil,{}
local captured=setmetatable({},{__mode="k"})
local function plain(value)
    if type(issecretvalue)=="function" then
        local ok,secret=pcall(issecretvalue,value)
        if not ok or secret then return nil,true end
    end
    return value,false
end
local function field(input,key)
    input=plain(input)
    if type(input)~="table" then return nil end
    local ok,value=pcall(function() return input[key] end)
    if not ok then return nil end
    return plain(value)
end
local function text(value,limit)
    local redacted
    value,redacted=plain(value)
    if type(value)~="string" then return nil,false,redacted end
    local truncated=#value>limit
    if truncated then
        local endAt=limit
        while endAt>0 and value:byte(endAt+1)>=128 and value:byte(endAt+1)<192 do endAt=endAt-1 end
        value=value:sub(1,endAt)
    end
    return value,truncated,redacted
end
local function number(value,minimum)
    value=plain(value)
    if type(value)=="number" and value>=minimum and value<=9007199254740991 and value==math.floor(value) then return value end
end
local function clock()
    if type(GetServerTime)=="function" then
        local ok,value=pcall(GetServerTime)
        if ok and number(value,1) then return number(value,1) end
    end
    if type(time)=="function" then local ok,value=pcall(time); if ok then return number(value,1) end end
end
function API.Capture(err)
    local accessible=plain(err)
    if type(accessible)=="table" and captured[accessible] then return accessible end
    local message,truncated,redacted=text(err,2048)
    if not message then redacted=true end
    local stack,stackTruncated,stackRedacted
    if type(debugstack)=="function" then
        local ok,value=pcall(debugstack,2,16,12)
        if ok then stack,stackTruncated,stackRedacted=text(value,8192) end
    end
    local fault={message=message,stack=stack,redacted=redacted or stackRedacted or nil,
        messageTruncated=truncated or nil,stackTruncated=stackTruncated or nil}
    captured[fault]=true
    return fault
end
-- Somente pacotes produzidos por Capture podem atravessar uma segunda barreira.
function API.Raise(fault,code)
    fault=plain(fault)
    if type(fault)~="table" or not captured[fault] then error("invalid_diagnostic_fault") end
    fault.code=text(code,96)
    error(fault,0)
end
function API.Try(fn,...)
    local args,count={...},select("#",...)
    return xpcall(function() return fn(unpack(args,1,count)) end,API.Capture)
end
function API.Context(input,model)
    local result={}
    for _, name in ipairs({"gameEvent","moment","captureType","field","stage"}) do
        result[name]=text(field(input,name),name=="field" and 192 or name=="moment" and 16 or name=="stage" and 64 or 96)
    end
    result.creatureID=number(field(input,"creatureID"),1)
    for _, name in ipairs({"viewportWidth","viewportHeight","frameWidth","frameHeight"}) do
        local value=field(input,name)
        if type(value)=="number" and value>=0 and value<=9007199254740991 and value==value then result[name]=value end
    end
    if not result.moment then result.moment=text(field(model,"moment"),16) end
    if not result.creatureID then result.creatureID=number(field(field(model,"npc"),"creatureID"),1) end
    return result
end
function API.Dimensions(parent,frame)
    local result={}
    for _, spec in ipairs({{parent,"viewport"},{frame,"frame"}}) do
        for _, axis in ipairs({"Width","Height"}) do
            local ok,value=pcall(function() return spec[1]["Get"..axis](spec[1]) end)
            if ok then result[spec[2]..axis]=plain(value) end
        end
    end
    return API.Context(result)
end
function API.Code(fault)
    local code=text(field(fault,"code"),96)
    if code then return code end
    local message=type(plain(fault))=="table" and field(fault,"message") or plain(fault)
    message=text(message,2048)
    if message then
        for _, code in ipairs({"layout_unavailable","font_unavailable","native_frame_restricted","native_frame_unavailable",
            "native_restore_failed","interaction_unavailable","defer_unavailable","quest_native_required","quest_state_unavailable"}) do
            if message:find(code,1,true) then return code end
        end
    end
    return "interface_error"
end
function API.Record(category,code,detail,context,model)
    category=plain(category)
    if category~="interface" and category~="capture" then return end
    local safeCode,_,hidden=text(code,96)
    if safeCode=="duplicate_location" or safeCode=="duplicate_quest" or safeCode=="duplicate_gossip" then return end
    local message,messageTruncated,messageRedacted=text(field(detail,"message"),2048)
    local stack,stackTruncated,stackRedacted=text(field(detail,"stack"),8192)
    local version
    if type(C_AddOns)=="table" and type(C_AddOns.GetAddOnMetadata)=="function" then
        local ok,value=pcall(C_AddOns.GetAddOnMetadata,addonName,"Version")
        if ok then version=text(value,64) end
    end
    local entry={category=category,code=safeCode and safeCode~="" and safeCode or "unknown_error",
        message=message,stack=stack,timestamp=clock(),version=version,context=API.Context(context,model),
        redacted=hidden or messageRedacted or stackRedacted or field(detail,"redacted")==true or nil,
        messageTruncated=messageTruncated or field(detail,"messageTruncated")==true or nil,
        stackTruncated=stackTruncated or field(detail,"stackTruncated")==true or nil}
    if sink then return sink(entry) end
    if #queued==50 then for i=1,49 do queued[i]=queued[i+1] end; queued[50]=nil end
    queued[#queued+1]=entry
end
function API.Bind(callback)
    sink=callback
    local pending=queued; queued={}
    if sink then for _, entry in ipairs(pending) do sink(entry) end end
end
function API.ChatText(value)
    value=text(value,160) or ""
    return value:gsub("[\r\n\t]"," "):gsub("|","||")
end
