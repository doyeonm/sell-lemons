-- [[ Sell Lemons - Final Stable Version (UI Fix + Q Toggle + Auto Cash) ]] --
if _G.MatchaCleanup then pcall(_G.MatchaCleanup) end
if _G.SellLemonsConnection then
    pcall(function() _G.SellLemonsConnection:Disconnect() end)
    _G.SellLemonsConnection = nil
end

local ScriptActive = true
_G.SellLemonsActive = true

-- 기본 설정
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

-- 상태 변수
local autoBuyActive   = false
local buyDecosActive  = false 
local lemonFarmActive = false
local autoStandActive = false

-- ==================== [핵심] 오토 캐시 (항시 작동) ====================
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

-- ==================== UI 로드 (안정적인 버전) ====================
local homesick
local UIRef = { win = nil, t = {} }

-- 라이브러리 로드
local ok, err = pcall(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/sharedechoes/Matcha-Luas/refs/heads/main/homesick.lua"))()
end)
homesick = _G.homesick or shared.homesick

if homesick then
    pcall(function() homesick.changelogEnabled = false end)
    local window = homesick.createWindow("sell lemons", 420, 400)
    UIRef.win = window
    
    local tab1 = window:addTab("automation")
    local left = tab1:addSection("automation", "Left")
    
    -- 오토 바이
    UIRef.t.AutoBuy = left:addToggle("autoBuy", "auto buy", false, function(val)
        autoBuyActive = val
    end):addKeybind("1", "Toggle", true)

    -- 데코 스킵 (기본값 false: 스킵함)
    UIRef.t.BuyDecos = left:addToggle("buyDecos", "Buy Decos", false, function(val)
        buyDecosActive = val
    end)

    -- 레몬 팜
    UIRef.t.LemonFarm = left:addToggle("lemonFarm", "lemon farm", false, function(val)
        lemonFarmActive = val
    end):addKeybind("2", "Toggle", true)

    -- 오토 스탠드
    UIRef.t.AutoStand = left:addToggle("autoStand", "auto stand", false, function(val)
        autoStandActive = val
    end):addKeybind("3", "Toggle", true)

    -- 우측 섹션
    local right = tab1:addSection("other", "Right")
    
    UIRef.t.StopAll = right:addToggle("stopAll", "stop all", false, function(val)
        if val then
            autoBuyActive = false; lemonFarmActive = false; autoStandActive = false;
            pcall(function() UIRef.t.AutoBuy:SetValue(false) end)
            pcall(function() UIRef.t.LemonFarm:SetValue(false) end)
            pcall(function() UIRef.t.AutoStand:SetValue(false) end)
            task.delay(0.1, function()
                pcall(function() UIRef.t.StopAll:SetValue(false) end)
            end)
        end
    end):addKeybind("9", "Toggle", true)

    window.visible = true
    window:render()
end

-- ==================== [핵심] Q키로 UI 끄기/켜기 ====================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Q then
        if UIRef.win then
            UIRef.win.visible = not UIRef.win.visible
            pcall(function() UIRef.win:render() end)
        end
    end
end)

-- (나머지 오토 바이, 레몬 파밍 로직은 기존 잘 작동하던 로직 그대로 유지)
-- [이 아래에 기존의 오토 바이, 레몬 파밍 등의 로직을 그대로 붙여넣으세요]
