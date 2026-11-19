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
        repaired[#repaired + 1] = "root"
    end
    if root.schemaVersion ~= Settings.VERSION then
        root.schemaVersion = Settings.VERSION
        repaired[#repaired + 1] = "schemaVersion"
    end
    if type(root.minimapHidden) ~= "boolean" then
        root.minimapHidden = false
        repaired[#repaired + 1] = "minimapHidden"
    end
    if not validAngle(root.minimapAngle) then
        root.minimapAngle = 225
        repaired[#repaired + 1] = "minimapAngle"
    end
    if type(root.dialogEnabled) ~= "boolean" then
        root.dialogEnabled = true
        repaired[#repaired + 1] = "dialogEnabled"
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
