--[[
    ═════════════════════════════════════════════════════════════════════════
    ⛩️ [JJK WORLD] TRAIN YOUR AURA - ALL-IN-ONE AUTOMATION HUB & UI
    ═════════════════════════════════════════════════════════════════════════
    Features:
      1. Auto-Equip Best Aura (Lowest weight / highest rarity & odds)
      2. Auto-Tap Multiplier Power Buttons (x2, x4, x8, x16 Screen Bonuses)
      3. Auto-Teleport to Best Unlocked Training Zone (Real-Time Power Scaling)
      4. Auto-Spin / Roll Assistant
      5. Real-Time HUD (Current Power, Training Zone, Equipped Aura, Best Aura)
      6. Dedicated ON/OFF Toggles for every feature
      7. Safe UNLOAD SCRIPT Button (cleans all loops, threads, and UI)
      8. Clean, Draggable, Minimizable Modern Dark Theme GUI
    ═════════════════════════════════════════════════════════════════════════
]]

-- Clean up any previous running instance
if _G.JJK_HUB_CLEANUP then
    pcall(_G.JJK_HUB_CLEANUP)
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Game Modules
local Shared = ReplicatedStorage:WaitForChild("Shared", 10)
local Config = Shared and Shared:WaitForChild("config", 10)
local State = Shared and Shared:WaitForChild("state", 10)

local SpinConfig = Config and require(Config:WaitForChild("spin", 10))
local PlayerData = State and require(State:WaitForChild("player-data", 10))
local AuraTiers = Config and require(Config:WaitForChild("aura-tiers", 10))
local Net = Shared and require(Shared:WaitForChild("net", 10))

-- Feature State Flags
local ConfigState = {
    AutoEquipBestAura = true,
    AutoTapMultipliers = true,
    AutoTeleportBestZone = true,
    AutoSpin = false,
    CheckInterval = 1.0,
    TotalTapsClaimed = 0,
    Running = true,
}

-- Rarity Colors
local RarityColors = {
    ["COMMON"] = Color3.fromRGB(180, 180, 180),
    ["UNCOMMON"] = Color3.fromRGB(85, 255, 127),
    ["RARE"] = Color3.fromRGB(85, 170, 255),
    ["EPIC"] = Color3.fromRGB(170, 85, 255),
    ["LEGENDARY"] = Color3.fromRGB(255, 170, 0),
    ["MYTHIC"] = Color3.fromRGB(255, 60, 60),
    ["DIVINE"] = Color3.fromRGB(255, 215, 0),
    ["SECRET"] = Color3.fromRGB(255, 0, 128),
    ["UNKNOWN"] = Color3.fromRGB(150, 150, 150),
}

----------------------------------------------------------------------
-- HELPER FUNCTIONS
----------------------------------------------------------------------

local function getPlayerData()
    if not PlayerData then return nil end
    local ok, atom = pcall(function() return PlayerData.atom() end)
    if ok and type(atom) == "table" then
        return atom[tostring(LocalPlayer.UserId)]
    end
    return nil
end

local function formatNumber(n)
    if not n or n ~= n then return "0" end
    if n >= 1e15 then return string.format("%.2fQ", n / 1e15)
    elseif n >= 1e12 then return string.format("%.2fT", n / 1e12)
    elseif n >= 1e9 then return string.format("%.2fB", n / 1e9)
    elseif n >= 1e6 then return string.format("%.2fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.2fK", n / 1e3)
    else return tostring(math.floor(n)) end
end

-- Get Real-Time Power / Aura
local function getCurrentPower()
    local data = getPlayerData()
    if data and data.money then
        return data.money
    end
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    if ls then
        for _, v in ipairs(ls:GetChildren()) do
            if v:IsA("NumberValue") or v:IsA("IntValue") then
                return v.Value
            end
        end
    end
    return 0
end

-- Best Owned Aura
local function getBestOwnedAura()
    local data = getPlayerData()
    if not data or not data.ownedAuras or #data.ownedAuras == 0 or not SpinConfig then
        return nil, nil
    end

    local bestAura, bestEntry = nil, nil
    local lowestWeight = math.huge

    for _, aura in ipairs(data.ownedAuras) do
        local entry = SpinConfig.getEntry(aura.id)
        if entry then
            local weight = entry.weight or math.huge
            if weight < lowestWeight then
                lowestWeight = weight
                bestAura = aura
                bestEntry = entry
            end
        end
    end

    return bestAura, bestEntry
end

-- Currently Equipped Aura
local function getEquippedAura()
    local data = getPlayerData()
    if not data or not data.equippedAuraUuid or not SpinConfig then
        return nil, nil
    end

    for _, aura in ipairs(data.ownedAuras or {}) do
        if aura.uuid == data.equippedAuraUuid then
            local entry = SpinConfig.getEntry(aura.id)
            return aura, entry
        end
    end

    return nil, nil
end

-- Equip Best Aura Logic
local function equipBestAura()
    local bestAura, bestEntry = getBestOwnedAura()
    if not bestAura then return false end

    local currentAura = getEquippedAura()
    if currentAura and currentAura.uuid == bestAura.uuid then
        return true -- Already equipped
    end

    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    local equipBestBtn = pgui and pgui:FindFirstChild("Auras") 
        and pgui.Auras:FindFirstChild("Auras")
        and pgui.Auras.Auras:FindFirstChild("Content")
        and pgui.Auras.Auras.Content:FindFirstChild("_frame")
        and pgui.Auras.Auras.Content._frame:FindFirstChild("Header")
        and pgui.Auras.Auras.Content._frame.Header:FindFirstChild("EquipBestButton")

    if equipBestBtn and firesignal then
        pcall(firesignal, equipBestBtn.Activated)
    end

    pcall(function()
        if Net and Net.Fire then
            Net:Fire("EquipAura", bestAura.uuid)
        end
    end)

    return true
end

-- Calculate Best Unlocked Training Zone
local function getBestUnlockedTrainingZone()
    local power = getCurrentPower()
    local bestTier = nil

    if AuraTiers and AuraTiers.TIERS then
        for _, tier in ipairs(AuraTiers.TIERS) do
            if power >= (tier.auraRequired or 0) then
                bestTier = tier
            else
                break
            end
        end
    end

    return bestTier
end

-- Teleport to Best Zone
local function teleportToBestZone()
    pcall(function()
        if Net and Net.Fire then
            Net:Fire("RequestTeleportBestZone")
        end
    end)

    local bestTier = getBestUnlockedTrainingZone()
    if bestTier and bestTier.id then
        pcall(function()
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if not hrp then return end

            local zonesFolder = workspace:FindFirstChild("FarmingZones") or workspace:FindFirstChild("Zones") or workspace:FindFirstChild("TrainingZones")
            if zonesFolder then
                local zoneModel = zonesFolder:FindFirstChild(bestTier.id)
                if zoneModel then
                    local pad = zoneModel:FindFirstChild("Pad") or zoneModel:FindFirstChild("Spawn") or zoneModel:FindFirstChildWhichIsA("BasePart")
                    if pad and (hrp.Position - pad.Position).Magnitude > 50 then
                        hrp.CFrame = pad.CFrame + Vector3.new(0, 3, 0)
                    end
                end
            end
        end)
    end
end

-- Auto-Tap Multiplier Power Buttons (Screen Bonuses)
local function tapScreenBonusButtons()
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    if not pgui then return end

    local screenBonuses = pgui:FindFirstChild("ScreenBonuses")
    if screenBonuses then
        for _, obj in ipairs(screenBonuses:GetDescendants()) do
            if (obj:IsA("ImageButton") or obj:IsA("TextButton")) and obj.Visible then
                pcall(function()
                    if firesignal then
                        firesignal(obj.Activated)
                        firesignal(obj.MouseButton1Click)
                        firesignal(obj.MouseButton1Down)
                    end
                    ConfigState.TotalTapsClaimed = ConfigState.TotalTapsClaimed + 1
                end)
            end
        end
    end

    for _, gui in ipairs(pgui:GetChildren()) do
        if gui:IsA("ScreenGui") and gui.Name ~= "AutoBestAura_Hub" then
            for _, btn in ipairs(gui:GetDescendants()) do
                if (btn:IsA("ImageButton") or btn:IsA("TextButton")) and btn.Visible then
                    local text = btn:IsA("TextButton") and btn.Text or ""
                    local name = btn.Name:lower()
                    if name:find("bonus") or name:find("multiplier") or text:find("x2") or text:find("x4") or text:find("x8") or text:find("x16") then
                        pcall(function()
                            if firesignal then
                                firesignal(btn.Activated)
                                firesignal(btn.MouseButton1Click)
                            end
                            ConfigState.TotalTapsClaimed = ConfigState.TotalTapsClaimed + 1
                        end)
                    end
                end
            end
        end
    end

    pcall(function()
        if Net and Net.Fire then
            Net:Fire("RequestClaimScreenBonus")
        end
    end)
end

----------------------------------------------------------------------
-- BUILD USER INTERFACE
----------------------------------------------------------------------

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoBestAura_Hub"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

pcall(function()
    ScreenGui.Parent = (gethui and gethui()) or CoreGui
end)
if not ScreenGui.Parent then
    ScreenGui.Parent = PlayerGui
end

-- Main Window Frame
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 380, 0, 560)
MainFrame.Position = UDim2.new(0.04, 0, 0.15, 0)
MainFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Parent = ScreenGui

local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 12)
MainCorner.Parent = MainFrame

local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(50, 55, 70)
MainStroke.Thickness = 1.5
MainStroke.Parent = MainFrame

-- Top Bar (Draggable)
local TopBar = Instance.new("Frame")
TopBar.Name = "TopBar"
TopBar.Size = UDim2.new(1, 0, 0, 44)
TopBar.BackgroundColor3 = Color3.fromRGB(25, 28, 38)
TopBar.BorderSizePixel = 0
TopBar.Parent = MainFrame

local TopCorner = Instance.new("UICorner")
TopCorner.CornerRadius = UDim.new(0, 12)
TopCorner.Parent = TopBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "Title"
TitleLabel.Text = "⛩️ JJK WORLD AUTOMATION"
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 13
TitleLabel.TextColor3 = Color3.fromRGB(255, 215, 80)
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Position = UDim2.new(0, 14, 0, 0)
TitleLabel.Size = UDim2.new(0.65, 0, 1, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Parent = TopBar

-- Minimize Button
local MinBtn = Instance.new("TextButton")
MinBtn.Name = "MinBtn"
MinBtn.Text = "—"
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 14
MinBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
MinBtn.BackgroundColor3 = Color3.fromRGB(38, 42, 55)
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -68, 0, 8)
MinBtn.BorderSizePixel = 0
MinBtn.Parent = TopBar

local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinBtn

local IsMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    IsMinimized = not IsMinimized
    if IsMinimized then
        TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = UDim2.new(0, 380, 0, 44)}):Play()
        MinBtn.Text = "□"
    else
        TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = UDim2.new(0, 380, 0, 560)}):Play()
        MinBtn.Text = "—"
    end
end)

-- Unload / Close Button
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Text = "✕"
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 14
CloseBtn.TextColor3 = Color3.fromRGB(200, 200, 200)
CloseBtn.BackgroundColor3 = Color3.fromRGB(38, 42, 55)
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -36, 0, 8)
CloseBtn.BorderSizePixel = 0
CloseBtn.Parent = TopBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

-- Dragging Handler
local Dragging, DragInput, DragStart, StartPos
TopBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        Dragging = true
        DragStart = input.Position
        StartPos = MainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then Dragging = false end
        end)
    end
end)
TopBar.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        DragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if input == DragInput and Dragging then
        local delta = input.Position - DragStart
        MainFrame.Position = UDim2.new(StartPos.X.Scale, StartPos.X.Offset + delta.X, StartPos.Y.Scale, StartPos.Y.Offset + delta.Y)
    end
end)

-- Scrolling / Content Container
local Content = Instance.new("ScrollingFrame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -20, 1, -54)
Content.Position = UDim2.new(0, 10, 0, 48)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 3
Content.ScrollBarImageColor3 = Color3.fromRGB(70, 75, 95)
Content.CanvasSize = UDim2.new(0, 0, 0, 500)
Content.Parent = MainFrame

-- Card: Real-Time Power & Best Training Zone
local CardStats = Instance.new("Frame")
CardStats.Size = UDim2.new(1, 0, 0, 74)
CardStats.Position = UDim2.new(0, 0, 0, 0)
CardStats.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
CardStats.BorderSizePixel = 0
CardStats.Parent = Content

local CSCorner = Instance.new("UICorner")
CSCorner.CornerRadius = UDim.new(0, 8)
CSCorner.Parent = CardStats

local CSStroke = Instance.new("UIStroke")
CSStroke.Color = Color3.fromRGB(42, 47, 62)
CSStroke.Parent = CardStats

local LabelPowerTitle = Instance.new("TextLabel")
LabelPowerTitle.Text = "⚡ REAL-TIME POWER / AURA"
LabelPowerTitle.Font = Enum.Font.GothamBold
LabelPowerTitle.TextSize = 10
LabelPowerTitle.TextColor3 = Color3.fromRGB(0, 200, 255)
LabelPowerTitle.Position = UDim2.new(0, 10, 0, 8)
LabelPowerTitle.Size = UDim2.new(0.5, 0, 0, 14)
LabelPowerTitle.BackgroundTransparency = 1
LabelPowerTitle.TextXAlignment = Enum.TextXAlignment.Left
LabelPowerTitle.Parent = CardStats

local LabelPowerVal = Instance.new("TextLabel")
LabelPowerVal.Text = "0"
LabelPowerVal.Font = Enum.Font.GothamBold
LabelPowerVal.TextSize = 17
LabelPowerVal.TextColor3 = Color3.fromRGB(255, 255, 255)
LabelPowerVal.Position = UDim2.new(0, 10, 0, 24)
LabelPowerVal.Size = UDim2.new(0.5, 0, 0, 22)
LabelPowerVal.BackgroundTransparency = 1
LabelPowerVal.TextXAlignment = Enum.TextXAlignment.Left
LabelPowerVal.Parent = CardStats

local LabelZoneTitle = Instance.new("TextLabel")
LabelZoneTitle.Text = "📍 BEST TRAINING ZONE"
LabelZoneTitle.Font = Enum.Font.GothamBold
LabelZoneTitle.TextSize = 10
LabelZoneTitle.TextColor3 = Color3.fromRGB(255, 215, 80)
LabelZoneTitle.Position = UDim2.new(0.52, 0, 0, 8)
LabelZoneTitle.Size = UDim2.new(0.46, 0, 0, 14)
LabelZoneTitle.BackgroundTransparency = 1
LabelZoneTitle.TextXAlignment = Enum.TextXAlignment.Left
LabelZoneTitle.Parent = CardStats

local LabelZoneVal = Instance.new("TextLabel")
LabelZoneVal.Text = "Detecting..."
LabelZoneVal.Font = Enum.Font.GothamBold
LabelZoneVal.TextSize = 13
LabelZoneVal.TextColor3 = Color3.fromRGB(255, 255, 255)
LabelZoneVal.Position = UDim2.new(0.52, 0, 0, 24)
LabelZoneVal.Size = UDim2.new(0.46, 0, 0, 22)
LabelZoneVal.BackgroundTransparency = 1
LabelZoneVal.TextXAlignment = Enum.TextXAlignment.Left
LabelZoneVal.Parent = CardStats

local LabelBonusTaps = Instance.new("TextLabel")
LabelBonusTaps.Text = "Multipliers Tapped: 0"
LabelBonusTaps.Font = Enum.Font.GothamMedium
LabelBonusTaps.TextSize = 10
LabelBonusTaps.TextColor3 = Color3.fromRGB(150, 230, 150)
LabelBonusTaps.Position = UDim2.new(0, 10, 0, 50)
LabelBonusTaps.Size = UDim2.new(1, -20, 0, 16)
LabelBonusTaps.BackgroundTransparency = 1
LabelBonusTaps.TextXAlignment = Enum.TextXAlignment.Left
LabelBonusTaps.Parent = CardStats

-- Card: Aura Status (Equipped vs Best)
local CardAuras = Instance.new("Frame")
CardAuras.Size = UDim2.new(1, 0, 0, 68)
CardAuras.Position = UDim2.new(0, 0, 0, 82)
CardAuras.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
CardAuras.BorderSizePixel = 0
CardAuras.Parent = Content

local CACorner = Instance.new("UICorner")
CACorner.CornerRadius = UDim.new(0, 8)
CACorner.Parent = CardAuras

local CAStroke = Instance.new("UIStroke")
CAStroke.Color = Color3.fromRGB(42, 47, 62)
CAStroke.Parent = CardAuras

local LabelEqStatus = Instance.new("TextLabel")
LabelEqStatus.Text = "EQUIPPED: Loading..."
LabelEqStatus.Font = Enum.Font.GothamBold
LabelEqStatus.TextSize = 12
LabelEqStatus.TextColor3 = Color3.fromRGB(240, 240, 240)
LabelEqStatus.Position = UDim2.new(0, 10, 0, 10)
LabelEqStatus.Size = UDim2.new(0.65, 0, 0, 20)
LabelEqStatus.BackgroundTransparency = 1
LabelEqStatus.TextXAlignment = Enum.TextXAlignment.Left
LabelEqStatus.Parent = CardAuras

local BadgeEqRarity = Instance.new("TextLabel")
BadgeEqRarity.Text = "EPIC"
BadgeEqRarity.Font = Enum.Font.GothamBold
BadgeEqRarity.TextSize = 10
BadgeEqRarity.TextColor3 = Color3.fromRGB(255, 255, 255)
BadgeEqRarity.BackgroundColor3 = Color3.fromRGB(170, 85, 255)
BadgeEqRarity.Size = UDim2.new(0, 80, 0, 20)
BadgeEqRarity.Position = UDim2.new(1, -90, 0, 10)
BadgeEqRarity.BorderSizePixel = 0
BadgeEqRarity.Parent = CardAuras

local BEqCorner = Instance.new("UICorner")
BEqCorner.CornerRadius = UDim.new(0, 4)
BEqCorner.Parent = BadgeEqRarity

local LabelBestStatus = Instance.new("TextLabel")
LabelBestStatus.Text = "BEST OWNED: Loading..."
LabelBestStatus.Font = Enum.Font.GothamMedium
LabelBestStatus.TextSize = 11
LabelBestStatus.TextColor3 = Color3.fromRGB(180, 185, 200)
LabelBestStatus.Position = UDim2.new(0, 10, 0, 38)
LabelBestStatus.Size = UDim2.new(1, -20, 0, 18)
LabelBestStatus.BackgroundTransparency = 1
LabelBestStatus.TextXAlignment = Enum.TextXAlignment.Left
LabelBestStatus.Parent = CardAuras

----------------------------------------------------------------------
-- TOGGLE BUILDER HELPER
----------------------------------------------------------------------
local function createToggle(name, text, defaultState, yPos, onToggle)
    local frame = Instance.new("Frame")
    frame.Name = "Toggle_" .. name
    frame.Size = UDim2.new(1, 0, 0, 42)
    frame.Position = UDim2.new(0, 0, 0, yPos)
    frame.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
    frame.BorderSizePixel = 0
    frame.Parent = Content

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = frame

    local title = Instance.new("TextLabel")
    title.Text = text
    title.Font = Enum.Font.GothamSemibold
    title.TextSize = 12
    title.TextColor3 = Color3.fromRGB(230, 235, 245)
    title.Position = UDim2.new(0, 12, 0, 0)
    title.Size = UDim2.new(0.72, 0, 1, 0)
    title.BackgroundTransparency = 1
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Text = defaultState and "ON" or "OFF"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.BackgroundColor3 = defaultState and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(231, 76, 60)
    btn.Size = UDim2.new(0, 58, 0, 26)
    btn.Position = UDim2.new(1, -68, 0, 8)
    btn.BorderSizePixel = 0
    btn.Parent = frame

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = btn

    local currentState = defaultState
    btn.MouseButton1Click:Connect(function()
        currentState = not currentState
        btn.Text = currentState and "ON" or "OFF"
        btn.BackgroundColor3 = currentState and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(231, 76, 60)
        onToggle(currentState)
    end)

    return frame
end

-- Toggles
createToggle("AutoEquip", "Auto-Equip Best Aura", ConfigState.AutoEquipBestAura, 158, function(val)
    ConfigState.AutoEquipBestAura = val
end)

createToggle("AutoTap", "Auto-Tap Multipliers (x2, x4, x8, x16)", ConfigState.AutoTapMultipliers, 206, function(val)
    ConfigState.AutoTapMultipliers = val
end)

createToggle("AutoZone", "Auto-Teleport Best Training Zone", ConfigState.AutoTeleportBestZone, 254, function(val)
    ConfigState.AutoTeleportBestZone = val
end)

createToggle("AutoSpin", "Auto-Spin / Roll Helper", ConfigState.AutoSpin, 302, function(val)
    ConfigState.AutoSpin = val
end)

-- Action Button: Instant Teleport
local ActionTpBtn = Instance.new("TextButton")
ActionTpBtn.Text = "⚡ TELEPORT TO BEST ZONE NOW"
ActionTpBtn.Font = Enum.Font.GothamBold
ActionTpBtn.TextSize = 12
ActionTpBtn.TextColor3 = Color3.fromRGB(20, 20, 25)
ActionTpBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
ActionTpBtn.Size = UDim2.new(1, 0, 0, 36)
ActionTpBtn.Position = UDim2.new(0, 0, 0, 352)
ActionTpBtn.BorderSizePixel = 0
ActionTpBtn.Parent = Content

local TpCorner = Instance.new("UICorner")
TpCorner.CornerRadius = UDim.new(0, 8)
TpCorner.Parent = ActionTpBtn

ActionTpBtn.MouseButton1Click:Connect(function()
    teleportToBestZone()
end)

-- Action Button: Instant Equip Best Aura
local ActionEqBtn = Instance.new("TextButton")
ActionEqBtn.Text = "👑 EQUIP BEST AURA NOW"
ActionEqBtn.Font = Enum.Font.GothamBold
ActionEqBtn.TextSize = 12
ActionEqBtn.TextColor3 = Color3.fromRGB(20, 20, 25)
ActionEqBtn.BackgroundColor3 = Color3.fromRGB(255, 215, 80)
ActionEqBtn.Size = UDim2.new(1, 0, 0, 36)
ActionEqBtn.Position = UDim2.new(0, 0, 0, 396)
ActionEqBtn.BorderSizePixel = 0
ActionEqBtn.Parent = Content

local EqCorner = Instance.new("UICorner")
EqCorner.CornerRadius = UDim.new(0, 8)
EqCorner.Parent = ActionEqBtn

ActionEqBtn.MouseButton1Click:Connect(function()
    equipBestAura()
end)

-- Dedicated UNLOAD SCRIPT Button
local UnloadBtn = Instance.new("TextButton")
UnloadBtn.Name = "UnloadBtn"
UnloadBtn.Text = "⛔ UNLOAD SCRIPT"
UnloadBtn.Font = Enum.Font.GothamBold
UnloadBtn.TextSize = 12
UnloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
UnloadBtn.Size = UDim2.new(1, 0, 0, 36)
UnloadBtn.Position = UDim2.new(0, 0, 0, 440)
UnloadBtn.BorderSizePixel = 0
UnloadBtn.Parent = Content

local UnloadCorner = Instance.new("UICorner")
UnloadCorner.CornerRadius = UDim.new(0, 8)
UnloadCorner.Parent = UnloadBtn

-- Unload Cleanup Handler
local function unloadScript()
    ConfigState.Running = false
    pcall(function() ScreenGui:Destroy() end)
    _G.JJK_HUB_CLEANUP = nil
    print("[⛩️ JJK WORLD] Script unloaded cleanly.")
end

UnloadBtn.MouseButton1Click:Connect(unloadScript)
CloseBtn.MouseButton1Click:Connect(unloadScript)
_G.JJK_HUB_CLEANUP = unloadScript

----------------------------------------------------------------------
-- REAL-TIME HUD & BACKGROUND ENGINE
----------------------------------------------------------------------
local function refreshHUD()
    local curPower = getCurrentPower()
    LabelPowerVal.Text = formatNumber(curPower)

    local bestZone = getBestUnlockedTrainingZone()
    if bestZone then
        LabelZoneVal.Text = bestZone.name .. " (" .. tostring(bestZone.multiplier) .. "x)"
    else
        LabelZoneVal.Text = "Sandbox (2x)"
    end

    LabelBonusTaps.Text = "Multipliers Auto-Claimed: " .. tostring(ConfigState.TotalTapsClaimed)

    local eqAura, eqEntry = getEquippedAura()
    if eqEntry then
        LabelEqStatus.Text = "EQUIPPED: " .. (eqEntry.name or eqAura.id:upper())
        BadgeEqRarity.Text = eqEntry.rarity or "UNKNOWN"
        BadgeEqRarity.BackgroundColor3 = RarityColors[eqEntry.rarity] or RarityColors["UNKNOWN"]
    end

    local bestAura, bestEntry = getBestOwnedAura()
    if bestEntry then
        local odds = SpinConfig and SpinConfig.oddsDenominator(bestEntry) or 0
        LabelBestStatus.Text = "BEST OWNED: " .. (bestEntry.name or bestAura.id:upper()) .. " (1 in " .. formatNumber(odds) .. ")"
    end
end

-- Fast Multiplier Tapping Thread (Checks every 0.15s)
task.spawn(function()
    while ConfigState.Running do
        if ConfigState.AutoTapMultipliers then
            pcall(tapScreenBonusButtons)
        end
        task.wait(0.15)
    end
end)

-- Main Automation Loop (Heartbeat every 1s)
task.spawn(function()
    while ConfigState.Running do
        pcall(function()
            refreshHUD()

            if ConfigState.AutoEquipBestAura then
                equipBestAura()
            end

            if ConfigState.AutoTeleportBestZone then
                teleportToBestZone()
            end

            if ConfigState.AutoSpin and Net and Net.Fire then
                Net:Fire("RequestSpin")
            end
        end)
        task.wait(ConfigState.CheckInterval)
    end
end)

print("[⛩️ JJK WORLD] Full Automation Hub loaded successfully!")
