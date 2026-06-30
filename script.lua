-- [[ Sell Lemons - Solara/Celery Ultimate Fix V8 ]] --
local ScriptActive = true

-- ==================== 1. 가장 먼저 UI부터 띄웁니다 (튕김 방지) ====================
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

local playerGui = player:WaitForChild("PlayerGui", 5)
if not playerGui then warn("PlayerGui Not Found") return end

-- 기존에 켜져있는 UI가 있다면 깔끔하게 지우기
for _, child in ipairs(playerGui:GetChildren()) do
    if child.Name == "SellLemonsV8" then
        pcall(function() child:Destroy() end)
    end
end
pcall(function()
    local coreGui = game:GetService("CoreGui")
    if coreGui:FindFirstChild("SellLemonsV8") then
        coreGui.SellLemonsV8:Destroy()
    end
end)

-- UI 뼈대 만들기
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SellLemonsV8"
ScreenGui.ResetOnSpawn = false

-- 인젝터가 지원하면 CoreGui에, 아니면 PlayerGui에 부착
local parentSuccess = pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end)
if not parentSuccess then ScreenGui.Parent = playerGui end

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 280)
MainFrame.Position = UDim2.new(0.5, -120, 0.5, -140)
MainFrame.BackgroundColor3 = Color3.fromRGB(190, 225, 245) -- 예쁜 파스텔 하늘색
MainFrame.BorderSizePixel = 0
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.Parent = ScreenGui

local UICorner = Instance.new("UICorner")
UICorner.CornerRadius = UDim.new(0, 12)
UICorner.Parent = MainFrame

local Title = Instance.new("TextLabel")
Title.Size = UDim2.new(1, 0, 0, 45)
Title.BackgroundTransparency = 1
Title.Text = "🍋 Sell Lemons"
Title.Font = Enum.Font.GothamBold
Title.TextSize = 20
Title.TextColor3 = Color3.fromRGB(60, 80, 100)
Title.Parent = MainFrame

local Hint = Instance.new("TextLabel")
Hint.Size = UDim2.new(1, 0, 0, 20)
Hint.Position = UDim2.new(0, 0, 0, 35)
Hint.BackgroundTransparency = 1
Hint.Text = "[ Q ] 키를 눌러 숨기기/열기"
Hint.Font = Enum.Font.Gotham
Hint.TextSize = 11
Hint.TextColor3 = Color3.fromRGB(100, 120, 140)
Hint.Parent = MainFrame

local Container = Instance.new("Frame")
Container.Size = UDim2.new(1, -30, 1, -70)
Container.Position = UDim2.new(0, 15, 0, 60)
Container.BackgroundTransparency = 1
Container.Parent = MainFrame

local UIListLayout = Instance.new("UIListLayout")
UIListLayout.Padding = UDim.new(0, 10)
UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
UIListLayout.Parent = Container

local toggles = { AutoBuy = false, BuyDecos = false, LemonFarm = false, AutoStand = false }

local function createToggle(name, text)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 35)
    
    local colorOn = Color3.fromRGB(160, 220, 170)
    local colorOff = Color3.fromRGB(245, 250, 255)
    
    btn.BackgroundColor3 = colorOff
    btn.Text = text .. " [OFF]"
    btn.Font = Enum.Font.GothamSemibold
    btn.TextSize = 14
    btn.TextColor3 = Color3.fromRGB(70, 70, 70)
    btn.Parent = Container
    
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = btn

    btn.MouseButton1Click:Connect(function()
        toggles[name] = not toggles[name]
        btn.BackgroundColor3 = toggles[name] and colorOn or colorOff
        btn.Text = text .. (toggles[name] and " [ON]" or " [OFF]")
    end)
end

createToggle("AutoBuy", "Auto Buy")
createToggle("BuyDecos", "Buy Decos (데코)")
createToggle("LemonFarm", "Lemon Farm")
createToggle("AutoStand", "Auto Stand")

-- Q 키로 UI 숨기기 기능
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Q then
        MainFrame.Visible = not MainFrame.Visible
    end
end)


-- ==================== 2. 자동화 로직 (가볍고 렉 없게) ====================

local function getMyTycoon()
    for _, t in ipairs(Workspace:GetChildren()) do
        if t.Name:lower():find("tycoon") then
            local owner = t:FindFirstChild("Owner")
            if owner and tostring(owner.Value) == player.Name then
                return t
            end
        end
    end
    return nil
end

local function isDeco(btn)
    local n1 = btn.Name:lower()
    local n2 = btn.Parent and btn.Parent.Name:lower() or ""
    if n1:find("deco") or n2:find("deco") then return true end
    if btn.Color then
        local r, g, b = btn.Color.R*255, btn.Color.G*255, btn.Color.B*255
        if r > 150 and g < 70 and b < 70 then return true end
    end
    pcall(function()
        if btn.BrickColor.Name:lower():find("red") then return true end
    end)
    return false
end

local function isGrey(btn)
    if not btn.Color then return false end
    local r, g, b = btn.Color.R*255, btn.Color.G*255, btn.Color.B*255
    return (math.abs(r-g) < 30 and math.abs(g-b) < 30 and r < 200)
end

-- [기능 1] 오토 캐시 (항시 켜져서 플레이어에게 돈을 순간이동시킴)
task.spawn(function()
    while ScriptActive do
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local drops = Workspace:FindFirstChild("CashDrops")
            if drops then
                for _, v in ipairs(drops:GetDescendants()) do
                    if v.Name == "TouchInterest" and v.Parent then
                        pcall(function() v.Parent.CFrame = hrp.CFrame end)
                    end
                end
            end
        end
        task.wait(0.2)
    end
end)

-- [기능 2] 제자리 레몬 파밍
task.spawn(function()
    while ScriptActive do
        if not toggles.LemonFarm then task.wait(0.1); continue end
        
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then task.wait(0.1); continue end
        
        local function collectTree(tree)
            for _, fruit in ipairs(tree:GetChildren()) do
                if fruit.Name == "Fruit" then
                    local cp = fruit:FindFirstChild("ClickPart")
                    if cp and cp:IsA("BasePart") then
                        pcall(function() cp.CFrame = hrp.CFrame end)
                    end
                end
            end
        end

        for _, v in ipairs(Workspace:GetChildren()) do
            if v.Name == "LemonTree" then collectTree(v) end
        end
        
        local tycoon = getMyTycoon()
        if tycoon then
            local constant = tycoon:FindFirstChild("Constant")
            if constant and constant:FindFirstChild("Trees") then
                for _, v in ipairs(constant.Trees:GetChildren()) do
                    collectTree(v)
                end
            end
        end
        task.wait(0.1)
    end
end)

-- [기능 3] 오토 바이 & 오토 스탠드 통합 
task.spawn(function()
    local VIM = game:GetService("VirtualInputManager")
    while ScriptActive do
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        local tycoon = getMyTycoon()
        if not hrp or not tycoon then task.wait(0.2); continue end

        -- 오토 바이 (환생 발판 완벽 감지)
        if toggles.AutoBuy then
            local allBtns = {}
            for _, v in ipairs(tycoon:GetDescendants()) do
                if v.Name == "Button" and v:IsA("BasePart") then
                    table.insert(allBtns, v)
                end
            end
            
            for _, btn in ipairs(allBtns) do
                if not toggles.AutoBuy then break end
                if not isGrey(btn) then
                    if (not toggles.BuyDecos) and isDeco(btn) then continue end
                    pcall(function() hrp.CFrame = btn.CFrame + Vector3.new(0, 2, 0) end)
                    task.wait(0.3)
                end
            end
        end

        -- 오토 스탠드 (E 연타)
        if toggles.AutoStand then
            local purchases = tycoon:FindFirstChild("Purchases")
            if purchases then
                for _, f in ipairs(purchases:GetChildren()) do
                    if not toggles.AutoStand then break end
                    if f.Name:lower():find("lemon") then
                        local pos = nil
                        for _, d in ipairs(f:GetDescendants()) do
                            if d:IsA("BasePart") then pos = d.Position; break end
                        end
                        if pos then
                            pcall(function() hrp.CFrame = CFrame.new(pos.X, pos.Y + 3, pos.Z) end)
                            task.wait(0.1)
                            pcall(function()
                                VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                task.wait(0.05)
                                VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                            end)
                        end
                    end
                end
            end
        end
        
        task.wait(0.1)
    end
end)
