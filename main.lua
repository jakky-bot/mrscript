--[[
    ═══════════════════════════════════════════════════════════════════
    🗡️ REBORN AS SWORDSMAN - AUTO CHALLENGE BOSS HUB (WITH CUSTOM UI)
    ═══════════════════════════════════════════════════════════════════
    Features:
      • Auto Challenge World/Dungeon Bosses (Wave 1-7 or Auto PK)
      • Auto Challenge Secret Bosses (Relics) with Live Cooldown Tracker
      • Auto Farm All Ready Secret Bosses in Rotation
      • Auto Tower Challenge
      • Kill Aura / Rapid Hit
      • Auto Teleport Behind Target (Backstab)
      • Auto Close Reward Windows
      • Clean Dark Glassmorphism Draggable UI with Floating Toggle & Keybind
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

local DataConfig = require(Config:WaitForChild("DataConfig"))
local RelicsConfig = require(Config:WaitForChild("RelicsConfig"))
local NPCConfig = require(Config:WaitForChild("NPCConfig"))
local AniModule = require(Helper:WaitForChild("AniModule"))

local FightNpcs = workspace:WaitForChild("FightNpcs")

-- Target GUI Parent (gethui, CoreGui, or PlayerGui)
local GuiParent = (gethui and gethui()) or game:GetService("CoreGui") or PlayerGui

-- Clean up older instance if existing
if GuiParent:FindFirstChild("RAS_BossHub_Gui") then
    GuiParent.RAS_BossHub_Gui:Destroy()
end

-- Global Config & State
_G.RAS_BossConfig = _G.RAS_BossConfig or {
    AutoWorldBoss = false,
    AutoSecretBoss = false,
    SecretBossCycleAll = false,
    SelectedSecretBoss = "SecretBoss001",
    AutoTower = false,
    FastAttack = true,
    TeleportBehind = true,
    AutoCloseRewards = true,
    AttackSpeed = 0.08,
}
local cfg = _G.RAS_BossConfig

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
MainWindow.Size = UDim2.new(0, 520, 0, 390)
MainWindow.Position = UDim2.new(0.5, -260, 0.5, -195)
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
TitleLabel.Text = "🗡️ Reborn As Swordsman • Auto Boss Hub"
TitleLabel.TextColor3 = Color3.fromRGB(235, 240, 255)
TitleLabel.TextSize = 13
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

local SubBadge = Instance.new("TextLabel")
SubBadge.Size = UDim2.new(0, 42, 0, 18)
SubBadge.Position = UDim2.new(0, 310, 0.5, -9)
SubBadge.BackgroundColor3 = Color3.fromRGB(99, 102, 241)
SubBadge.Text = "PRO"
SubBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
SubBadge.Font = Enum.Font.GothamBold
SubBadge.TextSize = 10
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

-- Floating Open Pill Button (Always accessible)
local FloatingPill = Instance.new("TextButton")
FloatingPill.Name = "FloatingPill"
FloatingPill.Size = UDim2.new(0, 120, 0, 34)
FloatingPill.Position = UDim2.new(0, 20, 0.2, 0)
FloatingPill.BackgroundColor3 = Color3.fromRGB(22, 25, 38)
FloatingPill.Text = "🗡️ Boss Hub"
FloatingPill.TextColor3 = Color3.fromRGB(165, 180, 252)
FloatingPill.Font = Enum.Font.GothamBold
FloatingPill.TextSize = 13
FloatingPill.Visible = false
FloatingPill.Parent = ScreenGui

local PillCorner = Instance.new("UICorner")
PillCorner.CornerRadius = UDim.new(0, 17)
PillCorner.Parent = FloatingPill

local PillStroke = Instance.new("UIStroke")
PillStroke.Color = Color3.fromRGB(99, 102, 241)
PillStroke.Thickness = 1.5
PillStroke.Parent = FloatingPill

-- Dragging Functionality
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

-- Minimize & Close Toggle Logic
local isMinimized = false
MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        MainWindow.Size = UDim2.new(0, 520, 0, 42)
        MinBtn.Text = "+"
    else
        MainWindow.Size = UDim2.new(0, 520, 0, 390)
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

-- Keybind to toggle (RightControl or RightShift)
UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe and (input.KeyCode == Enum.KeyCode.RightControl or input.KeyCode == Enum.KeyCode.RightShift) then
        MainWindow.Visible = not MainWindow.Visible
        FloatingPill.Visible = not MainWindow.Visible
    end
end)

-- ═══════════════════════════════════════════════════════════════════
-- 3. NAVIGATION SIDEBAR & TAB CONTAINER
-- ═══════════════════════════════════════════════════════════════════

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

-- ═══════════════════════════════════════════════════════════════════
-- 4. UI HELPER CONTROLS (CARDS, TOGGLES, BUTTONS)
-- ═══════════════════════════════════════════════════════════════════

local function createCard(parent, title, desc)
    local card = Instance.new("Frame")
    card.Size = UDim2.new(1, 0, 0, 52)
    card.BackgroundColor3 = Color3.fromRGB(22, 25, 38)
    card.BorderSizePixel = 0
    card.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = card

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(36, 42, 64)
    stroke.Thickness = 1
    stroke.Parent = card

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -70, 0, 20)
    lbl.Position = UDim2.new(0, 12, 0, 8)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.Text = title
    lbl.TextColor3 = Color3.fromRGB(220, 230, 250)
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
-- 5. POPULATE TABS
-- ═══════════════════════════════════════════════════════════════════

-- TAB 1: WORLD / DUNGEON BOSS
local TabWorld = createTab("world", "World Boss", "👑", 1)

local CardWorldBoss = createCard(TabWorld, "Auto Challenge World Boss", "Loops current world stages 1-7 (Boss) continuously")
addToggle(CardWorldBoss, cfg.AutoWorldBoss, function(val)
    cfg.AutoWorldBoss = val
    if val then
        addLog("Auto World Boss enabled")
        DataConfig.LocalData.AutoPK = true
    else
        addLog("Auto World Boss disabled")
        DataConfig.LocalData.AutoPK = false
    end
end)

local CardTeleport = createCard(TabWorld, "Teleport Behind Target", "Positions you right behind boss to avoid attacks")
addToggle(CardTeleport, cfg.TeleportBehind, function(val)
    cfg.TeleportBehind = val
    addLog("Teleport Behind: " .. tostring(val))
end)

local CardFastAttack = createCard(TabWorld, "Rapid Kill Aura", "Instantly attacks enemies in the arena via remotes")
addToggle(CardFastAttack, cfg.FastAttack, function(val)
    cfg.FastAttack = val
    addLog("Rapid Kill Aura: " .. tostring(val))
end)

local DirectBossBtn = Instance.new("TextButton")
DirectBossBtn.Size = UDim2.new(1, 0, 0, 36)
DirectBossBtn.BackgroundColor3 = Color3.fromRGB(49, 130, 206)
DirectBossBtn.Text = "⚡ Start World Challenge Now (Wave 1)"
DirectBossBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DirectBossBtn.Font = Enum.Font.GothamBold
DirectBossBtn.TextSize = 12
DirectBossBtn.Parent = TabWorld

local DirectCorner = Instance.new("UICorner")
DirectCorner.CornerRadius = UDim.new(0, 8)
DirectCorner.Parent = DirectBossBtn

DirectBossBtn.MouseButton1Click:Connect(function()
    if not DataConfig.LocalData.Fighting then
        addLog("Manual: Starting World Challenge...")
        DataConfig.LocalData.AutoPK = true
        Events.Fight.Re_ChallengeStart:FireServer(1)
    else
        addLog("Already fighting!")
    end
end)

-- TAB 2: SECRET BOSS (RELICS)
local TabSecret = createTab("secret", "Secret Boss", "🔮", 2)

local CardSecretBoss = createCard(TabSecret, "Auto Farm Selected Secret Boss", "Auto starts selected boss when cooldown reaches 0")
addToggle(CardSecretBoss, cfg.AutoSecretBoss, function(val)
    cfg.AutoSecretBoss = val
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
BossButtonsContainer.Size = UDim2.new(1, 0, 0, 180)
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

-- TAB 3: TOWER
local TabTower = createTab("tower", "Tower", "🗼", 3)

local CardTower = createCard(TabTower, "Auto Challenge Tower", "Continuously enters Tower floors")
addToggle(CardTower, cfg.AutoTower, function(val)
    cfg.AutoTower = val
    addLog("Auto Tower: " .. tostring(val))
end)

local TowerBtn = Instance.new("TextButton")
TowerBtn.Size = UDim2.new(1, 0, 0, 36)
TowerBtn.BackgroundColor3 = Color3.fromRGB(56, 161, 105)
TowerBtn.Text = "🗼 Challenge Next Tower Floor Now"
TowerBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
TowerBtn.Font = Enum.Font.GothamBold
TowerBtn.TextSize = 12
TowerBtn.Parent = TabTower

local TBCorner = Instance.new("UICorner")
TBCorner.CornerRadius = UDim.new(0, 8)
TBCorner.Parent = TowerBtn

TowerBtn.MouseButton1Click:Connect(function()
    if not DataConfig.LocalData.Fighting then
        addLog("Manual Tower Challenge...")
        Events.Tower.Re_Challenge:FireServer(true)
    else
        addLog("Already fighting!")
    end
end)

-- TAB 4: COMBAT & SETTINGS
local TabSettings = createTab("settings", "Combat & Misc", "⚡", 4)

local CardCloseRewards = createCard(TabSettings, "Auto Close Reward Popups", "Automatically hides BossReward & victory dialogs")
addToggle(CardCloseRewards, cfg.AutoCloseRewards, function(val)
    cfg.AutoCloseRewards = val
    addLog("Auto Close Rewards: " .. tostring(val))
end)

-- TAB 5: LOGS & LIVE STATS
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
-- 6. AUTOMATION LOOPS
-- ═══════════════════════════════════════════════════════════════════

-- A. Auto Attack / Rapid Hit Loop
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(cfg.AttackSpeed or 0.08)
        if cfg.FastAttack and DataConfig.LocalData.Fighting then
            pcall(function()
                local npcs = FightNpcs:GetChildren()
                if #npcs > 0 then
                    local char = LocalPlayer.Character
                    local hrp = char and char:FindFirstChild("HumanoidRootPart")

                    for _, npc in ipairs(npcs) do
                        if npc:IsA("Model") and npc:FindFirstChild("PrimaryPart") then
                            -- Teleport behind target
                            if cfg.TeleportBehind and hrp then
                                hrp.CFrame = npc.PrimaryPart.CFrame * CFrame.new(0, 0, 3.5)
                            end

                            local mapVal = npc:FindFirstChild("Map")
                            local mapType = mapVal and mapVal.Value or "Dungeon"

                            if mapType == "Dungeon" then
                                Events.Fight.Re_TakeDamage:FireServer(npc.Name, 1)
                            elseif mapType == "SecretBoss" then
                                Events.Relics.Re_TakeDamage:FireServer(1)
                            elseif mapType == "Tower" then
                                Events.Tower.Re_TakeDamage:FireServer(1)
                            else
                                Events.Fight.Re_TakeDamage:FireServer(npc.Name, 1)
                                Events.Relics.Re_TakeDamage:FireServer(1)
                            end
                        end
                    end
                    AniModule.PlayAtkAnim()
                end
            end)
        end
    end
end)

-- B. Auto World Boss Challenge Loop
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.6)
        if cfg.AutoWorldBoss then
            if not DataConfig.LocalData.Fighting then
                task.wait(0.8)
                if not DataConfig.LocalData.Fighting and cfg.AutoWorldBoss then
                    addLog("Challenging World Boss (Wave 1)...")
                    pcall(function()
                        DataConfig.LocalData.AutoPK = true
                        Events.Fight.Re_ChallengeStart:FireServer(1)
                    end)
                    task.wait(2.5)
                end
            end
        end
    end
end)

-- C. Auto Secret Boss Challenge Loop
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.8)
        if cfg.AutoSecretBoss then
            if not DataConfig.LocalData.Fighting then
                local cooldowns = DataConfig.GetData("SecretBossLefttime") or {}
                local target = cfg.SelectedSecretBoss

                if cfg.SecretBossCycleAll then
                    -- Search for any boss off cooldown
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
                    addLog("Starting Secret Boss: " .. target)
                    pcall(function()
                        Events.Relics.Re_Start:FireServer(target)
                    end)
                    task.wait(3)
                end
            end
        end
    end
end)

-- D. Auto Tower Challenge Loop
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.8)
        if cfg.AutoTower then
            if not DataConfig.LocalData.Fighting then
                task.wait(0.8)
                if not DataConfig.LocalData.Fighting and cfg.AutoTower then
                    addLog("Starting Tower Challenge...")
                    pcall(function()
                        Events.Tower.Re_Challenge:FireServer(true)
                    end)
                    task.wait(2.5)
                end
            end
        end
    end
end)

-- E. UI Auto Closer & Live Status Updater Loop
task.spawn(function()
    while ScreenGui.Parent do
        task.wait(0.5)
        pcall(function()
            -- Auto close popups if requested
            if cfg.AutoCloseRewards then
                local gui = LocalPlayer:FindFirstChild("PlayerGui")
                if gui and gui:FindFirstChild("MainUI") then
                    local center = gui.MainUI:FindFirstChild("CenterMenu")
                    if center and center:FindFirstChild("BossReward") and center.BossReward.Visible then
                        center.BossReward.Visible = false
                    end
                end
            end

            -- Update stats tab
            if activeTab == "logs" and StatLabel then
                local power = DataConfig.GetPower() or 0
                local wins = DataConfig.GetData("Wins") or 0
                local world = DataConfig.GetData("SpawnWorld") or "Unknown"
                local isFighting = DataConfig.LocalData.Fighting and "⚔️ FIGHTING" or "🟢 IDLE"
                local enemyCount = #FightNpcs:GetChildren()

                StatLabel.Text = string.format(
                    "Status: %s | Active Enemies: %d\nWorld: %s | Total Wins: %s\nPower: %s",
                    isFighting,
                    enemyCount,
                    tostring(world),
                    string.format("%.2e", wins),
                    string.format("%.2e", power)
                )
            end

            -- Update Secret Boss Buttons cooldown text if secret tab active
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

addLog("Hub Loaded! Press RightControl or click 🗡️ Boss Hub to toggle.")
print("[RAS Hub] Auto Boss Hub successfully loaded!")
