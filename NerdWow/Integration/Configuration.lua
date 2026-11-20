local _,addon=...
local UI={}
addon.ConfigurationUI=UI
local services,book,view,deadline,canvas
local flags,fontReport={},{}
local function fail(fault,stage)
    deadline=nil
    if view then pcall(view.Hide) end
    addon.DiagnosticAPI.Record("interface","configuration_error",fault,{stage=stage or "configuration"})
    addon.Wow.Print(addon.Text.configFailed)
end
local function safe(callback,stage)
    return function(...)
        local ok,value,code=addon.DiagnosticAPI.Try(callback,...)
        if not ok then fail(value,stage); return nil end
        return value,code
    end
end
function UI.Context()
    local r=addon.DialogueAPI.Reader()
    local map=r.Number(r.Call(C_Map.GetBestMapForUnit,"player"),1)
    local faction=r.String(r.Call(UnitFactionGroup,"player"))
    return {mapID=map},{faction=faction}
end
function UI.IsOpen() return view and view.IsOpen() or false end
function UI.Close() deadline=nil; if view then view.Hide() end end
function UI.Refresh()
    if not UI.IsOpen() then return end
    safe(function()
        local location,character=UI.Context()
        local theme=addon.DialogueThemes.Resolve(location,character,services.Settings.Read("theme"))
        local ready=view.Render(book.Snapshot(),theme)
        if ready then deadline=nil
        elseif not deadline then
            local ticket={}; deadline=ticket
            if not addon.ConversationPlatform.Defer(function()
                if deadline==ticket then fail(addon.DiagnosticAPI.Capture("configuration_preparation_timeout"),"configuration_prepare") end
            end,2) then error("defer_unavailable") end
        end
    end,"configuration_layout")()
end
function UI.RefreshInfo()
    UI.Refresh()
end
function UI.Open()
    if not services then addon.Wow.Print(addon.Text.configNotReady); return false end
    return safe(function()
        if not view then
            view=addon.ConfigurationView.New({Select=function(id) book.Select(id); UI.Refresh() end,
                Move=function(delta) book.Move(delta); UI.Refresh() end,
                Write=function(id,value) return book.Write(id,value) end,
                Action=function(id) return book.Activate(id) end,
                Reset=function() book.RequestReset() end,Close=UI.Close,
                Error=fail,Ready=UI.Refresh})
        end
        view.Open(); UI.Refresh(); return UI.IsOpen()
    end,"configuration_open")()==true
end
local function diagnosticText()
    local recent,code=services.Diagnostics()
    if not recent then return string.format(addon.Text.diagnosticsBlocked,addon.Text.errors[code] or code) end
    local lines={}
    for _,entry in ipairs(recent) do
        local context=entry.context or {}
        lines[#lines+1]=string.format("%s · %s (%dx) · v%s\n%s%s",
            entry.lastTimestamp and addon.Wow.FormatTime(entry.lastTimestamp) or addon.Text.noTime,
            addon.DiagnosticAPI.ChatText(entry.code),entry.count,entry.version or addon.Text.unavailable,
            addon.DiagnosticAPI.DisplayText(entry.message or addon.Text.diagnosticsRedacted),
            context.stage and "\n"..addon.DiagnosticAPI.ChatText(context.stage) or "")
    end
    return #lines>0 and table.concat(lines,"\n\n") or addon.Text.diagnosticsEmpty
end
function UI.Initialize(options)
    services=options
    local actions={
        Sync=function() UI.Close(); addon.Wow.RequestSync(); return true end,
        Diagnostics=function() flags.records=true; UI.Refresh(); return true end,
        Fonts=function()
            flags.fonts=true; fontReport={}; UI.Refresh()
            addon.FontAPI.Test(function(message)
                fontReport[#fontReport+1]=message; addon.Wow.Print(message); UI.Refresh()
            end)
            return true
        end,
    }
    book=addon.ConfigurationBook.New({Registry=addon.ConfigurationCatalog,Settings=options.Settings,
        CanAct=function() return not InCombatLockdown() end,
        IsVisible=function(key) return flags[key]==true end,
        ReadInfo=function(key)
            if key=="diagnostics.records" then return diagnosticText() end
            if key=="fonts.report" then return table.concat(fontReport,"\n") end
            if key=="about.version" then return addon.Wow.Version() end
            if key=="about.site" then return "gregson.com.br" end
            if key=="about.github" then return "https://github.com/ThiagoGregson/nerdwow_worldofwarcraft_addonLore" end
            if key=="about.credits" then return addon.Text.configCredits end
            return options.ReadInfo(key)
        end,
        Action=function(id) return addon.ConfigurationCatalog.RunAction(id,actions) end,
        ConfirmReset=function(callback) if view then view.Confirm(callback) end end})
    safe(UI.Register,"configuration_register")()
end
function UI.Register()
    if canvas then return true end
    local api=Settings
    if type(api)~="table" or type(api.RegisterCanvasLayoutCategory)~="function" then
        if UIParent and type(C_AddOns.LoadAddOn)=="function" and not InCombatLockdown() then
            C_AddOns.LoadAddOn("Blizzard_Settings"); api=Settings
        end
    end
    if type(api)~="table" or type(api.RegisterCanvasLayoutCategory)~="function" then
        if UIParent then addon.DiagnosticAPI.Record("interface","settings_api_unavailable",{message="settings_api_unavailable"},{stage="configuration_register"}) end
        return false
    end
    canvas=CreateFrame("Frame",nil,UIParent); canvas:Hide()
    local title=canvas:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    title:SetPoint("TOPLEFT",canvas,"TOPLEFT",24,-24); title:SetText("NerdWow")
    local description=canvas:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    description:SetPoint("TOPLEFT",title,"BOTTOMLEFT",0,-14); description:SetWidth(480)
    description:SetJustifyH("LEFT"); description:SetText(addon.Text.configCanvas)
    local button=CreateFrame("Button",nil,canvas,"UIPanelButtonTemplate")
    button:SetSize(180,28); button:SetPoint("TOPLEFT",description,"BOTTOMLEFT",0,-20)
    button:SetText(addon.Text.configOpen); button:SetScript("OnClick",UI.Open)
    canvas:SetScript("OnShow",UI.Open)
    local category=api.RegisterCanvasLayoutCategory(canvas,"NerdWow")
    api.RegisterAddOnCategory(category)
    return true
end
