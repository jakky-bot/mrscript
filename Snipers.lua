-- ============================================================
-- BRAINROT SNIPER v2 - Configurable Target + Mutation Filter
-- ============================================================

-- Rayfield loader
local RayfieldLoaded, Rayfield = pcall(function()
    return loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
end)

if not RayfieldLoaded then
    warn("[BrainrotSniper] Rayfield failed to load: " .. tostring(Rayfield))
    return
end

-- ============================================================
-- SERVICES & REMOTES
-- ============================================================

local Players   = game:GetService("Players")
local RS        = game:GetService("ReplicatedStorage")
local lp        = Players.LocalPlayer
local net       = RS.Shared.Packages.Net

local AttackRE            = net:FindFirstChild("RE/BrainrotAttack")
local DroneCapRF          = net:FindFirstChild("RF/DroneCapture")
local DroneStateRE        = net:FindFirstChild("RE/DroneState")
local MoveRE              = net:FindFirstChild("RE/BrainrotMove")
local BalloonHitRE        = net:FindFirstChild("RE/BalloonHit")
local BalloonHitConfirmRE = net:FindFirstChild("RE/BalloonHitConfirm")
local ClaimGoldRE         = net:FindFirstChild("RE/ClaimGold")
local ScopeStateRE        = net:FindFirstChild("RE/ScopeState")
local EquipBestRE         = net:FindFirstChild("RE/EquipBestBrainrot")
local ChargeShieldRF      = net:FindFirstChild("RF/ChargeShield")
local BrainrotDataReqRE   = net:FindFirstChild("RE/brainrot_data_sync_charm_request")
local BrainrotDataSyncRE  = net:FindFirstChild("RE/brainrot_data_sync_charm_sync")

-- ============================================================
-- LOAD CONFIGS
-- ============================================================

local brainrotCfgOk, BrainrotConfig =
    pcall(require, RS.Config.Brainrot.BrainrotConfig)

local mutCfgOk, MutationConfig =
    pcall(require, RS.Config.Brainrot.BrainrotMutationConfig)

local idToCash    = {}  -- brainrotId -> base cash
local idToName    = {}  -- brainrotId -> display name
local allBrainrots = {} -- sorted {id, name, cash}

if brainrotCfgOk and type(BrainrotConfig) == "table" then
    for _, v in pairs(BrainrotConfig) do
        if type(v) == "table" and v.id then
            local name = type(v.name) == "string" and v.name
                         or ("(id " .. tostring(v.id) .. ")")
            idToCash[v.id] = v.cash_product or 0
            idToName[v.id] = name
            table.insert(allBrainrots, { id = v.id, name = name, cash = v.cash_product or 0 })
        end
    end
    table.sort(allBrainrots, function(a, b) return a.cash > b.cash end)
end

local mutMultiplier = {}  -- mutId -> multiplier
local mutIdToName   = {}  -- mutId -> display name
local allMutations  = {}  -- sorted {id, name, mult}

if mutCfgOk and type(MutationConfig) == "table" then
    for _, v in pairs(MutationConfig) do
        if type(v) == "table" and v.id then
            local name = type(v.name) == "string" and v.name
                         or ("mut" .. tostring(v.id))
            mutMultiplier[v.id] = v.multiplier or 1
            mutIdToName[v.id]   = name
            table.insert(allMutations, { id = v.id, name = name, mult = v.multiplier or 1 })
        end
    end
    table.sort(allMutations, function(a, b) return a.mult > b.mult end)
end

-- ============================================================
-- RESOLVE PLAYER'S OWN PLOT SPAWN POINT
-- Find the PlayerPlacePos part closest to the player at load time.
-- This part is named by plot number (e.g. "2") and stays fixed.
-- ============================================================

local plotSpawnPart = nil

local function resolveOwnPlot()
    local char = lp.Character or lp.CharacterAdded:Wait()
    local hrp  = char:WaitForChild("HumanoidRootPart", 5)
    if not hrp then return end

    local gf  = workspace:FindFirstChild("GameFolder")
    local ppp = gf and gf:FindFirstChild("PlayerPlacePos")
    if not ppp then return end

    local closest, closestDist = nil, math.huge
    for _, part in ipairs(ppp:GetChildren()) do
        if part:IsA("BasePart") then
            local dist = (hrp.Position - part.Position).Magnitude
            if dist < closestDist then
                closestDist = dist
                closest = part
            end
        end
    end
    plotSpawnPart = closest
    print(string.format(
        "[BrainrotSniper] Plot spawn resolved: Part=%s  dist=%.1f  pos=%s",
        closest and closest.Name or "nil", closestDist,
        closest and tostring(closest.Position) or "nil"
    ))
end

-- Run immediately, and also re-resolve after any respawn
task.spawn(resolveOwnPlot)
lp.CharacterAdded:Connect(function() task.wait(1); resolveOwnPlot() end)

-- ============================================================
-- CONFIGURATION STATE  (single source of truth)
-- ============================================================

local cfg = {
    enabled             = false, -- auto-targeting ON/OFF
    selectedBrainrotIds = {},    -- set: brainrotId -> true
    selectedMutationIds = {},    -- set: mutId      -> true
    balloonEnabled      = false, -- auto-shoot balloons for skin tokens
    collectEnabled      = false, -- auto-collect all money
    collectInterval     = 5,     -- seconds between collections
    droneBestEnabled    = false, -- auto equip best brainrot + drone best
    droneShieldEnabled  = false, -- auto charge drone shield when off cooldown
    skipAnimEnabled     = false, -- skip sniper scope animation on attack
}

-- ============================================================
-- LIVE TARGET TRACKING
-- ============================================================

local liveTargets = {} -- uid -> {uid, spaceId, id, mutation, position}
local shotTargets = {} -- uid -> true  (cleared when target's destroy event fires)

if MoveRE then
    MoveRE.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        for _, entry in pairs(data) do
            if type(entry) == "table" and entry.uid then
                if entry.destroy then
                    liveTargets[entry.uid] = nil
                    shotTargets[entry.uid] = nil
                else
                    local t = liveTargets[entry.uid] or {}
                    t.uid      = entry.uid
                    t.spaceId  = entry.spaceId  or t.spaceId
                    t.id       = entry.id       or t.id
                    t.mutation = entry.mutation or t.mutation or 1
                    if entry.position then t.position = entry.position end
                    liveTargets[entry.uid] = t
                end
            end
        end
    end)
end

-- ============================================================
-- HELPERS
-- ============================================================

local function fmt(n)
    if     n >= 1e15 then return string.format("%.2fQ", n / 1e15)
    elseif n >= 1e12 then return string.format("%.2fT", n / 1e12)
    elseif n >= 1e9  then return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6  then return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3  then return string.format("%.2fK", n / 1e3)
    else                  return string.format("%.0f",  n)
    end
end

local function getDisplayName(brainrotId, mutationId)
    local bName = idToName[brainrotId]    or ("id=" .. tostring(brainrotId))
    local mName = mutIdToName[mutationId] or ""
    return (mName ~= "" and mName ~= "Normal") and (mName .. " " .. bName) or bName
end

local function selectedNamesStr(selectedSet, idToNameMap)
    local names = {}
    for id in pairs(selectedSet) do
        table.insert(names, idToNameMap[id] or tostring(id))
    end
    if #names == 0 then return "None" end
    table.sort(names)
    return table.concat(names, ", ")
end

-- ============================================================
-- TELEPORT BACK TO OWN PLOT
-- ============================================================

local function teleportToPlot()
    if not plotSpawnPart then
        warn("[BrainrotSniper] plotSpawnPart not resolved yet, skipping return TP")
        return
    end
    local char = lp.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end
    hrp.CFrame = CFrame.new(plotSpawnPart.Position + Vector3.new(0, 5, 0))
    print("[BrainrotSniper] Teleported back to plot: " .. plotSpawnPart.Name)
end

-- ============================================================
-- SHOOT + COLLECT  (returns true on success)
-- ============================================================

local function shootAndCollect(target)
    local displayName = getDisplayName(target.id, target.mutation)
    local base  = idToCash[target.id] or 0
    local mult  = mutMultiplier[target.mutation] or 1
    local valStr = fmt(base * mult)

    print(string.format(
        "[BrainrotSniper] Shooting > %s (uid=%s) val=$%s/s spaceId=%s",
        displayName, target.uid, valStr, tostring(target.spaceId)
    ))

    -- 1. Teleport above target to bypass range check
    local char = lp.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and target.position then
        hrp.CFrame = CFrame.new(target.position + Vector3.new(0, 80, 0))
        task.wait(0.15)
    end

    -- 2. Fire attack RE (with optional scope-skip)
    if AttackRE then
        if cfg.skipAnimEnabled and ScopeStateRE then
            pcall(function() ScopeStateRE:FireServer(true) end)
            task.wait(0.05)
        end
        AttackRE:FireServer(target.uid)
        if cfg.skipAnimEnabled and ScopeStateRE then
            task.wait(0.05)
            pcall(function() ScopeStateRE:FireServer(false) end)
        end
    else
        warn("[BrainrotSniper] AttackRE not found")
        return false
    end
    task.wait(0.5)

    -- 3. Supplemental DroneCapture
    if DroneCapRF then
        task.wait(0.2)
        pcall(function() DroneCapRF:InvokeServer(target.uid, target.spaceId) end)
    end

    -- 4. Teleport player back to their own plot
    task.wait(0.3)
    teleportToPlot()

    return true
end

-- ============================================================
-- FIND MATCHING TARGET
-- ============================================================

local function findMatchingTarget()
    local hasAnyBrainrot = next(cfg.selectedBrainrotIds) ~= nil
    local hasAnyMutation  = next(cfg.selectedMutationIds) ~= nil
    if not hasAnyBrainrot and not hasAnyMutation then return nil end

    for uid, t in pairs(liveTargets) do
        if shotTargets[uid] then continue end
        local brainrotMatch = not hasAnyBrainrot or cfg.selectedBrainrotIds[t.id]
        local mutationMatch  = not hasAnyMutation  or cfg.selectedMutationIds[t.mutation]
        if brainrotMatch and mutationMatch then return t end
    end
    return nil
end

-- ============================================================
-- BALLOON SKIN TOKEN AUTO-SHOOT
-- Scans workspace.ClientBalloon every second for live balloons,
-- fires RE/BalloonHit for each un-hit one, then waits for the
-- BalloonHitConfirm echo before moving on.
-- ============================================================

local shotBalloons = {}   -- uid -> true  (reset on balloon despawn)
local balloonHitsTotal = 0

-- Clear our hit-log when the balloon folder changes so stale uids don't
-- block fresh spawns of the same uid.
local ClientBalloonFolder = workspace:FindFirstChildOfClass("Folder", false)
do
    -- locate the folder by name at startup (it may arrive slightly late)
    local function findCBFolder()
        return workspace:FindFirstChild("ClientBalloon")
    end
    local cbf = findCBFolder() or workspace:WaitForChild("ClientBalloon", 30)
    if cbf then
        cbf.ChildRemoved:Connect(function(child)
            local uid = child:GetAttribute("Uid")
            if uid then shotBalloons[uid] = nil end
        end)
    end
end

task.spawn(function()
    while task.wait(1) do
        if not cfg.balloonEnabled then continue end
        if not BalloonHitRE then continue end

        local cbFolder = workspace:FindFirstChild("ClientBalloon")
        if not cbFolder then continue end

        for _, balloon in ipairs(cbFolder:GetChildren()) do
            if not cfg.balloonEnabled then break end
            local uid = balloon:GetAttribute("Uid")
            if uid and not shotBalloons[uid] then
                shotBalloons[uid] = true

                -- Fire the hit and wait for server confirm (up to 2 s)
                local confirmed = false
                local conn
                if BalloonHitConfirmRE then
                    conn = BalloonHitConfirmRE.OnClientEvent:Connect(function(confirmedUid)
                        if confirmedUid == uid then
                            confirmed = true
                        end
                    end)
                end

                pcall(function() BalloonHitRE:FireServer(uid) end)

                -- Brief yield so the confirm can arrive
                task.wait(0.4)
                if conn then conn:Disconnect() end

                if confirmed then
                    balloonHitsTotal = balloonHitsTotal + 1
                    print(string.format(
                        "[BrainrotSniper] 🎈 Balloon hit! uid=%s  total=%d",
                        tostring(uid), balloonHitsTotal
                    ))
                end

                task.wait(0.15)  -- slight gap between balloons
            end
        end
    end
end)

-- ============================================================
-- AUTO-COLLECT MONEY  (workspace-scan implementation)
--
-- HOW THE GAME STORES SLOTS (confirmed by live inspection):
--   workspace
--     GameFolder
--       PlayerPlace
--         <plotModel>           ← Model, Attribute "UserId" = owner's UserId
--           Places              ← Folder
--             <N>               ← Model container per slot (name = slot number)
--               <N>             ← Model with Attribute "SlotIndex" (number)
--                                  Also carries: Uid, Owner, CashSpeed, Level
--
-- RE/ClaimGold:FireServer(SlotIndex) — one integer per occupied slot.
-- Confirmed live: firing for all 11 SlotIndex values collected all income.
-- ============================================================

local collectTotal  = 0   -- sweep cycles completed
local lastGoldPatch = 0   -- last Gold value from eco sync
local collectTimer  = 0   -- seconds elapsed since last sweep

-- ── Find our own plot model ───────────────────────────────────
-- Returns the Model under GameFolder.PlayerPlace whose UserId attribute
-- matches LocalPlayer.UserId, or nil if not yet replicated.
local function getOwnPlot()
    local gf = workspace:FindFirstChild("GameFolder")
    local playerPlace = gf and gf:FindFirstChild("PlayerPlace")
    if not playerPlace then return nil end
    for _, model in ipairs(playerPlace:GetChildren()) do
        if model:GetAttribute("UserId") == lp.UserId then
            return model
        end
    end
    return nil
end

-- ── Scan all occupied slots on our plot ──────────────────────
-- Returns a list of SlotIndex numbers for every brainrot currently placed.
-- Re-called each sweep so newly placed brainrots are always included.
local function getOccupiedSlotIndices()
    local plot = getOwnPlot()
    if not plot then
        warn("[BrainrotSniper] 💰 Own plot not found in PlayerPlace — skipping sweep")
        return {}
    end

    local placesFolder = plot:FindFirstChild("Places")
    if not placesFolder then
        warn("[BrainrotSniper] 💰 No 'Places' folder inside plot '" .. plot.Name .. "'")
        return {}
    end

    local indices = {}
    for _, container in ipairs(placesFolder:GetChildren()) do
        -- Each container holds one child Model that carries the SlotIndex attribute
        for _, slotModel in ipairs(container:GetChildren()) do
            local si = slotModel:GetAttribute("SlotIndex")
            -- Must be a number and belong to us (Owner attribute double-check)
            if type(si) == "number" then
                local owner = slotModel:GetAttribute("Owner")
                if owner == nil or owner == lp.UserId then
                    table.insert(indices, si)
                end
            end
        end
    end

    table.sort(indices)
    return indices
end

-- ── Perform one full collection sweep ────────────────────────
local function doCollectSweep()
    if not ClaimGoldRE then
        warn("[BrainrotSniper] 💰 ClaimGoldRE not found — cannot collect")
        return
    end

    local indices = getOccupiedSlotIndices()
    if #indices == 0 then
        print("[BrainrotSniper] 💰 No occupied slots found on own plot this sweep")
        return
    end

    local fired = 0
    for _, si in ipairs(indices) do
        pcall(function() ClaimGoldRE:FireServer(si) end)
        fired = fired + 1
        task.wait(0.05)  -- small gap between fires to avoid flooding
    end

    collectTotal = collectTotal + 1
    print(string.format(
        "[BrainrotSniper] 💰 Sweep #%d — collected %d slots: [%s]",
        collectTotal, fired, table.concat(indices, ", ")
    ))
end

-- ── Listen for eco patches (gold display label) ───────────────
local EcoSyncRE = net:FindFirstChild("RE/eco_data_sync_charm_sync")
if EcoSyncRE then
    EcoSyncRE.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local state = data.data and data.data.state
        if state and state.Gold then
            lastGoldPatch = state.Gold
        end
    end)
end

-- ── Main collect loop — ticks every 1 s ──────────────────────
task.spawn(function()
    while task.wait(1) do
        if not cfg.collectEnabled then
            collectTimer = 0
            continue
        end
        collectTimer = collectTimer + 1
        if collectTimer >= cfg.collectInterval then
            collectTimer = 0
            task.spawn(doCollectSweep)  -- background so UI timer isn't blocked
        end
    end
end)

-- ============================================================
-- AUTO DRONE BEST
-- Fires RE/EquipBestBrainrot every 30 s to auto-equip the
-- strongest brainrot into the drone slot.
-- ============================================================

local _droneBestFires = 0   -- declared here; UI tab increments read this

task.spawn(function()
    while task.wait(30) do
        if not cfg.droneBestEnabled then continue end
        if not EquipBestRE then continue end
        pcall(function() EquipBestRE:FireServer() end)
        _droneBestFires = _droneBestFires + 1
        print("[BrainrotSniper] 🤖 EquipBestBrainrot fired #" .. _droneBestFires)
    end
end)

-- ============================================================
-- AUTO DRONE SHIELD
-- Calls RF/ChargeShield every 5 s; the server rejects with
-- {success=false,reason="cooldown"} when on cooldown so we
-- only count actual successes.
-- ============================================================

local shieldCharges = 0

task.spawn(function()
    while task.wait(5) do
        if not cfg.droneShieldEnabled then continue end
        if not ChargeShieldRF then continue end
        local ok, result = pcall(function() return ChargeShieldRF:InvokeServer() end)
        if ok and type(result) == "table" and result.success then
            shieldCharges = shieldCharges + 1
            print(string.format(
                "[BrainrotSniper] 🛡 Shield charged! (total=%d)",
                shieldCharges
            ))
        end
    end
end)

-- ============================================================
-- SKIP SNIPER SHOOT ANIMATION
-- Hooks into the existing attack path: immediately after
-- AttackRE fires, we send ScopeState(false) to collapse the
-- scope animation so the next shot is ready instantly.
-- We wrap the existing doAttack function via a flag so the
-- hook fires only when our script shoots.
-- ============================================================
-- (The hook is applied in the attack loop below via
--  cfg.skipAnimEnabled; see the killTarget function.)

local _origAttackFire = nil  -- set after the main attack loop is defined

-- ============================================================
-- RAYFIELD UI
-- ============================================================

local Window = Rayfield:CreateWindow({
    Name            = "🎯 Brainrot Sniper v2",
    LoadingTitle    = "Brainrot Sniper Script",
    LoadingSubtitle = "Configurable Target + Mutation Filter + Balloon + AutoCollect",
    ConfigurationSaving = { Enabled = false },
    Discord         = { Enabled = false },
    KeySystem       = false,
})

-- ----------------------------------------------------------------
-- TAB 1: STATUS
-- NOTE: Rayfield labels MUST be updated with lbl:Set("text").
--       Assigning lbl.Text = "..." only writes to the Lua wrapper
--       table and is silently ignored by the UI. All label updates
--       in this script exclusively use :Set().
-- ----------------------------------------------------------------
local StatusTab = Window:CreateTab("📊 Status", 4483362458)
StatusTab:CreateSection("Auto-Targeting Status")

local StatusLabel    = StatusTab:CreateLabel("⏸ Auto-targeting is OFF")
local TargetsLabel   = StatusTab:CreateLabel("🎯 Selected Brainrots: None")
local MutationsLabel = StatusTab:CreateLabel("✨ Selected Mutations: None")
local TrackingLabel  = StatusTab:CreateLabel("🔎 Tracking 0 live targets")
local LastShotLabel  = StatusTab:CreateLabel("🔫 Last shot: —")

StatusTab:CreateDivider()

-- The toggle ONLY writes cfg.enabled. The refresh loop owns all label updates.
StatusTab:CreateToggle({
    Name     = "🔴 / 🟢  Auto-Targeting (ON / OFF)",
    Default  = false,
    Callback = function(val)
        cfg.enabled = val
    end,
})

-- ----------------------------------------------------------------
-- TAB 2: BRAINROT SELECTION
-- ----------------------------------------------------------------
local BrainrotTab = Window:CreateTab("🧬 Brainrots", 4483362458)
BrainrotTab:CreateSection("Select Target Brainrots")
BrainrotTab:CreateLabel("Toggle ON any Brainrot(s) you want to hunt.")
BrainrotTab:CreateLabel("Leave all OFF to match ANY Brainrot.")
BrainrotTab:CreateDivider()

for _, b in ipairs(allBrainrots) do
    local bId = b.id
    BrainrotTab:CreateToggle({
        Name     = b.name .. "  [$" .. fmt(b.cash) .. "/s]",
        Default  = false,
        Callback = function(val)
            cfg.selectedBrainrotIds[bId] = val and true or nil
        end,
    })
end

-- ----------------------------------------------------------------
-- TAB 3: MUTATION SELECTION
-- ----------------------------------------------------------------
local MutationTab = Window:CreateTab("✨ Mutations", 4483362458)
MutationTab:CreateSection("Select Target Mutations")
MutationTab:CreateLabel("Toggle ON any Mutation(s) you want to target.")
MutationTab:CreateLabel("Leave all OFF to match ANY Mutation.")
MutationTab:CreateDivider()

for _, m in ipairs(allMutations) do
    local mId = m.id
    MutationTab:CreateToggle({
        Name     = m.name .. "  [x" .. tostring(m.mult) .. "]",
        Default  = false,
        Callback = function(val)
            cfg.selectedMutationIds[mId] = val and true or nil
        end,
    })
end

-- ----------------------------------------------------------------
-- TAB 4: BALLOON SKIN TOKENS
-- ----------------------------------------------------------------
local BalloonTab = Window:CreateTab("🎈 Balloon Tokens", 4483362458)
BalloonTab:CreateSection("Auto-Shoot Balloons for Skin Tokens")
BalloonTab:CreateLabel("Shoots every balloon in your area automatically.")
BalloonTab:CreateLabel("Each hit awards a Skin Token from the server.")
BalloonTab:CreateLabel("Balloons respawn ~every 120 seconds.")
BalloonTab:CreateDivider()

local BalloonStatusLabel = BalloonTab:CreateLabel("🎈 Balloon auto-shoot: OFF")
local BalloonHitsLabel   = BalloonTab:CreateLabel("🎯 Tokens earned this session: 0")

BalloonTab:CreateToggle({
    Name     = "🔴 / 🟢  Auto-Shoot Balloons (ON / OFF)",
    Default  = false,
    Callback = function(val)
        cfg.balloonEnabled = val
        BalloonStatusLabel:Set(val
            and "🟢 Balloon auto-shoot: ON — scanning..."
            or  "⏸ Balloon auto-shoot: OFF")
    end,
})

-- Refresh balloon hit counter every second
task.spawn(function()
    local lastCount = -1
    while task.wait(1) do
        if balloonHitsTotal ~= lastCount then
            lastCount = balloonHitsTotal
            BalloonHitsLabel:Set("🎯 Tokens earned this session: " .. lastCount)
        end
    end
end)

-- ----------------------------------------------------------------
-- TAB 5: AUTO-COLLECT MONEY
-- ----------------------------------------------------------------
local CollectTab = Window:CreateTab("💰 Auto Collect", 4483362458)
CollectTab:CreateSection("Auto-Collect All Money")
CollectTab:CreateLabel("Fires RE/ClaimGold on a timer to sweep your income.")
CollectTab:CreateLabel("Set your preferred interval below, then enable.")
CollectTab:CreateDivider()

local CollectStatusLabel  = CollectTab:CreateLabel("💰 Auto-collect: OFF")
local CollectGoldLabel    = CollectTab:CreateLabel("🪙 Last gold reading: —")
local CollectCountLabel   = CollectTab:CreateLabel("📦 Collect fires this session: 0")
local CollectTimerLabel   = CollectTab:CreateLabel("⏱ Next collect in: —")

CollectTab:CreateToggle({
    Name     = "🔴 / 🟢  Auto-Collect Money (ON / OFF)",
    Default  = false,
    Callback = function(val)
        cfg.collectEnabled = val
        collectTimer = 0   -- reset countdown on toggle
        CollectStatusLabel:Set(val
            and "🟢 Auto-collect: ON"
            or  "⏸ Auto-collect: OFF")
    end,
})

CollectTab:CreateSlider({
    Name    = "⏱ Collection Interval (seconds)",
    Range   = {1, 60},
    Increment = 1,
    Suffix  = "s",
    CurrentValue = cfg.collectInterval,
    Callback = function(val)
        cfg.collectInterval = val
        collectTimer = 0   -- reset so new interval takes effect immediately
    end,
})

-- Live status refresh
task.spawn(function()
    local lastFires = -1
    while task.wait(0.5) do
        -- gold label
        if lastGoldPatch > 0 then
            CollectGoldLabel:Set("🪙 Last gold reading: " .. fmt(lastGoldPatch))
        end
        -- fire count
        if collectTotal ~= lastFires then
            lastFires = collectTotal
            CollectCountLabel:Set("📦 Collect fires this session: " .. collectTotal)
        end
        -- countdown
        if cfg.collectEnabled then
            local remaining = cfg.collectInterval - collectTimer
            CollectTimerLabel:Set("⏱ Next collect in: " .. remaining .. "s")
        else
            CollectTimerLabel:Set("⏱ Next collect in: —")
        end
    end
end)

-- ----------------------------------------------------------------
-- TAB 6: AUTO DRONE BEST
-- ----------------------------------------------------------------
local DroneBestTab = Window:CreateTab("🤖 Drone Best", 4483362458)
DroneBestTab:CreateSection("Auto Equip Best Brainrot (Drone)")
DroneBestTab:CreateLabel("Fires RE/EquipBestBrainrot every 30 s.")
DroneBestTab:CreateLabel("The server picks and equips your strongest brainrot into the drone slot automatically.")
DroneBestTab:CreateDivider()

local DroneBestStatusLabel = DroneBestTab:CreateLabel("🤖 Auto Drone Best: OFF")
local DroneBestCountLabel  = DroneBestTab:CreateLabel("📡 Equip fires this session: 0")

DroneBestTab:CreateToggle({
    Name     = "🔴 / 🟢  Auto Drone Best (ON / OFF)",
    Default  = false,
    Callback = function(val)
        cfg.droneBestEnabled = val
        DroneBestStatusLabel:Set(val and "🟢 Auto Drone Best: ON" or "⏸ Auto Drone Best: OFF")
        if val and EquipBestRE then
            -- fire immediately on enable
            pcall(function() EquipBestRE:FireServer() end)
            _droneBestFires = _droneBestFires + 1
            DroneBestCountLabel:Set("📡 Equip fires this session: " .. _droneBestFires)
        end
    end,
})

-- Counter updater (the loop itself is in the logic section above)
task.spawn(function()
    local last = -1
    -- patch the loop counter into the UI
    while task.wait(1) do
        -- we count via the print statement in the loop; mirror via _G
        if _droneBestFires ~= last then
            last = _droneBestFires
            DroneBestCountLabel:Set("📡 Equip fires this session: " .. _droneBestFires)
        end
    end
end)

-- ----------------------------------------------------------------
-- TAB 7: AUTO DRONE SHIELD
-- ----------------------------------------------------------------
local DroneShieldTab = Window:CreateTab("🛡 Drone Shield", 4483362458)
DroneShieldTab:CreateSection("Auto Charge Drone Shield")
DroneShieldTab:CreateLabel("Polls RF/ChargeShield every 5 s.")
DroneShieldTab:CreateLabel("Server rejects silently while on cooldown — only counts real charges.")
DroneShieldTab:CreateDivider()

local DroneShieldStatusLabel = DroneShieldTab:CreateLabel("🛡 Auto Drone Shield: OFF")
local DroneShieldCountLabel  = DroneShieldTab:CreateLabel("⚡ Shields charged this session: 0")

DroneShieldTab:CreateToggle({
    Name     = "🔴 / 🟢  Auto Drone Shield (ON / OFF)",
    Default  = false,
    Callback = function(val)
        cfg.droneShieldEnabled = val
        DroneShieldStatusLabel:Set(val and "🟢 Auto Drone Shield: ON (polling every 5s)" or "⏸ Auto Drone Shield: OFF")
        if val and ChargeShieldRF then
            -- try immediately
            local ok, res = pcall(function() return ChargeShieldRF:InvokeServer() end)
            if ok and type(res) == "table" and res.success then
                shieldCharges = shieldCharges + 1
            end
        end
    end,
})

task.spawn(function()
    local lastShield = -1
    while task.wait(1) do
        if shieldCharges ~= lastShield then
            lastShield = shieldCharges
            DroneShieldCountLabel:Set("⚡ Shields charged this session: " .. shieldCharges)
        end
    end
end)

-- ----------------------------------------------------------------
-- TAB 8: SKIP SNIPER ANIMATION
-- ----------------------------------------------------------------
local SkipAnimTab = Window:CreateTab("⚡ Skip Anim", 4483362458)
SkipAnimTab:CreateSection("Skip Sniper Shoot Animation")
SkipAnimTab:CreateLabel("Fires ScopeState(true) then ScopeState(false) around each attack.")
SkipAnimTab:CreateLabel("This collapses the scope-in/scope-out animation immediately so the next shot cycles faster.")
SkipAnimTab:CreateDivider()

local SkipAnimStatusLabel = SkipAnimTab:CreateLabel("⚡ Skip Anim: OFF")

SkipAnimTab:CreateToggle({
    Name     = "🔴 / 🟢  Skip Sniper Animation (ON / OFF)",
    Default  = false,
    Callback = function(val)
        cfg.skipAnimEnabled = val
        SkipAnimStatusLabel:Set(val and "🟢 Skip Anim: ON — faster cycle enabled" or "⏸ Skip Anim: OFF")
    end,
})

-- ----------------------------------------------------------------
-- TAB 9: INFO (read-only reference)
-- ----------------------------------------------------------------
local InfoTab = Window:CreateTab("ℹ️ Info", 4483362458)
InfoTab:CreateSection("How It Works")
InfoTab:CreateLabel("1. Select Brainrots and/or Mutations in their tabs")
InfoTab:CreateLabel("2. Leave a filter empty to match ANY value for that field")
InfoTab:CreateLabel("3. Enable Auto-Targeting on the Status tab")
InfoTab:CreateLabel("4. Scanner fires every 0.5 s looking for a match")
InfoTab:CreateLabel("5. On match: teleports above target → fires attack → drone collects")
InfoTab:CreateLabel("6. After shot: teleports you back to your plot automatically")
InfoTab:CreateLabel("7. Each target UID is only processed once per spawn")
InfoTab:CreateDivider()
InfoTab:CreateSection("Auto-Collect Money")
InfoTab:CreateLabel("Enable in 💰 tab — set interval with the slider (1–60 s)")
InfoTab:CreateLabel("Scans GameFolder.PlayerPlace each sweep for your plot (UserId attr)")
InfoTab:CreateLabel("Reads Places > <slot> > <slot>.SlotIndex from your plot each cycle")
InfoTab:CreateLabel("Fires RE/ClaimGold(SlotIndex) once per occupied slot — no guessing")
InfoTab:CreateLabel("New slots placed after script starts are collected automatically")
InfoTab:CreateLabel("Never touches other players' plots (Owner attr double-checked)")
InfoTab:CreateDivider()
InfoTab:CreateSection("Auto Drone Best / Shield / Skip Anim")
InfoTab:CreateLabel("🤖 Drone Best: RE/EquipBestBrainrot fires every 30 s (fires immediately on enable)")
InfoTab:CreateLabel("🛡 Drone Shield: RF/ChargeShield polled every 5 s; cooldown silently rejected by server")
InfoTab:CreateLabel("⚡ Skip Anim: ScopeState(true→false) wraps each AttackRE fire to collapse scope animation")
InfoTab:CreateDivider()
InfoTab:CreateSection("Balloon Skin Tokens")
InfoTab:CreateLabel("Enable 'Auto-Shoot Balloons' in the 🎈 tab")
InfoTab:CreateLabel("Balloons appear in workspace.ClientBalloon with a Uid attribute")
InfoTab:CreateLabel("RE/BalloonHit is fired per balloon — server confirms with RE/BalloonHitConfirm")
InfoTab:CreateLabel("Balloons respawn ~every 120 s; stale UIDs are cleared automatically")
InfoTab:CreateDivider()
InfoTab:CreateSection("Mutation Multipliers")
InfoTab:CreateLabel("Normal x1  •  Gold x1.5  •  Diamond x2")
InfoTab:CreateLabel("Emerald x3  •  Void x4  •  Rainbow x10")

-- ============================================================
-- DRONE STATE FEEDBACK  (writes to StatusLabel via :Set())
-- ============================================================

if DroneStateRE then
    local droneStates = {
        [1] = "🚀 Drone launched",
        [2] = "✈️ Drone flying to target",
        [3] = "📦 Drone carrying target",
        [4] = "🔄 Drone returning home",
        [5] = "✅ Drone delivered!",
    }
    DroneStateRE.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" or data.owner ~= lp.UserId then return end
        local msg = droneStates[data.state] or ("Drone state " .. tostring(data.state))
        StatusLabel:Set(msg)
    end)
end

-- ============================================================
-- STATUS REFRESH LOOP
-- Runs every 0.5 s. This is the ONLY place that writes to the
-- Status tab labels, ensuring they always reflect real cfg state.
-- Uses :Set() — the only Rayfield API that actually updates the UI.
-- ============================================================

task.spawn(function()
    while task.wait(0.5) do
        -- ON/OFF
        StatusLabel:Set(cfg.enabled
            and "🟢 Auto-targeting is ON — scanning..."
            or  "⏸ Auto-targeting is OFF")

        -- Selected Brainrots
        TargetsLabel:Set("🎯 Selected Brainrots: "
            .. selectedNamesStr(cfg.selectedBrainrotIds, idToName))

        -- Selected Mutations
        MutationsLabel:Set("✨ Selected Mutations: "
            .. selectedNamesStr(cfg.selectedMutationIds, mutIdToName))

        -- Live target count
        local count = 0
        for _ in pairs(liveTargets) do count = count + 1 end
        TrackingLabel:Set(string.format("🔎 Tracking %d live targets", count))
    end
end)

-- ============================================================
-- MAIN AUTO-SCAN LOOP  (every 0.5 s)
-- ============================================================

task.spawn(function()
    local isShooting = false

    while task.wait(0.5) do
        if not cfg.enabled or isShooting then continue end

        local match = findMatchingTarget()
        if not match then continue end

        -- Lock immediately to prevent duplicate triggers
        shotTargets[match.uid] = true
        isShooting = true

        local displayName = getDisplayName(match.id, match.mutation)
        local base = idToCash[match.id] or 0
        local mult = mutMultiplier[match.mutation] or 1
        LastShotLabel:Set("🔫 Last shot: " .. displayName .. " ($" .. fmt(base * mult) .. "/s)")

        task.spawn(function()
            local ok, err = pcall(shootAndCollect, match)
            if not ok then
                warn("[BrainrotSniper] Error: " .. tostring(err))
            end
            isShooting = false
        end)
    end
end)

print("[BrainrotSniper v2] Script loaded successfully!")
