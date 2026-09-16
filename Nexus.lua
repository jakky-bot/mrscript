-- ============================================================
--  AUTO EGG COLLECTOR v9 (Full-Map Reach & Dynamic Travel)
--  Ride A Pet
-- ============================================================

if _G.AEC_Running then _G.AEC_Running = false end
if _G.AEC_GUI then _G.AEC_GUI:Destroy(); _G.AEC_GUI = nil end
task.wait(0.3)

local Players = game:GetService("Players")
local RS      = game:GetService("ReplicatedStorage")
local PPS     = game:GetService("ProximityPromptService")
local PFS     = game:GetService("PathfindingService")

local player  = Players.LocalPlayer
local pgui    = player:WaitForChild("PlayerGui")

local RemotesGame = RS:WaitForChild("Remotes"):WaitForChild("Game")
local EggPlacedRE = RemotesGame:WaitForChild("EggPlaced")
local DismountRE  = RemotesGame:WaitForChild("PetDismount")

-- Load game egg definitions
local EGG_DATA = {}
pcall(function()
    EGG_DATA = require(RS:WaitForChild("GameData"):WaitForChild("Eggs"))
end)

local RARITY_RANKS = {
    ["Common"]    = 1,
    ["Rare"]      = 2,
    ["Epic"]      = 3,
    ["Legendary"] = 4,
    ["Mythic"]    = 5,
    ["Divine"]    = 6,
    ["Ethereal"]  = 7,
}

local EGG_OPTIONS = {"ALL (Auto Best)"}
do
    local sortedEggs = {}
    for eggName, info in pairs(EGG_DATA) do
        table.insert(sortedEggs, {name = eggName, luck = info.Luck or 0})
    end
    table.sort(sortedEggs, function(a, b)
        if a.luck ~= b.luck then return a.luck < b.luck end
        return a.name < b.name
    end)
    for _, item in ipairs(sortedEggs) do
        table.insert(EGG_OPTIONS, item.name)
    end
end

local selectedEggIndex = 1
local COLLECT_RANGE    = 14
local RIDE_RANGE       = 8
local LOOP_DELAY       = 0.8

_G.AEC_Running = false
local collected = 0
local blacklist = {}

-- UI
local sg = Instance.new("ScreenGui")
sg.Name = "AEC_GUI"; sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = pgui; _G.AEC_GUI = sg

local frame = Instance.new("Frame")
frame.Size = UDim2.new(0, 310, 0, 260)
frame.Position = UDim2.new(0, 16, 0.5, -130)
frame.BackgroundColor3 = Color3.fromRGB(18, 18, 28)
frame.BorderSizePixel = 0; frame.Active = true; frame.Draggable = true
frame.Parent = sg
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = frame end
do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(80, 140, 255); s.Thickness = 1.5; s.Parent = frame end

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, 0, 0, 34)
title.BackgroundColor3 = Color3.fromRGB(25, 75, 200)
title.BorderSizePixel = 0; title.Text = "🥚  Auto Egg Collector  v9"
title.TextColor3 = Color3.new(1, 1, 1); title.TextScaled = true
title.Font = Enum.Font.GothamBold; title.Parent = frame
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = title end

local function mkLbl(y, txt)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.new(1, -14, 0, 24); l.Position = UDim2.new(0, 7, 0, y)
    l.BackgroundTransparency = 1; l.TextColor3 = Color3.fromRGB(200, 220, 255)
    l.TextXAlignment = Enum.TextXAlignment.Left; l.TextScaled = true
    l.Font = Enum.Font.Gotham; l.Text = txt; l.Parent = frame; return l
end

local lblPet    = mkLbl(38,  "🐾 Best Pet:  —")
local lblTarget = mkLbl(64,  "🎯 Target:   —")
local lblStatus = mkLbl(146, "⚡ Status:   Idle")
local lblCount  = mkLbl(170, "✅ Deposited: 0")

local selContainer = Instance.new("Frame")
selContainer.Size = UDim2.new(1, -14, 0, 30)
selContainer.Position = UDim2.new(0, 7, 0, 96)
selContainer.BackgroundColor3 = Color3.fromRGB(28, 28, 42)
selContainer.BorderSizePixel = 0; selContainer.Parent = frame
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = selContainer end
do local s = Instance.new("UIStroke"); s.Color = Color3.fromRGB(60, 100, 200); s.Thickness = 1; s.Parent = selContainer end

local btnPrev = Instance.new("TextButton")
btnPrev.Size = UDim2.new(0, 30, 1, 0); btnPrev.Position = UDim2.new(0, 0, 0, 0)
btnPrev.BackgroundColor3 = Color3.fromRGB(35, 35, 55); btnPrev.BorderSizePixel = 0
btnPrev.Text = "◀"; btnPrev.TextColor3 = Color3.new(1, 1, 1); btnPrev.Font = Enum.Font.GothamBold
btnPrev.TextScaled = true; btnPrev.Parent = selContainer
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = btnPrev end

local lblChoice = Instance.new("TextLabel")
lblChoice.Size = UDim2.new(1, -64, 1, 0); lblChoice.Position = UDim2.new(0, 32, 0, 0)
lblChoice.BackgroundTransparency = 1; lblChoice.TextColor3 = Color3.fromRGB(255, 220, 100)
lblChoice.Font = Enum.Font.GothamBold; lblChoice.TextScaled = true
lblChoice.Text = EGG_OPTIONS[selectedEggIndex]; lblChoice.Parent = selContainer

local btnNext = Instance.new("TextButton")
btnNext.Size = UDim2.new(0, 30, 1, 0); btnNext.Position = UDim2.new(1, -30, 0, 0)
btnNext.BackgroundColor3 = Color3.fromRGB(35, 35, 55); btnNext.BorderSizePixel = 0
btnNext.Text = "▶"; btnNext.TextColor3 = Color3.new(1, 1, 1); btnNext.Font = Enum.Font.GothamBold
btnNext.TextScaled = true; btnNext.Parent = selContainer
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = btnNext end

local function updateEggDisplay()
    local chosen = EGG_OPTIONS[selectedEggIndex]
    lblChoice.Text = chosen
    lblTarget.Text = "🎯 Target:   " .. chosen
    blacklist = {}
end

btnPrev.MouseButton1Click:Connect(function()
    selectedEggIndex = selectedEggIndex - 1
    if selectedEggIndex < 1 then selectedEggIndex = #EGG_OPTIONS end
    updateEggDisplay()
end)

btnNext.MouseButton1Click:Connect(function()
    selectedEggIndex = selectedEggIndex + 1
    if selectedEggIndex > #EGG_OPTIONS then selectedEggIndex = 1 end
    updateEggDisplay()
end)

local btn = Instance.new("TextButton")
btn.Size = UDim2.new(1, -18, 0, 38); btn.Position = UDim2.new(0, 9, 1, -46)
btn.BackgroundColor3 = Color3.fromRGB(40, 180, 80); btn.BorderSizePixel = 0
btn.Text = "▶  START"; btn.TextColor3 = Color3.new(1, 1, 1)
btn.TextScaled = true; btn.Font = Enum.Font.GothamBold; btn.Parent = frame
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = btn end

local function setStatus(msg)
    lblStatus.Text = "⚡ Status:   " .. msg
end

local function triggerPickupPrompt(prompt)
    if not prompt or not prompt.Parent then return false end
    local hold = prompt.HoldDuration or 0.2
    if fireproximityprompt then
        fireproximityprompt(prompt, 0)
        task.wait(0.05)
        fireproximityprompt(prompt, hold + 0.05)
        return true
    end
    local ok = pcall(function() PPS:PromptTriggered(prompt, player) end)
    if not ok then
        pcall(function() prompt.Triggered:Fire(player) end)
    end
    return true
end

local function isRiding()
    return player:GetAttribute("IsRiding") == true
end

local function dismount()
    if isRiding() then
        DismountRE:FireServer()
        task.wait(0.4)
    end
end

local function getMyPlot()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        local df = plot:FindFirstChild("Data")
        if df then
            local ov = df:FindFirstChild("Owner")
            if ov and ov.Value == player then return plot end
        end
    end
end

local function getAvailableNest(plot)
    local nestsFolder = plot and plot:FindFirstChild("Nests")
    if not nestsFolder then return nil end
    for _, nest in ipairs(nestsFolder:GetChildren()) do
        if nest:GetAttribute("Unlocked") == true and not nest:GetAttribute("Occupied") then
            local part = nest:FindFirstChildWhichIsA("BasePart", true)
            if part then return nest, part end
        end
    end
    return nil
end

local function getPetsSorted(plot)
    local pf = plot:FindFirstChild("Pets")
    if not pf then return {} end
    local list = {}
    for _, pet in ipairs(pf:GetChildren()) do
        if pet:IsA("Model") then
            local data = pet:FindFirstChild("Data")
            local speed = 0
            if data then
                local sv = data:FindFirstChild("Speed")
                if sv then speed = sv.Value end
            end
            local root = pet:FindFirstChild("RootPart")
            local rp = root and root:FindFirstChild("RidePrompt")
            if root and rp then
                table.insert(list, {
                    model = pet,
                    name = pet:GetAttribute("PetName") or pet.Name,
                    speed = speed,
                    root = root,
                    prompt = rp,
                })
            end
        end
    end
    table.sort(list, function(a, b) return a.speed > b.speed end)
    return list
end

-- Ground Walking with dynamic distance-based timeout
local function walkTo(targetPos, label, range, promptToTry)
    range = range or COLLECT_RANGE
    local char = player.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChild("Humanoid")
    if not hrp or not hum then return false end

    local initialDist = (hrp.Position - targetPos).Magnitude
    -- Scale travel timeout dynamically based on distance (e.g. 2000 studs = ~60s)
    local travelLimit = math.clamp(initialDist / 35 + 20, 30, 90)
    local deadline = tick() + travelLimit

    setStatus("→ " .. label .. " (" .. math.floor(initialDist) .. "m)")

    local path = PFS:CreatePath({
        AgentRadius = 3,
        AgentHeight = 7,
        AgentCanJump = false,
        WaypointSpacing = 12,
    })

    while tick() < deadline and _G.AEC_Running do
        char = player.Character
        if not char then return false end
        hrp = char:FindFirstChild("HumanoidRootPart")
        hum = char:FindFirstChild("Humanoid")
        if not hrp or not hum then return false end

        local dist3D = (hrp.Position - targetPos).Magnitude
        local distFlat = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude

        if dist3D <= range or (distFlat <= 8 and math.abs(hrp.Position.Y - targetPos.Y) <= 12) then
            if promptToTry and promptToTry.Parent then
                triggerPickupPrompt(promptToTry)
            end
            return true
        end

        local pathOk = pcall(function() path:ComputeAsync(hrp.Position, targetPos) end)
        if pathOk and path.Status == Enum.PathStatus.Success then
            local waypoints = path:GetWaypoints()
            local recompute = false

            for _, wp in ipairs(waypoints) do
                if not _G.AEC_Running or tick() >= deadline then return false end

                dist3D = (hrp.Position - targetPos).Magnitude
                distFlat = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
                if dist3D <= range or (distFlat <= 8 and math.abs(hrp.Position.Y - targetPos.Y) <= 12) then
                    if promptToTry and promptToTry.Parent then
                        triggerPickupPrompt(promptToTry)
                    end
                    return true
                end

                hum:MoveTo(wp.Position)

                local wpTimeout = tick() + 2.5
                local lastCheckPos = hrp.Position
                local stuckCount = 0

                while tick() < wpTimeout and _G.AEC_Running do
                    dist3D = (hrp.Position - targetPos).Magnitude
                    distFlat = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(targetPos.X, 0, targetPos.Z)).Magnitude
                    if dist3D <= range or (distFlat <= 8 and math.abs(hrp.Position.Y - targetPos.Y) <= 12) then
                        if promptToTry and promptToTry.Parent then
                            triggerPickupPrompt(promptToTry)
                        end
                        return true
                    end

                    local distToWp = (Vector3.new(hrp.Position.X, 0, hrp.Position.Z) - Vector3.new(wp.Position.X, 0, wp.Position.Z)).Magnitude
                    if distToWp <= 8 then break end

                    task.wait(0.08)
                    local moved = (hrp.Position - lastCheckPos).Magnitude
                    if moved < 0.6 then
                        stuckCount = stuckCount + 1
                        if stuckCount >= 3 then
                            local dodge = (math.random() > 0.5 and 1 or -1) * hrp.CFrame.RightVector * 8
                            hum:MoveTo(hrp.Position + dodge)
                            task.wait(0.25)
                            recompute = true
                            break
                        end
                    else
                        stuckCount = 0
                        lastCheckPos = hrp.Position
                    end
                end

                if recompute then break end
            end
        else
            -- Direct movement fallback
            hum:MoveTo(targetPos)
            local lastP = hrp.Position
            local directStuck = 0
            for _ = 1, 6 do
                if not _G.AEC_Running or tick() >= deadline then return false end
                dist3D = (hrp.Position - targetPos).Magnitude
                if dist3D <= range then return true end
                task.wait(0.15)
                if (hrp.Position - lastP).Magnitude < 0.8 then
                    directStuck = directStuck + 1
                    if directStuck >= 2 then
                        local dodge = (math.random() > 0.5 and 1 or -1) * hrp.CFrame.RightVector * 8
                        hum:MoveTo(hrp.Position + dodge)
                        task.wait(0.2)
                        break
                    end
                else
                    directStuck = 0
                    lastP = hrp.Position
                end
                hum:MoveTo(targetPos)
            end
        end
        task.wait(0.03)
    end

    return (hrp.Position - targetPos).Magnitude <= range
end

local function rideThisPet(petInfo)
    if isRiding() then return true end
    for attempt = 1, 3 do
        if not _G.AEC_Running then return false end
        setStatus("Mounting " .. petInfo.name .. " (" .. attempt .. ")")
        local char = player.Character
        if not char then return false end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local hum = char:FindFirstChild("Humanoid")
        if not hrp or not hum then return false end

        walkTo(petInfo.root.Position, petInfo.name, RIDE_RANGE)
        hum:MoveTo(hrp.Position)
        task.wait(0.2)

        triggerPickupPrompt(petInfo.prompt)
        task.wait(0.5)
        if isRiding() then return true end
        triggerPickupPrompt(petInfo.prompt)
        task.wait(0.6)
        if isRiding() then return true end
    end
    return isRiding()
end

-- Selects egg with full map radius
local function getTargetEgg(petSpeed)
    local re = workspace:FindFirstChild("RenderedEggs")
    if not re then return nil end

    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return nil end

    local chosenFilter = EGG_OPTIONS[selectedEggIndex]

    local candidates = {}
    for _, egg in ipairs(re:GetChildren()) do
        if not blacklist[egg] then
            local part = egg:FindFirstChildWhichIsA("BasePart")
            local prompt = egg:FindFirstChildWhichIsA("ProximityPrompt", true)
            if part and prompt and prompt.Enabled then
                local matchesFilter = (chosenFilter == "ALL (Auto Best)") or (egg.Name == chosenFilter)
                if matchesFilter then
                    local dist = (part.Position - hrp.Position).Magnitude
                    local data = EGG_DATA[egg.Name] or {}
                    local rarity = data.Rarity or "Common"
                    local rank = RARITY_RANKS[rarity] or 1

                    table.insert(candidates, {
                        model = egg,
                        name = egg.Name,
                        part = part,
                        prompt = prompt,
                        pos = part.Position,
                        rarity = rarity,
                        rank = rank,
                        dist = dist,
                    })
                end
            end
        end
    end

    if #candidates == 0 then return nil end

    -- For Auto Best: prioritize rarity first, then distance.
    -- For Specific Egg: prioritize closest distance to save travel time.
    if chosenFilter == "ALL (Auto Best)" then
        table.sort(candidates, function(a, b)
            if a.rank ~= b.rank then return a.rank > b.rank end
            return a.dist < b.dist
        end)
    else
        table.sort(candidates, function(a, b)
            return a.dist < b.dist
        end)
    end

    return candidates[1]
end

-- Main Loop
local function mainLoop()
    setStatus("Starting…")
    collected = 0
    blacklist = {}

    while _G.AEC_Running do
        local plot = getMyPlot()
        if not plot then setStatus("❌ Plot not found"); task.wait(2); continue end

        local nest, nestPart = getAvailableNest(plot)
        if not nest then
            setStatus("⚠️ All nests occupied"); task.wait(2); continue
        end

        local pets = getPetsSorted(plot)
        if #pets == 0 then setStatus("❌ No pets in plot"); task.wait(2); continue end
        local bestPet = pets[1]
        lblPet.Text = "🐾 Best Pet:  " .. bestPet.name .. " (spd " .. bestPet.speed .. ")"

        if not isRiding() then
            local mounted = rideThisPet(bestPet)
            if not mounted then setStatus("⚠️ Mount failed"); task.wait(2); continue end
        end

        local eggData = getTargetEgg(bestPet.speed)
        if not eggData or not eggData.model.Parent then
            local chosen = EGG_OPTIONS[selectedEggIndex]
            setStatus("⚠️ Searching " .. chosen .. "…"); task.wait(1.5); continue
        end

        lblTarget.Text = "🎯 Target:   " .. eggData.name .. " (" .. eggData.rarity .. ")"

        -- Ground walk to egg
        local reached = walkTo(eggData.pos, eggData.name, COLLECT_RANGE, eggData.prompt)

        -- Pickup prompt
        setStatus("🖐 Picking up " .. eggData.name .. "…")
        triggerPickupPrompt(eggData.prompt)
        task.wait(0.4)

        local basket = player:FindFirstChild("Basket")
        local inBasket = basket and #basket:GetChildren() > 0
        if not inBasket and eggData.prompt.Parent then
            task.wait(0.2)
            triggerPickupPrompt(eggData.prompt)
            task.wait(0.4)
            inBasket = basket and #basket:GetChildren() > 0
        end

        if not inBasket then
            blacklist[eggData.model] = true
            setStatus("⚠️ Skipped unreachable egg"); task.wait(0.5); continue
        end

        -- Depositing into plot nest
        setStatus("🏠 Depositing into Nest " .. nest.Name .. "…")
        walkTo(nestPart.Position, "Nest " .. nest.Name, 8)

        EggPlacedRE:FireServer({NestId = nest.Name})
        task.wait(0.5)

        collected = collected + 1
        lblCount.Text = "✅ Deposited: " .. collected
        setStatus("✨ Deposited " .. eggData.name .. "!")

        task.wait(LOOP_DELAY)
    end

    dismount()
    setStatus("Stopped")
end

btn.MouseButton1Click:Connect(function()
    if _G.AEC_Running then
        _G.AEC_Running = false
        btn.BackgroundColor3 = Color3.fromRGB(40, 180, 80)
        btn.Text = "▶  START"
        setStatus("Stopped")
    else
        _G.AEC_Running = true
        btn.BackgroundColor3 = Color3.fromRGB(200, 55, 55)
        btn.Text = "⏹  STOP"
        task.spawn(mainLoop)
    end
end)

print("[AEC v9] Loaded with full-map radius & dynamic distance timeout!")
