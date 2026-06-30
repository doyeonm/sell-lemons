-- [[ Sell Lemons Ultimate - AutoBuy Speed UP & Red Deco Restored ]] --
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
pcall_(function() setrobloxinput(true) end)

local mouse = nil
pcall_(function() mouse = player:GetMouse() end)

local DEBUG  = false
local rprint = print
local print  = function(...) if DEBUG then rprint(...) end end

local function _wrap(tag, fn)
    task_spawn(function()
        while ScriptActive do
            local ok, err = pcall_(fn)
            if ok then break end
            rprint("[SellLemons][ERROR] [" .. tag .. "] " .. tostring_(err))
            task_wait(0.5)
        end
    end)
end

-- ==================== CONFIG & STATE ====================
local CFG = {
    standRest = 60,
    zoomTicks = 16,
    zoomStep  = 1,
    buyWindow = 0.45,
}

local autoBuyActive   = false
local buyDecosActive  = false 
local lemonFarmActive = false
local autoStandActive = false

local _standIsTapping = false
local _isBuying       = false 
local _lemonZoomedIn  = false
local _lemonWasActive = false

local myTycoon = nil
local UIRef = { win = nil, t = {} }
local S = { pmx = 0, pmy = 0, keyDown = {}, lastFire = {} }

local function _windowFocused()
    if type(isrbxactive) ~= "function" then return true end
    local ok, r = pcall_(isrbxactive)
    if not ok then return true end
    return r ~= false
end

-- ==================== TYCOON FINDER ====================
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

-- ==================== SMART BLACKLIST & FILTER ====================
local tempBlacklist = {}
local blacklistTime = {}

local function getButtonKey(v)
    if not v then return nil end
    local pos = v.Position
    if not pos then return nil end
    return sformat("%d,%d,%d", mfloor(pos.X+0.5), mfloor(pos.Y+0.5), mfloor(pos.Z+0.5))
end

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

-- [수정됨] 빨간색 = 데코 필터 다시 부활
local decoNameCache = {}
local function isDecoration(btn)
    if not btn then return false end
    
    local cachedNameResult = decoNameCache[btn]
    if cachedNameResult == nil then
        local isDecoName = false
        local ok, btnName = pcall_(function() return string.lower(btn.Name) end)
        if ok and btnName and (string.find(btnName, "deco") or string.find(btnName, "tree") or string.find(btnName, "bush")) then 
            isDecoName = true 
        else
            local parent = btn.Parent
            if parent then
                local ok2, parentName = pcall_(function() return string.lower(parent.Name) end)
                if ok2 and parentName and (string.find(parentName, "deco") or string.find(parentName, "tree") or string.find(parentName, "bush")) then 
                    isDecoName = true 
                end
            end
        end
        decoNameCache[btn] = isDecoName
        cachedNameResult = isDecoName
    end

    if cachedNameResult then return true end

    -- 빨간색 발판은 무조건 데코로 간주 (요청 반영)
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
    pcall_(function()
        folder.AncestryChanged:Connect(function(_, parent)
            if not parent then
                buttonsFolderSet[folder] = nil
                for i = #buttonsFolders, 1, -1 do
                    if buttonsFolders[i] == folder then table.remove(buttonsFolders, i); break end
                end
            end
        end)
    end)
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

local function _anyLiveButtons()
    local buttons = getButtonsRealTime()
    local currentTime = tick_()
    for _, btn in ipairs_(buttons) do
        local key = getButtonKey(btn)
        if key then
            -- [수정됨] 대기 시간 10초 -> 4초로 변경
            local isBlacklisted = tempBlacklist[key] and (currentTime - blacklistTime[key]) <= 4
            if not isBlacklisted and not isGreyedOut(btn) then
                return true
            end
        end
    end
    return false
end


-- ==================== AUTO CASH FARM (항시 적용) ====================
_wrap("cash-farm", function()
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
            task_wait(0.3)
        else
            task_wait(0.2)
        end
    end
end)


-- ==================== LOAD EXTERNAL UI ====================
local homesick
do
    local ok, err = pcall_(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/sharedechoes/Matcha-Luas/refs/heads/main/homesick.lua"))()
    end)
    homes
