local _, addon = ...
local View = {}
addon.QuestView = View
-- Provisional skin: replace these slots when the original 2.4 artwork is ready.
local ART={paperAtlas="QuestBG-Parchment",circle="Interface\\CHARACTERFRAME\\TempPortraitAlphaMask",
    unknownItem="Interface\\Icons\\INV_Misc_QuestionMark",book="Interface\\Icons\\INV_Misc_Book_09",
    coins={"Interface\\MoneyFrame\\UI-GoldIcon","Interface\\MoneyFrame\\UI-SilverIcon","Interface\\MoneyFrame\\UI-CopperIcon"}}
local QUALITY={"9d9d9d","ffffff","1eff00","0070dd","a335ee","ff8000","e6cc80","00ccff","00ccff"}
local SEAL={alliance="2d4f86",horde="7a2214",quelthalas="9e2a35",neutral="3f5a4c"}
local function prepare(scale)
    for _,spec in ipairs({{"Cinzel-Bold",27},{"Cinzel-Bold",15},{"Cinzel-Bold",48},
        {"EBGaramond-Regular",17},{"EBGaramond-Regular",14},{"EBGaramond-Regular",16},{"EBGaramond-Regular",15},
        {"EBGaramond-Italic",12},{"EBGaramond-Italic",11},{"Cinzel-Regular",12},
        {"Cinzel-Bold",14},{"Cinzel-Bold",11},{"EBGaramond-Regular",12}}) do
        addon.FontAPI.Prepare(spec[1],spec[2]*scale)
    end
end
function View.Preload(width,height)
    local layout=addon.QuestPresentation.Layout(width,height)
    if layout then prepare(layout.scale) end
end
local function rgb(hex)
    return tonumber(hex:sub(1,2),16)/255,tonumber(hex:sub(3,4),16)/255,tonumber(hex:sub(5,6),16)/255
end
local function texture(parent,layer) return parent:CreateTexture(nil,layer or "BACKGROUND") end
local function solid(parent,hex,alpha,layer)
    local t=texture(parent,layer); local r,g,b=rgb(hex); t:SetColorTexture(r,g,b,alpha or 1); return t
end
local function circle(parent,hex,alpha)
    local t=texture(parent,"ARTWORK"); t:SetTexture(ART.circle)
    local r,g,b=rgb(hex); t:SetVertexColor(r,g,b,alpha or 1); return t
end
local function gradient(parent,orientation,from,to)
    local t=solid(parent,"ffffff")
    t:SetGradient(orientation,CreateColor(unpack(from)),CreateColor(unpack(to)))
    return t
end
function View.New(parent,options)
    local q,labels,items,actions,markers,coins={},{},{},{},{},{}
    local model,layout,elapsed,selected,active=nil,nil,0,nil,false
    local labelIndex,itemIndex=0,0
    local root=CreateFrame("Frame",nil,parent); root:Hide(); root:EnableMouse(false)
    local clip=CreateFrame("ScrollFrame",nil,root)
    local paper=CreateFrame("Frame",nil,clip); clip:SetScrollChild(paper)
    local ornaments=CreateFrame("Frame",nil,root); ornaments:SetAllPoints(root)
    ornaments:SetFrameLevel(paper:GetFrameLevel()+5); ornaments:EnableMouse(false)
    local base=solid(paper,"e8d8b4"); base:SetAllPoints()
    local grain=texture(paper)
    if type(C_Texture)=="table" and type(C_Texture.GetAtlasInfo)=="function"
        and C_Texture.GetAtlasInfo(ART.paperAtlas) then
        grain:SetAtlas(ART.paperAtlas); grain:SetAllPoints(); grain:SetAlpha(.48)
    end
    local shadeLeft=gradient(paper,"HORIZONTAL",{.34,.20,.08,.48},{.34,.20,.08,0})
    local shadeRight=gradient(paper,"HORIZONTAL",{.34,.20,.08,0},{.34,.20,.08,.48})
    local shadeTop=gradient(paper,"VERTICAL",{.32,.19,.07,0},{.32,.19,.07,.28})
    local shadeBottom=gradient(paper,"VERTICAL",{.32,.19,.07,.28},{.32,.19,.07,0})
    local scroll=CreateFrame("ScrollFrame",nil,paper); scroll:EnableMouseWheel(true); scroll:EnableMouse(true)
    local child=CreateFrame("Frame",nil,scroll); scroll:SetScrollChild(child)
    local footer=CreateFrame("Frame",nil,paper)
    local footerTint=solid(footer,"dfcba3",.93); footerTint:SetAllPoints()
    local footerRule=solid(footer,"9b7b49",.25); footerRule:SetPoint("TOPLEFT"); footerRule:SetPoint("TOPRIGHT")
    local function font(object,file,size,hex,alpha)
        options.Font(object,file,size)
        object:SetShadowOffset(0,0)
        local r,g,b=rgb(hex or "2a1d12"); object:SetTextColor(r,g,b,alpha or 1)
    end
    local function makeLabel(parentFrame)
        local object=parentFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
        object:SetJustifyH("LEFT"); object:SetJustifyV("TOP")
        object:SetWordWrap(true); object:SetNonSpaceWrap(true)
        return object
    end
    local note=makeLabel(footer)
    local more=makeLabel(paper)
    local book=texture(footer,"ARTWORK"); book:SetTexture(ART.book)
    local ruleLeft,ruleRight=solid(child,"70412a",.6),solid(child,"70412a",.6)
    local diamond=solid(child,"70412a",.7,"ARTWORK"); diamond:SetRotation(math.pi/4)
    local sealOuter=circle(ornaments,"4e251a")
    local sealInner=circle(ornaments,"9e2a35")
    local sealRim=circle(ornaments,"e8b777",.28)
    local sealCenter=circle(ornaments,"9e2a35")
    local sealCrest=texture(ornaments,"OVERLAY")
    local rods={}
    for index=1,2 do
        local rod=CreateFrame("Frame",nil,ornaments)
        rod.wood=gradient(rod,"VERTICAL",{.16,.08,.03,1},{.47,.31,.16,1}); rod.wood:SetAllPoints()
        rod.highlight=solid(rod,"bb8d54",.5,"ARTWORK"); rod.highlight:SetPoint("TOPLEFT",rod,"TOPLEFT",0,-3)
        rod.highlight:SetPoint("TOPRIGHT",rod,"TOPRIGHT",0,-3)
        rod.bottom=solid(rod,"23150c",.65,"ARTWORK"); rod.bottom:SetPoint("BOTTOMLEFT"); rod.bottom:SetPoint("BOTTOMRIGHT")
        rod.caps={}
        for side=1,2 do
            local outer=circle(rod,"3c2915")
            local inner=circle(rod,"c9a15a")
            local shine=circle(rod,"f2ddb0",.6)
            rod.caps[side]={outer,inner,shine}
        end
        rods[index]=rod
    end
    local track=solid(paper,"70412a",.12,"ARTWORK")
    local thumb=solid(paper,"70412a",.6,"ARTWORK")
    local function scrollHint()
        local range=scroll:GetVerticalScrollRange()
        more:SetText(range>1 and (scroll:GetVerticalScroll()<range-1 and addon.Text.cinemaMore or addon.Text.cinemaPrevious) or "")
        local h=scroll:GetHeight()
        local thumbHeight=math.max(22*layout.scale,h*h/math.max(h,child:GetHeight()))
        thumb:SetHeight(thumbHeight)
        thumb:ClearAllPoints(); thumb:SetPoint("TOPLEFT",track,"TOPLEFT",0,
            -((range>0 and scroll:GetVerticalScroll()/range or 0)*(h-thumbHeight)))
        thumb:SetAlpha(range>1 and 1 or 0); track:SetAlpha(range>1 and 1 or 0)
    end
    scroll:SetScript("OnMouseWheel",options.Safe(function(_,delta)
        if not active then return end
        scroll:SetVerticalScroll(math.max(0,math.min(scroll:GetVerticalScrollRange(),
            scroll:GetVerticalScroll()-delta*42*layout.scale)))
        scrollHint()
    end,"quest_scroll"))
    local function text(value,file,size,x,y,width,hex,alpha)
        labelIndex=labelIndex+1
        local object=labels[labelIndex]
        if not object then object=makeLabel(child); labels[labelIndex]=object end
        object:ClearAllPoints(); object:SetPoint("TOPLEFT",child,"TOPLEFT",x,-y)
        font(object,file,size,hex,alpha); object:SetSpacing(3*layout.scale)
        local height=options.Height(object,value,file,size,width)
        -- The shared measuring helper sets the cinematic shadow; ink has none.
        object:SetShadowOffset(0,0)
        return height,object
    end
    local function section(value,y,width)
        local height=text(value,"Cinzel-Bold",15*layout.scale,0,y,width,SEAL[model.theme.key])
        return y+height+7*layout.scale
    end
    local function itemRow(index)
        local b=items[index]
        if b then return b end
        b=CreateFrame("Button",nil,child); b:RegisterForClicks("LeftButtonUp")
        b.background=solid(b,"70412a",.065); b.background:SetAllPoints()
        b.light=solid(b,"9e2a35",.14,"ARTWORK"); b.light:SetAllPoints(); b.light:SetAlpha(0)
        b.border=solid(b,"ffffff",1,"ARTWORK")
        b.icon=texture(b,"OVERLAY")
        b.name=makeLabel(b); b.quantity=makeLabel(b); b.number=makeLabel(b); b.count=makeLabel(b)
        b.edges={}
        for edge=1,4 do b.edges[edge]=solid(b,"9e2a35",.85,"OVERLAY") end
        items[index]=b
        return b
    end
    local function placeItems(list,kind,y,width,choose)
        local s=layout.scale
        local sr,sg,sb=rgb(SEAL[model.theme.key])
        local columns=width>=340*s and 2 or 1
        local cardWidth=(width-(columns-1)*9*s)/columns
        local rowHeight,column=0,0
        for position,item in ipairs(list) do
            itemIndex=itemIndex+1
            local b=itemRow(itemIndex); b.item,b.source,b.choiceValue=item,kind,choose and item.index or nil
            b.light:SetColorTexture(sr,sg,sb,.14)
            for _,edge in ipairs(b.edges) do edge:SetColorTexture(sr,sg,sb,.85) end
            b:Show(); b:ClearAllPoints(); b:SetPoint("TOPLEFT",child,"TOPLEFT",column*(cardWidth+9*s),-y)
            b.name:ClearAllPoints(); b.name:SetPoint("TOPLEFT",b,"TOPLEFT",47*s,-8*s)
            local quality=QUALITY[(item.quality or 1)+1] or "ffffff"
            local r,g,blue=rgb(quality)
            font(b.name,"EBGaramond-Regular",14*s)
            b.name:SetTextColor(r*.52,g*.52,blue*.52,1)
            local height=options.Height(b.name,item.name or addon.Text.questUnknownItem,"EBGaramond-Regular",14*s,cardWidth-57*s)
            b.name:SetShadowOffset(0,0)
            local count=addon.QuestPresentation.ItemCount(item,kind=="required")
            b.count:ClearAllPoints(); b.count:SetPoint("TOPLEFT",b,"TOPLEFT",47*s,-8*s-height)
            font(b.count,"EBGaramond-Regular",12*s,"6e5942")
            if count~="" then
                height=height+options.Height(b.count,count,"EBGaramond-Regular",12*s,cardWidth-57*s)
                b.count:SetShadowOffset(0,0)
            else b.count:SetText("") end
            b:SetSize(cardWidth,math.max(48*s,height+16*s))
            b.border:ClearAllPoints(); b.border:SetPoint("TOPLEFT",b,"TOPLEFT",6*s,-7*s); b.border:SetSize(34*s,34*s)
            b.border:SetColorTexture(r,g,blue,.95)
            b.icon:ClearAllPoints(); b.icon:SetPoint("CENTER",b.border,"CENTER",0,0); b.icon:SetSize(31*s,31*s)
            b.icon:SetTexture(item.icon or ART.unknownItem)
            b.icon:SetTexCoord(.06,.94,.06,.94)
            font(b.quantity,"EBGaramond-Regular",12*s,"ffffff")
            b.quantity:SetShadowOffset(1,-1)
            b.quantity:ClearAllPoints(); b.quantity:SetPoint("BOTTOMRIGHT",b.icon,"BOTTOMRIGHT",-1*s,1*s)
            b.quantity:SetSize(30*s,16*s); b.quantity:SetJustifyH("RIGHT")
            b.quantity:SetText(item.quantity and item.quantity>1 and tostring(item.quantity) or "")
            font(b.number,"Cinzel-Bold",11*s,"2a1d12")
            b.number:ClearAllPoints(); b.number:SetPoint("TOPLEFT",b,"TOPLEFT",5*s,7*s)
            b.number:SetSize(26*s,17*s); b.number:SetText(choose and tostring(position) or "")
            b.number:SetWordWrap(false)
            local token=options.Callbacks()
            b:SetScript("OnClick",options.Safe(function()
                if choose and model.moment=="COMPLETE" then token.Choose(position) end
            end,"quest_reward"))
            b:SetScript("OnEnter",options.Safe(function()
                addon.QuestPlatform.ShowItem(b,item,kind,model.quest.id)
                if not b.choiceValue or b.choiceValue~=selected then b.light:SetAlpha(.5) end
            end,"quest_tooltip"))
            b:SetScript("OnLeave",options.Safe(function()
                addon.QuestPlatform.HideItem(b); b.light:SetAlpha(b.choiceValue==selected and 1 or 0)
            end,"quest_tooltip"))
            rowHeight=math.max(rowHeight,b:GetHeight()); column=column+1
            if column==columns or position==#list then y=y+rowHeight+9*s; column=0; rowHeight=0 end
        end
        return y
    end
    local function updateActions(format)
        if not model then return end
        local s=layout.scale
        local specs=addon.QuestPresentation.Actions(model,selected)
        for index,spec in ipairs(specs) do
            local b=actions[index]
            if not b then
                b=CreateFrame("Button",nil,footer); b:RegisterForClicks("LeftButtonUp")
                b.fill=solid(b,"9e2a35"); b.fill:SetAllPoints()
                b.light=solid(b,"ffffff",.13,"ARTWORK"); b.light:SetPoint("TOPLEFT",b,"TOPLEFT",1,-1)
                b.light:SetPoint("TOPRIGHT",b,"TOPRIGHT",-1,-1); b.light:SetHeight(1)
                b.label=makeLabel(b); b.label:SetAllPoints(); b.label:SetJustifyH("CENTER"); b.label:SetJustifyV("MIDDLE")
                b:SetScript("OnEnter",options.Safe(function() if b.allowed then b:SetAlpha(.86) end end))
                b:SetScript("OnLeave",options.Safe(function() b:SetAlpha(b.allowed and 1 or .4) end))
                actions[index]=b
            end
            local r,g,blue=rgb(SEAL[model.theme.key])
            b.fill:SetColorTexture(r,g,blue,spec.ghost and .09 or 1)
            b:Show(); b:SetSize(math.min(210*s,(layout.paperWidth-78*s-12*s)/#specs),35*s)
            b:ClearAllPoints(); b:SetPoint("BOTTOMLEFT",footer,"BOTTOMLEFT",39*s+(index-1)*(b:GetWidth()+12*s),29*s)
            if format then font(b.label,"Cinzel-Bold",14*s,spec.ghost and "352416" or "f7ecd4") end
            b.label:SetWordWrap(false); b.label:SetText(spec.text)
            b.allowed=spec.enabled; b:SetEnabled(spec.enabled); b:SetAlpha(spec.enabled and 1 or .4)
            local token=options.Callbacks()
            b:SetScript("OnClick",options.Safe(function() if b.allowed then token.Action(spec.key) end end,"quest_action"))
        end
        for index=#specs+1,#actions do actions[index]:Hide() end
        for _,b in ipairs(items) do
            local on=b.choiceValue~=nil and b.choiceValue==selected
            b.light:SetAlpha(on and 1 or 0)
            local w,h=b:GetWidth(),b:GetHeight()
            for _,edge in ipairs(b.edges) do edge:SetAlpha(on and 1 or 0); edge:ClearAllPoints() end
            b.edges[1]:SetPoint("TOPLEFT",b,"TOPLEFT",0,0); b.edges[1]:SetSize(w,1*s)
            b.edges[2]:SetPoint("BOTTOMLEFT",b,"BOTTOMLEFT",0,0); b.edges[2]:SetSize(w,1*s)
            b.edges[3]:SetPoint("TOPLEFT",b,"TOPLEFT",0,0); b.edges[3]:SetSize(1*s,h)
            b.edges[4]:SetPoint("TOPRIGHT",b,"TOPRIGHT",0,0); b.edges[4]:SetSize(1*s,h)
        end
        note:SetText(addon.QuestPresentation.Note(model))
        book:SetAlpha(note:GetText()~="" and .65 or 0)
    end
    local function opening()
        local s=layout.scale
        local p=math.min(1,math.max(0,(elapsed-.08)/.72))
        local eased=1-(1-p)^3
        clip:SetHeight(math.max(1,layout.paperHeight*eased))
        rods[2]:ClearAllPoints(); rods[2]:SetPoint("TOPLEFT",root,"TOPLEFT",-10*s,-layout.paperHeight*eased+8*s)
        local sealAlpha=math.min(1,math.max(0,(elapsed-.45)/.3))
        for _,object in ipairs({sealOuter,sealInner,sealRim,sealCenter,sealCrest}) do object:SetAlpha(sealAlpha) end
        root:SetAlpha(math.min(1,elapsed/.16))
        return elapsed<.82
    end
    q.Prepare=prepare
    function q.Place(input,newLayout)
        model,layout=input,newLayout; selected=model.selected; active=true
        local s=layout.scale
        q.Prepare(s)
        root:Show(); root:ClearAllPoints(); root:SetPoint("TOPLEFT",parent,"TOPLEFT",layout.paperLeft,-layout.paperTop)
        root:SetSize(layout.paperWidth,layout.paperHeight)
        clip:ClearAllPoints(); clip:SetPoint("TOPLEFT",root,"TOPLEFT",0,0); clip:SetWidth(layout.paperWidth)
        paper:SetSize(layout.paperWidth,layout.paperHeight)
        shadeLeft:SetSize(27*s,layout.paperHeight); shadeLeft:SetPoint("TOPLEFT",paper,"TOPLEFT",0,0)
        shadeRight:SetSize(27*s,layout.paperHeight); shadeRight:SetPoint("TOPRIGHT",paper,"TOPRIGHT",0,0)
        shadeTop:SetSize(layout.paperWidth,24*s); shadeTop:SetPoint("TOPLEFT",paper,"TOPLEFT",0,0)
        shadeBottom:SetSize(layout.paperWidth,24*s); shadeBottom:SetPoint("BOTTOMLEFT",paper,"BOTTOMLEFT",0,0)
        local width=layout.paperWidth-78*s
        footer:ClearAllPoints(); footer:SetPoint("BOTTOMLEFT",paper,"BOTTOMLEFT",0,0)
        footer:SetSize(layout.paperWidth,87*s); footerRule:SetHeight(1*s)
        scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT",paper,"TOPLEFT",39*s,-29*s)
        scroll:SetSize(width,layout.paperHeight-140*s)
        child:SetWidth(width)
        track:ClearAllPoints(); track:SetPoint("TOPLEFT",scroll,"TOPRIGHT",15*s,0); track:SetSize(2*s,scroll:GetHeight())
        thumb:SetWidth(2*s)
        for index,rod in ipairs(rods) do
            rod:SetSize(layout.paperWidth+20*s,19*s)
            if index==1 then rod:ClearAllPoints(); rod:SetPoint("TOPLEFT",root,"TOPLEFT",-10*s,8*s) end
            rod.highlight:SetHeight(3*s); rod.bottom:SetHeight(3*s)
            for side,cap in ipairs(rod.caps) do
                cap[1]:ClearAllPoints(); cap[1]:SetPoint(side==1 and "LEFT" or "RIGHT",rod,side==1 and "LEFT" or "RIGHT",0,0)
                cap[1]:SetSize(25*s,25*s)
                cap[2]:SetPoint("CENTER",cap[1],"CENTER",0,0); cap[2]:SetSize(19*s,19*s)
                cap[3]:SetPoint("TOPLEFT",cap[2],"TOPLEFT",3*s,-2*s); cap[3]:SetSize(8*s,5*s)
            end
        end
        local sealHex=SEAL[model.theme.key]
        local r,g,b=rgb(sealHex)
        for _,object in ipairs({ruleLeft,ruleRight,diamond}) do object:SetColorTexture(r,g,b,.55) end
        for _,object in ipairs({sealInner,sealCenter}) do object:SetVertexColor(r,g,b,1) end
        sealOuter:SetPoint("TOPRIGHT",root,"TOPRIGHT",-24*s,-7*s); sealOuter:SetSize(57*s,57*s)
        sealInner:SetPoint("CENTER",sealOuter,"CENTER",0,1*s); sealInner:SetSize(53*s,53*s)
        sealRim:SetPoint("CENTER",sealOuter,"CENTER",0,1*s); sealRim:SetSize(41*s,41*s)
        sealCenter:SetPoint("CENTER",sealOuter,"CENTER",0,1*s); sealCenter:SetSize(37*s,37*s)
        sealCrest:SetTexture(model.theme.crest); sealCrest:SetPoint("CENTER",sealOuter,"CENTER",0,1*s)
        sealCrest:SetSize(25*s,25*s); sealCrest:SetVertexColor(.95,.83,.57,.9)
        labelIndex,itemIndex=0,0
        local y=0
        y=y+text(model.paper.kind or addon.Text.questKinds[model.moment],"EBGaramond-Italic",12*s,0,y,width-45*s,sealHex)+4*s
        if model.npc then
            local byline=(model.npc.name or "")..(model.npc.title and " · "..model.npc.title or "")
            if byline~="" then y=y+text(byline,"EBGaramond-Italic",12*s,0,y,width,"6e5942")+5*s end
        end
        y=y+text(model.paper.title,"Cinzel-Bold",27*s,0,y,width,"352416")+11*s
        for _,object in ipairs({ruleLeft,ruleRight,diamond}) do object:Show(); object:ClearAllPoints() end
        ruleLeft:SetPoint("TOPLEFT",child,"TOPLEFT",0,-y); ruleLeft:SetSize(width/2-15*s,1*s)
        ruleRight:SetPoint("TOPRIGHT",child,"TOPRIGHT",0,-y); ruleRight:SetSize(width/2-15*s,1*s)
        diamond:SetPoint("CENTER",ruleLeft,"RIGHT",15*s,0); diamond:SetSize(5*s,5*s)
        y=y+18*s
        for index,part in ipairs(addon.Conversation.Paragraphs(model.paper.text)) do
            local drop,rest=nil,part.text
            if index==1 then drop,rest=addon.QuestPresentation.Drop(part.text) end
            if drop then
                local inset=48*s
                local position,lineStart,lines,split=1,1,1,#rest
                while position<=#rest do
                    local _,finish=rest:find("%S+%s*",position)
                    if not finish then break end
                    if options.Width(rest:sub(lineStart,finish),"EBGaramond-Regular",17*s)>width-inset then
                        if lines==2 then split=position-1; break end
                        lines=lines+1; lineStart=position
                    end
                    position=finish+1
                end
                local _,dropObject=text(drop,"Cinzel-Bold",48*s,0,y,inset-7*s,sealHex)
                local headHeight=text(rest:sub(1,split),"EBGaramond-Regular",17*s,inset,y,width-inset)
                dropObject:SetHeight(math.max(52*s,headHeight))
                y=y+math.max(52*s,headHeight)
                if split<#rest then y=y+text(rest:sub(split+1),"EBGaramond-Regular",17*s,0,y,width) end
            else y=y+text(part.text,"EBGaramond-Regular",17*s,0,y,width) end
            y=y+13*s
        end
        if model.paper.objectiveText and model.paper.objectiveText~="" or #model.paper.objectives>0 then
            y=section(addon.Text.questObjectives,y+4*s,width)
            if model.paper.objectiveText and model.paper.objectiveText~="" then
                y=y+text(model.paper.objectiveText,"EBGaramond-Regular",16*s,0,y,width)+8*s
            end
            for index,objective in ipairs(model.paper.objectives) do
                local marker=markers[index]
                if not marker then
                    marker={solid(child,sealHex,.7,"ARTWORK"),solid(child,"e8d8b4",1,"ARTWORK")}
                    for _,object in ipairs(marker) do object:SetRotation(math.pi/4) end
                    markers[index]=marker
                end
                marker[1]:Show(); marker[1]:ClearAllPoints()
                marker[1]:SetColorTexture(r,g,b,.7)
                marker[1]:SetPoint("TOPLEFT",child,"TOPLEFT",1*s,-y-7*s); marker[1]:SetSize(7*s,7*s)
                marker[2]:ClearAllPoints(); marker[2]:SetPoint("CENTER",marker[1],"CENTER",0,0)
                marker[2]:SetSize(4*s,4*s); marker[2]:SetAlpha(objective.finished and 0 or 1); marker[2]:Show()
                local caption,count=addon.QuestPresentation.Objective(objective)
                local reserve=count~="" and math.max(50*s,options.Width(count,"Cinzel-Regular",12*s)+4*s) or 0
                local height=text(caption,"EBGaramond-Regular",16*s,17*s,y,width-21*s-reserve,
                    objective.finished and "8b7964" or "352416")
                if count~="" then
                    local countHeight=text(count,"Cinzel-Regular",12*s,width-reserve,y+3*s,reserve,"6e5942")
                    height=math.max(height,countHeight)
                end
                y=y+height+5*s
            end
            y=y+9*s
        end
        for index=#model.paper.objectives+1,#markers do
            for _,object in ipairs(markers[index]) do object:Hide() end
        end
        if #model.paper.requiredItems>0 then
            y=section(addon.Text.questRequired,y,width)
            y=placeItems(model.paper.requiredItems,"required",y,width,false)+8*s
        end
        if #model.paper.choices>0 then
            y=section(model.moment=="COMPLETE" and addon.Text.questChoose or addon.Text.questRewards,y,width)
            y=placeItems(model.paper.choices,"choice",y+4*s,width,model.moment=="COMPLETE")+8*s
        end
        if #model.paper.fixed>0 then
            y=section(#model.paper.choices>0 and addon.Text.questReceive or addon.Text.questRewards,y,width)
            y=placeItems(model.paper.fixed,"reward",y,width,false)+8*s
        end
        if #model.paper.choices==0 and #model.paper.fixed==0
            and ((model.paper.money or 0)>0 or (model.paper.experience or 0)>0) then
            y=section(addon.Text.questRewards,y,width)
        end
        if model.paper.money and model.paper.money>0 then
            local money=model.paper.money
            local values={math.floor(money/10000),math.floor(money/100)%100,money%100}
            local x,height=0,0
            for index,value in ipairs(values) do
                if value>0 then
                    if not coins[index] then coins[index]=texture(child,"ARTWORK") end
                    coins[index]:Show(); coins[index]:SetTexture(ART.coins[index])
                    coins[index]:ClearAllPoints(); coins[index]:SetPoint("TOPLEFT",child,"TOPLEFT",x,-y-4*s)
                    coins[index]:SetSize(16*s,16*s)
                    local caption=tostring(value).." "..addon.Text.questCoins[index]
                    local used=options.Width(caption,"EBGaramond-Regular",15*s)+3*s
                    local lineHeight=text(caption,"EBGaramond-Regular",15*s,x+20*s,y,used,"6a4b13")
                    height=math.max(height,lineHeight)
                    x=x+20*s+used+12*s
                elseif coins[index] then coins[index]:Hide() end
            end
            y=y+height+5*s
        else
            for _,coin in pairs(coins) do coin:Hide() end
        end
        if model.paper.experience and model.paper.experience>0 then
            y=y+text(string.format(addon.Text.questExperience,tostring(model.paper.experience)),
                "EBGaramond-Regular",15*s,0,y,width,"6e5942")+5*s
        end
        for index=labelIndex+1,#labels do labels[index]:Hide() end
        for index=itemIndex+1,#items do items[index]:Hide() end
        local contentHeight=math.max(1,y+12*s)
        -- Measure in the final fonts at the final width before choosing height.
        -- All resizing happens in this layout pass, without replaying opening.
        layout.paperHeight=addon.QuestPresentation.PaperHeight(layout,contentHeight)
        root:SetHeight(layout.paperHeight); paper:SetHeight(layout.paperHeight)
        shadeLeft:SetHeight(layout.paperHeight); shadeRight:SetHeight(layout.paperHeight)
        scroll:SetHeight(layout.paperHeight-140*s); track:SetHeight(scroll:GetHeight())
        child:SetHeight(contentHeight); scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(),scroll:GetVerticalScrollRange()))
        font(more,"EBGaramond-Italic",11*s,"786148")
        more:ClearAllPoints(); more:SetPoint("BOTTOMLEFT",paper,"BOTTOMLEFT",39*s,88*s); more:SetSize(width,16*s)
        more:SetWordWrap(false)
        font(note,"EBGaramond-Italic",11*s,"786148")
        note:ClearAllPoints(); note:SetPoint("BOTTOMLEFT",footer,"BOTTOMLEFT",58*s,9*s); note:SetSize(width-19*s,16*s)
        note:SetWordWrap(false)
        book:ClearAllPoints(); book:SetPoint("BOTTOMLEFT",footer,"BOTTOMLEFT",39*s,9*s); book:SetSize(13*s,13*s)
        updateActions(true); scrollHint(); opening()
    end
    function q.Selection(value) selected=value; model.selected=value; updateActions() end
    function q.Recorded(kind) if model then model.recorded=kind; updateActions() end end
    function q.Start() elapsed=0; scroll:SetVerticalScroll(0) end
    function q.Advance(delta)
        if not active then return false end
        elapsed=math.min(.82,elapsed+delta)
        return opening()
    end
    function q.IsAnimating() return active and elapsed<.82 end
    function q.Hide()
        active=false; root:Hide()
        for _,item in ipairs(items) do addon.QuestPlatform.HideItem(item) end
        model=nil
    end
    return q
end
