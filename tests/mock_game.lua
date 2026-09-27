-- Contract-focused engine mock. Real engine callbacks still require in-game QA.
local json = require("json")
REPENTOGON = nil
local callbacks, persisted, output = {}, nil, nil
local now, paused, seed, frame = 0, false, "SEED A", 0
local stage, stageType, curses, roomType, roomIndex = 1, 0, 0, 1, 0
local clear, ambushDone, spawnSeed = true, false, 123
local entities, forms, collectibles, smelted, held = {}, {}, {}, {}, {}
local enterPressed = false
ModCallbacks = {}
for _, name in ipairs({"MC_POST_GAME_STARTED", "MC_POST_NEW_ROOM", "MC_POST_NEW_LEVEL",
    "MC_PRE_SPAWN_CLEAN_AWARD", "MC_POST_NPC_DEATH", "MC_POST_PEFFECT_UPDATE",
    "MC_POST_UPDATE", "MC_POST_GAME_END", "MC_PRE_GAME_EXIT", "MC_INPUT_ACTION",
    "MC_POST_RENDER", "MC_POST_GET_COLLECTIBLE", "MC_PRE_ENTITY_SPAWN",
    "MC_POST_PICKUP_INIT", "MC_POST_PICKUP_UPDATE", "MC_PRE_PICKUP_COLLISION",
    "MC_PRE_USE_ITEM", "MC_EXECUTE_CMD"}) do ModCallbacks[name]=name end
RoomType = {ROOM_BOSS=5, ROOM_SECRET=7, ROOM_SUPERSECRET=8, ROOM_BOSSRUSH=17}
StageType = {STAGETYPE_REPENTANCE=4}
LevelCurse = {CURSE_OF_LABYRINTH=2}
EntityFlag = {FLAG_FRIENDLY=1}
GridEntityType = {GRID_TRAPDOOR=17}
PickupVariant = {PICKUP_COLLECTIBLE=100}
PlayerForm = {NUM_PLAYER_FORMS=15}
InputHook = {IS_ACTION_PRESSED=0, IS_ACTION_TRIGGERED=1, GET_ACTION_VALUE=2}
ButtonAction = {ACTION_UP=2, ACTION_DOWN=3, ACTION_ITEM=9, ACTION_DROP=11, ACTION_PAUSE=12, ACTION_RESTART=18}
Keyboard = {KEY_ENTER=13, KEY_F4=115}
Options = {HUDOffset=0}
Vector = setmetatable({Zero={}}, {__call=function(_,x,y) return {X=x,Y=y} end})
function KColor(...) return {...} end
function Font() return {Load=function() end, DrawStringUTF8=function() end} end
Input = {IsActionTriggered=function() return false end,
    IsButtonTriggered=function(key) return key == Keyboard.KEY_ENTER and enterPressed end}
local p = {ControllerIndex=0}
function p:GetNumCoins() return 0 end
function p:GetNumBombs() return 0 end
function p:GetNumKeys() return 0 end
function p:GetHearts() return 6 end
function p:GetSoulHearts() return 0 end
function p:GetEternalHearts() return 0 end
function p:GetBoneHearts() return 0 end
function p:GetRottenHearts() return 0 end
function p:GetGoldenHearts() return 0 end
function p:GetCollectibleNum(id) return collectibles[id] or 0 end
function p:RemoveCollectible(id) collectibles[id]=math.max(0,(collectibles[id] or 0)-1) end
function p:GetActiveItem() return 0 end
function p:GetCard() return 0 end
function p:GetPill() return 0 end
function p:GetTrinket(slot) return held[slot] or 0 end
local function trinketUnits(id)
    local entry=smelted[id] or {}
    local n=(entry.trinketAmount or 0)+2*(entry.goldenTrinketAmount or 0)
    for _, raw in pairs(held) do
        if (raw & 32767)==id then n=n+((raw & 32768)~=0 and 2 or 1) end
    end
    return n
end
function p:HasTrinket(id) return trinketUnits(id)>0 end
function p:GetTrinketMultiplier(id)
    return trinketUnits(id)+(p:HasCollectible(439) and 1 or 0)
end
function p:HasPlayerForm(form) return forms[form] end
function p:GetPlayerType() return 0 end
function p:HasCollectible(id) return (collectibles[id] or 0) > 0 end
function p:AddCollectible(id) collectibles[id] = (collectibles[id] or 0) + 1 end
function p:UseCard() end
local room = {}
function room:GetType() return roomType end
function room:GetSpawnSeed() return spawnSeed end
function room:IsClear() return clear end
function room:IsAmbushDone() return ambushDone end
function room:GetGridSize() return 0 end
local descriptor = {Data={Name="ordinary", Type=1}, ListIndex=0, GridIndex=0}
local roomList = {{Data={Type=5}, ListIndex=10, GridIndex=10},{Data={Type=5},ListIndex=20,GridIndex=20}}
local level = {}
function level:GetStage() return stage end
function level:GetStageType() return stageType end
function level:GetCurses() return curses end
function level:GetLastBossRoomListIndex() return 20 end
function level:IsAscent() return false end
function level:GetDungeonPlacementSeed() return 999 end
function level:GetCurrentRoomDesc() descriptor.ListIndex=roomIndex; return descriptor end
function level:GetRooms() return {Size=#roomList, Get=function(_,i) return roomList[i+1] end} end
local game = {TimeCounter=0}
function game:GetRoom() return room end
function game:GetLevel() return level end
function game:IsPaused() return paused end
function game:GetFrameCount() return frame end
function game:GetSeeds() return {GetStartSeedString=function() return seed end} end
function Game() return game end
Isaac = {GetPlayer=function() return p end, GetTime=function() return now end,
    DebugString=function(s) error(s) end, ConsoleOutput=function(s) output=s end,
    GetRoomEntities=function() return entities end, FindByType=function() return {} end,
    GetItemConfig=function() return {
        GetCollectible=function(_,id) return {Quality=(id==168 and 4 or 0)} end,
        GetCollectibles=function() return {Size=733} end,
        GetTrinkets=function() return {Size=190} end,
        GetTrinket=function() return {} end,
    } end}
function RegisterMod()
    return {AddCallback=function(_,id,fn) callbacks[id]=callbacks[id] or {}; table.insert(callbacks[id],fn) end,
        SaveData=function(_,s) persisted=s end, HasData=function() return persisted~=nil end,
        LoadData=function() return persisted end}
end
function include(path) return dofile(ROOT .. "/" .. path:gsub("%.","/") .. ".lua") end
local function emit(id,...)
    local result
    for _, f in ipairs(callbacks[id] or {}) do result=f(nil,...) end
    return result
end
local function boot() callbacks={}; dofile(ROOT .. "/main.lua") end
local function snapshot() emit(ModCallbacks.MC_EXECUTE_CMD,"ea_status"); return json.decode(output) end
local checks=0
local function eq(a,b,label) checks=checks+1; assert(a==b,(label or "adapter")..": "..tostring(a).." != "..tostring(b)) end
local function tick(ms)
    now=now+ms; frame=frame+1
    emit(ModCallbacks.MC_POST_UPDATE); emit(ModCallbacks.MC_POST_RENDER)
end
local function enter(kind, index)
    roomType,roomIndex=kind,index
    emit(ModCallbacks.MC_POST_NEW_ROOM); tick(0)
end
boot()
-- Engine's initial level/room callbacks occur before GAME_STARTED.
emit(ModCallbacks.MC_POST_NEW_ROOM); emit(ModCallbacks.MC_POST_NEW_LEVEL)
emit(ModCallbacks.MC_POST_GAME_STARTED,false)
enterPressed=true; emit(ModCallbacks.MC_POST_RENDER); enterPressed=false
eq(snapshot().status,"running")
eq(emit(ModCallbacks.MC_INPUT_ACTION,p,InputHook.GET_ACTION_VALUE,ButtonAction.ACTION_RESTART),0)
tick(1000); eq(snapshot().elapsedMs,1000)
paused=true; tick(10000); eq(snapshot().elapsedMs,1000,"Esc pauses match clock")
paused=false; tick(1000); eq(snapshot().elapsedMs,2000)
enter(7,5); eq(snapshot().run.secretPoints,50)
enter(1,0); enter(7,5); eq(snapshot().run.secretPoints,50,"same room revisit")
emit(ModCallbacks.MC_PRE_GAME_EXIT,true)
now=now+600000
boot()
emit(ModCallbacks.MC_POST_NEW_ROOM); emit(ModCallbacks.MC_POST_NEW_LEVEL)
emit(ModCallbacks.MC_POST_GAME_STARTED,true)
eq(snapshot().elapsedMs,2000,"offline time excluded")
eq(snapshot().run.secretPoints,50,"continue does not pay secret again")
-- Forget Me Now changes generation, even with an unchanged placement seed.
emit(ModCallbacks.MC_POST_NEW_ROOM); emit(ModCallbacks.MC_POST_NEW_LEVEL); tick(0)
eq(snapshot().run.secretPoints,100,"regenerated secret pays again")
enter(5,10)
emit(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD); tick(0)
eq(snapshot().run.bossPoints,500)
emit(ModCallbacks.MC_POST_NEW_LEVEL); tick(0)
emit(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD); tick(0)
eq(snapshot().run.bossPoints,500,"same-depth boss cannot be farmed")
-- Five-pip dice room: engine emits the same floor-regeneration lifecycle.
enter(7,5)
local beforeDice=snapshot().run.secretPoints
emit(ModCallbacks.MC_POST_NEW_ROOM); emit(ModCallbacks.MC_POST_NEW_LEVEL); tick(0)
eq(snapshot().run.secretPoints,beforeDice+50,"five-pip dice allows regenerated secrets")
enter(5,10); emit(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD); tick(0)
eq(snapshot().run.bossPoints,500,"five-pip dice cannot farm floor boss")
-- XL awards both depths; a later reroll cannot pay either again.
curses=2
emit(ModCallbacks.MC_POST_NEW_LEVEL); tick(0)
enter(5,20); emit(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD); tick(0)
eq(snapshot().run.bossPoints,1000,"XL second boss")
emit(ModCallbacks.MC_POST_NEW_LEVEL); tick(0)
enter(5,20); emit(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD); tick(0)
eq(snapshot().run.bossPoints,1000,"XL second boss dedup")
curses=0
-- Death settlement, double callback, second-run penalty and inventory reset.
emit(ModCallbacks.MC_POST_GAME_END,true)
local first=snapshot()
eq(first.deaths,1)
eq(first.results[1].scores.hearts,0)
eq(first.results[1].scores.penalty,0)
emit(ModCallbacks.MC_POST_GAME_END,true); eq(snapshot().deaths,1)
seed="SEED B"; stage=1; roomType=1; roomIndex=0
collectibles={}; emit(ModCallbacks.MC_POST_GAME_STARTED,false)
eq(snapshot().run.penaltyDeaths,1)
eq(snapshot().run.bossPoints,0)
eq(snapshot().elapsedMs,2000)
-- Hush is optional, once only, no additional 500.
stage=9; enter(5,10)
emit(ModCallbacks.MC_POST_NPC_DEATH,{Type=407,Variant=0}); tick(0)
eq(snapshot().run.bossPoints,1000)
eq(snapshot().status,"running")
emit(ModCallbacks.MC_POST_NPC_DEATH,{Type=407,Variant=0}); tick(0)
eq(snapshot().run.bossPoints,1000)
-- Delirium ends a Mega Satan target match; other Void bosses never pay.
stage=12; enter(5,10)
emit(ModCallbacks.MC_PRE_SPAWN_CLEAN_AWARD); tick(0)
eq(snapshot().run.bossPoints,1000)
emit(ModCallbacks.MC_POST_NPC_DEATH,{Type=412,Variant=0}); tick(0)
local final=snapshot()
eq(final.status,"finished")
eq(final.run.bossPoints,3500)
eq(final.results[2].scores.penalty,-200)
tick(5000); eq(snapshot().elapsedMs,final.elapsedMs,"settled clock is frozen")
collectibles[636]=1
local breakfastBefore=collectibles[25] or 0
emit(ModCallbacks.MC_POST_PEFFECT_UPDATE,p)
eq(collectibles[636],0,"vanilla direct-grant cleanup")
eq(collectibles[25],breakfastBefore+1,"replacement breakfast")
eq(emit(ModCallbacks.MC_PRE_USE_ITEM,482),true)
eq(emit(ModCallbacks.MC_PRE_USE_ITEM,127),nil,"Forget Me Now remains allowed")
local replacement=emit(ModCallbacks.MC_PRE_ENTITY_SPAWN,5,100,721,{}, {},nil,123)
eq(replacement[3],25,"vanilla spawn interception")
eq(replacement[4],123,"spawn seed preserved")

-- Read real holdings, not the amplified trinket-effect multiplier.
held={[0]=32769,[1]=1}
smelted={[1]={trinketAmount=2,goldenTrinketAmount=3}}
collectibles={[330]=2,[168]=1,[358]=1}
forms={[0]=true,[2]=true}
local Rules=dofile(ROOT.."/scripts/rules.lua")
local inventory=dofile(ROOT.."/scripts/inventory.lua")(Rules).read()
eq(inventory.trinketUnits,11)
eq(Rules.inventory(inventory,false).trinkets,220)
eq(Rules.inventory(inventory,false).items,650)
eq(inventory.forms,2)
collectibles[439]=1
eq(dofile(ROOT.."/scripts/inventory.lua")(Rules).read().trinketUnits,11,"Mom's Box not counted as extra copies")
held,smelted,collectibles,forms={},{},{},{}

-- Vanilla NPC death path for all six targets, without any extended callbacks.
for _, case in ipairs({{1,11,275,0},{2,8,912,10},{3,13,951,0},{4,11,273,10},{5,11,102,1},{6,12,412,0}}) do
    persisted=json.encode(Rules.newMatch(case[1]))
    stage,stageType,curses,roomType,roomIndex=1,0,0,1,0
    seed="ENDPOINT "..case[1]
    boot(); emit(ModCallbacks.MC_POST_GAME_STARTED,false)
    enterPressed=true; emit(ModCallbacks.MC_POST_RENDER); enterPressed=false
    stage=case[2]; enter(5,10)
    if case[1]==3 then
        emit(ModCallbacks.MC_POST_NPC_DEATH,{Type=950,Variant=2}); tick(0)
        eq(snapshot().run.bossPoints,500,"Dogma is Home's only floor award")
    end
    emit(ModCallbacks.MC_POST_NPC_DEATH,{Type=case[3],Variant=case[4]}); tick(0)
    eq(snapshot().status,"finished","endpoint "..case[1])
    eq(snapshot().run.bossPoints,2500,"endpoint + floor / Dogma")
    local before=snapshot().best
    emit(ModCallbacks.MC_POST_NPC_DEATH,{Type=case[3],Variant=case[4]}); tick(0)
    eq(snapshot().best,before,"scripted end does not settle twice")
end
print("Callbacks: "..checks.." assertions passed")
