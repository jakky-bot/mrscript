-- ============================================================
-- BRAINROT SNIPER v2 - Configurable Target + Mutation Filter
-- Select specific Brainrots and Mutations, auto-shoot on match
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

local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")

local lp = Players.LocalPlayer
local net = RS.Shared.Packages.Net

local AttackRE      = net:FindFirstChild("RE/BrainrotAttack")
local DroneCapRF    = net:FindFirstChild("RF/DroneCapture")
local DroneCreateRE = net:FindFirstChild("RE/DroneCreate")
local DroneStateRE  = net:FindFirstChild("RE/DroneState")
local MoveRE        = net:FindFirstChild("RE/BrainrotMove")

-- ============================================================
-- LOAD CONFIGS
-- ============================================================

local brainrotCfgOk, BrainrotConfig =
    pcall(require, RS.Config.Brainrot.BrainrotConfig)

local mutCfgOk, MutationConfig =
    pcall(require, RS.Config.Brainrot.BrainrotMutationConfig)

local idToCash    = {}  -- brainrotId  -> base cash
local idToName    = {}  -- brainrotId  -> display name
local allBrainrots = {} -- sorted list of {id, name, cash}

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
local allMutations  = {}  -- sorted list of {id, name, mult}

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
local shotTargets = {} -- uid -> true  (dedup guard; cleared on destroy)

if MoveRE then
    MoveRE.OnClientEvent:Connect(function(data)
        if type(data) ~= "table" then return end
        for _, entry in pairs(data) do
            if type(entry) == "table" and entry.uid then
                if entry.destroy then
                    liveTargets[entry.uid] = nil
                    shotTargets[entry.uid] = nil
                else
                    local existing = liveTargets[entry.uid] or {}
                    existing.uid      = entry.uid
                    existing.spaceId  = entry.spaceId  or existing.spaceId
                    existing.id       = entry.id       or existing.id
                    existing.mutation = entry.mutation or existing.mutation or 1
                    if entry.position then existing.position = entry.position end
                    liveTargets[entry.uid] = existing
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
    if mName ~= "" and mName ~= "Normal" then
        return mName .. " " .. bName
    end
    return bName
end

-- Build comma-separated name list from a set {id -> true}
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
-- SHOOT + COLLECT
-- ============================================================

local function shootAndCollect(target)
    local displayName = getDisplayName(target.id, target.mutation)
    local base        = idToCash[target.id] or 0
    local mult        = mutMultiplier[target.mutation] or 1
    local val         = base * mult
    local valStr      = fmt(val)

    print(string.format(
        "[BrainrotSniper] Shooting > %s (uid=%s) val=$%s/s spaceId=%s",
        displayName, target.uid, valStr, tostring(target.spaceId)
    ))

    local char = lp.Character
    local hrp  = char and char:FindFirstChild("HumanoidRootPart")
    if hrp and target.position then
        hrp.CFrame = CFrame.new(target.position + Vector3.new(0, 80, 0))
        task.wait(0.15)
    end

    if AttackRE then
        AttackRE:FireServer(target.uid)
        print("[BrainrotSniper] BrainrotAttack fired uid=" .. target.uid)
    else
        warn("[BrainrotSniper] AttackRE not found")
    end

    task.wait(0.5)

    if DroneCapRF then
        task.wait(0.2)
        pcall(function() DroneCapRF:InvokeServer(target.uid, target.spaceId) end)
    end

    if hrp then
        local ppp = workspace:FindFirstChild("GameFolder")
            and workspace.GameFolder:FindFirstChild("PlayerPlacePos")
        if ppp then
            local firstPos = ppp:FindFirstChildWhichIsA("BasePart")
            if firstPos then
                task.wait(0.3)
                hrp.CFrame = CFrame.new(firstPos.Position + Vector3.new(0, 5, 0))
            end
        end
    end
end

-- ============================================================
-- FIND MATCHING TARGET
-- ============================================================

local function findMatchingTarget()
    local hasAnyBrainrot = next(cfg.selectedBrainrotIds) ~= nil
    local hasAnyMutation  = next(cfg.selectedMutationIds) ~= nil
    -- Require at least one filter to be set before shooting anything
    if not hasAnyBrainrot and not hasAnyMutation then return nil end

    for uid, t in pairs(liveTargets) do
        if shotTargets[uid] then continue end
        local brainrotMatch = not hasAnyBrainrot or cfg.selectedBrainrotIds[t.id]
        local mutationMatch  = not hasAnyMutation  or cfg.selectedMutationIds[t.mutation]
        if brainrotMatch and mutationMatch then
            return t
        end
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
-- TAB 1: STATUS  (labels are updated by the refresh loop below)
-- ----------------------------------------------------------------
local StatusTab = Window:CreateTab("📊 Status", 4483362458)
StatusTab:CreateSection("Auto-Targeting Status")

local StatusLabel    = StatusTab:CreateLabel("⏸ Auto-targeting is OFF")
local TargetsLabel   = StatusTab:CreateLabel("🎯 Selected Brainrots: None")
local MutationsLabel = StatusTab:CreateLabel("✨ Selected Mutations: None")
local TrackingLabel  = StatusTab:CreateLabel("🔎 Tracking 0 live targets")
local LastShotLabel  = StatusTab:CreateLabel("🔫 Last shot: —")

StatusTab:CreateDivider()

StatusTab:CreateToggle({
    Name    = "🔴 / 🟢  Auto-Targeting (ON / OFF)",
    Default = false,
    Callback = function(val)
        -- ONLY update cfg; the refresh loop handles the label
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
    local bId   = b.id
    local label = b.name .. "  [$" .. fmt(b.cash) .. "/s]"
    BrainrotTab:CreateToggle({
        Name     = label,
        Default  = false,
        Callback = function(val)
            -- ONLY update cfg; the refresh loop handles the label
            if val then
                cfg.selectedBrainrotIds[bId] = true
            else
                cfg.selectedBrainrotIds[bId] = nil
            end
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
    local mId   = m.id
    local label = m.name .. "  [x" .. tostring(m.mult) .. "]"
    MutationTab:CreateToggle({
        Name     = label,
        Default  = false,
        Callback = function(val)
            -- ONLY update cfg; the refresh loop handles the label
            if val then
                cfg.selectedMutationIds[mId] = true
            else
                cfg.selectedMutationIds[mId] = nil
            end
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
InfoTab:CreateLabel("4. Scanner checks live targets every 0.5 s")
InfoTab:CreateLabel("5. On match: teleports above target, fires attack, drone collects")
InfoTab:CreateLabel("6. Each unique target is only shot once per appearance")
InfoTab:CreateDivider()
InfoTab:CreateSection("Mutation Multipliers")
InfoTab:CreateLabel("Normal x1 • Gold x1.5 • Diamond x2")
InfoTab:CreateLabel("Emerald x3 • Void x4 • Rainbow x10")

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
        if type(data) ~= "table" then return end
        if data.owner ~= lp.UserId then return end
        local msg = droneStates[data.state] or ("Drone state " .. tostring(data.state))
        -- Write directly; the refresh loop will not overwrite drone status
        -- (it only writes when NOT shooting)
        StatusLabel.Text = msg
    end)
end

-- ============================================================
-- STATUS REFRESH LOOP  — single writer for all Status labels
-- Runs every 0.5 s so updates are near-instant after a toggle
-- ============================================================

task.spawn(function()
    while task.wait(0.5) do
        -- ON/OFF line
        if cfg.enabled then
            StatusLabel.Text = "🟢 Auto-targeting is ON — scanning..."
        else
            StatusLabel.Text = "⏸ Auto-targeting is OFF"
        end

        -- Selected Brainrots
        TargetsLabel.Text = "🎯 Selected Brainrots: "
            .. selectedNamesStr(cfg.selectedBrainrotIds, idToName)

        -- Selected Mutations
        MutationsLabel.Text = "✨ Selected Mutations: "
            .. selectedNamesStr(cfg.selectedMutationIds, mutIdToName)

        -- Live target count
        local count = 0
        for _ in pairs(liveTargets) do count = count + 1 end
        TrackingLabel.Text = string.format("🔎 Tracking %d live targets", count)
    end
end)

-- ============================================================
-- MAIN AUTO-SCAN LOOP  (every 0.5 s)
-- ============================================================

task.spawn(function()
    local isShooting = false

    while task.wait(0.5) do
        if not cfg.enabled then continue end
        if isShooting then continue end

        local match = findMatchingTarget()
        if not match then continue end

        shotTargets[match.uid] = true
        isShooting = true

        local displayName = getDisplayName(match.id, match.mutation)
        local base  = idToCash[match.id] or 0
        local mult  = mutMultiplier[match.mutation] or 1
        local val   = base * mult
        LastShotLabel.Text = "🔫 Last shot: " .. displayName .. " ($" .. fmt(val) .. "/s)"

        task.spawn(function()
            local ok, err = pcall(shootAndCollect, match)
            if not ok then
                warn("[BrainrotSniper] shootAndCollect error: " .. tostring(err))
            end
            isShooting = false
        end)
    end
end)

print("[BrainrotSniper v2] Script loaded successfully!")
