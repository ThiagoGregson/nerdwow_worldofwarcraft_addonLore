local _, addon = ...
local Fonts = {}
addon.FontAPI = Fonts
local BASE = "Interface\\AddOns\\NerdWow\\Fonts\\"
local TITLE, BODY = "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF"
local SAMPLE = "Áurea memória de Azeroth: Wimm, Vila Norte, 0123456789."
local INTERVAL, CHECKS, MAX_PROFILES = .1, 50, 128
local files = {
    {name="Cinzel-Regular",fallback=TITLE}, {name="Cinzel-Bold",fallback=TITLE},
    {name="EBGaramond-Regular",fallback=BODY}, {name="EBGaramond-Italic",fallback=BODY},
}
local embedded, reported, profiles, order = {},{},{},{}
local readyFiles={}
local applications = setmetatable({}, {__mode="k"})
local preloaded, frame, changed, probes, testGeneration = false,nil,{}, {},0
for _, file in ipairs(files) do file.path=BASE..file.name..".ttf"; embedded[file.name]=file end
local function restricted(value)
    if issecretvalue and issecretvalue(value) then error("restricted_font_result") end
    return value
end
local function normalized(path) return type(path)=="string" and path:gsub("/","\\"):lower() or "" end
local function positive(value) return type(value)=="number" and value>0 and value<math.huge end
local function setFont(object,path,size,flags)
    local ok,value=addon.DiagnosticAPI.Try(function() return restricted(object:SetFont(path,size,flags))==true end)
    if not ok then return false,value end
    return value
end
local function snapshot(job)
    local ok,value=addon.DiagnosticAPI.Try(function()
        local path,size,flags=job.object:GetFont()
        restricted(path); restricted(size); restricted(flags)
        local width,height
        if job.metrics then
            width=restricted(job.object:GetUnboundedStringWidth())
            height=restricted(job.object:GetStringHeight())
        end
        return {path=type(path)=="string" and path or nil,size=type(size)=="number" and size or nil,
            flags=type(flags)=="string" and flags or nil,width=width,height=height,
            applied=normalized(path)==normalized(job.path) and positive(size) and math.abs(size-job.size)<.01
                and (flags==nil or type(flags)=="string")
                and (flags or "")==(job.flags or "")}
    end)
    if not ok then return {applied=false},value end
    return value
end
local function result(path,flags,size,success)
    return string.format("font=%s; flags=%s; size=%g; success=%s",path,
        flags==nil and "nil" or '"'..flags..'"',size,tostring(success))
end
local function observation(value)
    return string.format("; actual=%s; actualSize=%s; actualFlags=%s; applied=%s; width=%s; height=%s",
        value.path or "nil",tostring(value.size),value.flags or "nil",tostring(value.applied),
        tostring(value.width),tostring(value.height))
end
local function detail(message,fault)
    return {message=message..(fault and fault.message and "; error="..fault.message or ""),
        stack=fault and fault.stack,redacted=fault and fault.redacted}
end
local function notify()
    if type(C_Timer)=="table" and type(C_Timer.After)=="function" then
        for _,callback in pairs(changed) do callback() end
    end
end
local function invisible()
    if not frame then
        frame=CreateFrame("Frame",nil,UIParent)
        frame:SetSize(1,1); frame:SetPoint("TOPLEFT",UIParent,"TOPLEFT",0,0)
        frame:SetAlpha(0); frame:EnableMouse(false)
    end
    local object=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    object:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0); object:SetSize(100000,1000)
    object:SetWordWrap(false); object:SetNonSpaceWrap(false); object:SetText(SAMPLE)
    return object
end
-- Fixed sample probes observe metric changes independently of the typewriter text.
local function request(object,path,size,flags,metrics,onChange,onDone,trusted)
    local after=type(C_Timer)=="table" and type(C_Timer.After)=="function" and C_Timer.After
    local job={object=object,path=path,size=size,flags=flags,metrics=metrics,ticks=0,stable=0}
    job.success,job.fault=setFont(object,path,size,flags)
    job.value,job.readFault=snapshot(job)
    local function valid(value)
        return value.applied and (not metrics or (positive(value.width) and positive(value.height)))
    end
    job.ready=(job.success or trusted) and valid(job.value)
    local function check()
        if job.cancelled then return end
        job.ticks=job.ticks+1
        local value,fault=snapshot(job)
        job.readFault=fault
        local same=value.applied==job.value.applied and value.path==job.value.path and value.size==job.value.size
            and value.flags==job.value.flags and value.width==job.value.width and value.height==job.value.height
        job.stable=valid(value) and (same and job.stable+1 or 0) or 0
        local ready=valid(value) and job.stable>=1
        local update=ready and not job.ready
        job.value,job.ready=value,ready
        if update and onChange then onChange(job) end
        if not metrics and ready then job.done=true; return end
        if job.ticks<CHECKS then after(INTERVAL,check)
        else
            job.done=true
            if onDone then onDone(job) end
        end
    end
    if after then after(0,check)
    else
        job.done=true; job.ready=job.value.applied
        if onDone then onDone(job) end
    end
    return job
end
local function fallback(job,file)
    -- A matching GetFont is never overridden just because SetFont returned false.
    if job.value.applied or job.readFault then return end
    local success,fault=setFont(job.object,file.fallback,job.size,nil)
    local native=snapshot({object=job.object,path=file.fallback,size=job.size,metrics=true})
    job.selected=file.fallback
    job.ready=native.applied and positive(native.width) and positive(native.height)
    if not reported[file.name] then
        reported[file.name]=true
        local message=result(file.path,nil,job.size,job.success).."; fallback="..file.fallback
            .."; fallbackSuccess="..tostring(success)..observation(job.value).."; fallbackApplied="..tostring(native.applied)
        addon.DiagnosticAPI.Record("interface",native.applied and "font_fallback" or "font_fallback_failed",
            detail(message,job.fault or fault),{stage="font_apply"})
    end
end
local function profile(file,size)
    local key=file.name..":"..string.format("%.9g",size)
    local job=profiles[key]
    if job then
        if job.ready and job.value.applied then readyFiles[file.path]=true end
        return job
    end
    local object
    if #order>=MAX_PROFILES then
        for index,oldKey in ipairs(order) do
            if profiles[oldKey].done then
                object=profiles[oldKey].object; profiles[oldKey].cancelled=true; profiles[oldKey]=nil
                table.remove(order,index); break
            end
        end
        if not object then error("font_unavailable") end
    end
    object=object or invisible()
    object:SetText(SAMPLE)
    job=request(object,file.path,size,nil,true,function(value)
        if value.ready and value.value.applied then readyFiles[file.path]=true end
        notify()
    end,function(value)
        if value.ready and value.value.applied then readyFiles[file.path]=true end
        if not value.ready then fallback(value,file); notify() end
    end,readyFiles[file.path])
    if job.ready and job.value.applied then readyFiles[file.path]=true end
    profiles[key]=job; order[#order+1]=key
    return job
end
function Fonts.Preload()
    if preloaded then return end
    preloaded=true
    for _,file in ipairs(files) do profile(file,21) end
end
function Fonts.Prepare(name,size)
    if not embedded[name] or not positive(size) then error("font_unavailable") end
    return profile(embedded[name],math.max(8,size)).ready
end
function Fonts.Retry()
    -- A new conversation may retry an unavailable asset; no permanent rejection cache.
    for key,job in pairs(profiles) do
        if job.done and (job.selected or not job.ready) then
            job.cancelled=true; job.object:SetText(SAMPLE)
            local file=embedded[key:match("^(.-):")]
            profiles[key]=request(job.object,job.path,job.size,nil,true,notify,function(value)
                if not value.ready then fallback(value,file); notify() end
            end)
        end
    end
end
-- The singleton renderer replaces its callback instead of accumulating listeners.
function Fonts.Watch(callback,key) changed[key or "conversation"]=callback end
function Fonts.Apply(object,name,size)
    local file=embedded[name]
    if not file or not positive(size) then error("font_unavailable") end
    size=math.max(8,size)
    local job=profile(file,size)
    if not job.ready then
        if job.done then
            if job.readFault then addon.DiagnosticAPI.Raise(job.readFault,"font_unavailable") end
            error("font_unavailable")
        end
        return nil,false
    end
    local path=job.selected or file.path
    local applied=applications[object]
    if not applied or applied.path~=path or applied.size~=size then
        if applied then applied.cancelled=true end
        applied=request(object,path,size,nil,false,notify,notify)
        -- The sample has already settled; matching identity on this region is sufficient.
        if applied.value.applied then applied.ready=true end
        applications[object]=applied
    end
    if applied.ready then return path,true end
    if applied.done then
        if applied.readFault then addon.DiagnosticAPI.Raise(applied.readFault,"font_unavailable") end
        error("font_unavailable")
    end
    return nil,false
end
function Fonts.Test(report)
    testGeneration=testGeneration+1
    local token=testGeneration
    local controls={}
    for _,file in ipairs(files) do controls[#controls+1]=file end
    controls[#controls+1]={name="Friz Quadrata (nativa)",path=TITLE}
    controls[#controls+1]={name="Arial Narrow (nativa)",path=BODY}
    local flags={{},{value=""},{value="OUTLINE"}}
    local size,pending=21,18
    local outcomes,loaded={},{}
    report(addon.Text.fontsHeader)
    local function finish()
        if token~=testGeneration then return end
        pending=pending-1
        if pending>0 then return end
        report(addon.Text.fontsLoadedHeader)
        for index,file in ipairs(controls) do
            report(string.format(addon.Text.fontsLine,file.name,size,loaded[index][1],loaded[index][2],loaded[index][3]))
        end
    end
    for index,file in ipairs(controls) do
        outcomes[index]={}; loaded[index]={}
        for flagIndex,flag in ipairs(flags) do
            local probeIndex=(index-1)*3+flagIndex
            local old=probes[probeIndex]
            if old then old.cancelled=true end
            local object=old and old.object or invisible()
            -- Do not inherit an earlier successful identity when repeating a probe.
            object:SetFontObject(GameFontNormal)
            object:SetText(SAMPLE)
            local job=request(object,file.path,size,flag.value,true,nil,function(value)
                if token~=testGeneration then return end
                local state=value.ready and addon.Text.fontsApplied or value.value.applied and addon.Text.fontsNoMetrics
                    or value.readFault and addon.Text.fontsError or addon.Text.fontsNotApplied
                loaded[index][flagIndex]=state
                addon.DiagnosticAPI.Record("interface","font_test_loaded",
                    detail(result(file.path,flag.value,size,value.success).."; phase=loaded; checks="..value.ticks
                        .."; ready="..tostring(value.ready)..observation(value.value),value.fault or value.readFault),
                    {gameEvent="COMMAND_FONTES",stage="font_probe_loaded"})
                finish()
            end)
            probes[probeIndex]=job
            outcomes[index][flagIndex]=job.success and addon.Text.fontsSuccess or job.fault and addon.Text.fontsError or addon.Text.fontsPending
            addon.DiagnosticAPI.Record("interface","font_test",
                detail(result(file.path,flag.value,size,job.success).."; phase=immediate"..observation(job.value),job.fault or job.readFault),
                {gameEvent="COMMAND_FONTES",stage="font_probe"})
        end
        report(string.format(addon.Text.fontsLine,file.name,size,outcomes[index][1],outcomes[index][2],outcomes[index][3]))
    end
end
