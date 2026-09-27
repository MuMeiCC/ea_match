-- Pure rules: no Isaac API calls. Scores use integer seconds and actual inventory.
local R = {}
R.version = 1
R.limit = 3600
R.targets = {
    { key = "mega", name = "大撒旦" },
    { key = "mother", name = "母亲" },
    { key = "beast", name = "祸兽" },
    { key = "lamb", name = "羔羊" },
    { key = "blue", name = "小蓝人" },
    { key = "delirium", name = "精神错乱" },
}
R.banned = { [482] = true, [636] = true, [721] = true }
R.special = {
    [52] = 50, [149] = 50, [168] = 50, [206] = 50,
    [222] = 50, [258] = 200, [276] = 150, [299] = 100,
    [316] = 50, [330] = 100, [358] = 150, [371] = 50,
    [561] = 200, [725] = 200,
}
R.hiddenAchievements = {
    lostSoul = { name = "呃啊", points = 666 },
    suicideKing = { name = "自杀之王", points = 1000 },
}

function R.inventory(v, dead)
    local coins = v.coins or 0
    local result = {
        coins = math.min(coins, 20) * 5
            + math.min(math.max(coins - 20, 0), 79) * 2
            + math.max(coins - 99, 0),
        consumables = (v.pockets or 0) * 20,
        items = 0, trinkets = 0, hearts = 0,
        forms = (v.forms or 0) * 100,
    }
    for _, name in ipairs({ "bombs", "keys" }) do
        local n = v[name] or 0
        result[name] = math.min(n, 10) * 10 + math.max(n - 10, 0) * 3
    end
    for _, item in ipairs(v.items or {}) do
        if not R.banned[item.id] then
            result.items = result.items + item.count *
                (50 + (item.quality == 4 and 50 or 0) + (R.special[item.id] or 0))
        end
    end
    result.trinkets = (v.trinkets or 0) * 20 + (v.goldTrinkets or 0) * 40
    if v.trinketUnits ~= nil then result.trinkets = v.trinketUnits * 20 end
    if not dead then
        result.hearts = math.max((v.red or 0) - (v.rotten or 0) * 2, 0) * 25
            + (v.soul or 0) * 30 + (v.eternal or 0) * 60
            + (v.bone or 0) * 10 + (v.rotten or 0) * 60 + (v.golden or 0) * 100
    end
    return result
end

function R.newMatch(target)
    return { version = R.version, target = target, elapsedMs = 0,
        deaths = 0, status = "ready", results = {}, run = nil }
end

function R.startRun(match, seed)
    assert(match.status == "ready" or match.status == "between", "Only a death permits another run")
    match.run = { seed = seed, awards = {},
        bossPoints = 0, secretPoints = 0, settled = false, lastInventory = {},
        -- Generation changes on a real new floor / Forget Me Now, not on continue.
        generation = 0, floor = "", pendingDeaths = {} }
    match.status = "running"
end

function R.award(match, key, points, category)
    local run = match.run
    if match.status ~= "running" or not run or run.settled or run.awards[key] then return false end
    run.awards[key] = true
    run[category] = run[category] + points
    return true
end

-- Logical depth, independent of seed/room ID: Forget Me Now cannot farm bosses.
function R.depth(stage, stageType)
    return stage + ((stageType >= 4 and stage <= 8) and 1 or 0)
end

function R.bossKeys(stage, stageType, xl, ordinal)
    local depth = R.depth(stage, stageType)
    return "floorboss:" .. tostring(xl and (depth + ordinal - 1) or depth)
end

function R.preview(match, inventory, dead)
    local scores = R.inventory(inventory, dead)
    scores.time = R.limit - math.floor(match.elapsedMs / 1000)
    scores.bosses = match.run.bossPoints
    scores.secrets = match.run.secretPoints
    local total = 0
    for _, n in pairs(scores) do total = total + n end
    return total, scores
end

-- A manual restart abandons this run without creating a score entry.
function R.restart(match)
    if match.status ~= "running" or match.run.settled then return end
    match.run.settled = true
    match.run.discarded = true
    match.deaths = match.deaths + 1
    match.status = "between"
end

function R.migrateScores(match)
    local results = {}
    match.best = nil
    for _, entry in ipairs(match.results) do
        if entry.reason ~= "R 重开" then
            if entry.scores.penalty then
                entry.total = entry.total - entry.scores.penalty
                entry.scores.penalty = nil
            end
            entry.number = #results + 1
            table.insert(results, entry)
            if match.best == nil or entry.total > match.best then match.best = entry.total end
        end
    end
    match.results = results
end

function R.settle(match, inventory, dead, reason)
    if match.status ~= "running" or match.run.settled then return nil end
    local total, scores = R.preview(match, inventory, dead)
    local achievements = {}
    if not dead and inventory.lostSoulAlive then
        for _, item in ipairs(inventory.items or {}) do
            if item.id == 612 and item.count > 0 then
                local reward = R.hiddenAchievements.lostSoul
                table.insert(achievements, { key = "lostSoul", name = reward.name, points = reward.points })
                scores.achievements = reward.points
                total = total + reward.points
                break -- Once per victory, regardless of duplicate items/familiars.
            end
        end
    end
    if not dead then
        local hasIpecacOrDrFetus, hasReflection = false, false
        for _, item in ipairs(inventory.items or {}) do
            if item.count > 0 then
                if item.id == 149 or item.id == 52 then hasIpecacOrDrFetus = true end
                if item.id == 5 then hasReflection = true end
            end
        end
        if hasIpecacOrDrFetus and hasReflection then
            local reward = R.hiddenAchievements.suicideKing
            table.insert(achievements, { key = "suicideKing", name = reward.name, points = reward.points })
            scores.achievements = (scores.achievements or 0) + reward.points
            total = total + reward.points
        end
    end
    local entry = { number = #match.results + 1, total = total, scores = scores,
        elapsed = math.floor(match.elapsedMs / 1000), dead = dead, reason = reason,
        achievements = achievements }
    match.run.settled = true
    table.insert(match.results, entry)
    if match.best == nil or total > match.best then match.best = total end
    if dead then
        match.deaths = match.deaths + 1
        match.status = "between"
    else
        match.status = "finished"
    end
    return entry
end

function R.valid(match)
    if type(match) ~= "table" or match.version ~= R.version then return false end
    if type(match.target) ~= "number" or not R.targets[match.target] then return false end
    if type(match.elapsedMs) ~= "number" or match.elapsedMs < 0 then return false end
    if type(match.deaths) ~= "number" or type(match.results) ~= "table" then return false end
    if match.status ~= "ready" and match.status ~= "running"
        and match.status ~= "between" and match.status ~= "finished" then return false end
    if match.status ~= "ready" then
        local run = match.run
        if type(run) ~= "table" or type(run.awards) ~= "table"
            or type(run.bossPoints) ~= "number" or type(run.secretPoints) ~= "number"
            or type(run.generation) ~= "number"
            or type(run.pendingDeaths) ~= "table"
            or type(run.lastInventory) ~= "table" then return false end
    end
    return true
end

return R
