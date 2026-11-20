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
            Action=function(key) if token==generation then controller.Action(key) end end,
            Updated=function() if token==generation then pending=false end end,
            Key=function(key) if token==generation then return controller.Key(key) end end,
            Close=function() if token==generation then controller.Close() end end,
            Error=function(fault,stage,context) if token==generation then controller.Fail(fault,stage,context) end end,
            NativeShown=function() if token==generation then controller.Schedule(current and current.kind=="quest") end end,
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
            local previous=current or lastModel
            release()
            token=generation
            if failed or not options.IsEnabled() or not options.Platform.CanPresent() then return true end
            lastModel,extraContext=nil,nil
            local model=options.GetModel()
            if not model then return true end
            local prepared,code=(options.Prepare or addon.Conversation.Build)(model)
            if not prepared and code=="quest_native_required" then
                lastModel=model
                local _,fault=attempt(function() error(code,0) end)
                diagnose(fault,"quest_native_required")
                return true
            end
            if not prepared then error(code or "invalid_conversation") end
            if prepared.kind~="quest" and not addon.GossipDialogue.HasContent(model) then return true end
            if prepared.kind=="quest" and previous and previous.kind=="quest"
                and previous.quest.id==prepared.quest.id and previous.moment==prepared.moment then
                local old=addon.QuestPresentation.ValidChoice(previous,previous.selected)
                if old and addon.QuestPresentation.ValidChoice(prepared,old.value,old.itemID) then prepared.selected=old.value end
            end
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
            if current.kind=="quest" and view.Selection then view.Selection(current.selected) end
            options.Platform.TakeNative(prepared.moment,callbacks(token).NativeShown)
            return true
        end)
    end
    function controller.Schedule(updateQuest)
        generation=generation+1
        local token=generation
        guard("schedule",function()
            if failed or not options.IsEnabled() or not options.Platform.CanPresent() then release(); return end
            if not options.Platform.Defer(function()
                if token==generation then
                    if updateQuest and current and current.kind=="quest" then controller.Update() else controller.Refresh() end
                end
            end) then error("defer_unavailable") end
        end)
    end
    function controller.Update()
        if not current or current.kind~="quest" or not view.Refresh then controller.Schedule(); return end
        guard("quest_update",function()
            if not options.Platform.CanPresent() then release(); return end
            local model=options.GetModel()
            if not model or not model.quest or model.quest.id~=current.quest.id or model.moment~=current.moment then
                controller.Refresh(); return
            end
            local prepared,code=options.Prepare(model)
            if not prepared then error(code or "quest_state_unavailable") end
            local selected=addon.QuestPresentation.ValidChoice(current,current.selected)
            if selected and addon.QuestPresentation.ValidChoice(prepared,selected.value,selected.itemID) then prepared.selected=selected.value end
            generation=generation+1
            local token=generation
            view=options.View.New(callbacks(token)); pending=true
            local ready=view.Refresh(prepared)
            if failed or generation~=token then return end
            current,lastModel=prepared,prepared; pending=ready==false
            if ready~=false and view.Selection then view.Selection(prepared.selected) end
            options.Platform.TakeNative(prepared.moment,callbacks(token).NativeShown)
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
        if current.kind=="quest" then
            current.selected=entry.value
            if view.Selection then guard("reward_choice",view.Selection,current.selected) end
            return
        end
        local moment=current.moment
        guard("select",function()
            if not options.Platform.CanPresent() then release(); return end
            pending=true
            if entry.kind~="conversation" then release() end
            options.Platform.Select(entry,moment)
        end)
    end
    function controller.Action(key)
        if not current or current.kind~="quest" or pending then return false end
        local allowed=false
        for _,action in ipairs(addon.QuestPresentation.Actions(current,current.selected)) do
            if action.key==key and action.enabled then allowed=true end
        end
        if not allowed then return false end
        local prepared,selected=current,current.selected
        guard("quest_action",function()
            if not options.Platform.CanPresent() then release(); return end
            pending=true; release()
            options.Platform.QuestAction(prepared,key,selected)
        end)
        return true
    end
    function controller.Recorded(kind,questID)
        if current and current.kind=="quest" and current.quest.id==questID then
            current.recorded=kind
            if view.Recorded then guard("quest_recorded",view.Recorded,kind) end
        end
    end
    function controller.Key(key)
        if not current or not view then return false end
        local ok,typing=attempt(view.IsTyping)
        if not ok then controller.Fail(typing,"key"); return false end
        local action,index=addon.Conversation.Key(key,typing)
        if action=="choose" and current and current.kind=="quest" and #current.entries==0 then return false end
        if action=="choose" then controller.Choose(index)
        elseif action=="close" then controller.Close()
        elseif action=="complete" then controller.Complete()
        else return false end
        return true
    end
    function controller.Handle(event,questID)
        local isQuest=options.Prepare and (event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE")
        local active=current or lastModel
        if isQuest then release() end
        if options.Prepare and event=="GOSSIP_CLOSED" then
            local model=options.GetModel()
            if model and model.quest then return false end
        end
        if options.Prepare and (event=="QUEST_ITEM_UPDATE" or event=="QUEST_LOG_UPDATE") and current and current.kind=="quest" then
            gameEvent=event; controller.Update()
        elseif isQuest or (options.Prepare and (event=="QUEST_ITEM_UPDATE" or event=="QUEST_LOG_UPDATE")
            and active and active.kind=="quest")
            or event=="GOSSIP_SHOW" or event=="QUEST_GREETING" or event=="GOSSIP_OPTIONS_REFRESHED" then
            gameEvent=event
            controller.Schedule()
        elseif options.Prepare and (event=="QUEST_ACCEPTED" or event=="QUEST_TURNED_IN") then
            if active and active.kind=="quest" and active.quest.id==questID then gameEvent=event; release() end
        elseif event=="GOSSIP_CLOSED" or event=="QUEST_FINISHED" or event=="PLAYER_LEAVING_WORLD"
            or event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE"
            or event=="GOSSIP_CONFIRM" or event=="GOSSIP_ENTER_CODE" or event=="PLAYER_REGEN_DISABLED" then
            gameEvent=event
            release()
        end
        return event=="PLAYER_REGEN_DISABLED" or (options.Prepare and event=="QUEST_LOG_UPDATE")
    end
    return controller
end
