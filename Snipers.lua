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

local idToCash    = {}
local idToName    = {}
local allBrainrots = {}

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

local mutMultiplier = {}
local mutIdToName   = {}
local allMutations  = {}

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

task.spawn(resolveOwnPlot)
lp.CharacterAdded:Connect(function() task.wait(1); resolveOwnPlot() end)

-- ============================================================
-- CONFIGURATION STATE
-- ============================================================

local cfg = {
    enabled             = false,
    selectedBrainrotIds = {},
    selectedMutationIds = {},
    balloonEnabled      = false,
    collectEnabled      = false,
    collectInterval     = 5,
    droneBestEnabled    = false,
    droneShieldEnabled  = false,
    skipAnimEnabled     = false,
}

-- ============================================================
-- LIVE TARGET TRACKING
-- ============================================================

local liveTargets = {}
local shotTargets = {}

local BrainrotModelsFolder = nil
pcall(function()
    local gf = workspace:WaitForChild("GameFolder", 10)
    BrainrotModelsFolder = gf:WaitForChild("BrainrotModels", 10)
end)

local function entryFromModel(model)
    local uid = model:GetAttribute("Uid")
    if not uid then return nil end
    local hrp = model:FindFirstChild("HumanoidRootPart", true)
    return {
        uid      = uid,
        id       = model:GetAttribute("BrainrotId"),
        mutation = model:GetAttribute("BrainrotMutation") or 1,
        spaceId  = model:GetAttribute("BrainrotSpaceId"),
        position = hrp and hrp.Position or nil,
        model    = model,
    }
end

local function syncFromWorkspace()
    if not BrainrotModelsFolder then return end
    local seenUids = {}
    for _, model in ipairs(BrainrotModelsFolder:GetChildren()) do
        local entry = entryFromModel(model)
        if entry then
            seenUids[entry.uid] = true
            local existing = liveTargets[entry.uid]
            if not existing then
                liveTargets[entry.uid] = entry
            else
                local hrp = model:FindFirstChild("HumanoidRootPart", true)
                if hrp then existing.position = hrp.Position end
                existing.model   = model
                existing.spaceId = model:GetAttribute("BrainrotSpaceId") or existing.spaceId
            end
        end
    end
    for uid in pairs(liveTargets) do
        if not seenUids[uid] then
            liveTargets[uid] = nil
            shotTargets[uid] = nil
        end
    end
end

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

if BrainrotModelsFolder then
    BrainrotModelsFolder.ChildAdded:Connect(function(model)
        task.wait(0.1)
        local entry = entryFromModel(model)
        if entry and not liveTargets[entry.uid] then
            liveTargets[entry.uid] = entry
            print(string.format("[BrainrotSniper] [DEBUG] New spawn: uid=%s id=%s mut=%s",
                entry.uid:sub(1,8), tostring(entry.id), tostring(entry.mutation)))
        end
    end)
    BrainrotModelsFolder.ChildRemoved:Connect(function(model)
        local uid = model:GetAttribute("Uid")
        if uid then
            liveTargets[uid] = nil
            shotTargets[uid] = nil
        end
    end)
end

task.spawn(function()
    while task.wait(1) do
        syncFromWorkspace()
    end
end)
task.spawn(syncFromWorkspace)

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
-- SHOOT + COLLECT  — FIXED PIPELINE
--
-- FIX SUMMARY:
--   The server validates that the attacking player is close to
--   the target brainrot before accepting RE/BrainrotAttack.
--   The original code teleported 80 studs above the target's
--   *cached* position and waited only 0.15 s — too short for
--   the server to replicate the new CFrame.
--
--   Fixes applied:
--   1. Always re-read HRP position LIVE from the model at
--      shoot time, never use the stale cached position.
--   2. If the model is gone (despawned), abort instead of
--      teleporting to a stale coord that fails the server check.
--   3. Increased post-teleport wait from 0.15 s → 0.35 s so
--      the server reliably receives the updated player position.
--   4. Added a second position-sync pulse (re-set CFrame after
--      the wait) to fight any server-side position reset.
--   5. spaceId is re-read fresh from the model attribute at
--      shoot time — never rely on the cached entry value which
--      may have been nil if the target arrived via BrainrotMove
--      without a spaceId field.
--   6. ScopeState(true) is now always sent before the attack
--      (not just when skipAnimEnabled) because the server may
--      require an active scope state to accept an attack RE.
--      ScopeState(false) is always sent after.
-- ============================================================

local function shootAndCollect(target)
    local displayName = getDisplayName(target.id, target.mutation)
    local base  = idToCash[target.id] or 0
    local mult  = mutMultiplier[target.mutation] or 1
    local valStr = fmt(base * mult)

    -- ── 1. Get the LIVE position from the model ──────────────────
    -- Do NOT use the cached target.position — brainrots move.
    local model = target.model
    -- Refresh model reference from workspace in case the Lua ref is stale
    if not model or not model.Parent then
        -- Try to find it by uid attribute in BrainrotModels
        if BrainrotModelsFolder then
            for _, m in ipairs(BrainrotModelsFolder:GetChildren()) do
                if m:GetAttribute("Uid") == target.uid then
                    model = m
                    break
                end
            end
        end
    end

    if not model or not model.Parent then
        warn(string.format("[BrainrotSniper] Model gone before shot: uid=%s — skipping", target.uid))
        return false
    end

    local targetHrp = model:FindFirstChild("HumanoidRootPart", true)
    if not targetHrp then
        warn(string.format("[BrainrotSniper] Target has no HRP: uid=%s — skipping", target.uid))
        return false
    end

    -- Read spaceId fresh from the live model attribute
    local spaceId = model:GetAttribute("BrainrotSpaceId") or target.spaceId

    local targetPos = targetHrp.Position

    print(string.format(
        "[BrainrotSniper] Shooting > %s (uid=%s) val=$%s/s spaceId=%s pos=%s",
        displayName, target.uid, valStr, tostring(spaceId), tostring(targetPos)
    ))

    -- ── 2. Teleport player directly above the target ─────────────
    -- We teleport 10 studs above (not 80) — close enough to pass
    -- any server-side proximity check while avoiding the model.
    local char = lp.Character
    local playerHrp = char and char:FindFirstChild("HumanoidRootPart")

    if not playerHrp then
        warn("[BrainrotSniper] Player has no HumanoidRootPart — cannot teleport")
        return false
    end

    local teleportCFrame = CFrame.new(targetPos + Vector3.new(0, 10, 0))
    playerHrp.CFrame = teleportCFrame

    -- ── 3. Wait for server to replicate new player position ───────
    -- 0.35 s is empirically sufficient for Roblox server replication.
    -- Then re-assert the CFrame a second time to fight any server
    -- position correction that might push the player back.
    task.wait(0.2)
    playerHrp.CFrame = teleportCFrame   -- second assertion
    task.wait(0.15)

    -- ── 4. Re-read live target position (it may have moved) ───────
    -- If the target's HRP is still valid, update teleport if needed.
    if targetHrp and targetHrp.Parent then
        local newPos = targetHrp.Position
        local drift = (newPos - targetPos).Magnitude
        if drift > 5 then
            -- Target moved significantly; re-teleport
            targetPos = newPos
            teleportCFrame = CFrame.new(targetPos + Vector3.new(0, 10, 0))
            playerHrp.CFrame = teleportCFrame
            task.wait(0.15)
        end
    end

    -- ── 5. Scope in (always — server may require active scope) ────
    if ScopeStateRE then
        pcall(function() ScopeStateRE:FireServer(true) end)
        task.wait(0.05)
    end

    -- ── 6. Fire the attack RE ─────────────────────────────────────
    -- Protocol confirmed: FireServer(uid) — only the uid string.
    if AttackRE then
        AttackRE:FireServer(target.uid)
        print(string.format("[BrainrotSniper] AttackRE fired: uid=%s", target.uid))
    else
        warn("[BrainrotSniper] AttackRE not found")
        return false
    end

    -- ── 7. Scope out ──────────────────────────────────────────────
    if ScopeStateRE then
        task.wait(0.05)
        pcall(function() ScopeStateRE:FireServer(false) end)
    end

    task.wait(0.4)

    -- ── 8. Supplemental DroneCapture ──────────────────────────────
    -- Pass (uid, spaceId) — spaceId read fresh above.
    if DroneCapRF then
        pcall(function() DroneCapRF:InvokeServer(target.uid, spaceId) end)
    end

    -- ── 9. Teleport player back to their own plot ─────────────────
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
        -- Skip if model is no longer in workspace
        if t.model and not t.model.Parent then continue end
        local brainrotMatch = not hasAnyBrainrot or cfg.selectedBrainrotIds[t.id]
        local mutationMatch  = not hasAnyMutation  or cfg.selectedMutationIds[t.mutation]
        if brainrotMatch and mutationMatch then return t end
    end
    return nil
end

-- ============================================================
-- BALLOON SKIN TOKEN AUTO-SHOOT
-- ============================================================

local shotBalloons = {}
local balloonHitsTotal = 0

local ClientBalloonFolder = workspace:FindFirstChildOfClass("Folder", false)
do
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

                local confirmed = false
                local conn
                if BalloonHitConfirmRE then
                    conn = BalloonHitConfirmRE.OnClientEvent:Connect(function(confirmedUid)
                        if confirmedUid == uid then confirmed = true end
                    end)
                end

                pcall(function() BalloonHitRE:FireServer(uid) end)
                task.wait(0.4)
                if conn then conn:Disconnect() end

                if confirmed then
                    balloonHitsTotal = balloonHitsTotal + 1
                    print(string.format("[BrainrotSniper] 🎈 Balloon hit! uid=%s  total=%d",
                        tostring(uid), balloonHitsTotal))
                end
                task.wait(0.15)
            end
        end
    end
end)

-- ============================================================
-- AUTO-COLLECT MONEY
-- ============================================================

local collectTotal    = 0
local lastGoldPatch   = 0
local collectTimer    = 0
local activeSlotIds   = {}

local function refreshSlotIds(data)
    if type(data) ~= "table" then return end
    local state = data.data and data.data.state
    if not state then return end
    local newIds = {}
    if state.brainrotCollectList then
        for _, entry in pairs(state.brainrotCollectList) do
            if type(entry) == "table" and entry.id then
                table.insert(newIds, entry.id)
            end
        end
    end
    if #newIds > 0 then
        table.sort(newIds)
        activeSlotIds = newIds
    end
end

if BrainrotDataSyncRE then
    BrainrotDataSyncRE.OnClientEvent:Connect(refreshSlotIds)
end
if BrainrotDataReqRE then
    task.delay(2, function() BrainrotDataReqRE:FireServer() end)
end

local EcoSyncRE = net:FindFirstChild("RE/eco_data_sync_charm_sync")
if EcoSyncRE then
    EcoSyncRE.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        local state = data.data and data.data.state
        if state and state.Gold then lastGoldPatch = state.Gold end
    end)
end

task.spawn(function()
    while task.wait(1) do
        if not cfg.collectEnabled then collectTimer = 0; continue end
        if not ClaimGoldRE then continue end

        collectTimer = collectTimer + 1
        if collectTimer >= cfg.collectInterval then
            collectTimer = 0
            local fired = 0
            for _, slotId in ipairs(activeSlotIds) do
                pcall(function() ClaimGoldRE:FireServer(slotId) end)
                fired = fired + 1
                task.wait(0.05)
            end
            pcall(function() ClaimGoldRE:FireServer() end)
            if fired > 0 then
                collectTotal = collectTotal + 1
                print(string.format("[BrainrotSniper] 💰 Collected %d slots  (sweep #%d)", fired, collectTotal))
            end
        end
    end
end)

-- ============================================================
-- AUTO DRONE BEST
-- ============================================================

local _droneBestFires = 0

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
-- ============================================================

local shieldCharges = 0

task.spawn(function()
    while task.wait(5) do
        if not cfg.droneShieldEnabled then continue end
        if not ChargeShieldRF then continue end
        local ok, result = pcall(function() return ChargeShieldRF:InvokeServer() end)
        if ok and type(result) == "table" and result.success then
            shieldCharges = shieldCharges + 1
            print(string.format("[BrainrotSniper] 🛡 Shield charged! (total=%d)", shieldCharges))
        end
    end
end)

local _origAttackFire = nil

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

-- TAB 1: STATUS
local StatusTab = Window:CreateTab("📊 Status", 4483362458)
StatusTab:CreateSection("Auto-Targeting Status")

local StatusLabel    = StatusTab:CreateLabel("⏸ Auto-targeting is OFF")
local TargetsLabel   = StatusTab:CreateLabel("🎯 Selected Brainrots: None")
local MutationsLabel = StatusTab:CreateLabel("✨ Selected Mutations: None")
local TrackingLabel  = StatusTab:CreateLabel("🔎 Tracking 0 live targets")
local LastShotLabel  = StatusTab:CreateLabel("🔫 Last shot: —")

StatusTab:CreateDivider()

StatusTab:CreateToggle({
    Name     = "🔴 / 🟢  Auto-Targeting (ON / OFF)",
    Default  = false,
    Callback = function(val)
        cfg.enabled = val
    end,
})

-- TAB 2: BRAINROT SELECTION
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

-- TAB 3: MUTATION SELECTION
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

-- TAB 4: BALLOON SKIN TOKENS
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

task.spawn(function()
    local lastCount = -1
    while task.wait(1) do
        if balloonHitsTotal ~= lastCount then
            lastCount = balloonHitsTotal
            BalloonHitsLabel:Set("🎯 Tokens earned this session: " .. lastCount)
        end
    end
end)

-- TAB 5: AUTO-COLLECT MONEY
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
        collectTimer = 0
        CollectStatusLabel:Set(val and "🟢 Auto-collect: ON" or "⏸ Auto-collect: OFF")
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
        collectTimer = 0
    end,
})

task.spawn(function()
    local lastFires = -1
    while task.wait(0.5) do
        if lastGoldPatch > 0 then
            CollectGoldLabel:Set("🪙 Last gold reading: " .. fmt(lastGoldPatch))
        end
        if collectTotal ~= lastFires then
            lastFires = collectTotal
            CollectCountLabel:Set("📦 Collect fires this session: " .. collectTotal)
        end
        if cfg.collectEnabled then
            local remaining = cfg.collectInterval - collectTimer
            CollectTimerLabel:Set("⏱ Next collect in: " .. remaining .. "s")
        else
            CollectTimerLabel:Set("⏱ Next collect in: —")
        end
    end
end)

-- TAB 6: AUTO DRONE BEST
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
            pcall(function() EquipBestRE:FireServer() end)
            _droneBestFires = _droneBestFires + 1
            DroneBestCountLabel:Set("📡 Equip fires this session: " .. _droneBestFires)
        end
    end,
})

task.spawn(function()
    local last = -1
    while task.wait(1) do
        if _droneBestFires ~= last then
            last = _droneBestFires
            DroneBestCountLabel:Set("📡 Equip fires this session: " .. _droneBestFires)
        end
    end
end)

-- TAB 7: AUTO DRONE SHIELD
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

-- TAB 8: SKIP SNIPER ANIMATION
local SkipAnimTab = Window:CreateTab("⚡ Skip Anim", 4483362458)
SkipAnimTab:CreateSection("Skip Sniper Shoot Animation")
SkipAnimTab:CreateLabel("ScopeState(true/false) is now always sent around each attack.")
SkipAnimTab:CreateLabel("This toggle collapses the scope animation immediately for faster cycling.")
SkipAnimTab:CreateDivider()

local SkipAnimStatusLabel = SkipAnimTab:CreateLabel("⚡ Skip Anim: ON (always active for reliability)")

SkipAnimTab:CreateToggle({
    Name     = "🔴 / 🟢  Skip Sniper Animation (ON / OFF)",
    Default  = false,
    Callback = function(val)
        cfg.skipAnimEnabled = val
        SkipAnimStatusLabel:Set(val and "🟢 Skip Anim: ON — faster cycle enabled" or "⏸ Skip Anim: OFF")
    end,
})

-- TAB 9: INFO
local InfoTab = Window:CreateTab("ℹ️ Info", 4483362458)
InfoTab:CreateSection("How It Works")
InfoTab:CreateLabel("1. Select Brainrots and/or Mutations in their tabs")
InfoTab:CreateLabel("2. Leave a filter empty to match ANY value for that field")
InfoTab:CreateLabel("3. Enable Auto-Targeting on the Status tab")
InfoTab:CreateLabel("4. Scanner fires every 0.5 s looking for a match")
InfoTab:CreateLabel("5. Teleports above target (10 studs) → waits 0.35 s for server sync")
InfoTab:CreateLabel("6. ScopeState(true) → BrainrotAttack(uid) → ScopeState(false)")
InfoTab:CreateLabel("7. DroneCapture(uid, spaceId) → teleport back to plot")
InfoTab:CreateLabel("8. Each target UID is only processed once per spawn")
InfoTab:CreateDivider()
InfoTab:CreateSection("Attack Pipeline Fix")
InfoTab:CreateLabel("OLD: 80-stud TP + 0.15s wait + cached position → often rejected")
InfoTab:CreateLabel("NEW: 10-stud TP + 0.35s wait + live HRP position → passes server check")
InfoTab:CreateLabel("spaceId now always read fresh from model attribute at shot time")
InfoTab:CreateLabel("ScopeState(true) always fires before attack (server may require it)")
InfoTab:CreateDivider()
InfoTab:CreateSection("Target Detection Sources")
InfoTab:CreateLabel("PRIMARY: GameFolder.BrainrotModels workspace scan (every 1s)")
InfoTab:CreateLabel("SECONDARY: RE/BrainrotMove events (real-time updates)")
InfoTab:CreateLabel("TERTIARY: ChildAdded on BrainrotModels (instant new spawn detection)")
InfoTab:CreateDivider()
InfoTab:CreateSection("Mutation Multipliers")
InfoTab:CreateLabel("Normal x1  •  Gold x1.5  •  Diamond x2")
InfoTab:CreateLabel("Emerald x3  •  Void x4  •  Rainbow x10")

-- ============================================================
-- DRONE STATE FEEDBACK
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
-- ============================================================

task.spawn(function()
    while task.wait(0.5) do
        StatusLabel:Set(cfg.enabled
            and "🟢 Auto-targeting is ON — scanning..."
            or  "⏸ Auto-targeting is OFF")

        TargetsLabel:Set("🎯 Selected Brainrots: "
            .. selectedNamesStr(cfg.selectedBrainrotIds, idToName))

        MutationsLabel:Set("✨ Selected Mutations: "
            .. selectedNamesStr(cfg.selectedMutationIds, mutIdToName))

        local totalCount = 0
        local matchCount = 0
        local hasAnyBrainrot = next(cfg.selectedBrainrotIds) ~= nil
        local hasAnyMutation  = next(cfg.selectedMutationIds) ~= nil
        for uid, t in pairs(liveTargets) do
            totalCount = totalCount + 1
            if not shotTargets[uid] then
                local bMatch = not hasAnyBrainrot or cfg.selectedBrainrotIds[t.id]
                local mMatch = not hasAnyMutation  or cfg.selectedMutationIds[t.mutation]
                if bMatch and mMatch then matchCount = matchCount + 1 end
            end
        end
        TrackingLabel:Set(string.format("🔎 %d brainrots visible | %d match filter (not yet shot)", totalCount, matchCount))

        if math.floor(tick()) % 5 == 0 then
            local names = {}
            for _, t in pairs(liveTargets) do
                local n = idToName[t.id] or ("id="..tostring(t.id))
                local m = mutIdToName[t.mutation] or tostring(t.mutation)
                table.insert(names, n.."["..m.."]")
            end
            table.sort(names)
            print(string.format("[BrainrotSniper] [DEBUG] Live targets (%d): %s", totalCount, table.concat(names, ", ")))
        end
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
