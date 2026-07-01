-- =============================================================================
-- 🌌 CASE PARADISE SENTINEL AUTOFARM HUB v2.0 (AUTOMATIC QUEST SCANNER)
-- =============================================================================

local VirtualUser = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new(0,0))
    print("[🔮 SENTINEL] Anti-AFK Triggered: Kept connection alive.")
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
Title.Text = "🛰️ CASE PARADISE HUD v2.0"
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
    local questData = player:FindFirstChild("Quests") or player:FindFirstChild("QuestData") or player:FindFirstChild("Data") and player.Data:FindFirstChild("Quests")
    
    if questData then
        for _, quest in pairs(questData:GetChildren()) do
            local target = quest:FindFirstChild("Target") or quest:FindFirstChild("CaseType") or quest:FindFirstChild("Description")
            local progress = quest:FindFirstChild("Value") or quest:FindFirstChild("Progress")
            local maxProgress = quest:FindFirstChild("MaxValue") or quest:FindFirstChild("TargetValue") or quest:FindFirstChild("Amount")
            
            if target and progress and maxProgress and progress.Value < maxProgress.Value then
                return tostring(target.Value)
            end
        end
    end
    
    local playerGui = player:FindFirstChild("PlayerGui")
    if playerGui then
        for _, v in pairs(playerGui:GetDescendants()) do
            if v:IsA("TextLabel") and string.find(v.Text:lower(), "open") and string.find(v.Text:lower(), "/") then
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

CreateToggleButton("📦 Auto Scan & Open Cases", "AutoQuestBox", function()
    while _G.AutoQuestBox do
        local currentTargetCase = GetCurrentQuestCaseName()
        QuestStatusLabel.Text = "🎯 Target Case: " .. currentTargetCase
        
        local args = { [1] = currentTargetCase, [2] = 1 } 
        local openRemote = game:GetService("ReplicatedStorage"):FindFirstChild("OpenCase", true) or 
                           game:GetService("ReplicatedStorage"):FindFirstChild("BuyCase", true)
                           
        if openRemote then
            if openRemote:IsA("RemoteFunction") then
                openRemote:InvokeServer(unpack(args))
            else
                openRemote:FireServer(unpack(args))
            end
        end
        task.wait(0.7)
    end
    QuestStatusLabel.Text = "🔍 Target Case: Scanning..."
end)

CreateToggleButton("⚔️ Auto Classic Battle Loop", "AutoClassicBattle", function()
    while _G.AutoClassicBattle do
        local battleRemote = game:GetService("ReplicatedStorage"):FindFirstChild("CreateBattle", true) or
                             game:GetService("ReplicatedStorage"):FindFirstChild("JoinBattle", true)
                             
        if battleRemote then
            local args = {
                [1] = "Classic", 
                [2] = 1, 
                [3] = false 
            }
            if battleRemote:IsA("RemoteFunction") then
                battleRemote:InvokeServer(unpack(args))
            else
                battleRemote:FireServer(unpack(args))
            end
        end
        task.wait(5.0)
    end
end)

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
        print("[💰 SENTINEL] อัปเดตราคาขายขั้นต่ำเป็น: " .. val)
    else
        PriceInput.Text = tostring(_G.MinSellPrice)
    end
end)

CreateToggleButton("💰 Enable Auto Sell Items", "AutoSell", function()
    while _G.AutoSell do
        local inventoryPath = game:GetService("Players").LocalPlayer:FindFirstChild("Inventory") or 
                               game:GetService("Players").LocalPlayer:FindFirstChild("Data")
                               
        if inventoryPath then
            for _, item in pairs(inventoryPath:GetChildren()) do
                local priceValue = item:FindFirstChild("Price") or item:FindFirstChild("Value")
                if priceValue and priceValue.Value < _G.MinSellPrice then
                    local sellRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SellItem", true)
                    if sellRemote then
                        sellRemote:FireServer(item.Name)
                    end
                end
            end
        end
        task.wait(1.5)
    end
end)

print("[✅ SENTINEL] Smart Auto-Quest Scanner Enabled successfully!")
