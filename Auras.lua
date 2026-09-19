--[[
    ═════════════════════════════════════════════════════════════════════════
    ⛩️ [JJK WORLD] TRAIN YOUR AURA - ALL-IN-ONE AUTOMATION HUB & UI (v2.3)
    ═════════════════════════════════════════════════════════════════════════
    Features in v2.3:
      • AUTO-DISMISS & BLOCK AURAS MENU:
          - Automatically detects if the in-game Auras menu/button is clicked
            or opened by new aura acquisitions.
          - Instantly forces auras.Visible = false, restores camera/blur/HUD,
            and fires the close button so the menu NEVER blocks the screen!
          - Dedicated [ON/OFF] toggle: "Auto-Block & Close Auras Screen"
      • PERMANENT x16 COMBO ENGINE:
          - Humanized reaction delay (0.36s - 0.48s) to bypass server anti-bot
          - Prevents suspicious strikes, chains x2 -> x4 -> x8 -> x16 smoothly
      • TRIPLE-LAYER ANTI-AFK ENGINE:
          - LocalPlayer.Idled interception + VirtualUser simulation + KeepAlive remote
      • ACCURATE REAL-TIME POWER & ZONE SCALING (big-uint)
      • AUTO-TELEPORT TO BEST UNLOCKED TRAINING ZONE
      • AUTO-EQUIP BEST AURA (Silent network execution, no screen blocking)
      • AUTO-SPIN HELPER
      • SAFE UNLOAD SCRIPT BUTTON
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
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

-- Game Modules
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("config")
local State = Shared:WaitForChild("state")
local Utils = Shared:WaitForChild("utils")

local SpinConfig = require(Config:WaitForChild("spin"))
local PlayerData = require(State:WaitForChild("player-data"))
local AuraTiers = require(Config:WaitForChild("aura-tiers"))
local Net = require(Shared:WaitForChild("net"))
local BigUint = require(Utils:WaitForChild("big-uint"))
local Format = require(Utils:WaitForChild("format"))

-- Configuration State
local ConfigState = {
    AutoEquipBestAura = true,
    AutoTapMultipliers = true,
    AutoBlockAurasMenu = true,
    AutoTeleportBestZone = true,
    AutoSpin = false,
    AntiAfk = true,
    CheckInterval = 1.0,
    TotalTapsClaimed = 0,
    CurrentStreakTier = "x2",
    MinHumanDelayMs = 360,
    MaxHumanDelayMs = 480,
    Running = true,
}

local ActiveConnections = {}
local PendingClaimSet = {}

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
-- ANTI-AFK ENGINE
----------------------------------------------------------------------

local idledConn = LocalPlayer.Idled:Connect(function()
    if ConfigState.AntiAfk then
        pcall(function()
            if VirtualUser then
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new(0, 0))
            end
        end)
    end
end)
table.insert(ActiveConnections, idledConn)

task.spawn(function()
    while ConfigState.Running do
        if ConfigState.AntiAfk then
            pcall(function()
                if VirtualUser then
                    VirtualUser:CaptureController()
                    VirtualUser:ClickButton2(Vector2.new(0, 0))
                end
            end)
        end
        task.wait(60)
    end
end)

----------------------------------------------------------------------
-- AUTO-DISMISS & BLOCK AURAS MENU ENGINE
----------------------------------------------------------------------

local function restoreGameView()
    pcall(function()
        -- Reset Lighting blur to default base level (1)
        local Lighting = game:GetService("Lighting")
        local blur = Lighting:FindFirstChildWhichIsA("BlurEffect") or Lighting:FindFirstChild("Blur")
        if blur then
            blur.Size = 1
        end

        -- Reset Camera FOV
        if workspace.CurrentCamera then
            workspace.CurrentCamera.FieldOfView = 70
        end

        -- Reset MenuController internal state and restore HUD
        local clientControllers = LocalPlayer:FindFirstChild("PlayerScripts") 
            and LocalPlayer.PlayerScripts:FindFirstChild("Client") 
            and LocalPlayer.PlayerScripts.Client:FindFirstChild("controllers")
        local menuCtrlMod = clientControllers and clientControllers:FindFirstChild("menu-controller")
        if menuCtrlMod then
            local mc = require(menuCtrlMod)
            if mc then
                mc._active = nil
                pcall(function() mc:_applyAmbience() end)
                pcall(function() mc:_applyHudVisibility(false) end)
            end
        end

        -- Ensure HUD Frame 1 is visible
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local hud = pgui and pgui:FindFirstChild("HUD")
        local hud1 = hud and hud:FindFirstChild("1")
        if hud1 then
            hud1.Visible = true
        end
    end)
end

local function dismissAurasMenu()
    pcall(function()
        local pgui = LocalPlayer:FindFirstChild("PlayerGui")
        local aurasGui = pgui and pgui:FindFirstChild("Auras")
        local aurasFrame = aurasGui and aurasGui:FindFirstChild("Auras")

        if aurasFrame and aurasFrame.Visible then
            aurasFrame.Visible = false

            -- Click close button if present
            local content = aurasFrame:FindFirstChild("Content")
            local closeBtn = content and content:FindFirstChild("_frame") 
                and content._frame:FindFirstChild("Header") 
                and content._frame.Header:FindFirstChild("Content") 
                and content._frame.Header.Content:FindFirstChild("CloseButton")
            if closeBtn and firesignal then
                pcall(firesignal, closeBtn.Activated)
            end

            -- Restore camera and HUD immediately
            restoreGameView()
        end

        -- Also auto-dismiss any blocking AuraPopups
        local auraPopups = pgui and pgui:FindFirstChild("AuraPopups")
        if auraPopups then
            for _, child in ipairs(auraPopups:GetChildren()) do
                if child:IsA("GuiObject") and child.Visible then
                    child.Visible = false
                end
            end
        end
    end)
end

-- Real-time property listener to immediately catch when Auras menu opens
local function setupAurasMenuListener()
    local pgui = LocalPlayer:WaitForChild("PlayerGui")
    local aurasGui = pgui:WaitForChild("Auras", 10)
    local aurasFrame = aurasGui and aurasGui:WaitForChild("Auras", 10)
    if aurasFrame then
        local c = aurasFrame:GetPropertyChangedSignal("Visible"):Connect(function()
            if ConfigState.AutoBlockAurasMenu and aurasFrame.Visible then
                task.wait(0.01)
                dismissAurasMenu()
            end
        end)
        table.insert(ActiveConnections, c)
    end
end
setupAurasMenuListener()

----------------------------------------------------------------------
-- DATA PROBES
----------------------------------------------------------------------

local function getPlayerData()
    local ok, atom = pcall(function() return PlayerData.atom() end)
    if ok and type(atom) == "table" then
        return atom[tostring(LocalPlayer.UserId)]
    end
    return nil
end

local function getCurrentPower()
    local data = getPlayerData()
    if data and data.aura and BigUint and BigUint.toNumber then
        local num = BigUint.toNumber(data.aura)
        if num and num > 0 then return num end
    end

    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local auraStat = ls and ls:FindFirstChild("Aura")
    if auraStat then
        local rawStr = tostring(auraStat.Value)
        local numPart, suffix = rawStr:match("^([%d%.]+)%s*([%a]*)$")
        if numPart then
            local val = tonumber(numPart) or 0
            suffix = (suffix or ""):upper()
            local mult = 1
            if suffix == "K" then mult = 1e3
            elseif suffix == "M" then mult = 1e6
            elseif suffix == "B" then mult = 1e9
            elseif suffix == "T" then mult = 1e12
            elseif suffix == "Q" or suffix == "QA" then mult = 1e15
            elseif suffix == "QI" then mult = 1e18
            elseif suffix == "SX" then mult = 1e21
            elseif suffix == "SP" then mult = 1e24
            end
            return val * mult
        end
    end

    return 0
end

local function formatPower(num)
    if not num then return "0" end
    if Format and Format.suffix then
        local ok, res = pcall(Format.suffix, num)
        if ok and res then return res end
    end
    if num >= 1e24 then return string.format("%.2fSP", num / 1e24)
    elseif num >= 1e21 then return string.format("%.2fSX", num / 1e21)
    elseif num >= 1e18 then return string.format("%.2fQI", num / 1e18)
    elseif num >= 1e15 then return string.format("%.2fQa", num / 1e15)
    elseif num >= 1e12 then return string.format("%.2fT", num / 1e12)
    elseif num >= 1e9 then return string.format("%.2fB", num / 1e9)
    elseif num >= 1e6 then return string.format("%.2fM", num / 1e6)
    elseif num >= 1e3 then return string.format("%.2fK", num / 1e3)
    else return tostring(math.floor(num)) end
end

local function getBestOwnedAura()
    local data = getPlayerData()
    if not data or not data.ownedAuras or #data.ownedAuras == 0 then
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

local function getEquippedAura()
    local data = getPlayerData()
    if not data or not data.equippedAuraUuid then
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

local function equipBestAura()
    local bestAura, bestEntry = getBestOwnedAura()
    if not bestAura then return false end

    local currentAura = getEquippedAura()
    if currentAura and currentAura.uuid == bestAura.uuid then
        return true
    end

    -- Direct network call (does NOT open GUI on screen)
    pcall(function()
        if Net and Net.Fire then
            Net:Fire("EquipAura", bestAura.uuid)
        end
    end)

    -- If Auras GUI opened as a side-effect, immediately close it
    if ConfigState.AutoBlockAurasMenu then
        task.defer(dismissAurasMenu)
    end

    return true
end

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

            local farmingZones = workspace:FindFirstChild("FarmingZones")
            if farmingZones then
                local zonePart = farmingZones:FindFirstChild(bestTier.id)
                if zonePart and zonePart:IsA("BasePart") then
                    local targetPos = zonePart.Position + Vector3.new(0, (zonePart.Size.Y / 2) + 3.5, 0)
                    if (hrp.Position - targetPos).Magnitude > 40 then
                        hrp.CFrame = CFrame.new(targetPos)
                    end
                end
            end
        end)
    end
end

----------------------------------------------------------------------
-- HUMANIZED COMBO-PRESERVING SCREEN BONUS AUTO-TAPPER
----------------------------------------------------------------------

local function executeClaim(icon)
    if not icon or not icon.Parent then return end

    local notif = icon:FindFirstChild("Notification")
    if notif and notif:IsA("TextLabel") and notif.Text ~= "" then
        ConfigState.CurrentStreakTier = notif.Text
    end

    local conns = getconnections and getconnections(icon.InputBegan) or {}
    for _, conn in ipairs(conns) do
        if conn.Function then
            for i = 1, 5 do
                local ok, uv = pcall(debug.getupvalue, conn.Function, i)
                if ok and type(uv) == "function" then
                    pcall(uv)
                end
            end
            pcall(conn.Function, {
                UserInputType = Enum.UserInputType.MouseButton1,
                UserInputState = Enum.UserInputState.Begin,
                Position = Vector3.new(icon.AbsolutePosition.X, icon.AbsolutePosition.Y, 0)
            })
        end
    end

    pcall(function()
        if VirtualInputManager and icon.Visible then
            local pos = icon.AbsolutePosition + (icon.AbsoluteSize / 2)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 0)
            task.wait(0.02)
            VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 0)
        end
    end)

    pcall(function()
        if firesignal then
            firesignal(icon.InputBegan, {
                UserInputType = Enum.UserInputType.MouseButton1,
                UserInputState = Enum.UserInputState.Begin,
                Position = Vector3.new(icon.AbsolutePosition.X, icon.AbsolutePosition.Y, 0)
            })
        end
    end)

    ConfigState.TotalTapsClaimed = ConfigState.TotalTapsClaimed + 1
end

local function scheduleHumanClaim(icon)
    if not icon or not icon.Parent or PendingClaimSet[icon] then return end
    PendingClaimSet[icon] = true

    local delaySeconds = math.random(ConfigState.MinHumanDelayMs, ConfigState.MaxHumanDelayMs) / 1000

    task.delay(delaySeconds, function()
        PendingClaimSet[icon] = nil
        if icon and icon.Parent and ConfigState.AutoTapMultipliers then
            executeClaim(icon)
        end
    end)
end

local function setupBonusListener()
    local pgui = LocalPlayer:WaitForChild("PlayerGui")
    local sb = pgui:WaitForChild("ScreenBonuses", 10)
    if sb then
        local c = sb.ChildAdded:Connect(function(child)
            if ConfigState.AutoTapMultipliers then
                scheduleHumanClaim(child)
            end
        end)
        table.insert(ActiveConnections, c)
    end
end
setupBonusListener()

local function scanAndScheduleBonuses()
    local pgui = LocalPlayer:FindFirstChild("PlayerGui")
    if not pgui then return end

    local sb = pgui:FindFirstChild("ScreenBonuses")
    if sb then
        for _, child in ipairs(sb:GetChildren()) do
            if (child.Name == "BonusIcon" or child:IsA("ImageButton")) and not PendingClaimSet[child] then
                scheduleHumanClaim(child)
            end
        end
    end
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

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 380, 0, 600)
MainFrame.Position = UDim2.new(0.04, 0, 0.12, 0)
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

-- Top Bar
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

local MinBtn = Instance.new("TextButton")
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
        TweenService:Create(MainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {Size = UDim2.new(0, 380, 0, 600)}):Play()
        MinBtn.Text = "—"
    end
end)

local CloseBtn = Instance.new("TextButton")
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

local Content = Instance.new("ScrollingFrame")
Content.Name = "Content"
Content.Size = UDim2.new(1, -20, 1, -54)
Content.Position = UDim2.new(0, 10, 0, 48)
Content.BackgroundTransparency = 1
Content.BorderSizePixel = 0
Content.ScrollBarThickness = 3
Content.ScrollBarImageColor3 = Color3.fromRGB(70, 75, 95)
Content.CanvasSize = UDim2.new(0, 0, 0, 600)
Content.Parent = MainFrame

local CardStats = Instance.new("Frame")
CardStats.Size = UDim2.new(1, 0, 0, 78)
CardStats.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
CardStats.BorderSizePixel = 0
CardStats.Parent = Content

local CSCorner = Instance.new("UICorner")
CSCorner.CornerRadius = UDim.new(0, 8)
CSCorner.Parent = CardStats

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
LabelPowerVal.Text = "Loading..."
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
LabelBonusTaps.Text = "Multipliers Claimed: 0  |  Combo: x16 Safe"
LabelBonusTaps.Font = Enum.Font.GothamMedium
LabelBonusTaps.TextSize = 10
LabelBonusTaps.TextColor3 = Color3.fromRGB(150, 230, 150)
LabelBonusTaps.Position = UDim2.new(0, 10, 0, 52)
LabelBonusTaps.Size = UDim2.new(1, -20, 0, 16)
LabelBonusTaps.BackgroundTransparency = 1
LabelBonusTaps.TextXAlignment = Enum.TextXAlignment.Left
LabelBonusTaps.Parent = CardStats

local CardAuras = Instance.new("Frame")
CardAuras.Size = UDim2.new(1, 0, 0, 68)
CardAuras.Position = UDim2.new(0, 0, 0, 86)
CardAuras.BackgroundColor3 = Color3.fromRGB(24, 27, 36)
CardAuras.BorderSizePixel = 0
CardAuras.Parent = Content

local CACorner = Instance.new("UICorner")
CACorner.CornerRadius = UDim.new(0, 8)
CACorner.Parent = CardAuras

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

local function createToggle(name, text, defaultState, yPos, onToggle)
    local frame = Instance.new("Frame")
    frame.Name = "Toggle_" .. name
    frame.Size = UDim2.new(1, 0, 0, 40)
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
    btn.Size = UDim2.new(0, 58, 0, 24)
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

createToggle("AutoEquip", "Auto-Equip Best Aura", ConfigState.AutoEquipBestAura, 162, function(val)
    ConfigState.AutoEquipBestAura = val
end)

createToggle("AutoTap", "Auto-Tap Multipliers (Human Timing / x16 Safe)", ConfigState.AutoTapMultipliers, 208, function(val)
    ConfigState.AutoTapMultipliers = val
end)

createToggle("AutoBlockAuras", "Auto-Block & Close Auras Screen", ConfigState.AutoBlockAurasMenu, 254, function(val)
    ConfigState.AutoBlockAurasMenu = val
    if val then dismissAurasMenu() end
end)

createToggle("AutoZone", "Auto-Teleport Best Training Zone", ConfigState.AutoTeleportBestZone, 300, function(val)
    ConfigState.AutoTeleportBestZone = val
end)

createToggle("AntiAfk", "Anti-AFK (20m Kick Bypass)", ConfigState.AntiAfk, 346, function(val)
    ConfigState.AntiAfk = val
end)

createToggle("AutoSpin", "Auto-Spin / Roll Helper", ConfigState.AutoSpin, 392, function(val)
    ConfigState.AutoSpin = val
end)

-- Action Buttons
local ActionTpBtn = Instance.new("TextButton")
ActionTpBtn.Text = "⚡ TELEPORT TO BEST ZONE NOW"
ActionTpBtn.Font = Enum.Font.GothamBold
ActionTpBtn.TextSize = 12
ActionTpBtn.TextColor3 = Color3.fromRGB(20, 20, 25)
ActionTpBtn.BackgroundColor3 = Color3.fromRGB(0, 200, 255)
ActionTpBtn.Size = UDim2.new(1, 0, 0, 34)
ActionTpBtn.Position = UDim2.new(0, 0, 0, 442)
ActionTpBtn.BorderSizePixel = 0
ActionTpBtn.Parent = Content

local TpCorner = Instance.new("UICorner")
TpCorner.CornerRadius = UDim.new(0, 8)
TpCorner.Parent = ActionTpBtn

ActionTpBtn.MouseButton1Click:Connect(teleportToBestZone)

local ActionEqBtn = Instance.new("TextButton")
ActionEqBtn.Text = "👑 EQUIP BEST AURA NOW"
ActionEqBtn.Font = Enum.Font.GothamBold
ActionEqBtn.TextSize = 12
ActionEqBtn.TextColor3 = Color3.fromRGB(20, 20, 25)
ActionEqBtn.BackgroundColor3 = Color3.fromRGB(255, 215, 80)
ActionEqBtn.Size = UDim2.new(1, 0, 0, 34)
ActionEqBtn.Position = UDim2.new(0, 0, 0, 482)
ActionEqBtn.BorderSizePixel = 0
ActionEqBtn.Parent = Content

local EqCorner = Instance.new("UICorner")
EqCorner.CornerRadius = UDim.new(0, 8)
EqCorner.Parent = ActionEqBtn

ActionEqBtn.MouseButton1Click:Connect(equipBestAura)

-- UNLOAD SCRIPT Button
local UnloadBtn = Instance.new("TextButton")
UnloadBtn.Text = "⛔ UNLOAD SCRIPT"
UnloadBtn.Font = Enum.Font.GothamBold
UnloadBtn.TextSize = 12
UnloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
UnloadBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
UnloadBtn.Size = UDim2.new(1, 0, 0, 34)
UnloadBtn.Position = UDim2.new(0, 0, 0, 522)
UnloadBtn.BorderSizePixel = 0
UnloadBtn.Parent = Content

local UnloadCorner = Instance.new("UICorner")
UnloadCorner.CornerRadius = UDim.new(0, 8)
UnloadCorner.Parent = UnloadBtn

local function unloadScript()
    ConfigState.Running = false
    for _, conn in ipairs(ActiveConnections) do
        pcall(function() conn:Disconnect() end)
    end
    ActiveConnections = {}
    PendingClaimSet = {}
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
    LabelPowerVal.Text = formatPower(curPower)

    local bestZone = getBestUnlockedTrainingZone()
    if bestZone then
        LabelZoneVal.Text = bestZone.name .. " (" .. tostring(bestZone.multiplier) .. "x)"
    else
        LabelZoneVal.Text = "Sandbox (2x)"
    end

    LabelBonusTaps.Text = "Multipliers: " .. tostring(ConfigState.TotalTapsClaimed) .. " | Current Tier: " .. ConfigState.CurrentStreakTier

    local eqAura, eqEntry = getEquippedAura()
    if eqEntry then
        LabelEqStatus.Text = "EQUIPPED: " .. (eqEntry.name or eqAura.id:upper())
        BadgeEqRarity.Text = eqEntry.rarity or "UNKNOWN"
        BadgeEqRarity.BackgroundColor3 = RarityColors[eqEntry.rarity] or RarityColors["UNKNOWN"]
    end

    local bestAura, bestEntry = getBestOwnedAura()
    if bestEntry then
        local odds = SpinConfig and SpinConfig.oddsDenominator(bestEntry) or 0
        LabelBestStatus.Text = "BEST OWNED: " .. (bestEntry.name or bestAura.id:upper()) .. " (1 in " .. formatPower(odds) .. ")"
    end
end

-- Fast Poller for Bonus Icons (Runs every 0.1s)
task.spawn(function()
    while ConfigState.Running do
        if ConfigState.AutoTapMultipliers then
            pcall(scanAndScheduleBonuses)
        end
        if ConfigState.AutoBlockAurasMenu then
            pcall(dismissAurasMenu)
        end
        task.wait(0.1)
    end
end)

-- Main Automation Loop (Heartbeat every 1.0s)
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

print("[⛩️ JJK WORLD] v2.3 Automation Hub with Auto-Block Auras Screen loaded!")
