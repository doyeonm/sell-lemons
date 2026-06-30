if _G.MatchaCleanup then pcall(_G.MatchaCleanup) end
if _G.SellLemonsConnection then pcall(function() _G.SellLemonsConnection:Disconnect() end) _G.SellLemonsConnection = nil end

local ScriptActive = true
_G.SellLemonsActive = true

local mfloor, mabs = math.floor, math.abs
local tinsert = table.insert
local pcall_ = pcall
local task_wait, task_spawn = task.wait, task.spawn
local tick_ = tick
local sformat = string.format
local CF = CFrame.new

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local playerGui = player:WaitForChild("PlayerGui")

pcall_(function() setrobloxinput(true) end)

local autoBuyActive = false
local buyDecosActive = false 
local lemonFarmActive = false
local autoStandActive = false

local myTycoon = nil
local tempBlacklist = {}
local blacklistTime = {}

local function getMyTycoon()
    for _, t in ipairs(workspace:GetChildren()) do
        if t.Name:lower():find("tycoon") then
            local owner = t:FindFirstChild("Owner")
            if owner and tostring(owner.Value) == player.Name then return t end
        end
    end
    return nil
end

local function getButtonKey(v)
    if not v or not v.Position then return nil end
    local p = v.Position
    return sformat("%d,%d,%d", mfloor(p.X+0.5), mfloor(p.Y+0.5), mfloor(p.Z+0.5))
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

local function isDecoration(btn)
    if not btn then return false end
    local isDeco = false
    pcall_(function()
        local n1 = btn.Name:lower()
        local n2 = btn.Parent and btn.Parent.Name:lower() or ""
        if n1:find("deco") or n2:find("deco") or n1:find("tree") or n2:find("tree") or n1:find("bush") or n2:find("bush") then
            isDeco = true
        end
    end)
    if isDeco then return true end

    local ok3, color3 = pcall_(function() return btn.Color end)
    if ok3 and color3 then
        local r, g, b = normalizeColor(color3)
        if r > 150 and g < 70 and b < 70 then return true end
    end
    
    local ok4, bColor = pcall_(function() return btn.BrickColor.Name end)
    if ok4 and type(bColor) == "string" and bColor:lower():find("red") then return true end

    return false
end

local function getButtonsRealTime()
    local temp = {}
    if myTycoon and myTycoon.Parent then
        for _, v in ipairs(myTycoon:GetDescendants()) do
            if v.Name == "Button" and v:IsA("BasePart") then
                if buyDecosActive or not isDecoration(v) then
                    tinsert(temp, v)
                end
            end
        end
    end
    return temp
end

task_spawn(function()
    while ScriptActive do
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if hrp then
            local drops = workspace:FindFirstChild("CashDrops")
            if drops then
                local hrpPos = hrp.Position
                for _, v in ipairs(drops:GetDescendants()) do
                    if v.Name == "TouchInterest" and v.Parent and v.Parent:IsA("BasePart") then
                        pcall_(function() v.Parent.Position = hrpPos end)
                    end
                end
            end
        end
        task_wait(0.3)
    end
end)

local homesick
local ok, err = pcall_(function()
    loadstring(game:HttpGet("https://raw.githubusercontent.com/sharedechoes/Matcha-Luas/refs/heads/main/homesick.lua"))()
end)
homesick = _G.homesick or shared.homesick

if homesick then
    pcall_(function() homesick.changelogEnabled = false end)
    local window = homesick.createWindow("sell lemons", 420, 400)
    local tab1 = window:addTab("automation")
    local left = tab1:addSection("automation", "Left")
    local right = tab1:addSection("other", "Right")

    left:addToggle("autoBuy", "auto buy", false, function(val) autoBuyActive = val end):addKeybind("1", "Toggle", true)
    left:addToggle("lemonFarm", "lemon farm", false, function(val) lemonFarmActive = val end):addKeybind("2", "Toggle", true)
    left:addToggle("autoStand", "auto stand", false, function(val) autoStandActive = val end):addKeybind("3", "Toggle", true)

    right:addToggle("stopAll", "stop all", false, function(val)
        if val then
            autoBuyActive = false; lemonFarmActive = false; autoStandActive = false;
            tempBlacklist = {}; blacklistTime = {}
        end
    end):addKeybind("9", "Toggle", true)
    
    right:addToggle("buyDecos", "Buy Decos", false, function(val)
        buyDecosActive = val
        tempBlacklist = {}; blacklistTime = {}
    end)

    window.visible = true
    window:render()
    _G.MatchaWindow = window
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Q then
        if _G.MatchaWindow then
            _G.MatchaWindow.visible = not _G.MatchaWindow.visible
            pcall_(function() _G.MatchaWindow:render() end)
        end
    end
end)

local _isBuying = false

task_spawn(function()
    while ScriptActive do
        if not autoBuyActive then task_wait(0.1); continue end
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp or not myTycoon or not myTycoon.Parent then 
            myTycoon = getMyTycoon()
            task_wait(0.3); continue 
        end

        local buttons = getButtonsRealTime()
        local targetBtn = nil
        local targetDist = math.huge
        local hrpPos = hrp.Position
        local currentTime = tick_()

        for _, btn in ipairs(buttons) do
            local key = getButtonKey(btn)
            if key then
                if tempBlacklist[key] and (currentTime - blacklistTime[key]) > 4 then
                    tempBlacklist[key] = nil
                end
                if not tempBlacklist[key] and not isGreyedOut(btn) then
                    local dist = (btn.Position - hrpPos).Magnitude
                    if dist < targetDist then
                        targetDist = dist
                        targetBtn = btn
                    end
                end
            end
        end

        if targetBtn then
            _isBuying = true 
            local key = getButtonKey(targetBtn)
            local pos = targetBtn.Position

            pcall_(function() hrp.CFrame = CF(pos.X, pos.Y + 2.5, pos.Z) end)
            task_wait(0.02)

            local bought = false
            local t0 = tick_()
            while ScriptActive and autoBuyActive and (tick_() - t0) < 0.45 do
                pcall_(function() hrp.CFrame = CF(pos.X, pos.Y + 0.8, pos.Z) end)
                task_wait(0.03)
                local gone = true
                pcall_(function() gone = not (targetBtn and targetBtn.Parent and targetBtn:IsDescendantOf(myTycoon)) end)
                if gone then bought = true; break end
                if isGreyedOut(targetBtn) then break end
            end

            if bought then
                tempBlacklist = {}
                blacklistTime = {}
            else
                tempBlacklist[key] = true
                blacklistTime[key] = tick_()
            end
            _isBuying = false
        else
            _isBuying = false
            task_wait(0.2)
        end
    end
end)

local function getLemonsFast()
    local temp = {}
    for _, tycoon in ipairs(workspace:GetChildren()) do
        if tycoon.Name:find("Tycoon") then
            local constant = tycoon:FindFirstChild("Constant")
            if constant then
                local trees = constant:FindFirstChild("Trees")
                if trees then
                    for _, tree in ipairs(trees:GetChildren()) do
                        for _, fruit in ipairs(tree:GetChildren()) do
                            if fruit.Name == "Fruit" then
                                local cp = fruit:FindFirstChild("ClickPart")
                                if cp and cp:IsA("BasePart") and cp.Position.Y <= 14 then
                                    tinsert(temp, cp)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    local rootLT = workspace:FindFirstChild("LemonTree")
    if rootLT then
        for _, fruit in ipairs(rootLT:GetChildren()) do
            if fruit.Name == "Fruit" then
                local cp = fruit:FindFirstChild("ClickPart")
                if cp and cp:IsA("BasePart") and cp.Position.Y <= 14 then
                    tinsert(temp, cp)
                end
            end
        end
    end
    return temp
end

task_spawn(function()
    while ScriptActive do
        if not lemonFarmActive then task_wait(0.1); continue end
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp then task_wait(0.1); continue end

        if lemonFarmActive and not _isBuying then
            local snapshot = getLemonsFast()
            for i = 1, #snapshot do
                if not lemonFarmActive or _isBuying then break end
                local v = snapshot[i]
                if v and v:IsDescendantOf(workspace) then
                    pcall_(function() v.CFrame = hrp.CFrame end)
                end
            end
            task_wait(0.05)
        else
            task_wait(0.1)
        end
    end
end)

task_spawn(function()
    while ScriptActive do
        if not autoStandActive then task_wait(0.25); continue end
        if not myTycoon or not myTycoon.Parent then task_wait(0.5); continue end

        local purchases; pcall_(function() purchases = myTycoon:FindFirstChild("Purchases") end)
        if purchases then
            for _, f in ipairs(purchases:GetChildren()) do
                if not autoStandActive then break end
                if f.Name:lower():find("lemon") then
                    local pos
                    for _, d in ipairs(f:GetDescendants()) do
                        if d:IsA("BasePart") then pos = d.Position; break end
                    end
                    if pos then
                        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            pcall_(function() hrp.CFrame = CF(pos.X, pos.Y + 3, pos.Z) end)
                            task_wait(0.1)
                            local t0 = tick_()
                            while autoStandActive and (tick_() - t0) < 1.5 do
                                pcall_(function()
                                    local vim = game:GetService("VirtualInputManager")
                                    vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                    task_wait(0.015)
                                    vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                end)
                            end
                        end
                    end
                end
            end
        end
        task_wait(60)
    end
end)

_G.MatchaCleanup = function()
    ScriptActive = false
    _G.SellLemonsActive = false
    pcall_(function() if _G.MatchaWindow then _G.MatchaWindow.visible = false end end)
end
