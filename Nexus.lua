-- ============================================================
--  AUTO EGG COLLECTOR v10  |  Ride A Pet
--  Features:
--    ✅ Best Available Pet selection (fastest rideable pet in plot)
--    ✅ Egg Selector UI (pick specific egg type or "ALL - Auto Best")
--    ✅ Ground-only pathfinding (no flying)
--    ✅ Anti-stuck with sideways dodge
--    ✅ Dynamic travel timeout based on distance
--    ✅ Full-map egg search (no distance cap)
--    ✅ Blacklist unreachable eggs
--    ✅ Prompt hold support
-- ============================================================

-- ▸ CLEANUP previous instance
if _G.AEC_Running then _G.AEC_Running = false end
if _G.AEC_GUI then pcall(function() _G.AEC_GUI:Destroy() end); _G.AEC_GUI = nil end
task.wait(0.4)

-- ▸ SERVICES
local Players  = game:GetService("Players")
local RS       = game:GetService("ReplicatedStorage")
local PPS      = game:GetService("ProximityPromptService")
local PFS      = game:GetService("PathfindingService")
local RunSvc   = game:GetService("RunService")

-- ▸ PLAYER
local lp   = Players.LocalPlayer
local char  = lp.Character or lp.CharacterAdded:Wait()
local hrp   = char:WaitForChild("HumanoidRootPart")
local hum   = char:WaitForChild("Humanoid")

lp.CharacterAdded:Connect(function(c)
    char = c
    hrp  = c:WaitForChild("HumanoidRootPart")
    hum  = c:WaitForChild("Humanoid")
end)

-- ▸ RARITY ORDERING (higher = rarer = better)
local RARITY_ORDER = {
    ["Common"]    = 1,
    ["Rare"]      = 2,
    ["Epic"]      = 3,
    ["Legendary"] = 4,
    ["Mythic"]    = 5,
    ["Divine"]    = 6,
    ["Ethereal"]  = 7,
}

-- ▸ CONFIG
local COLLECT_RANGE  = 14
local RIDE_RANGE     = 7
local LOOP_DELAY     = 1.5
local STUCK_THRESHOLD = 3    -- seconds without movement = stuck
local STUCK_DISTANCE  = 2    -- studs movement needed to not be "stuck"

-- ▸ STATE
_G.AEC_Running = true
local collected  = 0
local blacklist  = {}
local selectedEggIndex = 1   -- 1 = "ALL (Auto Best)"

-- ▸ EGG DATA from game
local eggDataModule = nil
local eggDataCache  = nil
do
    local gd = RS:FindFirstChild("GameData")
    if gd then
        local em = gd:FindFirstChild("Eggs")
        if em and em:IsA("ModuleScript") then
            local ok, data = pcall(require, em)
            if ok then eggDataCache = data end
        end
    end
end

local function getEggRarity(eggName)
    if eggDataCache and eggDataCache[eggName] then
        return eggDataCache[eggName].Rarity or "Common"
    end
    return "Common"
end

local function getRarityValue(rarity)
    return RARITY_ORDER[rarity] or 0
end

-- ▸ BUILD EGG TYPE LIST for selector
local function buildEggTypeList()
    local types = {"ALL (Auto Best)"}
    if eggDataCache then
        local sorted = {}
        for name, info in pairs(eggDataCache) do
            table.insert(sorted, {name = name, rarity = info.Rarity or "Common", luck = info.Luck or 0})
        end
        table.sort(sorted, function(a, b)
            local ra = getRarityValue(a.rarity)
            local rb = getRarityValue(b.rarity)
            if ra ~= rb then return ra > rb end
            return (a.luck or 0) > (b.luck or 0)
        end)
        for _, e in ipairs(sorted) do
            table.insert(types, e.name .. " [" .. e.rarity .. "]")
        end
    end
    return types
end

local eggTypeList = buildEggTypeList()

-- ============================================================
--  FIND PLAYER'S PLOT
-- ============================================================
local function findPlayerPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in pairs(plots:GetChildren()) do
        local df = plot:FindFirstChild("Data")
        if df then
            local ov = df:FindFirstChild("Owner")
            if ov and ov:IsA("ObjectValue") and ov.Value == lp then
                return plot
            end
        end
    end
    return nil
end

-- ============================================================
--  GET BEST AVAILABLE PET (sorted by speed, must have RidePrompt)
-- ============================================================
local function getBestAvailablePet()
    local plot = findPlayerPlot()
    if not plot then return nil, nil, "❌ No plot found" end

    local petsFolder = plot:FindFirstChild("Pets")
    if not petsFolder then return nil, nil, "❌ No Pets folder" end

    local pets = {}
    for _, petModel in pairs(petsFolder:GetChildren()) do
        if petModel:IsA("Model") then
            local speed = 0
            local data = petModel:FindFirstChild("Data")
            if data then
                local spd = data:FindFirstChild("Speed")
                if spd then speed = spd.Value end
            end

            -- Check for ride prompt
            local ridePrompt = nil
            for _, desc in pairs(petModel:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and desc.Name == "RidePrompt" then
                    ridePrompt = desc
                    break
                end
            end

            if ridePrompt and ridePrompt.Enabled then
                table.insert(pets, {
                    model  = petModel,
                    name   = petModel.Name,
                    speed  = speed,
                    prompt = ridePrompt,
                })
            end
        end
    end

    if #pets == 0 then return nil, nil, "❌ No rideable pets" end

    -- Sort by speed descending
    table.sort(pets, function(a, b) return a.speed > b.speed end)

    local best = pets[1]
    return best, pets, string.format("🐾 %s (Speed: %s)", best.name, tostring(best.speed))
end

-- ============================================================
--  MOUNT PET
-- ============================================================
local function mountPet(petInfo)
    if not petInfo or not petInfo.model or not petInfo.model.Parent then
        return false
    end

    -- Pets use RootPart or PrimaryPart (not HumanoidRootPart)
    local petRoot = petInfo.model.PrimaryPart
        or petInfo.model:FindFirstChild("RootPart")
        or petInfo.model:FindFirstChild("HumanoidRootPart")
    if not petRoot then return false end

    -- RidePrompt maxActivationDistance is ~25 studs, use 20 as safe range
    local mountRange = 20

    -- Walk to pet
    local startTime = tick()
    while _G.AEC_Running and (hrp.Position - petRoot.Position).Magnitude > mountRange do
        hum:MoveTo(petRoot.Position)
        task.wait(0.2)
        if tick() - startTime > 15 then return false end
    end
    hum:MoveTo(hrp.Position) -- stop

    -- Trigger ride prompt
    local prompt = petInfo.prompt
    if prompt and prompt.Enabled then
        -- Fire proximity prompt
        if fireproximityprompt then
            fireproximityprompt(prompt, 1)
            task.wait(math.max(prompt.HoldDuration or 0, 0.3))
            fireproximityprompt(prompt, 0)
        else
            prompt:InputHoldBegin()
            task.wait(math.max(prompt.HoldDuration or 0, 0.3))
            prompt:InputHoldEnd()
        end
        task.wait(0.5)
    end

    return true
end

-- ============================================================
--  FIND TARGET EGG
-- ============================================================
local function getTargetEgg(petSpeed)
    local renderedEggs = workspace:FindFirstChild("RenderedEggs")
    if not renderedEggs then return nil end

    local candidates = {}
    local selectedType = eggTypeList[selectedEggIndex]
    local isAutoMode = (selectedEggIndex == 1)

    for _, egg in pairs(renderedEggs:GetChildren()) do
        if egg:IsA("Model") and not blacklist[egg] then
            -- Check if egg has a pickup prompt
            local prompt = nil
            for _, desc in pairs(egg:GetDescendants()) do
                if desc:IsA("ProximityPrompt") and desc.Name == "Pickup" then
                    prompt = desc
                    break
                end
            end

            if prompt and prompt.Enabled then
                local eggPos = egg:GetPivot().Position
                local dist = (hrp.Position - eggPos).Magnitude
                local rarity = getEggRarity(egg.Name)
                local rarityVal = getRarityValue(rarity)

                if isAutoMode then
                    table.insert(candidates, {
                        model    = egg,
                        name     = egg.Name,
                        prompt   = prompt,
                        dist     = dist,
                        rarity   = rarity,
                        rarityVal = rarityVal,
                    })
                else
                    -- Match specific type (strip rarity label from selection)
                    local targetName = selectedType:match("^(.+) %[") or selectedType
                    if egg.Name == targetName then
                        table.insert(candidates, {
                            model    = egg,
                            name     = egg.Name,
                            prompt   = prompt,
                            dist     = dist,
                            rarity   = rarity,
                            rarityVal = rarityVal,
                        })
                    end
                end
            end
        end
    end

    if #candidates == 0 then return nil end

    -- Sort: Auto mode = by rarity desc then distance asc; specific = by distance asc
    if isAutoMode then
        table.sort(candidates, function(a, b)
            if a.rarityVal ~= b.rarityVal then return a.rarityVal > b.rarityVal end
            return a.dist < b.dist
        end)
    else
        table.sort(candidates, function(a, b) return a.dist < b.dist end)
    end

    return candidates[1]
end

-- ============================================================
--  PATHFINDING WALK (ground-only, anti-stuck)
-- ============================================================
local function walkToTarget(targetPos, timeoutOverride)
    local initialDist = (hrp.Position - targetPos).Magnitude
    local travelLimit = timeoutOverride or math.clamp(initialDist / 35 + 20, 30, 90)

    local path = PFS:CreatePath({
        AgentRadius    = 3,
        AgentHeight    = 7,
        AgentCanJump   = false,
        WaypointSpacing = 12,
    })

    local ok, err = pcall(function()
        path:ComputeAsync(hrp.Position, targetPos)
    end)

    if not ok or path.Status ~= Enum.PathStatus.Success then
        -- Fallback: direct MoveTo
        local startT = tick()
        local lastPos = hrp.Position
        local lastMoveCheck = tick()

        while _G.AEC_Running and (hrp.Position - targetPos).Magnitude > COLLECT_RANGE do
            hum:MoveTo(targetPos)
            task.wait(0.3)

            -- Stuck detection
            if tick() - lastMoveCheck > STUCK_THRESHOLD then
                if (hrp.Position - lastPos).Magnitude < STUCK_DISTANCE then
                    -- Dodge sideways
                    local dodge = hrp.CFrame.RightVector * 15
                    hum:MoveTo(hrp.Position + dodge)
                    task.wait(0.8)
                end
                lastPos = hrp.Position
                lastMoveCheck = tick()
            end

            if tick() - startT > travelLimit then return false end
        end
        return (hrp.Position - targetPos).Magnitude <= COLLECT_RANGE
    end

    local waypoints = path:GetWaypoints()
    local startT = tick()
    local lastPos = hrp.Position
    local lastMoveCheck = tick()

    for i, wp in ipairs(waypoints) do
        if not _G.AEC_Running then return false end

        hum:MoveTo(wp.Position)

        local wpStart = tick()
        while _G.AEC_Running and (hrp.Position - wp.Position).Magnitude > 4 do
            task.wait(0.15)

            -- Check if we're close enough to final target already
            if (hrp.Position - targetPos).Magnitude <= COLLECT_RANGE then
                return true
            end

            -- Stuck detection
            if tick() - lastMoveCheck > STUCK_THRESHOLD then
                if (hrp.Position - lastPos).Magnitude < STUCK_DISTANCE then
                    local dodge = hrp.CFrame.RightVector * 15
                    hum:MoveTo(hrp.Position + dodge)
                    task.wait(0.8)
                    hum:MoveTo(wp.Position)
                end
                lastPos = hrp.Position
                lastMoveCheck = tick()
            end

            if tick() - wpStart > 8 then break end  -- skip stuck waypoint
            if tick() - startT > travelLimit then return false end
        end
    end

    return (hrp.Position - targetPos).Magnitude <= COLLECT_RANGE
end

-- ============================================================
--  TRIGGER PICKUP PROMPT
-- ============================================================
local function triggerPickup(prompt)
    if not prompt or not prompt.Parent then return false end

    local holdTime = math.max(prompt.HoldDuration or 0, 0.25)

    if fireproximityprompt then
        fireproximityprompt(prompt, 1)
        task.wait(holdTime + 0.1)
        fireproximityprompt(prompt, 0)
    else
        prompt:InputHoldBegin()
        task.wait(holdTime + 0.1)
        prompt:InputHoldEnd()
    end

    task.wait(0.3)
    return true
end

-- ============================================================
--  GUI
-- ============================================================
local gui = Instance.new("ScreenGui")
gui.Name = "AEC_GUI_v10"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = lp:WaitForChild("PlayerGui")
_G.AEC_GUI = gui

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 320, 0, 210)
frame.Position = UDim2.new(0, 10, 0.5, -105)
frame.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -10, 0, 24)
title.Position = UDim2.new(0, 5, 0, 5)
title.BackgroundTransparency = 1
title.Text = "🥚 Auto Egg Collector v10"
title.TextColor3 = Color3.fromRGB(255, 220, 80)
title.Font = Enum.Font.GothamBold
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = frame

-- Close button
local btnClose = Instance.new("TextButton")
btnClose.Size = UDim2.new(0, 24, 0, 24)
btnClose.Position = UDim2.new(1, -29, 0, 5)
btnClose.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
btnClose.Text = "✕"
btnClose.TextColor3 = Color3.new(1, 1, 1)
btnClose.Font = Enum.Font.GothamBold
btnClose.TextSize = 12
btnClose.Parent = frame
local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 6); cc.Parent = btnClose
btnClose.MouseButton1Click:Connect(function()
    _G.AEC_Running = false
    task.wait(0.5)
    if _G.AEC_GUI then _G.AEC_GUI:Destroy(); _G.AEC_GUI = nil end
end)

-- Egg selector row
local selectorFrame = Instance.new("Frame")
selectorFrame.Size = UDim2.new(1, -10, 0, 26)
selectorFrame.Position = UDim2.new(0, 5, 0, 32)
selectorFrame.BackgroundTransparency = 1
selectorFrame.Parent = frame

local btnPrev = Instance.new("TextButton")
btnPrev.Size = UDim2.new(0, 28, 1, 0)
btnPrev.Position = UDim2.new(0, 0, 0, 0)
btnPrev.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
btnPrev.Text = "◀"
btnPrev.TextColor3 = Color3.new(1, 1, 1)
btnPrev.Font = Enum.Font.GothamBold
btnPrev.TextSize = 14
btnPrev.Parent = selectorFrame
local pc = Instance.new("UICorner"); pc.CornerRadius = UDim.new(0, 6); pc.Parent = btnPrev

local lblChoice = Instance.new("TextLabel")
lblChoice.Size = UDim2.new(1, -60, 1, 0)
lblChoice.Position = UDim2.new(0, 30, 0, 0)
lblChoice.BackgroundColor3 = Color3.fromRGB(40, 40, 55)
lblChoice.Text = eggTypeList[selectedEggIndex]
lblChoice.TextColor3 = Color3.fromRGB(180, 255, 180)
lblChoice.Font = Enum.Font.Gotham
lblChoice.TextSize = 11
lblChoice.TextTruncate = Enum.TextTruncate.AtEnd
lblChoice.Parent = selectorFrame
local lcc = Instance.new("UICorner"); lcc.CornerRadius = UDim.new(0, 4); lcc.Parent = lblChoice

local btnNext = Instance.new("TextButton")
btnNext.Size = UDim2.new(0, 28, 1, 0)
btnNext.Position = UDim2.new(1, -28, 0, 0)
btnNext.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
btnNext.Text = "▶"
btnNext.TextColor3 = Color3.new(1, 1, 1)
btnNext.Font = Enum.Font.GothamBold
btnNext.TextSize = 14
btnNext.Parent = selectorFrame
local nc = Instance.new("UICorner"); nc.CornerRadius = UDim.new(0, 6); nc.Parent = btnNext

btnPrev.MouseButton1Click:Connect(function()
    selectedEggIndex = selectedEggIndex - 1
    if selectedEggIndex < 1 then selectedEggIndex = #eggTypeList end
    lblChoice.Text = eggTypeList[selectedEggIndex]
    blacklist = {}
end)

btnNext.MouseButton1Click:Connect(function()
    selectedEggIndex = selectedEggIndex + 1
    if selectedEggIndex > #eggTypeList then selectedEggIndex = 1 end
    lblChoice.Text = eggTypeList[selectedEggIndex]
    blacklist = {}
end)

-- Status labels
local function makeLabel(yPos, defaultText)
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -10, 0, 18)
    lbl.Position = UDim2.new(0, 5, 0, yPos)
    lbl.BackgroundTransparency = 1
    lbl.Text = defaultText
    lbl.TextColor3 = Color3.fromRGB(200, 200, 220)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextTruncate = Enum.TextTruncate.AtEnd
    lbl.Parent = frame
    return lbl
end

local lblPet    = makeLabel(65, "🐾 Pet: scanning...")
local lblTarget = makeLabel(85, "🎯 Target: none")
local lblStatus = makeLabel(105, "📡 Status: initializing")
local lblDist   = makeLabel(125, "📏 Distance: --")
local lblCount  = makeLabel(145, "📦 Collected: 0")
local lblBlack  = makeLabel(165, "🚫 Blacklisted: 0")

-- Pause / Resume button
local btnPause = Instance.new("TextButton")
btnPause.Size = UDim2.new(1, -10, 0, 26)
btnPause.Position = UDim2.new(0, 5, 0, 186)
btnPause.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
btnPause.Text = "⏸ PAUSE"
btnPause.TextColor3 = Color3.new(1, 1, 1)
btnPause.Font = Enum.Font.GothamBold
btnPause.TextSize = 12
btnPause.Parent = frame
local bpc = Instance.new("UICorner"); bpc.CornerRadius = UDim.new(0, 6); bpc.Parent = btnPause

local paused = false
btnPause.MouseButton1Click:Connect(function()
    paused = not paused
    if paused then
        btnPause.Text = "▶ RESUME"
        btnPause.BackgroundColor3 = Color3.fromRGB(180, 120, 30)
        lblStatus.Text = "📡 Status: ⏸ PAUSED"
    else
        btnPause.Text = "⏸ PAUSE"
        btnPause.BackgroundColor3 = Color3.fromRGB(50, 120, 50)
    end
end)

-- ============================================================
--  MAIN LOOP
-- ============================================================
task.spawn(function()
    task.wait(1)

    while _G.AEC_Running do
        -- Wait if paused
        while paused and _G.AEC_Running do task.wait(0.5) end
        if not _G.AEC_Running then break end

        lblStatus.Text = "📡 Status: 🔍 Finding best pet..."

        -- ▸ STEP 1: Find best available pet
        local bestPet, allPets, petMsg = getBestAvailablePet()
        lblPet.Text = "🐾 Pet: " .. petMsg

        if not bestPet then
            lblStatus.Text = "📡 Status: " .. petMsg
            task.wait(5)
            continue
        end

        -- ▸ STEP 2: Mount the pet
        lblStatus.Text = "📡 Status: 🚶 Walking to pet..."
        local mounted = mountPet(bestPet)
        if not mounted then
            lblStatus.Text = "📡 Status: ⚠️ Failed to mount pet, retrying..."
            task.wait(3)
            continue
        end
        lblStatus.Text = "📡 Status: 🐎 Mounted! Finding eggs..."
        task.wait(0.5)

        -- ▸ STEP 3: Find and collect eggs in a loop while mounted
        local eggLoopCount = 0
        local maxEggLoop = 20  -- re-evaluate pet after N eggs

        while _G.AEC_Running and eggLoopCount < maxEggLoop do
            while paused and _G.AEC_Running do task.wait(0.5) end
            if not _G.AEC_Running then break end

            local targetEgg = getTargetEgg(bestPet.speed)
            lblBlack.Text = "🚫 Blacklisted: " .. tostring(#(function() local c=0; for _ in pairs(blacklist) do c=c+1 end; return c end)()) .. " eggs"

            if not targetEgg then
                lblTarget.Text = "🎯 Target: none found"
                lblDist.Text = "📏 Distance: --"
                lblStatus.Text = "📡 Status: 🔄 No eggs available, waiting..."
                -- Clear blacklist periodically
                blacklist = {}
                task.wait(5)
                eggLoopCount = eggLoopCount + 1
                continue
            end

            lblTarget.Text = "🎯 Target: " .. targetEgg.name .. " [" .. targetEgg.rarity .. "]"
            lblDist.Text = string.format("📏 Distance: %.0f studs", targetEgg.dist)
            lblStatus.Text = "📡 Status: 🚶 Walking to " .. targetEgg.name .. "..."

            -- Walk to egg
            local eggPos = targetEgg.model:GetPivot().Position
            local reached = walkToTarget(eggPos)

            if not reached then
                lblStatus.Text = "📡 Status: ⚠️ Couldn't reach, blacklisting"
                blacklist[targetEgg.model] = true
                task.wait(1)
                eggLoopCount = eggLoopCount + 1
                continue
            end

            -- Try to collect
            lblStatus.Text = "📡 Status: 🤚 Picking up " .. targetEgg.name .. "..."

            -- Check prompt still exists
            if targetEgg.prompt and targetEgg.prompt.Parent then
                triggerPickup(targetEgg.prompt)

                -- Verify it was collected (egg should be destroyed)
                task.wait(0.5)
                if not targetEgg.model.Parent then
                    collected = collected + 1
                    lblCount.Text = "📦 Collected: " .. tostring(collected)
                    lblStatus.Text = "📡 Status: ✅ Collected " .. targetEgg.name .. "!"
                else
                    -- Still there, try again
                    triggerPickup(targetEgg.prompt)
                    task.wait(0.5)
                    if not targetEgg.model.Parent then
                        collected = collected + 1
                        lblCount.Text = "📦 Collected: " .. tostring(collected)
                    else
                        blacklist[targetEgg.model] = true
                        lblStatus.Text = "📡 Status: ⚠️ Failed to pick up, blacklisted"
                    end
                end
            else
                -- Someone else grabbed it
                lblStatus.Text = "📡 Status: 🏃 Egg already taken"
            end

            eggLoopCount = eggLoopCount + 1
            task.wait(LOOP_DELAY)
        end

        task.wait(1)
    end

    -- Cleanup
    lblStatus.Text = "📡 Status: ⏹ Stopped"
end)

print("🥚 Auto Egg Collector v10 started!")
print("🐾 Finding best pet in your plot...")
