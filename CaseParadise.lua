-- =============================================================================
-- 🌌 CASE PARADISE SENTINEL AUTOFARM HUB v3.0 [APOCALYPSE QUEST FIXED]
-- =============================================================================

local VirtualUser = game:GetService("VirtualUser")
game:GetService("Players").LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new(0,0))
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
Title.Text = "🛰️ CASE PARADISE HUD v3.0"
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
_G.MinSellPrice = 10000 -- ตั้งเผื่อไว้ตามเดิม แต่สคริปต์ใหม่จะรองรับค่าหลักหน่วย/ทศนิยมได้ด้วย

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

-- 🎯 เจาะจงระบบสแกนตามหน้าต่าง Apocalypse Quests บนจอคุณโดยเฉพาะ
local function GetCurrentQuestCaseName()
    local player = game:GetService("Players").LocalPlayer
    local playerGui = player:FindFirstChild("PlayerGui")
    
    if playerGui then
        -- สแกนหาข้อความในหน้า UI เพื่อดึงคำว่า "Ultra Cases" ออกมาตรงๆ
        for _, v in pairs(playerGui:GetDescendants()) do
            if v:IsA("TextLabel") and v.Visible and string.find(v.Text:lower(), "open") and string.find(v.Text:lower(), "cases") then
                -- ตัดพวกตัวเลขด้านหน้าออก (เช่น Open 60 Ultra Cases -> เหลือ Ultra Cases)
                local cleanText = v.Text:gsub("Open", ""):gsub("Cases", ""):gsub("Case", ""):gsub("%d+", ""):gsub("[%[%]():]", "")
                cleanText = cleanText:match("^%s*(.-)%s*$") -- เคลียร์ช่องว่าง
                if cleanText and cleanText ~= "" then
                    return cleanText .. " Case" -- คืนค่าเป็น "Ultra Case"
                end
            end
        end
    end
    return "Ultra Case" -- แผนสำรองยิงไปที่กล่อง Ultra ตรงตามรูปเควสของคุณ
end

-- [📦 AUTO OPEN CASES]
CreateToggleButton("📦 Auto Scan & Open Cases", "AutoQuestBox", function()
    while _G.AutoQuestBox do
        local currentTargetCase = GetCurrentQuestCaseName()
        QuestStatusLabel.Text = "🎯 Target Case: " .. currentTargetCase
        
        local openRemote = game:GetService("ReplicatedStorage"):FindFirstChild("OpenCase", true) or 
                           game:GetService("ReplicatedStorage"):FindFirstChild("BuyCase", true) or
                           game:GetService("ReplicatedStorage"):FindFirstChild("CaseRemote", true)
                           
        if openRemote then
            -- ป้อนค่าเปิดกล่องไปที่ตัวแปรที่เราแกะมาได้จากเควส
            pcall(function()
                if openRemote:IsA("RemoteFunction") then
                    openRemote:InvokeServer(currentTargetCase, 1)
                else
                    openRemote:FireServer(currentTargetCase, 1)
                end
            end)
        end
        task.wait(0.8)
    end
    QuestStatusLabel.Text = "🔍 Target Case: Scanning..."
end)

-- [⚔️ AUTO CLASSIC BATTLE LOOP]
CreateToggleButton("⚔️ Auto Classic Battle Loop", "AutoClassicBattle", function()
    while _G.AutoClassicBattle do
        local battleRemote = game:GetService("ReplicatedStorage"):FindFirstChild("CreateBattle", true) or
                             game:GetService("ReplicatedStorage"):FindFirstChild("JoinBattle", true)
                             
        if battleRemote then
            local args = { ["Mode"] = "Classic", ["Cases"] = {"Common Case"}, ["Amount"] = 1, ["Privacy"] = "Public" }
            pcall(function() battleRemote:FireServer(args) end)
        end
        task.wait(6.0)
    end
end)

-- [💰 AUTO SELL SYSTEM - เจาะระบบขายจากของในกระเป๋าปืน]
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
    else
        PriceInput.Text = tostring(_G.MinSellPrice)
    end
end)

CreateToggleButton("💰 Enable Auto Sell Items", "AutoSell", function()
    while _G.AutoSell do
        local player = game:GetService("Players").LocalPlayer
        -- วิ่งหาตำแหน่งจัดเก็บไอเทมปืนในเซิฟเวอร์ให้ครอบคลุมที่สุด
        local inventory = player:FindFirstChild("Inventory") or player:FindFirstChild("Skins") or (player:FindFirstChild("Data") and (player.Data:FindFirstChild("Inventory") or player.Data:FindFirstChild("Skins")))
        
        if inventory then
            for _, item in pairs(inventory:GetChildren()) do
                -- ตรวจสอบมูลค่าปืน ดึงผ่านชื่อ ค่านิยม หรือโฟลเดอร์ย่อยของตัวไอเทม
                local priceObj = item:FindFirstChild("Price") or item:FindFirstChild("Value") or item:FindFirstChild("Worth")
                local price = priceObj and priceObj.Value or 0
                
                -- แผนสำรอง: ถ้าในไอเทมไม่มีราคา ให้พยายามดึงข้อมูลราคาจากชื่อที่แสดงบน UI ของปืนชิ้นนั้น
                if price == 0 and player.PlayerGui:FindFirstChild("Inventory") then
                    for _, guiItem in pairs(player.PlayerGui.Inventory:GetDescendants()) do
                        if guiItem:IsA("TextLabel") and string.find(guiItem.Text, "%$") and guiItem.Parent.Name == item.Name then
                            price = tonumber(guiItem.Text:gsub("%$", "")) or 0
                        end
                    end
                end

                -- ถ้าของชิ้นนั้นราคาต่ำกว่าที่คุณกรอกไว้ในหน้าเมนู... สั่งขายทิ้งทันที!
                if price < _G.MinSellPrice then
                    local sellRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SellItem", true) or 
                                       game:GetService("ReplicatedStorage"):FindFirstChild("Sell", true) or
                                       game:GetService("ReplicatedStorage"):FindFirstChild("SellWeapon", true)
                                       
                    if sellRemote then
                        -- ส่งพารามิเตอร์ทั้งรูปแบบชื่อ และ Object ตัวไอเทมเพื่อความชัวร์ในการสั่งลบออกจากเซิร์ฟเวอร์
                        pcall(function() sellRemote:FireServer(item.Name) end)
                        pcall(function() sellRemote:FireServer(item) end)
                    end
                end
            end
        end
        task.wait(1.5)
    end
end)

print("[✅ SENTINEL v3.0] Screen and Gun Overhaul Complete!")
