--[[
    ================================================================
    CASE PARADISE - AUTOMATION HUB V17
    ================================================================
    Architectural Upgrades:
    1. PRECISE GAME-VERIFIED COOLDOWN CONTROLLER:
       - Server cooldown analysis reveals Case Paradise enforces an active
         server-side cooldown of 3.0s (for single cases) and 3.8s (for 5-case batches).
       - Remotes.CheckCooldown tracks long-term case timers (Free cases, Level cases).
       - V17 enforces a centralized ServerCooldownExpire clock.
       - Level cases use Remotes.CheckCooldown:InvokeServer(caseKey) timestamp check.
       - If waiting for cooldown, cleanly yields scheduler turn without blocking.
    2. FIXED AUTO CASE LEVEL PROGRESSION & PARAMETERS:
       - Regular cases use OpenCaseFunction:InvokeServer(caseKey, quantity, true, nil).
       - Level cases require OpenCaseFunction:InvokeServer(caseKey, quantity, false, false).
       - Implemented rotating LevelQueueIndex scanning across all unlocked level cases
         (LEVEL10 through LEVEL70). Automatically advances to available cases and skips
         cases on cooldown.
    3. UNIFIED RESPONSIVE DASHBOARD & SCROLLING:
       - ClipsDescendants = true with AutomaticCanvasSize = Enum.AutomaticSize.Y.
       - UIPadding and layout constraints prevent text/card clipping or overlap.
       - 6 persistent cards: Auto Quest, Mantra Mode, Auto Case Level, Auto Opener, Auto Sell, Battle Tracker.
       - Real-time timestamped Activity Log.
    4. PERSISTENT FLOATING MONEY TRACKER (NEW IN V17):
       - Floating draggable widget tracking:
         * Starting Balance (exact in-game cash at script start)
         * Current Balance (live verified PlayerData.Currencies.Balance)
         * Net Profit/Loss (+ for net profit in green, - for net loss in red)
         * Elapsed Time (HH:MM:SS)
       - Persists across all tabs and cleanly resets upon script reload.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
-- Safely remove existing hub instances
if PlayerGui:FindFirstChild("ParadiseAutoHub") then
    PlayerGui.ParadiseAutoHub:Destroy()
end
if CoreGui:FindFirstChild("ParadiseAutoHub") then
    CoreGui.ParadiseAutoHub:Destroy()
end
-- Remotes
local Remotes = ReplicatedStorage:WaitForChild("Remotes", 10)
local OpenCaseFunction = Remotes and Remotes:WaitForChild("OpenCase", 10)
local SellFunction = Remotes and Remotes:WaitForChild("Sell", 10)
local CreateBattleFunction = Remotes and Remotes:WaitForChild("CreateBattle", 10)
local CheckCooldownFunction = Remotes and Remotes:WaitForChild("CheckCooldown", 10)
-- Modules
local CasesModule = {}
local QuestsModule = {}
local ItemsModule = {}
pcall(function()
    local cMod = ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("Cases", 5)
    if cMod and cMod:IsA("ModuleScript") then
        CasesModule = require(cMod)
    end
end)
pcall(function()
    local qMod = ReplicatedStorage:WaitForChild("Quests", 5)
    if qMod and qMod:IsA("ModuleScript") then
        QuestsModule = require(qMod)
    end
end)
pcall(function()
    local iMod = ReplicatedStorage:WaitForChild("Modules", 5):WaitForChild("Items", 5)
    if iMod and iMod:IsA("ModuleScript") then
        ItemsModule = require(iMod)
    end
end)
-- Automation State
local AutoQuestEnabled = false
local AutoLevelEnabled = false
local AutoOpenerEnabled = false
local AutoSellEnabled = false
local SelectedCase = "Starter"
local OpenQuantity = 1
local MantraTargetCase = "Yin Yang"
local MantraThreshold = 100
local MantraOpenCount = 5
local MantraModeEnabled = false
local AutoSellRarity = "Common"
local SellPriceThreshold = 500
local AutoSellKeepStatTrak = true
local BattleMatchId = nil
local InBattleMatch = false
local BattleGuiSuppressed = false
local ServerCooldownExpire = 0
local FeatureCards = {}
local ActivityLogs = {}
local LogLabels = {}
local MantraModeEngaged = false
local MantraOpeningsCompleted = 0
local LevelQueueIndex = 1
local TotalItemsSold = 0
local TotalSaleProceeds = 0
local ScriptRunning = true
local TrackerStartTime = os.clock()
local StartingMoney = nil
local EventConnections = {}
-- Create UI Hierarchy
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "ParadiseAutoHub"
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")
local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Size = UDim2.new(0, 520, 0, 640)
MainFrame.Position = UDim2.new(0.5, -260, 0.5, -320)
MainFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 28)
MainFrame.BorderSizePixel = 0
MainFrame.ClipsDescendants = true
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui
local MainCorner = Instance.new("UICorner")
MainCorner.CornerRadius = UDim.new(0, 8)
MainCorner.Parent = MainFrame
local MainStroke = Instance.new("UIStroke")
MainStroke.Color = Color3.fromRGB(45, 50, 62)
MainStroke.Thickness = 1.5
MainStroke.Parent = MainFrame
-- Header
local Header = Instance.new("Frame")
Header.Name = "Header"
Header.Size = UDim2.new(1, 0, 0, 42)
Header.BackgroundColor3 = Color3.fromRGB(26, 29, 36)
Header.BorderSizePixel = 0
Header.Parent = MainFrame
local HeaderCorner = Instance.new("UICorner")
HeaderCorner.CornerRadius = UDim.new(0, 8)
HeaderCorner.Parent = Header
local TitleLabel = Instance.new("TextLabel")
TitleLabel.Name = "Title"
TitleLabel.Size = UDim2.new(1, -50, 1, 0)
TitleLabel.Position = UDim2.new(0, 14, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "Case Paradise | Auto Farm Hub v17"
TitleLabel.TextColor3 = Color3.fromRGB(240, 240, 240)
TitleLabel.TextSize = 14
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = Header
local CloseBtn = Instance.new("TextButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Size = UDim2.new(0, 26, 0, 26)
CloseBtn.Position = UDim2.new(1, -34, 0.5, -13)
CloseBtn.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
CloseBtn.Text = "X"
CloseBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
CloseBtn.TextSize = 12
CloseBtn.Font = Enum.Font.GothamBold
CloseBtn.Parent = Header
local CloseCorner = Instance.new("UICorner")
CloseCorner.CornerRadius = UDim.new(0, 6)
CloseCorner.Parent = CloseBtn
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
-- Tabs Header
local TabBar = Instance.new("Frame")
TabBar.Name = "TabBar"
TabBar.Size = UDim2.new(1, -20, 0, 32)
TabBar.Position = UDim2.new(0, 10, 0, 48)
TabBar.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
TabBar.BorderSizePixel = 0
TabBar.Parent = MainFrame
local TabBarCorner = Instance.new("UICorner")
TabBarCorner.CornerRadius = UDim.new(0, 6)
TabBarCorner.Parent = TabBar
local TabListLayout = Instance.new("UIListLayout")
TabListLayout.FillDirection = Enum.FillDirection.Horizontal
TabListLayout.SortOrder = Enum.SortOrder.LayoutOrder
TabListLayout.Padding = UDim.new(0, 4)
TabListLayout.Parent = TabBar
local TabPadding = Instance.new("UIPadding")
TabPadding.PaddingLeft = UDim.new(0, 4)
TabPadding.PaddingTop = UDim.new(0, 3)
TabPadding.PaddingBottom = UDim.new(0, 3)
TabPadding.Parent = TabBar
local ContentContainer = Instance.new("Frame")
ContentContainer.Name = "ContentContainer"
ContentContainer.Size = UDim2.new(1, -20, 1, -92)
ContentContainer.Position = UDim2.new(0, 10, 0, 84)
ContentContainer.BackgroundTransparency = 1
ContentContainer.Parent = MainFrame
local TabButtons = {}
local TabPages = {}
local TabsList = {"Dashboard", "Quests & Mantra", "Case Openers", "Auto Sell"}
local function SwitchTab(targetName)
    for name, page in pairs(TabPages) do
        page.Visible = (name == targetName)
    end
    for name, btn in pairs(TabButtons) do
        if name == targetName then
            btn.BackgroundColor3 = Color3.fromRGB(0, 175, 255)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            btn.BackgroundColor3 = Color3.fromRGB(24, 27, 34)
            btn.TextColor3 = Color3.fromRGB(160, 165, 180)
        end
    end
end
for idx, tName in ipairs(TabsList) do
    local btn = Instance.new("TextButton")
    btn.Name = tName .. "Btn"
    btn.Size = UDim2.new(0.25, -4, 1, 0)
    btn.BackgroundColor3 = (idx == 1) and Color3.fromRGB(0, 175, 255) or Color3.fromRGB(24, 27, 34)
    btn.Text = tName
    btn.TextColor3 = (idx == 1) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(160, 165, 180)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 11
    btn.Parent = TabBar
    
    local bCorner = Instance.new("UICorner")
    bCorner.CornerRadius = UDim.new(0, 4)
    bCorner.Parent = btn
    
    btn.MouseButton1Click:Connect(function()
        SwitchTab(tName)
    end)
    TabButtons[tName] = btn
    
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
-- UI Helpers
local function CreateStatusCard(parent, titleText, initialStatus, layoutOrder)
    local card = Instance.new("Frame")
    card.Name = titleText:gsub("%s+", "") .. "Card"
    card.Size = UDim2.new(1, 0, 0, 68)
    card.BackgroundColor3 = Color3.fromRGB(26, 29, 36)
    card.BorderSizePixel = 0
    card.LayoutOrder = layoutOrder
    card.Parent = parent
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 6)
    corner.Parent = card
    
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(38, 42, 53)
    stroke.Thickness = 1
    stroke.Parent = card
    
    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(0.6, 0, 0, 20)
    title.Position = UDim2.new(0, 12, 0, 8)
    title.BackgroundTransparency = 1
    title.Text = titleText
    title.TextColor3 = Color3.fromRGB(240, 240, 240)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 12
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = card
    
    local sub = Instance.new("TextLabel")
    sub.Size = UDim2.new(0.4, -12, 0, 20)
    sub.Position = UDim2.new(0.6, 0, 0, 8)
    sub.BackgroundTransparency = 1
    sub.Text = "-"
    sub.TextColor3 = Color3.fromRGB(150, 155, 170)
    sub.Font = Enum.Font.Gotham
    sub.TextSize = 11
    sub.TextXAlignment = Enum.TextXAlignment.Right
    sub.Parent = card
    
    local status = Instance.new("TextLabel")
    status.Size = UDim2.new(1, -24, 0, 18)
    status.Position = UDim2.new(0, 12, 0, 28)
    status.BackgroundTransparency = 1
    status.Text = initialStatus or "Idle: Disabled"
    status.TextColor3 = Color3.fromRGB(180, 180, 180)
    status.Font = Enum.Font.GothamSemibold
    status.TextSize = 11
    status.TextXAlignment = Enum.TextXAlignment.Left
    status.Parent = card
    
    local extra = Instance.new("TextLabel")
    extra.Size = UDim2.new(1, -24, 0, 16)
    extra.Position = UDim2.new(0, 12, 0, 46)
    extra.BackgroundTransparency = 1
    extra.Text = "-"
    extra.TextColor3 = Color3.fromRGB(130, 135, 150)
    extra.Font = Enum.Font.Gotham
    extra.TextSize = 10
    extra.TextXAlignment = Enum.TextXAlignment.Left
    extra.Parent = card
    
    return {Card = card, Title = title, Sub = sub, Status = status, Extra = extra}
end
local function CreateSection(parent, titleText)
    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(1, 0, 0, 26)
    frame.BackgroundTransparency = 1
    frame.Parent = parent
    
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.Text = string.upper(titleText)
    label.TextColor3 = Color3.fromRGB(0, 175, 255)
    label.Font = Enum.Font.GothamBold
    label.TextSize = 11
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.Parent = frame
    return frame
end
local function CreateButton(parent, text, bgColor)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 36)
    btn.BackgroundColor3 = bgColor or Color3.fromRGB(35, 40, 52)
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(240, 240, 240)
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 12
    btn.Parent = parent
    
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, 6)
    c.Parent = btn
    return btn
end
-- Build Dashboard Page
local DashPage = TabPages["Dashboard"]
local GlobalBar = Instance.new("Frame")
GlobalBar.Name = "GlobalBar"
GlobalBar.Size = UDim2.new(1, 0, 0, 44)
GlobalBar.BackgroundColor3 = Color3.fromRGB(18, 22, 30)
GlobalBar.BorderSizePixel = 0
GlobalBar.LayoutOrder = 1
GlobalBar.Parent = DashPage
local gbCorner = Instance.new("UICorner")
gbCorner.CornerRadius = UDim.new(0, 6)
gbCorner.Parent = GlobalBar
local gbStroke = Instance.new("UIStroke")
gbStroke.Color = Color3.fromRGB(0, 175, 255)
gbStroke.Thickness = 1
gbStroke.Parent = GlobalBar
local gbTitle = Instance.new("TextLabel")
gbTitle.Size = UDim2.new(1, -20, 0, 16)
gbTitle.Position = UDim2.new(0, 10, 0, 6)
gbTitle.BackgroundTransparency = 1
gbTitle.Text = "SCHEDULER STATUS:"
gbTitle.TextColor3 = Color3.fromRGB(0, 175, 255)
gbTitle.Font = Enum.Font.GothamBold
gbTitle.TextSize = 10
gbTitle.TextXAlignment = Enum.TextXAlignment.Left
gbTitle.Parent = GlobalBar
local gbStatus = Instance.new("TextLabel")
gbStatus.Name = "GlobalStatusText"
gbStatus.Size = UDim2.new(1, -20, 0, 18)
gbStatus.Position = UDim2.new(0, 10, 0, 22)
gbStatus.BackgroundTransparency = 1
gbStatus.Text = "Idle - Waiting for enabled features"
gbStatus.TextColor3 = Color3.fromRGB(200, 205, 220)
gbStatus.Font = Enum.Font.GothamSemibold
gbStatus.TextSize = 11
gbStatus.TextXAlignment = Enum.TextXAlignment.Left
gbStatus.Parent = GlobalBar
FeatureCards["Quest"] = CreateStatusCard(DashPage, "Auto Quest", "Idle: Not started", 2)
FeatureCards["Mantra"] = CreateStatusCard(DashPage, "Mantra Mode", "Disabled", 3)
FeatureCards["Level"] = CreateStatusCard(DashPage, "Auto Case Level", "Idle: Disabled", 4)
FeatureCards["Opener"] = CreateStatusCard(DashPage, "Auto Opener", "Idle: Disabled", 5)
FeatureCards["Sell"] = CreateStatusCard(DashPage, "Auto Sell", "Idle: Disabled", 6)
FeatureCards["Battle"] = CreateStatusCard(DashPage, "Battle Tracker", "No Active Battle", 7)
-- Feed Frame
local FeedFrame = Instance.new("Frame")
FeedFrame.Name = "FeedFrame"
FeedFrame.Size = UDim2.new(1, 0, 0, 90)
FeedFrame.BackgroundColor3 = Color3.fromRGB(15, 17, 22)
FeedFrame.BorderSizePixel = 0
FeedFrame.LayoutOrder = 8
FeedFrame.Parent = DashPage
local ffCorner = Instance.new("UICorner")
ffCorner.CornerRadius = UDim.new(0, 6)
ffCorner.Parent = FeedFrame
local ffTitle = Instance.new("TextLabel")
ffTitle.Size = UDim2.new(1, -16, 0, 20)
ffTitle.Position = UDim2.new(0, 8, 0, 4)
ffTitle.BackgroundTransparency = 1
ffTitle.Text = "RECENT ACTIVITY LOG:"
ffTitle.TextColor3 = Color3.fromRGB(140, 145, 160)
ffTitle.Font = Enum.Font.GothamBold
ffTitle.TextSize = 10
ffTitle.TextXAlignment = Enum.TextXAlignment.Left
ffTitle.Parent = FeedFrame
for i = 1, 3 do
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, -16, 0, 18)
    lbl.Position = UDim2.new(0, 8, 0, 22 + (i - 1) * 20)
    lbl.BackgroundTransparency = 1
    lbl.Text = ""
    lbl.TextColor3 = Color3.fromRGB(180, 185, 200)
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 10
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = FeedFrame
    table.insert(LogLabels, lbl)
end
-- Logging & Status Helpers
local function LogActivity(msg)
    local timeStr = os.date("%H:%M:%S")
    local fullMsg = "[" .. timeStr .. "] " .. msg
    table.insert(ActivityLogs, 1, fullMsg)
    if #ActivityLogs > 20 then
        table.remove(ActivityLogs, #ActivityLogs)
    end
    for i = 1, 3 do
        if LogLabels[i] then
            LogLabels[i].Text = ActivityLogs[i] or ""
        end
    end
end
local function SetGlobalStatus(statusText, color)
    gbStatus.Text = statusText
    gbStatus.TextColor3 = color or Color3.fromRGB(200, 205, 220)
end
local function UpdateFeatureStatus(featKey, statusText, subText, extraText, statusColor)
    local c = FeatureCards[featKey]
    if not c then return end
    if statusText then
        c.Status.Text = statusText
        c.Status.TextColor3 = statusColor or Color3.fromRGB(180, 180, 180)
    end
    if subText then
        c.Sub.Text = subText
    end
    if extraText then
        c.Extra.Text = extraText
    end
end
-- Money Formatting Helper
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
-- Currency Helper
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
-- Check server cooldown and case-specific timers
local function CheckCaseCooldown(caseKey, quantity)
    local nowClock = os.clock()
    if ServerCooldownExpire > nowClock then
        return false, ServerCooldownExpire - nowClock
    end
    
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
local function RecordOpeningCooldown(batchQty)
    local cdDuration = (batchQty and batchQty > 1) and 3.85 or 3.0
    ServerCooldownExpire = os.clock() + cdDuration
end
-- Build Quests & Mantra Page
local QMPage = TabPages["Quests & Mantra"]
CreateSection(QMPage, "Auto Quest System")
local QuestToggleBtn = CreateButton(QMPage, "Auto Quest: OFF", Color3.fromRGB(40, 45, 58))
QuestToggleBtn.MouseButton1Click:Connect(function()
    AutoQuestEnabled = not AutoQuestEnabled
    QuestToggleBtn.Text = "Auto Quest: " .. (AutoQuestEnabled and "ON" or "OFF")
    QuestToggleBtn.BackgroundColor3 = AutoQuestEnabled and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(40, 45, 58)
    LogActivity("Auto Quest toggled " .. (AutoQuestEnabled and "ON" or "OFF"))
    if not AutoQuestEnabled then
        UpdateFeatureStatus("Quest", "Idle: Disabled", "-", "-", Color3.fromRGB(180, 180, 180))
    end
end)
CreateSection(QMPage, "Mantra Threshold Mode")
local MantraToggleBtn = CreateButton(QMPage, "Mantra Threshold Mode: OFF", Color3.fromRGB(40, 45, 58))
MantraToggleBtn.MouseButton1Click:Connect(function()
    MantraModeEnabled = not MantraModeEnabled
    MantraToggleBtn.Text = "Mantra Threshold Mode: " .. (MantraModeEnabled and "ON" or "OFF")
    MantraToggleBtn.BackgroundColor3 = MantraModeEnabled and Color3.fromRGB(155, 89, 182) or Color3.fromRGB(40, 45, 58)
    LogActivity("Mantra Mode toggled " .. (MantraModeEnabled and "ON" or "OFF"))
    if not MantraModeEnabled then
        UpdateFeatureStatus("Mantra", "Disabled", "-", "-", Color3.fromRGB(180, 180, 180))
    end
end)
-- Build Case Openers Page
local COPage = TabPages["Case Openers"]
CreateSection(COPage, "Standard Auto Opener")
local OpenerToggleBtn = CreateButton(COPage, "Auto Opener: OFF", Color3.fromRGB(40, 45, 58))
OpenerToggleBtn.MouseButton1Click:Connect(function()
    AutoOpenerEnabled = not AutoOpenerEnabled
    OpenerToggleBtn.Text = "Auto Opener: " .. (AutoOpenerEnabled and "ON" or "OFF")
    OpenerToggleBtn.BackgroundColor3 = AutoOpenerEnabled and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(40, 45, 58)
    LogActivity("Auto Opener toggled " .. (AutoOpenerEnabled and "ON" or "OFF"))
    if not AutoOpenerEnabled then
        UpdateFeatureStatus("Opener", "Idle: Disabled", "-", "-", Color3.fromRGB(180, 180, 180))
    end
end)
local CaseSelectBtn = CreateButton(COPage, "Case: " .. SelectedCase, Color3.fromRGB(30, 34, 44))
CaseSelectBtn.MouseButton1Click:Connect(function()
    local caseList = {"Starter", "Common", "Rare", "Mil-Spec", "Classified", "Covert", "Yin Yang"}
    local curIdx = 1
    for i, c in ipairs(caseList) do
        if c == SelectedCase then curIdx = i break end
    end
    local nextIdx = (curIdx % #caseList) + 1
    SelectedCase = caseList[nextIdx]
    CaseSelectBtn.Text = "Case: " .. SelectedCase
    LogActivity("Selected case changed to: " .. SelectedCase)
end)
local BatchSelectBtn = CreateButton(COPage, "Batch Qty: " .. OpenQuantity, Color3.fromRGB(30, 34, 44))
BatchSelectBtn.MouseButton1Click:Connect(function()
    local options = {1, 2, 3, 4, 5}
    local curIdx = 1
    for i, o in ipairs(options) do
        if o == OpenQuantity then curIdx = i break end
    end
    local nextIdx = (curIdx % #options) + 1
    OpenQuantity = options[nextIdx]
    BatchSelectBtn.Text = "Batch Qty: " .. OpenQuantity
    LogActivity("Batch size set to: " .. OpenQuantity)
end)
CreateSection(COPage, "Auto Case Level")
local LevelToggleBtn = CreateButton(COPage, "Auto Case Level: OFF", Color3.fromRGB(40, 45, 58))
LevelToggleBtn.MouseButton1Click:Connect(function()
    AutoLevelEnabled = not AutoLevelEnabled
    LevelToggleBtn.Text = "Auto Case Level: " .. (AutoLevelEnabled and "ON" or "OFF")
    LevelToggleBtn.BackgroundColor3 = AutoLevelEnabled and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(40, 45, 58)
    LogActivity("Auto Case Level toggled " .. (AutoLevelEnabled and "ON" or "OFF"))
    if not AutoLevelEnabled then
        UpdateFeatureStatus("Level", "Idle: Disabled", "-", "-", Color3.fromRGB(180, 180, 180))
    end
end)
-- Build Auto Sell Page
local SellPage = TabPages["Auto Sell"]
CreateSection(SellPage, "Auto Sell System")
local SellToggleBtn = CreateButton(SellPage, "Auto Sell: OFF", Color3.fromRGB(40, 45, 58))
SellToggleBtn.MouseButton1Click:Connect(function()
    AutoSellEnabled = not AutoSellEnabled
    SellToggleBtn.Text = "Auto Sell: " .. (AutoSellEnabled and "ON" or "OFF")
    SellToggleBtn.BackgroundColor3 = AutoSellEnabled and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(40, 45, 58)
    LogActivity("Auto Sell toggled " .. (AutoSellEnabled and "ON" or "OFF"))
    if not AutoSellEnabled then
        UpdateFeatureStatus("Sell", "Idle: Disabled", "-", "-", Color3.fromRGB(180, 180, 180))
    end
end)
-- Execute Case Opening Batch
local function ExecuteOpenBatch(caseKey, quantity, requesterName, isQuest)
    if not OpenCaseFunction then
        return false, "Missing OpenCase Remote"
    end
    
    local ready, cdTime = CheckCaseCooldown(caseKey, quantity)
    if not ready then
        return false, "Waiting for Cooldown (" .. string.format("%.1fs", cdTime) .. ")"
    end
    
    local isLevelCase = false
    local cData = CasesModule[caseKey]
    if cData and (cData.XPRequirement or cData.Category == "Level" or tostring(caseKey):find("LEVEL")) then
        isLevelCase = true
    end
    
    local success, res = pcall(function()
        if isLevelCase then
            return OpenCaseFunction:InvokeServer(caseKey, quantity, false, false)
        else
            return OpenCaseFunction:InvokeServer(caseKey, quantity, true, nil)
        end
    end)
    
    RecordOpeningCooldown(quantity)
    
    if not success then
        return false, "Invoke Error: " .. tostring(res)
    end
    
    if res == nil or res == false then
        return false, "Server rejected request (Cooldown/Busy)"
    end
    
    if typeof(res) == "table" then
        return true, res
    end
    
    return true, {res}
end
-- Quest Parser & Evaluator
local function GetBestMantraQuest()
    local pd = LocalPlayer:FindFirstChild("PlayerData")
    if not pd then return nil end
    local questsFolder = pd:FindFirstChild("Quests")
    if not questsFolder then return nil end
    
    local candidates = {}
    for _, qInst in ipairs(questsFolder:GetChildren()) do
        local qId = qInst.Name
        local qDef = QuestsModule[qId] or {}
        local curProgress = 0
        local targetProgress = 1
        
        local curVal = qInst:FindFirstChild("Current") or qInst:FindFirstChild("Progress") or qInst:FindFirstChild("Value")
        if curVal and curVal:IsA("ValueBase") then
            curProgress = curVal.Value
        end
        local maxVal = qInst:FindFirstChild("Target") or qInst:FindFirstChild("Goal") or qInst:FindFirstChild("Max")
        if maxVal and maxVal:IsA("ValueBase") then
            targetProgress = maxVal.Value
        elseif qDef.Target then
            targetProgress = qDef.Target
        end
        
        local completed = (curProgress >= targetProgress)
        local mantraReward = 0
        if qDef.Reward and qDef.Reward.Mantra then
            mantraReward = qDef.Reward.Mantra
        elseif qDef.Mantra then
            mantraReward = qDef.Mantra
        end
        
        if not completed then
            table.insert(candidates, {
                Id = qId,
                Title = qDef.Title or qDef.Name or qId,
                Type = qDef.Type or "Unknown",
                TargetCase = qDef.Case or qDef.TargetCase or "Starter",
                Current = curProgress,
                Target = targetProgress,
                Mantra = mantraReward,
                Def = qDef
            })
        end
    end
    
    table.sort(candidates, function(a, b)
        return a.Mantra > b.Mantra
    end)
    
    return candidates[1]
end
-- Money Tracker Update Routine
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
-- Main Scheduler Loop
task.spawn(function()
    LogActivity("Case Paradise Auto Hub V17 Loaded.")
    local schedulerCycle = {"Quest", "Level", "Opener", "Sell"}
    local cycleIndex = 1
    
    while ScriptRunning do
        task.wait(0.35)
        
        local mantraBal = GetPlayerCurrency("Mantra")
        UpdateFeatureStatus("Mantra", MantraModeEnabled and (MantraModeEngaged and "Active Opening" or "Threshold Monitoring") or "Disabled", "Balance: " .. mantraBal .. " Mantra", "Openings: " .. MantraOpeningsCompleted .. " cases")
        
        -- Mantra Mode Priority
        if MantraModeEnabled and mantraBal >= MantraThreshold and not MantraModeEngaged then
            MantraModeEngaged = true
            MantraOpeningsCompleted = 0
            LogActivity("Mantra threshold reached (" .. mantraBal .. "). Opening " .. MantraTargetCase)
        end
        
        if MantraModeEngaged then
            if MantraOpeningsCompleted < MantraOpenCount then
                local needed = MantraOpenCount - MantraOpeningsCompleted
                local batch = math.min(5, needed)
                SetGlobalStatus("Mantra Mode: Opening " .. batch .. "x " .. MantraTargetCase, Color3.fromRGB(155, 89, 182))
                local ok, res = ExecuteOpenBatch(MantraTargetCase, batch, "MantraOpener", false)
                if ok then
                    MantraOpeningsCompleted = MantraOpeningsCompleted + batch
                    LogActivity("Mantra Mode: Opened " .. batch .. "x " .. MantraTargetCase .. " (" .. MantraOpeningsCompleted .. "/" .. MantraOpenCount .. ")")
                else
                    UpdateFeatureStatus("Mantra", tostring(res), nil, nil, Color3.fromRGB(241, 196, 15))
                end
                task.wait(0.5)
                continue
            else
                MantraModeEngaged = false
                LogActivity("Mantra Mode cycle completed.")
            end
        end
        
        -- Round Robin across enabled features
        local activeFeature = schedulerCycle[cycleIndex]
        cycleIndex = (cycleIndex % #schedulerCycle) + 1
        
        -- 1. AUTO QUEST TURN
        if activeFeature == "Quest" and AutoQuestEnabled then
            local bestQuest = GetBestMantraQuest()
            if bestQuest then
                UpdateFeatureStatus("Quest", "Active: " .. bestQuest.Title, "Reward: " .. bestQuest.Mantra .. " Mantra", "Progress: " .. bestQuest.Current .. "/" .. bestQuest.Target, Color3.fromRGB(52, 152, 219))
                
                if bestQuest.Type == "OpenCase" or bestQuest.Type == "Case" or tostring(bestQuest.Title):find("Open") then
                    local needed = math.max(1, bestQuest.Target - bestQuest.Current)
                    local batch = math.min(5, needed)
                    SetGlobalStatus("Quest: Opening " .. batch .. "x " .. bestQuest.TargetCase, Color3.fromRGB(52, 152, 219))
                    local ok, res = ExecuteOpenBatch(bestQuest.TargetCase, batch, "QuestOpener", true)
                    if ok then
                        LogActivity("Quest: Opened " .. batch .. " " .. bestQuest.TargetCase)
                    else
                        UpdateFeatureStatus("Quest", tostring(res), nil, nil, Color3.fromRGB(241, 196, 15))
                    end
                elseif bestQuest.Type == "Battle" or tostring(bestQuest.Title):find("Battle") then
                    if not InBattleMatch then
                        SetGlobalStatus("Quest: Creating Case Battle", Color3.fromRGB(230, 126, 34))
                        if CreateBattleFunction then
                            local s, res = pcall(function()
                                return CreateBattleFunction:InvokeServer(bestQuest.TargetCase or "Starter", 1, 2)
                            end)
                            if s and res then
                                InBattleMatch = true
                                BattleMatchId = res
                                LogActivity("Quest: Battle Lobby created (" .. tostring(res) .. ")")
                            end
                        end
                    end
                end
            else
                UpdateFeatureStatus("Quest", "All Quests Completed", "No active tasks", "-", Color3.fromRGB(46, 204, 113))
            end
            
        -- 2. AUTO CASE LEVEL TURN
        elseif activeFeature == "Level" and AutoLevelEnabled then
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
                        LevelQueueIndex = (checkIdx % queueLen) + 1
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
                    local cdStr = (minCooldownFound < 3600) and string.format("%ds", math.ceil(minCooldownFound)) or string.format("%.1fh", minCooldownFound / 3600)
                    UpdateFeatureStatus("Level", "Queue Cooling Down (" .. cdStr .. ")", "Next: " .. minCooldownCaseName, "Eligible: " .. queueLen .. " cases", Color3.fromRGB(241, 196, 15))
                end
            else
                UpdateFeatureStatus("Level", "No cases unlocked for XP", "Req XP not met", "XP: " .. exp, Color3.fromRGB(180, 180, 180))
            end
            
        -- 3. AUTO OPENER TURN
        elseif activeFeature == "Opener" and AutoOpenerEnabled then
            SetGlobalStatus("Opener: Opening " .. OpenQuantity .. "x " .. SelectedCase, Color3.fromRGB(46, 204, 113))
            local ok, res = ExecuteOpenBatch(SelectedCase, OpenQuantity, "AutoOpener", false)
            if ok then
                local won = (typeof(res) == "table" and res[1] and res[1].Item) and res[1].Item or "Items"
                LogActivity("Opener: Opened " .. OpenQuantity .. "x " .. SelectedCase .. " -> " .. won)
                UpdateFeatureStatus("Opener", "Last: " .. won, "Selected: " .. SelectedCase .. " (x" .. OpenQuantity .. ")", "Status: Ready", Color3.fromRGB(46, 204, 113))
            else
                UpdateFeatureStatus("Opener", tostring(res), "Selected: " .. SelectedCase, "-", Color3.fromRGB(241, 196, 15))
            end
            
        -- 4. AUTO SELL TURN
        elseif activeFeature == "Sell" and AutoSellEnabled then
            local inv = LocalPlayer.PlayerData:FindFirstChild("Inventory")
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
SetGlobalStatus("Hub V17 Initialized: Tabbed Dashboard & Money Tracker Active.", Color3.fromRGB(46, 204, 113))
LogActivity("Case Paradise Auto Hub V17 Loaded.")
print("[Case Paradise Auto Hub V17] Initialized and Loaded.")
