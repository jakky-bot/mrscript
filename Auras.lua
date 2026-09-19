-- ============================================================
-- JJK WORLD: TRAIN YOUR AURA - AUTO FARM SCRIPT v2
-- Features: Auto Roll (combo) + Speed Multiplier, Equip Best
--           Aura, Auto Teleport to best zone, Auto Rebirth
--           with configurable aura threshold, Full UI
-- ============================================================

-- Prevent duplicate instances
if _G.JJKAutoFarm then
    _G.JJKAutoFarm.destroy()
end

local Players        = game:GetService("Players")
local RunService     = game:GetService("RunService")
local TweenService   = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player    = Players.LocalPlayer
local playerGui = player.PlayerGui

-- ============================================================
-- NUMBER PARSER  (K / M / B / T / Qa / Qi / Sx / Sp / Oc / No)
-- ============================================================
local SUFFIXES = {
    [""]   = 1,      ["K"]  = 1e3,   ["M"]  = 1e6,   ["B"]  = 1e9,
    ["T"]  = 1e12,   ["Qa"] = 1e15,  ["Qi"] = 1e18,  ["Sx"] = 1e21,
    ["Sp"] = 1e24,   ["Oc"] = 1e27,  ["No"] = 1e30,  ["De"] = 1e33,
}

local function parseNumber(str)
    if not str or str == "?" then return 0 end
    str = tostring(str):gsub(",", ""):gsub("%s+", ""):gsub("<[^>]+>", "")
    local num, suffix = str:match("^([%d%.]+)([%a]*)")
    if not num then return 0 end
    return (tonumber(num) or 0) * (SUFFIXES[suffix] or 1)
end

local function formatNumber(n)
    local sfx = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "De" }
    local i = 1
    while n >= 1000 and i < #sfx do n = n / 1000; i = i + 1 end
    return string.format("%.2f%s", n, sfx[i])
end

-- ============================================================
-- CONFIG
-- ============================================================
local CONFIG = {
    -- Base delay between rolls at speed x1 (seconds)
    baseRollDelay       = 0.05,
    -- Current speed multiplier index (1 = x1, 2 = x2, 3 = x4, 4 = x8)
    rollSpeedMultIndex  = 1,
    rollSpeedMults      = { 1, 2, 4, 8 },   -- divisors applied to baseRollDelay
    rollSpeedLabels     = { "x1", "x2", "x4", "x8" },

    teleportDelay       = 2.0,
    rebirthCheckInterval = 3,
    equipAuraInterval   = 10,
    zoneScanInterval    = 8,

    -- Rebirth threshold: auto-rebirth fires when aura >= this value
    -- 0 means "disabled even if autoRebirth toggle is on"
    rebirthAuraThreshold = 0,
}

-- ============================================================
-- STATE
-- ============================================================
local State = {
    autoRoll     = false,
    autoEquip    = false,
    autoTeleport = false,
    autoRebirth  = false,
    running      = true,
    status       = "Idle",
    bestZone     = "None",
    currentAura  = 0,
}

-- ============================================================
-- ZONE TABLE  (sorted ascending by requirement)
-- ============================================================
local ZONES = {
    { name = "SANDBOX",         req = 0,        pos = Vector3.new(53.86,   14.56,    6.34)   },
    { name = "LAVA BOX",        req = 1.7e3,    pos = Vector3.new(109.16,  31.25,  -35.91)   },
    { name = "DUMMIES",         req = 35.7e3,   pos = Vector3.new(-307.61,  5.79,   89.83)   },
    { name = "HOKAGE LOGS",     req = 1.76e6,   pos = Vector3.new(-287.96, 17.36,  -54.46)   },
    { name = "SPIKES",          req = 30.8e6,   pos = Vector3.new(-300.33, 26.27,  177.72)   },
    { name = "BALD HEAD",       req = 792e6,    pos = Vector3.new(-390.16, 125.50,  85.61)   },
    { name = "COCKPIT",         req = 14.9e9,   pos = Vector3.new(640.43,  154.17,  46.41)   },
    { name = "UPPER DECK",      req = 772e9,    pos = Vector3.new(370.42,   96.63,  -24.02)  },
    { name = "GRASS DECK",      req = 40.5e12,  pos = Vector3.new(491.55,   52.84,   10.05)  },
    { name = "LOOKOUT",         req = 1.95e15,  pos = Vector3.new(455.36,  315.30,   -1.43)  },
    { name = "NAMEK PLAINS",    req = 80.7e15,  pos = Vector3.new(-486.62, 1344.91, 221.78)  },
    { name = "NAMEK HOUSE",     req = 3.45e18,  pos = Vector3.new(-417.28, 1338.79, 187.66)  },
    { name = "NAMEK HILL",      req = 133e18,   pos = Vector3.new(-385.27, 1388.14, 329.00)  },
    { name = "DOJO",            req = 4.72e21,  pos = Vector3.new(58.26,    35.67, -570.64)  },
    { name = "TRAINING GROUND", req = 159e21,   pos = Vector3.new(-38.87,   27.61, -543.33)  },
    { name = "HUMILITY",        req = 108e24,   pos = Vector3.new(155.89,    6.62,  345.91)  },
    { name = "OLD HOUSE",       req = 4.57e24,  pos = Vector3.new(239.62,  183.76, -582.41)  },
    { name = "TEMPLE LOGS",     req = 2.16e27,  pos = Vector3.new(132.62,    9.15,  493.66)  },
    { name = "ANCIENT BRIDGE",  req = 44.7e27,  pos = Vector3.new(90.35,     9.15,  418.62)  },
    { name = "TRADITION",       req = 858e27,   pos = Vector3.new(219.93,   34.23,  547.69)  },
    { name = "MODERNITY",       req = 23.6e30,  pos = Vector3.new(43.62,    67.74,  523.55)  },
}
table.sort(ZONES, function(a, b) return a.req < b.req end)

-- ============================================================
-- HELPERS
-- ============================================================
local function getAuraValue()
    local ls = player:FindFirstChild("leaderstats")
    return (ls and ls:FindFirstChild("Aura")) and parseNumber(ls.Aura.Value) or 0
end

local function getRebirths()
    local ls = player:FindFirstChild("leaderstats")
    return (ls and ls:FindFirstChild("Rebirths")) and (tonumber(ls.Rebirths.Value) or 0) or 0
end

local function getBestZone(aura)
    local best = ZONES[1]
    for _, z in ipairs(ZONES) do
        if aura >= z.req then best = z else break end
    end
    return best
end

local function fireButton(btn)
    if not btn then return end
    pcall(function() btn.MouseButton1Click:Fire() end)
    task.wait(0.01)
    pcall(function() btn:Activate() end)
end

local function teleportToZone(zone)
    local char = player.Character
    if char and char:FindFirstChild("HumanoidRootPart") then
        char.HumanoidRootPart.CFrame = CFrame.new(zone.pos + Vector3.new(0, 3, 0))
        State.status = "Teleported → " .. zone.name
    end
end

-- ============================================================
-- CORE ACTIONS
-- ============================================================
local function doRoll()
    local btn = playerGui.HUD["1"]:FindFirstChild("MainDice")
    if btn then fireButton(btn) end
end

local function doEquipBest()
    pcall(function()
        local btn = playerGui.Auras.Auras.Content._frame.Header:FindFirstChild("EquipBestButton")
        if btn then
            fireButton(btn)
            State.status = "Equipped best aura"
        end
    end)
end

local function doRebirth()
    pcall(function()
        -- Press the REBIRTH teleport button
        local l3 = playerGui.HUD["1"]["2"]["3"]
        for _, frame in pairs(l3:GetChildren()) do
            if frame.Name == "4" then
                local rb = frame:FindFirstChild("RebirthTeleport")
                if rb then
                    fireButton(rb)
                    State.status = "Teleporting to Rebirth..."
                    task.wait(2)
                    -- Try proximity prompts in world
                    for _, v in pairs(workspace:GetDescendants()) do
                        if v:IsA("ProximityPrompt") then
                            local combined = (v.ActionText .. v.ObjectText):lower()
                            if combined:find("rebirth") then
                                v.Triggered:Fire(player)
                                State.status = "Rebirth triggered!"
                                return
                            end
                        end
                    end
                    -- Try confirm buttons in any GUI
                    for _, gui in pairs(playerGui:GetChildren()) do
                        for _, v in pairs(gui:GetDescendants()) do
                            if v:IsA("TextButton") or v:IsA("ImageButton") then
                                local txt = ""
                                for _, c in pairs(v:GetDescendants()) do
                                    if c:IsA("TextLabel") then txt = txt .. c.Text end
                                end
                                if txt:lower():find("rebirth") or txt:lower():find("confirm") then
                                    fireButton(v)
                                    State.status = "Rebirth confirmed!"
                                    return
                                end
                            end
                        end
                    end
                    State.status = "At rebirth zone — confirm manually"
                end
            end
        end
    end)
end

-- ============================================================
-- BACKGROUND THREADS
-- ============================================================
local threads = {}
local function spawn(fn)
    local t = task.spawn(fn)
    table.insert(threads, t)
    return t
end

-- Roll loop — delay shrinks as speed multiplier increases
spawn(function()
    while State.running do
        if State.autoRoll then
            local mult  = CONFIG.rollSpeedMults[CONFIG.rollSpeedMultIndex] or 1
            local delay = CONFIG.baseRollDelay / mult
            pcall(doRoll)
            task.wait(math.max(delay, 0.016))   -- never below one frame
        else
            task.wait(0.1)
        end
    end
end)

-- Equip-best loop
spawn(function()
    local t = 0
    while State.running do
        task.wait(0.5); t = t + 0.5
        if State.autoEquip and t >= CONFIG.equipAuraInterval then
            t = 0; pcall(doEquipBest)
        end
    end
end)

-- Zone-teleport loop
spawn(function()
    local t = 0
    while State.running do
        task.wait(0.5); t = t + 0.5
        if State.autoTeleport and t >= CONFIG.zoneScanInterval then
            t = 0
            local aura = getAuraValue()
            local zone = getBestZone(aura)
            State.bestZone = zone.name
            local char = player.Character
            if char and char:FindFirstChild("HumanoidRootPart") then
                if (char.HumanoidRootPart.Position - zone.pos).Magnitude > 20 then
                    teleportToZone(zone)
                    task.wait(CONFIG.teleportDelay)
                end
            end
        end
    end
end)

-- Rebirth loop — fires when aura >= user-set threshold (and threshold > 0)
spawn(function()
    local t = 0
    while State.running do
        task.wait(0.5); t = t + 0.5
        if State.autoRebirth and t >= CONFIG.rebirthCheckInterval then
            t = 0
            local threshold = CONFIG.rebirthAuraThreshold
            if threshold > 0 then
                local aura = getAuraValue()
                if aura >= threshold then
                    State.status = "Rebirth threshold reached! Rebirthing..."
                    task.spawn(doRebirth)
                    task.wait(6)    -- cooldown before checking again
                end
            else
                State.status = "Auto Rebirth: set a threshold below ↓"
            end
        end
    end
end)

-- ============================================================
-- UI HELPERS
-- ============================================================
local function applyCorner(parent, radius)
    local c = Instance.new("UICorner", parent)
    c.CornerRadius = UDim.new(0, radius or 8)
    return c
end

local function applyStroke(parent, color, thickness)
    local s = Instance.new("UIStroke", parent)
    s.Color = color or Color3.fromRGB(60, 60, 90)
    s.Thickness = thickness or 1
    return s
end

local COL = {
    bg        = Color3.fromRGB(12, 12, 20),
    panel     = Color3.fromRGB(20, 20, 35),
    titleBg   = Color3.fromRGB(25, 35, 70),
    btnOff    = Color3.fromRGB(38, 38, 58),
    btnOn     = Color3.fromRGB(18, 48, 18),
    accent    = Color3.fromRGB(80, 120, 255),
    textMain  = Color3.fromRGB(200, 200, 220),
    textDim   = Color3.fromRGB(120, 120, 150),
    textGreen = Color3.fromRGB(80, 255, 120),
    textRed   = Color3.fromRGB(220, 70, 70),
    textGold  = Color3.fromRGB(255, 200, 80),
    textBlue  = Color3.fromRGB(110, 180, 255),
}

-- ============================================================
-- BUILD UI
-- ============================================================
local existingUI = playerGui:FindFirstChild("JJKAutoFarmUI")
if existingUI then existingUI:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name            = "JJKAutoFarmUI"
screenGui.ResetOnSpawn    = false
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset  = false
screenGui.DisplayOrder    = 999
screenGui.Parent          = playerGui

-- ── Main frame ────────────────────────────────────────────
local UI_WIDTH  = 248
local UI_HEIGHT = 430   -- taller to fit new controls

local main = Instance.new("Frame")
main.Name            = "MainFrame"
main.Size            = UDim2.new(0, UI_WIDTH, 0, UI_HEIGHT)
main.Position        = UDim2.new(0, 10, 0.5, -UI_HEIGHT / 2)
main.BackgroundColor3 = COL.bg
main.BorderSizePixel = 0
main.Active          = true
main.Draggable       = true
main.Parent          = screenGui
applyCorner(main, 10)
applyStroke(main, COL.accent, 1.5)

-- ── Title bar ─────────────────────────────────────────────
local titleBar = Instance.new("Frame")
titleBar.Size             = UDim2.new(1, 0, 0, 36)
titleBar.BackgroundColor3 = COL.titleBg
titleBar.BorderSizePixel  = 0
titleBar.Parent           = main
applyCorner(titleBar, 10)

-- bottom-half filler so rounded corners only appear at top
local titleFix = Instance.new("Frame")
titleFix.Size             = UDim2.new(1, 0, 0.5, 0)
titleFix.Position         = UDim2.new(0, 0, 0.5, 0)
titleFix.BackgroundColor3 = COL.titleBg
titleFix.BorderSizePixel  = 0
titleFix.Parent           = titleBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Size              = UDim2.new(1, -10, 1, 0)
titleLbl.Position          = UDim2.new(0, 10, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text              = "⚡ JJK AUTO FARM"
titleLbl.TextColor3        = COL.textBlue
titleLbl.TextScaled        = true
titleLbl.Font              = Enum.Font.GothamBold
titleLbl.TextXAlignment    = Enum.TextXAlignment.Left
titleLbl.Parent            = titleBar

-- ── Status bar ────────────────────────────────────────────
local function makeMiniBar(yOffset, defaultText, textColor)
    local bar = Instance.new("Frame")
    bar.Size             = UDim2.new(1, -16, 0, 22)
    bar.Position         = UDim2.new(0, 8, 0, yOffset)
    bar.BackgroundColor3 = COL.panel
    bar.BorderSizePixel  = 0
    bar.Parent           = main
    applyCorner(bar, 5)

    local lbl = Instance.new("TextLabel")
    lbl.Size             = UDim2.new(1, -8, 1, 0)
    lbl.Position         = UDim2.new(0, 4, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text             = defaultText
    lbl.TextColor3       = textColor or COL.textMain
    lbl.TextScaled       = true
    lbl.Font             = Enum.Font.Gotham
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Parent           = bar
    return lbl
end

local statusLbl = makeMiniBar(42, "● Idle", COL.textGreen)
local infoLbl   = makeMiniBar(68, "Aura: — | Rebirths: —", COL.textGold)

-- ── Toggle button factory ─────────────────────────────────
local function makeToggle(labelText, yPos, activeStrokeColor, onToggle)
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(1, -16, 0, 42)
    btn.Position         = UDim2.new(0, 8, 0, yPos)
    btn.BackgroundColor3 = COL.btnOff
    btn.BorderSizePixel  = 0
    btn.Text             = ""
    btn.AutoButtonColor  = false
    btn.Parent           = main
    applyCorner(btn, 8)
    local stroke = applyStroke(btn, Color3.fromRGB(55, 55, 80), 1)

    local badge = Instance.new("TextLabel")
    badge.Size             = UDim2.new(0, 38, 1, 0)
    badge.BackgroundTransparency = 1
    badge.Text             = "OFF"
    badge.TextColor3       = COL.textRed
    badge.TextScaled       = true
    badge.Font             = Enum.Font.GothamBold
    badge.Parent           = btn

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size           = UDim2.new(1, -42, 1, 0)
    nameLbl.Position       = UDim2.new(0, 42, 0, 0)
    nameLbl.BackgroundTransparency = 1
    nameLbl.Text           = labelText
    nameLbl.TextColor3     = COL.textMain
    nameLbl.TextScaled     = true
    nameLbl.Font           = Enum.Font.GothamSemibold
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.Parent         = btn

    local on = false
    local function refresh()
        if on then
            btn.BackgroundColor3 = COL.btnOn
            stroke.Color         = activeStrokeColor
            badge.Text           = "ON"
            badge.TextColor3     = COL.textGreen
        else
            btn.BackgroundColor3 = COL.btnOff
            stroke.Color         = Color3.fromRGB(55, 55, 80)
            badge.Text           = "OFF"
            badge.TextColor3     = COL.textRed
        end
    end
    btn.MouseButton1Click:Connect(function()
        on = not on; refresh(); onToggle(on)
    end)
    return btn
end

-- ── Toggle buttons ────────────────────────────────────────
makeToggle("🎲 Auto Roll (Combo)", 96,
    Color3.fromRGB(80, 200, 255), function(v)
        State.autoRoll = v
        State.status   = v and "Auto Rolling..." or "Roll paused"
    end)

makeToggle("✨ Equip Best Aura", 143,
    Color3.fromRGB(200, 100, 255), function(v)
        State.autoEquip = v
        if v then task.spawn(doEquipBest) end
    end)

makeToggle("🌍 Auto Best Zone", 190,
    Color3.fromRGB(100, 255, 150), function(v)
        State.autoTeleport = v
        if v then
            local zone = getBestZone(getAuraValue())
            State.bestZone = zone.name
            teleportToZone(zone)
        end
    end)

makeToggle("🔄 Auto Rebirth", 237,
    Color3.fromRGB(255, 180, 50), function(v)
        State.autoRebirth = v
        State.status = v and "Watching for rebirth threshold..." or "Rebirth paused"
    end)

-- ============================================================
-- ROLL SPEED MULTIPLIER SELECTOR  (new feature)
-- A row of four pill buttons: x1 · x2 · x4 · x8
-- Pressing one sets CONFIG.rollSpeedMultIndex and dims the rest
-- ============================================================
local speedLabel = Instance.new("TextLabel")
speedLabel.Size             = UDim2.new(1, -16, 0, 18)
speedLabel.Position         = UDim2.new(0, 8, 0, 284)
speedLabel.BackgroundTransparency = 1
speedLabel.Text             = "⚡ Roll Speed Boost"
speedLabel.TextColor3       = COL.textDim
speedLabel.TextScaled       = true
speedLabel.Font             = Enum.Font.GothamSemibold
speedLabel.TextXAlignment   = Enum.TextXAlignment.Left
speedLabel.Parent           = main

local speedRow = Instance.new("Frame")
speedRow.Size             = UDim2.new(1, -16, 0, 32)
speedRow.Position         = UDim2.new(0, 8, 0, 304)
speedRow.BackgroundTransparency = 1
speedRow.Parent           = main

local speedLayout = Instance.new("UIListLayout", speedRow)
speedLayout.FillDirection  = Enum.FillDirection.Horizontal
speedLayout.Padding        = UDim.new(0, 6)
speedLayout.SortOrder      = Enum.SortOrder.LayoutOrder

local speedBtns = {}
local SPEED_ACTIVE_COLOR   = Color3.fromRGB(80, 200, 255)
local SPEED_INACTIVE_COLOR = Color3.fromRGB(38, 38, 58)

for i, lbl in ipairs(CONFIG.rollSpeedLabels) do
    local sb = Instance.new("TextButton")
    sb.Size             = UDim2.new(0.22, 0, 1, 0)
    sb.BackgroundColor3 = (i == 1) and SPEED_ACTIVE_COLOR or SPEED_INACTIVE_COLOR
    sb.BorderSizePixel  = 0
    sb.Text             = lbl
    sb.TextColor3       = Color3.fromRGB(255, 255, 255)
    sb.TextScaled       = true
    sb.Font             = Enum.Font.GothamBold
    sb.AutoButtonColor  = false
    sb.LayoutOrder      = i
    sb.Parent           = speedRow
    applyCorner(sb, 6)
    applyStroke(sb, Color3.fromRGB(60, 60, 100), 1)

    table.insert(speedBtns, sb)

    sb.MouseButton1Click:Connect(function()
        CONFIG.rollSpeedMultIndex = i
        -- Refresh all button colors
        for j, b in ipairs(speedBtns) do
            b.BackgroundColor3 = (j == i) and SPEED_ACTIVE_COLOR or SPEED_INACTIVE_COLOR
        end
        State.status = "Roll speed set to " .. lbl
    end)
end

-- ============================================================
-- REBIRTH THRESHOLD INPUT  (new feature)
-- A text box where the user types the aura amount they want
-- to reach before auto-rebirthing, e.g. "1.76M" or "35700"
-- ============================================================
local threshLabel = Instance.new("TextLabel")
threshLabel.Size             = UDim2.new(1, -16, 0, 18)
threshLabel.Position         = UDim2.new(0, 8, 0, 342)
threshLabel.BackgroundTransparency = 1
threshLabel.Text             = "🔄 Rebirth at Aura (e.g. 1.76M)"
threshLabel.TextColor3       = COL.textDim
threshLabel.TextScaled       = true
threshLabel.Font             = Enum.Font.GothamSemibold
threshLabel.TextXAlignment   = Enum.TextXAlignment.Left
threshLabel.Parent           = main

local threshRow = Instance.new("Frame")
threshRow.Size             = UDim2.new(1, -16, 0, 30)
threshRow.Position         = UDim2.new(0, 8, 0, 362)
threshRow.BackgroundColor3 = COL.panel
threshRow.BorderSizePixel  = 0
threshRow.Parent           = main
applyCorner(threshRow, 6)
applyStroke(threshRow, Color3.fromRGB(60, 60, 100), 1)

local threshBox = Instance.new("TextBox")
threshBox.Size              = UDim2.new(1, -80, 1, 0)
threshBox.BackgroundTransparency = 1
threshBox.Text              = ""
threshBox.PlaceholderText   = "0  (disabled)"
threshBox.PlaceholderColor3 = COL.textDim
threshBox.TextColor3        = Color3.fromRGB(255, 230, 120)
threshBox.TextScaled        = true
threshBox.Font              = Enum.Font.GothamSemibold
threshBox.TextXAlignment    = Enum.TextXAlignment.Left
threshBox.ClearTextOnFocus  = false
threshBox.Parent            = threshRow
local threshPad = Instance.new("UIPadding", threshBox)
threshPad.PaddingLeft = UDim.new(0, 6)

local setBtn = Instance.new("TextButton")
setBtn.Size             = UDim2.new(0, 68, 1, -4)
setBtn.Position         = UDim2.new(1, -72, 0, 2)
setBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 40)
setBtn.BorderSizePixel  = 0
setBtn.Text             = "SET"
setBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
setBtn.TextScaled       = true
setBtn.Font             = Enum.Font.GothamBold
setBtn.AutoButtonColor  = false
setBtn.Parent           = threshRow
applyCorner(setBtn, 5)

-- Confirm / flash visual
local function flashSetBtn(ok)
    local original = setBtn.BackgroundColor3
    setBtn.BackgroundColor3 = ok and Color3.fromRGB(30, 180, 60)
                                  or Color3.fromRGB(180, 40, 40)
    task.delay(0.4, function()
        setBtn.BackgroundColor3 = Color3.fromRGB(40, 100, 40)
    end)
end

setBtn.MouseButton1Click:Connect(function()
    local raw = threshBox.Text:gsub("%s+", "")
    if raw == "" or raw == "0" then
        CONFIG.rebirthAuraThreshold = 0
        State.status = "Rebirth threshold cleared"
        flashSetBtn(true)
        return
    end
    local parsed = parseNumber(raw)
    if parsed > 0 then
        CONFIG.rebirthAuraThreshold = parsed
        State.status = "Rebirth threshold → " .. formatNumber(parsed)
        flashSetBtn(true)
    else
        State.status = "⚠ Invalid threshold value"
        flashSetBtn(false)
    end
end)

-- ── Manual rebirth button ──────────────────────────────────
local nowBtn = Instance.new("TextButton")
nowBtn.Size             = UDim2.new(1, -16, 0, 26)
nowBtn.Position         = UDim2.new(0, 8, 0, 398)
nowBtn.BackgroundColor3 = Color3.fromRGB(160, 60, 15)
nowBtn.BorderSizePixel  = 0
nowBtn.Text             = "⚡ REBIRTH NOW"
nowBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
nowBtn.TextScaled       = true
nowBtn.Font             = Enum.Font.GothamBold
nowBtn.AutoButtonColor  = false
nowBtn.Parent           = main
applyCorner(nowBtn, 6)
nowBtn.MouseButton1Click:Connect(function()
    nowBtn.BackgroundColor3 = Color3.fromRGB(230, 110, 20)
    State.status = "Manual rebirth..."
    task.spawn(doRebirth)
    task.delay(0.3, function() nowBtn.BackgroundColor3 = Color3.fromRGB(160, 60, 15) end)
end)

-- ============================================================
-- STATUS UPDATER
-- ============================================================
spawn(function()
    while State.running do
        task.wait(0.5)
        pcall(function()
            local aura     = getAuraValue()
            local rebirths = getRebirths()
            State.currentAura = aura

            statusLbl.Text = "● " .. State.status

            local thresh = CONFIG.rebirthAuraThreshold
            if State.autoTeleport then
                local zone = getBestZone(aura)
                State.bestZone = zone.name
                infoLbl.Text = "🌍 " .. zone.name .. "  |  " .. formatNumber(aura)
            elseif thresh > 0 then
                local pct = math.floor(math.min(aura / thresh * 100, 100))
                infoLbl.Text = "Rebirth: " .. formatNumber(aura) .. " / "
                             .. formatNumber(thresh) .. "  (" .. pct .. "%)"
            else
                infoLbl.Text = "Aura: " .. formatNumber(aura)
                             .. "  |  Births: " .. rebirths
            end
        end)
    end
end)

-- ============================================================
-- CLEANUP
-- ============================================================
_G.JJKAutoFarm = {
    destroy = function()
        State.running = false
        for _, t in ipairs(threads) do pcall(task.cancel, t) end
        if screenGui and screenGui.Parent then screenGui:Destroy() end
        _G.JJKAutoFarm = nil
        print("[JJK AutoFarm] Destroyed.")
    end
}

print("[JJK AutoFarm v2] Loaded. To destroy: _G.JJKAutoFarm.destroy()")
