
local version = "v1.1.0"

RegisterAlyxLibAddon("partial_clip_storage", "Partial Clip Storage", "3329684800", "clip_storage", "v1.3.1", nil)

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

---Rough values where the attachment Z value will be at for each bullet count in the left hand.
---If storing a second table is unwanted we can generate these values using: (-ammoZValues[i] - 6.477)
local ammoZValuesLeftHand = {
    -7.724, -- 0
    -7.366, -- 1
    -7.007, -- 2
    -6.648, -- 3
    -6.289, -- 4
    -5.930, -- 5
    -5.572, -- 6
    -5.213, -- 7
    -4.854, -- 8
    -4.495, -- 9
    -4.136, -- 10
}

---Custom model with attachment used to find ammo count.
local CLIP_PROXY_MODEL = "models/weapons/vr_alyxgun/vr_alyxgun_clip_proxy.vmdl"

GlobalPrecache("model", CLIP_PROXY_MODEL)

---Game event for player trying to store partially empty pistol clip
---@param params GameEventPlayerAttemptedInvalidPistolClipStorage
ListenToGameEvent("player_attempted_invalid_pistol_clip_storage", function(params)

    local hand = Player.Hands[Util.GetHandIdFromTip(params.vr_tip_attachment) + 1]

    ---@type EntityHandle
    local clip

    if hand.LastClassDropped == "item_hlvr_clip_energygun" then
        clip = hand.LastItemDropped
    else
        warn("Clip wasn't found from hand drop, using nearest clip...")
        ---@TODO Player can throw into backpack so closest to hand might be wrong
        ---      Closest to backpack might also be wrong if player holds loaded gun close
        ---      or a clip is on a table behind them
        ---@TODO Check for hand.PreviouslyDropped
        clip = Entities:FindByClassnameNearest("item_hlvr_clip_energygun", hand:GetCenter(), 64)
    end

    if not clip then
        warn("Partial clip was not found for some reason!")
        return
    end

    local bulletCount = GetBulletCountFromPistolClip(clip)

    if bulletCount == 0 then
        devprint2("Clip is empty, not storing")
        return
    elseif bulletCount < 0 then
        warn("Could not determine the number of bullets in the clip, aborting storage.")
        return
    end

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

---
---Get the amount of bullets in a pistol clip(magazine).
---
---@param clip EntityHandle
---@return integer # The number of bullets in the clip, or -1 if it could not be determined.
function GetBulletCountFromPistolClip(clip)
    local proxy = SpawnEntityFromTableSynchronous("prop_dynamic", {
        model = CLIP_PROXY_MODEL,
        rendermode = "kRenderNone"
    })
    proxy:FollowEntity(clip, true)

    local bulletCount = -1

    local z = proxy:TransformPointWorldToEntity(proxy:GetAttachmentOrigin(1)).z
    local values = Convars:GetBool("hlvr_left_hand_primary") and ammoZValuesLeftHand or ammoZValues

    for ind, val in ipairs(values) do
        if math.isclose(z, val, nil, 0.05) then
            bulletCount = ind - 1
            break
        end
    end

    proxy:Kill()
    return bulletCount
end

RegisterAlyxLibCommand("print_bullets_in_gun_clip", function ()
    local pistol = Player.Items.weapons.energygun;
    if pistol then
        local clip = pistol:GetChild("item_hlvr_clip_energygun")
        if clip then
            local bulletCount = GetBulletCountFromPistolClip(clip)
            if bulletCount >= 0 then
                print("Bullets in the pistol's magazine: " .. bulletCount)
            else
                print("Could not determine the number of bullets in the pistol's magazine.")
            end
        else
            print("No clip found in the pistol.")
        end
    end
end, "(partial_clip_storange) Prints the number of bullets in the pistol's magazine if found")
