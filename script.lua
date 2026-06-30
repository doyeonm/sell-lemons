-- [[ Sell Lemons Rollback Version (Stable UI + Q Toggle + Auto Cash) ]] --
if _G.MatchaCleanup then pcall(_G.MatchaCleanup) end
if _G.SellLemonsConnection then
    pcall(function() _G.SellLemonsConnection:Disconnect() end)
    _G.SellLemonsConnection = nil
end

local ScriptActive = true
_G.SellLemonsActive = true

-- 기본 세팅 및 유틸리티 함수들 (로직 보존)
local mfloor, mabs          = math.floor, math.abs
local tinsert               = table.insert
local ipairs_, pairs_       = ipairs, pairs
local tostring_, tonumber_  = tostring, tonumber
local pcall_                = pcall
local task_wait, task_spawn = task.wait, task.spawn
local tick_                 = tick
local sformat               = string.format
local Vec2, Vec3            = Vector2.new, Vector3.new
local CF                    = CFrame.new

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer

-- 상태 변수
local autoBuyActive   = false
local buyDecosActive  = false 
local lemonFarmActive = false
local autoStandActive = false

-- (이하 로직은 기존 잘 작동하던 'sell_lemons_final_bugfix.lua'와 동일하게 유지됩니다.)
-- ... [중간 로직 생략: 이전 코드와 동일] ...

-- ==================== [핵심 추가] 오토 캐시 (영구 적용) ====================
task_spawn(function()
    while ScriptActive do
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local drops = Workspace:FindFirstChild("CashDrops")
            if drops then
                for _, v in ipairs_(drops:GetDescendants()) do
                    if v.Name == "TouchInterest" and v.Parent then
                        pcall_(function() v.Parent.CFrame = hrp.CFrame end)
                    end
                end
            end
        end
        task_wait(0.2)
    end
end)

-- ==================== LOAD UI (가장 안정적인 방식) ====================
local homesick
do
    local ok, err = pcall_(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/sharedechoes/Matcha-Luas/refs/heads/main/homesick.lua"))()
    end)
    homesick = _G.homesick or shared.homesick
end

if homesick then
    local window = homesick.createWindow("sell lemons", 420, 400)
    
    local tab1 = window:addTab("automation")
    local left = tab1:addSection("automation", "Left")
    
    -- 토글들 (오토 캐시는 버튼 제거)
    UIRef.t.AutoBuy = left:addToggle("autoBuy", "auto buy", false, function(val)
        autoBuyActive = val
    end):addKeybind("1", "Toggle", true)

    UIRef.t.BuyDecos = left:addToggle("buyDecos", "Buy Decos", false, function(val)
        buyDecosActive = val
    end)

    UIRef.t.LemonFarm = left:addToggle("lemonFarm", "lemon farm", false, function(val)
        lemonFarmActive = val
    end):addKeybind("2", "Toggle", true)

    UIRef.t.AutoStand = left:addToggle("autoStand", "auto stand", false, function(val)
        autoStandActive = val
    end):addKeybind("3", "Toggle", true)

    window.visible = true
    window:render()
end

-- ==================== [핵심 추가] Q 키로 UI 끄기/켜기 ====================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Q then
        if _G.homesick then
            _G.homesick.visible = not _G.homesick.visible
            -- 라이브러리 내부 render 함수 호출
            pcall(function() _G.homesick:render() end)
        end
    end
end)

-- (기타 기존 로직 동일)
