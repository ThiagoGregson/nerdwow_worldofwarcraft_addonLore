local _, addon = ...
local MinimapUI = {}
addon.MinimapUI = MinimapUI

function MinimapUI.Create(options)
    local geometry = addon.MinimapButton
    local gesture = geometry.NewGesture()
    local button = CreateFrame("Button", nil, Minimap)
    button:SetSize(32, 32)
    button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetHitRectInsets(2, 2, 2, 2)

    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetSize(24, 24)
    mask:SetPoint("CENTER")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetColorTexture(0.06, 0.05, 0.03, 1)
    background:SetAllPoints(mask)
    background:AddMaskTexture(mask)

    -- Ícone provisório; a troca pelo emblema original será uma entrega separada.
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER")
    icon:AddMaskTexture(mask)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(52, 52)
    border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    local highlight = button:GetHighlightTexture()
    highlight:SetAllPoints(button)
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    local pushed = button:GetPushedTexture()
    pushed:ClearAllPoints()
    pushed:SetPoint("CENTER")
    pushed:SetSize(24, 24)
    pushed:AddMaskTexture(mask)

    local function pressed(down)
        icon:ClearAllPoints()
        icon:SetPoint("CENTER", button, "CENTER", down and 1 or 0, down and -1 or 0)
        local shade = down and 0.65 or 1
        icon:SetVertexColor(shade, shade, shade)
    end
    local function position()
        local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
        local x, y = geometry.Position(options.GetSettings().minimapAngle,
            Minimap:GetWidth(), Minimap:GetHeight(), shape)
        button:ClearAllPoints()
        button:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end
    local function cursor()
        local x, y = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        return x / scale, y / scale
    end
    local function hideTooltip()
        if GameTooltip:IsOwned(button) then GameTooltip:Hide() end
    end
    local function showTooltip()
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        local lines = options.GetTooltip()
        GameTooltip:SetText(lines[1], 1, 0.82, 0)
        for index = 2, #lines do GameTooltip:AddLine(lines[index], 1, 1, 1, true) end
        GameTooltip:Show()
    end
    local function move()
        local x, y = cursor()
        if gesture.Move(x, y) then
            hideTooltip()
            local centerX, centerY = Minimap:GetCenter()
            local angle = geometry.Angle(x - centerX, y - centerY, Minimap:GetWidth(), Minimap:GetHeight())
            if angle then options.SetAngle(angle); position() end
        end
    end
    local function stop()
        button:SetScript("OnUpdate", nil)
        gesture.Cancel()
        pressed(false)
    end
    button:SetScript("OnMouseDown", function(_, mouseButton)
        if mouseButton ~= "LeftButton" then return end
        gesture.Press(cursor())
        pressed(true)
        button:SetScript("OnUpdate", move)
    end)
    button:SetScript("OnMouseUp", function(_, mouseButton, inside)
        if mouseButton=="RightButton" then
            local dragging=gesture.IsDragging(); stop()
            if not dragging and inside~=false and options.OnRightClick then options.OnRightClick() end
            return
        end
        if mouseButton ~= "LeftButton" then return end
        move()
        local action = gesture.Release()
        stop()
        if action == "click" and inside ~= false then options.OnClick() end
    end)
    button:SetScript("OnEnter", function()
        position()
        if not gesture.IsDragging() then showTooltip() end
    end)
    button:SetScript("OnLeave", hideTooltip)
    button:SetScript("OnHide", function() stop(); hideTooltip() end)
    Minimap:HookScript("OnSizeChanged", position)
    local handle = {}
    function handle.Refresh()
        position()
        button:SetShown(not options.GetSettings().minimapHidden)
    end
    function handle.RefreshTooltip()
        if GameTooltip:IsOwned(button) then showTooltip() end
    end
    handle.Refresh()
    return handle
end
