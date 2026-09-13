--[[
    ═══════════════════════════════════════════════════════════════════
    🗡️ REBORN AS SWORDSMAN - AUTO CHALLENGE BOSS HUB + AUTO KILL
    ═══════════════════════════════════════════════════════════════════
    Features:
      • 👑 SELECT STAGE / WORLD BOSS 1-16 with live stats & teleport
      • ⚡ AUTO KILL / INSTA-KILL (Ultra-fast multi-hit burst 5x-10x)
      • 🧲 CONTINUOUS MAGNET (Locked on 60/120 FPS Heartbeat, zero velocity)
      • 🛑 SMART ATTACK CONTROLLER (Instantly stops attacking when boss dies)
      • 🔮 Auto Challenge Secret Bosses (Relics) with Live Cooldown Tracker
      • 🔄 Auto Farm All Ready Secret Bosses in Continuous Rotation
      • 🗼 Auto Tower Challenge
      • 🛡️ Anti-Damage / Freeze Boss Attack
      • 🎁 Auto Close Reward Windows
      • 🖥️ Sleek Dark Glassmorphism Draggable UI with Floating Pill & Keybind
--]]

-- 1. Services & References
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Game Modules & Remotes
local Events = ReplicatedStorage:WaitForChild("Events")
local Config = ReplicatedStorage:WaitForChild("Config")
local Helper = ReplicatedStorage:WaitForChild("Helper")
local Managers = ReplicatedStorage:WaitForChild("Managers")

local DataConfig = require(Config:WaitForChild("DataConfig"))
local RelicsConfig = require(Config:WaitForChild("RelicsConfig"))
local WorldConfig = require(Config:WaitForChild("WorldConfig"))
local NPCConfig = require(Config:WaitForChild("NPCConfig"))
local AniModule = require(Helper:WaitForChild("AniModule"))
local WorldManager = require(Managers:WaitForChild("WorldManager"))
local TowerManager = require(Managers:WaitForChild("TowerManager"))

local FightNpcs = workspace:WaitForChild("FightNpcs")

-- Target GUI Parent: PlayerGui (most reliable across all executors, avoiding plugin capability limits)
local GuiParent = PlayerGui

-- Clean up older instance and connections if existing
if _G.RAS_MagnetConn then
    _G.RAS_MagnetConn:Disconnect()
    _G.RAS_MagnetConn = nil
end

pcall(function()
    if PlayerGui:FindFirstChild("RAS_BossHub_Gui") then
        PlayerGui.RAS_BossHub_Gui:Destroy()
    end
    if game:GetService("CoreGui"):FindFirstChild("RAS_BossHub_Gui") then
        game:GetService("CoreGui").RAS_BossHub_Gui:Destroy()
    end
end)

-- Ensure game internal auto-swinging is halted
DataConfig.LocalData.AutoPK = false
pcall(function()
    AniModule.CheckAutoPlayAttackAnim(false)
    AniModule.StopAllATKAnim()
end)

-- World Boss 1-16 Definition List
local WorldBossList = {
    {Index = 1, Id = "World001", WorldName = "Castle", BossName = "Blood-Red Igris", HP = "350K", Wins = "80", Cost = "Free"},
    {Index = 2, Id = "World002", WorldName = "Mushroom Forest", BossName = "Quartz Titan", HP = "36M", Wins = "31.25K", Cost = "1.6K"},
    {Index = 3, Id = "World003", WorldName = "Desert Pyramid", BossName = "Anubis King", HP = "2B", Wins = "6.25M", Cost = "1.25M"},
    {Index = 4, Id = "World004", WorldName = "Snow Land", BossName = "Veiled Vanguard", HP = "65B", Wins = "2B", Cost = "250M"},
    {Index = 5, Id = "World005", WorldName = "Underwater", BossName = "Frostplate Orc", HP = "2.4T", Wins = "666.6B", Cost = "100B"},
    {Index = 6, Id = "World006", WorldName = "Alien Desert", BossName = "Crimson Rhino", HP = "27T", Wins = "112.5T", Cost = "40T"},
    {Index = 7, Id = "World007", WorldName = "Candy", BossName = "Dungeon Samurai", HP = "480T", Wins = "25Qa", Cost = "9Qa"},
    {Index = 8, Id = "World008", WorldName = "Energy Factory", BossName = "Realm Knight", HP = "10Qa", Wins = "6.66Qi", Cost = "2.5Qi"},
    {Index = 9, Id = "World009", WorldName = "Altar", BossName = "Horned Warlord", HP = "300Qa", Wins = "1.57Sx", Cost = "800Qi"},
    {Index = 10, Id = "World010", WorldName = "Demon King", BossName = "Demon King", HP = "4.2Qi", Wins = "165Sx", Cost = "220Sx"},
    {Index = 11, Id = "World011", WorldName = "Heavenly Gates", BossName = "Azrael", HP = "15Sx", Wins = "1.66Sp", Cost = "44Sp"},
    {Index = 12, Id = "World012", WorldName = "Halls of Valhalla", BossName = "All-Father Odin", HP = "37.5Sp", Wins = "4.5Sp", Cost = "500Sp"},
    {Index = 13, Id = "World013", WorldName = "Voidfallen Kingdom", BossName = "Cthax'tha", HP = "5.62Oc", Wins = "15Sp", Cost = "1.5Oc"},
    {Index = 14, Id = "World014", WorldName = "Realm Monkey King", BossName = "Sun Wukong", HP = "56.2Oc", Wins = "35Sp", Cost = "2.5Oc"},
    {Index = 15, Id = "World015", WorldName = "Fractal Fortress", BossName = "Icon of Infinity", HP = "787Oc", Wins = "25.5Sp", Cost = "3.5Oc"},
    {Index = 16, Id = "World016", WorldName = "Timeless Cavern", BossName = "Sawblade Monarch", HP = "2.06No", Wins = "81.8Sp", Cost = "8.5Oc"},
}

-- Secret Boss Definition List
local SecretBossList = {
    {Id = "SecretBoss001", Name = "Tanjiro", RecPower = "2B", HP = "6B"},
    {Id = "SecretBoss002", Name = "Luffy Gear 5", RecPower = "200B", HP = "657B"},
    {Id = "SecretBoss003", Name = "Naruto", RecPower = "6T", HP = "24T"},
    {Id = "SecretBoss004", Name = "Asta Demonic", RecPower = "70T", HP = "277T"},
    {Id = "SecretBoss005", Name = "Rimuru Demon", RecPower = "1.6Qa", HP = "4.86Qa"},
    {Id = "SecretBoss006", Name = "Yuno Spirit", RecPower = "30Qa", HP = "100Qa"},
    {Id = "SecretBoss007", Name = "Heavenly Witness", RecPower = "4Sx", HP = "50Sx"},
    {Id = "SecretBoss008", Name = "Guardian Svartalheim", RecPower = "200Sx", HP = "5Sp"},
    {Id = "SecretBoss009", Name = "Blindseer Voluspa", RecPower = "1Sp", HP = "25Sp"},
    {Id = "SecretBoss010", Name = "Enraged Odin", RecPower = "7.5Sp", HP = "112.5Oc"},
    {Id = "SecretBoss011", Name = "Jonin Knight", RecPower = "200M", HP = "12M"},
}

-- Global Config & State
_G.RAS_BossConfig = {
    AutoKill = true,
    MultiHitBurst = 5,
    AutoWorldBoss = false,
    SelectedWorldIndex = 8,
    SelectedWorldId = "World008",
    AutoTeleportToWorld = true,
    AutoSecretBoss = false,
    SecretBossCycleAll = false,
    SelectedSecretBoss = "SecretBoss001",
    AutoTower = false,
    TowerAutoNext = true,
    FastAttack = true,
    TeleportBehind = true,
    FreezeBossAttack = true,
    AutoCloseRewards = true,
    AttackSpeed = 0.04,
}
local cfg = _G.RAS_BossConfig

local currentSpawn = DataConfig.GetData("SpawnWorld") or "World008"
for _, w in ipairs(WorldBossList) do
    if w.Id == currentSpawn then
        cfg.SelectedWorldIndex = w.Index
        cfg.SelectedWorldId = w.Id
        break
    end
end

-- Activity Logger
local logs = {}
local function addLog(msg)
    local timestamp = os.date("%X")
    local line = string.format("[%s] %s", timestamp, msg)
    table.insert(logs, 1, line)
    if #logs > 25 then table.remove(logs) end
    if _G.RAS_UpdateLogs then
        _G.RAS_UpdateLogs()
    end
end

-- Helper: Stop all character attack animations immediately
local function stopAllAttackTracks()
    pcall(function()
        AniModule.StopAllATKAnim()
        AniModule.CheckAutoPlayAttackAnim(false)
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChild("Humanoid")
        if hum and hum:FindFirstChild("Animator") then
            for _, track in ipairs(hum.Animator:GetPlayingAnimationTracks()) do
                if string.find(track.Name, "ATK") or string.find(track.Name, "Attack") then
                    track:Stop(0.1)
                end
            end
        end
    end)
end

-- Helper: Check if NPC in FightNpcs is genuinely alive
local function isNpcAlive(npc)
    if not npc or not npc.Parent or npc.Parent ~= FightNpcs then return false end
    if not npc:IsA("Model") then return false end

    -- Check Humanoid health if present
    local hum = npc:FindFirstChild("Humanoid")
    if hum and hum.Health <= 0 then return false end

    -- When an NPC dies, NpcModule attaches Monster_Death "emit" into Head
    local head = npc:FindFirstChild("Head")
    if head and head:FindFirstChild("emit") then
        return false
    end

    -- If death effect or marker exists, it's dead
    if npc:FindFirstChild("Monster_Death") then
        return false
    end

    return true
end

-- Helper: Get all currently alive NPCs
local function getAliveNpcs()
    local list = {}
    for _, npc in ipairs(FightNpcs:GetChildren()) do
        if isNpcAlive(npc) then
            table.insert(list, npc)
        end
    end
    return list
end

-- Helper: Get primary target (boss preferred)
local function getPrimaryTarget(npcs)
    if #npcs == 0 then return nil end
    
    -- 1. Prioritize the main Boss model (starts with "Npc" or contains "Boss")
    for _, npc in ipairs(npcs) do
        local name = npc.Name
        if string.find(name:lower(), "boss") or string.find(name, "^Npc") then
            return npc
        end
    end
    
    -- 2. Otherwise return first alive enemy (e.g. minion "1", "2")
    return npcs[1]
end

-- ═══════════════════════════════════════════════════════════════════
-- 2. GUI CREATION
-- ═══════════════════════════════════════════════════════════════════

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "RAS_BossHub_Gui"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Parent = GuiParent

-- Main Window
local MainWindow = Instance.new("Frame")
MainWindow.Name = "MainWindow"
MainWindow.Size = UDim2.new(0, 530, 0, 430)
MainWindow.Position = UDim2.new(0.5, -265, 0.5, -215)
MainWindow.BackgroundColor3 = Color3.fromRGB(16, 18, 27)
MainWindow.BorderSizePixel = 0
MainWindow.ClipsDescendants = true
MainWindow.Parent = ScreenGui

local WindowCorner = Instance.new("UICorner")
WindowCorner.CornerRadius = UDim.new(0, 10)
WindowCorner.Parent = MainWindow

local WindowStroke = Instance.new("UIStroke")
WindowStroke.Color = Color3.fromRGB(45, 52, 75)
WindowStroke.Thickness = 1.2
WindowStroke.Parent = MainWindow

-- Title Bar
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = Color3.fromRGB(22, 25, 38)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainWindow

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

local TitleBottomFix = Instance.new("Frame")
TitleBottomFix.Size = UDim2.new(1, 0, 0, 10)
TitleBottomFix.Position = UDim2.new(0, 0, 1, -10)
TitleBottomFix.BackgroundColor3 = Color3.fromRGB(22, 25, 38)
TitleBottomFix.BorderSizePixel = 0
TitleBottomFix.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "TitleLabel"
TitleLabel.Size = UDim2.new(1, -100, 1, 0)
TitleLabel.Position = UDim2.new(0, 14, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.Text = "🗡️ Reborn As Swordsman "
TitleLabel.TextColor3 = Color3.fromRGB(235, 240, 255)
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

local SubBadge = Instance.new("TextLabel")
SubBadge.Size = UDim2.new(0, 46, 0, 18)
SubBadge.Position = UDim2.new(0, 325, 0.5, -9)
SubBadge.BackgroundColor3 = Color3.fromRGB(239, 68, 68)
SubBadge.Text = "W1-16"
SubBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
SubBadge.Font = Enum.Font.GothamBold
SubBadge.TextSize = 9
SubBadge.Parent = TitleBar
local SubBadgeCorner = Instance.new("UICorner")
SubBadgeCorner.CornerRadius = UDim.new(0, 4)
SubBadgeCorner.Parent = SubBadge

-- Min & Close Buttons
local MinBtn = Instance.new("TextButton")
MinBtn.Name = "MinBtn"
MinBtn.Size = UDim2.new(0, 28, 0, 28)
MinBtn.Position = UDim2.new(1, -66, 0.5, -14)
MinBtn.BackgroundColor3 = Color3.fromRGB(33, 38, 56)
MinBtn.Text = "-"
MinBtn.TextColor3 = Color3.fromRGB(200, 210, 230)
MinBtn.Font = Enum.Font.GothamBold
MinBtn.TextSize = 16
MinBtn.Parent = TitleBar
local MinCorner = Instance.new("UICorner")
MinCorner.CornerRadius = UDim.new(0, 6)
MinCorner.Parent = MinBtn

local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 28, 0, 28)
CloseBtn.Position = UDim2.new(1, -34, 0.5, -14)
CloseBtn.BackgroundColor3 = Color3.fromRGB(75, 25, 35)
CloseBtn.Text = "✕"
CloseBtn.TextColor3 = Color3.fromRGB(255, 120, 130)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 12
CloseBtn.Parent = TitleBar
local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

-- Floating Open Pill Button
local FloatingPill = Instance.new("TextButton")
FloatingPill.Name = "FloatingPill"
FloatingPill.Size = UDim2.new(0, 135, 0, 34)
FloatingPill.Position = UDim2.new(0, 20, 0.2, 0)
FloatingPill.BackgroundColor3 = Color3.fromRGB(22, 25, 38)
FloatingPill.Text = "👑 Boss Hub (1-16)"
FloatingPill.TextColor3 = Color3.fromRGB(248, 113, 113)
FloatingPill.Font = Enum.Font.GothamBold
FloatingPill.TextSize = 12
FloatingPill.Visible = false
FloatingPill.Parent = ScreenGui

local PillCorner = Instance.new("UICorner")
PillCorner.CornerRadius = UDim.new(0, 17)
PillCorner.Parent = FloatingPill

local PillStroke = Instance.new("UIStroke")
PillStroke.Color = Color3.fromRGB(239, 68, 68)
PillStroke.Thickness = 1.5
PillStroke.Parent = FloatingPill

-- Dragging
local function makeDraggable(topbar, object)
    local dragging, dragInput, dragStart, startPos
    topbar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = object.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    topbar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if input == dragInput and dragging then
            local delta = input.Position - dragStart
            object.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

makeDraggable(TitleBar, MainWindow)
makeDraggable(FloatingPill, FloatingPill)

local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        MainWindow.Size = UDim2.new(0, 530, 0, 42)
        MinBtn.Text = "+"
    else
        MainWindow.Size = UDim2.new(0, 530, 0, 430)
        MinBtn.Text = "-"
    end
end)

CloseBtn.MouseButton1Click:Connect(function()
    MainWindow.Visible = false
    FloatingPill.Visible = true
end)

FloatingPill.MouseButton1Click:Connect(function()
    MainWindow.Visible = true
    FloatingPill.Visible = false
end)

UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.RightShift) then
        MainWindow.Visible = not MainWindow.Visible
        FloatingPill.Visible = not MainWindow.Visible
    end
end)

-- Sidebar & Content
local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Size = UDim2.new(0, 130, 1, -42)
Sidebar.Position = UDim2.new(0, 0, 0, 42)
Sidebar.BackgroundColor3 = Color3.fromRGB(19, 21, 32)
Sidebar.BorderSizePixel = 0
Sidebar.Parent = MainWindow

local SidebarLayout = Instance.new("UIListLayout")
SidebarLayout.Padding = UDim.new(0, 4)
SidebarLayout.FillDirection = Enum.FillDirection.Vertical
SidebarLayout.SortOrder = Enum.SortOrder.LayoutOrder
SidebarLayout.Parent = Sidebar

local SidebarPad = Instance.new("UIPadding")
SidebarPad.PaddingTop = UDim.new(0, 10)
SidebarPad.PaddingLeft = UDim.new(0, 8)
SidebarPad.PaddingRight = UDim.new(0, 8)
SidebarPad.Parent = Sidebar

local ContentArea = Instance.new("Frame")
ContentArea.Name = "ContentArea"
ContentArea.Size = UDim2.new(1, -138, 1, -46)
ContentArea.Position = UDim2.new(0, 134, 0, 44)
ContentArea.BackgroundTransparency = 1
ContentArea.Parent = MainWindow

local Tabs = {}
local TabButtons = {}
local activeTab = nil

local function switchTab(id)
    for k, f in pairs(Tabs) do
        local isTarget = (k == id)
        f.Visible = isTarget
        if TabButtons[k] then
            if isTarget then
                TabButtons[k].BackgroundColor3 = Color3.fromRGB(99, 102, 241)
                TabButtons[k].TextColor3 = Color3.fromRGB(255, 255, 255)
                TabButtons[k].Font = Enum.Font.GothamBold
            else
                TabButtons[k].BackgroundColor3 = Color3.fromRGB(24, 27, 40)
                TabButtons[k].TextColor3 = Color3.fromRGB(150, 160, 185)
                TabButtons[k].Font = Enum.Font.GothamMedium
            end
        end
    end
    activeTab = id
end

local function createTab(id, label, icon, order)
    local tabFrame = Instance.new("ScrollingFrame")
    tabFrame.Name = "Tab_" .. id
    tabFrame.Size = UDim2.new(1, 0, 1, 0)
    tabFrame.BackgroundTransparency = 1
    tabFrame.BorderSizePixel = 0
    tabFrame.ScrollBarThickness = 4
    tabFrame.ScrollBarImageColor3 = Color3.fromRGB(60, 68, 98)
    tabFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    tabFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    tabFrame.Visible = false
    tabFrame.Parent = ContentArea

    local tabLayout = Instance.new("UIListLayout")
    tabLayout.Padding = UDim.new(0, 8)
    tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
    tabLayout.Parent = tabFrame

    local tabPad = Instance.new("UIPadding")
    tabPad.PaddingTop = UDim.new(0, 6)
    tabPad.PaddingBottom = UDim.new(0, 12)
    tabPad.PaddingLeft = UDim.new(0, 6)
    tabPad.PaddingRight = UDim.new(0, 10)
    tabPad.Parent = tabFrame

    local tabBtn = Instance.new("TextButton")
    tabBtn.Name = "TabBtn_" .. id
    tabBtn.Size = UDim2.new(1, 0, 0, 34)
    tabBtn.BackgroundColor3 = Color3.fromRGB(24, 27, 40)
    tabBtn.Text = icon .. " " .. label
    tabBtn.TextColor3 = Color3.fromRGB(150, 160, 185)
    tabBtn.Font = Enum.Font.GothamMedium
    tabBtn.TextSize = 12
    tabBtn.LayoutOrder = order
    tabBtn.Parent = Sidebar

    local btnCorner = Instance.new("UICorner")
    btnCorner.CornerRadius = UDim.new(0, 6)
    btnCorner.Parent = tabBtn

    Tabs[id] = tabFrame
    TabButtons[id] = tabBtn

    tabBtn.MouseButton1Click:Connect(function()
        switchTab(id)
    end)

    return tabFrame
end

local function createCard(parent, title, desc, highlight)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 52)
    card.BackgroundColor3 = highlight and Color3.fromRGB(30, 25, 42) or Color3.fromRGB(22, 25, 38)
    card.BorderSizePixel = 0
    card.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = highlight and Color3.fromRGB(168, 85, 247) or Color3.fromRGB(36, 42, 64)
    stroke.Thickness = highlight and 1.3 or 1
    stroke.Parent = card

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -70, 0, 20)
    lbl.Position = UDim2.new(0, 12, 0, 8)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = title
    lbl.TextColor3 = highlight and Color3.fromRGB(245, 208, 254) or Color3.fromRGB(220, 230, 250)
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = card

    if desc then
        local sub = Instance.new("TextLabel")
        sub.Size = UDim2.new(1, -70, 0, 16)
        sub.Position = UDim2.new(0, 12, 0, 28)
        sub.BackgroundTransparency = 1
        sub.Font = Enum.Font.Gotham
        sub.Text = desc
        sub.TextColor3 = Color3.fromRGB(125, 135, 165)
        sub.TextSize = 11
        sub.TextXAlignment = Enum.TextXAlignment.Left
        sub.Parent = card
    end

    return card
end

local function addToggle(card, initialValue, onToggle)
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Size = UDim2.new(0, 44, 0, 24)
    toggleBtn.Position = UDim2.new(1, -54, 0.5, -12)
    toggleBtn.BackgroundColor3 = initialValue and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(40, 45, 65)
    toggleBtn.Text = ""
    toggleBtn.Parent = card

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = toggleBtn

    local indicator = Instance.new("Frame")
    indicator.Size = UDim2.new(0, 18, 0, 18)
    indicator.Position = initialValue and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)
    indicator.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    indicator.BorderSizePixel = 0
    indicator.Parent = toggleBtn

    local indCorner = Instance.new("UICorner")
    indCorner.CornerRadius = UDim.new(0, 9)
    indCorner.Parent = indicator

    local state = initialValue

    toggleBtn.MouseButton1Click:Connect(function()
        state = not state
        local targetColor = state and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(40, 45, 65)
        local targetPos = state and UDim2.new(1, -21, 0.5, -9) or UDim2.new(0, 3, 0.5, -9)

        TweenService:Create(toggleBtn, TweenInfo.new(0.2), {BackgroundColor3 = targetColor}):Play()
        TweenService:Create(indicator, TweenInfo.new(0.2), {Position = targetPos}):Play()

        onToggle(state)
    end)

    return toggleBtn
end

-- ═══════════════════════════════════════════════════════════════════
-- 3. POPULATE TABS
-- ═══════════════════════════════════════════════════════════════════

-- TAB 1: World Boss (Stage 1-16 Selection)
local TabWorld = createTab("world", "World Boss", "👑", 1)

local SelectedBossCard = Instance.new("Frame")
SelectedBossCard.Size = UDim2.new(1, 0, 0, 58)
SelectedBossCard.BackgroundColor3 = Color3.fromRGB(26, 30, 46)
SelectedBossCard.BorderSizePixel = 0
SelectedBossCard.Parent = TabWorld

local SBCorner = Instance.new("UICorner")
SBCorner.CornerRadius = UDim.new(0, 8)
SBCorner.Parent = SelectedBossCard

local SBStroke = Instance.new("UIStroke")
SBStroke.Color = Color3.fromRGB(99, 102, 241)
SBStroke.Thickness = 1.2
SBStroke.Parent = SelectedBossCard

local SBTitle = Instance.new("TextLabel")
SBTitle.Size = UDim2.new(1, -16, 0, 24)
SBTitle.Position = UDim2.new(0, 10, 0, 6)
SBTitle.BackgroundTransparency = 1
SBTitle.Font = Enum.Font.GothamBold
SBTitle.Text = "Target: World 8 (Realm Knight)"
SBTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
SBTitle.TextSize = 13
SBTitle.TextXAlignment = Enum.TextXAlignment.Left
SBTitle.Parent = SelectedBossCard

local SBSub = Instance.new("TextLabel")
SBSub.Size = UDim2.new(1, -16, 0, 18)
SBSub.Position = UDim2.new(0, 10, 0, 32)
SBSub.BackgroundTransparency = 1
SBSub.Font = Enum.Font.Gotham
SBSub.Text = "HP: 10Qa | Reward: 6.66Qi Wins"
SBSub.TextColor3 = Color3.fromRGB(165, 180, 252)
SBSub.TextSize = 11
SBSub.TextXAlignment = Enum.TextXAlignment.Left
SBSub.Parent = SelectedBossCard

local WorldSelectorLabel = Instance.new("TextLabel")
WorldSelectorLabel.Size = UDim2.new(1, 0, 0, 18)
WorldSelectorLabel.BackgroundTransparency = 1
WorldSelectorLabel.Font = Enum.Font.GothamBold
WorldSelectorLabel.Text = "SELECT WORLD BOSS (1-16):"
WorldSelectorLabel.TextColor3 = Color3.fromRGB(170, 185, 220)
WorldSelectorLabel.TextSize = 11
WorldSelectorLabel.TextXAlignment = Enum.TextXAlignment.Left
WorldSelectorLabel.Parent = TabWorld

local WorldContainer = Instance.new("Frame")
WorldContainer.Size = UDim2.new(1, 0, 0, 150)
WorldContainer.BackgroundColor3 = Color3.fromRGB(20, 23, 34)
WorldContainer.BorderSizePixel = 0
WorldContainer.Parent = TabWorld

local WCCorner = Instance.new("UICorner")
WCCorner.CornerRadius = UDim.new(0, 8)
WCCorner.Parent = WorldContainer

local WorldScroll = Instance.new("ScrollingFrame")
WorldScroll.Size = UDim2.new(1, -8, 1, -8)
WorldScroll.Position = UDim2.new(0, 4, 0, 4)
WorldScroll.BackgroundTransparency = 1
WorldScroll.ScrollBarThickness = 4
WorldScroll.ScrollBarImageColor3 = Color3.fromRGB(70, 80, 110)
WorldScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
WorldScroll.Parent = WorldContainer

local WorldScrollLayout = Instance.new("UIListLayout")
WorldScrollLayout.Padding = UDim.new(0, 4)
WorldScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
WorldScrollLayout.Parent = WorldScroll

local worldBtnList = {}

local function updateSelectedWorldUI(wData)
    cfg.SelectedWorldIndex = wData.Index
    cfg.SelectedWorldId = wData.Id
    
    local unlockedWorlds = DataConfig.GetData("Worlds") or {}
    local isUnlocked = table.find(unlockedWorlds, wData.Id) ~= nil
    local statusStr = isUnlocked and "✓ UNLOCKED" or string.format("🔒 Cost: %s", wData.Cost)

    SBTitle.Text = string.format("Target: World %d - %s [%s]", wData.Index, wData.WorldName, statusStr)
    SBSub.Text = string.format("👑 Boss: %s | HP: %s | Wins: %s", wData.BossName, wData.HP, wData.Wins)

    for otherIndex, otherBtn in pairs(worldBtnList) do
        local isSel = (otherIndex == wData.Index)
        otherBtn.BackgroundColor3 = isSel and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(28, 32, 48)
        otherBtn.TextColor3 = isSel and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 200, 225)
    end
end

for _, wData in ipairs(WorldBossList) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -6, 0, 30)
    btn.BackgroundColor3 = (cfg.SelectedWorldIndex == wData.Index) and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(28, 32, 48)
    btn.Text = string.format(" [W%02d] %s • Boss: %s (HP: %s)", wData.Index, wData.WorldName, wData.BossName, wData.HP)
    btn.TextColor3 = (cfg.SelectedWorldIndex == wData.Index) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 200, 225)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.LayoutOrder = wData.Index
    btn.Parent = WorldScroll

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 6)
    bCorner.Parent = btn

    worldBtnList[wData.Index] = btn

    btn.MouseButton1Click:Connect(function()
        updateSelectedWorldUI(wData)
        addLog(string.format("Selected World %d: %s (%s)", wData.Index, wData.WorldName, wData.BossName))
    end)
end

for _, w in ipairs(WorldBossList) do
    if w.Index == cfg.SelectedWorldIndex then
        updateSelectedWorldUI(w)
        break
    end
end

local CardAutoKill = createCard(TabWorld, "⚡ Auto Kill (Insta-Melt)", "Massive multi-hit burst to delete all waves & bosses instantly", true)
addToggle(CardAutoKill, cfg.AutoKill, function(val)
    cfg.AutoKill = val
    addLog("Auto Kill: " .. (val and "ENABLED (Instant)" or "DISABLED"))
end)

local CardWorldBoss = createCard(TabWorld, "Auto Challenge Selected World", "Auto teleports & loops selected world boss (Wave 1-7)")
addToggle(CardWorldBoss, cfg.AutoWorldBoss, function(val)
    cfg.AutoWorldBoss = val
    if not val then
        stopAllAttackTracks()
    end
    addLog(val and string.format("Auto World %d Boss enabled", cfg.SelectedWorldIndex) or "Auto World Boss disabled")
end)

local CardAutoTP = createCard(TabWorld, "Auto Teleport To Selected World", "Ensures you are in the selected world before challenging")
addToggle(CardAutoTP, cfg.AutoTeleportToWorld, function(val)
    cfg.AutoTeleportToWorld = val
    addLog("Auto TP to world: " .. tostring(val))
end)

local CardTeleport = createCard(TabWorld, "Continuous Magnet (Stick Behind)", "Glues you smoothly behind the active target at 60/120 FPS")
addToggle(CardTeleport, cfg.TeleportBehind, function(val)
    cfg.TeleportBehind = val
    addLog("Continuous Magnet: " .. tostring(val))
end)

local ActionRow = Instance.new("Frame")
ActionRow.Size = UDim2.new(1, 0, 0, 36)
ActionRow.BackgroundTransparency = 1
ActionRow.Parent = TabWorld

local TPWorldBtn = Instance.new("TextButton")
TPWorldBtn.Size = UDim2.new(0.48, 0, 1, 0)
TPWorldBtn.BackgroundColor3 = Color3.fromRGB(76, 81, 191)
TPWorldBtn.Text = "🚀 Teleport To World"
TPWorldBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TPWorldBtn.Font = Enum.Font.GothamBold
TPWorldBtn.TextSize = 11
TPWorldBtn.Parent = ActionRow
local TPCorner = Instance.new("UICorner")
TPCorner.CornerRadius = UDim.new(0, 8)
TPCorner.Parent = TPWorldBtn

TPWorldBtn.MouseButton1Click:Connect(function()
    local unlocked = DataConfig.GetData("Worlds") or {}
    if table.find(unlocked, cfg.SelectedWorldId) then
        addLog("Teleporting to " .. cfg.SelectedWorldId .. "...")
        WorldManager.TeleportToWorld(cfg.SelectedWorldId)
    else
        addLog("World not unlocked yet!")
        WorldManager.UnlockWorld(cfg.SelectedWorldId)
    end
end)

local DirectBossBtn = Instance.new("TextButton")
DirectBossBtn.Size = UDim2.new(0.48, 0, 1, 0)
DirectBossBtn.Position = UDim2.new(0.52, 0, 0, 0)
DirectBossBtn.BackgroundColor3 = Color3.fromRGB(49, 130, 206)
DirectBossBtn.Text = "⚡ Challenge Boss Now"
DirectBossBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DirectBossBtn.Font = Enum.Font.GothamBold
DirectBossBtn.TextSize = 11
DirectBossBtn.Parent = ActionRow
local DirectCorner = Instance.new("UICorner")
DirectCorner.CornerRadius = UDim.new(0, 8)
DirectCorner.Parent = DirectBossBtn

DirectBossBtn.MouseButton1Click:Connect(function()
    if not DataConfig.LocalData.Fighting then
        local currentSpawn = DataConfig.GetData("SpawnWorld")
        if currentSpawn ~= cfg.SelectedWorldId then
            addLog("Switching to " .. cfg.SelectedWorldId .. "...")
            WorldManager.TeleportToWorld(cfg.SelectedWorldId)
            task.wait(1.5)
        end
        addLog(string.format("Starting World %d Challenge...", cfg.SelectedWorldIndex))
        Events.Fight.Re_ChallengeStart:FireServer(1)
    else
        addLog("Already fighting!")
    end
end)

-- TAB 2: Secret Boss
local TabSecret = createTab("secret", "Secret Boss", "🔮", 2)

local CardSecretAutoKill = createCard(TabSecret, "⚡ Auto Kill Secret Boss", "Instantly eliminates Secret Boss upon spawn", true)
addToggle(CardSecretAutoKill, cfg.AutoKill, function(val)
    cfg.AutoKill = val
    addLog("Auto Kill: " .. tostring(val))
end)

local CardSecretBoss = createCard(TabSecret, "Auto Farm Selected Secret Boss", "Auto starts selected boss when cooldown reaches 0")
addToggle(CardSecretBoss, cfg.AutoSecretBoss, function(val)
    cfg.AutoSecretBoss = val
    if not val then
        stopAllAttackTracks()
    end
    addLog("Auto Secret Boss: " .. tostring(val))
end)

local CardCycleAll = createCard(TabSecret, "Auto Cycle All Available Bosses", "Fights any ready Secret Boss in sequence")
addToggle(CardCycleAll, cfg.SecretBossCycleAll, function(val)
    cfg.SecretBossCycleAll = val
    addLog("Cycle All Secret Bosses: " .. tostring(val))
end)

local SelectorHeader = Instance.new("TextLabel")
SelectorHeader.Size = UDim2.new(1, 0, 0, 20)
SelectorHeader.BackgroundTransparency = 1
SelectorHeader.Font = Enum.Font.GothamBold
SelectorHeader.Text = "SELECT TARGET SECRET BOSS:"
SelectorHeader.TextColor3 = Color3.fromRGB(170, 185, 220)
SelectorHeader.TextSize = 11
SelectorHeader.TextXAlignment = Enum.TextXAlignment.Left
SelectorHeader.Parent = TabSecret

local BossButtonsContainer = Instance.new("Frame")
BossButtonsContainer.Size = UDim2.new(1, 0, 0, 160)
BossButtonsContainer.BackgroundColor3 = Color3.fromRGB(20, 23, 34)
BossButtonsContainer.BorderSizePixel = 0
BossButtonsContainer.Parent = TabSecret

local BBCorner = Instance.new("UICorner")
BBCorner.CornerRadius = UDim.new(0, 8)
BBCorner.Parent = BossButtonsContainer

local BossScroll = Instance.new("ScrollingFrame")
BossScroll.Size = UDim2.new(1, -8, 1, -8)
BossScroll.Position = UDim2.new(0, 4, 0, 4)
BossScroll.BackgroundTransparency = 1
BossScroll.ScrollBarThickness = 4
BossScroll.ScrollBarImageColor3 = Color3.fromRGB(70, 80, 110)
BossScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
BossScroll.Parent = BossButtonsContainer

local BossScrollLayout = Instance.new("UIListLayout")
BossScrollLayout.Padding = UDim.new(0, 4)
BossScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
BossScrollLayout.Parent = BossScroll

local bossBtnList = {}

for idx, bData in ipairs(SecretBossList) do
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -6, 0, 32)
    btn.BackgroundColor3 = (cfg.SelectedSecretBoss == bData.Id) and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(28, 32, 48)
    btn.Text = string.format(" %s (%s) • HP: %s | Rec: %s", bData.Name, bData.Id, bData.HP, bData.RecPower)
    btn.TextColor3 = (cfg.SelectedSecretBoss == bData.Id) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 200, 225)
    btn.Font = Enum.Font.GothamMedium
    btn.TextSize = 11
    btn.TextXAlignment = Enum.TextXAlignment.Left
    btn.LayoutOrder = idx
    btn.Parent = BossScroll

    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 6)
    bCorner.Parent = btn

    bossBtnList[bData.Id] = btn

    btn.MouseButton1Click:Connect(function()
        cfg.SelectedSecretBoss = bData.Id
        addLog("Selected boss: " .. bData.Name)
        for otherId, otherBtn in pairs(bossBtnList) do
            local isSel = (otherId == bData.Id)
            otherBtn.BackgroundColor3 = isSel and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(28, 32, 48)
            otherBtn.TextColor3 = isSel and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(190, 200, 225)
        end
    end)
end

local ChallengeSecretBtn = Instance.new("TextButton")
ChallengeSecretBtn.Size = UDim2.new(1, 0, 0, 36)
ChallengeSecretBtn.BackgroundColor3 = Color3.fromRGB(128, 90, 213)
ChallengeSecretBtn.Text = "🔮 Challenge Selected Secret Boss Now"
ChallengeSecretBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
ChallengeSecretBtn.Font = Enum.Font.GothamBold
ChallengeSecretBtn.TextSize = 12
ChallengeSecretBtn.Parent = TabSecret

local CSBCorner = Instance.new("UICorner")
CSBCorner.CornerRadius = UDim.new(0, 8)
CSBCorner.Parent = ChallengeSecretBtn

ChallengeSecretBtn.MouseButton1Click:Connect(function()
    if not DataConfig.LocalData.Fighting then
        addLog("Manual Challenge Secret Boss: " .. cfg.SelectedSecretBoss)
        Events.Relics.Re_Start:FireServer(cfg.SelectedSecretBoss)
    else
        addLog("Already fighting!")
    end
end)

-- TAB 3: Tower
local TabTower = createTab("tower", "Tower", "🗼", 3)

local CardTowerKill = createCard(TabTower, "⚡ Auto Kill Tower Mobs", "Instantly clears every Tower floor as it loads", true)
addToggle(CardTowerKill, cfg.AutoKill, function(val)
    cfg.AutoKill = val
    addLog("Tower Auto Kill: " .. tostring(val))
end)

local CardTowerNext = createCard(TabTower, "⏩ Auto Next Floor (Instant Climb)", "Instantly teleports to Next Floor portal when floor is cleared", true)
addToggle(CardTowerNext, cfg.TowerAutoNext, function(val)
    cfg.TowerAutoNext = val
    addLog("Tower Auto Next Floor: " .. tostring(val))
end)

local CardTower = createCard(TabTower, "Auto Challenge Tower Loop", "Continuously climbs all Tower floors endlessly")
addToggle(CardTower, cfg.AutoTower, function(val)
    cfg.AutoTower = val
    if not val then
        stopAllAttackTracks()
    end
    addLog("Auto Tower Loop: " .. tostring(val))
end)

local TowerBtn = Instance.new("TextButton")
TowerBtn.Size = UDim2.new(1, 0, 0, 36)
TowerBtn.BackgroundColor3 = Color3.fromRGB(56, 161, 105)
TowerBtn.Text = "🗼 Challenge / Next Tower Floor Now"
TowerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TowerBtn.Font = Enum.Font.GothamBold
TowerBtn.TextSize = 12
TowerBtn.Parent = TabTower

local TBCorner = Instance.new("UICorner")
TBCorner.CornerRadius = UDim.new(0, 8)
TBCorner.Parent = TowerBtn

TowerBtn.MouseButton1Click:Connect(function()
    local tt = workspace:FindFirstChild("TowerTeleport")
    if tt and tt:FindFirstChild("Next") then
        addLog("Advancing to next floor...")
        local char = LocalPlayer.Character
        if char and char:FindFirstChild("HumanoidRootPart") then
            char:PivotTo(tt.Next.CFrame * CFrame.new(0, 3, 0))
        end
        Events.Tower.Re_Challenge:FireServer()
        pcall(function() TowerManager.CheckMovetoNext() end)
    elseif not DataConfig.LocalData.Fighting then
        addLog("Manual Tower Challenge...")
        Events.Tower.Re_Challenge:FireServer(true)
    else
        addLog("Floor in progress!")
    end
end)

-- TAB 4: Combat Settings & Auto Kill Multipliers
local TabSettings = createTab("settings", "Combat & Misc", "⚡", 4)

local CardBurst = createCard(TabSettings, "🔥 Multi-Hit Burst Multiplier", "Hits per tick (Current: " .. tostring(cfg.MultiHitBurst) .. "x hits)")
local burstBtn1 = Instance.new("TextButton")
burstBtn1.Size = UDim2.new(0, 36, 0, 24)
burstBtn1.Position = UDim2.new(1, -125, 0.5, -12)
burstBtn1.BackgroundColor3 = (cfg.MultiHitBurst == 2) and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(40, 45, 65)
burstBtn1.Text = "2x"
burstBtn1.TextColor3 = Color3.fromRGB(255, 255, 255)
burstBtn1.Font = Enum.Font.GothamBold
burstBtn1.TextSize = 11
burstBtn1.Parent = CardBurst
local bc1 = Instance.new("UICorner")
bc1.CornerRadius = UDim.new(0, 6)
bc1.Parent = burstBtn1

local burstBtn2 = Instance.new("TextButton")
burstBtn2.Size = UDim2.new(0, 36, 0, 24)
burstBtn2.Position = UDim2.new(1, -85, 0.5, -12)
burstBtn2.BackgroundColor3 = (cfg.MultiHitBurst == 5) and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(40, 45, 65)
burstBtn2.Text = "5x"
burstBtn2.TextColor3 = Color3.fromRGB(255, 255, 255)
burstBtn2.Font = Enum.Font.GothamBold
burstBtn2.TextSize = 11
burstBtn2.Parent = CardBurst
local bc2 = Instance.new("UICorner")
bc2.CornerRadius = UDim.new(0, 6)
bc2.Parent = burstBtn2

local burstBtn3 = Instance.new("TextButton")
burstBtn3.Size = UDim2.new(0, 36, 0, 24)
burstBtn3.Position = UDim2.new(1, -45, 0.5, -12)
burstBtn3.BackgroundColor3 = (cfg.MultiHitBurst == 10) and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(40, 45, 65)
burstBtn3.Text = "10x"
burstBtn3.TextColor3 = Color3.fromRGB(255, 255, 255)
burstBtn3.Font = Enum.Font.GothamBold
burstBtn3.TextSize = 11
burstBtn3.Parent = CardBurst
local bc3 = Instance.new("UICorner")
bc3.CornerRadius = UDim.new(0, 6)
bc3.Parent = burstBtn3

local function updateBurstBtns()
    burstBtn1.BackgroundColor3 = (cfg.MultiHitBurst == 2) and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(40, 45, 65)
    burstBtn2.BackgroundColor3 = (cfg.MultiHitBurst == 5) and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(40, 45, 65)
    burstBtn3.BackgroundColor3 = (cfg.MultiHitBurst == 10) and Color3.fromRGB(99, 102, 241) or Color3.fromRGB(40, 45, 65)
end

burstBtn1.MouseButton1Click:Connect(function() cfg.MultiHitBurst = 2 updateBurstBtns() addLog("Burst set to 2x") end)
burstBtn2.MouseButton1Click:Connect(function() cfg.MultiHitBurst = 5 updateBurstBtns() addLog("Burst set to 5x") end)
burstBtn3.MouseButton1Click:Connect(function() cfg.MultiHitBurst = 10 updateBurstBtns() addLog("Burst set to 10x") end)

local CardFreeze = createCard(TabSettings, "🛡️ Freeze Boss Attack (God Mode)", "Prevents bosses & enemies from hitting you back")
addToggle(CardFreeze, cfg.FreezeBossAttack, function(val)
    cfg.FreezeBossAttack = val
    addLog("Freeze Boss Attack: " .. tostring(val))
end)

local CardCloseRewards = createCard(TabSettings, "Auto Close Reward Popups", "Automatically hides BossReward & victory dialogs")
addToggle(CardCloseRewards, cfg.AutoCloseRewards, function(val)
    cfg.AutoCloseRewards = val
    addLog("Auto Close Rewards: " .. tostring(val))
end)

-- TAB 5: Stats & Log
local TabLogs = createTab("logs", "Stats & Log", "📊", 5)

local StatsCard = Instance.new("Frame")
StatsCard.Size = UDim2.new(1, 0, 0, 64)
StatsCard.BackgroundColor3 = Color3.fromRGB(22, 25, 38)
StatsCard.BorderSizePixel = 0
StatsCard.Parent = TabLogs
local SCCorner = Instance.new("UICorner")
SCCorner.CornerRadius = UDim.new(0, 8)
SCCorner.Parent = StatsCard

local StatLabel = Instance.new("TextLabel")
StatLabel.Size = UDim2.new(1, -16, 1, -8)
StatLabel.Position = UDim2.new(0, 10, 0, 4)
StatLabel.BackgroundTransparency = 1
StatLabel.Font = Enum.Font.Gotham
StatLabel.Text = "Loading stats..."
StatLabel.TextColor3 = Color3.fromRGB(200, 215, 240)
StatLabel.TextSize = 11
StatLabel.TextXAlignment = Enum.TextXAlignment.Left
StatLabel.TextYAlignment = Enum.TextYAlignment.Center
StatLabel.Parent = StatsCard

local LogBox = Instance.new("ScrollingFrame")
LogBox.Size = UDim2.new(1, 0, 0, 190)
LogBox.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
LogBox.BorderSizePixel = 0
LogBox.ScrollBarThickness = 4
LogBox.ScrollBarImageColor3 = Color3.fromRGB(60, 68, 98)
LogBox.AutomaticCanvasSize = Enum.AutomaticSize.Y
LogBox.Parent = TabLogs
local LBCorner = Instance.new("UICorner")
LBCorner.CornerRadius = UDim.new(0, 8)
LBCorner.Parent = LogBox

local LogLayout = Instance.new("UIListLayout")
LogLayout.Padding = UDim.new(0, 2)
LogLayout.SortOrder = Enum.SortOrder.LayoutOrder
LogLayout.Parent = LogBox

local LogPad = Instance.new("UIPadding")
LogPad.PaddingLeft = UDim.new(0, 8)
LogPad.PaddingRight = UDim.new(0, 8)
LogPad.PaddingTop = UDim.new(0, 6)
LogPad.Parent = LogBox

local function refreshLogs()
    for _, child in ipairs(LogBox:GetChildren()) do
        if child:IsA("TextLabel") then child:Destroy() end
    end
    for _, line in ipairs(logs) do
        local l = Instance.new("TextLabel")
        l.Size = UDim2.new(1, 0, 0, 18)
        l.BackgroundTransparency = 1
        l.Font = Enum.Font.Code
        l.Text = line
        l.TextColor3 = Color3.fromRGB(160, 175, 200)
        l.TextSize = 10
        l.TextXAlignment = Enum.TextXAlignment.Left
        l.Parent = LogBox
    end
end
_G.RAS_UpdateLogs = refreshLogs

-- Open World tab by default
switchTab("world")

-- ═══════════════════════════════════════════════════════════════════
-- 4. CONTINUOUS MAGNET & SMART ATTACK ENGINE
-- ═══════════════════════════════════════════════════════════════════

-- A. 🧲 CONTINUOUS MAGNET (Runs on every physics Heartbeat frame)
local magnetConnection
magnetConnection = RunService.Heartbeat:Connect(function()
    if not ScreenGui.Parent then
        if magnetConnection then magnetConnection:Disconnect() end
        return
    end

    local char = LocalPlayer.Character
    if not cfg.TeleportBehind then
        -- Restore collision when magnet is disabled
        if char then
            for _, p in ipairs(char:GetChildren()) do
                if p:IsA("BasePart") and not p.CanCollide then
                    p.CanCollide = true
                end
            end
        end
        return
    end

    local aliveNpcs = getAliveNpcs()
    if #aliveNpcs == 0 then return end

    local target = getPrimaryTarget(aliveNpcs)
    if not target then return end

    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local targetPart = target.PrimaryPart or target:FindFirstChild("HumanoidRootPart") or target:FindFirstChild("UpperTorso") or target:FindFirstChild("Torso") or target:FindFirstChildWhichIsA("BasePart")
    if not targetPart then return end

    -- Disable collision on character parts to prevent fling/bounce
    for _, p in ipairs(char:GetChildren()) do
        if p:IsA("BasePart") and p.CanCollide then
            p.CanCollide = false
        end
    end

    -- Calculate distance behind boss based on boss model size
    local size = target:GetExtentsSize()
    local depth = math.max(2.5, math.min(size.Z / 2 + 1.2, 5.5))

    local targetPos = targetPart.Position
    local behindOffset = targetPart.CFrame.LookVector * -depth
    local newPos = Vector3.new(targetPos.X + behindOffset.X, targetPos.Y, targetPos.Z + behindOffset.Z)
    char:PivotTo(CFrame.lookAt(newPos, targetPos))

    -- Zero velocities to eliminate jitter and bounce
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.AssemblyAngularVelocity = Vector3.zero
end)
_G.RAS_MagnetConn = magnetConnection

-- B. ⚡ SMART AUTO KILL & RAPID HIT LOOP (Stops immediately when boss dies or AutoKill disabled)
task.spawn(function()
    while ScreenGui.Parent do
        local delayTime = cfg.AttackSpeed or 0.04
        task.wait(delayTime)

        -- AutoKill is the master switch — if it's off, stop attacking entirely
        if not cfg.AutoKill then
            stopAllAttackTracks()
            task.wait(0.2)
            goto continue
        end

        local aliveNpcs = getAliveNpcs()

        if #aliveNpcs > 0 then
            pcall(function()
                -- FastAttack = true → multi-hit burst; false → single hit per tick
                local burstCount = cfg.FastAttack and (cfg.MultiHitBurst or 5) or 1

                for _, npc in ipairs(aliveNpcs) do
                    -- Freeze Enemy Attack Time
                    if cfg.FreezeBossAttack then
                        local atkTime = npc:FindFirstChild("AttackTime")
                        if atkTime and atkTime:IsA("NumberValue") then
                            atkTime.Value = 999999
                        end
                    end

                    local mapVal = npc:FindFirstChild("Map")
                    local mapType = (mapVal and mapVal.Value ~= "" and mapVal.Value) or "Dungeon"

                    if mapType == "Dungeon" then
                        for b = 1, burstCount do
                            Events.Fight.Re_TakeDamage:FireServer(npc.Name, (b % 4) + 1)
                        end
                    elseif mapType == "SecretBoss" then
                        for b = 1, burstCount do
                            Events.Relics.Re_TakeDamage:FireServer((b % 4) + 1)
                        end
                    elseif mapType == "Tower" then
                        for b = 1, burstCount do
                            Events.Tower.Re_TakeDamage:FireServer((b % 4) + 1)
                        end
                    else
                        for b = 1, burstCount do
                            Events.Fight.Re_TakeDamage:FireServer(npc.Name, (b % 4) + 1)
                            Events.Relics.Re_TakeDamage:FireServer((b % 4) + 1)
                        end
                    end
                end

                -- Visually slash with weapon!
                AniModule.PlayAtkAnim()

                -- Ensure sword animation is actively swinging
                local anyAtkPlaying = false
                for k, track in pairs(AniModule.WeaponTracks) do
                    if string.find(k, "ATK") and track.IsPlaying then
                        anyAtkPlaying = true
                        break
                    end
                end
                if not anyAtkPlaying then
                    local atk1 = AniModule.WeaponTracks["ATK1"] or AniModule.WeaponTracks["ATK2"]
                    if atk1 then
                        atk1:Play(0.05, 1, 1.4)
                    end
                end
            end)
        else
            -- No enemies alive — instantly halt attack animations
            stopAllAttackTracks()
        end

        ::continue::
    end
end)

-- C. Auto World Boss Challenge Loop (Targeting Selected World 1-16)
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.5)
        if cfg.AutoWorldBoss then
            if not DataConfig.LocalData.Fighting then
                task.wait(0.6)
                if not DataConfig.LocalData.Fighting and cfg.AutoWorldBoss then
                    local currentSpawn = DataConfig.GetData("SpawnWorld")
                    local targetWorld = cfg.SelectedWorldId or "World008"

                    if cfg.AutoTeleportToWorld and currentSpawn ~= targetWorld then
                        local unlocked = DataConfig.GetData("Worlds") or {}
                        if table.find(unlocked, targetWorld) then
                            addLog("Auto TP to " .. targetWorld .. "...")
                            WorldManager.TeleportToWorld(targetWorld)
                            task.wait(2)
                        end
                    end

                    if not DataConfig.LocalData.Fighting and cfg.AutoWorldBoss then
                        addLog(string.format("⚡ Challenging World %d Boss (Wave 1)...", cfg.SelectedWorldIndex))
                        pcall(function()
                            Events.Fight.Re_ChallengeStart:FireServer(1)
                        end)
                        task.wait(2.2)
                    end
                end
            end
        end
    end
end)

-- D. Auto Secret Boss Challenge Loop
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.6)
        if cfg.AutoSecretBoss then
            if not DataConfig.LocalData.Fighting then
                local cooldowns = DataConfig.GetData("SecretBossLefttime") or {}
                local target = cfg.SelectedSecretBoss

                if cfg.SecretBossCycleAll then
                    for _, b in ipairs(SecretBossList) do
                        local cd = cooldowns[b.Id] or 0
                        if cd <= 0 then
                            target = b.Id
                            break
                        end
                    end
                end

                local currentCd = cooldowns[target] or 0
                if currentCd <= 0 then
                    addLog("🔮 Auto Starting Secret Boss: " .. target)
                    pcall(function()
                        Events.Relics.Re_Start:FireServer(target)
                    end)
                    task.wait(2.8)
                end
            end
        end
    end
end)

-- E. Auto Tower Challenge & Auto Next Floor Loop
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.35)

        -- 1. Auto Next Floor — only if TowerAutoNext is enabled
        if cfg.TowerAutoNext then
            local tt = workspace:FindFirstChild("TowerTeleport")
            if tt and tt:FindFirstChild("Next") then
                addLog("🗼 Floor Cleared! Auto Advancing to Next Floor...")
                pcall(function()
                    local char = LocalPlayer.Character
                    if char and char:FindFirstChild("HumanoidRootPart") then
                        char:PivotTo(tt.Next.CFrame * CFrame.new(0, 3, 0))
                    end
                    Events.Tower.Re_Challenge:FireServer()
                    pcall(function() TowerManager.CheckMovetoNext() end)
                end)
                task.wait(1.5)
            end
        end

        -- 2. Auto Start Tower — only if AutoTower is enabled
        if cfg.AutoTower and not DataConfig.LocalData.Fighting and not workspace:FindFirstChild("TowerTeleport") then
            task.wait(0.6)
            if cfg.AutoTower and not DataConfig.LocalData.Fighting and not workspace:FindFirstChild("TowerTeleport") then
                addLog("🗼 Starting Tower Challenge...")
                pcall(function()
                    Events.Tower.Re_Challenge:FireServer(true)
                end)
                task.wait(2.2)
            end
        end
    end
end)

-- F. UI Auto Closer & Live Status Updater Loop
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.4)
        pcall(function()
            if cfg.AutoCloseRewards then
                local gui = LocalPlayer:FindFirstChild("PlayerGui")
                if gui and gui:FindFirstChild("MainUI") then
                    local center = gui.MainUI:FindFirstChild("CenterMenu")
                    if center then
                        if center:FindFirstChild("BossReward") and center.BossReward.Visible then
                            center.BossReward.Visible = false
                        end
                        if center:FindFirstChild("Tower-defeat") and center["Tower-defeat"].Visible then
                            center["Tower-defeat"].Visible = false
                        end
                        if center:FindFirstChild("TowerOut") and center.TowerOut.Visible then
                            center.TowerOut.Visible = false
                        end
                    end
                end
            end

            if activeTab == "logs" and StatLabel then
                local power = DataConfig.GetPower() or 0
                local wins = DataConfig.GetData("Wins") or 0
                local world = DataConfig.GetData("SpawnWorld") or "Unknown"
                local aliveCount = #getAliveNpcs()
                local isFighting = DataConfig.LocalData.Fighting and (aliveCount > 0 and "⚔️ FIGHTING" or "🛑 DEFEATED") or "🟢 IDLE"

                StatLabel.Text = string.format(
                    "Status: %s | Target: World %d\nWorld: %s | Total Wins: %s\nPower: %s | Alive Mobs: %d",
                    isFighting,
                    cfg.SelectedWorldIndex or 8,
                    tostring(world),
                    string.format("%.2e", wins),
                    string.format("%.2e", power),
                    aliveCount
                )
            end

            if activeTab == "secret" then
                local cds = DataConfig.GetData("SecretBossLefttime") or {}
                for _, b in ipairs(SecretBossList) do
                    local btn = bossBtnList[b.Id]
                    if btn then
                        local cd = cds[b.Id] or 0
                        local statusTxt = (cd <= 0) and "READY" or string.format("%ds", cd)
                        local isSel = (cfg.SelectedSecretBoss == b.Id)
                        btn.Text = string.format(" %s • HP: %s [%s]", b.Name, b.HP, statusTxt)
                        if isSel then
                            btn.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
                        else
                            btn.BackgroundColor3 = (cd <= 0) and Color3.fromRGB(35, 45, 68) or Color3.fromRGB(24, 27, 40)
                        end
                    end
                end
            end
        end)
    end
end)

addLog("Hub Loaded! Continuous Magnet & Smart Attack Active.")
print("[RAS Hub] Loaded with Continuous Magnet and Smart Stop Attack!")
