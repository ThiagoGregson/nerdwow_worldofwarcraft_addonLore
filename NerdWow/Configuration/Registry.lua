local _,addon=...
local Registry={}
addon.ConfigurationRegistry=Registry
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for k,v in pairs(value) do result[k]=copy(v) end; return result
end
local function identifier(value) return type(value)=="string" and value:match("^[%a][%w_.-]*$")~=nil end
local function ordered(map)
    local result={}; for _,value in pairs(map) do result[#result+1]=copy(value) end
    table.sort(result,function(a,b) if a.order~=b.order then return a.order<b.order end; return a.id<b.id end)
    return result
end
local kinds={switch="boolean",slider="number",select="select",text="string",action=true,info=true,indicator=true}
function Registry.New(schema)
    local chapters,options,actions={},{},{}
    local r={}
    function r.RegisterAction(id,callback)
        if not identifier(id) or type(callback)~="function" then return nil,"invalid_action" end
        if actions[id] then return nil,"duplicate_action" end
        actions[id]=callback; return true
    end
    function r.RunAction(id,services)
        if not actions[id] then return nil,"unknown_action" end
        return actions[id](services)
    end
    function r.RegisterChapter(spec)
        if type(spec)~="table" or not identifier(spec.id) or type(spec.title)~="string" or spec.title==""
            or type(spec.description)~="string" or type(spec.order)~="number" or spec.order~=spec.order
            or math.abs(spec.order)==math.huge or spec.soon~=nil and type(spec.soon)~="boolean" then return nil,"invalid_chapter" end
        if chapters[spec.id] then return nil,"duplicate_chapter" end
        chapters[spec.id]=copy(spec); options[spec.id]={}; return true
    end
    function r.RegisterOption(chapter,spec)
        if not chapters[chapter] then return nil,"unknown_chapter" end
        if type(spec)~="table" or not identifier(spec.id) or not kinds[spec.kind] or type(spec.title)~="string"
            or type(spec.order)~="number" or spec.order~=spec.order or math.abs(spec.order)==math.huge
            or spec.soon~=nil and type(spec.soon)~="boolean" or spec.readOnly~=nil and type(spec.readOnly)~="boolean" then return nil,"invalid_option" end
        if spec.description~=nil and type(spec.description)~="string" or spec.inverted~=nil and type(spec.inverted)~="boolean"
            or spec.protected~=nil and type(spec.protected)~="boolean"
            or spec.visibleWhen~=nil and not identifier(spec.visibleWhen) then return nil,"invalid_option" end
        if options[chapter][spec.id] then return nil,"duplicate_option" end
        local soon=spec.soon or chapters[chapter].soon
        if not soon and not spec.field and kinds[spec.kind]~=true and not spec.readOnly then return nil,"option_binding_missing" end
        if spec.field then
            local field=schema.Describe(spec.field)
            if not field then return nil,"unknown_field" end
            if spec.kind~="select" and kinds[spec.kind]~=true and field.type~=kinds[spec.kind] then return nil,"option_field_type" end
            if spec.kind=="slider" and (not field.min or not field.max or not field.step)
                or spec.kind=="select" and not field.values then return nil,"option_field_limits" end
        elseif not soon and not spec.valueKey and spec.value==nil and spec.kind~="action" then return nil,"option_binding_missing" end
        if spec.kind=="action" and not identifier(spec.action) then return nil,"option_action_missing" end
        if spec.kind=="action" and not soon and not actions[spec.action] then return nil,"unknown_action" end
        if spec.valueKey and not identifier(spec.valueKey) then return nil,"invalid_value_key" end
        if spec.field and (spec.action or spec.valueKey) then return nil,"option_binding_conflict" end
        if spec.kind~="action" and spec.action then return nil,"option_binding_conflict" end
        if spec.inverted and spec.kind~="switch" then return nil,"option_field_type" end
        local value=copy(spec); value.soon=soon or false
        value.readOnly=value.readOnly or value.kind=="info" or value.kind=="indicator"
        options[chapter][spec.id]=value; return true
    end
    function r.Chapters() return ordered(chapters) end
    function r.Options(chapter) return options[chapter] and ordered(options[chapter]) or {} end
    function r.Option(chapter,id) return options[chapter] and copy(options[chapter][id]) end
    function r.Fields()
        local result,seen={},{}
        for _,chapter in ipairs(r.Chapters()) do for _,option in ipairs(r.Options(chapter.id)) do
            if option.field and not option.soon and not option.readOnly and not seen[option.field] then
                result[#result+1]=option.field; seen[option.field]=true
            end
        end end
        return result
    end
    function r.Describe(field) return schema.Describe(field) end
    return r
end
