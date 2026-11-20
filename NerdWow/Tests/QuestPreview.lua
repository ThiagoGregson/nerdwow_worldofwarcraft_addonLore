-- Development-only drawing of the real renderer's recorded regions/anchors.
-- Native bitmaps and font metrics are approximated; this is not a Retail screenshot.
local fixtures,fonts=...
local function esc(value)
    return tostring(value):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;")
end
local function rgba(value)
    return string.format("rgba(%d,%d,%d,%g)",math.floor((value[1] or 0)*255),math.floor((value[2] or 0)*255),
        math.floor((value[3] or 0)*255),value[4] or 1)
end
local function anchor(point,w,h)
    return point:find("RIGHT",1,true) and w or point:find("LEFT",1,true) and 0 or w/2,
        point:find("TOP",1,true) and h or point:find("BOTTOM",1,true) and 0 or h/2
end
local function draw(s)
    local r=s.r
    local bounds={}
    local function rect(object)
        if bounds[object] then return bounds[object] end
        if object.kind=="UIParent" then return {x=0,y=0,w=object.width,h=object.height} end
        if object.all then local b=rect(object.all); bounds[object]=b; return b end
        local w,h=object:GetWidth(),object:GetHeight()
        local p=object.points and object.points[1]
        local target=p and type(p[2])=="table" and p[2] or object.parent
        local b=rect(target)
        local x,y=b.x,b.y+b.h-h
        if p then
            local point=p[1]; local relative=p[3] or point
            local tx,ty=anchor(relative,b.w,b.h); local sx,sy=anchor(point,w,h)
            x=b.x+tx+(p[4] or 0)-sx; y=b.y+ty+(p[5] or 0)-sy
        elseif target.kind=="ScrollFrame" then y=y+(target.scroll or 0) end
        local value={x=x,y=y,w=w,h=h}; bounds[object]=value; return value
    end
    local defs,output={},{}
    local ordered={}
    local layers={BACKGROUND=0,BORDER=1,ARTWORK=2,OVERLAY=3}
    for index,region in ipairs(r.regions) do
        ordered[#ordered+1]={region=region,index=index,level=region.parent:GetFrameLevel(),layer=layers[region.layer] or 3}
    end
    table.sort(ordered,function(a,b)
        if a.level~=b.level then return a.level<b.level end
        if a.layer~=b.layer then return a.layer<b.layer end
        return a.index<b.index
    end)
    for _,entry in ipairs(ordered) do
        local object=entry.region
        local alpha=object.alpha or 1
        local ancestor=object
        local clip={x=0,y=0,w=1280,h=720}
        while ancestor do
            if ancestor~=object then alpha=alpha*(ancestor.alpha or 1) end
            if not ancestor.shown then alpha=0; break end
            if ancestor.kind=="ScrollFrame" then
                local b=rect(ancestor)
                local right,top=math.min(clip.x+clip.w,b.x+b.w),math.min(clip.y+clip.h,b.y+b.h)
                clip.x,clip.y=math.max(clip.x,b.x),math.max(clip.y,b.y)
                clip.w,clip.h=right-clip.x,top-clip.y
            end
            ancestor=ancestor.parent
        end
        if alpha>.001 and clip.w>0 and clip.h>0 then
            local b=rect(object); local y=720-b.y-b.h
            local id=s.source.moment.."r"..entry.index
            defs[#defs+1]=string.format('<clipPath id="%s"><rect x="%g" y="%g" width="%g" height="%g"/></clipPath>',
                id,clip.x,720-clip.y-clip.h,clip.w,clip.h)
            local shape
            if object.kind=="FontString" and object.text and object.text~="" then
                local family=(object.font or ""):match("([^\\]+)%.ttf$") or "EBGaramond-Regular"
                shape=string.format('<foreignObject x="%g" y="%g" width="%g" height="%g"><div xmlns="http://www.w3.org/1999/xhtml" style="width:100%%;height:100%%;overflow:hidden;font-family:%s;font-size:%gpx;line-height:%gpx;color:%s;white-space:%s;text-align:%s;%s">%s</div></foreignObject>',
                    b.x,y,b.w,b.h,family,object.size or 16,(object.size or 16)*1.4+(object.spacing or 0),
                    rgba(object.textColor or {1,1,1}),object.wrap==false and "pre" or "pre-wrap",
                    object.justifyH=="CENTER" and "center" or object.justifyH=="RIGHT" and "right" or "left",
                    object.justifyV=="MIDDLE" and "display:flex;align-items:center;justify-content:center" or "",esc(object.text))
            elseif object.fill then
                local paint=rgba(object.fill)
                if object.gradient then
                    local g=object.gradient
                    defs[#defs+1]=string.format('<linearGradient id="g%s" x1="0" y1="%s" x2="%s" y2="0"><stop stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient>',
                        id,g[1]=="VERTICAL" and "1" or "0",g[1]=="HORIZONTAL" and "1" or "0",rgba(g[2]),rgba(g[3]))
                    paint="url(#g"..id..")"
                end
                shape=string.format('<rect x="%g" y="%g" width="%g" height="%g" fill="%s"%s/>',b.x,y,b.w,b.h,paint,
                    object.rotation and string.format(' transform="rotate(45 %g %g)"',b.x+b.w/2,y+b.h/2) or "")
            elseif object.texture then
                if type(object.texture)=="string" and object.texture:find("TempPortrait",1,true) then
                    shape=string.format('<ellipse cx="%g" cy="%g" rx="%g" ry="%g" fill="%s"/>',b.x+b.w/2,y+b.h/2,b.w/2,b.h/2,rgba(object.tint or {1,1,1}))
                else
                    shape=string.format('<rect x="%g" y="%g" width="%g" height="%g" rx="3" fill="#70532d"/><text x="%g" y="%g" text-anchor="middle" fill="#f0ce84" font-size="%g">✦</text>',
                        b.x,y,b.w,b.h,b.x+b.w/2,y+b.h*.78,b.h*.75)
                end
            end
            if shape then output[#output+1]=string.format('<g clip-path="url(#%s)" opacity="%g">%s</g>',id,alpha,shape) end
        end
    end
    return '<svg viewBox="0 0 1280 720" xmlns="http://www.w3.org/2000/svg"><defs>'..table.concat(defs)..'</defs><rect width="1280" height="720" fill="#24352d"/><path d="M0 520L220 250 420 500 800 190 1280 440V720H0Z" fill="#182820"/>'..table.concat(output)..'</svg>'
end
local styles={}
for _,name in ipairs({"Cinzel-Regular","Cinzel-Bold","EBGaramond-Regular","EBGaramond-Italic"}) do
    styles[#styles+1]='@font-face{font-family:'..name..';src:url("file:///'..fonts..'/'..name..'.ttf");}'
end
local html={'<!doctype html><html lang="pt-BR"><meta charset="utf-8"><title>NerdWow · revisão externa 2.2</title><style>',
    table.concat(styles),'body{margin:0;padding:22px;background:#151416;color:#e8d8b4;font:16px EBGaramond-Regular}main{width:1280px;margin:auto}h2{font:18px Cinzel-Regular;margin:20px 0 10px}svg{display:block;width:1280px;height:720px;border:1px solid #514330}</style><main><p>Revisão externa do renderer Lua · geometria real da simulação; métricas e bitmaps nativos aproximados. Não é captura do Retail.</p>'}
local talk=fixtures.conversationScene()
local talkRoot=talk.open(); talk.view.Complete(); talkRoot.scripts.OnUpdate(talkRoot,1)
html[#html+1]='<h2>GOSSIP · Fábio</h2>'..draw(talk)
for _,moment in ipairs({"OFFER","PROGRESS","COMPLETE"}) do
    local s=fixtures.scene(moment)
    if moment=="PROGRESS" then
        s.source.npc={name="Durval Pilão",faction="Alliance"}
        s.source.quest.title="Velas dos Kobolds"; s.source.quest.progressText="Você já coletou as velas?"
        s.source.location={zone="Floresta de Elwynn",subZone="Vila d'Ouro",mapID=37}
        s.source.objectives={{index=1,text="0/8 Vela Grande",fulfilled=0,required=8}}
        s.source.requiredItems={{index=1,itemID=772,name="Vela Grande",icon=133750,quality=1,quantity=8}}
        s.r.env.C_Item={GetItemCount=function() return 0 end}
    end
    s.receipt={questID=101,kind=moment=="OFFER" and "QUEST_OFFERED" or "QUEST_PROGRESS_VIEWED"}
    s.completable=moment=="PROGRESS"
    s.c.Refresh(); s.root().scripts.OnUpdate(s.root(),1)
    if moment=="COMPLETE" then s.c.Choose(2) end
    html[#html+1]='<h2>'..moment..'</h2>'..draw(s)
end
html[#html+1]='</main></html>'
return table.concat(html)
