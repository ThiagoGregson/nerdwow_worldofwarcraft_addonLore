local _, addon = ...
local Button = { EDGE_OFFSET = 8, DRAG_THRESHOLD = 4 }
addon.MinimapButton = Button

-- Coordenadas locais do minimapa: direita = 0 graus; acima = 90 graus.
function Button.Position(angle, width, height, shape)
    local radians = math.rad(angle)
    local x, y = math.cos(radians), math.sin(radians)
    if shape == "SQUARE" then
        local edge = math.max(math.abs(x), math.abs(y))
        x, y = x / edge, y / edge
    end
    return x * (width / 2 + Button.EDGE_OFFSET), y * (height / 2 + Button.EDGE_OFFSET)
end

function Button.Angle(x, y, width, height)
    if x == 0 and y == 0 then return nil end
    return math.deg(math.atan2(y / (height / 2 + Button.EDGE_OFFSET),
        x / (width / 2 + Button.EDGE_OFFSET))) % 360
end

function Button.NewGesture()
    local startX, startY, dragging
    local gesture = {}
    function gesture.Press(x, y)
        startX, startY, dragging = x, y, false
    end
    function gesture.Move(x, y)
        if not startX then return false end
        if (x - startX) ^ 2 + (y - startY) ^ 2 >= Button.DRAG_THRESHOLD ^ 2 then
            dragging = true
        end
        return dragging
    end
    function gesture.Release()
        if not startX then return nil end
        local action = dragging and "drag" or "click"
        startX, startY, dragging = nil, nil, false
        return action
    end
    function gesture.Cancel()
        startX, startY, dragging = nil, nil, false
    end
    function gesture.IsDragging()
        return dragging == true
    end
    return gesture
end

function Button.Tooltip(view, text)
    local lines = { string.format(text.buttonTitle, view.version) }
    if view.blockedReason then
        lines[#lines + 1] = string.format(text.blocked, view.blockedReason)
    else
        lines[#lines + 1] = string.format(text.buttonTotal, view.totalEvents)
        lines[#lines + 1] = string.format(text.buttonPending, view.pendingEvents)
        lines[#lines + 1] = string.format(text.buttonLast, view.lastTime)
    end
    lines[#lines + 1] = " "
    lines[#lines + 1] = text.buttonClick
    lines[#lines + 1] = text.buttonDrag
    return lines
end
