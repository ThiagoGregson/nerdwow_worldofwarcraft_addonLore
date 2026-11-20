local _, addon = ...
local View = {}
addon.ConversationView = View
local CIRCLE="Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local handle,root,callbacks,shown,model,speech
local top,bottom,edgeLeft,edgeRight,crest,crestShadow,name,title,zone,subzone,hint,scroll,child,line,exit
local optionScroll,optionChild,more
local paragraphs,paragraphData={},{}
local buttons={}
local entrance,bottomHeight,layout=0,0,nil
local preparing,faulted=false,false
local waiting=false
local measures={}
local measureOrder={}
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
    local _,ready=addon.FontAPI.Apply(object,file,size)
    if not ready then error("font_pending",0) end
    object:SetShadowColor(0,0,0,.9)
    object:SetShadowOffset(0,-1)
end
local function dimensions() return addon.DiagnosticAPI.Dimensions(UIParent,root) end
local function safe(fn,stage)
    return function(...)
        local ok,value=addon.DiagnosticAPI.Try(fn,...)
        if not ok and callbacks then
            faulted=true
            pcall(callbacks.Error,value,stage or "view_callback",dimensions())
        end
        return ok and value
    end
end
local function texture(parent,layer)
    return parent:CreateTexture(nil,layer or "BACKGROUND")
end
local function label(parent)
    local result=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    result:SetJustifyH("LEFT"); result:SetJustifyV("TOP")
    result:SetWordWrap(true)
    return result
end
local function button(index)
    if buttons[index] then return buttons[index] end
    local b=CreateFrame("Button",nil,optionChild)
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
-- A medição tem uma região própria mostrada (alpha zero), nunca Hide().
local function textWidth(text,file,size)
    -- Never reuse a pending FontString for another font/size.
    local key=file..":"..string.format("%.9g",size)
    local meter=measures[key]
    if not meter then
        if #measureOrder>=128 then
            local oldKey=table.remove(measureOrder,1); meter=measures[oldKey]; measures[oldKey]=nil
        else
            meter=label(root); meter:SetSize(100000,1000); meter:SetPoint("TOPLEFT",root,"TOPLEFT",0,0)
            meter:SetWordWrap(false); meter:SetAlpha(0)
        end
        measures[key]=meter; measureOrder[#measureOrder+1]=key
    end
    font(meter,file,size)
    meter:SetText(text)
    local width=meter:GetUnboundedStringWidth()
    if type(width)=="number" and width>0 and width<math.huge then return width end
    local _,characters=text:gsub("[^\128-\191]","")
    return characters*size*.55
end
local function textHeight(object,text,file,size,width)
    font(object,file,size)
    object:SetWidth(width); object:SetHeight(100000); object:SetText(text); object:Show()
    local height=object:GetStringHeight()
    if type(height)~="number" or height<=0 or height==math.huge then
        local lines=0
        for part in (text.."\n"):gmatch("([^\n]*)\n") do
            lines=lines+math.max(1,math.ceil(textWidth(part,file,size)/width))
        end
        height=math.max(1,lines)*size*1.45
    end
    object:SetHeight(math.max(size*1.45,height)+2*layout.scale)
    return object:GetHeight()
end
local function fit(object,text,file,size,minimum,maximum)
    while size>minimum and textWidth(text,file,size)>maximum do size=math.max(minimum,size-layout.scale) end
    if textWidth(text,file,size)>maximum then
        local ends={}
        for index=1,#text do
            local nextByte=text:byte(index+1)
            if not nextByte or nextByte<128 or nextByte>=192 then ends[#ends+1]=index end
        end
        local low,high=0,#ends
        while low<high do
            local mid=math.ceil((low+high)/2)
            if textWidth(text:sub(1,ends[mid]).."...",file,size)<=maximum then low=mid else high=mid-1 end
        end
        text=text:sub(1,ends[low] or 0).."..."
    end
    object:SetWordWrap(false); object:SetNonSpaceWrap(false)
    -- Give the client the available box, not a tight natural-width box that can
    -- acquire an automatic ellipsis after glyph metrics or pixel rounding settle.
    local used=math.min(maximum,math.max(1,math.ceil(textWidth(text,file,size)+size*.15+4*layout.scale)))
    local height=textHeight(object,text,file,size,used)
    return used,height
end
local function reveal(text)
    for index,part in ipairs(paragraphData) do
        paragraphs[index]:SetText(text:sub(part.first,math.min(#text,part.last)))
    end
end
local function scrollHint()
    local range=scroll:GetVerticalScrollRange()
    more:SetText(range>0 and (scroll:GetVerticalScroll()<range-1 and addon.Text.cinemaMore or addon.Text.cinemaPrevious) or "")
end
local function place()
    if not shown or not model then return end
    local viewport=dimensions()
    local width,height=viewport.viewportWidth,viewport.viewportHeight
    layout=addon.Conversation.Layout(width,height)
    if not layout then return false end
    local s=layout.scale
    layout=addon.Conversation.Layout(width,height,textWidth(addon.Conversation.LINE_SAMPLE,"EBGaramond-Regular",layout.speechSize))
    local widthText,left=layout.textWidth,layout.textLeft
    local titleText=model.npc and model.npc.title or ""
    local titleSpace=titleText~="" and math.min(widthText*.36,textWidth(titleText,"EBGaramond-Italic",17*s)+14*s) or 0
    name:ClearAllPoints(); name:SetPoint("TOPLEFT",root,"BOTTOMLEFT",left,layout.bottom-18*s)
    local nameWidth,nameHeight=fit(name,model.npc and model.npc.name or addon.Text.cinemaUnknownNPC,
        "Cinzel-Bold",layout.nameSize,14*s,widthText-titleSpace)
    color(name,model.theme.glow)
    title:ClearAllPoints(); title:SetPoint("TOPLEFT",name,"TOPRIGHT",14*s,-3*s)
    local _,titleHeight=fit(title,titleText,"EBGaramond-Italic",17*s,13*s,math.max(1,widthText-nameWidth-14*s))
    color(title,model.theme.muted)
    local header=math.max(nameHeight,titleText~="" and titleHeight+3*s or 0)
    zone:ClearAllPoints(); zone:SetPoint("TOP",root,"TOP",0,-6*s)
    local zoneWidth=fit(zone,model.location and model.location.zone or addon.Text.cinemaUnknownLocation,
        "Cinzel-Regular",layout.zoneSize,12*s,width*.4)
    color(zone,model.theme.glow,.85); zone:SetJustifyH("CENTER")
    subzone:ClearAllPoints(); subzone:SetPoint("TOP",zone,"BOTTOM",0,-1*s)
    local subzoneText=model.location and model.location.subZone or ""
    local subzoneWidth=fit(subzone,subzoneText,"EBGaramond-Regular",13*s,11*s,width*.3)
    color(subzone,model.theme.muted); subzone:SetJustifyH("CENTER")
    local zoneGroup=zoneWidth+(subzoneText~="" and subzoneWidth+12*s or 0)
    zone:ClearAllPoints(); zone:SetPoint("TOPLEFT",root,"TOPLEFT",(width-zoneGroup)/2,-6*s)
    subzone:ClearAllPoints(); subzone:SetPoint("TOPLEFT",zone,"TOPRIGHT",12*s,-3*s)
    hint:ClearAllPoints(); hint:SetPoint("TOPRIGHT",root,"TOPRIGHT",-48*s,-layout.top+17*s)
    local _,hintHeight=fit(hint,addon.Text.cinemaHint,"EBGaramond-Regular",12*s,10*s,width*.65)
    hint:ClearAllPoints(); hint:SetPoint("TOPRIGHT",root,"TOPRIGHT",-48*s,-layout.top+hintHeight+4*s)
    color(hint,model.theme.muted,.8)
    font(exit.label,"Cinzel-Regular",24*s); color(exit.label,model.theme.muted)
    exit:SetSize(28*s,28*s); exit:ClearAllPoints(); exit:SetPoint("TOPRIGHT",root,"TOPRIGHT",-14*s,-6*s)
    exit.label:SetWordWrap(false)
    scroll:SetWidth(widthText); child:SetWidth(widthText)
    optionScroll:SetWidth(widthText); optionChild:SetWidth(widthText)
    paragraphData=addon.Conversation.Paragraphs(model.text)
    local speechHeight=0
    for index,part in ipairs(paragraphData) do
        local object=paragraphs[index]
        if not object then object=label(child); paragraphs[index]=object end
        object:SetWordWrap(true); object:SetNonSpaceWrap(true); object:SetSpacing(3*s)
        object:ClearAllPoints(); object:SetPoint("TOPLEFT",child,"TOPLEFT",0,-speechHeight)
        color(object,model.theme.subtitle)
        speechHeight=speechHeight+textHeight(object,part.text,"EBGaramond-Regular",layout.speechSize,widthText)
        if index<#paragraphData then speechHeight=speechHeight+layout.speechSize*.32 end
    end
    for index=#paragraphData+1,#paragraphs do paragraphs[index]:Hide() end
    child:SetHeight(math.max(1,speechHeight))
    local x,y,rowHeight=0,0,0
    for index,entry in ipairs(model.entries) do
        local b=button(index); b.entry=entry; b:Show()
        local tokenCallbacks=callbacks
        b:SetScript("OnClick",safe(function() tokenCallbacks.Choose(index) end))
        local text=entry.text and entry.text:find("%S") and entry.text or addon.Text.cinemaUnknownOption
        local numberSize=layout.optionSize*.78
        local diameter=numberSize*1.6
        local labelLeft=diameter+28*s
        local itemWidth=math.min(widthText,math.max(110*s,textWidth(text,"EBGaramond-Regular",layout.optionSize)+labelLeft+12*s))
        if x>0 and x+itemWidth>widthText then x=0; y=y-rowHeight-7*s; rowHeight=0 end
        b:ClearAllPoints(); b:SetPoint("TOPLEFT",optionChild,"TOPLEFT",x,y)
        b.label:ClearAllPoints(); b.label:SetPoint("TOPLEFT",b,"TOPLEFT",labelLeft,-3*s)
        b.label:SetWordWrap(true); b.label:SetNonSpaceWrap(true)
        color(b.label,entry.enabled and model.theme.option or model.theme.muted,entry.enabled and 1 or .6)
        local itemHeight=math.max(diameter+8*s,textHeight(b.label,text,"EBGaramond-Regular",layout.optionSize,itemWidth-labelLeft-6*s)+8*s)
        b:SetSize(itemWidth,itemHeight)
        for _,circle in ipairs({b.ring,b.fill}) do circle:ClearAllPoints(); circle:SetPoint("TOPLEFT",b,"TOPLEFT",0,-4*s) end
        b.ring:SetSize(diameter,diameter); tint(b.ring,model.theme.accent,.75)
        b.fill:SetSize(diameter-2*s,diameter-2*s); b.fill:ClearAllPoints(); b.fill:SetPoint("CENTER",b.ring,"CENTER",0,0)
        tint(b.fill,model.theme.night)
        font(b.number,"Cinzel-Regular",numberSize); color(b.number,model.theme.accent)
        b.number:SetWordWrap(false); b.number:SetText(tostring(index)); b.number:SetJustifyH("CENTER"); b.number:SetJustifyV("MIDDLE")
        b.number:ClearAllPoints(); b.number:SetPoint("CENTER",b.ring,"CENTER",0,0); b.number:SetSize(diameter,diameter)
        b.icon:ClearAllPoints(); b.icon:SetPoint("TOPLEFT",b,"TOPLEFT",diameter+8*s,-6*s); b.icon:SetSize(16*s,16*s)
        b.symbol:ClearAllPoints(); b.symbol:SetPoint("TOPLEFT",b,"TOPLEFT",diameter+8*s,-4*s); b.symbol:SetSize(20*s,26*s)
        font(b.symbol,"Cinzel-Bold",18*s); b.symbol:SetWordWrap(false)
        color(b.symbol,entry.kind=="active" and model.theme.muted or model.theme.secondary)
        if entry.kind=="conversation" and entry.icon then
            b.icon:SetTexture(entry.icon); b.icon:Show(); b.symbol:Hide()
        else
            b.icon:Hide(); b.symbol:Show()
            b.symbol:SetText(entry.kind=="available" and "!" or entry.kind=="conversation" and "·" or "?")
        end
        b:SetEnabled(entry.enabled); b:SetAlpha(1); b.light:SetAlpha(0)
        rowHeight=math.max(rowHeight,itemHeight); x=x+itemWidth+18*s
    end
    for index=#model.entries+1,#buttons do buttons[index]:Hide() end
    local optionHeight=#model.entries>0 and -y+rowHeight+2*s or 0
    optionChild:SetHeight(math.max(1,optionHeight))
    local boxes=addon.Conversation.Arrange(layout,header,speechHeight,optionHeight)
    bottomHeight=boxes.bottom
    name:ClearAllPoints(); name:SetPoint("TOPLEFT",root,"BOTTOMLEFT",left,boxes.headerTop)
    scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT",root,"BOTTOMLEFT",left,boxes.speechTop)
    scroll:SetHeight(boxes.speechHeight)
    optionScroll:ClearAllPoints(); optionScroll:SetPoint("BOTTOMLEFT",root,"BOTTOMLEFT",left,boxes.optionBottom)
    optionScroll:SetHeight(boxes.optionHeight)
    more:ClearAllPoints(); more:SetPoint("TOPLEFT",root,"BOTTOMLEFT",left,boxes.speechBottom-2*s)
    font(more,"EBGaramond-Regular",12*s); color(more,model.theme.muted,.8)
    more:SetSize(widthText,14*s); more:SetWordWrap(false)
    scroll:UpdateScrollChildRect(); optionScroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(),scroll:GetVerticalScrollRange()))
    optionScroll:SetVerticalScroll(math.min(optionScroll:GetVerticalScroll(),optionScroll:GetVerticalScrollRange()))
    scrollHint()
    local r,g,b=rgb(model.theme.night)
    top:SetColorTexture(r,g,b,1); bottom:SetColorTexture(r,g,b,1)
    local ar,ag,ab=rgb(model.theme.accent)
    edgeLeft:SetGradient("HORIZONTAL",CreateColor(ar,ag,ab,0),CreateColor(ar,ag,ab,.6))
    edgeRight:SetGradient("HORIZONTAL",CreateColor(ar,ag,ab,.6),CreateColor(ar,ag,ab,0))
    for _,edge in ipairs({edgeLeft,edgeRight}) do edge:SetSize(width/2,1) end
    crest:SetTexture(model.theme.crest); crestShadow:SetTexture(model.theme.crest)
    crest:SetSize(56*s,56*s); crestShadow:SetSize(58*s,58*s)
    crest:ClearAllPoints(); crest:SetPoint("TOPLEFT",root,"BOTTOMLEFT",left-84*s,boxes.headerTop)
    crestShadow:ClearAllPoints(); crestShadow:SetPoint("CENTER",crest,"CENTER",0,-2*s)
    crestShadow:SetVertexColor(0,0,0,.65); crest:SetVertexColor(1,1,1,1)
    reveal(speech.GetText())
    local eased=1-(1-math.min(1,entrance/.9))^3
    top:SetHeight(math.max(.01,layout.top*eased)); bottom:SetHeight(math.max(.01,bottomHeight*eased))
    return true
end
local function arrange()
    local ok,value=addon.DiagnosticAPI.Try(place)
    -- A partially prepared layout must never reveal the full typewriter text.
    if speech then reveal(speech.GetText()) end
    if ok then return value end
    if value.message=="font_pending" then return false,"font_pending" end
    addon.DiagnosticAPI.Raise(value,"interface_error")
end
local function update(_,delta)
    if entrance<.9 then
        entrance=math.min(.9,entrance+delta)
        local t=entrance/.9
        local eased=1-(1-t)^3
        top:SetHeight(math.max(.01,layout.top*eased)); bottom:SetHeight(math.max(.01,bottomHeight*eased))
        for _, object in ipairs({name,title,zone,subzone,hint,crest,crestShadow,scroll,optionScroll,more,exit}) do object:SetAlpha(eased) end
    end
    local text,changed=speech.Advance(delta)
    if changed then reveal(text) end
    if entrance==.9 and speech.IsComplete() then root:SetScript("OnUpdate",nil) end
end
function View.New(newCallbacks)
    callbacks=newCallbacks
    if handle then return handle end
    root=CreateFrame("Frame",nil,UIParent); root:Hide(); root:SetAllPoints(UIParent)
    addon.FontAPI.Watch(safe(function()
        if preparing then return end
        if waiting then waiting=false; if callbacks.Ready then callbacks.Ready() end
        elseif shown and model then
            local ready,code=arrange()
            if ready==false and code~="font_pending" then error("layout_unavailable") end
        end
    end,"font_ready"))
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
        scrollHint()
    end))
    line=label(child); paragraphs[1]=line
    optionScroll=CreateFrame("ScrollFrame",nil,root); optionChild=CreateFrame("Frame",nil,optionScroll)
    optionScroll:SetScrollChild(optionChild); optionScroll:EnableMouseWheel(true)
    optionScroll:SetScript("OnMouseWheel",safe(function(_,delta)
        optionScroll:SetVerticalScroll(math.max(0,math.min(optionScroll:GetVerticalScrollRange(),optionScroll:GetVerticalScroll()-delta*42*layout.scale)))
    end))
    more=label(root)
    exit=CreateFrame("Button",nil,root); exit.label=label(exit); exit.label:SetAllPoints(); exit.label:SetJustifyH("CENTER")
    exit.label:SetText("×"); exit:SetScript("OnClick",safe(function() callbacks.Close() end))
    exit:SetScript("OnEnter",safe(function() color(exit.label,"ffffff") end))
    exit:SetScript("OnLeave",safe(function() if model then color(exit.label,model.theme.muted) end end))
    root:SetScript("OnKeyDown",safe(function(_,key)
        root:SetPropagateKeyboardInput(true)
        if shown and addon.ConversationPlatform.KeyAllowed() and callbacks.Key(key) then root:SetPropagateKeyboardInput(false) end
    end))
    root:SetScript("OnKeyUp",safe(function() root:SetPropagateKeyboardInput(true) end))
    root:SetScript("OnSizeChanged",safe(function()
        if not preparing and shown then
            local ready,code=arrange()
            if ready==false and code~="font_pending" then error("layout_unavailable") end
        end
    end,"OnSizeChanged"))
    root:SetScript("OnShow",safe(function()
        if shown and model and not preparing then
            local ready,code=arrange()
            if ready==false and code~="font_pending" then error("layout_unavailable") end
            root:EnableKeyboard(true)
            if entrance<.9 or not speech.IsComplete() then root:SetScript("OnUpdate",safe(update)) end
        end
    end,"OnShow"))
    root:SetScript("OnHide",safe(function() root:SetScript("OnUpdate",nil); root:EnableKeyboard(false) end,"OnHide"))
    handle={}
    function handle.Show(input,retryFonts)
        faulted=false; preparing=false; waiting=false
        if retryFonts~=false then addon.FontAPI.Retry() end
        model=input; speech=assert(addon.Conversation.NewSpeech(input.text)); entrance=0
        local viewport=dimensions()
        local initial=addon.Conversation.Layout(viewport.viewportWidth,viewport.viewportHeight)
        if not initial then
            shown=false; root:Hide(); return false,"layout_pending",viewport
        end
        local s=initial.scale
        -- Start the sizes needed by this layout together, so a missing asset has
        -- one verification window instead of a separate wait for every label.
        for _,request in ipairs({{"Cinzel-Bold",initial.nameSize},{"EBGaramond-Italic",17*s},
            {"Cinzel-Regular",initial.zoneSize},{"EBGaramond-Regular",13*s},{"EBGaramond-Regular",12*s},
            {"Cinzel-Regular",24*s},{"EBGaramond-Regular",initial.speechSize},
            {"EBGaramond-Regular",initial.optionSize},{"Cinzel-Regular",initial.optionSize*.78},
            {"Cinzel-Bold",18*s}}) do addon.FontAPI.Prepare(request[1],request[2]) end
        shown=true; preparing=true
        root:SetAlpha(0); root:Show(); preparing=false
        if faulted or not shown then return false,"view_failed",dimensions() end
        local ready,code=arrange()
        if not ready then
            waiting=code=="font_pending"
            shown=false; root:Hide()
            return false,code or "layout_pending",dimensions()
        end
        scroll:SetVerticalScroll(0)
        optionScroll:SetVerticalScroll(0); scrollHint()
        top:SetHeight(.01); bottom:SetHeight(.01)
        for _, object in ipairs({name,title,zone,subzone,hint,crest,crestShadow,scroll,optionScroll,more,exit}) do object:SetAlpha(0) end
        if faulted or not shown then return false,"view_failed",dimensions() end
        root:EnableKeyboard(true); root:SetPropagateKeyboardInput(true); root:SetAlpha(1)
        root:SetScript("OnUpdate",safe(update,"OnUpdate"))
        return true,nil,dimensions()
    end
    function handle.Hide()
        shown=false; preparing=false; waiting=false; root:SetScript("OnUpdate",nil); root:EnableKeyboard(false)
        root:SetPropagateKeyboardInput(true); root:Hide(); model,speech=nil,nil
    end
    function handle.Complete() if speech then reveal(speech.Complete()) end end
    function handle.IsTyping() return speech and not speech.IsComplete() or false end
    return handle
end
