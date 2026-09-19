--[[
    🥚 Egg ESP — Ride A Pet  [FIXED v2]
    
    FIXES:
    • Now scans ALL egg sources:
        - Workspace.Plots.*.Eggs       (player plot eggs)
        - Workspace.RenderedEggs       (main map eggs — was MISSING, had 72 models!)
        - Workspace.Eggs               (misc eggs)
        - Workspace.*Egg standalone Models (AdminEgg, AsteroidEgg, etc.)
    • Added "🔍 Scan Map" button — manual full rescan on demand
    • Live scan counter shows how many eggs found per source
    • Individual egg-type toggles with Select All / Deselect All
    • Master ESP ON/OFF toggle
    • Real-time distance labels (Studs)
    • Clean, draggable UI with minimize
--]]

---------------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------------
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
local Camera      = workspace.CurrentCamera

---------------------------------------------------------------------------
-- STATE
---------------------------------------------------------------------------
local espEnabled    = true
local selectedTypes = {}   -- [eggName] = bool
local espLabels     = {}   -- [egg Model] = BillboardGui

---------------------------------------------------------------------------
-- COLOUR PALETTE
---------------------------------------------------------------------------
local C = {
    BG         = Color3.fromRGB(18,  18,  24),
    HEADER     = Color3.fromRGB(26,  26,  36),
    ACCENT     = Color3.fromRGB(120, 80, 220),
    ACCENT2    = Color3.fromRGB(80, 160, 255),
    SCAN       = Color3.fromRGB(40, 180, 120),
    SCAN_FLASH = Color3.fromRGB(80, 230, 160),
    TEXT       = Color3.fromRGB(230, 230, 240),
    SUBTEXT    = Color3.fromRGB(150, 150, 165),
    ON         = Color3.fromRGB(80,  210, 130),
    OFF        = Color3.fromRGB(220, 80,  80),
    ITEM_BG    = Color3.fromRGB(28,  28,  38),
    ITEM_HOVER = Color3.fromRGB(38,  38,  52),
    SCROLL_BAR = Color3.fromRGB(80,  80, 100),
    CHECK_ON   = Color3.fromRGB(100, 190, 255),
    CHECK_OFF  = Color3.fromRGB(55,  55,  70),
    BORDER     = Color3.fromRGB(50,  50,  68),
    LABEL_BG   = Color3.fromRGB(10,  10,  20),
    LABEL_TEXT = Color3.fromRGB(255, 255, 255),
    LABEL_DIST = Color3.fromRGB(120, 220, 255),
    INFO_BG    = Color3.fromRGB(22,  22,  32),
}

---------------------------------------------------------------------------
-- HELPERS
---------------------------------------------------------------------------
local function makeCorner(r, parent)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, r)
    c.Parent = parent
    return c
end

local function makeStroke(t, col, parent)
    local s = Instance.new("UIStroke")
    s.Thickness = t
    s.Color = col
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Parent = parent
    return s
end

local function makePadding(t, b, l, r, parent)
    local p = Instance.new("UIPadding")
    p.PaddingTop    = UDim.new(0, t)
    p.PaddingBottom = UDim.new(0, b)
    p.PaddingLeft   = UDim.new(0, l)
    p.PaddingRight  = UDim.new(0, r)
    p.Parent = parent
    return p
end

local function getEggPosition(egg)
    if egg and egg:IsDescendantOf(workspace) then
        local h = egg:FindFirstChild("Handle")
        if h and h:IsA("BasePart") then return h.Position end
        if egg.PrimaryPart then return egg.PrimaryPart.Position end
        for _, p in ipairs(egg:GetDescendants()) do
            if p:IsA("BasePart") then return p.Position end
        end
    end
    return nil
end

local function getPlayerPos()
    local char = LocalPlayer.Character
    if not char then return nil end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return hrp and hrp.Position or nil
end

---------------------------------------------------------------------------
-- COLLECT ALL EGGS — MULTI-SOURCE (THE FIX)
---------------------------------------------------------------------------
-- Returns: list of egg Models, plus a source breakdown table
local function getAllEggsInWorkspace()
    local eggs = {}
    local sourceCounts = {}

    local function addFromFolder(folder, sourceName)
        if not folder then return end
        local count = 0
        for _, child in ipairs(folder:GetDescendants()) do
            if child:IsA("Model") and child.Name:lower():find("egg")
                and child:IsDescendantOf(workspace) then
                table.insert(eggs, child)
                count += 1
            end
        end
        if count > 0 then
            sourceCounts[sourceName] = (sourceCounts[sourceName] or 0) + count
        end
    end

    -- 1. Player Plots (original source — small set)
    local plots = workspace:FindFirstChild("Plots")
    if plots then
        for _, plot in ipairs(plots:GetChildren()) do
            local f = plot:FindFirstChild("Eggs")
            if f then addFromFolder(f, "Plots") end
        end
    end

    -- 2. RenderedEggs — the main map eggs (was missing! ~72 models)
    addFromFolder(workspace:FindFirstChild("RenderedEggs"), "RenderedEggs")

    -- 3. Workspace.Eggs top-level folder
    addFromFolder(workspace:FindFirstChild("Eggs"), "WS.Eggs")

    -- 4. Standalone *Egg Models at workspace root (AdminEgg, AsteroidEgg, etc.)
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Model") and child.Name:lower():find("egg") then
            table.insert(eggs, child)
            sourceCounts["Standalone"] = (sourceCounts["Standalone"] or 0) + 1
        end
    end

    return eggs, sourceCounts
end

local function getUniqueEggTypes()
    local seen  = {}
    local types = {}
    local eggs  = getAllEggsInWorkspace()
    for _, egg in ipairs(eggs) do
        if not seen[egg.Name] then
            seen[egg.Name] = true
            table.insert(types, egg.Name)
        end
    end
    table.sort(types)
    return types
end

---------------------------------------------------------------------------
-- ESP LABEL CREATION / REMOVAL
---------------------------------------------------------------------------
local function createESPLabel(egg)
    if espLabels[egg] then return end
    local pos = getEggPosition(egg)
    if not pos then return end

    local bb = Instance.new("BillboardGui")
    bb.Name        = "EggESP_Label"
    bb.Adornee     = egg:FindFirstChild("Handle") or egg.PrimaryPart or egg:FindFirstChildWhichIsA("BasePart")
    bb.AlwaysOnTop = true
    bb.Size        = UDim2.new(0, 160, 0, 44)
    bb.StudsOffset = Vector3.new(0, 2.5, 0)
    bb.LightInfluence = 0
    bb.ResetOnSpawn   = false
    bb.Parent = game.CoreGui

    local bg = Instance.new("Frame")
    bg.Size = UDim2.new(1, 0, 1, 0)
    bg.BackgroundColor3 = C.LABEL_BG
    bg.BackgroundTransparency = 0.25
    bg.BorderSizePixel = 0
    bg.Parent = bb
    makeCorner(6, bg)
    makeStroke(1, C.ACCENT, bg)
    makePadding(4, 4, 8, 8, bg)

    local layout = Instance.new("UIListLayout")
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding   = UDim.new(0, 1)
    layout.Parent    = bg

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "EggName"
    nameLabel.Size = UDim2.new(1, 0, 0, 16)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = "🥚 " .. egg.Name
    nameLabel.TextColor3 = C.LABEL_TEXT
    nameLabel.TextScaled = true
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.LayoutOrder = 1
    nameLabel.Parent = bg

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "Distance"
    distLabel.Size = UDim2.new(1, 0, 0, 14)
    distLabel.BackgroundTransparency = 1
    distLabel.Text = "-- Studs"
    distLabel.TextColor3 = C.LABEL_DIST
    distLabel.TextScaled = true
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextXAlignment = Enum.TextXAlignment.Center
    distLabel.LayoutOrder = 2
    distLabel.Parent = bg

    espLabels[egg] = bb
end

local function removeESPLabel(egg)
    if espLabels[egg] then
        espLabels[egg]:Destroy()
        espLabels[egg] = nil
    end
end

local function refreshAllESP()
    for egg, _ in pairs(espLabels) do
        if not egg:IsDescendantOf(workspace)
            or not espEnabled
            or not selectedTypes[egg.Name] then
            removeESPLabel(egg)
        end
    end
    if espEnabled then
        local eggs = getAllEggsInWorkspace()
        for _, egg in ipairs(eggs) do
            if selectedTypes[egg.Name] and not espLabels[egg] then
                createESPLabel(egg)
            end
        end
    end
end

---------------------------------------------------------------------------
-- SCREEN GUI
---------------------------------------------------------------------------
pcall(function()
    local old = game.CoreGui:FindFirstChild("EggESP_GUI")
    if old then old:Destroy() end
end)

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name           = "EggESP_GUI"
ScreenGui.ResetOnSpawn   = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder   = 999
ScreenGui.Parent         = game.CoreGui

---------------------------------------------------------------------------
-- MAIN WINDOW
---------------------------------------------------------------------------
local Window = Instance.new("Frame")
Window.Name              = "Window"
Window.Size              = UDim2.new(0, 270, 0, 420)
Window.Position          = UDim2.new(0, 24, 0.5, -210)
Window.BackgroundColor3  = C.BG
Window.BorderSizePixel   = 0
Window.ClipsDescendants  = true
Window.Parent            = ScreenGui
makeCorner(10, Window)
makeStroke(1.5, C.BORDER, Window)

local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new({
    ColorSequenceKeypoint.new(0, C.ACCENT),
    ColorSequenceKeypoint.new(1, C.ACCENT2),
})
grad.Rotation = 90

local accentBar = Instance.new("Frame")
accentBar.Size            = UDim2.new(0, 3, 1, 0)
accentBar.Position        = UDim2.new(0, 0, 0, 0)
accentBar.BackgroundColor3 = C.ACCENT
accentBar.BorderSizePixel  = 0
accentBar.ZIndex           = 5
accentBar.Parent           = Window
makeCorner(2, accentBar)
grad:Clone().Parent = accentBar

---------------------------------------------------------------------------
-- HEADER
---------------------------------------------------------------------------
local Header = Instance.new("Frame")
Header.Size             = UDim2.new(1, 0, 0, 46)
Header.BackgroundColor3 = C.HEADER
Header.BorderSizePixel  = 0
Header.ZIndex           = 2
Header.Parent           = Window
makeCorner(10, Header)

local headerCoverBottom = Instance.new("Frame")
headerCoverBottom.Size             = UDim2.new(1, 0, 0, 10)
headerCoverBottom.Position         = UDim2.new(0, 0, 1, -10)
headerCoverBottom.BackgroundColor3 = C.HEADER
headerCoverBottom.BorderSizePixel  = 0
headerCoverBottom.ZIndex           = 2
headerCoverBottom.Parent           = Header

local titleLabel = Instance.new("TextLabel")
titleLabel.Size               = UDim2.new(1, -110, 1, 0)
titleLabel.Position           = UDim2.new(0, 14, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text               = "🥚  Egg  ESP"
titleLabel.TextColor3         = C.TEXT
titleLabel.Font               = Enum.Font.GothamBold
titleLabel.TextSize           = 16
titleLabel.TextXAlignment     = Enum.TextXAlignment.Left
titleLabel.ZIndex             = 3
titleLabel.Parent             = Header

local subtitleLabel = Instance.new("TextLabel")
subtitleLabel.Size               = UDim2.new(1, -110, 0, 14)
subtitleLabel.Position           = UDim2.new(0, 14, 0, 26)
subtitleLabel.BackgroundTransparency = 1
subtitleLabel.Text               = "Ride A Pet  •  v2 Fixed"
subtitleLabel.TextColor3         = C.SUBTEXT
subtitleLabel.Font               = Enum.Font.Gotham
subtitleLabel.TextSize           = 11
subtitleLabel.TextXAlignment     = Enum.TextXAlignment.Left
subtitleLabel.ZIndex             = 3
subtitleLabel.Parent             = Header

-- ESP Toggle button in header
local ESPToggleBtn = Instance.new("TextButton")
ESPToggleBtn.Size             = UDim2.new(0, 44, 0, 26)
ESPToggleBtn.Position         = UDim2.new(1, -54, 0.5, -13)
ESPToggleBtn.BackgroundColor3 = C.ON
ESPToggleBtn.Text             = "ON"
ESPToggleBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
ESPToggleBtn.Font             = Enum.Font.GothamBold
ESPToggleBtn.TextSize         = 13
ESPToggleBtn.BorderSizePixel  = 0
ESPToggleBtn.ZIndex           = 4
ESPToggleBtn.Parent           = Header
makeCorner(6, ESPToggleBtn)
makeStroke(1, Color3.fromRGB(255,255,255), ESPToggleBtn)

---------------------------------------------------------------------------
-- BODY
---------------------------------------------------------------------------
local Body = Instance.new("Frame")
Body.Size                = UDim2.new(1, 0, 1, -46)
Body.Position            = UDim2.new(0, 0, 0, 46)
Body.BackgroundTransparency = 1
Body.BorderSizePixel     = 0
Body.Parent              = Window

local BodyLayout = Instance.new("UIListLayout")
BodyLayout.SortOrder = Enum.SortOrder.LayoutOrder
BodyLayout.Padding   = UDim.new(0, 0)
BodyLayout.Parent    = Body

---------------------------------------------------------------------------
-- CONTROL ROW 1 — Select All / Deselect All
---------------------------------------------------------------------------
local CtrlRow = Instance.new("Frame")
CtrlRow.Size                = UDim2.new(1, 0, 0, 34)
CtrlRow.BackgroundTransparency = 1
CtrlRow.BorderSizePixel     = 0
CtrlRow.LayoutOrder         = 1
CtrlRow.Parent              = Body
makePadding(5, 5, 8, 8, CtrlRow)

local CtrlRowLayout = Instance.new("UIListLayout")
CtrlRowLayout.FillDirection      = Enum.FillDirection.Horizontal
CtrlRowLayout.SortOrder          = Enum.SortOrder.LayoutOrder
CtrlRowLayout.Padding            = UDim.new(0, 6)
CtrlRowLayout.VerticalAlignment  = Enum.VerticalAlignment.Center
CtrlRowLayout.Parent             = CtrlRow

local function makeCtrlBtn(text, order, color)
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(0.5, -3, 1, -10)
    btn.BackgroundColor3 = color or C.ACCENT
    btn.Text             = text
    btn.TextColor3       = C.TEXT
    btn.Font             = Enum.Font.GothamBold
    btn.TextSize         = 11
    btn.BorderSizePixel  = 0
    btn.LayoutOrder      = order
    btn.Parent           = CtrlRow
    makeCorner(5, btn)
    return btn
end

local SelectAllBtn   = makeCtrlBtn("✓ Select All",   1)
local DeselectAllBtn = makeCtrlBtn("✕ Deselect All", 2, Color3.fromRGB(80, 60, 100))

---------------------------------------------------------------------------
-- SCAN MAP BUTTON ROW
---------------------------------------------------------------------------
local ScanRow = Instance.new("Frame")
ScanRow.Size                = UDim2.new(1, 0, 0, 32)
ScanRow.BackgroundTransparency = 1
ScanRow.BorderSizePixel     = 0
ScanRow.LayoutOrder         = 2
ScanRow.Parent              = Body
makePadding(0, 4, 8, 8, ScanRow)

local ScanBtn = Instance.new("TextButton")
ScanBtn.Size             = UDim2.new(1, 0, 1, -4)
ScanBtn.BackgroundColor3 = C.SCAN
ScanBtn.Text             = "🔍  Scan Map for New Eggs"
ScanBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
ScanBtn.Font             = Enum.Font.GothamBold
ScanBtn.TextSize         = 12
ScanBtn.BorderSizePixel  = 0
ScanBtn.Parent           = ScanRow
makeCorner(6, ScanBtn)
makeStroke(1, Color3.fromRGB(60, 220, 150), ScanBtn)

---------------------------------------------------------------------------
-- SOURCE INFO ROW
---------------------------------------------------------------------------
local InfoRow = Instance.new("Frame")
InfoRow.Size                = UDim2.new(1, 0, 0, 28)
InfoRow.BackgroundColor3    = C.INFO_BG
InfoRow.BorderSizePixel     = 0
InfoRow.LayoutOrder         = 3
InfoRow.Parent              = Body
makePadding(0, 0, 10, 8, InfoRow)
makeStroke(1, C.BORDER, InfoRow)

local InfoLabel = Instance.new("TextLabel")
InfoLabel.Size               = UDim2.new(1, 0, 1, 0)
InfoLabel.BackgroundTransparency = 1
InfoLabel.Text               = "Click 🔍 Scan to detect all map eggs"
InfoLabel.TextColor3         = C.SUBTEXT
InfoLabel.Font               = Enum.Font.Gotham
InfoLabel.TextSize           = 10
InfoLabel.TextXAlignment     = Enum.TextXAlignment.Left
InfoLabel.TextTruncate       = Enum.TextTruncate.AtEnd
InfoLabel.Parent             = InfoRow

---------------------------------------------------------------------------
-- EGG COUNT LABEL
---------------------------------------------------------------------------
local CountRow = Instance.new("Frame")
CountRow.Size                = UDim2.new(1, 0, 0, 18)
CountRow.BackgroundTransparency = 1
CountRow.BorderSizePixel     = 0
CountRow.LayoutOrder         = 4
CountRow.Parent              = Body
makePadding(0, 0, 14, 8, CountRow)

local CountLabel = Instance.new("TextLabel")
CountLabel.Size               = UDim2.new(1, 0, 1, 0)
CountLabel.BackgroundTransparency = 1
CountLabel.Text               = "Scanning..."
CountLabel.TextColor3         = C.SUBTEXT
CountLabel.Font               = Enum.Font.Gotham
CountLabel.TextSize           = 11
CountLabel.TextXAlignment     = Enum.TextXAlignment.Left
CountLabel.Parent             = CountRow

---------------------------------------------------------------------------
-- SCROLL FRAME
---------------------------------------------------------------------------
local ScrollOuter = Instance.new("Frame")
ScrollOuter.Size                = UDim2.new(1, 0, 1, -132)
ScrollOuter.BackgroundTransparency = 1
ScrollOuter.BorderSizePixel     = 0
ScrollOuter.LayoutOrder         = 5
ScrollOuter.Parent              = Body

local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Size                 = UDim2.new(1, 0, 1, 0)
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel      = 0
ScrollFrame.ScrollBarThickness   = 4
ScrollFrame.ScrollBarImageColor3 = C.SCROLL_BAR
ScrollFrame.CanvasSize           = UDim2.new(0, 0, 0, 0)
ScrollFrame.AutomaticCanvasSize  = Enum.AutomaticSize.Y
ScrollFrame.ScrollingDirection   = Enum.ScrollingDirection.Y
ScrollFrame.Parent               = ScrollOuter
makePadding(2, 6, 6, 6, ScrollFrame)

local ScrollLayout = Instance.new("UIListLayout")
ScrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
ScrollLayout.Padding   = UDim.new(0, 4)
ScrollLayout.Parent    = ScrollFrame

---------------------------------------------------------------------------
-- EGG ROW FACTORY
---------------------------------------------------------------------------
local checkboxRows = {}

local function setCheckVisual(eggName)
    local row = checkboxRows[eggName]
    if not row then return end
    local on = selectedTypes[eggName] == true
    row.check.BackgroundColor3 = on and C.CHECK_ON or C.CHECK_OFF
    row.check.Text = on and "✓" or ""
end

local function buildEggRow(eggName, order)
    if checkboxRows[eggName] then return end

    local row = Instance.new("Frame")
    row.Name             = "Row_" .. eggName
    row.Size             = UDim2.new(1, 0, 0, 32)
    row.BackgroundColor3 = C.ITEM_BG
    row.BorderSizePixel  = 0
    row.LayoutOrder      = order
    row.Parent           = ScrollFrame
    makeCorner(6, row)
    makeStroke(1, C.BORDER, row)
    makePadding(0, 0, 8, 8, row)

    row.MouseEnter:Connect(function() row.BackgroundColor3 = C.ITEM_HOVER end)
    row.MouseLeave:Connect(function() row.BackgroundColor3 = C.ITEM_BG end)

    local check = Instance.new("TextButton")
    check.Size             = UDim2.new(0, 20, 0, 20)
    check.Position         = UDim2.new(0, 0, 0.5, -10)
    check.BackgroundColor3 = C.CHECK_OFF
    check.Text             = ""
    check.TextColor3       = Color3.fromRGB(20, 20, 30)
    check.Font             = Enum.Font.GothamBold
    check.TextSize         = 13
    check.BorderSizePixel  = 0
    check.ZIndex           = 2
    check.Parent           = row
    makeCorner(4, check)
    makeStroke(1, C.BORDER, check)

    local nameL = Instance.new("TextLabel")
    nameL.Size               = UDim2.new(1, -30, 1, 0)
    nameL.Position           = UDim2.new(0, 28, 0, 0)
    nameL.BackgroundTransparency = 1
    nameL.Text               = eggName
    nameL.TextColor3         = C.TEXT
    nameL.Font               = Enum.Font.Gotham
    nameL.TextSize           = 12
    nameL.TextXAlignment     = Enum.TextXAlignment.Left
    nameL.TextTruncate       = Enum.TextTruncate.AtEnd
    nameL.ZIndex             = 2
    nameL.Parent             = row

    checkboxRows[eggName] = { row = row, check = check, label = nameL }
    setCheckVisual(eggName)

    local function toggle()
        selectedTypes[eggName] = not selectedTypes[eggName]
        setCheckVisual(eggName)
        refreshAllESP()
        updateCount()
    end
    check.MouseButton1Click:Connect(toggle)

    local rowBtn = Instance.new("TextButton")
    rowBtn.Size                = UDim2.new(1, 0, 1, 0)
    rowBtn.BackgroundTransparency = 1
    rowBtn.Text                = ""
    rowBtn.ZIndex              = 1
    rowBtn.Parent              = row
    rowBtn.MouseButton1Click:Connect(toggle)
end

function updateCount()
    local total, sel = 0, 0
    for name, _ in pairs(checkboxRows) do
        total += 1
        if selectedTypes[name] then sel += 1 end
    end
    CountLabel.Text = string.format("Showing %d / %d egg types", sel, total)
end

---------------------------------------------------------------------------
-- POPULATE / RESCAN
---------------------------------------------------------------------------
local function populateList(isRescan)
    local eggs, sourceCounts = getAllEggsInWorkspace()

    -- Build unique types
    local seen  = {}
    local types = {}
    for _, egg in ipairs(eggs) do
        if not seen[egg.Name] then
            seen[egg.Name] = true
            table.insert(types, egg.Name)
        end
    end
    table.sort(types)

    local order = 0
    for _, name in ipairs(types) do
        if selectedTypes[name] == nil then
            selectedTypes[name] = true
        end
        order += 1
        buildEggRow(name, order)
    end

    updateCount()
    refreshAllESP()

    -- Update info bar with source breakdown
    local parts = {}
    for src, n in pairs(sourceCounts) do
        table.insert(parts, src .. ": " .. n)
    end
    table.sort(parts)
    InfoLabel.Text = "Sources → " .. (#parts > 0 and table.concat(parts, "  |  ") or "none found")

    return #types
end

-- Initial populate
local initialCount = populateList(false)
print("[EggESP v2] Loaded — " .. initialCount .. " egg types from all sources.")

---------------------------------------------------------------------------
-- SCAN MAP BUTTON
---------------------------------------------------------------------------
ScanBtn.MouseButton1Click:Connect(function()
    ScanBtn.Text             = "⏳  Scanning..."
    ScanBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
    task.wait(0.05)

    local found = populateList(true)

    ScanBtn.Text             = "✅  Found " .. found .. " types — Done!"
    ScanBtn.BackgroundColor3 = C.SCAN_FLASH
    task.wait(2)
    ScanBtn.Text             = "🔍  Scan Map for New Eggs"
    ScanBtn.BackgroundColor3 = C.SCAN
end)

---------------------------------------------------------------------------
-- SELECT ALL / DESELECT ALL
---------------------------------------------------------------------------
SelectAllBtn.MouseButton1Click:Connect(function()
    for name, _ in pairs(checkboxRows) do
        selectedTypes[name] = true
        setCheckVisual(name)
    end
    refreshAllESP()
    updateCount()
end)

DeselectAllBtn.MouseButton1Click:Connect(function()
    for name, _ in pairs(checkboxRows) do
        selectedTypes[name] = false
        setCheckVisual(name)
    end
    refreshAllESP()
    updateCount()
end)

---------------------------------------------------------------------------
-- ESP ON/OFF TOGGLE
---------------------------------------------------------------------------
ESPToggleBtn.MouseButton1Click:Connect(function()
    espEnabled = not espEnabled
    if espEnabled then
        ESPToggleBtn.Text             = "ON"
        ESPToggleBtn.BackgroundColor3 = C.ON
    else
        ESPToggleBtn.Text             = "OFF"
        ESPToggleBtn.BackgroundColor3 = C.OFF
    end
    refreshAllESP()
end)

---------------------------------------------------------------------------
-- MINIMIZE BUTTON
---------------------------------------------------------------------------
local MinBtn = Instance.new("TextButton")
MinBtn.Size             = UDim2.new(0, 22, 0, 22)
MinBtn.Position         = UDim2.new(1, -30, 0.5, -11)
MinBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 68)
MinBtn.Text             = "−"
MinBtn.TextColor3       = C.TEXT
MinBtn.Font             = Enum.Font.GothamBold
MinBtn.TextSize         = 15
MinBtn.BorderSizePixel  = 0
MinBtn.ZIndex           = 4
MinBtn.Parent           = Header
makeCorner(5, MinBtn)

local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    Body.Visible = not minimized
    Window.Size  = minimized
        and UDim2.new(0, 270, 0, 46)
        or  UDim2.new(0, 270, 0, 420)
    MinBtn.Text  = minimized and "+" or "−"
end)

---------------------------------------------------------------------------
-- DRAGGABLE WINDOW
---------------------------------------------------------------------------
do
    local dragging, dragStart, startPos = false, nil, nil
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging  = true
            dragStart = input.Position
            startPos  = Window.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Window.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

---------------------------------------------------------------------------
-- MAIN LOOP — update distances + auto-detect new eggs
---------------------------------------------------------------------------
local UPDATE_INTERVAL  = 0.1
local EGG_SCAN_INTERVAL = 3
local lastUpdate  = 0
local lastEggScan = 0

RunService.Heartbeat:Connect(function(dt)
    local now = tick()

    -- Distance update
    if now - lastUpdate >= UPDATE_INTERVAL then
        lastUpdate = now
        local playerPos = getPlayerPos()
        for egg, bb in pairs(espLabels) do
            if not egg:IsDescendantOf(workspace) then
                removeESPLabel(egg)
            else
                local pos  = getEggPosition(egg)
                local distL = bb:FindFirstChild("Frame") and bb.Frame:FindFirstChild("Distance")
                if pos and playerPos and distL then
                    distL.Text = math.floor((pos - playerPos).Magnitude) .. " Studs"
                end
                bb.Enabled = espEnabled and (selectedTypes[egg.Name] == true)
            end
        end
    end

    -- Periodic auto-scan for newly spawned egg types
    if now - lastEggScan >= EGG_SCAN_INTERVAL then
        lastEggScan = now
        local types = getUniqueEggTypes()
        local newFound = false
        for i, name in ipairs(types) do
            if not checkboxRows[name] then
                if selectedTypes[name] == nil then
                    selectedTypes[name] = true
                end
                buildEggRow(name, 2000 + i)
                newFound = true
            end
        end
        if newFound then
            updateCount()
            refreshAllESP()
        end
        -- Add ESP for any newly appeared egg instances
        if espEnabled then
            local eggs = getAllEggsInWorkspace()
            for _, egg in ipairs(eggs) do
                if selectedTypes[egg.Name] and not espLabels[egg] then
                    createESPLabel(egg)
                end
            end
        end
        -- Clean stale ESP labels
        for egg, _ in pairs(espLabels) do
            if not egg:IsDescendantOf(workspace) then
                removeESPLabel(egg)
            end
        end
    end
end)
