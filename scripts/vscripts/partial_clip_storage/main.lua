
local version = "v1.2.0"

RegisterAlyxLibAddon("Partial Clip Storage", version, "3329684800", nil, "v1.3.1", nil)

---Failover mode is enabled when ammo can't be determined from a clip.
---This is most likely due to the clip being a custom model.
---Failover mode tracks bullet count using game events.
local failoverEnabled = false

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

GlobalPrecache:Add("model", CLIP_PROXY_MODEL)

local function enableFailover()
    failoverEnabled = true

    ---Failover: Update bullet count on pistol clip insert
    ---@param params GameEventPlayerPistolClipInserted
    ListenToGameEvent("player_pistol_clip_inserted", function (params)
        -- Clip is not parented at this point so we delay, thanks Valve
        Player:Delay(function()
            local clip = GetCurrentClipInPistol()
            if clip then
                if type(params.bullet_count) == "number" then
                    clip:Attribute_SetIntValue("BulletCount", params.bullet_count)
                else
                    local bulletCount = clip:Attribute_GetIntValue("BulletCount", 9)
                    clip:Attribute_SetIntValue("BulletCount", bulletCount)
                end
            end
        end, 0.1)
    end, nil)

    ---Failover: Subtract a bullet when pistol is chambered
    ---@param params GameEventPlayerPistolChamberedRound
    ListenToGameEvent("player_pistol_chambered_round", function (params)
        local clip = GetCurrentClipInPistol()
        if clip then
            local bulletCount = clip:Attribute_GetIntValue("BulletCount", 9)
            bulletCount = bulletCount - 1
            clip:Attribute_SetIntValue("BulletCount", bulletCount)
        end
    end, nil)

    ---Failover: Subtract a bullet when player shoots the pistol
    ---@param params GameEventPlayerShootWeapon
    ListenToGameEvent("player_shoot_weapon", function (params)
        if Player.CurrentlyEquipped == "hlvr_weapon_energygun" then
            local clip = GetCurrentClipInPistol()
            if clip then
                local bulletCount = clip:Attribute_GetIntValue("BulletCount", 9)
                bulletCount = bulletCount - 1
                clip:Attribute_SetIntValue("BulletCount", bulletCount)
            end
        end
    end, nil)
end

---Incompatible addons are those that change the clip model
local unsupportedAddons = {
    ["2260861413"] = "USP Match (Half-Life 2 Pistol)",
}

local addonList = GetEnabledAddons()
for addonID, addonDesc in pairs(unsupportedAddons) do
    if vlua.find(addonList, addonID) then
        Msg("Partial Clip Storage: Incompatible addon detected - " .. addonDesc .. " (" .. addonID .. ").\nSwitching to alternative tracking mode...\n")
        enableFailover()
        break
    end
end

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

    local bulletCount = -1
    if failoverEnabled then
        bulletCount = clip:Attribute_GetIntValue("BulletCount", -1)
    else
        bulletCount = GetBulletCountFromPistolClip(clip)
        if bulletCount < 0 then
            warn("Could not determine the number of bullets in the clip, switching to alternative tracking...")
            enableFailover()
            bulletCount = clip:Attribute_GetIntValue("BulletCount", -1)
        end
    end

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
    if failoverEnabled then
        return clip:Attribute_GetIntValue("BulletCount", -1)
    end

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

---
---Get the current clip of a pistol.
---
---@param pistol? EntityHandle # The pistol to get the current clip of, defaults to the player's pistol.
function GetCurrentClipInPistol(pistol)
    pistol = pistol or Player.Items.weapons.energygun;
    if pistol then
        return pistol:GetChild("item_hlvr_clip_energygun")
    end
    return nil
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
                if not failoverEnabled then
                    print("Could not determine the number of bullets in the pistol's magazine, switching to alternative tracking...")
                    enableFailover()
                else
                    print("Could not determine the number of bullets in the pistol's magazine.")
                end
            end
        else
            print("No clip found in the pistol.")
        end
    end
end, "(partial_clip_storange) Prints the number of bullets in the pistol's magazine if found")
