local _,addon=...
local Book={}
addon.ConfigurationBook=Book
local roman={{1000,"M"},{900,"CM"},{500,"D"},{400,"CD"},{100,"C"},{90,"XC"},{50,"L"},{40,"XL"},{10,"X"},{9,"IX"},{5,"V"},{4,"IV"},{1,"I"}}
function Book.Roman(number)
    local result={}
    for _,pair in ipairs(roman) do while number>=pair[1] do result[#result+1]=pair[2]; number=number-pair[1] end end
    return table.concat(result)
end
function Book.Layout(width,height)
    if type(width)~="number" or type(height)~="number" or width<=0 or height<=0
        or width~=width or height~=height or width==math.huge or height==math.huge then return nil end
    local s=math.min(width/1280,height/720)
    local w,h=math.min(width*.92,1020*s),math.min(height*.86,600*s)
    return {scale=s,width=w,height=h,left=(w-28*s)*.34,right=(w-28*s)*.66,padding=14*s}
end
function Book.New(options)
    local r,settings=options.Registry,options.Settings
    local chapter=r.Chapters()[1]; chapter=chapter and chapter.id
    local book={}
    function book.Select(id)
        for _,spec in ipairs(r.Chapters()) do if spec.id==id then chapter=id; return true end end
        return nil,"unknown_chapter"
    end
    function book.Move(delta)
        local chapters=r.Chapters()
        if #chapters==0 then return end
        for index,spec in ipairs(chapters) do
            if spec.id==chapter then chapter=chapters[(index-1+delta)%#chapters+1].id; return chapter end
        end
    end
    local function enabled(spec)
        return not spec.soon and not spec.readOnly and (not spec.protected or options.CanAct())
    end
    function book.Snapshot()
        local result={chapters=r.Chapters(),chapter=chapter,options={}}
        for index,spec in ipairs(result.chapters) do spec.roman=Book.Roman(index); if spec.id==chapter then result.header=spec end end
        for _,spec in ipairs(r.Options(chapter)) do
            if not spec.visibleWhen or options.IsVisible(spec.visibleWhen) then
                spec.enabled=enabled(spec)
                spec.definition=spec.field and r.Describe(spec.field) or {min=spec.min,max=spec.max,step=spec.step}
                if spec.field then spec.value=settings.Read(spec.field)
                elseif spec.valueKey then spec.value=options.ReadInfo(spec.valueKey) end
                if spec.inverted then spec.value=not spec.value end
                result.options[#result.options+1]=spec
            end
        end
        return result
    end
    function book.Write(id,value)
        local spec=r.Option(chapter,id)
        if not spec or not spec.field or not enabled(spec) then return nil,"option_disabled" end
        if spec.inverted then if type(value)~="boolean" then return nil,"invalid_setting" end; value=not value end
        return settings.Set(spec.field,value)
    end
    function book.Activate(id)
        local spec=r.Option(chapter,id)
        if not spec or spec.kind~="action" or not enabled(spec) then return nil,"option_disabled" end
        return options.Action(spec.action)
    end
    function book.RequestReset() options.ConfirmReset(function() return settings.Reset(r.Fields()) end) end
    return book
end
