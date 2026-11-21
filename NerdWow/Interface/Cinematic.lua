local _,addon=...
local Cinematic={DURATION=.65,RETURN_DURATION=.45,MODEL_TIMEOUT=1}
addon.Cinematic=Cinematic
local names={"test_cameraTargetFocusInteractEnable","test_cameraTargetFocusInteractStrengthPitch",
    "test_cameraTargetFocusInteractStrengthYaw","test_cameraOverShoulder","test_cameraHeadMovementStrength",
    "CameraKeepCharacterCentered","CameraReduceUnexpectedMovement"}
local animated={test_cameraTargetFocusInteractStrengthPitch=true,test_cameraTargetFocusInteractStrengthYaw=true,test_cameraOverShoulder=true}
local function copy(value)
    if type(value)~="table" then return value end
    local result={}; for key,item in pairs(value) do result[key]=copy(item) end; return result
end
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
function Cinematic.CVars() return copy(names) end
function Cinematic.Validate(record)
    if type(record)~="table" or record.version~=1 or type(record.characterKey)~="string"
        or not record.characterKey:match("^Player%-%w+%-%w+$") or #record.characterKey>128
        or not finite(record.zoom) or record.zoom<0 or record.zoom>1000 or type(record.cvars)~="table" then return false end
    local seen={}; for _,name in ipairs(names) do
        local value=record.cvars[name]
        if type(value)~="string" or #value>64 or not finite(tonumber(value)) then return false end
        seen[name]=true
    end
    for name in pairs(record.cvars) do if not seen[name] then return false end end
    return true
end
function Cinematic.Plan(preferences,context)
    local safe=preferences.dialogEnabled==true and context.combat==false and context.vehicle==false
        and context.taxi==false and context.cinematic==false
    return {camera=safe and preferences.cameraEnabled==true and context.creature==true,
        hide=safe and preferences.hideGameUI==true and context.hasUI==true,
        intensity=preferences.cameraIntensity or 3}
end
function Cinematic.Target(intensity,height,original)
    if not finite(intensity) or intensity<1 or intensity>5 or intensity~=math.floor(intensity)
        or not finite(height) or height<.3 or height>20 or not finite(original) or original<1.2 or original>1000 then return nil end
    local factors={2.8,2.25,1.75,1.35,1.05}
    return math.min(original,math.max(1.2,height*factors[intensity])),{
        test_cameraTargetFocusInteractEnable="1",test_cameraTargetFocusInteractStrengthPitch="1",
        test_cameraTargetFocusInteractStrengthYaw="1",test_cameraOverShoulder=tostring(.75+intensity*.15),
        test_cameraHeadMovementStrength="0",CameraKeepCharacterCentered="0",CameraReduceUnexpectedMovement="0"}
end
function Cinematic.New(p)
    local d={}
    local opened,blocked,plan,record,hud,waiting=false,false,nil,nil,false,0
    local motion,elapsed,from,to,returning=nil,0,nil,nil,false
    local hudAlpha,hudDirection,hudHeartbeat=1,nil,0
    local reported={}
    local function attempt(stage,fn,...)
        local ok,value=(p.Try or pcall)(fn,...)
        if not ok and not reported[stage] then reported[stage]=true; p.Diagnose(stage,value) end
        return ok,value
    end
    local function save(value) p.Save(value and copy(value)) end
    local function restoreCamera()
        if not record then return true end
        local ok=true
        for _,name in ipairs(names) do
            local restored=attempt("camera_restore_failed",p.SetCVar,name,record.cvars[name])
            ok=restored and ok
        end
        local zoomed=attempt("camera_restore_failed",p.Zoom,record.zoom); ok=zoomed and ok
        if ok then
            local verified,value=attempt("camera_restore_failed",function()
                for _,name in ipairs(names) do
                    if tonumber(p.ReadCVar(name))~=tonumber(record.cvars[name]) then error("camera_restore_unconfirmed:"..name) end
                end
                return math.abs(p.ReadZoom()-record.zoom)<.01
            end)
            if verified and value and attempt("camera_recovery_write_failed",save,nil) then record=nil; return true end
        end
        return false
    end
    local function restoreHUD()
        hudDirection=nil; hudAlpha=1
        if hud and attempt("hud_restore_failed",p.HUD,1,true) then hud=false end
    end
    function d.Recover()
        if record then return restoreCamera() end
        local loaded,value=attempt("camera_recovery_invalid",p.Load)
        if not loaded then return false end
        if value==nil then return true end
        if not Cinematic.Validate(value) then
            attempt("camera_recovery_invalid",function() error("camera_recovery_invalid") end); return false
        end
        if value.characterKey~=p.CharacterKey() then return false end
        record=copy(value); returning=true; elapsed=0; motion="verify"
        if restoreCamera() then motion=nil; returning=false; return true end
        return false
    end
    local function startCamera(context)
        local ok,snapshot=attempt("camera_capture_failed",p.CaptureCamera)
        if not ok then return end
        if not Cinematic.Validate(snapshot) then
            attempt("camera_capture_failed",function() error("invalid_camera_snapshot") end); return
        end
        local zoom,target=Cinematic.Target(plan.intensity,context.height,snapshot.zoom)
        if not zoom then return end
        -- Publish the complete recovery before the first setter, even a setter that fails.
        record=copy(snapshot)
        if not attempt("camera_recovery_write_failed",save,record) then record=nil; return end
        from=copy(record.cvars); to=target
        from.test_cameraTargetFocusInteractStrengthPitch="0"; from.test_cameraTargetFocusInteractStrengthYaw="0"
        local applied=attempt("camera_apply_failed",function()
            p.SetCVar("test_cameraTargetFocusInteractStrengthPitch","0")
            p.SetCVar("test_cameraTargetFocusInteractStrengthYaw","0")
            for _,name in ipairs(names) do if not animated[name] then p.SetCVar(name,target[name]) end end
            p.Zoom(zoom)
        end)
        if not applied then returning=true; motion="verify"; elapsed=0; restoreCamera(); return end
        motion="enter"; elapsed=0; returning=false
    end
    function d.Enter()
        if opened then return end
        if motion or record then d.Close(true) end
        opened=true; blocked=false
        local ok,context=attempt("cinematic_context_failed",p.Context)
        if not ok then blocked=true; return end
        plan=Cinematic.Plan(p.Preferences(),context)
        if plan.hide then
            local captured=attempt("hud_capture_failed",p.CaptureHUD)
            if captured then hud=true; hudAlpha=1; hudDirection=-1 end
        end
        if plan.camera and d.Recover() then
            if context.height then startCamera(context) else waiting=Cinematic.MODEL_TIMEOUT end
        end
    end
    function d.Close(immediate)
        opened=false; blocked=true; waiting=0
        if immediate then
            motion=nil; restoreHUD()
            if not restoreCamera() then motion="verify"; elapsed=0; returning=true end
            return
        end
        if not record and not hud then motion=nil; return end
        if hud then hudDirection=1 end
        local captured,value=attempt("camera_restore_failed",function()
            local values={}
            if record then
                for name in pairs(animated) do values[name]=p.ReadCVar(name) end
                p.Zoom(record.zoom)
            end
            return values
        end)
        if not captured then d.Close(true); return end
        from=value; to=record and record.cvars; motion="leave"; elapsed=0; returning=true
    end
    function d.Suspend() blocked=true; d.Close(true); opened=true end
    function d.Tick(delta)
        if not finite(delta) or delta<=0 then return end
        if opened and not blocked then
            local ok,context=attempt("cinematic_context_failed",p.Context)
            if not ok or context.combat or context.vehicle or context.taxi or context.cinematic then d.Suspend(); return end
            if waiting>0 then
                waiting=math.max(0,waiting-delta)
                if context.height then waiting=0; startCamera(context) end
            end
        end
        if hud and hudDirection then
            hudAlpha=math.max(0,math.min(1,hudAlpha+hudDirection*delta/.25))
            if not attempt("hud_transition_failed",p.HUD,hudAlpha,false) then d.Close(true); return end
            if hudAlpha==0 or hudAlpha==1 then hudDirection=nil end
        elseif hud and opened and not blocked and hudAlpha==0 then
            hudHeartbeat=hudHeartbeat+delta
            if hudHeartbeat>=.1 then
                hudHeartbeat=0
                if not attempt("hud_transition_failed",p.HUD,0,false) then d.Close(true); return end
            end
        end
        if not motion then return end
        elapsed=elapsed+delta
        if motion=="verify" then
            if restoreCamera() or elapsed>=2 then motion=nil; returning=false end
            return
        end
        local duration=motion=="enter" and Cinematic.DURATION or Cinematic.RETURN_DURATION
        local fraction=math.min(1,elapsed/duration); local eased=1-(1-fraction)^3
        if record and from and to then
            local ok=attempt("camera_transition_failed",function()
                for name in pairs(animated) do p.SetCVar(name,tostring(tonumber(from[name])+(tonumber(to[name])-tonumber(from[name]))*eased)) end
            end)
            if not ok then d.Close(true); return end
        end
        if fraction==1 then
            if returning then
                restoreHUD()
                if not restoreCamera() then motion="verify"; elapsed=0; return end
            end
            motion=nil; returning=false
        end
    end
    function d.IsUpdating() return motion~=nil or waiting>0 or hudDirection~=nil or hud and opened and not blocked end
    return d
end
