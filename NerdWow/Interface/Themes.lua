local _, addon = ...
local Themes = {}
addon.DialogueThemes = Themes
local maps = { [94]=true, [95]=true, [110]=true, [122]=true, [2393]=true, [2395]=true,
    [2424]=true, [2432]=true, [2443]=true, [2537]=true, [2565]=true, [2566]=true, [2594]=true, [2605]=true }
local definitions = {
    quelthalas = { accent="e0a33f", secondary="b8323f", glow="ffd38a",
        crest="Interface\\Icons\\INV_Misc_Tournaments_banner_BloodElf", roundCrest=true },
    alliance = { accent="4f86d1", secondary="d7b45a", glow="ffe3a3",
        crest="Interface\\FriendsFrame\\PlusManz-Alliance" },
    horde = { accent="c4472c", secondary="c9a15a", glow="ffb36b",
        crest="Interface\\FriendsFrame\\PlusManz-Horde" },
    neutral = { accent="7fa58c", secondary="c2a56a", glow="d9f0dc",
        crest="Interface\\Minimap\\UI-Minimap-WorldMapIcon", roundCrest=true },
}
function Themes.Resolve(location, npc)
    local key = "neutral"
    if location and maps[location.mapID] then key = "quelthalas"
    elseif npc and npc.faction == "Alliance" then key = "alliance"
    elseif npc and npc.faction == "Horde" then key = "horde" end
    local result = { key=key, night="07060a", subtitle="f3e9d2", option="d8ccb4", muted="a99d86" }
    for field, value in pairs(definitions[key]) do result[field] = value end
    return result
end
