local _, addon = ...
local Settings = { VERSION=1 }
addon.Settings = Settings

local definitions,order={},{}
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end
    return result
end
local function valid(spec,value)
    if type(value)~=spec.type then return false end
    if spec.type=="number" then
        if value~=value or value==math.huge or value==-math.huge then return false end
        if spec.min and value<spec.min or spec.max and (value>spec.max or spec.exclusiveMax and value==spec.max) then return false end
        if spec.step and math.abs((value-(spec.min or 0))/spec.step-math.floor((value-(spec.min or 0))/spec.step+.5))>.000001 then return false end
    elseif spec.type=="string" then
        if spec.maxLength and #value>spec.maxLength then return false end
    end
    if spec.values then
        local found=false
        for _,choice in ipairs(spec.values) do if choice.value==value then found=true end end
        if not found then return false end
    end
    return not spec.validate or spec.validate(value)==true
end
function Settings.Register(key,spec)
    if type(key)~="string" or not key:match("^[%a][%w_]*$") or type(spec)~="table" then return nil,"invalid_field" end
    if definitions[key] then return nil,"duplicate_field" end
    if spec.type~="boolean" and spec.type~="number" and spec.type~="string" then return nil,"invalid_field_type" end
    for _,field in ipairs({"min","max","step","maxLength"}) do
        local value=spec[field]
        if value~=nil and (type(value)~="number" or value~=value or math.abs(value)==math.huge) then return nil,"invalid_field_limits" end
    end
    if spec.min and spec.max and spec.min>spec.max or spec.step and spec.step<=0
        or spec.maxLength and (spec.maxLength<1 or spec.maxLength~=math.floor(spec.maxLength))
        or spec.validate~=nil and type(spec.validate)~="function" then return nil,"invalid_field_limits" end
    if spec.type~="number" and (spec.min~=nil or spec.max~=nil or spec.step~=nil)
        or spec.type~="string" and spec.maxLength~=nil
        or spec.exclusiveMax~=nil and type(spec.exclusiveMax)~="boolean" then return nil,"invalid_field_limits" end
    if spec.values then
        if type(spec.values)~="table" or #spec.values==0 then return nil,"invalid_field_values" end
        local seen={}
        for _,choice in ipairs(spec.values) do
            if type(choice)~="table" or type(choice.value)~=spec.type or type(choice.text)~="string"
                or type(choice.value)=="number" and (choice.value~=choice.value or math.abs(choice.value)==math.huge)
                or seen[choice.value] then return nil,"invalid_field_values" end
            seen[choice.value]=true
        end
    end
    if not valid(spec,spec.default) then return nil,"invalid_field_default" end
    definitions[key]=copy(spec); order[#order+1]=key
    return true
end
function Settings.Describe(key) return copy(definitions[key]) end
function Settings.List() return copy(order) end
function Settings.Validate(key,value)
    local spec=definitions[key]
    if not spec then return nil,"unknown_field" end
    if not valid(spec,value) then return nil,"invalid_setting" end
    return true
end
Settings.Register("schemaVersion",{type="number",default=Settings.VERSION,min=Settings.VERSION,max=Settings.VERSION,step=1})
function Settings.Open(saved)
    local root,repaired=saved,{}
    if type(root)~="table" then root={}; if saved~=nil then repaired[1]="root" end end
    for _,key in ipairs(order) do
        if not valid(definitions[key],root[key]) then
            if root[key]~=nil then repaired[#repaired+1]=key end
            root[key]=definitions[key].default
        end
    end
    local listeners={}
    local function notify(keys)
        if #keys>0 then for listener in pairs(listeners) do listener(copy(keys)) end end
    end
    local handle={}
    function handle.Read(key)
        local spec=definitions[key]
        if not spec then return nil,"unknown_field" end
        if root[key]==nil then root[key]=spec.default end
        return root[key]
    end
    function handle.Get()
        local result={}; for _,key in ipairs(order) do result[key]=handle.Read(key) end
        return result
    end
    function handle.Set(key,value)
        local ok,code=Settings.Validate(key,value)
        if not ok then return nil,code end
        local changed=handle.Read(key)~=value; root[key]=value
        if changed then notify({key}) end
        return true
    end
    function handle.Toggle(key)
        local spec=definitions[key]
        if not spec or spec.type~="boolean" then return nil,"invalid_toggle" end
        local value=not handle.Read(key); local ok,code=handle.Set(key,value)
        if not ok then return nil,code end
        return value
    end
    function handle.Reset(keys)
        if type(keys)~="table" then return nil,"invalid_fields" end
        local seen,count={},0
        for index,key in pairs(keys) do
            if type(index)~="number" or index<1 or index>#keys or index~=math.floor(index)
                or type(key)~="string" or not definitions[key] or seen[key] then return nil,"invalid_fields" end
            seen[key]=true; count=count+1
        end
        if count~=#keys then return nil,"invalid_fields" end
        local changed={}
        for _,key in ipairs(keys) do
            if handle.Read(key)~=definitions[key].default then changed[#changed+1]=key end
            root[key]=definitions[key].default
        end
        notify(changed); return true
    end
    function handle.Subscribe(callback)
        if type(callback)~="function" then return nil,"invalid_listener" end
        listeners[callback]=true; return function() listeners[callback]=nil end
    end
    -- Compatibility wrappers share the generic validation and mutation path.
    function handle.SetAngle(value)
        local ok=handle.Set("minimapAngle",value); if not ok then return nil,"invalid_angle" end; return true
    end
    function handle.ToggleHidden() return handle.Toggle("minimapHidden") end
    function handle.ToggleDialog() return handle.Toggle("dialogEnabled") end
    return handle,root,repaired
end
