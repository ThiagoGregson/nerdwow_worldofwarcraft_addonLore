local _,addon=...
local Integration={Events={"PLAYER_LOGOUT","UNIT_ENTERED_VEHICLE","PLAYER_CONTROL_LOST","CINEMATIC_START","PLAY_MOVIE"}}
addon.CinematicIntegration=Integration
local hudNames={"MainActionBar","MainMenuBar","MultiBarBottomLeft","MultiBarBottomRight","MultiBarLeft","MultiBarRight",
    "MultiBar5","MultiBar6","MultiBar7","PetActionBar","StanceBar","PossessActionBar","MicroMenu","MicroMenuContainer",
    "BagsBar","StatusTrackingBarManager","MinimapCluster","ObjectiveTrackerFrame","PlayerFrame","TargetFrame",
    "FocusFrame","PetFrame","PartyFrame","CompactRaidFrameContainer","CompactRaidFrameManager","BossTargetFrameContainer",
    "BuffFrame","DebuffFrame","GeneralDockManager","ChatFrameMenuButton","ChatFrameChannelButton",
    "ContainerFrameCombinedBags","CharacterFrame","SpellBookFrame"}
local function global(name) return rawget(_G,name) end
local function plain(value)
    local check=global("issecretvalue")
    if check and check(value) then error("restricted_cinematic_value") end
    return value
end
local function finite(value) return type(value)=="number" and value==value and math.abs(value)<math.huge end
local function boolean(name,unit)
    local fn=global(name)
    if type(fn)~="function" then return nil end
    return plain(fn(unit))==true
end
function Integration.New(options)
    local v,model,open,scene,actor={},nil,false,nil,nil
    local measured,measureTried,update,shield,lastZoom,preferences=nil,false,nil,nil,nil,nil
    local frames,reported={},{}
    local hudActive,hudAlpha=false,1
    local names=addon.Cinematic.CVars()
    local function diagnose(stage,fault)
        if reported[stage] then return end
        reported[stage]=true
        addon.DiagnosticAPI.Record("interface",stage,fault,{stage=stage})
    end
    local function cvar()
        local api=global("C_CVar")
        if type(api)~="table" or type(api.GetCVarInfo)~="function" or type(api.SetCVar)~="function" then error("camera_api_unavailable") end
        return api
    end
    local function readCVar(name)
        local value=plain(cvar().GetCVar(name))
        if type(value)~="string" or not finite(tonumber(value)) then error("camera_cvar_unavailable:"..name) end
        return value
    end
    local function setCVar(name,value)
        if tonumber(readCVar(name))==tonumber(value) then return end
        if plain(cvar().SetCVar(name,value))~=true then error("camera_cvar_refused:"..name) end
    end
    local function readZoom()
        local fn=global("GetCameraZoom")
        if type(fn)~="function" then error("camera_api_unavailable") end
        local zoom=plain(fn())
        if not finite(zoom) or zoom<0 then error("camera_zoom_unavailable") end
        return zoom
    end
    local function zoom(target)
        if lastZoom==target then return end
        local diff=readZoom()-target
        local fn=global(diff>0 and "CameraZoomIn" or "CameraZoomOut")
        if type(fn)~="function" then error("camera_api_unavailable") end
        if math.abs(diff)>.001 then fn(math.abs(diff)) end
        lastZoom=target
    end
    local function characterKey()
        local value=plain(global("UnitGUID")("player"))
        if type(value)~="string" then error("camera_character_unavailable") end
        return value
    end
    local function captureCamera()
        local snapshot={version=1,characterKey=characterKey(),zoom=readZoom(),cvars={}}
        local api=cvar()
        for _,name in ipairs(names) do
            local value,default,account,character,locked,secure,readOnly=api.GetCVarInfo(name)
            plain(value); plain(default); plain(account); plain(character); plain(locked); plain(secure); plain(readOnly)
            if type(value)~="string" or not finite(tonumber(value)) or locked~=false or secure~=false or readOnly~=false then
                error("camera_cvar_not_writable:"..name)
            end
            snapshot.cvars[name]=value
        end
        lastZoom=nil
        return snapshot
    end
    local function visible(name)
        local frame=global(name)
        return frame and frame.IsShown and plain(frame:IsShown())==true or false
    end
    local function height()
        if measured then return measured end
        if not measureTried then
            measureTried=true
            local secrets=global("C_Secrets")
            if secrets and secrets.ShouldUnitIdentityBeSecret and plain(secrets.ShouldUnitIdentityBeSecret("npc")) then return end
            scene=scene or CreateFrame("ModelScene",nil,UIParent)
            scene:SetSize(1,1); scene:SetPoint("BOTTOMLEFT",UIParent,"BOTTOMLEFT",0,0); scene:SetAlpha(0)
            actor=actor or scene:CreateActor()
            if plain(actor:SetModelByUnit("npc"))==false then actor:ClearModel(); return end
        end
        if not actor then return end
        local x1,y1,z1,x2,y2,z2=actor:GetActiveBoundingBox()
        plain(x1); plain(y1); plain(z1); plain(x2); plain(y2); plain(z2)
        if not finite(z1) or not finite(z2) then return end
        measured=z2-z1
        if measured<=0 then measured=nil end
        return measured
    end
    local function context()
        local result={combat=boolean("InCombatLockdown"),vehicle=boolean("UnitInVehicle","player"),
            taxi=boolean("UnitOnTaxi","player"),cinematic=visible("CinematicFrame") or visible("MovieFrame"),
            hasUI=global("UIParent")~=nil and global("UIParent")~=false,creature=false}
        -- Missing safety APIs cannot grant permission to move the camera or hide controls.
        if result.combat==nil or result.vehicle==nil or result.taxi==nil then result.vehicle=true end
        if boolean("UnitHasVehicleUI","player")==true then result.vehicle=true end
        if not model or not model.npc or not model.npc.creatureID or result.combat or result.vehicle or result.taxi or result.cinematic then return result end
        if boolean("UnitExists","npc")~=true or boolean("UnitIsVisible","npc")~=true then return result end
        local guid=plain(global("UnitGUID")("npc"))
        if type(guid)~="string" then return result end
        local kind,id=guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")
        if kind~="Creature" or tonumber(id)~=model.npc.creatureID then return result end
        result.creature=true
        if preferences.cameraEnabled then result.height=height() end
        return result
    end
    local function collectHUD()
        if boolean("InCombatLockdown")~=false then error("combat_cinematic") end
        if not shield then
            shield=CreateFrame("Frame",nil,UIParent); shield:SetAllPoints(UIParent)
            shield:SetFrameStrata("HIGH"); shield:EnableMouse(true); shield:Hide()
        end
        local collected,seen={},{}
        for _,state in ipairs(frames) do collected[#collected+1]=state; seen[state.frame]=true end
        local function collect(frame)
            if not frame or seen[frame] then return end
            seen[frame]=true
            if frame.IsForbidden and plain(frame:IsForbidden()) then return end
            local alpha=plain(frame:GetAlpha())
            if not finite(alpha) or alpha<0 or alpha>1 then error("hud_alpha_unavailable") end
            if #collected>=128 then error("hud_frame_limit") end
            collected[#collected+1]={frame=frame,alpha=alpha}
        end
        for _,name in ipairs(hudNames) do collect(global(name)) end
        for i=1,10 do collect(global("ChatFrame"..i)); collect(global("ChatFrame"..i.."Tab")) end
        for i=1,13 do collect(global("ContainerFrame"..i)) end
        frames=collected
        hudActive=true
    end
    local function hud(alpha,release)
        hudAlpha=alpha
        if not release and alpha<1 and boolean("InCombatLockdown")~=false then error("combat_cinematic") end
        local fault
        for _,state in ipairs(frames) do
            local ok,value=addon.DiagnosticAPI.Try(function()
                if state.frame.IsForbidden and plain(state.frame:IsForbidden()) then error("hud_frame_forbidden") end
                state.frame:SetAlpha(state.alpha*alpha)
            end)
            if not ok then fault=fault or value end
        end
        if shield then shield:SetShown(not release and alpha<1 and #frames>0) end
        if fault then addon.DiagnosticAPI.Raise(fault,"hud_restore_failed") end
        if release then frames={}; hudActive=false end
    end
    local function load()
        local value=plain(addon.database.ReadCinematicRecovery())
        if value==nil then return end
        if type(value)~="table" then return value end
        local result={version=plain(value.version),characterKey=plain(value.characterKey),zoom=plain(value.zoom)}
        local vars=plain(value.cvars)
        if type(vars)~="table" then return result end
        result.cvars={}
        for key,val in pairs(vars) do plain(key); plain(val); result.cvars[key]=val end
        return result
    end
    local d=addon.Cinematic.New({Try=addon.DiagnosticAPI.Try,Diagnose=diagnose,Preferences=function() return preferences end,
        Context=context,CharacterKey=characterKey,CaptureCamera=captureCamera,SetCVar=setCVar,ReadCVar=readCVar,
        ReadZoom=readZoom,Zoom=zoom,CaptureHUD=collectHUD,HUD=hud,Load=load,Save=addon.database.BindCinematicRecovery})
    local function pump()
        if not d.IsUpdating() then if update then update:SetScript("OnUpdate",nil) end; return end
        if not update then update=CreateFrame("Frame",nil,UIParent) end
        local accumulated=0
        update:SetScript("OnUpdate",function(_,delta)
            accumulated=accumulated+delta
            if accumulated<1/30 then return end
            local elapsed=accumulated; accumulated=0
            local ok,fault=addon.DiagnosticAPI.Try(d.Tick,elapsed)
            if not ok then
                diagnose("cinematic_update_failed",fault)
                local restored,restoreFault=addon.DiagnosticAPI.Try(d.Close,true)
                if not restored then diagnose("cinematic_restore_failed",restoreFault) end
            end
            if not d.IsUpdating() then update:SetScript("OnUpdate",nil); if actor then actor:ClearModel() end end
        end)
    end
    local function safe(fn,...)
        local ok,fault=addon.DiagnosticAPI.Try(fn,...)
        if not ok then
            diagnose("cinematic_error",fault)
            local restored,restoreFault=addon.DiagnosticAPI.Try(d.Close,true)
            if not restored then diagnose("cinematic_restore_failed",restoreFault) end
        end
        local pumped,pumpFault=addon.DiagnosticAPI.Try(pump)
        if not pumped then
            diagnose("cinematic_update_failed",pumpFault)
            local restored,restoreFault=addon.DiagnosticAPI.Try(d.Close,true)
            if not restored then diagnose("cinematic_restore_failed",restoreFault) end
        end
    end
    function v.Enter(input)
        if open then return end
        safe(function()
            open=true; model=input; measured=nil; measureTried=false; preferences=options.Preferences()
            d.Enter()
        end)
    end
    function v.Leave(immediate)
        open=false; model=nil; measureTried=false; measured=nil
        safe(d.Close,immediate)
        if actor then actor:ClearModel() end
    end
    function v.Suspend() if open then safe(d.Suspend) else safe(d.Close,true) end end
    function v.Recover() safe(d.Recover) end
    function v.Handle(event,unit)
        if event=="ADDON_LOADED" and hudActive and open and boolean("InCombatLockdown")==false then
            safe(function() collectHUD(); hud(hudAlpha,false) end)
        elseif event=="PLAYER_ENTERING_WORLD" or event=="PLAYER_REGEN_ENABLED" then if not open then v.Recover() end
        elseif event=="PLAYER_REGEN_DISABLED" or event=="PLAYER_CONTROL_LOST" or event=="CINEMATIC_START" or event=="PLAY_MOVIE"
            or event=="UNIT_ENTERED_VEHICLE" and unit=="player" then v.Suspend()
        elseif event=="PLAYER_LOGOUT" or event=="PLAYER_LEAVING_WORLD" then v.Leave(true)
        end
        for _,name in ipairs(Integration.Events) do if name==event then return true end end
        return false
    end
    return v
end
