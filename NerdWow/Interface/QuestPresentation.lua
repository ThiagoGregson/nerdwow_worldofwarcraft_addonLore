local _, addon = ...
local Quest = {}
addon.QuestPresentation = Quest
local function nonblank(value) return type(value)=="string" and value:find("%S") end
local function boundary(text,limit)
    local finish=math.min(#text,limit)
    while finish>0 do
        local nextByte=text:byte(finish+1)
        if not nextByte or nextByte<128 or nextByte>=192 then break end
        finish=finish-1
    end
    return finish
end
function Quest.Short(text)
    if not nonblank(text) then return "" end
    local finish=text:find("[.!?]") or text:find("\n") or #text
    -- Keep WoW markup intact rather than cutting inside a hyperlink/texture.
    if text:find("|",1,true) then
        local speech=addon.Conversation.NewSpeech(text)
        local prefix=speech.Advance(150/60)
        return prefix..(prefix~=text and "…" or "")
    end
    finish=math.min(finish,boundary(text,220))
    return text:sub(1,finish)..(finish<#text and not text:sub(finish,finish):match("[.!?]") and "…" or "")
end
function Quest.Drop(text)
    if not nonblank(text) or text:find("|",1,true) then return nil,text end
    local start=text:find("%S")
    local byte=text:byte(start)
    if byte<128 and not text:sub(start,start):match("%a") then return nil,text end
    local size=byte>=240 and 4 or byte>=224 and 3 or byte>=192 and 2 or 1
    if size>1 then
        local second=text:byte(start+1)
        if not second or second<128 or second>=192 then return nil,text end
        local code=size==2 and second and (byte-192)*64+second-128 or 0
        if not (code>=192 and code<=214 or code>=216 and code<=246 or code>=248 and code<=591) then return nil,text end
    end
    -- A decomposed accent belongs with its base; leave that grapheme intact.
    local nextByte=text:byte(start+size)
    if nextByte==204 or nextByte==205 then return nil,text end
    return text:sub(start,start+size-1),text:sub(1,start-1)..text:sub(start+size)
end
function Quest.Objective(objective)
    local text=objective.text or ""
    local plain=text:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
    if plain:find("%d+%s*/%s*%d+") then return text,"" end
    local count=objective.fulfilled~=nil and objective.required~=nil
        and tostring(objective.fulfilled).."/"..tostring(objective.required) or ""
    return text,count
end
function Quest.ItemCount(item,required)
    if not required then return "" end
    if item.quantity~=nil then
        return string.format(item.owned~=nil and addon.Text.questOwnedCount or addon.Text.questRequiredCount,
            tostring(item.owned~=nil and item.owned or item.quantity),tostring(item.quantity))
    end
    return item.owned~=nil and string.format(addon.Text.questOwnedOnly,tostring(item.owned)) or ""
end
function Quest.Build(input,state,receipt)
    local model,code=addon.QuestDialogue.Snapshot(input)
    if not model then return nil,code end
    if not state or state.questID~=model.quest.id then return nil,"quest_state_unavailable" end
    if state.nativeRequired then return nil,"quest_native_required" end
    local rewards=model.moment~="PROGRESS" and model.rewards or nil
    local choices=rewards and rewards.choices or {}
    local required=model.moment=="PROGRESS" and model.requiredItems or {}
    for _,item in ipairs(required or {}) do
        local owned=state.requiredOwned and state.requiredOwned[item.index]
        if owned and owned.itemID==item.itemID then item.owned=owned.count end
    end
    if model.moment=="COMPLETE" and (type(state.choiceCount)~="number" or state.choiceCount~=#choices) then
        return nil,"quest_state_unavailable"
    end
    local text=model.moment=="OFFER" and model.quest.description
        or model.moment=="PROGRESS" and model.quest.progressText or model.quest.rewardText
    text=text or ""
    local view={kind="quest",moment=model.moment,quest=model.quest,npc=model.npc,location=model.location,
        theme=addon.DialogueThemes.Resolve(model.location,model.npc),text=Quest.Short(text),entries={},state=state,
        paper={title=model.quest.title or addon.Text.questUnknownTitle,kind=state.kind,
            text=text,objectiveText=model.moment=="OFFER" and model.quest.objectiveText or nil,objectives=model.objectives or {},
            requiredItems=required or {},choices=choices,fixed=rewards and rewards.fixed or {},
            money=rewards and rewards.money,experience=rewards and rewards.experience}}
    if model.moment=="COMPLETE" then
        for _,item in ipairs(choices) do
            view.entries[#view.entries+1]={kind="reward",value=item.index,itemID=item.itemID,text=item.name,
                enabled=item.itemID~=nil and nonblank(item.name)~=nil}
        end
        if #view.entries==1 and view.entries[1].enabled then view.selected=view.entries[1].value end
    end
    if receipt and receipt.questID==model.quest.id then view.recorded=receipt.kind end
    return view
end
function Quest.ValidChoice(view,index,itemID)
    for _,entry in ipairs(view.entries or {}) do
        if entry.value==index and entry.enabled and (not itemID or entry.itemID==itemID) then return entry end
    end
end
function Quest.Actions(view,selected)
    local t=addon.Text
    if view.moment=="OFFER" then
        if view.state.autoAccept then return {{key="CONFIRM",text=t.questConfirm,enabled=true}} end
        return {{key="ACCEPT",text=t.questAccept,enabled=true},{key="DECLINE",text=t.questDecline,enabled=true,ghost=true}}
    elseif view.moment=="PROGRESS" then
        return {{key="CONTINUE",text=t.questContinue,enabled=view.state.canComplete==true},
            {key="LATER",text=t.questLater,enabled=true,ghost=true}}
    end
    return {{key="FINISH",text=t.questFinish,enabled=#view.entries==0 or Quest.ValidChoice(view,selected)~=nil}}
end
function Quest.Note(view)
    local kind=view.recorded
    local moments={QUEST_OFFERED="OFFER",QUEST_ACCEPTED="OFFER",QUEST_PROGRESS_VIEWED="PROGRESS",QUEST_COMPLETED="COMPLETE"}
    if moments[kind]==view.moment and addon.Text.questRecorded[kind] then return addon.Text.questRecorded[kind] end
    return view.moment=="COMPLETE" and addon.Text.questWillRecord or ""
end
function Quest.Layout(width,height,lineWidth)
    local layout=addon.Conversation.Layout(width,height,lineWidth)
    if not layout then return nil end
    local s=layout.scale
    layout.paperWidth=math.min(width*.37,490*s)
    layout.paperLeft=width-width*.045-layout.paperWidth
    layout.paperTop=height*.12
    layout.paperHeight=height*.82
    local available=layout.paperLeft-32*s
    layout.textWidth=math.min(layout.textWidth,available-110*s)
    if layout.textWidth<180*s then return nil end
    layout.textLeft=(available-layout.textWidth-84*s)/2+84*s
    layout.contentWidth=layout.textWidth+84*s
    return layout
end
function Quest.PaperHeight(layout,contentHeight)
    return math.min(layout.paperHeight,math.max(360*layout.scale,contentHeight+140*layout.scale))
end
