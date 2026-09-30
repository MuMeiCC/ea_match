local mod = RegisterMod("ea_match", 1)
local json = require("json")
local Rules = include("scripts.rules")
local Inventory = include("scripts.inventory")(Rules)
local Routes = include("scripts.routes")()
local game = Game()
local font = Font()
local fontReady, fontAttempted, readingMenuInput = false, false, false
local function loadFont()
    if fontAttempted then return fontReady end
    fontAttempted = true
    local suffix = "resources/font/ea_match/eid9_9px.fnt"
    local paths = {}
    -- Font.Load reads filesystem paths, not the merged mod resource namespace.
    -- debug is unavailable in some vanilla builds; require's search paths are a fallback.
    if debug and debug.getinfo then
        local ok, info = pcall(debug.getinfo, loadFont, "S")
        if ok and info and info.source then
            local base = info.source:gsub("^@", ""):match("^(.*[/\\])")
            if base then table.insert(paths, base .. suffix) end
        end
    end
    local _, searchPaths = pcall(require, "")
    if type(searchPaths) == "string" then
        local base = searchPaths:match("(%a:[/\\][^'\r\n]-[/\\]mods[/\\]ea_match[/\\])")
        if base then table.insert(paths, base .. suffix) end
    end
    table.insert(paths, "mods/ea_match/" .. suffix)
    table.insert(paths, "../mods/ea_match/" .. suffix)
    for _, path in ipairs(paths) do
        local ok = pcall(function() font:Load(path, "") end)
        if ok and font:IsLoaded() then
            fontReady = true
            Isaac.DebugString("[ea_match] Font loaded: " .. path)
            return true
        end
    end
    Isaac.DebugString("[ea_match] Font load failed; tried: " .. table.concat(paths, " | "))
    return false
end
local white, yellow = KColor(1, 1, 1, 1), KColor(1, 0.85, 0.3, 1)
local match, selected, active, loaded = nil, 1, false, false
local blocked, menu, dirtyRoom = nil, false, false
local lastMs, lastSave = nil, 0
local currentRoom, clearPending, sawBoss = nil, false, false
local bossRefs, messages = {}, {}
local dirty = false
local scoreBoardVisible = true
local restartAt = nil
local awaitingDirectRestart = false

local function removeDonationMachines()
    -- Remove without destruction effects or changing saved donation totals.
    for _, variant in ipairs({8, 11}) do -- Donation Machine / Greed Donation Machine
        for _, machine in ipairs(Isaac.FindByType(6, variant, -1, false, false)) do
            machine:Remove()
        end
    end
end

local function message(s)
    messages = { text = s, untilMs = Isaac.GetTime() + 4000 }
end

local function save()
    if not match then return end
    local ok, result = pcall(json.encode, match)
    if ok then
        local written, err = pcall(function() mod:SaveData(result) end)
        if not written then blocked = "存档失败，请暂停比赛并检查日志"; Isaac.DebugString(tostring(err)) end
    else
        blocked = "比赛记录无法保存，请检查日志"
        Isaac.DebugString(tostring(result))
    end
    dirty = false
    lastSave = Isaac.GetTime()
end

local function load()
    if not mod:HasData() then return nil end
    local ok, value = pcall(function() return json.decode(mod:LoadData()) end)
    if ok and Rules.valid(value) then
        Rules.migrateScores(value)
        return value
    end
    blocked = "比赛存档不兼容或损坏，未覆盖原记录"
    return nil
end

local function target()
    return Rules.targets[match and match.target or selected].key
end

local function clock()
    local now = Isaac.GetTime()
    if lastMs and active and match and match.status == "running"
        and fontReady and not menu and not game:IsPaused() and not blocked then
        match.elapsedMs = match.elapsedMs + math.max(0, now - lastMs)
    end
    lastMs = now
end

local function award(key, points, category)
    if Rules.award(match, key, points, category) then
        dirty = true
        message("+" .. points)
    end
end

local function refreshInventory()
    local ok, result = pcall(Inventory.read)
    if ok then
        Rules.trackItems(match.run, result)
        match.run.lastInventory = result
        return result
    end
    blocked = "读取物品失败，请查看游戏日志"
    Isaac.DebugString(tostring(result))
    return match.run.lastInventory
end

local function finish(dead, reason)
    if not match or match.status ~= "running" then return end
    clock()
    local inventory = refreshInventory()
    if blocked then save(); return end
    if not dead then inventory.lostSoulAlive = Inventory.hasLivingLostSoul() end
    Rules.settle(match, inventory, dead, reason)
    if not dead then
        local level = game:GetLevel()
        match.run.ending = {
            reason = reason, stage = level:GetStage(),
            room = level:GetCurrentRoomDesc().ListIndex,
            seed = level:GetDungeonPlacementSeed(),
            delay = reason == "beast" and 50 or (reason == "mega" and 100 or 1),
        }
    end
    save()
end

local function updateMatchEnding()
    if not match or match.status ~= "finished" or not match.run
        or game:IsPaused() then return end
    local level = game:GetLevel()
    -- Preserve a pending Beast replacement saved by the previous version.
    if not match.run.ending and match.run.beastEndingDelay and level:GetStage() == 13 then
        match.run.ending = { reason = "beast", stage = 13,
            room = level:GetCurrentRoomDesc().ListIndex, seed = level:GetDungeonPlacementSeed(),
            delay = match.run.beastEndingDelay }
        match.run.beastEndingDelay = nil
    end
    local ending = match.run.ending
    if not ending or ending.stage ~= level:GetStage()
        or ending.seed ~= level:GetDungeonPlacementSeed()
        or ending.room ~= level:GetCurrentRoomDesc().ListIndex then return end
    -- Native chests may spawn after the death animation finishes.
    for _, chest in ipairs(Isaac.FindByType(5, PickupVariant.PICKUP_BIGCHEST, -1, false, false)) do
        chest:Remove()
    end
    if ending.spawned then return end
    ending.delay = ending.delay - 1
    if ending.delay > 0 then return end
    if ending.reason == "beast" or ending.reason == "mega" then
        local holderType = Isaac.GetEntityTypeByName("EA Match Ending Holder")
        if holderType <= 0 then return end -- Requires a full restart to load the XML.
        local holder = Isaac.Spawn(holderType, 0, 0,
            Isaac.GetFreeNearPosition(Isaac.GetPlayer(0).Position, 3), Vector.Zero, nil)
        holder.EntityCollisionClass = EntityCollisionClass.ENTCOLL_NONE
        holder:AddEntityFlags(EntityFlag.FLAG_NO_TARGET | EntityFlag.FLAG_NO_STATUS_EFFECTS)
        local bossType = ending.reason == "beast" and 951 or 275
        for _, boss in ipairs(Isaac.FindByType(bossType, 0, -1, false, false)) do
            boss:Remove()
        end
    end
    if #Isaac.FindByType(5, PickupVariant.PICKUP_TROPHY, -1, false, false) == 0 then
        local room = game:GetRoom()
        local pos = ending.reason == "beast" and room:GetGridPosition(127)
            or (ending.reason == "mega" and room:GetGridPosition(157) or room:GetCenterPos())
        Isaac.Spawn(5, PickupVariant.PICKUP_TROPHY, 0,
            room:FindFreePickupSpawnPosition(pos, 40, true), Vector.Zero, nil)
    end
    ending.spawned = true
    save()
end

local function floorInfo()
    local level = game:GetLevel()
    local stage, st = level:GetStage(), level:GetStageType()
    return stage, st, (level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH) ~= 0
end

local function logicalBossFloor()
    local stage, st, xl = floorInfo()
    local level = game:GetLevel()
    if level:IsAscent() or stage == 9 or stage == 12 or stage == 13 then return nil end
    -- XL's two fights occupy the two merged floor numbers. Room identity only
    -- distinguishes these fights; it is never part of the saved scoring key.
    local index = level:GetCurrentRoomDesc().ListIndex
    local ordinal = 1
    if xl then ordinal = index == level:GetLastBossRoomListIndex() and 2 or 1 end
    return Rules.depth(stage, st) + (xl and ordinal - 1 or 0)
end

local function awardFloorBoss(floorNumber)
    if not floorNumber then return end
    -- One saved entry per floor for the whole run, including regenerated floors.
    -- Keep the existing key format so continued runs retain their scored floors.
    award("floorboss:" .. tostring(floorNumber), 500, "bossPoints")
end

local function signature()
    local stage, st = floorInfo()
    return tostring(stage) .. ":" .. tostring(st) .. ":"
        .. tostring(game:GetLevel():GetDungeonPlacementSeed())
end

local function enterRoom()
    if not active or not match or match.status ~= "running" then return end
    local level, room = game:GetLevel(), game:GetRoom()
    local sig = signature()
    if match.run.floor ~= sig then
        match.run.floor = sig
        match.run.generation = match.run.generation + 1
    end
    local d = level:GetCurrentRoomDesc()
    currentRoom = tostring(match.run.generation) .. ":" .. tostring(d.ListIndex)
        .. ":" .. tostring(room:GetSpawnSeed())
    sawBoss, clearPending, bossRefs = false, false, {}
    local roomType = room:GetType()
    if roomType == RoomType.ROOM_SECRET then award("secret:" .. currentRoom, 50, "secretPoints") end
    if roomType == RoomType.ROOM_SUPERSECRET then award("secret:" .. currentRoom, 60, "secretPoints") end
    dirtyRoom = false
    dirty = true
end

local function bossTag(npc)
    local stage = game:GetLevel():GetStage()
    if stage == 12 and npc.Type == 412 then return "delirium" end
    if stage == 11 and npc.Type == 275 then return "mega" end
    if (stage == 8 or stage == 7) and npc.Type == 912 and npc.Variant == 10 then return "mother" end
    if stage == 13 and npc.Type == 951 and npc.Variant == 0 then return "beast" end
    if stage == 11 and npc.Type == 273 then return "lamb" end
    if stage == 11 and npc.Type == 102 and npc.Variant == 1 then return "blue" end
    if stage == 9 and npc.Type == 407 and npc.Variant == 0 then return "hush" end
    if stage == 13 and npc.Type == 950 and npc.Variant == 2 then return "dogma" end
end

local function recordDeath(npc)
    if not active or not match or match.status ~= "running" then return end
    Routes.npcDied(target(), match.run, npc, currentRoom)
    dirty = true
    local tag = bossTag(npc)
    if tag then match.run.pendingDeaths[tag] = currentRoom; dirty = true end
end

local function processBosses()
    local room, level = game:GetRoom(), game:GetLevel()
    local roomType = room:GetType()
    for _, entity in ipairs(Isaac.GetRoomEntities()) do
        local npc = entity:ToNPC()
        if npc and npc:IsBoss() and not npc:HasEntityFlags(EntityFlag.FLAG_FRIENDLY) then
            sawBoss = true
            local tag = bossTag(npc)
            if tag then bossRefs[tostring(npc.InitSeed) .. ":" .. tag] = npc end
        end
    end
    -- Mega Satan / Beast can bypass ordinary room-clear awards.
    for key, npc in pairs(bossRefs) do
        if npc:IsDead() then recordDeath(npc); bossRefs[key] = nil end
    end
    if roomType == RoomType.ROOM_BOSS and room:IsClear() and (sawBoss or clearPending) then
        awardFloorBoss(logicalBossFloor())
        Routes.bossCleared(target(), match.run, currentRoom)
        dirty = true
        sawBoss, clearPending = false, false
    end
    if roomType == RoomType.ROOM_BOSSRUSH and room:IsAmbushDone() then
        award("bossrush", 1000, "bossPoints")
    end
    local pending = match.run.pendingDeaths
    if pending.hush then award("hush", 1000, "bossPoints"); pending.hush = nil end
    if pending.dogma then awardFloorBoss(13); pending.dogma = nil end
    for _, tag in ipairs({ "delirium", "mega", "mother", "beast", "lamb", "blue" }) do
        if pending[tag] then
            -- The Lamb has a separate head and body; finish only after the room clears.
            if tag ~= "lamb" or (room:IsClear() and pending[tag] == currentRoom) then
                if tag == "delirium" or tag == target() then
                    if tag == "delirium" then awardFloorBoss(12)
                    elseif tag ~= "beast" then
                        awardFloorBoss(logicalBossFloor())
                    end
                    award("endpoint", 2000, "bossPoints")
                    finish(false, tag)
                    return
                end
                pending[tag] = nil
            end
        end
    end
end

local function begin()
    match = Rules.newMatch(selected)
    Rules.startRun(match, game:GetSeeds():GetStartSeedString())
    menu, blocked = false, nil
    lastMs = Isaac.GetTime()
    Routes.begin(target())
    enterRoom()
    refreshInventory()
    save()
end

mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, function(_, continued)
    -- Native quick restart can start a new run without an exit callback.
    -- Discard the old run's score, retaining the match clock and death count.
    if not continued and active and not menu and not blocked
        and match and match.status == "running" then
        clock()
        Rules.restart(match)
        awaitingDirectRestart = true
        save()
    end
    local continueMatch = awaitingDirectRestart
    awaitingDirectRestart = false
    active, loaded, blocked = true, true, nil
    loadFont()
    lastMs, lastSave = Isaac.GetTime(), Isaac.GetTime()
    match = load()
    if restartAt and not continued and match and match.status == "between" then
        match.elapsedMs = match.elapsedMs + math.max(0, Isaac.GetTime() - restartAt)
    end
    restartAt = nil
    if blocked then return end
    if bs9 then blocked = "请关闭原 bisai9 Mod 后重新启动游戏"; return end
    if continued then
        if not match or not match.run or match.run.seed ~= game:GetSeeds():GetStartSeedString() then
            blocked = "未找到与本局对应的比赛记录；不能把中途存档当作新比赛"
            return
        end
        if match.status == "running" then
            selected = match.target
            menu = false
            enterRoom()
        else
            menu = false
        end
    elseif continueMatch and match and match.status == "between" then
        Rules.startRun(match, game:GetSeeds():GetStartSeedString())
        selected, menu = match.target, false
        Routes.begin(target())
        enterRoom()
        refreshInventory()
        save()
    else
        -- A new game from the main menu is allowed, even if an earlier run
        -- was unfinished. In-run restarts instead continue the match above.
        -- Replace the previous match after confirming the new target.
        menu = true
        selected = match and match.target or 1
    end
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_ROOM, function()
    removeDonationMachines()
    dirtyRoom = true
end)

mod:AddCallback(ModCallbacks.MC_POST_NEW_LEVEL, function()
    if not active or not match or match.status ~= "running" then return end
    if game:GetFrameCount() == 0 then return end -- New-run callbacks precede GAME_STARTED.
    -- A floor regeneration must count new secrets even when its seed repeats.
    match.run.generation = match.run.generation + 1
    match.run.floor = signature()
    dirtyRoom = true
    dirty = true
end)

mod:AddCallback(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD, function()
    if active then clearPending = true end
end)
mod:AddCallback(ModCallbacks.MC_POST_NPC_DEATH, function(_, npc) recordDeath(npc) end)
mod:AddCallback(ModCallbacks.MC_POST_PEFFECT_UPDATE, function(_, player)
    removeDonationMachines() -- Include machines spawned after entering the room.
    Inventory.removeBanned(player)
end)

-- Optional enhancement when REPENTOGON is installed. Vanilla uses NPC death,
-- observed IsDead state and room-clear detection in processBosses above.
if ModCallbacks.MC_POST_COMPLETION_EVENT then
    mod:AddCallback(ModCallbacks.MC_POST_COMPLETION_EVENT, function(_, completion)
        if not active or blocked or not match or match.status ~= "running" then return end
        if dirtyRoom then enterRoom() end
        local tags = { [4]="blue", [5]="lamb", [6]="mega", [12]="delirium", [13]="mother", [14]="beast" }
        local stage = game:GetLevel():GetStage()
        if completion == 3 and game:GetRoom():GetType() == RoomType.ROOM_BOSSRUSH then
            award("bossrush", 1000, "bossPoints")
        elseif completion == 9 and stage == 9 then
            award("hush", 1000, "bossPoints")
        else
            local tag = tags[completion]
            if tag and (tag == target() or tag == "delirium") then
                local valid = (tag == "delirium" and stage == 12)
                    or (tag == "mother" and (stage == 7 or stage == 8))
                    or (tag == "beast" and stage == 13)
                    or ((tag == "blue" or tag == "lamb" or tag == "mega") and stage == 11)
                if not valid then return end
                if tag == "delirium" then awardFloorBoss(12)
                elseif tag ~= "beast" then
                    awardFloorBoss(logicalBossFloor())
                end
                award("endpoint", 2000, "bossPoints")
                finish(false, tag)
            end
        end
        if dirty then save() end
    end)
end

mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if active then updateMatchEnding() end
    if not active or blocked or not fontReady then return end
    if menu then
        -- Keep BR/Hush's own game clock at zero while choosing a target.
        game.TimeCounter = 0
        return
    end
    if not match or match.status ~= "running" then return end
    if dirtyRoom then enterRoom() end
    clock()
    processBosses()
    if match.status ~= "running" then return end
    refreshInventory() -- Retain the final old-run inventory for native quick restart.
    if dirty or Isaac.GetTime() - lastSave >= 1000 then save() end
end)

mod:AddCallback(ModCallbacks.MC_POST_GAME_END, function(_, gameOver)
    if not active or blocked then return end
    if gameOver then
        finish(true, "死亡")
        awaitingDirectRestart = match and match.status == "between" or false
    elseif match and match.status == "running" then
        -- An unrelated ending is not an authorized endpoint.
        blocked = "未击败比赛终点，请保留记录并联系裁判"
        save()
    end
    active = false
    lastMs = nil
end)

mod:AddCallback(ModCallbacks.MC_PRE_GAME_EXIT, function(_, shouldSave)
    local restarting = Input.IsButtonPressed(Keyboard.KEY_R, 0)
    if game:GetNumPlayers() > 0 then
        restarting = restarting or Input.IsActionPressed(ButtonAction.ACTION_RESTART,
            Isaac.GetPlayer(0).ControllerIndex)
    end
    -- Leaving for the main menu ends the direct-restart flow. A saved death
    -- alone must not make a later New Game inherit the previous competition.
    if shouldSave or not restarting then
        awaitingDirectRestart = false
        restartAt = nil
    end
    if active and not menu and not blocked and shouldSave == false
        and match and match.status == "running" then
        if restarting then
            clock()
            Rules.restart(match)
            save()
            awaitingDirectRestart = match.status == "between"
            restartAt = Isaac.GetTime()
        end
    end
    if active then clock(); save() end
    active, loaded, lastMs = false, false, nil
end)

-- Let native restart input pass through; settlement happens on the run transition.
mod:AddCallback(ModCallbacks.MC_INPUT_ACTION, function(_, entity, hook, action)
    if readingMenuInput then return end
    -- Alias F4 to the native pause action: enemies, projectiles and both clocks pause.
    if active and action == ButtonAction.ACTION_PAUSE and hook == InputHook.IS_ACTION_TRIGGERED
        and Input.IsButtonTriggered(Keyboard.KEY_F4, 0) then return true end
    -- Settlement freezes scores, not player controls. F6 can hide the result panel.
    local freeze = active and fontReady and (menu or blocked)
    if freeze and entity and action <= ButtonAction.ACTION_DROP then
        if hook == InputHook.GET_ACTION_VALUE then return 0 end
        return false
    end
end)

-- Draw an independent result panel; scores are frozen at settlement.
local function draw(text, x, y, color)
    font:DrawStringUTF8(tostring(text), x, y, color or white, 0, false)
end
local function timeText(ms)
    local s = math.floor(ms / 1000)
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    if not loaded and not match then return end
    if not loadFont() then
        Isaac.RenderText("EA Match: font could not be loaded. Match clock stopped.", 20, 65, 1, 0.8, 0.2, 1)
        Isaac.RenderText("Check mods/ea_match/resources/font/ea_match and log.txt.", 20, 80, 1, 1, 1, 1)
        return
    end
    clock()
    local x = 16 + Options.HUDOffset * 20
    if blocked then draw(blocked, x, 70, yellow); return end
    if menu then
        draw("饿啊杯：上下射击键选择终点，回车确认", 80, 65, yellow)
        for i, t in ipairs(Rules.targets) do
            draw((i == selected and "→ " or "   ") .. t.name, 150, 80 + i * 17)
        end
        if match and match.best then draw("上场最高分：" .. match.best, 120, 210) end
        if not game:IsPaused() then
            local c = Isaac.GetPlayer(0).ControllerIndex
            readingMenuInput = true
            local up = Input.IsActionTriggered(ButtonAction.ACTION_SHOOTUP, c)
            local down = Input.IsActionTriggered(ButtonAction.ACTION_SHOOTDOWN, c)
            local confirm = Input.IsButtonTriggered(Keyboard.KEY_ENTER, 0)
                or Input.IsActionTriggered(ButtonAction.ACTION_ITEM, c)
            readingMenuInput = false
            if up then selected = (selected - 2) % #Rules.targets + 1 end
            if down then selected = selected % #Rules.targets + 1 end
            if confirm then begin() end
        end
        return
    end
    if not match then return end
    if Input.IsButtonTriggered(Keyboard.KEY_F6, 0) then
        scoreBoardVisible = not scoreBoardVisible
    end
    if not scoreBoardVisible then return end
    draw("目标：" .. Rules.targets[match.target].name .. "  总用时 " .. timeText(match.elapsedMs), x, 45)
    draw("死亡 " .. match.deaths .. " 次  历史最高：" .. tostring(match.best or "—"), x, 58)
    if match.status == "running" then
        local total = Rules.preview(match, match.run.lastInventory, false)
        draw("当前分数：" .. total .. "  时间分：" .. (3600 - math.floor(match.elapsedMs / 1000)), x, 71)
        if game:IsPaused() then draw("比赛暂停中", x, 84, yellow) end
    else
        local result = match.results[#match.results]
        if result then
            local deathPanel = match.status == "between"
            local panelX = deathPanel and 12 or 130
            draw(deathPanel and "本局死亡" or "比赛结束", panelX, 100, yellow)
            draw(deathPanel and "F6 显示/隐藏" or "F6 隐藏／显示计分板", panelX, 84, yellow)
            if deathPanel then
                -- Keep each line inside the left margin of the native death screen.
                draw("本局：" .. result.total, panelX, 116)
                draw("最高：" .. match.best, panelX, 128)
            else
                draw("本局：" .. result.total .. "  比赛最高：" .. match.best, 110, 120)
            end
            local labels = { {"time", "时间"}, {"coins", "金币"}, {"bombs", "炸弹"},
                {"keys", "钥匙"}, {"consumables", "卡牌/药丸/符文"}, {"hearts", "血量"},
                {"items", "道具"}, {"trinkets", "饰品"}, {"bosses", "Boss"},
                {"secrets", "隐藏房"}, {"forms", "套装"} }
            for i, pair in ipairs(labels) do
                local label = pair[2]
                if deathPanel and pair[1] == "consumables" then label = "消耗品" end
                draw(label .. "：" .. result.scores[pair[1]], panelX, 136 + i * 12)
            end
            for i, achievement in ipairs(result.achievements or {}) do
                draw(achievement.name .. "：+" .. achievement.points,
                    panelX, 136 + (#labels + i) * 12, yellow)
            end
        end
    end
    if messages.untilMs and Isaac.GetTime() < messages.untilMs then draw(messages.text, x, 98, yellow) end
end)

-- Vanilla interception: pool draws, spawning, morphed pedestals and collisions.
-- Direct AddCollectible/crafting is cleaned by Inventory.removeBanned.
mod:AddCallback(ModCallbacks.MC_POST_GET_COLLECTIBLE, function(_, id, pool, decrease, seed)
    if not Rules.banned[id] then return end
    local itemPool = game:GetItemPool()
    for banned in pairs(Rules.banned) do itemPool:RemoveCollectible(banned) end
    return itemPool:GetCollectible(pool, decrease, seed, 25)
end)
mod:AddCallback(ModCallbacks.MC_PRE_ENTITY_SPAWN, function(_, kind, variant, subtype, pos, vel, spawner, seed)
    if kind == 5 and variant == 100 and Rules.banned[subtype] then return {5, 100, 25, seed} end
end)
local function replaceBannedPedestal(_, pickup)
    if Rules.banned[pickup.SubType] then pickup:Morph(5, 100, 25, true, true, false) end
end
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_INIT, replaceBannedPedestal, PickupVariant.PICKUP_COLLECTIBLE)
mod:AddCallback(ModCallbacks.MC_POST_PICKUP_UPDATE, replaceBannedPedestal, PickupVariant.PICKUP_COLLECTIBLE)
mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_COLLISION, function(_, pickup)
    if Rules.banned[pickup.SubType] then
        replaceBannedPedestal(nil, pickup)
        return true
    end
end, PickupVariant.PICKUP_COLLECTIBLE)
mod:AddCallback(ModCallbacks.MC_PRE_USE_ITEM, function(_, id)
    if Rules.banned[id] then return true end
end)
if ModCallbacks.MC_PRE_ADD_COLLECTIBLE then
    mod:AddCallback(ModCallbacks.MC_PRE_ADD_COLLECTIBLE, function(_, id)
        if Rules.banned[id] then return 25 end
    end)
end
if ModCallbacks.MC_PRE_PICKUP_MORPH then
    mod:AddCallback(ModCallbacks.MC_PRE_PICKUP_MORPH, function(_, pickup, entityType, variant, subtype, price, seed, modifiers)
        if entityType == 5 and variant == 100 and Rules.banned[subtype] then
            return {5, 100, 25, price, seed, modifiers}
        end
    end)
end
if ModCallbacks.MC_PRE_MEGA_SATAN_ENDING then
    mod:AddCallback(ModCallbacks.MC_PRE_MEGA_SATAN_ENDING, function()
        if match and (match.status == "running" or match.status == "finished") then return true end
    end)
end

-- Read-only diagnostics. No win/reset command that could alter a running match.
mod:AddCallback(ModCallbacks.MC_EXECUTE_CMD, function(_, command)
    if command == "ea_status" then
        Isaac.ConsoleOutput(match and json.encode(match) or "No match\n")
    end
end)
