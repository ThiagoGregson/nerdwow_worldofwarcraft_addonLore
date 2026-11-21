local _, addon = ...
local Fonts = {}
addon.FontAPI = Fonts
local BASE = "Interface\\AddOns\\NerdWow\\Fonts\\"
local TITLE, BODY = "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF"
local SAMPLE = "Áurea memória de Azeroth: Wimm, Vila Norte, 0123456789."
local INTERVAL, CHECKS = .1, 50
local files = {
    {name="Cinzel-Regular",fallback=TITLE}, {name="Cinzel-Bold",fallback=TITLE},
    {name="EBGaramond-Regular",fallback=BODY}, {name="EBGaramond-Italic",fallback=BODY},
}
local embedded, reported, profiles = {},{},{}
local applications = setmetatable({}, {__mode="k"})
local preloaded, frame, changed, probes, testGeneration = false,nil,{}, {},0
for _, file in ipairs(files) do file.path=BASE..file.name..".ttf"; embedded[file.name]=file end
local function restricted(value)
    if issecretvalue and issecretvalue(value) then error("restricted_font_result") end
    return value
end
local function normalized(path) return type(path)=="string" and path:gsub("/","\\"):lower() or "" end
local function positive(value) return type(value)=="number" and value>0 and value<math.huge end
function Fonts.Scale(percent)
    local _,height=GetPhysicalScreenSize()
    height=restricted(height)
    local effective=restricted(UIParent:GetEffectiveScale())
    if not positive(height) or not positive(effective) then error("layout_unavailable") end
    local value=addon.Typography.Build(height,effective/(768/height),percent)
    if not value then error("layout_unavailable") end
    return value
end
local function setFont(object,path,size,flags)
    -- EditBox requires a string even though FontString accepts absent flags.
    -- Keep this normalization at the only SetFont boundary, including probes.
    local ok,value=addon.DiagnosticAPI.Try(function() return restricted(object:SetFont(path,size,flags or ""))==true end)
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
    return string.format("font=%s; flags=\"%s\"; size=%g; success=%s%s",path,
        flags or "",size,tostring(success),flags==nil and "; requestedFlags=nil" or "")
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
local function fallback(object,file,size,job,reason)
    local success,fault=setFont(object,file.fallback,size,nil)
    local native,readFault=snapshot({object=object,path=file.fallback,size=size})
    local final,objectFault,objectSuccess
    if not native.applied then
        -- SetFontObject does not depend on this widget accepting SetFont.
        -- Inherit the Blizzard object; never mutate the shared global font.
        objectSuccess,objectFault=addon.DiagnosticAPI.Try(function() object:SetFontObject(GameFontNormal) end)
        final,readFault=snapshot({object=object,path=file.fallback,size=size})
        if not (type(final.path)=="string" and final.path~="" and positive(final.size)) then final=nil end
    end
    if not reported[file.name] then
        reported[file.name]=true
        local message=result(file.path,nil,size,job.success).."; fallback="..file.fallback
            .."; fallbackSuccess="..tostring(success)..observation(job.value).."; fallbackApplied="..tostring(native.applied)
            .."; reason="..(reason or "unconfirmed")
        if objectSuccess~=nil then
            message=message.."; fontObject=GameFontNormal; fontObjectSuccess="..tostring(objectSuccess)
                .."; recovered="..tostring(final~=nil)
            if final then message=message.."; finalFont="..final.path.."; finalSize="..tostring(final.size) end
        end
        addon.DiagnosticAPI.Record("interface",native.applied and "font_fallback" or "font_fallback_failed",
            detail(message,job.readFault or job.fault or readFault or fault or objectFault),{stage="font_apply"})
    end
    if not native.applied and not final then
        local failure=readFault or job.readFault or objectFault
        if failure then addon.DiagnosticAPI.Raise(failure,"font_unavailable") end
        error("font_unavailable")
    end
    return final and final.path or file.fallback
end
local RETRIES={1,2,4,8}
local function later(state,callback)
    if state.ticket or state.attempts>=#RETRIES or type(C_Timer)~="table" or type(C_Timer.After)~="function" then return end
    state.attempts=state.attempts+1
    local ticket={}; state.ticket=ticket
    C_Timer.After(RETRIES[state.attempts],function()
        if state.ticket~=ticket then return end
        state.ticket=nil; callback()
    end)
end
local start
start=function(file,state)
    if state.loaded then return end
    if state.job then state.job.cancelled=true end
    local function observed(job)
        if job.ready then state.loaded=true; state.ticket=nil; state.reason=nil end
        if job.done and not state.loaded then
            state.fallback=true
            later(state,function() start(file,state) end)
        end
        notify()
    end
    state.job=request(state.object,file.path,21,nil,true,observed,observed)
    if state.job.ready then state.loaded=true; state.ticket=nil; state.reason=nil end
end
local function profile(file)
    local state=profiles[file.name]
    if not state then
        state={object=invisible(),attempts=0}
        profiles[file.name]=state; start(file,state)
    end
    return state
end
function Fonts.Preload()
    if preloaded then return end
    preloaded=true
    for _,file in ipairs(files) do profile(file) end
end
function Fonts.Prepare(name,size)
    if not embedded[name] or not positive(size) then error("font_unavailable") end
    local state=profile(embedded[name])
    return state.loaded or state.fallback or false
end
function Fonts.Retry()
    for name,state in pairs(profiles) do
        if not state.loaded then
            state.attempts=0; state.ticket=nil
            if state.job.done then start(embedded[name],state) end
        end
    end
    for object,app in pairs(applications) do
        if app.native or app.failed then app.ticket=nil; applications[object]=nil end
    end
end
function Fonts.UseFallback(reason)
    for _,file in ipairs(files) do
        local state=profile(file)
        if not state.loaded then state.fallback=true; state.reason=reason or "preparation_deadline" end
    end
end
-- The singleton renderer replaces its callback instead of accumulating listeners.
function Fonts.Watch(callback,key) changed[key or "conversation"]=callback end
function Fonts.Apply(object,name,size)
    local file=embedded[name]
    if not file or not positive(size) then error("font_unavailable") end
    size=math.max(8,size)
    local state=profile(file)
    if not state.loaded and not state.fallback then return nil,false end
    local app=applications[object]
    if not app or app.file~=file or app.size~=size then
        if app then app.ticket=nil end
        app={file=file,size=size,attempts=0}; applications[object]=app
    end
    local function apply()
        local job=state.job
        app.attemptedLoaded=state.loaded
        if state.loaded then
            job={object=object,path=file.path,size=size}
            job.success,job.fault=setFont(object,file.path,size,nil)
            job.value,job.readFault=snapshot(job)
            if job.value.applied then
                app.path=file.path; app.native=false; app.failed=false; app.ticket=nil
                return
            end
        end
        app.native=true; app.failed=true
        app.path=fallback(object,file,size,job,state.reason or "region_unconfirmed")
        app.failed=false
        if state.loaded then
            later(app,function()
                if applications[object]~=app then return end
                -- Callback errors belong to the next safe layout, never the timer.
                local ok=addon.DiagnosticAPI.Try(apply)
                if not ok then app.failed=true; app.path=nil end
                notify()
            end)
        end
    end
    if not app.path or app.failed or app.native and state.loaded and not app.attemptedLoaded then apply() end
    return app.path,true
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
