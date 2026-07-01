-- =============================================================================
-- 🌌 CASE PARADISE SENTINEL AUTOFARM HUB v5.0 [RE-ENGINEERED FROM SCRATCH]
-- =============================================================================

local ScreenGui = Instance.new("ScreenGui")
local MainFrame = Instance.new("Frame")
local UIListLayout = Instance.new("UIListLayout")
local Title = Instance.new("TextLabel")

ScreenGui.Parent = game:GetService("CoreGui")
ScreenGui.Name = "CaseParadiseSentinel"

MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
MainFrame.Position = UDim2.new(0.05, 0, 0.3, 0)
MainFrame.Size = UDim2.new(0, 260, 0, 300)
MainFrame.BorderSizePixel = 2
MainFrame.BorderColor3 = Color3.fromRGB(57, 255, 20)
MainFrame.Active = true
MainFrame.Draggable = true

Title.Parent = MainFrame
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(20, 22, 34)
Title.Text = "🛰️ CASE PARADISE HUD v5.0"
Title.TextColor3 = Color3.fromRGB(57, 255, 20)
Title.Font = Enum.Font.Code
Title.TextSize = 14

UIListLayout.Parent = MainFrame
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 8)

-- แถบแสดงสถานะเควสปัจจุบันที่ตรวจจับได้
local CurrentQuestLabel = Instance.new("TextLabel")
CurrentQuestLabel.Parent = MainFrame
CurrentQuestLabel.Size = UDim2.new(0.9, 0, 0, 40)
CurrentQuestLabel.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
CurrentQuestLabel.Text = "🔍 Scanning Quests..."
CurrentQuestLabel.TextColor3 = Color3.fromRGB(0, 240, 255)
CurrentQuestLabel.Font = Enum.Font.SourceSans
CurrentQuestLabel.TextSize = 13
CurrentQuestLabel.TextWrapped = true

local _G = _G or {}
_G.AutoQuestBox = false
_G.AutoSell = false

local function CreateToggleButton(text, global_var_name, callback)
    local Button = Instance.new("TextButton")
    Button.Parent = MainFrame
    Button.Size = UDim2.new(0.9, 0, 0, 35)
    Button.BackgroundColor3 = Color3.fromRGB(25, 27, 42)
    Button.Text = text .. ": OFF"
    Button.TextColor3 = Color3.fromRGB(255, 0, 127)
    Button.Font = Enum.Font.SourceSansBold
    Button.TextSize = 14
    
    Button.MouseButton1Click:Connect(function()
        _G[global_var_name] = not _G[global_var_name]
        if _G[global_var_name] then
            Button.Text = text .. ": ON"
            Button.TextColor3 = Color3.fromRGB(57, 255, 20)
            Button.BackgroundColor3 = Color3.fromRGB(30, 45, 35)
            if callback then task.spawn(callback) end
        else
            Button.Text = text .. ": OFF"
            Button.TextColor3 = Color3.fromRGB(255, 0, 127)
            Button.BackgroundColor3 = Color3.fromRGB(25, 27, 42)
        end
    end)
    return Button
end

-- =============================================================================
-- 📌 1 & 2. ลอจิกหลัก: สแกน APOCALYPSE QUEST แล้วแตกแขนงไปสั่งเปิดกล่อง หรือ เล่น Battle
-- =============================================================================
local function ScanAndExecuteQuest()
    local player = game:GetService("Players").LocalPlayer
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return end
    
    -- ค้นหาหน้าต่างเควสที่ไม่ใช่ Daily Quests จากหน้าจอ
    local targetQuestText = nil
    local currentProgress = 0
    local maxProgress = 0
    
    for _, v in pairs(playerGui:GetDescendants()) do
        -- ค้นหาข้อความที่อยู่ในหน้าต่างที่ไม่ใช่ Daily Quests และมีตัวบ่งชี้ความคืบหน้า (เช่น 1/9, 0/60)
        if v:IsA("TextLabel") and v.Visible and string.find(v.Text, "/") and not string.find(v.Parent.Name:lower(), "daily") then
            -- ดึงข้อความจากหัวข้อของเควสนั้น ๆ (มักจะเป็น TextLabel ที่อยู่ใกล้กันหรือเป็น Parent/Sibling)
            local questTitleLabel = v.Parent:FindFirstChildOfClass("TextLabel") or v
            if questTitleLabel and questTitleLabel.Text ~= v.Text then
                targetQuestText = questTitleLabel.Text
                -- แกะตัวเลขความคืบหน้า เช่น "1/9"
                currentProgress, maxProgress = v.Text:match("(%d+)/(%d+)")
                currentProgress = tonumber(currentProgress) or 0
                maxProgress = tonumber(maxProgress) or 0
                break
            end
        end
    end
    
    -- หากตรวจพบเควสและยังทำไม่เสร็จ
    if targetQuestText and currentProgress < maxProgress then
        CurrentQuestLabel.Text = "📌 Quest: " .. targetQuestText .. " (" .. currentProgress .. "/" .. maxProgress .. ")"
        
        local textLower = targetQuestText:lower()
        
        -- 🌟 [กรณีที่ ก]: เควสสั่งให้เปิดกล่อง (มีคำว่า Open หรือ Case)
        if string.find(textLower, "open") or string.find(textLower, "case") then
            -- ดึงชื่อกล่องออกจากข้อความ เช่น "Open 60 Ultra Cases." -> "Ultra Case"
            local caseName = targetQuestText:gsub("Open", ""):gsub("Cases", ""):gsub("Case", ""):gsub("%d+", ""):gsub("[%[%]().,:]", "")
            caseName = caseName:match("^%s*(.-)%s*$") .. " Case"
            
            -- ยิง Remote เปิดกล่องใบที่เควสสั่ง
            local openRemote = game:GetService("ReplicatedStorage"):FindFirstChild("OpenCase", true) or game:GetService("ReplicatedStorage"):FindFirstChild("BuyCase", true)
            if openRemote then
                pcall(function() openRemote:FireServer(caseName, 1) end)
            end
            
        -- 🌟 [กรณีที่ ข]: เควสบังคับเล่น Battle Mode (มีคำว่า Battle, Win, Play หรือ Mode)
        elseif string.find(textLower, "battle") or string.find(textLower, "win") or string.find(textLower, "play") then
            -- ค้นหาชื่อโหมดที่เควสสั่งจากประโยค (เช่น Classic, Crazy Terminal, Juggernaut)
            local detectedMode = "Classic" -- ค่าเริ่มต้นถ้าไม่เจอชื่อโหมดเฉพาะ
            if string.find(textLower, "crazy terminal") then
                detectedMode = "Crazy Terminal"
            elseif string.find(textLower, "juggernaut") then
                detectedMode = "Juggernaut"
            elseif string.find(textLower, "teams") then
                detectedMode = "Teams"
            end
            
            -- ยิง Remote สร้างห้องตามโหมดที่ระบบแกะได้จากเควส ณ ตอนนั้นทันที
            local battleRemote = game:GetService("ReplicatedStorage"):FindFirstChild("CreateBattle", true) or game:GetService("ReplicatedStorage"):FindFirstChild("JoinBattle", true)
            if battleRemote then
                pcall(function() 
                    battleRemote:FireServer({
                        ["Mode"] = detectedMode, 
                        ["Cases"] = {"Common Case"}, -- ใช้กล่องที่ถูกที่สุดเพื่อปั๊มจำนวนรอบเควส
                        ["Amount"] = 1,
                        ["Privacy"] = "Public"
                    })
                end)
            end
        end
    else
        CurrentQuestLabel.Text = "🔍 Scanning Apocalypse Quests..."
    end
end

-- ปุ่มเปิดระบบทำงานตามเควส (สแกน -> ระบุประเภทเควส -> สั่งการเปิดกล่องหรือลงแข่งอัตโนมัติ)
CreateToggleButton("🎯 Run Auto Quest Scanner", "AutoQuestBox", function()
    while _G.AutoQuestBox do
        pcall(ScanAndExecuteQuest)
        task.wait(1.0) -- ตรวจเช็กและทำงานทุก ๆ 1 วินาที
    end
    CurrentQuestLabel.Text = "🔍 Scanning Quests..."
end)

-- =============================================================================
-- 📌 3. ระบบ AUTO-SELL (รื้อโค้ดใหม่: เจาะหาค่าผ่านระบบ UI Inventory ที่แสดงบนจอจริง)
-- =============================================================================
local function ExecuteAutoSell()
    local player = game:GetService("Players").LocalPlayer
    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return end
    
    -- ค้นหาปุ่มขาย หรือ Remote ขายที่ตัวเกมเรียกใช้งานจริงผ่านการตรวจสอบจาก UI หน้าต่างช่องเก็บของ
    local sellRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SellItem", true) or game:GetService("ReplicatedStorage"):FindFirstChild("Sell", true)
    
    -- วิ่งไล่ดูไอเทมในหน้าต่าง UI Inventory ที่เปิดอยู่บนหน้าจอของคุณเพื่อหาชื่อไอเทมจริง ๆ ในเซสชันนั้น
    for _, v in pairs(playerGui:GetDescendants()) do
        -- หา TextLabel ที่แสดงชื่อปืนหรือราคาปืนในหน้าคลังสินค้า เพื่อดึงชื่อตัวแปรที่ตรงกับระบบของเกม
        if v:IsA("TextLabel") and string.find(v.Text, "%$") then
            -- สมมติว่าโครงสร้างคือกล่องไอเทมที่มีชื่อปืนอยู่ร่วมด้วย
            local itemFrame = v.Parent
            if itemFrame then
                local itemName = itemFrame.Name
                -- ยิงคำสั่งขายไอเทมชิ้นนั้นออกไปที่เซิร์ฟเวอร์โดยตรง
                if sellRemote and itemName ~= "" and itemName ~= "Frame" then
                    pcall(function() sellRemote:FireServer(itemName) end)
                end
            end
        end
    end
end

CreateToggleButton("💰 Enable Auto Sell Items", "AutoSell", function()
    while _G.AutoSell do
        pcall(ExecuteAutoSell)
        task.wait(2.0) -- ตรวจสอบเพื่อกวาดขายปืนทุก ๆ 2 วินาที
    end
end)
