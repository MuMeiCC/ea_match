return function(rules)
    local I = {}
    function I.hasLivingLostSoul()
        local player = Isaac.GetPlayer(0)
        if player:GetCollectibleNum(612, true) <= 0 then return false end
        for _, entity in ipairs(Isaac.FindByType(3, 211, 0, false, false)) do
            local familiar = entity:ToFamiliar()
            if familiar and familiar.Player and familiar.Player.InitSeed == player.InitSeed
                and familiar:Exists() and not familiar:IsDead() and familiar.Visible then
                -- The death animation can remain after the familiar has stopped following.
                local animation = familiar:GetSprite():GetAnimation():lower()
                if not animation:find("death", 1, true) and not animation:find("dead", 1, true)
                    and animation ~= "die" then return true end
            end
        end
        return false
    end

    function I.removeBanned(player)
        -- Vanilla has no pre-AddCollectible callback. Catch direct grants/crafting
        -- on player update, and again before taking a scoring snapshot.
        for slot = 0, 3 do
            local id = player:GetActiveItem(slot)
            if rules.banned[id] then
                player:RemoveCollectible(id, true, slot)
                if player:GetActiveItem(slot) ~= id then player:AddCollectible(25, 0, true) end
            end
        end
        for id in pairs(rules.banned) do
            local count = player:GetCollectibleNum(id, true)
            for _ = 1, count do
                local before = player:GetCollectibleNum(id, true)
                player:RemoveCollectible(id, true)
                if player:GetCollectibleNum(id, true) >= before then break end
                player:AddCollectible(25, 0, true)
            end
        end
    end
    function I.read()
        local player = Isaac.GetPlayer(0)
        I.removeBanned(player)
        local v = { coins = player:GetNumCoins(), bombs = player:GetNumBombs(),
            keys = player:GetNumKeys(), items = {}, pockets = 0, trinkets = 0,
            goldTrinkets = 0, forms = 0, red = player:GetHearts(),
            soul = player:GetSoulHearts(), eternal = player:GetEternalHearts(),
            bone = player:GetBoneHearts(), rotten = player:GetRottenHearts(),
            golden = player:GetGoldenHearts() }
        local config = Isaac.GetItemConfig()
        -- Original Repentance API: true excludes temporary granted effects.
        local pocket = {}
        for slot = 2, 3 do
            local id = player:GetActiveItem(slot)
            if id ~= 0 then pocket[id] = (pocket[id] or 0) + 1 end
        end
        for id = 1, config:GetCollectibles().Size - 1 do
            local item = config:GetCollectible(id)
            local amount = player:GetCollectibleNum(id, true)
            local n = math.max(0, amount - (pocket[id] or 0))
            if item and n > 0 then
                table.insert(v.items, { id = id, count = n, quality = item.Quality })
            end
        end
        for slot = 0, 3 do
            if player:GetCard(slot) ~= 0 or player:GetPill(slot) ~= 0 then v.pockets = v.pockets + 1 end
        end
        -- The vanilla multiplier is normal copies + 2 * gold copies + Mom's Box.
        -- This is exactly the weighting needed for 20/40 points; there is no need
        -- to reconstruct how many of each color were swallowed. Do not gate this
        -- on HasTrinket(id, true): swallowed trinkets must remain eligible.
        -- Remove the box's one extra effect per type.
        v.trinketUnits = 0
        local box = player:HasCollectible(439) and 1 or 0
        for id = 1, config:GetTrinkets().Size - 1 do
            if config:GetTrinket(id) then
                v.trinketUnits = v.trinketUnits + math.max(0, player:GetTrinketMultiplier(id) - box)
            end
        end
        for form = 0, PlayerForm.NUM_PLAYER_FORMS - 1 do
            if player:HasPlayerForm(form) then v.forms = v.forms + 1 end
        end
        -- The Forgotten's soul carries separate health, but shares inventory.
        local pt = player:GetPlayerType()
        if pt == 16 or pt == 17 then
            local other = player:GetSubPlayer()
            if other then
                v.red = v.red + other:GetHearts()
                v.soul = v.soul + other:GetSoulHearts()
                v.eternal = v.eternal + other:GetEternalHearts()
                v.bone = v.bone + other:GetBoneHearts()
                v.rotten = v.rotten + other:GetRottenHearts()
                v.golden = v.golden + other:GetGoldenHearts()
            end
        end
        return v
    end
    return I
end
