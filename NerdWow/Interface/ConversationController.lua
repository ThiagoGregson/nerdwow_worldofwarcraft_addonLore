local _, addon = ...
local Controller = { PREPARATION_TIMEOUT=2 }
addon.ConversationController = Controller
function Controller.New(options)
    local view,current,lastModel,failed,generation,warned,pending=nil,nil,nil,false,0,false,false
    local gameEvent,extraContext,activeMoment,deadline
    local releasing=false
    local retainedCombat=false
    local controller={}
    local attempt=options.Try or pcall
    local function diagnose(fault,stage)
        local context={gameEvent=gameEvent,stage=stage}
        for _,field in ipairs({"viewportWidth","viewportHeight","frameWidth","frameHeight"}) do
            if extraContext then context[field]=extraContext[field] end
        end
        local model=lastModel or current
        if not model or activeMoment and model.moment~=activeMoment then
            local ok,value=pcall(options.GetModel)
            if ok then model=value end
        end
        if options.Diagnose then pcall(options.Diagnose,fault,context,model) end
    end
    local function report(fault)
        if not warned then warned=true; pcall(options.Report,fault) end
    end
    local function effect(method,...)
        if not options.Effects then return end
        local ok,fault=attempt(options.Effects[method],...)
        if not ok then diagnose(fault,"cinematic_"..method) end
    end
    local function canPresent() return options.Platform.CanPresent(retainedCombat) end
    local function release()
        if releasing then return false end
        releasing=true; deadline=nil; generation=generation+1
        effect("Leave",failed or gameEvent=="PLAYER_LEAVING_WORLD" or gameEvent=="CINEMATIC_START" or gameEvent=="PLAY_MOVIE")
        local ok=true
        if view then
            local hidden,fault=attempt(view.Hide)
            if not hidden then failed=true; diagnose(fault,"hide"); report(fault); ok=false end
        end
        local restored,fault=attempt(options.Platform.RestoreNative)
        if not restored then failed=true; diagnose(fault,"restore"); report(fault); ok=false end
        current,lastModel,pending,activeMoment=nil,nil,false,nil
        retainedCombat=false
        releasing=false
        return ok
    end
    function controller.Fail(fault,stage,context)
        failed=true
        if context then extraContext=context end
        diagnose(fault,stage or "interface"); report(fault); release()
    end
    local function guard(stage,callback,...)
        local ok,value=attempt(callback,...)
        if not ok then controller.Fail(value,stage); return nil end
        return value
    end
    local function beginWait()
        if deadline then return end
        local ticket={}; deadline=ticket
        if not options.Platform.Defer(function()
            if deadline==ticket then
                guard("preparation_timeout",function()
                    if view and view.Fallback and view.Fallback() then controller.Refresh(0,true)
                    else error("preparation_timeout",0) end
                end)
            end
        end,Controller.PREPARATION_TIMEOUT) then error("defer_unavailable") end
    end
    local function callbacks(token)
        return {
            Choose=function(index) if token==generation then controller.Choose(index) end end,
            Action=function(key) if token==generation then controller.Action(key) end end,
            Updated=function() if token==generation then pending=false; deadline=nil end end,
            Key=function(key) if token==generation then return controller.Key(key) end end,
            Close=function() if token==generation then controller.Close() end end,
            Error=function(fault,stage,context) if token==generation then controller.Fail(fault,stage,context) end end,
            NativeShown=function(fault,moment)
                if token~=generation then return end
                if fault then controller.Fail(fault,"native_show"); return end
                guard("native_show",function()
                    if not options.Platform.Defer(function()
                        if token~=generation then return end
                        guard("native_refresh",function()
                            options.Platform.TakeNative(moment or activeMoment,callbacks(token).NativeShown,retainedCombat)
                            if not pending then
                                if current and current.kind=="quest" then controller.Update() else controller.Refresh() end
                            end
                        end)
                    end) then error("defer_unavailable") end
                end)
            end,
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
    local function hold(moment)
        activeMoment=moment; pending=true
        view=options.View.New(callbacks(generation))
        options.Platform.TakeNative(moment,callbacks(generation).NativeShown,retainedCombat)
        beginWait()
        if view.Transition then view.Transition() else view.Hide() end
    end
    function controller.Refresh(retry,fontsReady)
        retry=retry or 0; generation=generation+1
        local token=generation
        return guard("show",function()
            if failed or not options.IsEnabled() or not canPresent() then release(); return true end
            local previous=current or lastModel
            local model=options.GetModel()
            if not model then release(); return true end
            lastModel=model
            extraContext=nil
            hold(model.moment)
            local prepared,code=(options.Prepare or addon.Conversation.Build)(model)
            if not prepared and code=="quest_native_required" then
                lastModel=model
                local _,fault=attempt(function() error(code,0) end)
                diagnose(fault,"quest_native_required"); release(); return true
            end
            if not prepared then error(code or "invalid_conversation") end
            addon.Conversation.Configure(prepared,options.GetPreferences and options.GetPreferences())
            if prepared.kind~="quest" and not addon.GossipDialogue.HasContent(model) then release(); return true end
            if prepared.kind=="quest" and previous and previous.kind=="quest"
                and previous.quest.id==prepared.quest.id and previous.moment==prepared.moment then
                local old=addon.QuestPresentation.ValidChoice(previous,previous.selected)
                if old and addon.QuestPresentation.ValidChoice(prepared,old.value,old.itemID) then prepared.selected=old.value end
            end
            lastModel=prepared
            local ready,code,context=view.Show(prepared,not fontsReady)
            extraContext=context
            if failed or token~=generation then return false end
            if ready==false then
                if code=="font_pending" then return true end
                if code=="layout_pending" and retry<3 then
                    if not options.Platform.Defer(function()
                        if token==generation then controller.Refresh(retry+1,true) end
                    end) then error("defer_unavailable") end
                    return true
                end
                error("layout_unavailable")
            end
            current=prepared; pending=false; deadline=nil
            if current.kind=="quest" and view.Selection then view.Selection(current.selected) end
            options.Platform.TakeNative(prepared.moment,callbacks(token).NativeShown,retainedCombat)
            effect("Enter",prepared)
            return true
        end)
    end
    function controller.Schedule(updateQuest,moment)
        generation=generation+1
        local token=generation
        guard("schedule",function()
            if failed or not options.IsEnabled() or not canPresent() then release(); return end
            if moment and not updateQuest then hold(moment) end
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
            if not canPresent() then release(); return end
            local model=options.GetModel()
            if not model or not model.quest or model.quest.id~=current.quest.id or model.moment~=current.moment then
                controller.Refresh(); return
            end
            local prepared,code=options.Prepare(model)
            if not prepared then error(code or "quest_state_unavailable") end
            addon.Conversation.Configure(prepared,options.GetPreferences and options.GetPreferences())
            local selected=addon.QuestPresentation.ValidChoice(current,current.selected)
            if selected and addon.QuestPresentation.ValidChoice(prepared,selected.value,selected.itemID) then prepared.selected=selected.value end
            generation=generation+1
            local token=generation
            view=options.View.New(callbacks(token)); pending=true
            options.Platform.TakeNative(prepared.moment,callbacks(token).NativeShown,retainedCombat)
            local ready=view.Refresh(prepared)
            if failed or generation~=token then return end
            current,lastModel=prepared,prepared; pending=ready==false
            if pending then beginWait() else deadline=nil end
            if not pending and view.Selection then view.Selection(prepared.selected) end
        end)
    end
    function controller.Toggle()
        failed=false; gameEvent="COMMAND_DIALOGO"; release()
        guard("toggle",function() if options.IsEnabled() then controller.Schedule() end end)
    end
    function controller.Configure()
        guard("configure",function()
            if current and not pending then
                local preferences=options.GetPreferences and options.GetPreferences() or {}
                addon.Conversation.Configure(current,preferences)
                if view.Configure then view.Configure(preferences) end
            end
        end)
    end
    function controller.Complete() if current and view and not pending then guard("complete",view.Complete) end end
    function controller.Close()
        local moment=activeMoment or current and current.moment
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
            if not canPresent() then release(); return end
            pending=true
            if options.Prepare then generation=generation+1; hold(moment)
            elseif entry.kind~="conversation" then release() end
            options.Platform.Select(entry,moment,retainedCombat)
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
            if not canPresent() then release(); return end
            generation=generation+1; hold(prepared.moment)
            options.Platform.QuestAction(prepared,key,selected,retainedCombat)
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
        if pending then
            if key=="ESCAPE" then controller.Close(); return true end
            return false
        end
        if not current or not view then return false end
        local ok,typing=attempt(view.IsTyping)
        if not ok then controller.Fail(typing,"key"); return false end
        if key=="SPACE" and not typing and current.kind=="quest" then
            local primary=addon.QuestPresentation.Primary(current)
            if primary then controller.Action(primary.key) end
            return true
        end
        local action,index=addon.Conversation.Key(key,typing)
        if action=="choose" and current.numberHotkeys==false then return false end
        if action=="choose" and current.kind=="quest" and #current.entries==0 then return false end
        if action=="choose" then controller.Choose(index)
        elseif action=="close" then controller.Close()
        elseif action=="complete" then controller.Complete()
        else return false end
        return true
    end
    local function endSoon()
        generation=generation+1; local token=generation
        guard("finish",function()
            if activeMoment then hold(activeMoment) end
            if not options.Platform.Defer(function()
                if token~=generation then return end
                guard("finish",function()
                    local model=options.GetModel()
                    if model then controller.Refresh() else release() end
                end)
            end,.1) then error("defer_unavailable") end
        end)
    end
    function controller.Handle(event,questID)
        if event=="PLAYER_REGEN_DISABLED" and options.Effects and activeMoment then
            gameEvent=event; retainedCombat=true; effect("Suspend"); return true
        end
        local moments={GOSSIP_SHOW="GOSSIP",GOSSIP_OPTIONS_REFRESHED="GOSSIP",QUEST_GREETING="GREETING"}
        if options.Prepare then moments.QUEST_DETAIL="OFFER"; moments.QUEST_PROGRESS="PROGRESS"; moments.QUEST_COMPLETE="COMPLETE" end
        local active=current or lastModel
        if options.Prepare and event=="GOSSIP_CLOSED" then
            local model=options.GetModel()
            if model and model.quest then return false end
        end
        if options.Prepare and (event=="QUEST_ITEM_UPDATE" or event=="QUEST_LOG_UPDATE") and current and current.kind=="quest" and not pending then
            gameEvent=event; controller.Update()
        elseif moments[event] or (options.Prepare and (event=="QUEST_ITEM_UPDATE" or event=="QUEST_LOG_UPDATE")
            and active and active.kind=="quest") then
            gameEvent=event; controller.Schedule(false,moments[event] or activeMoment)
        elseif options.Prepare and (event=="QUEST_ACCEPTED" or event=="QUEST_TURNED_IN") then
            if active and active.kind=="quest" and active.quest.id==questID then gameEvent=event; endSoon() end
        elseif options.Prepare and (event=="GOSSIP_CLOSED" or event=="QUEST_FINISHED") and activeMoment then
            gameEvent=event; endSoon()
        elseif event=="GOSSIP_CLOSED" or event=="QUEST_FINISHED" or event=="PLAYER_LEAVING_WORLD"
            or event=="QUEST_DETAIL" or event=="QUEST_PROGRESS" or event=="QUEST_COMPLETE"
            or event=="GOSSIP_CONFIRM" or event=="GOSSIP_ENTER_CODE" or event=="PLAYER_REGEN_DISABLED"
            or event=="CINEMATIC_START" or event=="PLAY_MOVIE" then
            gameEvent=event; release()
        end
        return event=="PLAYER_REGEN_DISABLED" or (options.Prepare and event=="QUEST_LOG_UPDATE")
    end
    return controller
end
