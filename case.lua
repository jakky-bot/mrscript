--[[
    ================================================================
    CASE PARADISE - AUTOMATION HUB V21
    ================================================================
    Architectural Upgrades in V15:

    1. PRECISE GAME-VERIFIED COOLDOWN CONTROLLER:
       - Server cooldown analysis reveals Case Paradise enforces an active
         server-side cooldown of 3.0s (for single cases) and 3.8s (for 5-case batches).
       - Remotes.CheckCooldown only tracks long-term case timers (Free cases, Level cases),
         returning 0 for standard cases.
       - V15 enforces a centralized ServerCooldownExpire clock set to os.clock() + (batchQty == 1 and 3.0 or 3.85).
       - If the server ever returns nil/false/cooldown, it dynamically marks the state as
         "Waiting for Cooldown" (NOT permanent failure or blocked state) and yields smoothly.
       - Zero repeated failed requests; cleanly resumes when the clock expires.

    2. DEDICATED PERSISTENT STATUS PANEL FOR EACH FEATURE:
       - Replaces the rapidly changing single status bar with 6 persistent cards:
         1. Auto Quest: Current quest title, progress (e.g. 5/40), Mantra reward, and state.
         2. Mantra Mode: Balance, configured threshold, target Event Case, openings completed, state.
         3. Auto Case Level: Target level/case, required XP, cooldown, and last result.
         4. Auto Opener: Selected case, batch qty, cooldown, and last item won.
         5. Auto Sell: Total items sold, confirmed sale proceeds ($), eligible items remaining.
         6. Battle: Active lobby status, mode, round progress, and transition states.
       - Includes a compact persistent activity feed with timestamps ([HH:MM:SS]).
       - Global header bar provides an overarching scheduler status without overwriting individual cards.

    3. CLEAN TABBED UI LAYOUT & ZERO OVERFLOW:
       - Implements a modern responsive Tabbed Navigation System:
         * [Dashboard]: Persistent status panels for all 6 features + live activity log.
         * [Quests & Mantra]: Auto Quest controls + Mantra Threshold Mode controls.
         * [Case Openers]: Auto Case Opener (Qty 1-5, case dropdown) + Auto Case Level controls.
         * [Auto Sell]: Threshold configuration + Auto Sell toggle.
       - Each tab has its own dedicated ScrollingFrame with proper CanvasSize auto-scaling.
       - No clipped controls, no overflowing text, no overlapping widgets.

    4. CORRECTED MANTRA THRESHOLD MODE CYCLE:
       - The threshold acts as an ACTIVATION TRIGGER ONLY:
         1. Triggers when Mantra balance >= configured threshold (> 0).
         2. Sets MantraModeEngaged = true and pauses normal scheduler tasks.
         3. Remains engaged and continues opening Event Cases even after balance drops below threshold.
         4. If cooldown occurs, remains in Mantra Mode and waits safely without releasing priority.
         5. Disengages ONLY when balance drops below the case cost (10 Mantra) or reaches 0.
         6. Releases priority cleanly, returning to the normal cooperative scheduler.
         7. Stays on standby until Mantra balance reaches or exceeds the threshold again.
    ================================================================
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer

-- Clean up any prior running instance
if _G.ParadiseHubCleanup then
    pcall(_G.ParadiseHubCleanup)
end

-- Remotes & Core Services
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local OpenCaseFunction = Remotes and Remotes:WaitForChild("OpenCase", 5)
local SellFunction = Remotes and Remotes:WaitForChild("Sell", 5)
local CheckCooldownFunction = Remotes and Remotes:FindFirstChild("CheckCooldown")
local CreateBattleFunction = Remotes and Remotes:FindFirstChild("CreateBattle")
local AddBotRemote = Remotes and Remotes:FindFirstChild("AddBot")
local LeaveBattleRemote = Remotes and Remotes:FindFirstChild("LeaveBattle")
local BattlesFolder = ReplicatedStorage:WaitForChild("Battles", 5)

-- Game Modules
local CasesModule = require(ReplicatedStorage:WaitForChild("Modules").Cases)
local ItemsModule = require(ReplicatedStorage:WaitForChild("Modules").Items)

-- Clean existing UI if present
if LocalPlayer.PlayerGui:FindFirstChild("ParadiseAutoHub") then
    LocalPlayer.PlayerGui.ParadiseAutoHub:Destroy()
end

-- Create Main ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ParadiseAutoHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Main Frame (Clean 520x640 frame)
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 640)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -320)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 10)
UICorner.Parent = MainFrame

-- Title Header
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Size = UDim2.new(1, 0, 0, 42)
TitleBar.BackgroundColor3 = Color3.fromRGB(30, 33, 48)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = MainFrame

local TitleCorner = Instance.new("UICorner")
TitleCorner.CornerRadius = UDim.new(0, 10)
TitleCorner.Parent = TitleBar

-- ==================== FLOATING MONEY TRACKER ====================
local MoneyTrackerFrame = Instance.new("Frame")
MoneyTrackerFrame.Name = "MoneyTrackerFrame"
MoneyTrackerFrame.Size = UDim2.new(0, 240, 0, 116)
MoneyTrackerFrame.Position = UDim2.new(0.5, 270, 0.5, -320)
MoneyTrackerFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 32)
MoneyTrackerFrame.BorderSizePixel = 0
MoneyTrackerFrame.Active = true
MoneyTrackerFrame.Draggable = true
MoneyTrackerFrame.Parent = ScreenGui

local MTCorner = Instance.new("UICorner")
MTCorner.CornerRadius = UDim.new(0, 8)
MTCorner.Parent = MoneyTrackerFrame

local MTStroke = Instance.new("UIStroke")
MTStroke.Color = Color3.fromRGB(45, 50, 68)
MTStroke.Thickness = 1.5
MTStroke.Parent = MoneyTrackerFrame

local MTHeader = Instance.new("Frame")
MTHeader.Name = "MTHeader"
MTHeader.Size = UDim2.new(1, 0, 0, 26)
MTHeader.BackgroundColor3 = Color3.fromRGB(30, 33, 48)
MTHeader.BorderSizePixel = 0
MTHeader.Parent = MoneyTrackerFrame

local MTHCorner = Instance.new("UICorner")
MTHCorner.CornerRadius = UDim.new(0, 8)
MTHCorner.Parent = MTHeader

local MTTitle = Instance.new("TextLabel")
MTTitle.Size = UDim2.new(1, -12, 1, 0)
MTTitle.Position = UDim2.new(0, 10, 0, 0)
MTTitle.BackgroundTransparency = 1
MTTitle.Text = "MONEY TRACKER"
MTTitle.TextColor3 = Color3.fromRGB(0, 175, 255)
MTTitle.TextSize = 11
MTTitle.Font = Enum.Font.GothamBold
MTTitle.TextXAlignment = Enum.TextXAlignment.Left
MTTitle.Parent = MTHeader

local MTBody = Instance.new("Frame")
MTBody.Name = "MTBody"
MTBody.Size = UDim2.new(1, -16, 1, -32)
MTBody.Position = UDim2.new(0, 8, 0, 28)
MTBody.BackgroundTransparency = 1
MTBody.Parent = MoneyTrackerFrame

local function CreateMTStatRow(name, labelText, yOffset)
    local row = Instance.new("Frame")
    row.Name = name .. "Row"
    row.Size = UDim2.new(1, 0, 0, 18)
    row.Position = UDim2.new(0, 0, 0, yOffset)
    row.BackgroundTransparency = 1
    row.Parent = MTBody
    
    local titleLbl = Instance.new("TextLabel")
    titleLbl.Size = UDim2.new(0.48, 0, 1, 0)
    titleLbl.BackgroundTransparency = 1
    titleLbl.Text = labelText
    titleLbl.TextColor3 = Color3.fromRGB(150, 155, 170)
    titleLbl.TextSize = 10
    titleLbl.Font = Enum.Font.GothamSemibold
    titleLbl.TextXAlignment = Enum.TextXAlignment.Left
    titleLbl.Parent = row
    
    local valLbl = Instance.new("TextLabel")
    valLbl.Name = "ValueLabel"
    valLbl.Size = UDim2.new(0.52, 0, 1, 0)
    valLbl.Position = UDim2.new(0.48, 0, 0, 0)
    valLbl.BackgroundTransparency = 1
    valLbl.Text = "-"
    valLbl.TextColor3 = Color3.fromRGB(240, 240, 240)
    valLbl.TextSize = 10
    valLbl.Font = Enum.Font.GothamBold
    valLbl.TextXAlignment = Enum.TextXAlignment.Right
    valLbl.Parent = row
    
    return valLbl
end

local MTStartVal = CreateMTStatRow("Start", "Starting Balance:", 2)
local MTCurrVal = CreateMTStatRow("Current", "Current Balance:", 22)
local MTProfitVal = CreateMTStatRow("Profit", "Net Profit/Loss:", 42)
local MTEndTimeVal = CreateMTStatRow("Elapsed", "Elapsed Time:", 62)


local TitleText = Instance.new("TextLabel")
TitleText.Size = UDim2.new(1, -50, 1, 0)
TitleText.Position = UDim2.new(0, 15, 0, 0)
TitleText.BackgroundTransparency = 1
TitleText.Text = "Case Paradise | Auto Farm Hub v21"
TitleText.TextColor3 = Color3.fromRGB(255, 255, 255)
TitleText.TextSize = 15
TitleText.Font = Enum.Font.GothamBold
TitleText.TextXAlignment = Enum.TextXAlignment.Left
TitleText.Parent = TitleBar

local CloseBtn = Instance.new("TextButton")
CloseBtn.Size = UDim2.new(0, 30, 0, 30)
CloseBtn.Position = UDim2.new(1, -36, 0, 6)
CloseBtn.BackgroundColor3 = Color3.fromRGB(220, 55, 55)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.TextSize = 13
CloseBtn.Parent = TitleBar

local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn

-- TAB NAVIGATION BAR
local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.Size = UDim2.new(1, -20, 0, 34)
TabBar.Position = UDim2.new(0, 10, 0, 48)
TabBar.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame

local TBCorner = Instance.new("UICorner")
TBCorner.CornerRadius = UDim.new(0, 6)
TBCorner.Parent = TabBar

local TabButtons = {}
local TabPages = {}
local TabNames = {"Dashboard", "Quests & Mantra", "Case Openers", "Auto Sell"}

-- Content Container
local ContentContainer = Instance.new("Frame")
ContentContainer.Name = "ContentContainer"
ContentContainer.Size = UDim2.new(1, -20, 1, -92)
ContentContainer.Position = UDim2.new(0, 10, 0, 86)
ContentContainer.BackgroundTransparency = 1
ContentContainer.Parent = MainFrame

local function SwitchTab(selectedTab)
    for name, page in pairs(TabPages) do
        page.Visible = (name == selectedTab)
    end
    for name, btn in pairs(TabButtons) do
        btn.BackgroundColor3 = (name == selectedTab) and Color3.fromRGB(0, 175, 255) or Color3.fromRGB(25, 28, 40)
        btn.TextColor3 = (name == selectedTab) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 180)
    end
end

for idx, tName in ipairs(TabNames) do
    local btn = Instance.new("TextButton")
    btn.Name = tName .. "Btn"
    btn.Size = UDim2.new(0.25, -4, 1, -4)
    btn.Position = UDim2.new((idx - 1) * 0.25, 2, 0, 2)
    btn.BackgroundColor3 = (idx == 1) and Color3.fromRGB(0, 175, 255) or Color3.fromRGB(25, 28, 40)
    btn.Text = tName
    btn.TextColor3 = (idx == 1) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(180, 180, 180)
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 11
    btn.Parent = TabBar
    
    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 4)
    bCorner.Parent = btn
    
    btn.MouseButton1Click:Connect(function()
        SwitchTab(tName)
    end)
    TabButtons[tName] = btn
    
    -- Create Page
    local page = Instance.new("ScrollingFrame")
    page.Name = tName .. "Page"
    page.Size = UDim2.new(1, 0, 1, 0)
    page.BackgroundTransparency = 1
    page.ScrollBarThickness = 5
    page.ScrollBarImageColor3 = Color3.fromRGB(0, 175, 255)
    page.Visible = (idx == 1)
    page.ClipsDescendants = true
    page.AutomaticCanvasSize = Enum.AutomaticSize.Y
    page.CanvasSize = UDim2.new(0, 0, 0, 0)
    page.Parent = ContentContainer
    
    local pList = Instance.new("UIListLayout")
    pList.SortOrder = Enum.SortOrder.LayoutOrder
    pList.Padding = UDim.new(0, 10)
    pList.Parent = page

    local pPadding = Instance.new("UIPadding")
    pPadding.PaddingTop = UDim.new(0, 2)
    pPadding.PaddingBottom = UDim.new(0, 14)
    pPadding.PaddingLeft = UDim.new(0, 2)
    pPadding.PaddingRight = UDim.new(0, 6)
    pPadding.Parent = page
    
    TabPages[tName] = page
end

-- ==================== FEATURE STATUS REGISTERS ====================
local FeatureStatusData = {
    Quest = {Title = "Auto Quest", Status = "Idle: Not started", Detail = "Progress: -", Reward = "Reward: -", Color = Color3.fromRGB(46, 204, 113)},
    Mantra = {Title = "Mantra Mode", Status = "Standby (Below Threshold)", Detail = "Openings: 0 completed", Reward = "Balance: -", Color = Color3.fromRGB(230, 126, 34)},
    Level = {Title = "Auto Case Level", Status = "Idle: Disabled", Detail = "Target: -", Reward = "XP: -", Color = Color3.fromRGB(155, 89, 182)},
    Opener = {Title = "Auto Opener", Status = "Idle: Disabled", Detail = "Selected: -", Reward = "Last: -", Color = Color3.fromRGB(52, 152, 219)},
    Sell = {Title = "Auto Sell", Status = "Idle: Disabled", Detail = "Sold: 0 items ($0.00)", Reward = "Eligible: 0", Color = Color3.fromRGB(241, 196, 15)},
    Battle = {Title = "Battle Tracker", Status = "No Active Battle", Detail = "Lobby: None", Reward = "Mode: -", Color = Color3.fromRGB(52, 152, 219)}
}

local StatusCardLabels = {}

local function CreateStatusCard(parent, key, data)
    local card = Instance.new("Frame")
    card.Name = key .. "Card"
    card.Size = UDim2.new(1, 0, 0, 68)
    card.BackgroundColor3 = Color3.fromRGB(25, 28, 40)
    card.BorderSizePixel = 0
    card.Parent = parent
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = card
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.5, 0, 0, 18)
    title.Position = UDim2.new(0, 10, 0, 5)
    title.BackgroundTransparency = 1
    title.Text = data.Title
    title.TextColor3 = data.Color
    title.Font = Enum.Font.GothamBold
    title.TextSize = 11
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card
    
    local rightInfo = Instance.new("TextLabel")
    rightInfo.Size = UDim2.new(0.45, 0, 0, 18)
    rightInfo.Position = UDim2.new(0.52, 0, 0, 5)
    rightInfo.BackgroundTransparency = 1
    rightInfo.Text = data.Reward
    rightInfo.TextColor3 = Color3.fromRGB(180, 180, 180)
    rightInfo.Font = Enum.Font.Gotham
    rightInfo.TextSize = 10
    rightInfo.TextXAlignment = Enum.TextXAlignment.Right
    rightInfo.Parent = card
    
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -20, 0, 20)
    status.Position = UDim2.new(0, 10, 0, 24)
    status.BackgroundTransparency = 1
    status.Text = data.Status
    status.TextColor3 = Color3.fromRGB(230, 230, 230)
    status.Font = Enum.Font.GothamSemibold
    status.TextSize = 11
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.TextTruncate = Enum.TextTruncate.AtEnd
    status.Parent = card
    
    local detail = Instance.new("TextLabel")
    detail.Size = UDim2.new(1, -20, 0, 18)
    detail.Position = UDim2.new(0, 10, 0, 44)
    detail.BackgroundTransparency = 1
    detail.Text = data.Detail
    detail.TextColor3 = Color3.fromRGB(150, 150, 150)
    detail.Font = Enum.Font.Gotham
    detail.TextSize = 10
    detail.TextXAlignment = Enum.TextXAlignment.Left
    detail.TextTruncate = Enum.TextTruncate.AtEnd
    detail.Parent = card
    
    StatusCardLabels[key] = {
        Status = status,
        Detail = detail,
        RightInfo = rightInfo,
        Card = card
    }
end

-- ==================== BUILD TAB 1: DASHBOARD ====================
local DashPage = TabPages["Dashboard"]

-- Global Activity Overview Bar
local GlobalBar = Instance.new("Frame")
GlobalBar.Name = "GlobalBar"
GlobalBar.Size = UDim2.new(1, 0, 0, 44)
GlobalBar.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
GlobalBar.BorderSizePixel = 0
GlobalBar.Parent = DashPage

local GBCorner = Instance.new("UICorner")
GBCorner.CornerRadius = UDim.new(0, 6)
GBCorner.Parent = GlobalBar

local GTitle = Instance.new("TextLabel")
GTitle.Size = UDim2.new(1, -16, 0, 16)
GTitle.Position = UDim2.new(0, 8, 0, 4)
GTitle.BackgroundTransparency = 1
GTitle.Text = "SCHEDULER STATUS:"
GTitle.TextColor3 = Color3.fromRGB(0, 200, 255)
GTitle.Font = Enum.Font.GothamBold
GTitle.TextSize = 10
GTitle.TextXAlignment = Enum.TextXAlignment.Left
GTitle.Parent = GlobalBar

local GText = Instance.new("TextLabel")
GText.Size = UDim2.new(1, -16, 0, 20)
GText.Position = UDim2.new(0, 8, 0, 20)
GText.BackgroundTransparency = 1
GText.Text = "Scheduler Active & Synchronized"
GText.TextColor3 = Color3.fromRGB(220, 220, 220)
GText.Font = Enum.Font.GothamSemibold
GText.TextSize = 11
GText.TextXAlignment = Enum.TextXAlignment.Left
GText.Parent = GlobalBar

local function SetGlobalStatus(msg, color)
    GText.Text = msg
    GText.TextColor3 = color or Color3.fromRGB(220, 220, 220)
end

-- Persistent Feature Status Cards
for _, key in ipairs({"Quest", "Mantra", "Level", "Opener", "Sell", "Battle"}) do
    CreateStatusCard(DashPage, key, FeatureStatusData[key])
end

local function UpdateFeatureStatus(key, statusText, detailText, rightInfoText, color)
    local labels = StatusCardLabels[key]
    if labels then
        if statusText then
            labels.Status.Text = statusText
            if color then labels.Status.TextColor3 = color end
        end
        if detailText then labels.Detail.Text = detailText end
        if rightInfoText then labels.RightInfo.Text = rightInfoText end
    end
end

-- Compact Activity Feed
local FeedFrame = Instance.new("Frame")
FeedFrame.Name = "FeedFrame"
FeedFrame.Size = UDim2.new(1, 0, 0, 90)
FeedFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 24)
FeedFrame.BorderSizePixel = 0
FeedFrame.Parent = DashPage

local FFCorner = Instance.new("UICorner")
FFCorner.CornerRadius = UDim.new(0, 6)
FFCorner.Parent = FeedFrame

local FeedTitle = Instance.new("TextLabel")
FeedTitle.Size = UDim2.new(1, -16, 0, 16)
FeedTitle.Position = UDim2.new(0, 8, 0, 4)
FeedTitle.BackgroundTransparency = 1
FeedTitle.Text = "RECENT ACTIVITY LOG:"
FeedTitle.TextColor3 = Color3.fromRGB(0, 175, 255)
FeedTitle.Font = Enum.Font.GothamBold
FeedTitle.TextSize = 10
FeedTitle.TextXAlignment = Enum.TextXAlignment.Left
FeedTitle.Parent = FeedFrame

local FeedLines = {}
for i = 1, 3 do
    local fLine = Instance.new("TextLabel")
    fLine.Size = UDim2.new(1, -16, 0, 18)
    fLine.Position = UDim2.new(0, 8, 0, 18 + (i - 1) * 20)
    fLine.BackgroundTransparency = 1
    fLine.Text = ""
    fLine.TextColor3 = Color3.fromRGB(170, 170, 170)
    fLine.Font = Enum.Font.Gotham
    fLine.TextSize = 10
    fLine.TextXAlignment = Enum.TextXAlignment.Left
    fLine.TextTruncate = Enum.TextTruncate.AtEnd
    fLine.Parent = FeedFrame
    table.insert(FeedLines, fLine)
end

local ActivityHistory = {}
local function LogActivity(msg)
    local ts = os.date("%H:%M:%S")
    local entry = "[" .. ts .. "] " .. msg
    table.insert(ActivityHistory, 1, entry)
    if #ActivityHistory > 3 then table.remove(ActivityHistory) end
    for idx, line in ipairs(FeedLines) do
        line.Text = ActivityHistory[idx] or ""
    end
end

-- Auto CanvasSize handled dynamically via AutomaticSize.Y

-- ==================== BUILD TAB 2: QUESTS & MANTRA ====================
local QMPage = TabPages["Quests & Mantra"]

local function CreateSection(parent, title, height)
    local Frame = Instance.new("Frame")
    Frame.Size = UDim2.new(1, 0, 0, height or 120)
    Frame.BackgroundColor3 = Color3.fromRGB(25, 28, 40)
    Frame.BorderSizePixel = 0
    Frame.Parent = parent
    
    local Corner = Instance.new("UICorner")
    Corner.CornerRadius = UDim.new(0, 8)
    Corner.Parent = Frame
    
    local Label = Instance.new("TextLabel")
    Label.Size = UDim2.new(1, -20, 0, 25)
    Label.Position = UDim2.new(0, 10, 0, 5)
    Label.BackgroundTransparency = 1
    Label.Text = title
    Label.TextColor3 = Color3.fromRGB(0, 175, 255)
    Label.TextSize = 13
    Label.Font = Enum.Font.GothamBold
    Label.TextXAlignment = Enum.TextXAlignment.Left
    Label.Parent = Frame
    
    return Frame
end

-- Section 1: Auto Quest
local QuestSec = CreateSection(QMPage, "1. Smart Quests (Highest Mantra First | 5-Batch)", 85)
local QuestToggleBtn = Instance.new("TextButton")
QuestToggleBtn.Size = UDim2.new(0.9, 0, 0, 36)
QuestToggleBtn.Position = UDim2.new(0.05, 0, 0, 35)
QuestToggleBtn.BackgroundColor3 = Color3.fromRGB(55, 58, 75)
QuestToggleBtn.Text = "Auto Complete Quests: OFF"
QuestToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
QuestToggleBtn.Font = Enum.Font.GothamSemibold
QuestToggleBtn.TextSize = 13
QuestToggleBtn.Parent = QuestSec

local QCorner = Instance.new("UICorner")
QCorner.CornerRadius = UDim.new(0, 6)
QCorner.Parent = QuestToggleBtn

-- Section 2: Mantra Threshold Mode
local MantraSec = CreateSection(QMPage, "2. Automatic Mantra Threshold Mode (Opens Event Cases)", 130)
local MantraInput = Instance.new("TextBox")
MantraInput.Size = UDim2.new(0.9, 0, 0, 32)
MantraInput.Position = UDim2.new(0.05, 0, 0, 35)
MantraInput.BackgroundColor3 = Color3.fromRGB(42, 45, 60)
MantraInput.Text = ""
MantraInput.PlaceholderText = "Enter Mantra Activation Trigger (e.g. 200)"
MantraInput.TextColor3 = Color3.fromRGB(255, 255, 255)
MantraInput.Font = Enum.Font.Gotham
MantraInput.TextSize = 12
MantraInput.Parent = MantraSec

local MCorner = Instance.new("UICorner")
MCorner.CornerRadius = UDim.new(0, 6)
MCorner.Parent = MantraInput

local MantraToggleBtn = Instance.new("TextButton")
MantraToggleBtn.Size = UDim2.new(0.9, 0, 0, 36)
MantraToggleBtn.Position = UDim2.new(0.05, 0, 0, 78)
MantraToggleBtn.BackgroundColor3 = Color3.fromRGB(55, 58, 75)
MantraToggleBtn.Text = "Mantra Threshold Mode: OFF"
MantraToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
MantraToggleBtn.Font = Enum.Font.GothamSemibold
MantraToggleBtn.TextSize = 13
MantraToggleBtn.Parent = MantraSec

local MTCorner = Instance.new("UICorner")
MTCorner.CornerRadius = UDim.new(0, 6)
MTCorner.Parent = MantraToggleBtn

-- Auto CanvasSize handled dynamically via AutomaticSize.Y

-- ==================== BUILD TAB 3: CASE OPENERS ====================
local COPage = TabPages["Case Openers"]

-- Section 3: Auto Case Opener
local CaseSec = CreateSection(COPage, "3. Auto Case Opener (Batch Qty 1-5)", 180)
local QtyLabel = Instance.new("TextLabel")
QtyLabel.Size = UDim2.new(0.3, 0, 0, 28)
QtyLabel.Position = UDim2.new(0.05, 0, 0, 32)
QtyLabel.BackgroundTransparency = 1
QtyLabel.Text = "Batch Qty:"
QtyLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
QtyLabel.Font = Enum.Font.GothamSemibold
QtyLabel.TextSize = 12
QtyLabel.TextXAlignment = Enum.TextXAlignment.Left
QtyLabel.Parent = CaseSec

local OpenQuantity = 1
local QtyButtons = {}
for q = 1, 5 do
    local qBtn = Instance.new("TextButton")
    qBtn.Size = UDim2.new(0, 32, 0, 26)
    qBtn.Position = UDim2.new(0.32 + (q - 1) * 0.12, 0, 0, 33)
    qBtn.BackgroundColor3 = (q == OpenQuantity) and Color3.fromRGB(0, 175, 255) or Color3.fromRGB(45, 48, 65)
    qBtn.Text = tostring(q)
    qBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    qBtn.Font = Enum.Font.GothamBold
    qBtn.TextSize = 12
    qBtn.Parent = CaseSec
    
    local qCorner = Instance.new("UICorner")
    qCorner.CornerRadius = UDim.new(0, 4)
    qCorner.Parent = qBtn
    
    qBtn.MouseButton1Click:Connect(function()
        OpenQuantity = q
        for idx, btn in ipairs(QtyButtons) do
            btn.BackgroundColor3 = (idx == q) and Color3.fromRGB(0, 175, 255) or Color3.fromRGB(45, 48, 65)
        end
    end)
    table.insert(QtyButtons, qBtn)
end

-- Case Selection Dropdown
local ScannedCases = {}
for id, c in pairs(CasesModule) do
    if c.Name and c.Price and (c.Currency == "Balance" or c.Currency == nil) then
        table.insert(ScannedCases, {
            Id = id,
            Name = c.Name,
            Price = c.Price,
            Currency = c.Currency or "Balance"
        })
    end
end
table.sort(ScannedCases, function(a, b) return a.Name < b.Name end)

local SelectedCaseKey = #ScannedCases > 0 and ScannedCases[1].Id or ""

local DropdownBtn = Instance.new("TextButton")
DropdownBtn.Size = UDim2.new(0.9, 0, 0, 32)
DropdownBtn.Position = UDim2.new(0.05, 0, 0, 70)
DropdownBtn.BackgroundColor3 = Color3.fromRGB(42, 45, 60)
DropdownBtn.Text = "Select Case (Scanned " .. #ScannedCases .. " cases)"
DropdownBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
DropdownBtn.Font = Enum.Font.Gotham
DropdownBtn.TextSize = 12
DropdownBtn.ZIndex = 5
DropdownBtn.Parent = CaseSec

local DCorner = Instance.new("UICorner")
DCorner.CornerRadius = UDim.new(0, 6)
DCorner.Parent = DropdownBtn

local DropdownFrame = Instance.new("ScrollingFrame")
DropdownFrame.Size = UDim2.new(0.9, 0, 0, 200)
DropdownFrame.Position = UDim2.new(0.05, 0, 0, 104)
DropdownFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
DropdownFrame.BorderSizePixel = 1
DropdownFrame.BorderColor3 = Color3.fromRGB(0, 175, 255)
DropdownFrame.Visible = false
DropdownFrame.ZIndex = 20
DropdownFrame.ScrollBarThickness = 6
DropdownFrame.CanvasSize = UDim2.new(0, 0, 0, #ScannedCases * 26)
DropdownFrame.Parent = CaseSec

local DropList = Instance.new("UIListLayout")
DropList.SortOrder = Enum.SortOrder.LayoutOrder
DropList.Parent = DropdownFrame

for idx, cInfo in ipairs(ScannedCases) do
    local ItemBtn = Instance.new("TextButton")
    ItemBtn.Size = UDim2.new(1, 0, 0, 26)
    ItemBtn.BackgroundColor3 = (idx % 2 == 0) and Color3.fromRGB(28, 31, 42) or Color3.fromRGB(34, 37, 50)
    ItemBtn.Text = cInfo.Name .. " (" .. cInfo.Price .. " " .. cInfo.Currency .. ")"
    ItemBtn.TextColor3 = Color3.fromRGB(230, 230, 230)
    ItemBtn.Font = Enum.Font.Gotham
    ItemBtn.TextSize = 11
    ItemBtn.ZIndex = 21
    ItemBtn.Parent = DropdownFrame
    
    ItemBtn.MouseButton1Click:Connect(function()
        SelectedCaseKey = cInfo.Id
        DropdownBtn.Text = "Selected: " .. cInfo.Name
        DropdownFrame.Visible = false
    end)
end

DropdownBtn.MouseButton1Click:Connect(function()
    DropdownFrame.Visible = not DropdownFrame.Visible
end)

local OpenCaseToggleBtn = Instance.new("TextButton")
OpenCaseToggleBtn.Size = UDim2.new(0.9, 0, 0, 36)
OpenCaseToggleBtn.Position = UDim2.new(0.05, 0, 0, 115)
OpenCaseToggleBtn.BackgroundColor3 = Color3.fromRGB(55, 58, 75)
OpenCaseToggleBtn.Text = "Auto Open Selected Case: OFF"
OpenCaseToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
OpenCaseToggleBtn.Font = Enum.Font.GothamSemibold
OpenCaseToggleBtn.TextSize = 13
OpenCaseToggleBtn.ZIndex = 2
OpenCaseToggleBtn.Parent = CaseSec

local OCorner = Instance.new("UICorner")
OCorner.CornerRadius = UDim.new(0, 6)
OCorner.Parent = OpenCaseToggleBtn

-- Section 4: Auto Case Level
local LevelSec = CreateSection(COPage, "4. Auto Case Level (Level 10, 20, 30, 40+ Queue)", 85)
local LevelToggleBtn = Instance.new("TextButton")
LevelToggleBtn.Size = UDim2.new(0.9, 0, 0, 36)
LevelToggleBtn.Position = UDim2.new(0.05, 0, 0, 35)
LevelToggleBtn.BackgroundColor3 = Color3.fromRGB(55, 58, 75)
LevelToggleBtn.Text = "Auto Case Level: OFF"
LevelToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
LevelToggleBtn.Font = Enum.Font.GothamSemibold
LevelToggleBtn.TextSize = 13
LevelToggleBtn.Parent = LevelSec

local LCorner = Instance.new("UICorner")
LCorner.CornerRadius = UDim.new(0, 6)
LCorner.Parent = LevelToggleBtn

-- Auto CanvasSize handled dynamically via AutomaticSize.Y

-- ==================== BUILD TAB 4: AUTO SELL ====================
local SellPage = TabPages["Auto Sell"]

local SellSec = CreateSection(SellPage, "5. Auto Sell Items (Sell Items Below Price: < Value)", 130)
local ThresholdInput = Instance.new("TextBox")
ThresholdInput.Size = UDim2.new(0.9, 0, 0, 32)
ThresholdInput.Position = UDim2.new(0.05, 0, 0, 35)
ThresholdInput.BackgroundColor3 = Color3.fromRGB(42, 45, 60)
ThresholdInput.Text = ""
ThresholdInput.PlaceholderText = "Enter Price Threshold (Sells items < this value)"
ThresholdInput.TextColor3 = Color3.fromRGB(255, 255, 255)
ThresholdInput.Font = Enum.Font.Gotham
ThresholdInput.TextSize = 12
ThresholdInput.Parent = SellSec

local TCorner = Instance.new("UICorner")
TCorner.CornerRadius = UDim.new(0, 6)
TCorner.Parent = ThresholdInput

local SellPriceThreshold = 0
ThresholdInput.FocusLost:Connect(function()
    SellPriceThreshold = tonumber(ThresholdInput.Text) or 0
end)

local SellToggleBtn = Instance.new("TextButton")
SellToggleBtn.Size = UDim2.new(0.9, 0, 0, 36)
SellToggleBtn.Position = UDim2.new(0.05, 0, 0, 78)
SellToggleBtn.BackgroundColor3 = Color3.fromRGB(55, 58, 75)
SellToggleBtn.Text = "Auto Sell Items: OFF"
SellToggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
SellToggleBtn.Font = Enum.Font.GothamSemibold
SellToggleBtn.TextSize = 13
SellToggleBtn.Parent = SellSec

local SCorner = Instance.new("UICorner")
SCorner.CornerRadius = UDim.new(0, 6)
SCorner.Parent = SellToggleBtn

-- Auto CanvasSize handled dynamically via AutomaticSize.Y

-- ==================== TOGGLE HANDLERS ====================
local ScriptRunning = true
local TrackerStartTime = os.clock()
local StartingMoney = nil
local AutoQuestEnabled = false
local AutoCaseLevelEnabled = false
local AutoOpenEnabled = false
local AutoSellEnabled = false
local MantraThresholdEnabled = false
local MantraThresholdValue = 0

QuestToggleBtn.MouseButton1Click:Connect(function()
    AutoQuestEnabled = not AutoQuestEnabled
    QuestToggleBtn.Text = "Auto Complete Quests: " .. (AutoQuestEnabled and "ON" or "OFF")
    QuestToggleBtn.BackgroundColor3 = AutoQuestEnabled and Color3.fromRGB(46, 139, 87) or Color3.fromRGB(55, 58, 75)
    UpdateFeatureStatus("Quest", AutoQuestEnabled and "Active (Monitoring)" or "Disabled", nil, nil, AutoQuestEnabled and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(180, 180, 180))
end)

LevelToggleBtn.MouseButton1Click:Connect(function()
    AutoCaseLevelEnabled = not AutoCaseLevelEnabled
    LevelToggleBtn.Text = "Auto Case Level: " .. (AutoCaseLevelEnabled and "ON" or "OFF")
    LevelToggleBtn.BackgroundColor3 = AutoCaseLevelEnabled and Color3.fromRGB(46, 139, 87) or Color3.fromRGB(55, 58, 75)
    UpdateFeatureStatus("Level", AutoCaseLevelEnabled and "Active (Queued)" or "Disabled", nil, nil, AutoCaseLevelEnabled and Color3.fromRGB(155, 89, 182) or Color3.fromRGB(180, 180, 180))
end)

OpenCaseToggleBtn.MouseButton1Click:Connect(function()
    AutoOpenEnabled = not AutoOpenEnabled
    OpenCaseToggleBtn.Text = "Auto Open Selected Case: " .. (AutoOpenEnabled and "ON" or "OFF")
    OpenCaseToggleBtn.BackgroundColor3 = AutoOpenEnabled and Color3.fromRGB(46, 139, 87) or Color3.fromRGB(55, 58, 75)
    UpdateFeatureStatus("Opener", AutoOpenEnabled and "Active" or "Disabled", nil, nil, AutoOpenEnabled and Color3.fromRGB(52, 152, 219) or Color3.fromRGB(180, 180, 180))
end)

SellToggleBtn.MouseButton1Click:Connect(function()
    AutoSellEnabled = not AutoSellEnabled
    SellToggleBtn.Text = "Auto Sell Items: " .. (AutoSellEnabled and "ON" or "OFF")
    SellToggleBtn.BackgroundColor3 = AutoSellEnabled and Color3.fromRGB(46, 139, 87) or Color3.fromRGB(55, 58, 75)
    UpdateFeatureStatus("Sell", AutoSellEnabled and "Active" or "Disabled", nil, nil, AutoSellEnabled and Color3.fromRGB(241, 196, 15) or Color3.fromRGB(180, 180, 180))
end)

MantraInput.FocusLost:Connect(function()
    MantraThresholdValue = tonumber(MantraInput.Text) or 0
    UpdateFeatureStatus("Mantra", nil, nil, "Trigger: " .. MantraThresholdValue)
end)

MantraToggleBtn.MouseButton1Click:Connect(function()
    MantraThresholdEnabled = not MantraThresholdEnabled
    MantraToggleBtn.Text = "Mantra Threshold Mode: " .. (MantraThresholdEnabled and "ON" or "OFF")
    MantraToggleBtn.BackgroundColor3 = MantraThresholdEnabled and Color3.fromRGB(46, 139, 87) or Color3.fromRGB(55, 58, 75)
    UpdateFeatureStatus("Mantra", MantraThresholdEnabled and "Standby (Waiting for balance)" or "Disabled", nil, "Trigger: " .. MantraThresholdValue, MantraThresholdEnabled and Color3.fromRGB(230, 126, 34) or Color3.fromRGB(180, 180, 180))
end)

-- ==================== CENTRALIZED COOLDOWN CONTROLLER ====================
-- Game-Verified Timing: Standard cases enforce a 3.0s cooldown; 5-case batches enforce 3.8s.
local OpeningInProgress = false
local ServerCooldownExpire = 0
local EventConnections = {}
local BattleCooldownUntil = 0
local ActiveBattleId = nil
local MatchHiddenState = false

-- State Tracker for Mantra Mode Cycle
local MantraModeEngaged = false
local MantraOpeningsCompleted = 0
local LevelQueueIndex = 1

-- Statistics Tracker for Auto Sell
local TotalItemsSold = 0
local TotalSaleProceeds = 0

-- Currency Helper
-- Money Formatting Helper for Tracker
local function FormatMoney(amount)
    local isNegative = amount < 0
    local absVal = math.abs(amount)
    local formatted = string.format("%.2f", absVal)
    local intPart, decPart = formatted:match("^(%d+)(%.%d+)$")
    if not intPart then
        intPart = formatted
        decPart = ".00"
    end
    local k
    while true do
        intPart, k = string.gsub(intPart, "^(-?%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    return (isNegative and "-$" or "$") .. intPart .. decPart
end

local function GetPlayerCurrency(currName)
    local pData = LocalPlayer:FindFirstChild("PlayerData")
    if not pData then return 0 end
    
    if currName == "Mantra" or currName == "Leaves" then
        local currs = pData:FindFirstChild("Currencies")
        if currs and currs:FindFirstChild("Tickets") then
            return currs.Tickets.Value
        end
        if currs and currs:FindFirstChild("Leaves") then
            return currs.Leaves.Value
        end
        if pData:FindFirstChild("Leaves") then
            return pData.Leaves.Value
        end
        return 0
    end
    
    local currencies = pData:FindFirstChild("Currencies")
    if currencies and currencies:FindFirstChild(currName) then
        return currencies[currName].Value
    end
    if pData:FindFirstChild(currName) then
        return pData[currName].Value
    end
    return 0
end

local function GetMantraBalance()
    return GetPlayerCurrency("Mantra")
end

local function CanAfford(caseKey, quantity)
    local cData = CasesModule[caseKey]
    if not cData then return false, "Invalid Case" end
    local currency = cData.Currency or "Balance"
    local price = (cData.Price or 0) * (quantity or 1)
    
    if currency == "Leaves" or currency == "Tickets" or currency == "Mantra" then
        local currentBal = GetMantraBalance()
        if currentBal < price then
            return false, "Insufficient Mantra (Need " .. price .. ", Have " .. currentBal .. ")"
        end
        return true, "Mantra"
    else
        local currentBal = GetPlayerCurrency(currency)
        if currentBal < price then
            return false, "Insufficient " .. currency .. " (Need $" .. price .. ", Have $" .. currentBal .. ")"
        end
        return true, currency
    end
end

-- Checks precise server cooldown and case-specific timer
local function CheckCaseCooldown(caseKey, quantity)
    local nowClock = os.clock()
    if ServerCooldownExpire > nowClock then
        return false, ServerCooldownExpire - nowClock
    end
    
    -- Check game server cooldown for Level / Free cases
    local cData = CasesModule[caseKey]
    if cData and (cData.XPRequirement or cData.Category == "Level" or tostring(caseKey):find("LEVEL")) then
        if CheckCooldownFunction then
            local success, cdTimestamp = pcall(function()
                return CheckCooldownFunction:InvokeServer(caseKey)
            end)
            if success and typeof(cdTimestamp) == "number" then
                local diff = cdTimestamp - os.time()
                if diff > 0 then
                    return false, diff
                end
            end
        end
    end
    
    return true, 0
end

-- Sets server cooldown based on batch size
local function RecordOpeningCooldown(batchQty)
    local cdDuration = (batchQty and batchQty > 1) and 3.85 or 3.0
    ServerCooldownExpire = os.clock() + cdDuration
end

-- Dynamic In-Game Battle Match Visibility Controller
local BattleLobbyCreatedTime = 0

local function FindMyActiveBattle()
    if not BattlesFolder then return nil end
    local myName = LocalPlayer.Name
    
    local function IsMeInBattle(b)
        if not b then return false end
        local host = b:FindFirstChild("Host") and b.Host.Value
        if host == myName then return true end
        local playersFolder = b:FindFirstChild("Players")
        if playersFolder and playersFolder:FindFirstChild(myName) then
            return true
        end
        return false
    end
    
    -- Verify ActiveBattleId actually belongs to LocalPlayer
    if ActiveBattleId then
        local b = BattlesFolder:FindFirstChild(tostring(ActiveBattleId))
        if b and IsMeInBattle(b) then
            return b
        else
            ActiveBattleId = nil
        end
    end
    
    -- Scan all battles in folder for LocalPlayer
    for _, b in ipairs(BattlesFolder:GetChildren()) do
        if IsMeInBattle(b) then
            ActiveBattleId = tonumber(b.Name) or b.Name
            return b
        end
    end
    return nil
end

local function IsMatchInProgress()
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return false end
    local battleGui = pg:FindFirstChild("Battle")
    if not battleGui then return false end
    local bf = battleGui:FindFirstChild("BattleFrame")
    if not bf then return false end
    
    local caseAmount = bf:FindFirstChild("CaseAmount")
    local hasCaseRound = caseAmount and caseAmount.Visible and caseAmount.Text:find("Case") ~= nil
    
    local activeBattle = FindMyActiveBattle()
    local battleRunning = false
    if activeBattle then
        local ended = activeBattle:FindFirstChild("Ended") and activeBattle.Ended.Value
        if not ended then
            battleRunning = true
        end
    end
    
    if (bf.Visible and hasCaseRound) or battleRunning then
        return true
    end
    return false
end

local function SetBattleMatchUIHidden(hide)
    MatchHiddenState = hide
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end
    
    local battleGui = pg:FindFirstChild("Battle")
    if battleGui then
        local bf = battleGui:FindFirstChild("BattleFrame")
        if hide then
            if bf then bf.Visible = false end
        else
            local myBattle = FindMyActiveBattle()
            if myBattle then
                local ended = myBattle:FindFirstChild("Ended") and myBattle.Ended.Value
                if not ended then
                    if bf then bf.Visible = true end
                    battleGui.Enabled = true
                else
                    if bf then bf.Visible = false end
                    battleGui.Enabled = false
                end
            else
                if bf then bf.Visible = false end
                battleGui.Enabled = false
            end
        end
    end
    
    local mainGui = pg:FindFirstChild("Main")
    if mainGui and not mainGui.Enabled then
        mainGui.Enabled = true
    end
    
    local winGui = pg:FindFirstChild("Windows")
    if winGui and not winGui.Enabled then
        winGui.Enabled = true
    end
end

local function SetCaseOpeningAnimationHidden(hide)
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if not pg then return end
    local openAnim = pg:FindFirstChild("OpenAnimation")
    if openAnim then
        openAnim.Enabled = not hide
    end
end

-- Centralized Case Opening Execution
local function ExecuteOpenBatch(caseKey, quantity, callerName, hideAnimation)
    if OpeningInProgress then
        return false, "Opening in progress"
    end
    
    if not OpenCaseFunction then
        return false, "OpenCase Remote missing"
    end
    
    local affordable, reason = CanAfford(caseKey, quantity)
    if not affordable then
        return false, reason
    end
    
    local ready, cdLeft = CheckCaseCooldown(caseKey, quantity)
    if not ready then
        return false, "Waiting for Cooldown: " .. string.format("%.1fs", cdLeft)
    end
    
    OpeningInProgress = true
    
    if hideAnimation then
        SetCaseOpeningAnimationHidden(true)
    end
    
    local initialItems = #LocalPlayer.PlayerData.Inventory:GetChildren()
    local isLevelCase = false
    local cData = CasesModule[caseKey]
    if cData and (cData.XPRequirement or cData.Category == "Level" or tostring(caseKey):find("LEVEL")) then
        isLevelCase = true
    end
    
    local success, res = pcall(function()
        if isLevelCase then
            -- Level cases require false for quickOpen and false for wild
            return OpenCaseFunction:InvokeServer(caseKey, quantity, false, false)
        else
            return OpenCaseFunction:InvokeServer(caseKey, quantity, true, nil)
        end
    end)
    
    if success and typeof(res) == "table" and #res > 0 then
        -- Record server-verified cooldown immediately
        RecordOpeningCooldown(#res)
        
        local timeout = os.clock() + 3
        while os.clock() < timeout do
            if #LocalPlayer.PlayerData.Inventory:GetChildren() >= initialItems + #res then
                break
            end
            task.wait(0.1)
        end
        
        task.wait(0.2)
        OpeningInProgress = false
        if hideAnimation then
            SetCaseOpeningAnimationHidden(false)
        end
        return true, res
    else
        -- Server rejected due to cooldown: mark 1.5s recovery cooldown cleanly
        ServerCooldownExpire = os.clock() + 1.5
        OpeningInProgress = false
        if hideAnimation then
            SetCaseOpeningAnimationHidden(false)
        end
        return false, "Waiting for Cooldown: Server busy"
    end
end

local function FindLowestPriceCase()
    local lowestCase = nil
    local lowestPrice = math.huge
    for id, c in pairs(CasesModule) do
        if c.Price and c.Price > 0 and (c.Currency == "Balance" or c.Currency == nil) then
            if c.Price < lowestPrice then
                lowestPrice = c.Price
                lowestCase = id
            end
        end
    end
    return lowestCase or "PERCHANCE"
end

local function FindEligibleEventCases()
    local eligible = {}
    for id, c in pairs(CasesModule) do
        if c.Currency == "Leaves" or c.Category == "Autumn Event" or id == "AutumnCase" then
            table.insert(eligible, {
                Id = id,
                Name = c.Name or id,
                Price = c.Price or 10,
                Currency = c.Currency or "Leaves"
            })
        end
    end
    return eligible
end

-- Dynamic Quest Parser with Highest Mantra Reward Priority (Source of Truth: PlayerData.Quests)
local function GetPrioritizedActiveQuest()
    local pData = LocalPlayer:FindFirstChild("PlayerData")
    if not pData or not pData:FindFirstChild("Quests") then
        return nil, "Missing PlayerData.Quests"
    end
    
    local candidates = {}
    
    for _, q in ipairs(pData.Quests:GetChildren()) do
        local completed = (q:FindFirstChild("Completed") and q.Completed.Value == true)
        local prog = (q:FindFirstChild("Progress") and q.Progress.Value) or 0
        local req = (q:FindFirstChild("Requirement") and q.Requirement.Value) or 1
        local reward = (q:FindFirstChild("Reward") and q.Reward.Value) or 0
        local qType = q.Value or "Open"
        local subject = (q:FindFirstChild("Subject") and q.Subject.Value) or ""
        
        -- A quest is eligible only if NOT completed and live progress < requirement
        if not completed and prog < req then
            local titleText = ""
            local targetKey = subject
            
            if qType == "Open" then
                local cData = CasesModule and CasesModule[subject]
                local cName = cData and cData.Name or (tostring(subject) .. " Case")
                titleText = "Open " .. req .. " " .. cName .. "s."
                targetKey = subject
            elseif qType == "Play" then
                titleText = "Play " .. req .. " " .. tostring(subject) .. " mode battles."
                targetKey = subject
            elseif qType == "Win" then
                titleText = "Win " .. req .. " battles."
                targetKey = (subject ~= "" and subject) or "CLASSIC"
            else
                titleText = tostring(qType) .. " " .. req .. " " .. tostring(subject)
                targetKey = subject
            end
            
            table.insert(candidates, {
                QuestObject = q,
                Type = qType,
                Target = targetKey,
                Current = prog,
                Requirement = req,
                Reward = tonumber(reward) or 0,
                Title = titleText
            })
        end
    end
    
    if #candidates == 0 then
        return nil, "All Quests Completed"
    end
    
    -- Sort candidates: Highest Mantra Reward first (preserves existing priority)
    table.sort(candidates, function(a, b)
        if a.Reward ~= b.Reward then
            return a.Reward > b.Reward
        end
        return (a.Requirement - a.Current) < (b.Requirement - b.Current)
    end)
    
    return candidates[1], nil
end

-- ==================== CENTRALIZED NON-BLOCKING GLOBAL SCHEDULER ====================
local FeatureOrder = {"Quest", "Level", "Opener", "Sell"}
local CurrentOrderIndex = 1

local function GetNextEnabledFeature()
    for _ = 1, #FeatureOrder do
        local feature = FeatureOrder[CurrentOrderIndex]
        CurrentOrderIndex = (CurrentOrderIndex % #FeatureOrder) + 1
        
        if feature == "Quest" and AutoQuestEnabled then
            return "Quest"
        elseif feature == "Level" and AutoCaseLevelEnabled then
            return "Level"
        elseif feature == "Opener" and AutoOpenEnabled and SelectedCaseKey ~= "" then
            return "Opener"
        elseif feature == "Sell" and AutoSellEnabled and SellPriceThreshold > 0 then
            return "Sell"
        end
    end
    return nil
end

task.spawn(function()
    while ScriptRunning do
        task.wait(0.35)
        
        local pData = LocalPlayer:FindFirstChild("PlayerData")
        if not pData then
            SetGlobalStatus("Idle: Waiting for PlayerData...", Color3.fromRGB(150, 150, 150))
            continue
        end

        -- ==================== PRIORITY 0: MANTRA THRESHOLD MODE CYCLE ====================
        -- Activation Trigger: Triggers when balance >= threshold.
        -- Cycle persists until balance < Event Case Price (10) or exhausted.
        local currentMantra = GetMantraBalance()
        
        if MantraThresholdEnabled and MantraThresholdValue > 0 then
            if not MantraModeEngaged and currentMantra >= MantraThresholdValue then
                MantraModeEngaged = true
                LogActivity("Mantra Mode ACTIVATED (Trigger: " .. currentMantra .. " >= " .. MantraThresholdValue .. ")")
            end
        else
            MantraModeEngaged = false
        end

        if MantraModeEngaged then
            local eventCases = FindEligibleEventCases()
            local targetEventCase = #eventCases > 0 and eventCases[1] or {Id = "AutumnCase", Name = "Autumn Case", Price = 10}
            local cost = targetEventCase.Price
            
            if currentMantra < cost then
                -- Exhaustion confirmed: disengage and resume normal tasks
                MantraModeEngaged = false
                LogActivity("Mantra Mode STOPPED (Exhausted: " .. currentMantra .. " < " .. cost .. "). Resuming scheduler.")
                UpdateFeatureStatus("Mantra", "Standby (Exhausted)", "Completed: " .. MantraOpeningsCompleted .. " cases", "Balance: " .. currentMantra .. " Mantra", Color3.fromRGB(46, 204, 113))
                SetGlobalStatus("Mantra Mode Exhausted: Resumed Normal Tasks", Color3.fromRGB(46, 204, 113))
            else
                -- Cycle remains engaged: open eligible Event Cases
                local ready, cdLeft = CheckCaseCooldown(targetEventCase.Id, 1)
                if not ready then
                    UpdateFeatureStatus("Mantra", "Waiting for Cooldown (" .. string.format("%.1fs", cdLeft) .. ")", "Target: " .. targetEventCase.Name .. " (" .. cost .. " M)", "Balance: " .. currentMantra .. " Mantra", Color3.fromRGB(241, 196, 15))
                    SetGlobalStatus("Mantra Mode: Waiting for Cooldown (" .. string.format("%.1fs", cdLeft) .. ")", Color3.fromRGB(241, 196, 15))
                    continue
                end
                
                local maxAffordable = math.floor(currentMantra / cost)
                local batchToOpen = math.clamp(maxAffordable, 1, 5)
                
                SetGlobalStatus("Mantra Mode: Opening " .. targetEventCase.Name .. " x" .. batchToOpen, Color3.fromRGB(230, 126, 34))
                local ok, res = ExecuteOpenBatch(targetEventCase.Id, batchToOpen, "MantraMode", false)
                if ok then
                    MantraOpeningsCompleted = MantraOpeningsCompleted + #res
                    local newBal = GetMantraBalance()
                    LogActivity("Mantra Mode: Opened " .. #res .. " " .. targetEventCase.Name .. " (Remaining: " .. newBal .. ")")
                    UpdateFeatureStatus("Mantra", "Active (Opening Batch)", "Completed: " .. MantraOpeningsCompleted .. " cases", "Balance: " .. newBal .. " Mantra", Color3.fromRGB(46, 204, 113))
                else
                    UpdateFeatureStatus("Mantra", tostring(res), "Target: " .. targetEventCase.Name, "Balance: " .. currentMantra .. " Mantra", Color3.fromRGB(241, 196, 15))
                end
                continue -- Remains in Mantra Mode next tick
            end
        else
            UpdateFeatureStatus("Mantra", MantraThresholdEnabled and "Standby (Waiting for Trigger)" or "Disabled", "Openings: " .. MantraOpeningsCompleted .. " cases", "Balance: " .. currentMantra .. " Mantra", Color3.fromRGB(180, 180, 180))
        end

        -- ==================== NORMAL COOPERATIVE SCHEDULER ====================
        local activeFeature = GetNextEnabledFeature()
        if not activeFeature then
            if not IsMatchInProgress() then
                SetBattleMatchUIHidden(false)
            end
            SetCaseOpeningAnimationHidden(false)
            SetGlobalStatus("All Features Idle / Ready", Color3.fromRGB(180, 180, 180))
            continue
        end

        -- ==================== 1. AUTO QUEST TURN ====================
        if activeFeature == "Quest" then
            local activeQuest, qReason = GetPrioritizedActiveQuest()
            if not activeQuest then
                UpdateFeatureStatus("Quest", "Idle: " .. tostring(qReason), "All Quests Complete", "Reward: -", Color3.fromRGB(180, 180, 180))
                continue
            end
            
            if activeQuest.Type == "Open" then
                local ready, cdLeft = CheckCaseCooldown(activeQuest.Target, 5)
                if not ready then
                    UpdateFeatureStatus("Quest", "Waiting for Cooldown (" .. string.format("%.1fs", cdLeft) .. ")", "Target: " .. activeQuest.Title .. " (" .. activeQuest.Current .. "/" .. activeQuest.Requirement .. ")", "Reward: " .. activeQuest.Reward .. " M", Color3.fromRGB(241, 196, 15))
                    SetGlobalStatus("Quest: Waiting for Cooldown (" .. string.format("%.1fs", cdLeft) .. ")", Color3.fromRGB(241, 196, 15))
                    continue
                end
                
                local needed = math.max(1, activeQuest.Requirement - activeQuest.Current)
                local batchQty = math.clamp(math.min(needed, 5), 1, 5)
                
                SetGlobalStatus("Quest: Opening " .. activeQuest.Title .. " x" .. batchQty, Color3.fromRGB(46, 204, 113))
                UpdateFeatureStatus("Quest", "Opening " .. activeQuest.Title .. " x" .. batchQty, "Progress: " .. activeQuest.Current .. "/" .. activeQuest.Requirement, "Reward: " .. activeQuest.Reward .. " M", Color3.fromRGB(46, 204, 113))
                local ok, res = ExecuteOpenBatch(activeQuest.Target, batchQty, "Quest", true)
                if ok then
                    -- Re-read actual server-replicated quest state directly from PlayerData.Quests
                    local updatedQuest = nil
                    local checkStart = os.clock()
                    while os.clock() - checkStart < 1.2 do
                        local foundMatching = false
                        for _, q in ipairs(pData.Quests:GetChildren()) do
                            local qType = q.Value or "Open"
                            local subject = (q:FindFirstChild("Subject") and q.Subject.Value) or ""
                            if qType == activeQuest.Type and subject == activeQuest.Target then
                                foundMatching = true
                                local completed = (q:FindFirstChild("Completed") and q.Completed.Value == true)
                                local prog = (q:FindFirstChild("Progress") and q.Progress.Value) or 0
                                local req = (q:FindFirstChild("Requirement") and q.Requirement.Value) or activeQuest.Requirement
                                if completed or prog >= req then
                                    updatedQuest = { Completed = true, Progress = prog, Requirement = req }
                                elseif prog > activeQuest.Current then
                                    updatedQuest = { Completed = false, Progress = prog, Requirement = req }
                                end
                                break
                            end
                        end
                        if not foundMatching then
                            -- Quest was completed and removed/replaced by the server
                            updatedQuest = { Completed = true, Progress = activeQuest.Requirement, Requirement = activeQuest.Requirement }
                            break
                        end
                        if updatedQuest then
                            break
                        end
                        task.wait(0.1)
                    end
                    
                    if updatedQuest and updatedQuest.Completed then
                        LogActivity("Quest COMPLETED: " .. activeQuest.Title .. "! Discarding completed target.")
                        UpdateFeatureStatus("Quest", "Quest Completed!", "Refreshing next quest...", "Reward: " .. activeQuest.Reward .. " M", Color3.fromRGB(46, 204, 113))
                        SetGlobalStatus("Quest Completed! (" .. activeQuest.Title .. ")", Color3.fromRGB(46, 204, 113))
                        
                        -- Immediately query and select the next incomplete quest
                        local nextQuest, nextReason = GetPrioritizedActiveQuest()
                        if nextQuest then
                            LogActivity("Next Quest Selected: " .. nextQuest.Title .. " (Reward: " .. nextQuest.Reward .. " Mantra)")
                            UpdateFeatureStatus("Quest", "Next: " .. nextQuest.Title, "Progress: " .. nextQuest.Current .. "/" .. nextQuest.Requirement, "Reward: " .. nextQuest.Reward .. " M", Color3.fromRGB(52, 152, 219))
                            SetGlobalStatus("Quest: Next -> " .. nextQuest.Title, Color3.fromRGB(52, 152, 219))
                        else
                            UpdateFeatureStatus("Quest", "All Quests Complete", "No remaining quests", "Reward: -", Color3.fromRGB(180, 180, 180))
                            SetGlobalStatus("All Quests Completed", Color3.fromRGB(46, 204, 113))
                        end
                    else
                        local liveProg = (updatedQuest and updatedQuest.Progress) or math.min(activeQuest.Current + #res, activeQuest.Requirement)
                        LogActivity("Quest Progress: " .. liveProg .. "/" .. activeQuest.Requirement .. " (" .. activeQuest.Title .. ")")
                        UpdateFeatureStatus("Quest", "In Progress", "Progress: " .. liveProg .. "/" .. activeQuest.Requirement, "Reward: " .. activeQuest.Reward .. " M", Color3.fromRGB(46, 204, 113))
                        SetGlobalStatus("Quest: " .. activeQuest.Title .. " (" .. liveProg .. "/" .. activeQuest.Requirement .. ")", Color3.fromRGB(46, 204, 113))
                    end
                else
                    UpdateFeatureStatus("Quest", tostring(res), "Progress: " .. activeQuest.Current .. "/" .. activeQuest.Requirement, "Reward: " .. activeQuest.Reward .. " M", Color3.fromRGB(241, 196, 15))
                    SetGlobalStatus("Quest: " .. tostring(res), Color3.fromRGB(241, 196, 15))
                end
                
            elseif activeQuest.Type == "Play" or activeQuest.Type == "Win" then
                -- Authoritative reconciliation: verify current quest is still active & incomplete in PlayerData.Quests
                local isQuestStillActive = false
                local liveProg = activeQuest.Current
                local liveReq = activeQuest.Requirement
                local liveReward = activeQuest.Reward
                
                if pData and pData:FindFirstChild("Quests") then
                    for _, q in ipairs(pData.Quests:GetChildren()) do
                        local qType = q.Value or "Open"
                        local subject = (q:FindFirstChild("Subject") and q.Subject.Value) or ""
                        local targetKey = (qType == "Win" and (subject ~= "" and subject or "CLASSIC") or subject)
                        if qType == activeQuest.Type and targetKey == activeQuest.Target then
                            local comp = (q:FindFirstChild("Completed") and q.Completed.Value == true)
                            local prog = (q:FindFirstChild("Progress") and q.Progress.Value) or 0
                            local req = (q:FindFirstChild("Requirement") and q.Requirement.Value) or liveReq
                            if not comp and prog < req then
                                isQuestStillActive = true
                                liveProg = prog
                                liveReq = req
                                liveReward = tonumber(q:FindFirstChild("Reward") and q.Reward.Value) or liveReward
                                activeQuest.Current = liveProg
                                activeQuest.Requirement = liveReq
                                activeQuest.Reward = liveReward
                            end
                            break
                        end
                    end
                end
                
                -- If current quest completed, disappeared, or rotated: release stale battle state immediately
                if not isQuestStillActive then
                    LogActivity("Quest COMPLETED / Rotated (" .. activeQuest.Title .. "). Releasing stale battle references.")
                    local oldBattle = FindMyActiveBattle()
                    if oldBattle then
                        local bId = tonumber(oldBattle.Name) or oldBattle.Name
                        local started = oldBattle:FindFirstChild("Started") and oldBattle.Started.Value
                        if not started and LeaveBattleRemote then
                            pcall(function() LeaveBattleRemote:InvokeServer(bId) end)
                        end
                    end
                    ActiveBattleId = nil
                    BattleLobbyCreatedTime = 0
                    SetBattleMatchUIHidden(false)
                    
                    local nextQuest, nextReason = GetPrioritizedActiveQuest()
                    if nextQuest then
                        LogActivity("Next Quest Selected: " .. nextQuest.Title .. " (Reward: " .. nextQuest.Reward .. " Mantra)")
                        UpdateFeatureStatus("Quest", "Next: " .. nextQuest.Title, "Progress: " .. nextQuest.Current .. "/" .. nextQuest.Requirement, "Reward: " .. nextQuest.Reward .. " M", Color3.fromRGB(52, 152, 219))
                        SetGlobalStatus("Quest: Next -> " .. nextQuest.Title, Color3.fromRGB(52, 152, 219))
                    else
                        UpdateFeatureStatus("Quest", "All Quests Complete", "No remaining quests", "Reward: -", Color3.fromRGB(180, 180, 180))
                        SetGlobalStatus("All Quests Completed", Color3.fromRGB(46, 204, 113))
                    end
                    continue
                end
                
                local myBattle = FindMyActiveBattle()
                if myBattle then
                    local battleId = tonumber(myBattle.Name) or myBattle.Name
                    ActiveBattleId = battleId
                    local ended = myBattle:FindFirstChild("Ended") and myBattle.Ended.Value
                    
                    if not ended then
                        local started = myBattle:FindFirstChild("Started") and myBattle.Started.Value
                        
                        -- Check for stalled unstarted lobby watchdog (> 18 seconds)
                        if not started then
                            if BattleLobbyCreatedTime > 0 and (os.time() - BattleLobbyCreatedTime) > 18 then
                                LogActivity("Battle #" .. battleId .. " lobby timed out. Resetting.")
                                if LeaveBattleRemote then
                                    pcall(function() LeaveBattleRemote:InvokeServer(battleId) end)
                                end
                                ActiveBattleId = nil
                                BattleLobbyCreatedTime = 0
                                BattleCooldownUntil = os.time() + 3
                                SetBattleMatchUIHidden(false)
                                continue
                            end
                        else
                            BattleLobbyCreatedTime = 0 -- Match started successfully
                        end
                        
                        local stateText = started and "Match In Progress" or "Waiting for Match Start"
                        SetGlobalStatus("Quest: Battle #" .. battleId .. " (" .. stateText .. ")", Color3.fromRGB(52, 152, 219))
                        UpdateFeatureStatus("Battle", stateText .. " (#" .. battleId .. ")", "Mode: " .. tostring(activeQuest.Target), "Active", Color3.fromRGB(52, 152, 219))
                        UpdateFeatureStatus("Quest", "Battle #" .. battleId .. " (" .. stateText .. ")", "Progress: " .. activeQuest.Current .. "/" .. activeQuest.Requirement, "Reward: " .. activeQuest.Reward .. " M", Color3.fromRGB(52, 152, 219))
                        SetBattleMatchUIHidden(true)
                        continue
                    else
                        UpdateFeatureStatus("Battle", "Match Ended (#" .. battleId .. ")", "Leaving lobby...", "Complete", Color3.fromRGB(46, 204, 113))
                        if LeaveBattleRemote then
                            pcall(function() LeaveBattleRemote:InvokeServer(battleId) end)
                        end
                        pcall(function()
                            local bIdVal = LocalPlayer.PlayerGui.Windows["Case Battles"].BattlesScript.BattleId
                            if bIdVal then bIdVal.Value = 0 end
                        end)
                        SetBattleMatchUIHidden(false)
                        ActiveBattleId = nil
                        BattleLobbyCreatedTime = 0
                        BattleCooldownUntil = os.time() + 4
                        continue
                    end
                else
                    ActiveBattleId = nil
                    BattleLobbyCreatedTime = 0
                    UpdateFeatureStatus("Battle", "No Active Battle", "Lobby: None", "Ready", Color3.fromRGB(180, 180, 180))
                    local now = os.time()
                    if BattleCooldownUntil > now then
                        local remaining = BattleCooldownUntil - now
                        SetGlobalStatus("Quest: Waiting for Battle Reset (" .. remaining .. "s)", Color3.fromRGB(241, 196, 15))
                        UpdateFeatureStatus("Quest", "Waiting for Battle Reset (" .. remaining .. "s)", "Progress: " .. activeQuest.Current .. "/" .. activeQuest.Requirement, "Reward: " .. activeQuest.Reward .. " M", Color3.fromRGB(241, 196, 15))
                        continue
                    end
                    
                    local eligibleCase = FindLowestPriceCase()
                    local affordable, reason = CanAfford(eligibleCase, 1)
                    if not affordable then
                        SetGlobalStatus("Quest: Battle Blocked (" .. reason .. ")", Color3.fromRGB(231, 76, 60))
                        UpdateFeatureStatus("Quest", "Battle Blocked: " .. reason, "Progress: " .. activeQuest.Current .. "/" .. activeQuest.Requirement, "Reward: " .. activeQuest.Reward .. " M", Color3.fromRGB(231, 76, 60))
                        continue
                    end
                    
                    SetGlobalStatus("Quest: Creating Battle Lobby...", Color3.fromRGB(241, 196, 15))
                    local success, bId = pcall(function()
                        return CreateBattleFunction:InvokeServer({eligibleCase}, 2, activeQuest.Target, false)
                    end)
                    
                    if success and bId then
                        local battleId = tonumber(bId)
                        ActiveBattleId = battleId
                        BattleLobbyCreatedTime = os.time()
                        BattleCooldownUntil = os.time() + 4
                        LogActivity("Quest Created Battle #" .. battleId .. " (" .. activeQuest.Target .. ")")
                        if AddBotRemote then
                            task.spawn(function()
                                pcall(function() AddBotRemote:FireServer(battleId, LocalPlayer) end)
                            end)
                        end
                        SetBattleMatchUIHidden(true)
                        SetGlobalStatus("Quest: Battle #" .. battleId .. " Lobby Active", Color3.fromRGB(52, 152, 219))
                        UpdateFeatureStatus("Battle", "Lobby #" .. battleId .. " Created", "Bot Invited", "Active", Color3.fromRGB(52, 152, 219))
                    else
                        BattleCooldownUntil = os.time() + 6
                        SetGlobalStatus("Quest: Lobby Standby - Cooldown (6s)", Color3.fromRGB(241, 196, 15))
                        UpdateFeatureStatus("Quest", "Waiting for Battle Cooldown (6s)", "Lobby standby", "Reward: " .. activeQuest.Reward .. " M", Color3.fromRGB(241, 196, 15))
                    end
                end
            end

        -- ==================== 2. AUTO CASE LEVEL TURN ====================
        elseif activeFeature == "Level" then
            local exp = GetPlayerCurrency("Experience")
            local levelQueue = {}
            for id, c in pairs(CasesModule) do
                if c.XPRequirement and c.XPRequirement > 0 and c.XPRequirement <= exp then
                    table.insert(levelQueue, {
                        Id = id,
                        Name = c.Name,
                        XP = c.XPRequirement,
                        Price = c.Price or 0
                    })
                end
            end
            table.sort(levelQueue, function(a, b) return a.XP < b.XP end)
            
            if #levelQueue > 0 then
                -- Search across eligible cases in queue for one that is ready, starting from LevelQueueIndex
                local chosenCase = nil
                local minCooldownFound = math.huge
                local minCooldownCaseName = ""
                local queueLen = #levelQueue
                
                for offset = 0, queueLen - 1 do
                    local checkIdx = ((LevelQueueIndex - 1 + offset) % queueLen) + 1
                    local cand = levelQueue[checkIdx]
                    local ready, cdLeft = CheckCaseCooldown(cand.Id, 1)
                    if ready then
                        chosenCase = cand
                        LevelQueueIndex = (checkIdx % queueLen) + 1 -- advance cursor for next turn
                        break
                    else
                        if cdLeft < minCooldownFound then
                            minCooldownFound = cdLeft
                            minCooldownCaseName = cand.Name
                        end
                    end
                end
                
                if chosenCase then
                    SetGlobalStatus("Case Level: Opening " .. chosenCase.Name, Color3.fromRGB(155, 89, 182))
                    local ok, res = ExecuteOpenBatch(chosenCase.Id, 1, "LevelOpener", false)
                    if ok and typeof(res) == "table" and #res > 0 then
                        local wonItem = res[1] and res[1].Item or "Item"
                        LogActivity("Case Level: Opened " .. chosenCase.Name .. " -> " .. wonItem)
                        UpdateFeatureStatus("Level", "Won: " .. wonItem, "Case: " .. chosenCase.Name .. " (Success)", "XP: " .. exp, Color3.fromRGB(46, 204, 113))
                    else
                        UpdateFeatureStatus("Level", tostring(res), "Case: " .. chosenCase.Name, "XP: " .. exp, Color3.fromRGB(241, 196, 15))
                    end
                else
                    -- All eligible level cases are currently on cooldown; cleanly release scheduler turn
                    local cdStr = (minCooldownFound < 3600) and string.format("%ds", math.ceil(minCooldownFound)) or string.format("%.1fh", minCooldownFound / 3600)
                    UpdateFeatureStatus("Level", "Queue Cooling Down (" .. cdStr .. ")", "Next: " .. minCooldownCaseName, "Eligible: " .. queueLen .. " cases", Color3.fromRGB(241, 196, 15))
                end
            else
                UpdateFeatureStatus("Level", "No cases unlocked for XP", "Req XP not met", "XP: " .. exp, Color3.fromRGB(180, 180, 180))
            end

        -- ==================== 3. AUTO CASE OPENER TURN ====================
        elseif activeFeature == "Opener" then
            local cData = CasesModule[SelectedCaseKey]
            local cName = cData and cData.Name or SelectedCaseKey
            local ready, cdLeft = CheckCaseCooldown(SelectedCaseKey, OpenQuantity)
            if not ready then
                UpdateFeatureStatus("Opener", "Waiting for Cooldown (" .. string.format("%.1fs", cdLeft) .. ")", "Case: " .. cName .. " (x" .. OpenQuantity .. ")", "Ready in " .. string.format("%.1fs", cdLeft), Color3.fromRGB(241, 196, 15))
                continue
            end
            
            SetGlobalStatus("Opener: Opening " .. cName .. " x" .. OpenQuantity, Color3.fromRGB(52, 152, 219))
            local ok, res = ExecuteOpenBatch(SelectedCaseKey, OpenQuantity, "AutoOpener", false)
            if ok then
                local won = res[1] and res[1].Item or "Item"
                LogActivity("Opener: " .. cName .. " -> " .. won)
                UpdateFeatureStatus("Opener", "Won: " .. won, "Case: " .. cName .. " (x" .. OpenQuantity .. ")", "Confirmed", Color3.fromRGB(46, 204, 113))
            else
                UpdateFeatureStatus("Opener", tostring(res), "Case: " .. cName .. " (x" .. OpenQuantity .. ")", "Waiting", Color3.fromRGB(241, 196, 15))
            end

        -- ==================== 4. AUTO SELL TURN ====================
        elseif activeFeature == "Sell" then
            local inv = pData:FindFirstChild("Inventory")
            if inv and SellFunction then
                local sellBatch = {}
                local totalBatchValue = 0
                for _, itemObj in ipairs(inv:GetChildren()) do
                    local iName = itemObj.Name
                    local iData = ItemsModule[iName]
                    if iData and not itemObj:GetAttribute("Locked") and not itemObj:GetAttribute("Escrow") then
                        local wear = itemObj:GetAttribute("Wear") or "Factory New"
                        local isStattrak = itemObj:GetAttribute("Stattrak") == true
                        local wearData = iData.Wears and iData.Wears[wear]
                        local price = 0
                        if wearData then
                            price = isStattrak and (wearData.StatTrak or wearData.Normal or 0) or (wearData.Normal or 0)
                        end
                        
                        if price > 0 and price < SellPriceThreshold then
                            totalBatchValue = totalBatchValue + price
                            table.insert(sellBatch, {
                                Name = iName,
                                Wear = wear,
                                Stattrak = isStattrak,
                                Age = itemObj:GetAttribute("TimeObtained") or 0,
                                UUID = itemObj:GetAttribute("UUID") or 0
                            })
                            if #sellBatch >= 20 then break end
                        end
                    end
                end
                
                if #sellBatch > 0 then
                    SetGlobalStatus("Selling " .. #sellBatch .. " items priced < " .. SellPriceThreshold, Color3.fromRGB(230, 126, 34))
                    local success, res = pcall(function()
                        return SellFunction:InvokeServer(sellBatch)
                    end)
                    if success and res ~= nil then
                        TotalItemsSold = TotalItemsSold + #sellBatch
                        TotalSaleProceeds = TotalSaleProceeds + totalBatchValue
                        LogActivity("Sold " .. #sellBatch .. " items for $" .. string.format("%.2f", totalBatchValue))
                        UpdateFeatureStatus("Sell", "Sold " .. #sellBatch .. " items ($" .. string.format("%.2f", totalBatchValue) .. ")", "Total Sold: " .. TotalItemsSold .. " ($" .. string.format("%.2f", TotalSaleProceeds) .. ")", "Threshold: < " .. SellPriceThreshold, Color3.fromRGB(46, 204, 113))
                    else
                        UpdateFeatureStatus("Sell", "Server rejected sell batch", "Remaining eligible: " .. #sellBatch, "Threshold: < " .. SellPriceThreshold, Color3.fromRGB(231, 76, 60))
                    end
                else
                    UpdateFeatureStatus("Sell", "Idle: No items < " .. SellPriceThreshold, "Total Sold: " .. TotalItemsSold .. " ($" .. string.format("%.2f", TotalSaleProceeds) .. ")", "Threshold: < " .. SellPriceThreshold, Color3.fromRGB(180, 180, 180))
                end
            end
        end
    end
end)


-- Money Tracker Live Update Thread
task.spawn(function()
    while ScriptRunning do
        local pData = LocalPlayer:FindFirstChild("PlayerData")
        local currs = pData and pData:FindFirstChild("Currencies")
        local balObj = currs and currs:FindFirstChild("Balance")
        if balObj and typeof(balObj.Value) == "number" then
            if StartingMoney == nil then
                StartingMoney = balObj.Value
                if MTStartVal then
                    MTStartVal.Text = FormatMoney(StartingMoney)
                end
            end
            
            local currentBal = balObj.Value
            local netProfit = currentBal - StartingMoney
            local elapsedSecs = math.floor(os.clock() - TrackerStartTime)
            local hours = math.floor(elapsedSecs / 3600)
            local mins = math.floor((elapsedSecs % 3600) / 60)
            local secs = elapsedSecs % 60
            local timeStr = string.format("%02d:%02d:%02d", hours, mins, secs)
            
            if MTCurrVal then
                MTCurrVal.Text = FormatMoney(currentBal)
            end
            
            if MTProfitVal then
                if netProfit > 0.001 then
                    MTProfitVal.Text = "+ " .. FormatMoney(netProfit)
                    MTProfitVal.TextColor3 = Color3.fromRGB(46, 204, 113)
                elseif netProfit < -0.001 then
                    MTProfitVal.Text = "- " .. FormatMoney(math.abs(netProfit))
                    MTProfitVal.TextColor3 = Color3.fromRGB(231, 76, 60)
                else
                    MTProfitVal.Text = "+ $0.00"
                    MTProfitVal.TextColor3 = Color3.fromRGB(200, 205, 220)
                end
            end
            
            if MTEndTimeVal then
                MTEndTimeVal.Text = timeStr
            end
        end
        task.wait(0.5)
    end
end)

-- Clean exit cleanup
local function CleanupInstance()
    ScriptRunning = false
    if MoneyTrackerFrame and MoneyTrackerFrame.Parent then
        MoneyTrackerFrame:Destroy()
    end
    for _, conn in ipairs(EventConnections) do
        pcall(function() conn:Disconnect() end)
    end
    EventConnections = {}
    
    local pg = LocalPlayer:FindFirstChild("PlayerGui")
    if pg then
        local battleGui = pg:FindFirstChild("Battle")
        if battleGui then
            battleGui.Enabled = false
            local bf = battleGui:FindFirstChild("BattleFrame")
            if bf then bf.Visible = false end
        end
        local openAnim = pg:FindFirstChild("OpenAnimation")
        if openAnim then openAnim.Enabled = true end
        local mainGui = pg:FindFirstChild("Main")
        if mainGui then mainGui.Enabled = true end
        local winGui = pg:FindFirstChild("Windows")
        if winGui then winGui.Enabled = true end
    end
end

_G.ParadiseHubCleanup = CleanupInstance

CloseBtn.MouseButton1Click:Connect(function()
    CleanupInstance()
    ScreenGui:Destroy()
end)

SetGlobalStatus("Hub V21 Initialized: Tabbed Dashboard Active.", Color3.fromRGB(46, 204, 113))
LogActivity("Case Paradise Auto Hub V21 Loaded.")
print("[Case Paradise Auto Hub V21] Initialized and Loaded.")
