local _, addon = ...
local Settings = { VERSION = 1 }
addon.Settings = Settings

local function validAngle(value)
    return type(value) == "number" and value == value and value >= 0 and value < 360
end

function Settings.Open(saved)
    local root, repaired = saved, {}
    if type(root) ~= "table" then
        root = { schemaVersion = Settings.VERSION, minimapHidden = false, minimapAngle = 225, dialogEnabled = true }
        if saved ~= nil then repaired[#repaired + 1] = "root" end
    end
    if root.schemaVersion ~= Settings.VERSION then
        if root.schemaVersion ~= nil then repaired[#repaired + 1] = "schemaVersion" end
        root.schemaVersion = Settings.VERSION
    end
    if type(root.minimapHidden) ~= "boolean" then
        if root.minimapHidden ~= nil then repaired[#repaired + 1] = "minimapHidden" end
        root.minimapHidden = false
    end
    if not validAngle(root.minimapAngle) then
        if root.minimapAngle ~= nil then repaired[#repaired + 1] = "minimapAngle" end
        root.minimapAngle = 225
    end
    if type(root.dialogEnabled) ~= "boolean" then
        if root.dialogEnabled ~= nil then repaired[#repaired + 1] = "dialogEnabled" end
        root.dialogEnabled = true
    end
    local handle = {}
    function handle.Get()
        return { schemaVersion = root.schemaVersion,
            minimapHidden = root.minimapHidden, minimapAngle = root.minimapAngle, dialogEnabled = root.dialogEnabled }
    end
    function handle.SetAngle(angle)
        if not validAngle(angle) then return nil, "invalid_angle" end
        root.minimapAngle = angle
        return true
    end
    function handle.ToggleHidden()
        root.minimapHidden = not root.minimapHidden
        return root.minimapHidden
    end
    function handle.ToggleDialog()
        root.dialogEnabled = not root.dialogEnabled
        return root.dialogEnabled
    end
    return handle, root, repaired
end
