local _, addon = ...
local Conversation = {}
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
function Conversation.Layout(width,height)
    if type(width)~="number" or type(height)~="number" or width<=0 or height<=0
        or width==math.huge or height==math.huge or width~=width or height~=height then return nil end
    local scale=math.min(width/1280,height/720)
    return { scale=scale, width=width, height=height, top=height*.09, bottom=height*.27,
        maximumBottom=height*.50, contentWidth=math.min(width*.88,1160*scale), speechSize=22*scale,
        optionSize=18*scale, nameSize=21*scale, zoneSize=15*scale }
end
function Conversation.NewSpeech(text)
    if type(text)~="string" then return nil,"invalid_speech" end
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
    function handle.Advance(delta)
        if type(delta)~="number" or delta<0 or delta~=delta or delta==math.huge then return handle.GetText(),false end
        elapsed=elapsed+delta
        local nextValue=math.min(#ends,math.floor(elapsed*60))
        if nextValue<revealed then nextValue=revealed end
        local changed=nextValue~=revealed
        revealed=nextValue
        if changed then rendered=revealed==#ends and text or text:sub(1,ends[revealed] or 0) end
        return handle.GetText(),changed
    end
    return handle
end
