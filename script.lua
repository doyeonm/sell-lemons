-- [[ Sell Lemons Ultimate - Luau (Solara/Celery) Bulletproof ]] --
if _G.MatchaCleanup then pcall(_G.MatchaCleanup) end
if _G.SellLemonsConnection then
    pcall(function() _G.SellLemonsConnection:Disconnect() end)
    _G.SellLemonsConnection = nil
end

local ScriptActive = true
_G.SellLemonsActive = true

-- ==================== LOCAL CACHE ====================
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
local C3rgb                 = Color3.fromRGB

-- ==================== INIT ====================
local Players, RunService, player, camera
local initAttempts = 0
while not player and initAttempts < 50 do
    initAttempts = initAttempts + 1
    pcall_(function()
        Players    = game:GetService("Players")
        RunService = game:GetService("RunService")
        player     = Players.LocalPlayer
        if player then camera = workspace.CurrentCamera end
    end)
    if not player then task_wait(0.1) end
end
if not player then warn("[SellLemons] No LocalPlayer"); return end
if not camera then camera = workspace.CurrentCamera end

local playerGui = player:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")

-- [크래시 원인 픽스] Luau 인젝터에 없는 해킹 함수 보호 처리
pcall_(function() setrobloxinput(true) end)

local mouse = nil
pcall_(function() mouse = player:GetMouse() end)

local DEBUG  = false
local rprint = print
local print  = function(...) if DEBUG then rprint(...) end end

-- ==================== STATE ====================
local autoBuyActive   = false
local buyDecosActive  = false 
local lemonFarmActive = false
local autoStandActive = false

local myTycoon = nil

-- ==================== UI CREATION (파스텔 하늘색 자체 UI) ====================
local existingUI = playerGui:FindFirstChild("SellLemonsPastelUI")
if existingUI then existingUI:Destroy() end

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "SellLemonsPastelUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.Parent = playerGui

local MainFrame = Instance.new("Frame")
MainFrame.Size = UDim2.new(0, 240, 0, 280)
MainFrame.Position = UDim2.new(0.5, -120, 0.5, -140)
MainFrame.BackgroundColor3 = Color3.fromRGB(190, 225, 245) -- 파스텔 하늘색
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

local function createToggle(name, text, defaultState, callback)
    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, 0, 0, 35)
    
    local colorOn = Color3.fromRGB(160, 220, 170) -- 연한 민트
    local colorOff = Color3.fromRGB(245, 250, 255) -- 하얀색
    
    btn.BackgroundColor3 = defaultState and colorOn or colorOff
    btn.Text = text .. (defaultState and " [ON]" or " [OFF]")
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
        if callback then callback(toggles[name]) end
    end)
end

-- ==================== KEY & TYCOON LOGIC ====================
local function _windowFocused()
    if type(isrbxactive) ~= "function" then return true end
    local ok, r = pcall_(isrbxactive)
    if not ok then return true end
    return r ~= false
end

local function findMyTycoon()
    local pname = player.Name
    for _, tycoon in ipairs_(workspace:GetChildren()) do
        if tycoon.Name:find("Tycoon") then
            local owner = tycoon:FindFirstChild("Owner")
            if owner then
                local val
                pcall_(function() val = tostring_(owner.Value) end)
                if val and val:find(pname) then return tycoon end
            end
        end
    end
    return nil
end
myTycoon = findMyTycoon()

-- ==================== BUY BLACKLIST ====================
local buyBlacklist = {}
local failedButtons = {}
local buyAttempt = {}

local function getButtonKey(v)
    if not v then return nil end
    local pos = v.Position
    if not pos then return nil end
    return sformat("%d,%d,%d", mfloor(pos.X+0.5), mfloor(pos.Y+0.5), mfloor(pos.Z+0.5))
end

local function resetBuyBlacklist()
    buyBlacklist  = {}
    failedButtons = {}
    buyAttempt    = {}
end

local function buyReady(key, v)
    local a = buyAttempt[key]
    if not a then return true end
    if v and a.inst and a.inst ~= v then buyAttempt[key] = nil; return true end
    if a.n >= 6 then return false end
    return tick_() >= a.next
end

local function markBuyFail(key, v)
    local a = buyAttempt[key]
    if not a then a = { n=0, next=0 }; buyAttempt[key] = a end
    a.inst = v or a.inst
    a.n = a.n + 1
    local d = 0.35 * (2 ^ (a.n - 1))
    if d > 4 then d = 4 end
    a.next = tick_() + d
end

local function isBlacklisted(key, v)
    if buyBlacklist[key] then return true end
    return false
end

-- ==================== COLOR / GREY HELPERS ====================
local function normalizeColor(c)
    local r, g, b = c.R, c.G, c.B
    if r <= 1 and g <= 1 and b <= 1 then r, g, b = r*255, g*255, b*255 end
    return r, g, b
end

local function isGreyedOut(v)
    if not v or not v:IsA("BasePart") then return false end
    local ok, color3 = pcall_(function() return v.Color end)
    if not ok or not color3 then return false end
    local r, g, b = normalizeColor(color3)
    return mabs(r-g) < 30 and mabs(g-b) < 30 and mabs(r-b) < 30 and r < 200
end

local decoNameCache = {}
local function isDecoration(btn)
    if not btn then return false end
    
    local cachedNameResult = decoNameCache[btn]
    if cachedNameResult == nil then
        local isDecoName = false
        local ok, btnName = pcall_(function() return string.lower(btn.Name) end)
        if ok and btnName and (string.find(btnName, "deco") or string.find(btnName, "decoration")) then 
            isDecoName = true 
        else
            local parent = btn.Parent
            if parent then
                local ok2, parentName = pcall_(function() return string.lower(parent.Name) end)
                if ok2 and parentName and (string.find(parentName, "deco") or string.find(parentName, "decoration")) then 
                    isDecoName = true 
                end
            end
        end
        decoNameCache[btn] = isDecoName
        cachedNameResult = isDecoName
    end

    if cachedNameResult then return true end

    local ok3, color3 = pcall_(function() return btn.Color end)
    if ok3 and color3 then
        local r, g, b = normalizeColor(color3)
        if r > 150 and g < 70 and b < 70 then
            return true
        end
    end
    
    local ok4, bColor = pcall_(function() return btn.BrickColor.Name end)
    if ok4 and type(bColor) == "string" and string.find(string.lower(bColor), "red") then
        return true
    end

    return false
end

-- ==================== BUTTONS CACHE ====================
local buttonsFolders    = {}
local buttonsFolderSet  = {}
local buttonsCacheReady = false
local purchasesConnSet  = {}

local function addButtonsFolder(folder)
    if not folder or buttonsFolderSet[folder] then return end
    buttonsFolderSet[folder] = true
    tinsert(buttonsFolders, folder)
end

local function hookPurchaseCategory(cat)
    if not cat or purchasesConnSet[cat] then return end
    purchasesConnSet[cat] = true
    local bf = cat:FindFirstChild("Buttons")
    if bf then addButtonsFolder(bf) end
    pcall_(function()
        cat.ChildAdded:Connect(function(child)
            if child.Name == "Buttons" then addButtonsFolder(child) end
        end)
    end)
end

local function buildButtonsCache()
    buttonsFolders, buttonsFolderSet, purchasesConnSet = {}, {}, {}
    buttonsCacheReady = false
    if not myTycoon then return end
    local purchases = myTycoon:FindFirstChild("Purchases")
    if not purchases then return end
    for _, cat in ipairs_(purchases:GetChildren()) do hookPurchaseCategory(cat) end
    pcall_(function()
        purchases.ChildAdded:Connect(function(newCat) hookPurchaseCategory(newCat) end)
    end)
    buttonsCacheReady = true
end
buildButtonsCache()

local localQueue = {}
local queueIndex = 1

local function getButtonsRealTime()
    if not buttonsCacheReady then buildButtonsCache() end
    if not buttonsCacheReady then return {} end
    local temp = {}
    for i = 1, #buttonsFolders do
        local bf = buttonsFolders[i]
        if bf and bf.Parent then
            for _, model in ipairs_(bf:GetChildren()) do
                local btn = model:FindFirstChild("Button")
                if btn and btn:IsA("BasePart") and btn.Parent then 
                    if buyDecosActive or not isDecoration(btn) then
                        tinsert(temp, btn) 
                    end
                end
                for _, child in ipairs_(model:GetDescendants()) do
                    if child.Name == "Button" and child ~= btn and child:IsA("BasePart") and child.Parent then
                        if buyDecosActive or not isDecoration(child) then
                            tinsert(temp, child)
                        end
                    end
                end
            end
        end
    end
    return temp
end

local function allButtonsDead()
    local buttons = getButtonsRealTime()
    if #buttons == 0 then return false end
    for _, v in ipairs_(buttons) do
        local key = getButtonKey(v)
        if key then
            local a = buyAttempt[key]
            if a and a.inst and a.inst ~= v then buyAttempt[key] = nil; a = nil end
            if not isBlacklisted(key, v) and not isGreyedOut(v) and not (a and a.n >= 6) then
                return false
            end
        end
    end
    return true
end

-- ==================== UI BUTTON EVENTS ====================
local function appendNewButtons()
    if not myTycoon or not myTycoon.Parent then return 0 end
    local buttons = getButtonsRealTime()
    local existingKeys = {}
    for i = queueIndex, #localQueue do
        local it = localQueue[i]
        if it and it.key then existingKeys[it.key] = true end
    end
    local hrpPos = player.Character and player.Character:FindFirstChild("HumanoidRootPart") and player.Character.HumanoidRootPart.Position or nil
    local added = 0
    for _, v in ipairs_(buttons) do
        local key = getButtonKey(v)
        if key and not existingKeys[key] and buyReady(key, v) and not isGreyedOut(v) and not isBlacklisted(key, v) then
            local dist = hrpPos and (v.Position - hrpPos).Magnitude or 999999
            tinsert(localQueue, {btn=v, key=key, dist=dist})
            added = added + 1
        end
    end
    return added
end

createToggle("AutoBuy", "Auto Buy", false, function(val)
    autoBuyActive = val
end)

createToggle("BuyDecos", "Buy Decos (데코 구매)", false, function(val)
    buyDecosActive = val
    resetBuyBlacklist()
    localQueue = {}
    queueIndex = 1
    appendNewButtons()
end)

createToggle("LemonFarm", "Lemon Farm", false, function(val)
    lemonFarmActive = val
end)

createToggle("AutoStand", "Auto Stand", false, function(val)
    autoStandActive = val
end)

-- Q Key Toggle
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Q then
        MainFrame.Visible = not MainFrame.Visible
    end
end)

-- ==================== AUTO CASH FARM (항시 작동) ====================
task_spawn(function()
    while ScriptActive do
        local character = player.Character
        local head = character and character:FindFirstChild("Head")
        if head then
            local drops = workspace:FindFirstChild("CashDrops")
            if drops then
                local headPos = head.Position
                for _, v in ipairs_(drops:GetDescendants()) do
                    if v.Name == "TouchInterest" and v.Parent and v.Parent:IsA("BasePart") then
                        pcall_(function() v.Parent.Position = headPos end)
                    end
                end
            end
        end
        task_wait(0.2)
    end
end)

-- ==================== LEMON TREE CACHE ====================
local lemonTrees = {}
local lemonTreeSet = {}
local lemonTreeCacheReady = false

local function addLemonTree(tree)
    if not tree or lemonTreeSet[tree] then return end
    lemonTreeSet[tree] = true
    tinsert(lemonTrees, tree)
end

local function buildLemonTreeCache()
    lemonTrees, lemonTreeSet = {}, {}
    local rootLT = workspace:FindFirstChild("LemonTree")
    if rootLT then addLemonTree(rootLT) end
    for _, tycoon in ipairs_(workspace:GetChildren()) do 
        if tycoon.Name:find("Tycoon") then
            local constant = tycoon:FindFirstChild("Constant")
            if constant then
                local trees = constant:FindFirstChild("Trees")
                if trees then 
                    for _, t in ipairs_(trees:GetChildren()) do addLemonTree(t) end
                end
            end
        end
    end
    lemonTreeCacheReady = true
end
buildLemonTreeCache()

local function getLemonsFast()
    if not lemonTreeCacheReady then buildLemonTreeCache() end
    local temp = {}
    for ti = 1, #lemonTrees do
        local tree = lemonTrees[ti]
        if tree and tree.Parent then
            for _, fruit in ipairs_(tree:GetChildren()) do
                if fruit.Name == "Fruit" then
                    local cp = fruit:FindFirstChild("ClickPart")
                    if cp and cp:IsA("BasePart") and cp.Position.Y <= 14 then
                        tinsert(temp, cp)
                    end
                end
            end
        end
    end
    return temp
end

local function lemonGone(v)
    return not (v and v.Parent and v:IsDescendantOf(workspace))
end

local function lsmTouch(v, hrp)
    if not hrp then return false end
    pcall_(function() hrp.CFrame = CF(v.Position.X, v.Position.Y, v.Position.Z) end)
    task_wait(0.12)
    if lemonGone(v) then return true end
    return false
end

-- ==================== AUTO BUY WORKER ====================
local lastResetTime = 0
local emptyStreak = 0

task_spawn(function()
    while ScriptActive do
        if not autoBuyActive or _standIsTapping then task_wait(0.05); continue end

        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp or not myTycoon then task_wait(0.05); continue end

        local item = nil
        while queueIndex <= #localQueue do
            if not autoBuyActive then break end
            local candidate = localQueue[queueIndex]
            queueIndex = queueIndex + 1
            if candidate and candidate.btn and candidate.btn.Parent then
                local key = candidate.key
                if buyReady(key, candidate.btn) and not isGreyedOut(candidate.btn) and not isBlacklisted(key, candidate.btn) then
                    item = candidate; break
                end
            end
        end

        if not item and autoBuyActive then
            local remaining = #localQueue - queueIndex + 1
            if remaining <= 0 then
                local added = appendNewButtons()
                if added > 0 then
                    emptyStreak = 0
                    while queueIndex <= #localQueue do
                        if not autoBuyActive then break end
                        local candidate = localQueue[queueIndex]
                        queueIndex = queueIndex + 1
                        if candidate and candidate.btn and candidate.btn.Parent then
                            local key = candidate.key
                            if buyReady(key, candidate.btn) and not isGreyedOut(candidate.btn) and not isBlacklisted(key, candidate.btn) then
                                item = candidate; break
                            end
                        end
                    end
                end
            end
        end

        if not item and autoBuyActive then
            local buttons = getButtonsRealTime()
            local allDead = true
            
            for _, v in ipairs_(buttons) do
                local key = getButtonKey(v)
                if key then
                    local a = buyAttempt[key]
                    if a and a.inst and a.inst ~= v then buyAttempt[key] = nil; a = nil end
                    if not isBlacklisted(key, v) and not isGreyedOut(v) and not (a and a.n >= 6) then
