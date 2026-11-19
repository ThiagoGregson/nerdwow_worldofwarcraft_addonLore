local _, addon = ...
local Controller = {}
addon.ConversationController = Controller
function Controller.New(options)
    local view, current, failed, generation, warned, pending = nil,nil,false,0,false,false
    local controller={}
    local function report(code)
        if warned then return end
        warned=true
        local cause="interface_error"
        for _, known in ipairs({"font_unavailable","native_frame_restricted","native_frame_unavailable",
            "native_restore_failed","interaction_unavailable","defer_unavailable"}) do
            if type(code)=="string" and code:find(known,1,true) then cause=known; break end
        end
        pcall(options.Report,cause)
    end
    local function release()
        local ok=true
        if view then ok=pcall(view.Hide) and ok end
        ok=pcall(options.Platform.RestoreNative) and ok
        current=nil
        pending=false
        generation=generation+1
        if not ok then failed=true; report("native_restore_failed") end
        return ok
    end
    function controller.Fail(code)
        failed=true
        release()
        report(code)
    end
    local function guard(callback,...)
        local ok,value=pcall(callback,...)
        if not ok then controller.Fail(value); return nil end
        return value
    end
    local function callbacks(token)
        return {
            Choose=function(index) if token==generation then controller.Choose(index) end end,
            Key=function(key) if token==generation then return controller.Key(key) end end,
            Close=function() if token==generation then controller.Close() end end,
            Error=controller.Fail,
            NativeShown=function() if token==generation then controller.Refresh() end end,
        }
    end
    function controller.Refresh()
        generation=generation+1
        local token=generation
        local ok=guard(function()
            release()
            token=generation
            if failed or not options.IsEnabled() or not options.Platform.CanPresent() then return true end
            local model=options.GetModel()
            if not model then return true end
            local prepared=addon.Conversation.Build(model)
            if not prepared then error("invalid_conversation") end
            if not addon.GossipDialogue.HasContent(model) then return true end
            view=options.View.New(callbacks(token))
            view.Show(prepared)
            current=prepared
            options.Platform.TakeNative(prepared.moment,callbacks(token).NativeShown)
            return true
        end)
        return ok
    end
    function controller.Schedule()
        generation=generation+1
        local token=generation
        guard(function()
            if failed or not options.IsEnabled() or not options.Platform.CanPresent() then release(); return end
            if not options.Platform.Defer(function()
                if token==generation then controller.Refresh() end
            end) then error("defer_unavailable") end
        end)
    end
    function controller.Toggle()
        failed=false
        release()
        if options.IsEnabled() then controller.Schedule() end
    end
    function controller.Complete()
        if current and view then guard(view.Complete) end
    end
    function controller.Close()
        local moment=current and current.moment
        release()
        if moment then guard(options.Platform.Close,moment) end
    end
    function controller.Choose(index)
        if not current or pending or type(index)~="number" or index~=math.floor(index) then return end
        local entry=current.entries[index]
        if not entry or not entry.enabled then return end
        local moment=current.moment
        guard(function()
            if not options.Platform.CanPresent() then release(); return end
            pending=true
            if entry.kind~="conversation" then release() end
            options.Platform.Select(entry,moment)
        end)
    end
    function controller.Key(key)
        if not current or not view then return false end
        local ok,typing=pcall(view.IsTyping)
        if not ok then controller.Fail(typing); return false end
        local action,index=addon.Conversation.Key(key,typing)
        if action=="choose" then controller.Choose(index)
        elseif action=="close" then controller.Close()
        elseif action=="complete" then controller.Complete()
        else return false end
        return true
    end
    function controller.Handle(event)
        if event=="GOSSIP_SHOW" or event=="QUEST_GREETING" or event=="GOSSIP_OPTIONS_REFRESHED" then
            controller.Schedule()
        elseif event=="GOSSIP_CLOSED" or event=="QUEST_FINISHED" or event=="PLAYER_LEAVING_WORLD"
            or event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE"
            or event=="GOSSIP_CONFIRM" or event=="GOSSIP_ENTER_CODE" or event=="PLAYER_REGEN_DISABLED" then release() end
        return event=="PLAYER_REGEN_DISABLED"
    end
    return controller
end
