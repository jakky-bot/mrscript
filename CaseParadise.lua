-- =============================================================================
-- 🌌 CASE PARADISE SENTINEL AUTOFARM HUB v2.5 [FIXED BATTLE MODE]
-- =============================================================================

local VirtualUser = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new(0,0))
    print("[🔮 SENTINEL] Anti-AFK Triggered.")
end)

local ScreenGui = Instance.new("ScreenGui")
local MainFrame = Instance.new("Frame")
local UIListLayout = Instance.new("UIListLayout")
local Title = Instance.new("TextLabel")

ScreenGui.Parent = game:GetService("CoreGui")
ScreenGui.Name = "CaseParadiseSentinel"

MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 20)
MainFrame.Position = UDim2.new(0.05, 0, 0.3, 0)
MainFrame.Size = UDim2.new(0, 260, 0, 410)
MainFrame.BorderSizePixel = 2
MainFrame.BorderColor3 = Color3.fromRGB(57, 255, 20)
MainFrame.Active = true
MainFrame.Draggable = true

Title.Parent = MainFrame
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(20, 22, 34)
Title.Text = "🛰️ CASE PARADISE HUD v2.5"
Title.TextColor3 = Color3.fromRGB(57, 255, 20)
Title.Font = Enum.Font.Code
Title.TextSize = 14

UIListLayout.Parent = MainFrame
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 8)

local QuestStatusLabel = Instance.new("TextLabel")
QuestStatusLabel.Parent = MainFrame
QuestStatusLabel.Size = UDim2.new(0.9, 0, 0, 30)
QuestStatusLabel.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
QuestStatusLabel.Text = "🔍 Target Case: Scanning..."
QuestStatusLabel.TextColor3 = Color3.fromRGB(0, 240, 255)
QuestStatusLabel.Font = Enum.Font.SourceSansItalic
QuestStatusLabel.TextSize = 13

local _G = _G or {}
_G.AutoQuestBox = false
_G.AutoClassicBattle = false
_G.AutoSell = false
_G.MinSellPrice = 10000 

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

local function GetCurrentQuestCaseName()
    local player = game:GetService("Players").LocalPlayer
    local questData = player:FindFirstChild("Quests") or player:FindFirstChild("QuestData") or (player:FindFirstChild("Data") and player.Data:FindFirstChild("Quests"))
    
    if questData then
        for _, quest in pairs(questData:GetChildren()) do
            local target = quest:FindFirstChild("Target") or quest:FindFirstChild("CaseType") or quest:FindFirstChild("Description") or quest:FindFirstChild("Case")
            local progress = quest:FindFirstChild("Value") or quest:FindFirstChild("Progress")
            local maxProgress = quest:FindFirstChild("MaxValue") or quest:FindFirstChild("TargetValue") or quest:FindFirstChild("Amount")
            
            if target and progress and maxProgress and progress.Value < maxProgress.Value then
                local s = tostring(target.Value)
                if not string.find(s:lower(), "case") then s = s .. " Case" end
                return s
            end
        end
    end
    
    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then
        for _, v in pairs(playerGui:GetDescendants()) do
            if v:IsA("TextLabel") and v.Visible and string.find(v.Text:lower(), "open") and string.find(v.Text:lower(), "/") then
                local cleanText = v.Text:gsub("Open", ""):gsub("%d+/%d+", ""):gsub("Cases", ""):gsub("Case", ""):gsub("[%[%]():]", "")
                cleanText = cleanText:match("^%s*(.-)%s*$")
                if cleanText and cleanText ~= "" then
                    return cleanText .. " Case"
                end
            end
        end
    end
    return "Common Case"
end

-- [📦 AUTO OPEN CASES]
CreateToggleButton("📦 Auto Scan & Open Cases", "AutoQuestBox", function()
    while _G.AutoQuestBox do
        local currentTargetCase = GetCurrentQuestCaseName()
        QuestStatusLabel.Text = "🎯 Target Case: " .. currentTargetCase
        
        -- ค้นหา Remote ระบบเปิดกล่องตรงของตัวเกม
        local openRemote = game:GetService("ReplicatedStorage"):FindFirstChild("OpenCase", true) or 
                           game:GetService("ReplicatedStorage"):FindFirstChild("BuyCase", true) or
                           game:GetService("ReplicatedStorage"):FindFirstChild("CaseRemote", true)
                           
        if openRemote then
            if openRemote:IsA("RemoteFunction") then
                openRemote:InvokeServer(currentTargetCase, 1)
            else
                openRemote:FireServer(currentTargetCase, 1)
            end
        end
        task.wait(0.6)
    end
    QuestStatusLabel.Text = "🔍 Target Case: Scanning..."
end)

-- [⚔️ AUTO CLASSIC BATTLE LOOP - FIXED VERSION]
CreateToggleButton("⚔️ Auto Classic Battle Loop", "AutoClassicBattle", function()
    while _G.AutoClassicBattle do
        local battleRemote = game:GetService("ReplicatedStorage"):FindFirstChild("CreateBattle", true) or
                             game:GetService("ReplicatedStorage"):FindFirstChild("JoinBattle", true) or
                             game:GetService("ReplicatedStorage"):FindFirstChild("BattleRemote", true)
                             
        if battleRemote then
            -- ปรับโครงสร้าง Arguments ใหม่เพื่อให้เซิร์ฟเวอร์ตรวจรับค่า Mode ผ่าน
            -- ตัวเกมต้องการคีย์เวิร์ดที่เป็นพิมพ์เล็กทั้งหมด หรือต้องการโครงสร้าง Table แทน String โดดๆ
            local args = {
                ["Mode"] = "Classic", 
                ["Cases"] = {"Common Case"}, -- เลือกใช้กล่องเริ่มต้นเพื่อทำจำนวนครั้งของเควส
                ["Amount"] = 1,
                ["Privacy"] = "Public"
            }
            
            -- แผนสำรองหากระบบต้องการอาร์กิวเมนต์แบบอาร์เรย์เรียงลำดับ
            local backupArgs = {
                [1] = "classic", 
                [2] = {"Common Case"},
                [3] = 1
            }
            
            if battleRemote:IsA("RemoteFunction") then
                pcall(function() battleRemote:InvokeServer(args) end)
                pcall(function() battleRemote:InvokeServer(unpack(backupArgs)) end)
            else
                pcall(function() battleRemote:FireServer(args) end)
                pcall(function() battleRemote:FireServer(unpack(backupArgs)) end)
            end
        end
        task.wait(6.0) -- ให้เวลาเซิร์ฟเวอร์เคลียร์ห้องเพื่อป้องกันการสแปมจนโดนเตะ
    end
end)

-- [💰 AUTO SELL SYSTEM]
local InputFrame = Instance.new("Frame")
local InputLabel = Instance.new("TextLabel")
local PriceInput = Instance.new("TextBox")

InputFrame.Parent = MainFrame
InputFrame.Size = UDim2.new(0.9, 0, 0, 40)
InputFrame.BackgroundTransparency = 1

InputLabel.Parent = InputFrame
InputLabel.Size = UDim2.new(0.5, 0, 1, 0)
InputLabel.Text = "Min Sell Price:"
InputLabel.TextColor3 = Color3.fromRGB(226, 232, 240)
InputLabel.Font = Enum.Font.SourceSans
InputLabel.TextSize = 14

PriceInput.Parent = InputFrame
PriceInput.Size = UDim2.new(0.5, 0, 1, 0)
PriceInput.Position = UDim2.new(0.5, 0, 0, 0)
PriceInput.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
PriceInput.Text = tostring(_G.MinSellPrice)
PriceInput.TextColor3 = Color3.fromRGB(0, 240, 255)
PriceInput.Font = Enum.Font.Code
PriceInput.TextSize = 14

PriceInput.FocusLost:Connect(function()
    local val = tonumber(PriceInput.Text)
    if val then
        _G.MinSellPrice = val
        print("[💰 SENTINEL] Updated Min Price to: " .. val)
    else
        PriceInput.Text = tostring(_G.MinSellPrice)
    end
end)

CreateToggleButton("💰 Enable Auto Sell Items", "AutoSell", function()
    while _G.AutoSell do
        local player = game:GetService("Players").LocalPlayer
        local inventoryPath = player:FindFirstChild("Inventory") or player:FindFirstChild("Data") and player.Data:FindFirstChild("Inventory")
                               
        if inventoryPath then
            for _, item in pairs(inventoryPath:GetChildren()) do
                local priceValue = item:FindFirstChild("Price") or item:FindFirstChild("Value")
                if priceValue and priceValue.Value < _G.MinSellPrice then
                    local sellRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SellItem", true) or 
                                       game:GetService("ReplicatedStorage"):FindFirstChild("SellRemote", true)
                    if sellRemote then
                        sellRemote:FireServer(item.Name)
                    end
                end
            end
        end
        task.wait(1.5)
    end
end)

print("[✅ SENTINEL v2.5] Patched & Re-connected to Case Paradise net-nodes!")
