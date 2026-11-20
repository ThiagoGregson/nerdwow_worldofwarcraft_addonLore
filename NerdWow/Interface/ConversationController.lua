local _, addon = ...
local Controller = {}
addon.ConversationController = Controller
function Controller.New(options)
    local view, current, lastModel, failed, generation, warned, pending = nil,nil,nil,false,0,false,false
    local gameEvent, extraContext
    local releasing=false
    local controller={}
    local attempt=options.Try or pcall
    local function diagnose(fault,stage)
        local context={gameEvent=gameEvent,stage=stage}
        for _, field in ipairs({"viewportWidth","viewportHeight","frameWidth","frameHeight"}) do
            if extraContext then context[field]=extraContext[field] end
        end
        if options.Diagnose then pcall(options.Diagnose,fault,context,current or lastModel) end
    end
    local function report(fault)
        if not warned then warned=true; pcall(options.Report,fault) end
    end
    local function release()
        if releasing then return false end
        releasing=true
        local ok=true
        if view then
            local hidden,fault=attempt(view.Hide)
            if not hidden then failed=true; diagnose(fault,"hide"); report(fault); ok=false end
        end
        local restored,fault=attempt(options.Platform.RestoreNative)
        if not restored then failed=true; diagnose(fault,"restore"); report(fault); ok=false end
        current,pending=nil,false
        generation=generation+1
        releasing=false
        return ok
    end
    function controller.Fail(fault,stage,context)
        failed=true
        if context then extraContext=context end
        diagnose(fault,stage or "interface")
        report(fault)
        release()
    end
    local function guard(stage,callback,...)
        local ok,value=attempt(callback,...)
        if not ok then controller.Fail(value,stage); return nil end
        return value
    end
    local function callbacks(token)
        return {
            Choose=function(index) if token==generation then controller.Choose(index) end end,
            Key=function(key) if token==generation then return controller.Key(key) end end,
            Close=function() if token==generation then controller.Close() end end,
            Error=function(fault,stage,context) if token==generation then controller.Fail(fault,stage,context) end end,
            NativeShown=function() if token==generation then controller.Schedule() end end,
            Ready=function()
                if token~=generation then return end
                guard("font_ready",function()
                    if not options.Platform.Defer(function()
                        if token==generation then controller.Refresh(0,true) end
                    end) then error("defer_unavailable") end
                end)
            end,
        }
    end
    function controller.Refresh(retry,fontsReady)
        retry=retry or 0
        generation=generation+1
        local token=generation
        return guard("show",function()
            release()
            token=generation
            if failed or not options.IsEnabled() or not options.Platform.CanPresent() then return true end
            lastModel,extraContext=nil,nil
            local model=options.GetModel()
            if not model then return true end
            local prepared=addon.Conversation.Build(model)
            if not prepared then error("invalid_conversation") end
            if not addon.GossipDialogue.HasContent(model) then return true end
            lastModel=prepared
            view=options.View.New(callbacks(token))
            local ready,code,context=view.Show(prepared,not fontsReady)
            extraContext=context
            -- Um callback síncrono pode ter executado o fallback dentro de Show.
            if failed or token~=generation then return false end
            if ready==false then
                if code=="font_pending" then return true end
                release()
                if code=="layout_pending" and retry<3 then
                    token=generation
                    if not options.Platform.Defer(function()
                        if token==generation then controller.Refresh(retry+1) end
                    end) then error("defer_unavailable") end
                    return true
                end
                error("layout_unavailable")
            end
            current=prepared
            options.Platform.TakeNative(prepared.moment,callbacks(token).NativeShown)
            return true
        end)
    end
    function controller.Schedule()
        generation=generation+1
        local token=generation
        guard("schedule",function()
            if failed or not options.IsEnabled() or not options.Platform.CanPresent() then release(); return end
            if not options.Platform.Defer(function()
                if token==generation then controller.Refresh() end
            end) then error("defer_unavailable") end
        end)
    end
    function controller.Toggle()
        failed=false
        gameEvent="COMMAND_DIALOGO"
        release()
        guard("toggle",function() if options.IsEnabled() then controller.Schedule() end end)
    end
    function controller.Complete() if current and view then guard("complete",view.Complete) end end
    function controller.Close()
        local moment=current and current.moment
        release()
        if moment then guard("close",options.Platform.Close,moment) end
    end
    function controller.Choose(index)
        if not current or pending or type(index)~="number" or index~=math.floor(index) then return end
        local entry=current.entries[index]
        if not entry or not entry.enabled then return end
        local moment=current.moment
        guard("select",function()
            if not options.Platform.CanPresent() then release(); return end
            pending=true
            if entry.kind~="conversation" then release() end
            options.Platform.Select(entry,moment)
        end)
    end
    function controller.Key(key)
        if not current or not view then return false end
        local ok,typing=attempt(view.IsTyping)
        if not ok then controller.Fail(typing,"key"); return false end
        local action,index=addon.Conversation.Key(key,typing)
        if action=="choose" then controller.Choose(index)
        elseif action=="close" then controller.Close()
        elseif action=="complete" then controller.Complete()
        else return false end
        return true
    end
    function controller.Handle(event)
        if event=="GOSSIP_SHOW" or event=="QUEST_GREETING" or event=="GOSSIP_OPTIONS_REFRESHED" then
            gameEvent=event
            controller.Schedule()
        elseif event=="GOSSIP_CLOSED" or event=="QUEST_FINISHED" or event=="PLAYER_LEAVING_WORLD"
            or event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE"
            or event=="GOSSIP_CONFIRM" or event=="GOSSIP_ENTER_CODE" or event=="PLAYER_REGEN_DISABLED" then
            gameEvent=event
            release()
        end
        return event=="PLAYER_REGEN_DISABLED"
    end
    return controller
end
