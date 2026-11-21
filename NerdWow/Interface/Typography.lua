local _,addon=...
local Typography={MINIMUM=13}
addon.Typography=Typography
local ratios={note=.85,body=1,speech=1.1,heading=1.05,title=1.4,initial=2}
local function positive(value)
    return type(value)=="number" and value>0 and value<math.huge
end
-- All dimensions here are plain numbers. The adapter supplies the client's
-- physical height and pixels per UI unit, including its 768-unit conversion.
function Typography.Build(physicalHeight,pixelsPerUIUnit,percent)
    if percent==nil then percent=100 end
    if not positive(physicalHeight) or not positive(pixelsPerUIUnit)
        or type(percent)~="number" or percent<80 or percent>140 or percent%5~=0 then
        return nil,"invalid_typography"
    end
    local physicalBody=math.max(Typography.MINIMUM,(3+physicalHeight/72)*percent/100)
    local result={minimum=Typography.MINIMUM/pixelsPerUIUnit,pixelsPerUIUnit=pixelsPerUIUnit,
        physicalHeight=physicalHeight,percent=percent}
    for role,ratio in pairs(ratios) do
        result[role]=math.max(Typography.MINIMUM,physicalBody*ratio)/pixelsPerUIUnit
    end
    result.unit=result.body/18
    result.line=result.body*1.45
    result.gap=result.body*.15
    return result
end
