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

local AttackRE      = net:FindFirstChild("RE/BrainrotAttack")
local DroneCapRF    = net:FindFirstChild("RF/DroneCapture")
local DroneStateRE  = net:FindFirstChild("RE/DroneState")
local MoveRE        = net:FindFirstChild("RE/BrainrotMove")

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

    -- 2. Fire attack RE
    if AttackRE then
        AttackRE:FireServer(target.uid)
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
-- RAYFIELD UI
-- ============================================================

local Window = Rayfield:CreateWindow({
    Name            = "🎯 Brainrot Sniper v2",
    LoadingTitle    = "Brainrot Sniper Script",
    LoadingSubtitle = "Configurable Target + Mutation Filter",
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
-- TAB 4: INFO
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
