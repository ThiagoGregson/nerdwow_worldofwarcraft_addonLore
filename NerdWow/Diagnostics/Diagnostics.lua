local _, addon = ...
local Diagnostics = { VERSION = 1, MAX_ENTRIES = 50, MAX_COUNT = 9007199254740991 }
addon.Diagnostics = Diagnostics
local function integer(value, minimum)
    return type(value) == "number" and value >= minimum and value <= Diagnostics.MAX_COUNT
        and value == math.floor(value)
end
local contextRules = { gameEvent=96, moment=16, creatureID=true, captureType=96, field=192, stage=64,
    viewportWidth=false, viewportHeight=false, frameWidth=false, frameHeight=false }
local limits = { code=96, message=2048, stack=8192, version=64 }
local function copyEntry(input, stored)
    if type(input) ~= "table" or (input.category ~= "interface" and input.category ~= "capture") then return nil end
    local result = { category=input.category, count=stored and input.count or 1, context={} }
    if not integer(result.count,1) then return nil end
    for field, limit in pairs(limits) do
        local value=input[field]
        if value ~= nil then
            if type(value) ~= "string" or #value > limit or (field=="code" and value=="") then return nil end
            result[field]=value
        elseif field=="code" then return nil end
    end
    for _, field in ipairs({"timestamp","lastTimestamp"}) do
        if input[field] ~= nil then
            if not integer(input[field],1) then return nil end
            result[field]=input[field]
        end
    end
    for _, field in ipairs({"redacted","messageTruncated","stackTruncated"}) do
        if input[field] ~= nil then
            if type(input[field]) ~= "boolean" then return nil end
            result[field]=input[field]
        end
    end
    if input.context ~= nil then
        if type(input.context) ~= "table" then return nil end
        for field, rule in pairs(contextRules) do
            local value=input.context[field]
            if value ~= nil then
                if type(rule)=="number" then
                    if type(value) ~= "string" or #value > rule then return nil end
                elseif rule then
                    if not integer(value,1) then return nil end
                elseif type(value)~="number" or value<0 or value>Diagnostics.MAX_COUNT or value~=value then return nil end
                result.context[field]=value
            end
        end
    end
    return result
end
local function equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a==b end
    for key,value in pairs(a) do if not equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end
local function identity(entry)
    local value=copyEntry(entry,true)
    value.count,value.timestamp,value.lastTimestamp=nil,nil,nil
    return value
end
function Diagnostics.Open(saved)
    local root=saved
    if root==nil then root={schemaVersion=Diagnostics.VERSION,entries={}} end
    if type(root)~="table" then return nil,saved,"invalid_diagnostics" end
    if root.schemaVersion~=Diagnostics.VERSION then return nil,saved,"unsupported_diagnostics" end
    if type(root.entries)~="table" then return nil,saved,"invalid_diagnostics" end
    local count,maximum=0,0
    for index in pairs(root.entries) do
        if not integer(index,1) or index>Diagnostics.MAX_ENTRIES then return nil,saved,"invalid_diagnostics" end
        count,maximum=count+1,math.max(maximum,index)
    end
    if count~=maximum then return nil,saved,"invalid_diagnostics" end
    for index=1,count do if not copyEntry(root.entries[index],true) then return nil,saved,"invalid_diagnostics" end end
    local handle={}
    function handle.Append(input)
        local entry=copyEntry(input,false)
        if not entry then return nil,"invalid_diagnostic" end
        entry.lastTimestamp=entry.timestamp
        local last=root.entries[#root.entries]
        if last and equal(identity(last),identity(entry)) then
            last.count=math.min(Diagnostics.MAX_COUNT,last.count+1)
            if entry.timestamp then last.lastTimestamp=entry.timestamp end
            return true,"repeated_diagnostic"
        end
        if #root.entries==Diagnostics.MAX_ENTRIES then
            for index=1,Diagnostics.MAX_ENTRIES-1 do root.entries[index]=root.entries[index+1] end
            root.entries[Diagnostics.MAX_ENTRIES]=nil
        end
        root.entries[#root.entries+1]=entry
        return true
    end
    function handle.Recent(limit)
        if not integer(limit,1) then limit=5 end
        limit=math.min(limit,Diagnostics.MAX_ENTRIES)
        local result={}
        for index=#root.entries,math.max(1,#root.entries-limit+1),-1 do result[#result+1]=copyEntry(root.entries[index],true) end
        return result
    end
    function handle.GetStatus() return {total=#root.entries} end
    return handle,root
end
