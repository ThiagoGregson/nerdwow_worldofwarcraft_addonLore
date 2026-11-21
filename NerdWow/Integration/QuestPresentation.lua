local _, addon = ...
local Platform = {}
addon.QuestPlatform = Platform
local function plain(value)
    if issecretvalue and issecretvalue(value) then error("restricted_interface") end
    return value
end
local function call(fn,...)
    if type(fn)~="function" then error("quest_state_unavailable") end
    return plain(fn(...))
end
function Platform.ReadState(model)
    local id=call(GetQuestID)
    if type(id)~="number" or id~=model.quest.id then error("quest_state_unavailable") end
    local state={questID=id}
    if type(C_QuestInfoSystem)=="table" and type(C_QuestInfoSystem.GetQuestClassification)=="function"
        and type(Enum)=="table" and type(Enum.QuestClassification)=="table" then
        local classification=call(C_QuestInfoSystem.GetQuestClassification,id)
        if type(classification)=="number" then
            for _,key in ipairs({"Normal","Questline","Important","Campaign","Calling","Legendary","Recurring","Meta"}) do
                if Enum.QuestClassification[key]~=nil and Enum.QuestClassification[key]==classification then
                    state.kind=addon.Text.questClasses[key].." · "..addon.Text.questPhases[model.moment]; break
                end
            end
        end
    end
    if model.moment=="OFFER" then
        state.autoAccept=call(QuestGetAutoAccept)
        if type(state.autoAccept)~="boolean" then error("quest_state_unavailable") end
        state.nativeRequired=call(QuestFlagsPVP)
        if type(state.nativeRequired)~="boolean" then error("quest_state_unavailable") end
    elseif model.moment=="PROGRESS" then
        state.canComplete=call(IsQuestCompletable)
        if type(state.canComplete)~="boolean" then error("quest_state_unavailable") end
        state.requiredOwned={}
        if type(C_Item)=="table" and type(C_Item.GetItemCount)=="function" then
            local r=addon.DialogueAPI.Reader()
            for _,item in ipairs(model.requiredItems or {}) do
                if item.itemID then
                    local count=r.Number(r.Call(C_Item.GetItemCount,item.itemID,false,false,false,false),0)
                    if count~=nil then state.requiredOwned[item.index]={itemID=item.itemID,count=count} end
                end
            end
        end
    elseif model.moment=="COMPLETE" then
        state.choiceCount=call(GetNumQuestChoices)
        if type(state.choiceCount)~="number" or state.choiceCount<0 or state.choiceCount>256
            or state.choiceCount~=math.floor(state.choiceCount) then error("quest_state_unavailable") end
    end
    -- The offer panel does not query delivery money. The native reward button
    -- also permits nil here; only an actual positive cost opens confirmation.
    if model.moment~="OFFER" then
        local cost=call(GetQuestMoneyToGet)
        if cost==nil and model.moment=="COMPLETE" then cost=0 end
        if type(cost)~="number" or cost<0 or cost>9007199254740991 or cost~=cost then error("quest_state_unavailable") end
        if cost>0 then state.nativeRequired=true end
    end
    return state
end
function Platform.Action(view,key,selected)
    if not addon.ConversationPlatform.CanPresent() then error("combat_interface") end
    local state=Platform.ReadState(view)
    if state.nativeRequired then error("quest_native_required") end
    if view.moment=="OFFER" and key=="ACCEPT" and not state.autoAccept then call(AcceptQuest)
    elseif view.moment=="OFFER" and key=="CONFIRM" and state.autoAccept then call(AcknowledgeAutoAcceptQuest)
    elseif view.moment=="OFFER" and key=="DECLINE" and not state.autoAccept
        or view.moment=="PROGRESS" and key=="LATER" then call(CloseQuest)
    elseif view.moment=="PROGRESS" and key=="CONTINUE" and state.canComplete then call(CompleteQuest)
    elseif view.moment=="COMPLETE" and key=="FINISH" then
        if state.choiceCount~=#view.entries then error("quest_state_unavailable") end
        local choice=state.choiceCount>0 and addon.QuestPresentation.ValidChoice(view,selected)
        if state.choiceCount>0 and not choice then error("invalid_interaction") end
        -- Revalidate the item at its original API index before the irreversible action.
        if choice then
            local _,_,_,_,_,itemID=GetQuestItemInfo("choice",choice.value)
            if plain(itemID)~=choice.itemID then error("quest_state_unavailable") end
        end
        call(GetQuestReward,choice and choice.value or 0)
    else error("invalid_interaction") end
end
function Platform.ShowItem(owner,item,kind,questID)
    if call(GetQuestID)~=questID then return end
    if not GameTooltip then error("interaction_unavailable") end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    if type(GameTooltip.SetQuestItem)=="function" then GameTooltip:SetQuestItem(kind,item.index)
    elseif item.itemID and type(GameTooltip.SetItemByID)=="function" then GameTooltip:SetItemByID(item.itemID)
    else error("interaction_unavailable") end
    GameTooltip:Show()
end
function Platform.HideItem(owner)
    if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end
