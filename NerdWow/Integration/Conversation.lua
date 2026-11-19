local _, addon = ...
local Platform = {}
addon.ConversationPlatform = Platform
local states, activeRoot, notify = {},nil,nil
local hooked = {}
local function plain(value)
    if issecretvalue and issecretvalue(value) then error("restricted_interface") end
    return value
end
function Platform.Defer(callback)
    if type(C_Timer)~="table" or type(C_Timer.After)~="function" then return false end
    C_Timer.After(0,callback)
    return true
end
function Platform.CanPresent()
    return not plain(InCombatLockdown()) and UIParent~=nil and UIParent~=false
end
function Platform.RestoreNative()
    activeRoot,notify=nil,nil
    local remaining,failures={},{}
    local api=addon.DiagnosticAPI
    local attempt=api and api.Try or pcall
    local function restore(fn,frame,value)
        local ok,fault=attempt(fn,frame,value)
        if not ok then failures[#failures+1]=fault end
        return ok
    end
    for _, state in ipairs(states) do
        local ok=true
        if state.alpha~=nil then ok=restore(state.frame.SetAlpha,state.frame,state.alpha) and ok end
        if state.mouse~=nil then ok=restore(state.frame.EnableMouse,state.frame,state.mouse) and ok end
        if state.keyboard~=nil then ok=restore(state.frame.EnableKeyboard,state.frame,state.keyboard) and ok end
        if not ok then remaining[#remaining+1]=state end
    end
    states=remaining
    if #remaining>0 then
        if api then
            for index=2,#failures do api.Record("interface","native_restore_failed",failures[index],{stage="restore"}) end
            api.Raise(failures[1],"native_restore_failed")
        end
        error("native_restore_failed")
    end
end
function Platform.TakeNative(moment,onShow)
    if not Platform.CanPresent() then error("combat_interface") end
    Platform.RestoreNative()
    local root=moment=="GOSSIP" and GossipFrame or QuestFrame
    if not root then error("native_frame_unavailable") end
    local collected,visited={},{}
    local function visit(frame)
        if visited[frame] then return end
        visited[frame]=true
        if #collected>=1024 or (frame.IsForbidden and plain(frame:IsForbidden()))
            or (frame.IsProtected and plain(frame:IsProtected())) then error("native_frame_restricted") end
        local state={frame=frame}
        if frame==root then
            state.alpha=plain(frame:GetAlpha())
            if type(state.alpha)~="number" then error("native_alpha_unavailable") end
        end
        if frame.IsMouseEnabled then state.mouse=plain(frame:IsMouseEnabled()) end
        if frame.IsKeyboardEnabled then state.keyboard=plain(frame:IsKeyboardEnabled()) end
        collected[#collected+1]=state
        if frame.GetChildren then for _, child in ipairs({frame:GetChildren()}) do visit(child) end end
    end
    visit(root)
    -- Captura toda a transação antes da primeira alteração, inclusive filhos.
    states=collected
    for _, state in ipairs(states) do
        if state.mouse~=nil then state.frame:EnableMouse(false) end
        if state.keyboard~=nil then state.frame:EnableKeyboard(false) end
    end
    root:SetAlpha(0)
    if not hooked[root] then
        root:HookScript("OnShow",function()
            if activeRoot==root and notify then notify() end
        end)
        hooked[root]=true
    end
    activeRoot,notify=root,onShow
end
local function invoke(fn,...)
    if type(fn)~="function" then error("interaction_unavailable") end
    fn(...)
end
function Platform.Select(entry,moment)
    if not Platform.CanPresent() then error("combat_interface") end
    if moment=="GREETING" then
        if entry.action=="AVAILABLE" then invoke(SelectAvailableQuest,entry.value)
        elseif entry.action=="ACTIVE" then invoke(SelectActiveQuest,entry.value)
        else error("invalid_interaction") end
    elseif moment=="GOSSIP" and type(C_GossipInfo)=="table" then
        if entry.action=="AVAILABLE" then invoke(C_GossipInfo.SelectAvailableQuest,entry.value)
        elseif entry.action=="ACTIVE" then invoke(C_GossipInfo.SelectActiveQuest,entry.value)
        elseif entry.action=="OPTION_ID" then invoke(C_GossipInfo.SelectOption,entry.value)
        elseif entry.action=="OPTION_INDEX" then invoke(C_GossipInfo.SelectOptionByIndex,entry.value)
        else error("invalid_interaction") end
    else error("invalid_interaction") end
end
function Platform.Close(moment)
    if moment=="GOSSIP" and type(C_GossipInfo)=="table" then invoke(C_GossipInfo.CloseGossip)
    elseif moment=="GREETING" then invoke(CloseQuest)
    else error("invalid_interaction") end
end
function Platform.KeyAllowed()
    if plain(InCombatLockdown()) then return false end
    if GetCurrentKeyBoardFocus and plain(GetCurrentKeyBoardFocus()) then return false end
    if plain(IsControlKeyDown()) or plain(IsAltKeyDown()) or plain(IsShiftKeyDown()) then return false end
    return true
end
