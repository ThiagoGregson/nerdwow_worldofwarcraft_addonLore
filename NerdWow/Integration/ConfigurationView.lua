local _,addon=...
local View={}
addon.ConfigurationView=View
local CIRCLE="Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"
local function rgb(hex) return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255 end
local function paint(object,hex,alpha) local r,g,b=rgb(hex); object:SetColorTexture(r,g,b,alpha or 1) end
local function ink(object,hex,alpha) local r,g,b=rgb(hex); object:SetTextColor(r,g,b,alpha or 1) end
local function solid(parent,hex,alpha,layer)
    local t=parent:CreateTexture(nil,layer or "BACKGROUND"); paint(t,hex,alpha); return t
end
local function circle(parent,hex,alpha)
    local t=parent:CreateTexture(nil,"ARTWORK"); t:SetTexture(CIRCLE)
    local r,g,b=rgb(hex); t:SetVertexColor(r,g,b,alpha or 1); return t
end
local function gradient(parent,orientation,from,to)
    local t=solid(parent,"ffffff")
    t:SetGradient(orientation,CreateColor(unpack(from)),CreateColor(unpack(to))); return t
end
local function label(parent)
    local l=parent:CreateFontString(nil,"OVERLAY","GameFontNormal")
    l:SetJustifyH("LEFT"); l:SetJustifyV("TOP"); l:SetWordWrap(true); l:SetNonSpaceWrap(true); return l
end
local function display(value)
    if value==nil then return addon.Text.unavailable end
    return tostring(value)
end
function View.New(callbacks)
    local v,layout,snapshot,theme,t={},nil,nil,nil,nil
    local elapsed,pending,rendering=0,false,false
    local root=CreateFrame("Frame",nil,UIParent); root:Hide(); root:SetAllPoints(UIParent)
    root:SetFrameStrata("DIALOG"); root:EnableMouse(true); root:EnableKeyboard(false); root:SetPropagateKeyboardInput(true)
    local shade=solid(root,"07060a",.55); shade:SetAllPoints()
    local cover=CreateFrame("Frame",nil,root)
    local shadows={}
    for i=1,4 do shadows[i]=solid(cover,"000000",.09); shadows[i]:SetPoint("CENTER",cover,"CENTER",0,-i*4) end
    local leather=gradient(cover,"VERTICAL",{.12,.067,.043,1},{.23,.133,.086,1}); leather:SetAllPoints()
    local edges={}; for i=1,4 do edges[i]=solid(cover,"c9a15a",.35,"BORDER") end
    local left=CreateFrame("Frame",nil,cover); local right=CreateFrame("Frame",nil,cover)
    local paperLeft=solid(left,"e8d8b4"); paperLeft:SetAllPoints()
    local paperRight=gradient(right,"VERTICAL",{.85,.75,.57,1},{.91,.85,.71,1}); paperRight:SetAllPoints()
    local grain={}
    for i,page in ipairs({left,right}) do
        local t=page:CreateTexture(nil,"BACKGROUND")
        if type(C_Texture)=="table" and type(C_Texture.GetAtlasInfo)=="function" and C_Texture.GetAtlasInfo("QuestBG-Parchment") then
            t:SetAtlas("QuestBG-Parchment"); t:SetAllPoints(); t:SetAlpha(.23)
        end
        grain[i]=t
    end
    local spineLeft=gradient(left,"HORIZONTAL",{.31,.19,.08,0},{.31,.19,.08,.34})
    local spineRight=gradient(right,"HORIZONTAL",{.31,.19,.08,.34},{.31,.19,.08,0})
    local contents=CreateFrame("Frame",nil,cover); contents:SetAllPoints()
    local ornaments=CreateFrame("Frame",nil,cover); ornaments:SetAllPoints(); ornaments:EnableMouse(false)
    ornaments:SetFrameLevel(contents:GetFrameLevel()+5)
    local ribbon=solid(ornaments,"2d4f86",1,"OVERLAY"); local ribbonTips={}
    for i=1,30 do ribbonTips[i]=solid(ornaments,"2d4f86",1,"OVERLAY") end
    local headings={brand=label(contents),subtitle=label(contents)}
    local emblem=contents:CreateTexture(nil,"ARTWORK"); emblem:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    local rules={solid(contents,"70412a",.5),solid(contents,"70412a",.5),solid(contents,"70412a",.5)}
    rules[3]:SetRotation(math.pi/4)
    local indexScroll=CreateFrame("ScrollFrame",nil,contents); local indexChild=CreateFrame("Frame",nil,indexScroll)
    indexScroll:SetScrollChild(indexChild); indexScroll:EnableMouseWheel(true)
    indexChild:SetPoint("TOPLEFT",indexScroll,"TOPLEFT",0,0)
    local indexNote=label(contents)
    headings.kicker=label(contents); headings.title=label(contents); headings.lead=label(contents)
    local optionScroll=CreateFrame("ScrollFrame",nil,contents); local child=CreateFrame("Frame",nil,optionScroll)
    optionScroll:SetScrollChild(child); optionScroll:EnableMouseWheel(true); optionScroll:EnableMouse(true)
    child:SetPoint("TOPLEFT",optionScroll,"TOPLEFT",0,0)
    local scrollTrack,scrollThumb=solid(contents,"70412a",.12),solid(contents,"70412a",.5)
    local footer=CreateFrame("Frame",nil,contents); local footerRule=solid(footer,"70412a",.22)
    footerRule:SetPoint("TOPLEFT"); footerRule:SetPoint("TOPRIGHT")
    local saved=label(footer)
    local waiting=CreateFrame("Frame",nil,cover); waiting:SetAllPoints(); waiting:EnableMouse(true)
    waiting:SetFrameLevel(contents:GetFrameLevel()+40); waiting:Hide()
    local loading=label(waiting); loading:SetPoint("CENTER",cover,"CENTER",70,0)
    loading:SetSize(340,40); loading:SetJustifyH("CENTER"); loading:SetText(addon.Text.configLoading)
    local nav,rows={},{}
    local menu=CreateFrame("Frame",nil,contents); menu:Hide(); menu:SetFrameLevel(contents:GetFrameLevel()+20)
    local menuFill=solid(menu,"e8d8b4"); menuFill:SetAllPoints(); local choices={}
    local confirm=CreateFrame("Frame",nil,cover); confirm:SetAllPoints(); confirm:Hide(); confirm:EnableMouse(true)
    confirm:SetFrameLevel(contents:GetFrameLevel()+30)
    local confirmShade=solid(confirm,"07060a",.65); confirmShade:SetAllPoints()
    local confirmPaper=CreateFrame("Frame",nil,confirm)
    local confirmBase=solid(confirmPaper,"e8d8b4"); confirmBase:SetAllPoints()
    local confirmTitle,confirmText=label(confirmPaper),label(confirmPaper)
    local confirmation
    local function safe(fn,stage)
        return function(...)
            local ok,a,b=addon.DiagnosticAPI.Try(fn,...)
            if not ok then callbacks.Error(a,stage or "configuration_callback"); return end
            return a,b
        end
    end
    local function font(object,file,size,hex)
        local _,ready=addon.FontAPI.Apply(object,file,size)
        if not ready then error("font_pending",0) end
        if hex then ink(object,hex) end
        object:SetShadowOffset(0,0)
    end
    local function text(object,value,file,size,width)
        if value==nil or value=="" then object:SetText(""); object:Hide(); return 0 end
        font(object,file,size)
        object:SetSpacing(t.gap)
        object:SetWidth(width); object:SetHeight(100000); object:Show()
        object:SetText(addon.Conversation.LINE_SAMPLE)
        width=math.min(width,object:GetUnboundedStringWidth())
        object:SetWidth(width); object:SetHeight(100000); object:SetText(value or ""); object:Show()
        local height=object:GetStringHeight()
        if issecretvalue and issecretvalue(height) or type(height)~="number" or height<=0 or height>=math.huge then error("layout_unavailable") end
        object:SetHeight(height); return height
    end
    local function anchor(object,parent,x,y,width,height)
        object:ClearAllPoints(); object:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
        if width then object:SetSize(width,height) end
    end
    local function scrollbar()
        if not layout then return end
        local range=optionScroll:GetVerticalScrollRange(); local h=optionScroll:GetHeight()
        local thumb=math.max(20*layout.scale,h*h/(h+range))
        scrollTrack:SetAlpha(range>1 and 1 or 0); scrollThumb:SetAlpha(range>1 and 1 or 0)
        scrollThumb:SetHeight(thumb)
        anchor(scrollThumb,scrollTrack,0,(range>0 and optionScroll:GetVerticalScroll()/range or 0)*(h-thumb))
    end
    local function wheel(frame,delta)
        frame:SetVerticalScroll(math.max(0,math.min(frame:GetVerticalScrollRange(),frame:GetVerticalScroll()-delta*38*layout.scale)))
        scrollbar()
    end
    indexScroll:SetScript("OnMouseWheel",safe(wheel)); optionScroll:SetScript("OnMouseWheel",safe(wheel))
    local function feedback(frame,owner)
        if frame.feedback then return end
        local f={fill=solid(frame,"70412a",0,"BORDER"),marker=solid(frame,"70412a",0,"OVERLAY")}
        frame.feedback=f
        f.fill:SetPoint("TOPLEFT",frame,"TOPLEFT",0,0); f.fill:SetPoint("BOTTOMRIGHT",frame,"BOTTOMRIGHT",0,0)
        function frame.RefreshFeedback()
            if not layout or not theme then return end
            local active=f.hover or f.focus or f.childHover or f.childFocus
            local alpha=active and (f.selected and .32 or .24) or 0
            if frame.allowed==false then alpha=alpha*.45 end
            paint(f.fill,f.primary and theme.secondary or theme.seal,alpha)
            paint(f.marker,f.primary and "f7ecd4" or theme.seal,active and .95 or 0)
            local x=-5*layout.scale
            if frame:GetObjectType()=="Frame" or f.selected~=nil then x=0 end
            f.marker:ClearAllPoints(); f.marker:SetPoint("TOPLEFT",frame,"TOPLEFT",x,0)
            f.marker:SetSize((f.selected and 5 or 3)*layout.scale,frame:GetHeight())
        end
        local function hook(event,callback)
            local previous=frame:GetScript(event)
            frame:SetScript(event,safe(function(...)
                if previous then previous(...) end
                callback()
            end,"configuration_feedback"))
        end
        local function update(field,value)
            f[field]=value; frame.RefreshFeedback()
            if owner then
                local key=field=="hover" and "childHover" or "childFocus"
                if value then owner.feedback[key]=frame
                elseif owner.feedback[key]==frame then owner.feedback[key]=nil end
                owner.RefreshFeedback()
            end
        end
        hook("OnEnter",function() update("hover",true) end)
        hook("OnLeave",function() update("hover",false) end)
        hook("OnHide",function() update("hover",false); update("focus",false) end)
        if frame:GetObjectType()=="EditBox" then
            hook("OnEditFocusGained",function() update("focus",true) end)
            hook("OnEditFocusLost",function() update("focus",false) end)
        else
            hook("OnMouseDown",function() update("focus",true) end)
            hook("OnMouseUp",function() update("focus",false) end)
        end
    end
    local function button(parent)
        local b=CreateFrame("Button",nil,parent); b:RegisterForClicks("LeftButtonUp")
        b.fill=solid(b,"70412a",.07); b.fill:SetAllPoints()
        b.edges={}; for i=1,4 do b.edges[i]=solid(b,"70412a",.5,"BORDER") end
        b.label=label(b); b.label:SetAllPoints(); b.label:SetJustifyH("CENTER"); b.label:SetJustifyV("MIDDLE"); b.label:SetWordWrap(false)
        return b
    end
    local function formatButton(b,caption,width,height,primary)
        local s=layout.scale
        b:SetSize(width,height); b.label:SetText(caption)
        font(b.label,"Cinzel-Bold",t.heading,primary and "f7ecd4" or "2a1d12")
        width=math.max(width,b.label:GetUnboundedStringWidth()+16*t.unit)
        height=math.max(height,t.heading*1.6+8*t.unit)
        b:SetSize(width,height)
        paint(b.fill,theme.seal,primary and 1 or .04)
        local w,h=width,height
        for _,t in ipairs(b.edges) do paint(t,theme.seal,.65); t:ClearAllPoints() end
        b.edges[1]:SetPoint("TOPLEFT"); b.edges[1]:SetSize(w,s)
        b.edges[2]:SetPoint("BOTTOMLEFT"); b.edges[2]:SetSize(w,s)
        b.edges[3]:SetPoint("TOPLEFT"); b.edges[3]:SetSize(s,h)
        b.edges[4]:SetPoint("TOPRIGHT"); b.edges[4]:SetSize(s,h)
        feedback(b); b.feedback.primary=primary; b.RefreshFeedback()
    end
    local restore,close=button(footer),button(footer)
    restore:SetScript("OnClick",safe(function() callbacks.Reset() end))
    close:SetScript("OnClick",safe(callbacks.Close))
    local accept,cancel=button(confirmPaper),button(confirmPaper)
    accept:SetScript("OnClick",safe(function()
        local callback=confirmation; confirmation=nil; confirm:Hide()
        if callback then callback() end
    end,"configuration_reset"))
    cancel:SetScript("OnClick",safe(function() confirmation=nil; confirm:Hide() end))
    local xClose=button(contents); xClose:SetScript("OnClick",safe(callbacks.Close))
    local function row(index)
        local row=rows[index]; if row then return row end
        row=CreateFrame("Frame",nil,child); row.title=label(row); row.description=label(row)
        row.rule=solid(row,"70412a",.16); row.rule:SetPoint("BOTTOMLEFT"); row.rule:SetPoint("BOTTOMRIGHT")
        row.value=label(row); row.badge=label(row)
        row:EnableMouse(true); feedback(row)
        rows[index]=row; return row
    end
    local controls={}
    controls.switch=function(row)
        local b=CreateFrame("Button",nil,row); b:RegisterForClicks("LeftButtonUp")
        b.track=solid(b,"70412a",.2); b.ends={circle(b,"70412a",.2),circle(b,"70412a",.2)}
        b.wax=circle(b,"e8d8b4"); b.rim=circle(b,"70412a",.25); b.glow=circle(b,"f7ecd4",.28)
        b:SetScript("OnClick",safe(function() if row.spec.enabled then menu:Hide(); callbacks.Write(row.spec.id,not row.spec.value) end end))
        return b
    end
    controls.slider=function(row)
        local f=CreateFrame("Slider",nil,row); f:SetOrientation("HORIZONTAL"); f:EnableMouse(true)
        f.track=solid(f,"70412a",.3); f.fill=solid(f,"2d4f86")
        f.thumb=solid(f,"9e2a35",1,"OVERLAY"); f.thumb:SetRotation(math.pi/4); f:SetThumbTexture(f.thumb)
        f.output=label(f)
        f:SetScript("OnValueChanged",safe(function(_,value)
            if rendering or not row.spec.enabled then return end
            local d=row.spec.definition; local step=d.step or 1
            value=math.max(d.min,math.min(d.max,d.min+math.floor((value-d.min)/step+.5)*step))
            callbacks.Write(row.spec.id,value)
        end))
        return f
    end
    controls.select=function(row)
        local b=button(row)
        b.arrow=b:CreateTexture(nil,"OVERLAY"); b.arrow:SetTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        b:SetScript("OnClick",safe(function()
            if not row.spec.enabled then return end
            local values=row.spec.definition.values
            menu:ClearAllPoints(); menu:SetPoint("TOPRIGHT",b,"BOTTOMRIGHT",0,-2*layout.scale)
            menu:SetSize(b:GetWidth(),#values*29*layout.scale); menu:Show()
            for i,choice in ipairs(values) do
                local item=choices[i]
                if not item then item=button(menu); choices[i]=item end
                item:Show(); anchor(item,menu,0,(i-1)*29*layout.scale)
                formatButton(item,choice.text,b:GetWidth(),29*layout.scale,false)
                local value,id=choice.value,row.spec.id
                item:SetScript("OnClick",safe(function() menu:Hide(); callbacks.Write(id,value) end))
            end
            for i=#values+1,#choices do choices[i]:Hide() end
        end))
        return b
    end
    controls.text=function(row)
        local edit=CreateFrame("EditBox",nil,row)
        edit:SetAutoFocus(false); edit:SetMultiLine(false); edit:EnableMouse(true)
        edit.line=solid(edit,"70412a",.5); edit.line:SetPoint("BOTTOMLEFT"); edit.line:SetPoint("BOTTOMRIGHT")
        edit:SetScript("OnEditFocusGained",function(self) menu:Hide(); self:HighlightText() end)
        edit:SetScript("OnEscapePressed",safe(callbacks.Close))
        edit:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
        edit:SetScript("OnTextChanged",safe(function(self,userInput)
            if rendering or not userInput then return end
            if row.spec.readOnly then self:SetText(tostring(row.spec.value or "")); self:HighlightText(); return end
            local ok=callbacks.Write(row.spec.id,self:GetText())
            if not ok then saved:SetText(addon.Text.configInvalid) end
        end))
        return edit
    end
    controls.action=function(row)
        local b=button(row)
        b:SetScript("OnClick",safe(function() if row.spec.enabled then callbacks.Action(row.spec.id) end end))
        return b
    end
    local function control(row)
        row.widgets=row.widgets or {}
        local kind=row.spec.kind
        for key,widget in pairs(row.widgets) do if key~=kind then widget:Hide() end end
        if not controls[kind] then return end
        local w=row.widgets[kind]
        if not w then w=controls[kind](row); feedback(w,row); row.widgets[kind]=w end
        w:Show(); return w
    end
    local function arrangeControl(row,b,width,height)
        local spec,s=row.spec,t.unit
        b:SetSize(width,height)
        local enabled=spec.enabled or spec.kind=="text" and spec.readOnly and not spec.soon
        if spec.kind=="text" or spec.kind=="slider" then
            if enabled then b:Enable() else b:Disable() end
        else b:SetEnabled(enabled) end
        b.allowed=enabled; b:SetAlpha(spec.soon and .5 or 1)
        if spec.kind=="switch" then
            b:SetSize(54*s,26*s)
            anchor(b.track,b,13*s,1*s,28*s,24*s)
            for i,t in ipairs(b.ends) do anchor(t,b,(i-1)*28*s,s,26*s,24*s) end
            local tr,tg,tb=rgb(spec.value and theme.seal or "70412a")
            tr,tg,tb=.82*.91+.18*tr,.82*.85+.18*tg,.82*.71+.18*tb
            b.track:SetColorTexture(tr,tg,tb,1)
            for _,t in ipairs(b.ends) do t:SetVertexColor(tr,tg,tb,1) end
            anchor(b.rim,b,(spec.value and 30 or 2)*s,2*s,22*s,22*s)
            anchor(b.wax,b,(spec.value and 31 or 3)*s,3*s,20*s,20*s)
            local r,g,blue=rgb(spec.value and theme.seal or "b7a27c"); b.wax:SetVertexColor(r,g,blue,1)
            anchor(b.glow,b,(spec.value and 34 or 6)*s,5*s,9*s,6*s)
        elseif spec.kind=="slider" then
            local d=spec.definition
            b:SetWidth(width-60*s); b:SetMinMaxValues(d.min,d.max); b:SetValueStep(d.step or 1); b:SetObeyStepOnDrag(true)
            b:SetValue(spec.value)
            anchor(b.track,b,0,height/2,b:GetWidth(),2*s)
            anchor(b.fill,b,0,height/2,b:GetWidth()*(spec.value-d.min)/(d.max-d.min),2*s)
            paint(b.fill,theme.seal); paint(b.thumb,theme.secondary)
            b.thumb:SetSize(12*s,12*s)
            anchor(b.output,b,b:GetWidth()+10*s,4*s,50*s,math.max(22*s,t.heading*1.5))
            font(b.output,"Cinzel-Regular",t.heading,"2a1d12"); b.output:SetText(tostring(spec.value)..(spec.suffix or "")); b.output:SetJustifyH("RIGHT")
        elseif spec.kind=="select" then
            local caption=""
            for _,choice in ipairs(spec.definition.values) do if choice.value==spec.value then caption=choice.text end end
            font(b.label,"EBGaramond-Regular",t.body,"2a1d12"); b.label:SetText(caption)
            b.label:SetJustifyH("LEFT"); paint(b.fill,"70412a",0)
            b.arrow:ClearAllPoints(); b.arrow:SetPoint("RIGHT",b,"RIGHT",0,0); b.arrow:SetSize(22*s,22*s)
            for _,edge in ipairs(b.edges) do edge:Hide() end
            b.edges[2]:Show(); b.edges[2]:ClearAllPoints(); b.edges[2]:SetPoint("BOTTOMLEFT"); b.edges[2]:SetSize(width,s)
        elseif spec.kind=="text" then
            font(b,"EBGaramond-Regular",t.body,"2a1d12"); b:SetMaxLetters(spec.definition.maxLength or 512)
            if not b:HasFocus() then b:SetText(tostring(spec.value or spec.placeholder or "")); b:SetCursorPosition(0) end
            b.line:SetHeight(s)
            if spec.soon and (spec.value==nil or spec.value=="") then b:SetText(spec.placeholder or "") end
        elseif spec.kind=="action" then formatButton(b,spec.button or spec.title,width,height,spec.primary); b:SetAlpha(spec.enabled and 1 or .4) end
        b.RefreshFeedback()
    end
    local function render()
        local dimensions=addon.DiagnosticAPI.Dimensions(UIParent,root)
        layout=assert(addon.ConfigurationBook.Layout(dimensions.viewportWidth,dimensions.viewportHeight),"layout_unavailable")
        t=addon.FontAPI.Scale(snapshot.textSize)
        local s=layout.scale; local w,h,lw,rw=layout.width,layout.height,layout.left,layout.right
        -- All sizes share a single readiness probe for each font file.
        for _,file in ipairs({"Cinzel-Bold","Cinzel-Regular","EBGaramond-Italic","EBGaramond-Regular"}) do
            addon.FontAPI.Prepare(file,t.body)
        end
        theme.seal=theme.seal or ({alliance="2d4f86",horde="7a2214",quelthalas="9e2a35",neutral="3f5a4c"})[theme.key]
        cover:SetSize(w,h)
        for i,t in ipairs(shadows) do t:SetSize(w+i*7*s,h+i*7*s) end
        anchor(left,cover,14*s,14*s,lw,h-28*s); anchor(right,cover,14*s+lw,14*s,rw,h-28*s)
        for _,t in ipairs(edges) do t:ClearAllPoints(); paint(t,theme.secondary,.4) end
        edges[1]:SetPoint("TOPLEFT",cover,"TOPLEFT",3*s,-3*s); edges[1]:SetSize(w-6*s,s)
        edges[2]:SetPoint("BOTTOMLEFT",cover,"BOTTOMLEFT",3*s,3*s); edges[2]:SetSize(w-6*s,s)
        edges[3]:SetPoint("TOPLEFT",cover,"TOPLEFT",3*s,-3*s); edges[3]:SetSize(s,h-6*s)
        edges[4]:SetPoint("TOPRIGHT",cover,"TOPRIGHT",-3*s,-3*s); edges[4]:SetSize(s,h-6*s)
        anchor(spineLeft,left,lw-20*s,0,20*s,h-28*s); anchor(spineRight,right,0,0,22*s,h-28*s)
        anchor(ribbon,cover,14*s+lw-11*s,-6*s,22*s,77*s); paint(ribbon,theme.seal)
        for i=1,15 do
            local width=11*(1-(i-1)/15)*s
            anchor(ribbonTips[i*2-1],cover,14*s+lw-11*s,(70+i)*s,width,s)
            anchor(ribbonTips[i*2],cover,14*s+lw+11*s-width,(70+i)*s,width,s)
            paint(ribbonTips[i*2-1],theme.seal); paint(ribbonTips[i*2],theme.seal)
        end
        anchor(emblem,contents,42*s,42*s,40*t.unit,40*t.unit)
        anchor(headings.brand,contents,94*s,40*s)
        local brandHeight=text(headings.brand,"NerdWow","Cinzel-Bold",t.title,lw-100*s); ink(headings.brand,"2a1d12")
        anchor(headings.subtitle,contents,94*s,40*s+brandHeight+4*t.unit)
        local subHeight=text(headings.subtitle,"Configurações","EBGaramond-Italic",t.note,lw-100*s); ink(headings.subtitle,"5a4632")
        local divider=40*s+brandHeight+subHeight+18*t.unit
        anchor(rules[1],contents,42*s,divider,(lw-70*s)/2-13*s,s)
        anchor(rules[2],contents,42*s+(lw-70*s)/2+13*s,divider,(lw-70*s)/2-13*s,s)
        anchor(rules[3],contents,42*s+(lw-70*s)/2-3*s,divider-3*s,6*s,6*s)
        anchor(indexNote,contents,42*s,h-86*s)
        local indexHeight=text(indexNote,addon.Text.configIndexFoot,"EBGaramond-Italic",t.note,lw-52*s); ink(indexNote,"5a4632")
        local indexBottom=h-34*s-indexHeight
        anchor(indexNote,contents,42*s,indexBottom)
        anchor(indexScroll,contents,34*s,divider+20*s,lw-40*s,indexBottom-divider-34*s); indexChild:SetWidth(lw-40*s)
        local y=0
        for index,spec in ipairs(snapshot.chapters) do
            local b=nav[index]
            if not b then
                b=CreateFrame("Button",nil,indexChild); b:RegisterForClicks("LeftButtonUp")
                b.fill=solid(b,"70412a",.08); b.fill:SetAllPoints(); b.marker=solid(b,"2d4f86")
                b.number,b.label,b.soon=label(b),label(b),label(b); b.dots={}; nav[index]=b
                feedback(b)
            end
            b:Show(); anchor(b,indexChild,0,y)
            anchor(b.number,b,9*s,9*s)
            font(b.number,"Cinzel-Regular",t.note)
            b.number:SetText(spec.roman)
            local numberWidth=math.ceil(b.number:GetUnboundedStringWidth()+2*t.unit)
            local numberHeight=text(b.number,spec.roman,"Cinzel-Regular",t.note,numberWidth); ink(b.number,theme.seal)
            local labelLeft=math.max(42*s,9*s+numberWidth+7*t.unit)
            local labelWidth=lw-labelLeft-48*s-(spec.soon and 55*s or 0)
            anchor(b.label,b,labelLeft,6*s)
            local height=math.max(text(b.label,spec.title,"EBGaramond-Regular",t.body,labelWidth),numberHeight+3*s); ink(b.label,"2a1d12")
            local natural=b.label:GetUnboundedStringWidth()
            local dotCount=math.max(0,math.floor((labelWidth-natural-8*s)/(5*s)))
            for i=1,math.max(dotCount,#b.dots) do
                local dot=b.dots[i]
                if not dot then dot=solid(b,"70412a",.35); b.dots[i]=dot end
                if i<=dotCount then dot:Show(); anchor(dot,b,labelLeft+natural+8*s+i*5*s,23*s,1.2*s,1.2*s) else dot:Hide() end
            end
            if spec.soon then
                anchor(b.soon,b,lw-95*s,9*s); height=math.max(height,text(b.soon,"em breve","EBGaramond-Italic",t.note,50*s))
                ink(b.soon,"6e5942"); b.soon:Show()
            else b.soon:Hide() end
            b:SetSize(lw-40*s,height+13*s)
            b.fill:SetAlpha(spec.id==snapshot.chapter and 1 or 0); paint(b.fill,theme.seal,.12)
            b.marker:SetAlpha(spec.id==snapshot.chapter and 1 or 0); paint(b.marker,theme.seal)
            anchor(b.marker,b,0,0,3*s,b:GetHeight())
            b.feedback.selected=spec.id==snapshot.chapter
            b.RefreshFeedback()
            local id=spec.id; b:SetScript("OnClick",safe(function()
                for _,item in ipairs(nav) do item.feedback.focus=false end
                menu:Hide(); optionScroll:SetVerticalScroll(0); callbacks.Select(id)
            end))
            y=y+b:GetHeight()+2*s
        end
        for index=#snapshot.chapters+1,#nav do nav[index]:Hide() end
        indexChild:SetHeight(y); indexScroll:UpdateScrollChildRect()
        local x=14*s+lw+34*s; local width=rw-68*s
        anchor(headings.kicker,contents,x,40*s)
        local header=snapshot.header
        local chapterNumber=""
        for _,chapter in ipairs(snapshot.chapters) do if chapter.id==snapshot.chapter then chapterNumber=chapter.roman end end
        local kh=text(headings.kicker,"Capítulo "..chapterNumber..(header.soon and " · em breve" or ""),"EBGaramond-Italic",t.note,width); ink(headings.kicker,theme.seal)
        local titleTop=40*s+kh+5*t.unit
        anchor(headings.title,contents,x,titleTop); local th=text(headings.title,header.title,"Cinzel-Bold",t.title,width); ink(headings.title,"2a1d12")
        anchor(headings.lead,contents,x,titleTop+th+4*t.unit); local lh=text(headings.lead,header.description,"EBGaramond-Regular",t.note,width); ink(headings.lead,"5a4632")
        local top=titleTop+th+lh+16*t.unit
        anchor(optionScroll,contents,x,top,width,h-top-78*s); child:SetWidth(width)
        anchor(scrollTrack,contents,x+width+10*s,top,2*s,optionScroll:GetHeight()); scrollThumb:SetWidth(2*s)
        local y,index=4*s,1
        while index<=#snapshot.options do
            local spec=snapshot.options[index]
            if spec.kind=="indicator" then
                local count=1
                while count<3 and snapshot.options[index+count] and snapshot.options[index+count].kind=="indicator" do count=count+1 end
                local cardWidth=(width-(count-1)*10*s)/count; local maxHeight=0
                for column=1,count do
                    local row=row(index+column-1); row.spec=snapshot.options[index+column-1]; row:Show()
                    if row.widgets then for _,w in pairs(row.widgets) do w:Hide() end end
                    row.badge:Hide(); row.description:Hide(); row.rule:Hide()
                    row.card=row.card or solid(row,"70412a",.06); row.card:SetAllPoints(); row.card:Show()
                    anchor(row,child,(column-1)*(cardWidth+10*s),y)
                    anchor(row.value,row,10*s,10*s)
                    local vh=text(row.value,display(row.spec.value),"Cinzel-Regular",t.heading,cardWidth-20*s); ink(row.value,"2a1d12")
                    anchor(row.title,row,10*s,14*s+vh)
                    local hh=text(row.title,row.spec.title,"EBGaramond-Regular",t.note,cardWidth-20*s); ink(row.title,"5a4632")
                    maxHeight=math.max(maxHeight,vh+hh+25*s); row:SetSize(cardWidth,vh+hh+25*s)
                end
                for column=1,count do
                    local card=rows[index+column-1]; card:SetHeight(maxHeight); card.RefreshFeedback()
                end
                y=y+maxHeight+14*s; index=index+count
            else
                local row=row(index); row.spec=spec; row:Show(); anchor(row,child,0,y)
                if row.card then row.card:Hide() end
                row.rule:SetAlpha(index<#snapshot.options and 1 or 0); row.rule:Show(); row.rule:SetHeight(s); row.value:Hide(); row.badge:Hide()
                local controlWidth=spec.kind=="switch" and 54*s or spec.kind=="action" and 170*s or 230*s
                local b=control(row)
                local full=spec.fullWidth or spec.kind=="info" and not spec.description
                local titleWidth=full and width or width-controlWidth-24*s
                anchor(row.title,row,7*s,12*s)
                local hh=text(row.title,spec.title..(spec.soon and " · em breve" or ""),"EBGaramond-Regular",t.body,titleWidth-7*s)
                ink(row.title,"2a1d12",spec.soon and .55 or 1)
                anchor(row.description,row,7*s,16*s+hh)
                local dh=text(row.description,spec.description or "","EBGaramond-Regular",t.note,titleWidth-7*s)
                ink(row.description,"5a4632",spec.soon and .55 or 1)
                local height=hh+(spec.description and dh+4*s or 0)+24*s
                if spec.kind=="info" then
                    anchor(row.value,row,full and 0 or width-controlWidth,full and height-8*s or 12*s)
                    local vh=text(row.value,display(spec.value),"EBGaramond-Regular",t.body,full and width or controlWidth)
                    ink(row.value,"5a4632"); height=full and height+vh+5*s or math.max(height,vh+24*s)
                elseif b then
                    local by=full and height-8*s or math.max(12*s,(height-30*s)/2)
                    anchor(b,row,full and 0 or width-controlWidth,by)
                    arrangeControl(row,b,full and width or controlWidth,30*s)
                    height=math.max(height,by+b:GetHeight()+12*s)
                end
                row:SetSize(width,height); row.RefreshFeedback(); y=y+height; index=index+1
            end
        end
        for i=#snapshot.options+1,#rows do rows[i]:Hide() end
        child:SetHeight(y+10*s); optionScroll:UpdateScrollChildRect()
        optionScroll:SetVerticalScroll(math.min(optionScroll:GetVerticalScroll(),optionScroll:GetVerticalScrollRange())); scrollbar()
        formatButton(close,"Fechar",74*s,33*s,true)
        formatButton(restore,"Restaurar padrões",176*s,33*s,false)
        local restoreLeft=rw-34*s-close:GetWidth()-12*t.unit-restore:GetWidth()
        anchor(saved,footer,34*s,20*s)
        local savedHeight=text(saved,addon.Text.configSaved,"EBGaramond-Italic",t.note,math.max(t.body*4,restoreLeft-46*s)); ink(saved,"5a4632")
        local footerHeight=math.max(56*s,close:GetHeight()+28*s,restore:GetHeight()+28*s,savedHeight+20*s)
        anchor(footer,contents,14*s+lw,h-14*s-footerHeight,rw,footerHeight); footerRule:SetHeight(s)
        anchor(saved,footer,34*s,(footerHeight-savedHeight)/2)
        anchor(restore,footer,restoreLeft,(footerHeight-restore:GetHeight())/2)
        anchor(close,footer,rw-34*s-close:GetWidth(),(footerHeight-close:GetHeight())/2)
        optionScroll:SetHeight(h-top-footerHeight-22*s); optionScroll:UpdateScrollChildRect()
        scrollTrack:SetHeight(optionScroll:GetHeight()); scrollbar()
        formatButton(xClose,"×",28*s,28*s,false); anchor(xClose,contents,w-42*s,22*s)
        font(xClose.label,"Cinzel-Regular",t.heading,"5a4632")
        for _,edge in ipairs(xClose.edges) do edge:Hide() end; xClose.fill:SetAlpha(0)
        confirm:Show(); confirm:SetAlpha(0) -- shown at alpha zero so native metrics exist.
        confirmPaper:SetSize(480*s,210*s); confirmPaper:ClearAllPoints(); confirmPaper:SetPoint("CENTER",cover,"CENTER",0,0)
        anchor(confirmTitle,confirmPaper,26*s,22*s); text(confirmTitle,"Restaurar padrões?","Cinzel-Bold",t.title,428*s); ink(confirmTitle,"2a1d12")
        anchor(confirmText,confirmPaper,26*s,60*s); text(confirmText,addon.Text.configResetText,"EBGaramond-Regular",t.body,428*s); ink(confirmText,"5a4632")
        formatButton(accept,"Restaurar",150*s,34*s,true); anchor(accept,confirmPaper,26*s,150*s)
        formatButton(cancel,"Cancelar",130*s,34*s,false); anchor(cancel,confirmPaper,190*s,150*s)
        confirm:SetAlpha(1); if not confirmation then confirm:Hide() end
    end
    local function animate(_,delta)
        elapsed=math.min(.7,elapsed+delta)
        local p=1-(1-elapsed/.7)^3
        cover:SetAlpha(p); cover:SetScale(.98+.02*p)
        cover:ClearAllPoints(); cover:SetPoint("CENTER",root,"CENTER",0,-14*layout.scale*(1-p))
        if elapsed==.7 then root:SetScript("OnUpdate",nil) end
    end
    function v.IsOpen() return root:IsShown() end
    function v.Open()
        if not root:IsShown() then elapsed=0 end
        root:Show(); root:EnableKeyboard(true); root:SetPropagateKeyboardInput(true)
    end
    function v.Hide()
        for _,row in ipairs(rows) do if row.widgets and row.widgets.text then row.widgets.text:ClearFocus() end end
        pending=false; root:SetScript("OnUpdate",nil); root:EnableKeyboard(false); root:SetPropagateKeyboardInput(true)
        root:Hide(); menu:Hide(); confirmation=nil; confirm:Hide()
    end
    function v.Render(input,newTheme)
        snapshot,theme=input,newTheme; rendering=true
        contents:SetAlpha(0); waiting:Hide(); loading:Hide()
        local ok,fault=addon.DiagnosticAPI.Try(render)
        rendering=false
        if not ok then
            if fault.message~="font_pending" then addon.DiagnosticAPI.Raise(fault,"configuration_error") end
            pending=true; waiting:Show(); loading:Show(); ink(loading,"5a4632")
            if not confirmation then confirm:Hide() end
        else pending=false; contents:SetAlpha(1) end
        if layout then animate(nil,0); if elapsed<.7 then root:SetScript("OnUpdate",safe(animate)) end end
        return not pending
    end
    function v.Confirm(callback)
        for _,row in ipairs(rows) do if row.widgets and row.widgets.text then row.widgets.text:ClearFocus() end end
        confirmation=callback; menu:Hide(); confirm:Show()
    end
    root:SetScript("OnKeyDown",safe(function(_,key)
        root:SetPropagateKeyboardInput(true)
        if key=="ESCAPE" then
            if confirm:IsShown() then confirmation=nil; confirm:Hide()
            elseif menu:IsShown() then menu:Hide() else callbacks.Close() end
            root:SetPropagateKeyboardInput(false)
        elseif not GetCurrentKeyBoardFocus() and not confirm:IsShown() and (key=="UP" or key=="DOWN") then
            menu:Hide(); optionScroll:SetVerticalScroll(0); callbacks.Move(key=="UP" and -1 or 1); root:SetPropagateKeyboardInput(false)
            for _,b in ipairs(nav) do b.feedback.focus=b.feedback.selected; b.RefreshFeedback() end
        end
    end))
    root:SetScript("OnKeyUp",function() root:SetPropagateKeyboardInput(true) end)
    root:SetScript("OnMouseDown",function() menu:Hide() end)
    root:SetScript("OnHide",function() root:SetScript("OnUpdate",nil); root:EnableKeyboard(false) end)
    root:SetScript("OnSizeChanged",safe(function() if root:IsShown() and not rendering then callbacks.Ready() end end))
    addon.FontAPI.Watch(safe(function() if root:IsShown() and not rendering then callbacks.Ready() end end,"configuration_fonts"),"configuration")
    return v
end
