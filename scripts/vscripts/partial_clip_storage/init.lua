-- This file was automatically generated by alyxlib.

-- alyxlib can only run on server
if IsServer() then
    -- Load alyxlib before using it, in case this mod loads before the alyxlib mod.
    require("alyxlib.init")

    -- execute code or load mod libraries here
    require("partial_clip_storage.main")
end
