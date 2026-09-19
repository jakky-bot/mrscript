-- ============================================================
-- JJK WORLD: TRAIN YOUR AURA - AUTO FARM SCRIPT v3
-- Features: Auto Roll (combo) + Speed Multiplier, Equip Best
--           Aura, Auto Teleport to best zone, Auto Rebirth
--           with configurable aura threshold, Auto Tap/Train
--           with Tap Multiplier selector, Full Redesigned UI
-- ============================================================

-- Prevent duplicate instances
if _G.JJKAutoFarm then
    _G.JJKAutoFarm.destroy()
end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
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
    -- Roll (spin/combo) settings
    baseRollDelay       = 0.05,
    rollSpeedMultIndex  = 1,
    rollSpeedMults      = { 1, 2, 4, 8 },
    rollSpeedLabels     = { "x1", "x2", "x4", "x8" },

    -- Tap/Train settings  (auto-clicking MainDice to earn power)
    -- tapMults match the in-game x2/x4/x8/x16 multiplier buttons
    baseTapDelay        = 0.1,          -- base seconds between taps
    tapMultIndex        = 1,            -- current tap multiplier index
    tapMults            = { 2, 4, 8, 16 },
    tapMultLabels       = { "x2", "x4", "x8", "x16" },

    teleportDelay       = 2.0,
    rebirthCheckInterval = 3,
    equipAuraInterval   = 10,
    zoneScanInterval    = 8,

    rebirthAuraThreshold = 0,
}

-- ============================================================
-- STATE
-- ============================================================
local State = {
    autoRoll     = false,
    autoTap      = false,      -- NEW: auto tap/train toggle
    autoEquip    = false,
    autoTeleport = false,
    autoRebirth  = false,
    running      = true,
    status       = "Idle",
    bestZone     = "None",
    currentAura  = 0,
    tapCount     = 0,          -- session tap counter
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

local VIM = game:GetService("VirtualInputManager")

-- Real simulated click via VirtualInputManager (works for training tap buttons)
local function realClick(btn)
    if not btn then return end
    local abs = btn.AbsolutePosition
    local sz  = btn.AbsoluteSize
    local cx  = abs.X + sz.X / 2
    local cy  = abs.Y + sz.Y / 2
    pcall(function()
        VIM:SendMouseButtonEvent(cx, cy, 0, true,  game, 1)
        VIM:SendMouseButtonEvent(cx, cy, 0, false, game, 1)
    end)
end

-- Fallback event-fire for non-training buttons (roll, equip, rebirth, etc.)
local function fireButton(btn)
    if not btn then return end
    pcall(function() btn.MouseButton1Click:Fire() end)
    task.wait(0.01)
    pcall(function() btn:Activate() end)
end

-- Selects the in-game tap multiplier button matching the current config index.
-- The training UI has buttons labelled x2, x4, x8, x16 — we find and real-click the right one.
local function selectTapMultButton()
    local targetLabel = CONFIG.tapMultLabels[CONFIG.tapMultIndex] -- e.g. "x2"
    pcall(function()
        -- Search common HUD/training frame paths for a button whose text matches
        for _, gui in ipairs(playerGui:GetChildren()) do
            for _, btn in ipairs(gui:GetDescendants()) do
                if (btn:IsA("TextButton") or btn:IsA("ImageButton")) then
                    -- Check direct text match or a child TextLabel
                    local txt = (btn:IsA("TextButton") and btn.Text) or ""
                    if txt == "" then
                        local lbl = btn:FindFirstChildWhichIsA("TextLabel", true)
                        if lbl then txt = lbl.Text end
                    end
                    if txt:lower() == targetLabel:lower() then
                        realClick(btn)
                        return
                    end
                end
            end
        end
    end)
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

-- Tap/Train: selects the in-game multiplier button (x2/x4/x8/x16) then
-- real-clicks MainDice so the server registers a proper tap with bonus power.
local _lastTapMultIndex = -1
local function doTap()
    -- Re-select the in-game multiplier button whenever the player changes it
    if CONFIG.tapMultIndex ~= _lastTapMultIndex then
        selectTapMultButton()
        _lastTapMultIndex = CONFIG.tapMultIndex
        task.wait(0.05)
    end

    -- Real-click the main training/tap button
    pcall(function()
        local btn = playerGui.HUD["1"]:FindFirstChild("MainDice")
        if btn then
            realClick(btn)
            State.tapCount = State.tapCount + 1
        end
    end)
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
        local l3 = playerGui.HUD["1"]["2"]["3"]
        for _, frame in pairs(l3:GetChildren()) do
            if frame.Name == "4" then
                local rb = frame:FindFirstChild("RebirthTeleport")
                if rb then
                    fireButton(rb)
                    State.status = "Teleporting to Rebirth..."
                    task.wait(2)
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

-- Roll loop
spawn(function()
    while State.running do
        if State.autoRoll then
            local mult  = CONFIG.rollSpeedMults[CONFIG.rollSpeedMultIndex] or 1
            local delay = CONFIG.baseRollDelay / mult
            pcall(doRoll)
            task.wait(math.max(delay, 0.016))
        else
            task.wait(0.1)
        end
    end
end)

-- Tap/Train loop  ← NEW
spawn(function()
    while State.running do
        if State.autoTap then
            local mult  = CONFIG.tapMults[CONFIG.tapMultIndex] or 1
            local delay = CONFIG.baseTapDelay / mult
            pcall(doTap)
            task.wait(math.max(delay, 0.016))
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

-- Rebirth loop
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
                    task.wait(6)
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
    s.Color     = color or Color3.fromRGB(60, 60, 90)
    s.Thickness = thickness or 1
    return s
end

local function applyGradient(parent, c0, c1, rotation)
    local g = Instance.new("UIGradient", parent)
    g.Color    = ColorSequence.new(c0, c1)
    g.Rotation = rotation or 90
    return g
end

-- ── Color palette ─────────────────────────────────────────
local COL = {
    bg        = Color3.fromRGB(8,  10,  18),
    bgAlt     = Color3.fromRGB(12, 14,  24),
    panel     = Color3.fromRGB(16, 18,  30),
    panelAlt  = Color3.fromRGB(22, 24,  40),
    titleBg   = Color3.fromRGB(18, 22,  52),
    btnOff    = Color3.fromRGB(30, 30,  50),
    btnOn     = Color3.fromRGB(10, 40,  15),
    accent    = Color3.fromRGB(90, 130, 255),
    accentAlt = Color3.fromRGB(60, 100, 220),
    textMain  = Color3.fromRGB(210, 215, 230),
    textDim   = Color3.fromRGB(110, 115, 140),
    textGreen = Color3.fromRGB(70,  240, 110),
    textRed   = Color3.fromRGB(230, 70,  70),
    textGold  = Color3.fromRGB(255, 200, 80),
    textBlue  = Color3.fromRGB(120, 190, 255),
    textPurp  = Color3.fromRGB(180, 120, 255),
    tapColor  = Color3.fromRGB(255, 140, 50),
    tapActive = Color3.fromRGB(200, 90,  10),
    divider   = Color3.fromRGB(35,  38,  65),
}

-- ============================================================
-- BUILD UI
-- ============================================================
local existingUI = playerGui:FindFirstChild("JJKAutoFarmUI")
if existingUI then existingUI:Destroy() end

local screenGui = Instance.new("ScreenGui")
screenGui.Name           = "JJKAutoFarmUI"
screenGui.ResetOnSpawn   = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder   = 999
screenGui.Parent         = playerGui

-- ── Main frame ────────────────────────────────────────────
local UI_WIDTH  = 256
local UI_HEIGHT = 560   -- taller for new tap section

local main = Instance.new("Frame")
main.Name             = "MainFrame"
main.Size             = UDim2.new(0, UI_WIDTH, 0, UI_HEIGHT)
main.Position         = UDim2.new(0, 10, 0.5, -UI_HEIGHT / 2)
main.BackgroundColor3 = COL.bg
main.BorderSizePixel  = 0
main.Active           = true
main.Draggable        = true
main.Parent           = screenGui
applyCorner(main, 12)
applyStroke(main, COL.accent, 1.5)

-- Subtle gradient on background
applyGradient(main, Color3.fromRGB(12, 14, 26), Color3.fromRGB(6, 8, 16), 145)

-- ── Title bar ─────────────────────────────────────────────
local titleBar = Instance.new("Frame")
titleBar.Size             = UDim2.new(1, 0, 0, 40)
titleBar.BackgroundColor3 = COL.titleBg
titleBar.BorderSizePixel  = 0
titleBar.Parent           = main
applyCorner(titleBar, 12)
applyGradient(titleBar, Color3.fromRGB(30, 40, 90), Color3.fromRGB(15, 20, 50), 135)

-- bottom-half filler so rounded corners only appear at top
local titleFix = Instance.new("Frame")
titleFix.Size             = UDim2.new(1, 0, 0.5, 0)
titleFix.Position         = UDim2.new(0, 0, 0.5, 0)
titleFix.BackgroundColor3 = COL.titleBg
titleFix.BorderSizePixel  = 0
titleFix.Parent           = titleBar

local titleLbl = Instance.new("TextLabel")
titleLbl.Size               = UDim2.new(1, -50, 1, 0)
titleLbl.Position           = UDim2.new(0, 12, 0, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text               = "⚡ JJK AUTO FARM  v3"
titleLbl.TextColor3         = COL.textBlue
titleLbl.TextScaled         = true
titleLbl.Font               = Enum.Font.GothamBold
titleLbl.TextXAlignment     = Enum.TextXAlignment.Left
titleLbl.Parent             = titleBar

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size             = UDim2.new(0, 28, 0, 28)
closeBtn.Position         = UDim2.new(1, -34, 0, 6)
closeBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
closeBtn.BorderSizePixel  = 0
closeBtn.Text             = "✕"
closeBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
closeBtn.TextScaled       = true
closeBtn.Font             = Enum.Font.GothamBold
closeBtn.AutoButtonColor  = false
closeBtn.Parent           = titleBar
applyCorner(closeBtn, 6)
closeBtn.MouseButton1Click:Connect(function()
    _G.JJKAutoFarm.destroy()
end)

-- ── Helper: section divider label ─────────────────────────
local function makeSectionLabel(text, yPos, icon)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, -16, 0, 16)
    row.Position         = UDim2.new(0, 8, 0, yPos)
    row.BackgroundTransparency = 1
    row.Parent           = main

    local line = Instance.new("Frame")
    line.Size             = UDim2.new(1, 0, 0, 1)
    line.Position         = UDim2.new(0, 0, 0.5, 0)
    line.BackgroundColor3 = COL.divider
    line.BorderSizePixel  = 0
    line.Parent           = row

    local lbl = Instance.new("TextLabel")
    lbl.Size               = UDim2.new(0, 130, 1, 0)
    lbl.Position           = UDim2.new(0, 4, 0, 0)
    lbl.BackgroundColor3   = COL.bg
    lbl.BorderSizePixel    = 0
    lbl.Text               = (icon or "") .. " " .. text
    lbl.TextColor3         = COL.textDim
    lbl.TextScaled         = true
    lbl.Font               = Enum.Font.GothamSemibold
    lbl.TextXAlignment     = Enum.TextXAlignment.Left
    lbl.Parent             = row
    applyGradient(lbl, COL.bg, Color3.fromRGB(8, 10, 18), 0)
end

-- ── Status / info bars ────────────────────────────────────
local function makeMiniBar(yOffset, defaultText, textColor)
    local bar = Instance.new("Frame")
    bar.Size             = UDim2.new(1, -16, 0, 22)
    bar.Position         = UDim2.new(0, 8, 0, yOffset)
    bar.BackgroundColor3 = COL.panel
    bar.BorderSizePixel  = 0
    bar.Parent           = main
    applyCorner(bar, 5)
    applyStroke(bar, COL.divider, 1)

    local lbl = Instance.new("TextLabel")
    lbl.Size             = UDim2.new(1, -8, 1, 0)
    lbl.Position         = UDim2.new(0, 6, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text             = defaultText
    lbl.TextColor3       = textColor or COL.textMain
    lbl.TextScaled       = true
    lbl.Font             = Enum.Font.Gotham
    lbl.TextXAlignment   = Enum.TextXAlignment.Left
    lbl.Parent           = bar
    return lbl
end

local statusLbl = makeMiniBar(46, "● Idle", COL.textGreen)
local infoLbl   = makeMiniBar(72, "Aura: —  |  Rebirths: —", COL.textGold)

-- ── Toggle button factory ─────────────────────────────────
local function makeToggle(labelText, iconText, yPos, activeColor, activeStrokeColor, onToggle)
    local btn = Instance.new("TextButton")
    btn.Size             = UDim2.new(1, -16, 0, 40)
    btn.Position         = UDim2.new(0, 8, 0, yPos)
    btn.BackgroundColor3 = COL.btnOff
    btn.BorderSizePixel  = 0
    btn.Text             = ""
    btn.AutoButtonColor  = false
    btn.Parent           = main
    applyCorner(btn, 8)
    local stroke = applyStroke(btn, Color3.fromRGB(42, 42, 68), 1)

    -- Icon area
    local iconBg = Instance.new("Frame")
    iconBg.Size             = UDim2.new(0, 34, 0, 30)
    iconBg.Position         = UDim2.new(0, 5, 0.5, -15)
    iconBg.BackgroundColor3 = Color3.fromRGB(25, 25, 45)
    iconBg.BorderSizePixel  = 0
    iconBg.Parent           = btn
    applyCorner(iconBg, 6)

    local iconLbl = Instance.new("TextLabel")
    iconLbl.Size               = UDim2.new(1, 0, 1, 0)
    iconLbl.BackgroundTransparency = 1
    iconLbl.Text               = iconText
    iconLbl.TextScaled         = true
    iconLbl.Font               = Enum.Font.GothamBold
    iconLbl.Parent             = iconBg

    -- Badge (ON/OFF)
    local badge = Instance.new("TextLabel")
    badge.Size             = UDim2.new(0, 36, 0, 18)
    badge.Position         = UDim2.new(1, -42, 0.5, -9)
    badge.BackgroundColor3 = Color3.fromRGB(60, 15, 15)
    badge.BorderSizePixel  = 0
    badge.Text             = "OFF"
    badge.TextColor3       = COL.textRed
    badge.TextScaled       = true
    badge.Font             = Enum.Font.GothamBold
    badge.Parent           = btn
    applyCorner(badge, 4)

    local nameLbl = Instance.new("TextLabel")
    nameLbl.Size           = UDim2.new(1, -90, 1, 0)
    nameLbl.Position       = UDim2.new(0, 44, 0, 0)
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
            btn.BackgroundColor3  = activeColor or COL.btnOn
            stroke.Color          = activeStrokeColor
            badge.Text            = "ON"
            badge.TextColor3      = COL.textGreen
            badge.BackgroundColor3 = Color3.fromRGB(10, 50, 15)
            iconBg.BackgroundColor3 = Color3.fromRGB(20, 40, 20)
        else
            btn.BackgroundColor3  = COL.btnOff
            stroke.Color          = Color3.fromRGB(42, 42, 68)
            badge.Text            = "OFF"
            badge.TextColor3      = COL.textRed
            badge.BackgroundColor3 = Color3.fromRGB(60, 15, 15)
            iconBg.BackgroundColor3 = Color3.fromRGB(25, 25, 45)
        end
    end

    btn.MouseButton1Click:Connect(function()
        on = not on; refresh(); onToggle(on)
    end)
    return btn
end

-- ── Section: Automation toggles ───────────────────────────
makeSectionLabel("AUTOMATION", 100, "🔧")

makeToggle("Auto Roll / Combo",    "🎲", 120,
    Color3.fromRGB(18, 45, 80), Color3.fromRGB(80, 200, 255),
    function(v)
        State.autoRoll = v
        State.status   = v and "Auto Rolling..." or "Roll paused"
    end)

makeToggle("Equip Best Aura",      "✨", 164,
    Color3.fromRGB(40, 18, 60), Color3.fromRGB(200, 100, 255),
    function(v)
        State.autoEquip = v
        if v then task.spawn(doEquipBest) end
    end)

makeToggle("Auto Best Zone",       "🌍", 208,
    Color3.fromRGB(18, 50, 30), Color3.fromRGB(100, 255, 150),
    function(v)
        State.autoTeleport = v
        if v then
            local zone = getBestZone(getAuraValue())
            State.bestZone = zone.name
            teleportToZone(zone)
        end
    end)

makeToggle("Auto Rebirth",         "🔄", 252,
    Color3.fromRGB(50, 35, 10), Color3.fromRGB(255, 180, 50),
    function(v)
        State.autoRebirth = v
        State.status = v and "Watching for rebirth threshold..." or "Rebirth paused"
    end)

-- ── Section: Roll Speed ───────────────────────────────────
makeSectionLabel("ROLL SPEED BOOST", 300, "⚡")

local function makeMultRow(yPos, mults, labels, activeColor, inactiveColor, onSelect)
    local row = Instance.new("Frame")
    row.Size             = UDim2.new(1, -16, 0, 30)
    row.Position         = UDim2.new(0, 8, 0, yPos)
    row.BackgroundTransparency = 1
    row.Parent           = main

    local layout = Instance.new("UIListLayout", row)
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.Padding       = UDim.new(0, 5)
    layout.SortOrder     = Enum.SortOrder.LayoutOrder

    local btns = {}
    for i, lbl in ipairs(labels) do
        local sb = Instance.new("TextButton")
        sb.Size             = UDim2.new(1 / #labels, -5, 1, 0)
        sb.BackgroundColor3 = (i == 1) and activeColor or inactiveColor
        sb.BorderSizePixel  = 0
        sb.Text             = lbl
        sb.TextColor3       = Color3.fromRGB(255, 255, 255)
        sb.TextScaled       = true
        sb.Font             = Enum.Font.GothamBold
        sb.AutoButtonColor  = false
        sb.LayoutOrder      = i
        sb.Parent           = row
        applyCorner(sb, 7)
        applyStroke(sb, Color3.fromRGB(50, 50, 80), 1)
        table.insert(btns, sb)

        sb.MouseButton1Click:Connect(function()
            for j, b in ipairs(btns) do
                b.BackgroundColor3 = (j == i) and activeColor or inactiveColor
            end
            onSelect(i, lbl)
        end)
    end
    return btns
end

makeMultRow(318,
    CONFIG.rollSpeedMults, CONFIG.rollSpeedLabels,
    Color3.fromRGB(60, 160, 240), Color3.fromRGB(28, 28, 48),
    function(i, lbl)
        CONFIG.rollSpeedMultIndex = i
        State.status = "Roll speed → " .. lbl
    end)

-- ── Section: Tap / Train Multiplier ───────────────────────
makeSectionLabel("TAP POWER MULTIPLIER", 356, "👊")

-- Auto Tap toggle (compact, inline with the section)
makeToggle("Auto Tap / Train",     "👊", 375,
    Color3.fromRGB(55, 28, 5), Color3.fromRGB(255, 140, 50),
    function(v)
        State.autoTap  = v
        State.tapCount = 0
        State.status   = v and "Auto Tapping..." or "Tap paused"
    end)

makeMultRow(419,
    CONFIG.tapMults, CONFIG.tapMultLabels,
    Color3.fromRGB(220, 100, 20), Color3.fromRGB(28, 28, 48),
    function(i, lbl)
        CONFIG.tapMultIndex = i
        State.status = "Tap speed → " .. lbl
    end)

-- ── Section: Rebirth ──────────────────────────────────────
makeSectionLabel("AUTO REBIRTH CONFIG", 458, "🔁")

local threshRow = Instance.new("Frame")
threshRow.Size             = UDim2.new(1, -16, 0, 30)
threshRow.Position         = UDim2.new(0, 8, 0, 476)
threshRow.BackgroundColor3 = COL.panel
threshRow.BorderSizePixel  = 0
threshRow.Parent           = main
applyCorner(threshRow, 7)
applyStroke(threshRow, COL.divider, 1)

local threshBox = Instance.new("TextBox")
threshBox.Size              = UDim2.new(1, -76, 1, 0)
threshBox.BackgroundTransparency = 1
threshBox.Text              = ""
threshBox.PlaceholderText   = "Rebirth at Aura (e.g. 1.76M)"
threshBox.PlaceholderColor3 = COL.textDim
threshBox.TextColor3        = COL.textGold
threshBox.TextScaled        = true
threshBox.Font              = Enum.Font.GothamSemibold
threshBox.TextXAlignment    = Enum.TextXAlignment.Left
threshBox.ClearTextOnFocus  = false
threshBox.Parent            = threshRow
local threshPad = Instance.new("UIPadding", threshBox)
threshPad.PaddingLeft = UDim.new(0, 8)

local setBtn = Instance.new("TextButton")
setBtn.Size             = UDim2.new(0, 62, 1, -6)
setBtn.Position         = UDim2.new(1, -66, 0, 3)
setBtn.BackgroundColor3 = Color3.fromRGB(30, 100, 35)
setBtn.BorderSizePixel  = 0
setBtn.Text             = "SET"
setBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
setBtn.TextScaled       = true
setBtn.Font             = Enum.Font.GothamBold
setBtn.AutoButtonColor  = false
setBtn.Parent           = threshRow
applyCorner(setBtn, 5)

local function flashSetBtn(ok)
    setBtn.BackgroundColor3 = ok and Color3.fromRGB(30, 180, 60) or Color3.fromRGB(180, 40, 40)
    task.delay(0.4, function() setBtn.BackgroundColor3 = Color3.fromRGB(30, 100, 35) end)
end

setBtn.MouseButton1Click:Connect(function()
    local raw = threshBox.Text:gsub("%s+", "")
    if raw == "" or raw == "0" then
        CONFIG.rebirthAuraThreshold = 0
        State.status = "Rebirth threshold cleared"
        flashSetBtn(true); return
    end
    local parsed = parseNumber(raw)
    if parsed > 0 then
        CONFIG.rebirthAuraThreshold = parsed
        State.status = "Rebirth at → " .. formatNumber(parsed)
        flashSetBtn(true)
    else
        State.status = "⚠ Invalid threshold"
        flashSetBtn(false)
    end
end)

-- Manual rebirth button
local nowBtn = Instance.new("TextButton")
nowBtn.Size             = UDim2.new(1, -16, 0, 28)
nowBtn.Position         = UDim2.new(0, 8, 0, 512)
nowBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 12)
nowBtn.BorderSizePixel  = 0
nowBtn.Text             = "⚡ REBIRTH NOW"
nowBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
nowBtn.TextScaled       = true
nowBtn.Font             = Enum.Font.GothamBold
nowBtn.AutoButtonColor  = false
nowBtn.Parent           = main
applyCorner(nowBtn, 7)
applyStroke(nowBtn, Color3.fromRGB(220, 100, 40), 1)
nowBtn.MouseButton1Click:Connect(function()
    nowBtn.BackgroundColor3 = Color3.fromRGB(220, 100, 20)
    State.status = "Manual rebirth..."
    task.spawn(doRebirth)
    task.delay(0.3, function() nowBtn.BackgroundColor3 = Color3.fromRGB(150, 50, 12) end)
end)

-- ── Footer version tag ────────────────────────────────────
local footerLbl = Instance.new("TextLabel")
footerLbl.Size               = UDim2.new(1, 0, 0, 12)
footerLbl.Position           = UDim2.new(0, 0, 1, -14)
footerLbl.BackgroundTransparency = 1
footerLbl.Text               = "JJK AutoFarm v3  —  drag title to move"
footerLbl.TextColor3         = COL.textDim
footerLbl.TextScaled         = true
footerLbl.Font               = Enum.Font.Gotham
footerLbl.Parent             = main

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

            -- Status dot color
            local dot = State.autoTap and "🟠" or (State.autoRoll and "🔵" or "●")
            statusLbl.Text = dot .. " " .. State.status

            local thresh = CONFIG.rebirthAuraThreshold
            if State.autoTeleport then
                local zone = getBestZone(aura)
                State.bestZone = zone.name
                infoLbl.Text = "🌍 " .. zone.name .. "  |  " .. formatNumber(aura)
            elseif thresh > 0 then
                local pct = math.floor(math.min(aura / thresh * 100, 100))
                infoLbl.Text = "Rebirth: " .. formatNumber(aura) .. " / "
                             .. formatNumber(thresh) .. "  (" .. pct .. "%)"
            elseif State.autoTap then
                infoLbl.Text = "👊 Taps: " .. tostring(State.tapCount)
                             .. "  |  Aura: " .. formatNumber(aura)
            else
                infoLbl.Text = "Aura: " .. formatNumber(aura)
                             .. "  |  Births: " .. rebirths
            end
        end)
    end
end)

-- ============================================================
-- CLEANUP / GLOBAL HANDLE
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

print("[JJK AutoFarm v3] Loaded. To destroy: _G.JJKAutoFarm.destroy()")
