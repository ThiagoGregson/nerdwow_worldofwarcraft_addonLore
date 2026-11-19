local _, addon = ...
local View = {}
addon.ConversationView = View
local FONT="Interface\\AddOns\\NerdWow\\Fonts\\"
local CIRCLE="Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local handle,root,callbacks,shown,model,speech
local top,bottom,edgeLeft,edgeRight,crest,crestShadow,name,title,zone,subzone,hint,scroll,child,line,measure,exit
local buttons={}
local entrance,bottomHeight,layout=0,0,nil
local function rgb(hex)
    return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255
end
local function color(object,hex,alpha)
    local r,g,b=rgb(hex)
    object:SetTextColor(r,g,b,alpha or 1)
end
local function tint(object,hex,alpha)
    local r,g,b=rgb(hex)
    object:SetVertexColor(r,g,b,alpha or 1)
end
local function font(object,file,size)
    if not object:SetFont(FONT..file..".ttf",math.max(8,size),"") then error("font_unavailable") end
    object:SetShadowColor(0,0,0,.9)
    object:SetShadowOffset(0,-1)
end
local function safe(fn)
    return function(...)
        local ok,value=pcall(fn,...)
        if not ok and callbacks then pcall(callbacks.Error,value) end
        return ok and value
    end
end
local function texture(parent,layer)
    return parent:CreateTexture(nil,layer or "BACKGROUND")
end
local function label(parent)
    local result=parent:CreateFontString(nil,"OVERLAY")
    result:SetJustifyH("LEFT"); result:SetJustifyV("TOP")
    result:SetWordWrap(true)
    return result
end
local function button(index)
    if buttons[index] then return buttons[index] end
    local b=CreateFrame("Button",nil,child)
    b:RegisterForClicks("LeftButtonUp")
    b.ring=texture(b,"ARTWORK"); b.ring:SetTexture(CIRCLE)
    b.fill=texture(b,"ARTWORK"); b.fill:SetTexture(CIRCLE)
    b.number=label(b); b.icon=texture(b,"ARTWORK"); b.symbol=label(b); b.label=label(b)
    b.light=texture(b); b.light:SetColorTexture(1,1,1,1); b.light:SetAllPoints(); b.light:SetAlpha(0)
    b:SetScript("OnEnter",safe(function()
        if b.entry and b.entry.enabled then
            color(b.label,"ffffff"); tint(b.fill,model.theme.accent); color(b.number,model.theme.night)
            b.light:SetAlpha(.055)
        end
    end))
    b:SetScript("OnLeave",safe(function()
        if model then color(b.label,b.entry.enabled and model.theme.option or model.theme.muted)
            tint(b.fill,model.theme.night); color(b.number,model.theme.accent) end
        b.light:SetAlpha(0); b:SetAlpha(1)
    end))
    b:SetScript("OnMouseDown",safe(function() if b.entry.enabled then b:SetAlpha(.65) end end))
    b:SetScript("OnMouseUp",safe(function() b:SetAlpha(1) end))
    buttons[index]=b
    return b
end
local function place()
    if not shown or not model then return end
    local width,height=root:GetWidth(),root:GetHeight()
    layout=assert(addon.Conversation.Layout(width,height))
    local s=layout.scale
    local textWidth=layout.contentWidth-84*s
    local left=(width-layout.contentWidth)/2
    font(name,"Cinzel-Bold",layout.nameSize); color(name,model.theme.glow)
    name:ClearAllPoints(); name:SetWidth(textWidth*.62)
    name:SetText(model.npc and model.npc.name or addon.Text.cinemaUnknownNPC)
    name:SetWidth(math.min(textWidth*.62,name:GetStringWidth()+2*s))
    font(title,"EBGaramond-Italic",17*s); color(title,model.theme.muted)
    title:SetWidth(textWidth*.35); title:SetText(model.npc and model.npc.title or "")
    title:ClearAllPoints(); title:SetPoint("TOPLEFT",name,"TOPRIGHT",14*s,-3*s)
    local header=math.max(26*s,name:GetStringHeight(),title:GetStringHeight())
    font(zone,"Cinzel-Regular",layout.zoneSize); color(zone,model.theme.glow,.85)
    zone:SetText(model.location and model.location.zone or "")
    zone:SetWidth(width*.48); zone:ClearAllPoints(); zone:SetPoint("TOP",root,"TOP",0,-height*.026)
    zone:SetJustifyH("CENTER")
    font(subzone,"EBGaramond-Regular",13*s); color(subzone,model.theme.muted)
    subzone:SetText(model.location and model.location.subZone or "")
    subzone:SetWidth(width*.5); subzone:ClearAllPoints(); subzone:SetPoint("TOP",zone,"BOTTOM",0,-2*s)
    subzone:SetJustifyH("CENTER")
    font(hint,"EBGaramond-Regular",12*s); color(hint,model.theme.muted,.8)
    hint:SetText(addon.Text.cinemaHint); hint:ClearAllPoints(); hint:SetPoint("TOPRIGHT",root,"TOPRIGHT",-48*s,-height*.026)
    font(exit.label,"Cinzel-Regular",24*s); color(exit.label,model.theme.muted)
    exit:SetSize(28*s,28*s); exit:ClearAllPoints(); exit:SetPoint("TOPRIGHT",root,"TOPRIGHT",-14*s,-height*.018)
    scroll:SetWidth(textWidth); child:SetWidth(textWidth)
    font(line,"EBGaramond-Regular",layout.speechSize); color(line,model.theme.subtitle)
    line:SetSpacing(4*s); line:SetWidth(textWidth); line:SetText(model.text)
    local speechHeight=model.text~="" and math.max(layout.speechSize*2.9,line:GetStringHeight()) or 0
    line:SetHeight(math.max(1,speechHeight)); line:ClearAllPoints(); line:SetPoint("TOPLEFT",child,"TOPLEFT",0,0)
    font(measure,"EBGaramond-Regular",layout.optionSize)
    local x,y,rowHeight=0,-speechHeight-12*s,0
    for index,entry in ipairs(model.entries) do
        local b=button(index); b.entry=entry
        local tokenCallbacks=callbacks
        b:SetScript("OnClick",safe(function() tokenCallbacks.Choose(index) end))
        local text=entry.text and entry.text:find("%S") and entry.text or addon.Text.cinemaUnknownOption
        measure:SetText(text)
        local itemWidth=math.min(textWidth,math.max(110*s,measure:GetStringWidth()+66*s))
        if x>0 and x+itemWidth>textWidth then x=0; y=y-rowHeight-7*s; rowHeight=0 end
        font(b.label,"EBGaramond-Regular",layout.optionSize)
        color(b.label,entry.enabled and model.theme.option or model.theme.muted,entry.enabled and 1 or .6)
        b.label:SetWidth(itemWidth-60*s); b.label:SetText(text)
        local itemHeight=math.max(28*s,b.label:GetStringHeight()+8*s)
        b:SetSize(itemWidth,itemHeight); b:ClearAllPoints(); b:SetPoint("TOPLEFT",child,"TOPLEFT",x,y)
        b.label:ClearAllPoints(); b.label:SetPoint("TOPLEFT",b,"TOPLEFT",54*s,-3*s)
        for _, circle in ipairs({b.ring,b.fill}) do circle:ClearAllPoints(); circle:SetPoint("TOPLEFT",b,"TOPLEFT",0,-4*s) end
        b.ring:SetSize(22*s,22*s); tint(b.ring,model.theme.accent,.75)
        b.fill:SetSize(20*s,20*s); b.fill:ClearAllPoints(); b.fill:SetPoint("CENTER",b.ring,"CENTER",0,0)
        tint(b.fill,model.theme.night)
        font(b.number,"Cinzel-Regular",12*s); color(b.number,model.theme.accent)
        b.number:SetText(tostring(index)); b.number:SetJustifyH("CENTER"); b.number:SetJustifyV("MIDDLE")
        b.number:ClearAllPoints(); b.number:SetAllPoints(b.ring)
        b.icon:ClearAllPoints(); b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",30*s,-6*s); b.icon:SetSize(16*s,16*s)
        b.symbol:ClearAllPoints(); b.symbol:SetPoint("TOPLEFT",b,"TOPLEFT",30*s,-4*s)
        font(b.symbol,"Cinzel-Bold",18*s)
        color(b.symbol,entry.kind=="active" and model.theme.muted or model.theme.secondary)
        if entry.kind=="conversation" and entry.icon then
            b.icon:SetTexture(entry.icon); b.icon:Show(); b.symbol:Hide()
        else
            b.icon:Hide(); b.symbol:Show()
            b.symbol:SetText(entry.kind=="available" and "!" or entry.kind=="conversation" and "·" or "?")
        end
        b:SetEnabled(entry.enabled); b:SetAlpha(1); b.light:SetAlpha(0); b:Show()
        rowHeight=math.max(rowHeight,itemHeight); x=x+itemWidth+18*s
    end
    for index=#model.entries+1,#buttons do buttons[index]:Hide() end
    local contentHeight=math.max(1,-y+rowHeight+8*s)
    child:SetHeight(contentHeight)
    bottomHeight=math.min(layout.maximumBottom,math.max(layout.bottom,contentHeight+header+48*s))
    name:SetPoint("TOPLEFT",root,"BOTTOMLEFT",left+84*s,bottomHeight-24*s)
    scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT",root,"BOTTOMLEFT",left+84*s,bottomHeight-24*s-header-8*s)
    scroll:SetHeight(math.max(1,bottomHeight-header-56*s))
    local r,g,b=rgb(model.theme.night)
    top:SetColorTexture(r,g,b,1); bottom:SetColorTexture(r,g,b,1)
    local ar,ag,ab=rgb(model.theme.accent)
    edgeLeft:SetGradient("HORIZONTAL",CreateColor(ar,ag,ab,0),CreateColor(ar,ag,ab,.6))
    edgeRight:SetGradient("HORIZONTAL",CreateColor(ar,ag,ab,.6),CreateColor(ar,ag,ab,0))
    for _, edge in ipairs({edgeLeft,edgeRight}) do edge:SetSize(width/2,1) end
    crest:SetTexture(model.theme.crest); crestShadow:SetTexture(model.theme.crest)
    crest:SetSize(56*s,56*s); crestShadow:SetSize(58*s,58*s)
    crest:ClearAllPoints(); crest:SetPoint("TOPLEFT",root,"BOTTOMLEFT",left,bottomHeight-24*s)
    crestShadow:ClearAllPoints(); crestShadow:SetPoint("CENTER",crest,"CENTER",0,-2*s)
    crestShadow:SetVertexColor(0,0,0,.65)
    crest:SetVertexColor(1,1,1,1)
    line:SetText(speech.GetText())
    local eased=1-(1-math.min(1,entrance/.9))^3
    top:SetHeight(math.max(.01,layout.top*eased)); bottom:SetHeight(math.max(.01,bottomHeight*eased))
end
local function update(_,delta)
    if entrance<.9 then
        entrance=math.min(.9,entrance+delta)
        local t=entrance/.9
        local eased=1-(1-t)^3
        top:SetHeight(math.max(.01,layout.top*eased)); bottom:SetHeight(math.max(.01,bottomHeight*eased))
        for _, object in ipairs({name,title,zone,subzone,hint,crest,crestShadow,scroll,exit}) do object:SetAlpha(eased) end
    end
    local text,changed=speech.Advance(delta)
    if changed then line:SetText(text) end
    if entrance==.9 and speech.IsComplete() then root:SetScript("OnUpdate",nil) end
end
function View.New(newCallbacks)
    callbacks=newCallbacks
    if handle then return handle end
    root=CreateFrame("Frame",nil,UIParent); root:Hide(); root:SetAllPoints(UIParent)
    root:SetFrameStrata("DIALOG"); root:EnableMouse(false); root:EnableKeyboard(false)
    root:SetPropagateKeyboardInput(true)
    top,bottom=texture(root),texture(root)
    top:SetPoint("TOPLEFT"); top:SetPoint("TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT")
    edgeLeft,edgeRight=texture(root,"BORDER"),texture(root,"BORDER")
    edgeLeft:SetColorTexture(1,1,1,1); edgeRight:SetColorTexture(1,1,1,1)
    edgeLeft:SetPoint("TOPLEFT",bottom,"TOPLEFT",0,1); edgeRight:SetPoint("TOPRIGHT",bottom,"TOPRIGHT",0,1)
    crestShadow,crest=texture(root,"ARTWORK"),texture(root,"OVERLAY")
    local mask=root:CreateMaskTexture(nil,"ARTWORK"); mask:SetTexture(CIRCLE); mask:SetAllPoints(crest)
    crest:AddMaskTexture(mask); crestShadow:AddMaskTexture(mask)
    name,title,zone,subzone,hint=label(root),label(root),label(root),label(root),label(root)
    scroll=CreateFrame("ScrollFrame",nil,root); child=CreateFrame("Frame",nil,scroll)
    scroll:SetScrollChild(child); scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel",safe(function(_,delta)
        scroll:SetVerticalScroll(math.max(0,math.min(scroll:GetVerticalScrollRange(),scroll:GetVerticalScroll()-delta*42*layout.scale)))
    end))
    line,measure=label(child),label(child); measure:SetWidth(100000); measure:Hide()
    exit=CreateFrame("Button",nil,root); exit.label=label(exit); exit.label:SetAllPoints(); exit.label:SetJustifyH("CENTER")
    exit.label:SetText("×"); exit:SetScript("OnClick",safe(function() callbacks.Close() end))
    exit:SetScript("OnEnter",safe(function() color(exit.label,"ffffff") end))
    exit:SetScript("OnLeave",safe(function() if model then color(exit.label,model.theme.muted) end end))
    root:SetScript("OnKeyDown",safe(function(_,key)
        root:SetPropagateKeyboardInput(true)
        if shown and addon.ConversationPlatform.KeyAllowed() and callbacks.Key(key) then root:SetPropagateKeyboardInput(false) end
    end))
    root:SetScript("OnKeyUp",safe(function() root:SetPropagateKeyboardInput(true) end))
    root:SetScript("OnSizeChanged",safe(place))
    root:SetScript("OnShow",safe(function()
        if shown and model then
            place()
            root:EnableKeyboard(true)
            if entrance<.9 or not speech.IsComplete() then root:SetScript("OnUpdate",safe(update)) end
        end
    end))
    root:SetScript("OnHide",function() root:SetScript("OnUpdate",nil); root:EnableKeyboard(false) end)
    handle={}
    function handle.Show(input)
        model=input; speech=assert(addon.Conversation.NewSpeech(input.text)); entrance=0; shown=true
        place(); scroll:SetVerticalScroll(0)
        top:SetHeight(.01); bottom:SetHeight(.01)
        for _, object in ipairs({name,title,zone,subzone,hint,crest,crestShadow,scroll,exit}) do object:SetAlpha(0) end
        root:Show(); root:EnableKeyboard(true); root:SetPropagateKeyboardInput(true)
        root:SetScript("OnUpdate",safe(update))
    end
    function handle.Hide()
        shown=false; root:SetScript("OnUpdate",nil); root:EnableKeyboard(false)
        root:SetPropagateKeyboardInput(true); root:Hide(); model,speech=nil,nil
    end
    function handle.Complete() if speech then line:SetText(speech.Complete()) end end
    function handle.IsTyping() return speech and not speech.IsComplete() or false end
    return handle
end
