-- =============================================================================
-- 🌌 CASE PARADISE SENTINEL AUTOFARM HUB v6.0 [FORCE ACTION + SMART UI SELL]
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
MainFrame.Size = UDim2.new(0, 260, 0, 320)
MainFrame.BorderSizePixel = 2
MainFrame.BorderColor3 = Color3.fromRGB(57, 255, 20)
MainFrame.Active = true
MainFrame.Draggable = true

Title.Parent = MainFrame
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(20, 22, 34)
Title.Text = "🛰️ CASE PARADISE HUD v6.0"
Title.TextColor3 = Color3.fromRGB(57, 255, 20)
Title.Font = Enum.Font.Code
Title.TextSize = 14

UIListLayout.Parent = MainFrame
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 8)

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Parent = MainFrame
StatusLabel.Size = UDim2.new(0.9, 0, 0, 35)
StatusLabel.BackgroundColor3 = Color3.fromRGB(5, 5, 8)
StatusLabel.Text = "⚡ System Ready"
StatusLabel.TextColor3 = Color3.fromRGB(57, 255, 20)
StatusLabel.Font = Enum.Font.SourceSans
StatusLabel.TextSize = 14

local _G = _G or {}
_G.AutoQuestBox = false
_G.AutoSell = false
_G.MinSellPrice = 1.0 -- ตั้งราคาขายขั้นต่ำเริ่มต้นไว้ที่ $1.0 (ปืน $0.14 และ $0.05 จะถูกขายออก)

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
-- 📦 1 & 2. ลูปทำลายล้างเควส: ยิงคำสั่งตรงเปิด Ultra Case + วนสร้างห้องสู้ทุกโหมดไปพร้อมกัน!
-- =============================================================================
local battleModes = {"Classic", "Crazy Terminal", "Teams", "Juggernaut", "Underdog"}

CreateToggleButton("🚀 Run Apocalypse Farm", "AutoQuestBox", function()
    StatusLabel.Text = "🔥 Open Cases & Battles Active!"
    StatusLabel.TextColor3 = Color3.fromRGB(255, 170, 0)
    
    while _G.AutoQuestBox do
        local replicated = game:GetService("ReplicatedStorage")
        
        -- [ส่วนที่ 1: สั่งเปิดกล่อง Ultra Case ทันที]
        local openRemote = replicated:FindFirstChild("OpenCase", true) or replicated:FindFirstChild("BuyCase", true)
        if openRemote then
            pcall(function() openRemote:FireServer("Ultra Case", 1) end)
        end
        
        -- [ส่วนที่ 2: วนสั่งสร้างห้อง Battle ครบทุกโหมดเพื่อดักเควสบอร์ด]
        local battleRemote = replicated:FindFirstChild("CreateBattle", true) or replicated:FindFirstChild("JoinBattle", true)
        if battleRemote then
            for _, mode in pairs(battleModes) do
                pcall(function()
                    battleRemote:FireServer({
                        ["Mode"] = mode,
                        ["Cases"] = {"Common Case"}, -- ใช้กล่องถูกสุดปั๊มจำนวนรอบ
                        ["Amount"] = 1,
                        ["Privacy"] = "Public"
                    })
                end)
            end
        end
        
        task.wait(1.5) -- หน่วงเวลาที่ปลอดภัยเพื่อป้องกันเซิร์ฟเวอร์เตะ
    end
    StatusLabel.Text = "⚡ System Ready"
    StatusLabel.TextColor3 = Color3.fromRGB(57, 255, 20)
end)

-- =============================================================================
-- 💰 3. ระบบ AUTO-SELL: ดึงตัวเลขจากป้ายราคาเขียวบน UI ตรงๆ ต่ำกว่าที่ตั้ง = ขายทิ้ง!
-- =============================================================================
local InputFrame = Instance.new("Frame")
local InputLabel = Instance.new("TextLabel")
local PriceInput = Instance.new("TextBox")

InputFrame.Parent = MainFrame
InputFrame.Size = UDim2.new(0.9, 0, 0, 40)
InputFrame.BackgroundTransparency = 1

InputLabel.Parent = InputFrame
InputLabel.Size = UDim2.new(0.5, 0, 1, 0)
InputLabel.Text = "Min Price ($):"
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
    if val then _G.MinSellPrice = val else PriceInput.Text = tostring(_G.MinSellPrice) end
end)

CreateToggleButton("💰 Smart Auto Sell Items", "AutoSell", function()
    while _G.AutoSell do
        local player = game:GetService("Players").LocalPlayer
        local playerGui = player:FindFirstChild("PlayerGui")
        
        local sellRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SellItem", true) or 
                           game:GetService("ReplicatedStorage"):FindFirstChild("Sell", true)
        
        if playerGui and sellRemote then
            -- วิ่งสแกนหาข้อความราคาปืนสีเขียว (\$0.14) บนหน้าต่างคลังปืนของคุณโดยตรง
            for _, v in pairs(playerGui:GetDescendants()) do
                if v:IsA("TextLabel") and v.Visible and string.find(v.Text, "%$") then
                    -- แกะเอาเฉพาะตัวเลขทศนิยมออกมาจากข้อความ เช่น "$0.14" -> 0.14
                    local priceText = v.Text:gsub("%$", "")
                    local actualPrice = tonumber(priceText)
                    
                    if actualPrice and actualPrice < _G.MinSellPrice then
                        -- ดึงชื่อไอเทมจาก Frame หลักที่เป็นพ่อมัน เพื่อส่งค่าไปขาย
                        local itemBox = v.Parent
                        if itemBox and itemBox.Name ~= "Frame" and itemBox.Name ~= "Template" then
                            pcall(function() 
                                sellRemote:FireServer(itemBox.Name)
                            end)
                        end
                    end
                end
            end
        end
        task.wait(2.0) -- วนลูปกวาดเช็กราคาปืนบนหน้าจอทุกๆ 2 วินาที
    end
end)
