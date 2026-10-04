-- Route assistance adapted from bisai9. No ambush.xml override: vanilla Boss Rush.
return function()
    local Routes = {}
    function Routes.removeBeastBloodDoor(target)
        if target ~= "beast" then return end
        local level, room = Game():GetLevel(), Game():GetRoom()
        if level:IsAscent() or room:GetType() ~= RoomType.ROOM_BOSS then return end
        local stage = level:GetStage()
        local alt = level:GetStageType() >= StageType.STAGETYPE_REPENTANCE
        local xl = (level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH) ~= 0
        -- Depths I or Mines II (including Mines XL): both lead to Mausoleum I.
        -- The photograph door on Depths II is outside this scope.
        if not ((not alt and stage == 5)
            or (alt and (stage == 4 or (xl and stage == 3)))) then return end
        for slot = 0, 7 do
            local door = room:GetDoor(slot)
            if door and door.TargetRoomType == RoomType.ROOM_SECRET_EXIT then
                room:RemoveDoor(slot)
            end
        end
    end

    function Routes.npcDied(target, run, npc, roomKey)
        local level = Game():GetLevel()
        if target == "mother" and npc.Type == 78 and not level:IsAscent()
            and level:GetStageType() >= StageType.STAGETYPE_REPENTANCE
            and (level:GetStage() == 6 or (level:GetStage() == 5
                and (level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH) ~= 0)) then
            run.pendingCorpseEntrance = roomKey
        end
    end

    local function ensureCorpseEntrance(room)
        for i = 0, room:GetGridSize() - 1 do
            local grid = room:GetGridEntity(i)
            if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then return end
        end
        room:SpawnGridEntity(room:GetGridIndex(Vector(320, 200)), 17, 0, room:GetSpawnSeed(), 0)
    end

    local function removeExit(kind)
        local room = Game():GetRoom()
        if kind == 1 then
            for _, e in ipairs(Isaac.FindByType(1000, 39)) do
                local pos = e.Position
                e:Remove()
                return pos
            end
        else
            for i = 0, room:GetGridSize() - 1 do
                local grid = room:GetGridEntity(i)
                if grid and grid:GetType() == GridEntityType.GRID_TRAPDOOR then
                    local pos = grid.Position
                    room:RemoveGridEntity(i, 0, false)
                    return pos
                end
            end
        end
    end

    local function portal(pos)
        for _, e in ipairs(Isaac.FindByType(1000, 161, 1084)) do
            if e.Position:Distance(pos) < 40 then return end
        end
        Isaac.Spawn(1000, 161, 1084, pos, Vector.Zero, nil)
    end

    function Routes.begin(target)
        if target == "mega" then
            local p = Isaac.GetPlayer(0)
            for _, id in ipairs({238, 239}) do
                if not p:HasCollectible(id) then p:AddCollectible(id, 0, false) end
            end
        end
    end

    function Routes.bossCleared(target, run, roomKey)
        local game = Game()
        local room, level = game:GetRoom(), game:GetLevel()
        if level:IsAscent() or room:GetType() ~= RoomType.ROOM_BOSS
            or not room:IsClear() then return end
        local corpsePending = target == "mother" and run.pendingCorpseEntrance == roomKey
        -- Persist by generated room, not by visit. A regenerated floor is a new
        -- battle; re-entering or continuing a cleared room never repeats this.
        run.routeClears = run.routeClears or {}
        if run.routeClears[roomKey] then
            -- Mom and her Heart may share a room: the Heart's death still gets
            -- its own one-time entrance repair, without rerunning door removal.
            if corpsePending then
                ensureCorpseEntrance(room)
                run.pendingCorpseEntrance = nil
            end
            return
        end
        run.routeClears[roomKey] = true
        local name = level:GetCurrentRoomDesc().Data.Name
        local p = Isaac.GetPlayer(0)
        if target == "mother" and room:GetType() == RoomType.ROOM_BOSS then
            local stage = level:GetStage()
            local alt = level:GetStageType() >= StageType.STAGETYPE_REPENTANCE
            local xl = (level:GetCurses() & LevelCurse.CURSE_OF_LABYRINTH) ~= 0
            if not alt or stage == 2 or stage == 4 or stage == 6
                or (xl and (stage == 1 or stage == 3 or stage == 5)) then
                p:UseCard(name == "Mom (mausoleum)" and 83 or 47, 1 | (1 << 8))
                removeExit(0)
            end
            if corpsePending or name == "Mom's Heart (mausoleum)" then
                ensureCorpseEntrance(room)
                run.pendingCorpseEntrance = nil
            end
        elseif target == "beast" and name == "Mom" then
            removeExit(0)
            portal(Vector(320, 200))
        elseif target == "lamb" or target == "blue" then
            if name == "Mom" or name == "Mom (mausoleum)" then
                local from, to = 327, 328
                if target == "blue" then from, to = 328, 327 end
                for _, e in ipairs(Isaac.FindByType(5, 100, from)) do
                    e:ToPickup():Morph(5, 100, to, true, true, false)
                end
            elseif name == "It Lives!" or level:GetStage() == 9 then
                -- Hush's cleared boss room offers the same two onward routes.
                removeExit(target == "lamb" and 1 or 0)
            end
        elseif target == "mega" and name == "It Lives!" then
            if p:HasCollectible(328) and not p:HasCollectible(327) then removeExit(1)
            elseif p:HasCollectible(327) and not p:HasCollectible(328) then removeExit(0) end
        end
        -- No portal to Delirium, irrespective of selected target.
    end
    return Routes
end
