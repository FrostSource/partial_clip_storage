
---Rough values where the attachment Z value will be at for each bullet count.
local ammoZValues = {
    1.247, -- 0
    0.888, -- 1
    0.529, -- 2
    0.170, -- 3
    -0.190, -- 4
    -0.549, -- 5
    -0.908, -- 6
    -1.267, -- 7
    -1.625, -- 8
    -1.984, -- 9
    -2.343, -- 10
}

---Custom model with attachment used to find ammo count.
local CLIP_PROXY_MODEL = "models/weapons/vr_alyxgun/vr_alyxgun_clip_proxy.vmdl"

GlobalPrecache("model", CLIP_PROXY_MODEL)

---commentary_started
---@param params GAME_EVENT_PLAYER_ATTEMPTED_INVALID_PISTOL_CLIP_STORAGE
ListenToGameEvent("player_attempted_invalid_pistol_clip_storage", function(params)

    local hand = Player.Hands[Util.GetHandIdFromTip(params.vr_tip_attachment) + 1]

    ---@type EntityHandle
    local clip

    if hand.LastClassDropped == "item_hlvr_clip_energygun" then
        -- print("Found clip from drop")
        clip = hand.LastItemDropped
    else
        warn("Clip wasn't found from hand drop, using nearest clip...")
        clip = Entities:FindByClassnameNearest("item_hlvr_clip_energygun", hand:GetCenter(), 64)
    end

    if not clip then
        warn("Partial clip was not found for some reason!")
        return
    end

    local bulletCount = GetBulletCountFromPistolClip(clip)

    devprint2("Storing partial clip with " .. bulletCount .. " bullets")

    SendToServerConsole("hlvr_addresources " .. bulletCount .. " 0 0 0")

    -- Kill the clip entity after ammo was added to inventory
    clip:Kill()

    ---@TODO Best way to play sound?
    StartSoundEventFromPositionReliable("Inventory.DepositItem", Player:EyePosition())

    local instructorEnabled = Convars:GetStr("gameinstructor_enable")
    SendToConsole("gameinstructor_enable 0")
    SendToConsole("gameinstructor_enable " .. instructorEnabled)
    ---@TODO Instructor sound still plays, is there a way to stop it?

end, nil)

function GetBulletCountFromPistolClip(clip)
    local proxy = SpawnEntityFromTableSynchronous("prop_dynamic", {
        model = CLIP_PROXY_MODEL,
        rendermode = "kRenderNone"
    })
    proxy:FollowEntity(clip, true)

    local bulletCount = -1

    local z = proxy:TransformPointWorldToEntity(proxy:GetAttachmentOrigin(1)).z
    for ind, val in ipairs(ammoZValues) do
        if z >= val then
            bulletCount = ind - 1
            break
        end
    end

    proxy:Kill()
    return bulletCount
end