local _, addon = ...
local Conversation = { DEFAULT_SPEED=60 }
addon.Conversation = Conversation
local function nonblank(value) return type(value)=="string" and value:find("%S") ~= nil end
local function unique(entries, field, value)
    if value == nil then return false end
    local count = 0
    for _, entry in ipairs(entries or {}) do if entry[field] == value then count = count + 1 end end
    return count == 1
end
function Conversation.Build(input)
    local model, code = addon.GossipDialogue.Snapshot(input)
    if not model then return nil, code end
    local view = { moment=model.moment, text=model.text or "", npc=model.npc, location=model.location,
        theme=addon.DialogueThemes.Resolve(model.location, model.npc), entries={} }
    for _, spec in ipairs({ {"activeQuests","ACTIVE"}, {"availableQuests","AVAILABLE"} }) do
        for _, quest in ipairs(model[spec[1]] or {}) do
            local value = model.moment=="GREETING" and quest.index or quest.questID
            local safe = value ~= nil and (model.moment=="GREETING" or unique(model[spec[1]],"questID",value))
            view.entries[#view.entries+1] = { kind=spec[2]=="AVAILABLE" and "available"
                or quest.isComplete==true and "complete" or "active", text=quest.title,
                action=spec[2], value=value, enabled=safe and nonblank(quest.title) }
        end
    end
    local options = model.options or {}
    table.sort(options,function(a,b)
        if a.orderIndex ~= nil and b.orderIndex ~= nil and a.orderIndex ~= b.orderIndex then return a.orderIndex < b.orderIndex end
        if (a.orderIndex==nil) ~= (b.orderIndex==nil) then return a.orderIndex ~= nil end
        return a.index < b.index
    end)
    for _, option in ipairs(options) do
        local action, value
        if unique(options,"optionID",option.optionID) then action,value="OPTION_ID",option.optionID
        elseif unique(options,"orderIndex",option.orderIndex) then action,value="OPTION_INDEX",option.orderIndex end
        view.entries[#view.entries+1] = { kind="conversation", text=option.text,
            icon=option.overrideIconID or option.icon, action=action, value=value,
            enabled=model.moment=="GOSSIP" and action~=nil and nonblank(option.text)
                and (option.status==nil or option.status==0) }
    end
    for index, entry in ipairs(view.entries) do entry.number=index end
    return view
end
function Conversation.Key(key, typing)
    if key=="ESCAPE" then return "close" end
    if key=="SPACE" and typing then return "complete" end
    if type(key)=="string" and key:match("^[1-9]$") then return "choose", tonumber(key) end
end
function Conversation.Configure(view,preferences)
    preferences=preferences or {}
    view.theme=addon.DialogueThemes.Resolve(view.location,view.npc,preferences.theme)
    view.speechSpeed=preferences.speechSpeed or Conversation.DEFAULT_SPEED
    view.numberHotkeys=preferences.numberHotkeys~=false
    view.textSize=preferences.textSize or 100
end
Conversation.LINE_SAMPLE="A história de Azeroth vive nas palavras de quem protege os antigos lares"
function Conversation.Layout(width,height,lineWidth,typography)
    if type(width)~="number" or type(height)~="number" or width<=0 or height<=0
        or width==math.huge or height==math.huge or width~=width or height~=height then return nil end
    local scale=math.min(width/1280,height/720)
    typography=typography or addon.Typography.Build(height,1,100)
    local speechSize=typography.speech
    if type(lineWidth)~="number" or lineWidth<=0 or lineWidth~=lineWidth or lineWidth==math.huge then
        lineWidth=72*typography.body*.5
    end
    local textWidth=math.min(width*.88-84*scale,lineWidth)
    return { scale=scale, width=width, height=height, top=height*.09, bottom=height*.27,
        maximumBottom=height*.38, textWidth=textWidth, textLeft=(width-textWidth)/2,
        contentWidth=textWidth+84*typography.unit, speechSize=speechSize,typography=typography,
        optionSize=typography.body, nameSize=typography.heading, zoneSize=typography.heading }
end
function Conversation.Arrange(layout,header,speech,options)
    local s=layout.scale
    local noteHeight=layout.typography.note*1.6
    -- Give measured options priority over extra speech lines. Both viewports
    -- stay inside the bar; only lists that exceed the remaining space scroll.
    local minimumSpeech=math.min(speech,layout.speechSize*1.6)
    local capacity=math.max(1,layout.maximumBottom-(18*s+header+8*s+noteHeight+12*s+18*s+minimumSpeech))
    local optionHint=options>capacity and noteHeight or 0
    local optionHeight=math.min(options,math.max(1,capacity-optionHint))
    local optionBottom=18*s+optionHint
    local fixed=18*s+header+8*s+noteHeight+12*s+optionHeight+optionBottom
    local bottom=math.min(layout.maximumBottom,math.max(layout.bottom,fixed+speech))
    local speechTop=bottom-18*s-header-8*s
    local speechBottom=optionBottom+optionHeight+12*s+noteHeight
    return {bottom=bottom,headerTop=bottom-18*s,speechTop=speechTop,
        speechHeight=math.max(1,speechTop-speechBottom),speechBottom=speechBottom,
        optionHeight=math.max(1,optionHeight),optionBottom=optionBottom,optionHint=optionHint>0}
end
function Conversation.Hint(view,typing)
    local parts={}
    if typing then parts[#parts+1]=addon.Text.cinemaHintSpeech
    elseif view.kind=="quest" then
        local primary=addon.QuestPresentation.Primary(view)
        if primary then parts[#parts+1]=string.format(addon.Text.cinemaHintPrimary,primary.text) end
    end
    for index,entry in ipairs(view.entries or {}) do
        if index>9 then break end
        if entry.enabled and view.numberHotkeys~=false then
            parts[#parts+1]=view.kind=="quest" and addon.Text.cinemaHintReward or addon.Text.cinemaHintOption
            break
        end
    end
    parts[#parts+1]=addon.Text.cinemaHintExit
    return table.concat(parts,"  ·  ")
end
function Conversation.Paragraphs(text)
    local result,position={},1
    while position<=#text do
        local first,last=text:find("\r?\n[ \t\r]*\n[ \t\r\n]*",position)
        local finish=first and first-1 or #text
        if finish>=position then result[#result+1]={text=text:sub(position,finish),first=position,last=finish} end
        if not first then break end
        position=last+1
    end
    return result
end
function Conversation.NewSpeech(text,speed)
    if type(text)~="string" then return nil,"invalid_speech" end
    speed=speed or Conversation.DEFAULT_SPEED
    if type(speed)~="number" or speed<=0 or speed~=speed or speed==math.huge then return nil,"invalid_speed" end
    local ends, position = {}, 1
    while position<=#text do
        local finish, visible
        local prefix=text:sub(position,position+1)
        if prefix=="|c" and text:sub(position+2,position+9):match("^%x%x%x%x%x%x%x%x$") then finish=position+9
        elseif prefix=="|r" then finish=position+1
        elseif prefix=="|T" or prefix=="|A" then
            local close=text:find(prefix=="|T" and "|t" or "|a",position+2,true)
            if close then finish,visible=close+1,true end
        elseif prefix=="|H" then
            local first=text:find("|h",position+2,true)
            local last=first and text:find("|h",first+2,true)
            if last then finish,visible=last+1,true end
        elseif prefix=="||" then finish,visible=position+1,true end
        if not finish then
            local byte=text:byte(position)
            local size=byte>=240 and 4 or byte>=224 and 3 or byte>=192 and 2 or 1
            finish,visible=math.min(#text,position+size-1),true
        end
        if visible then ends[#ends+1]=finish
        elseif #ends>0 then ends[#ends]=finish end
        position=finish+1
    end
    local revealed,elapsed=0,0
    local rendered=#ends==0 and text or ""
    local handle={}
    function handle.GetText() return rendered end
    function handle.IsComplete() return revealed==#ends end
    function handle.Complete() revealed=#ends; rendered=text; return text end
    function handle.SetSpeed(value)
        if type(value)~="number" or value<=0 or value~=value or value==math.huge then return nil,"invalid_speed" end
        elapsed=elapsed*speed/value; speed=value; return true
    end
    function handle.Advance(delta)
        if type(delta)~="number" or delta<0 or delta~=delta or delta==math.huge then return handle.GetText(),false end
        elapsed=elapsed+delta
        local nextValue=math.min(#ends,math.floor(elapsed*speed))
        if nextValue<revealed then nextValue=revealed end
        local changed=nextValue~=revealed
        revealed=nextValue
        if changed then rendered=revealed==#ends and text or text:sub(1,ends[revealed] or 0) end
        return handle.GetText(),changed
    end
    return handle
end
