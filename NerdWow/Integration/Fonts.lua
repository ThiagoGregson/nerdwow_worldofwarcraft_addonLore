local _, addon = ...
local Fonts = {}
addon.FontAPI = Fonts
local BASE = "Interface\\AddOns\\NerdWow\\Fonts\\"
local TITLE, BODY = "Fonts\\FRIZQT__.TTF", "Fonts\\ARIALN.TTF"
local files = {
    {name="Cinzel-Regular",fallback=TITLE}, {name="Cinzel-Bold",fallback=TITLE},
    {name="EBGaramond-Regular",fallback=BODY}, {name="EBGaramond-Italic",fallback=BODY},
}
local embedded, reported = {},{}
for _, file in ipairs(files) do
    file.path=BASE..file.name..".ttf"
    embedded[file.name]=file
end
local probe
local function setFont(object,path,size,flags)
    local ok,success=addon.DiagnosticAPI.Try(function()
        local value=object:SetFont(path,size,flags)
        if issecretvalue and issecretvalue(value) then error("restricted_font_result") end
        return value==true
    end)
    if not ok then return false,success end
    return success
end
local function result(path,flags,size,success)
    return string.format("font=%s; flags=%s; size=%g; success=%s",path,
        flags==nil and "nil" or '"'..flags..'"',size,tostring(success))
end
local function detail(message,fault)
    return {message=message..(fault and fault.message and "; error="..fault.message or ""),
        stack=fault and fault.stack,redacted=fault and fault.redacted}
end
function Fonts.Apply(object,name,size)
    local file=embedded[name]
    if not file or type(size)~="number" or size~=size or size==math.huge then error("font_unavailable") end
    size=math.max(8,size)
    local success,fault=setFont(object,file.path,size,nil)
    if success then return file.path end
    local fallbackSuccess,fallbackFault=setFont(object,file.fallback,size,nil)
    if not reported[name] then
        reported[name]=true
        local message=result(file.path,nil,size,false).."; fallback="..file.fallback
            .."; fallbackSuccess="..tostring(fallbackSuccess)
        if fallbackFault and fallbackFault.message then message=message.."; fallbackError="..fallbackFault.message end
        addon.DiagnosticAPI.Record("interface",fallbackSuccess and "font_fallback" or "font_fallback_failed",
            detail(message,fault or fallbackFault),{stage="font_apply"})
    end
    if not fallbackSuccess then error("font_unavailable") end
    return file.fallback
end
function Fonts.Test(report)
    if not probe then
        local frame=CreateFrame("Frame",nil,UIParent)
        frame:Hide()
        probe=frame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    end
    local controls={}
    for _, file in ipairs(files) do controls[#controls+1]=file end
    controls[#controls+1]={name="Friz Quadrata (nativa)",path=TITLE}
    controls[#controls+1]={name="Arial Narrow (nativa)",path=BODY}
    local flags={{},{value=""},{value="OUTLINE"}}
    local size=21 -- Nome no layout de referência 1280x720; mesma altura em todas as combinações.
    report(addon.Text.fontsHeader)
    for _, file in ipairs(controls) do
        local outcomes={}
        for index,flag in ipairs(flags) do
            local success,fault=setFont(probe,file.path,size,flag.value)
            outcomes[index]=success and addon.Text.fontsSuccess or fault and addon.Text.fontsError or addon.Text.fontsRejected
            addon.DiagnosticAPI.Record("interface","font_test",detail(result(file.path,flag.value,size,success),fault),
                {gameEvent="COMMAND_FONTES",stage="font_probe"})
        end
        report(string.format(addon.Text.fontsLine,file.name,size,outcomes[1],outcomes[2],outcomes[3]))
    end
end
