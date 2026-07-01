-- =============================================================================
-- 🌌 CASE PARADISE SENTINEL AUTOFARM HUB v4.5 [ALL-MODES UNIVERSAL]
-- =============================================================================

-- [🛡️ ANTI-AFK]
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
MainFrame.Size = UDim2.new(0, 260, 0, 380)
MainFrame.BorderSizePixel = 2
MainFrame.BorderColor3 = Color3.fromRGB(57, 255, 20)
MainFrame.Active = true
MainFrame.Draggable = true

Title.Parent = MainFrame
Title.Size = UDim2.new(1, 0, 0, 35)
Title.BackgroundColor3 = Color3.fromRGB(20, 22, 34)
Title.Text = "🛰️ CASE PARADISE HUD v4.5"
Title.TextColor3 = Color3.fromRGB(57, 255, 20)
Title.Font = Enum.Font.Code
Title.TextSize = 14

UIListLayout.Parent = MainFrame
UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
UIListLayout.Padding = UDim.new(0, 8)

local _G = _G or {}
_G.AutoQuestBox = false
_G.AutoAllBattles = false
_G.AutoSell = false
_G.MinSellPrice = 10 -- เคลียร์ปืนราคาต่ำกว่า $10 ทันที ($0.14 และ $0.05 จะหายวับ)

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
-- 📦 [1. เควสเปิดกล่อง]: เจาะจงยิงเปิด Ultra Cases แบบตรงตัว
-- =============================================================================
CreateToggleButton("📦 Auto Open Ultra Cases", "AutoQuestBox", function()
    while _G.AutoQuestBox do
        -- ค้นหา Remote ของระบบกล่องทั้งหมดใน ReplicatedStorage
        for _, r in pairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
            if r:IsA("RemoteEvent") and (string.find(r.Name:lower(), "opencase") or string.find(r.Name:lower(), "buycase") or r.Name == "Open" or r.Name == "Unbox") then
                pcall(function() r:FireServer("Ultra Case", 1) end)
                pcall(function() r:FireServer({"Ultra Case"}, 1) end) -- แผนสำรองแบบ Table Array
            elseif r:IsA("RemoteFunction") and (string.find(r.Name:lower(), "opencase") or string.find(r.Name:lower(), "buycase")) then
                pcall(function() r:InvokeServer("Ultra Case", 1) end)
            end
        end
        task.wait(0.5)
    end
end)

-- =============================================================================
-- ⚔️ [2. เควส CASE BATTLE]: ระบบวนลูปยิงคำสั่งสร้างห้องครบทุกโหมดในเกม เพื่อดักทุกเควส!
-- =============================================================================
-- รายชื่อโหมดทั้งหมดของเกม Case Paradise ที่จะถูกบอทสแปมสั่งเล่นอัตโนมัติ
local gameModes = {
    "Classic", "classic", 
    "Crazy Terminal", "crazy terminal", "CrazyTerminal",
    "Teams", "teams", 
    "Juggernaut", "juggernaut", 
    "1v1", "Solo", "solo",
    "Underdog", "underdog"
}

CreateToggleButton("⚔️ Auto Battle (All Modes Loop)", "AutoAllBattles", function()
    while _G.AutoAllBattles do
        for _, r in pairs(game:GetService("ReplicatedStorage"):GetDescendants()) do
            if r:IsA("RemoteEvent") and (string.find(r.Name:lower(), "battle") or string.find(r.Name:lower(), "match")) then
                
                -- ลูปยิงสร้างห้องแมตช์ตามรายชื่อโหมดทั้งหมดด้านบน
                for _, mode in pairs(gameModes) do
                    if not _G.AutoAllBattles then break end
                    
                    pcall(function()
                        -- ยิงโครงสร้างแบบที่ 1 (Dictionary/Table)
                        r:FireServer({
                            ["Mode"] = mode, 
                            ["Cases"] = {"Common Case"}, -- ใช้กล่องถูกสุดปั๊มจำนวนรอบเควส
                            ["Amount"] = 1,
                            ["Privacy"] = "Public"
                        })
                        
                        -- ยิงโครงสร้างแบบที่ 2 (Standard Parameters)
                        r:FireServer(mode, {"Common Case"}, 1, "Public")
                        r:FireServer(mode, {"Common Case"}, 1)
                    end)
                    task.wait(0.2) -- หน่วงเวลาระหว่างยิงโหมดสั้น ๆ กันเกมจับสแปม
                end
            end
        end
        task.wait(5.0) -- จบลูปทุกโหมดแล้วรอ 5 วินาทีก่อนเริ่มวนกวาดใหม่อีกรอบ
    end
end)

-- =============================================================================
-- 💰 [3. ระบบขายไอเทมปืนอัตโนมัติ]: กวาดขายปืนที่มีราคาต่ำกว่ากำหนด
-- =============================================================================
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
    if val then _G.MinSellPrice = val else PriceInput.Text = tostring(_G.MinSellPrice) end
end)

CreateToggleButton("💰 Enable Auto Sell Items", "AutoSell", function()
    while _G.AutoSell do
        local player = game:GetService("Players").LocalPlayer
        
        -- ค้นหาตัวสั่งขายไอเทม
        local sellRemote = game:GetService("ReplicatedStorage"):FindFirstChild("SellItem", true) or 
                           game:GetService("ReplicatedStorage"):FindFirstChild("Sell", true) or
                           game:GetService("ReplicatedStorage"):FindFirstChild("SellSkin", true) or
                           game:GetService("ReplicatedStorage"):FindFirstChild("SellWeapon", true)

        -- วนลูปหาข้อมูลกระเป๋าในตัวผู้เล่นแบบละเอียดยิบ
        for _, obj in pairs(player:GetDescendants()) do
            if obj.Name == "Inventory" or obj.Name == "Skins" or obj.Name == "Weapons" or obj.Name == "MyItems" then
                for _, item in pairs(obj:GetChildren()) do
                    
                    local priceObj = item:FindFirstChild("Price") or item:FindFirstChild("Value") or item:FindFirstChild("Worth")
                    local price = priceObj and priceObj.Value or 0
                    
                    -- หากปืนราคาต่ำกว่าที่เรากำหนด (หรือดึงค่า Object ราคาตรง ๆ ไม่เจอแต่ต้องการบังคับขายปืนถูก)
                    if price < _G.MinSellPrice or price == 0 then
                        if sellRemote then
                            pcall(function() sellRemote:FireServer(item.Name) end)
                            pcall(function() sellRemote:FireServer(item) end)
                            pcall(function() sellRemote:FireServer({item.Name}) end) -- ยิงเป็น Array ป้องกันตัวเกมเปลี่ยนโครงสร้างรับค่า
                            if sellRemote:IsA("RemoteFunction") then
                                pcall(function() sellRemote:InvokeServer(item.Name) end)
                            end
                        end
                    end
                end
            end
        end
        task.wait(1.5)
    end
end)

print("[✅ SENTINEL v4.5] Ultimate Universal Farm Deployed!")
