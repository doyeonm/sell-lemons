if _G.MatchaCleanup then pcall(_G.MatchaCleanup) end
if _G.SellLemonsConnection then pcall(function() _G.SellLemonsConnection:Disconnect() end) _G.SellLemonsConnection = nil end
local ScriptActive = true
_G.SellLemonsActive = true
local mfloor, mabs = math.floor, math.abs
local tinsert = table.insert
local ipairs_, pairs_ = ipairs, pairs
local tostring_, tonumber_ = tostring, tonumber
local pcall_ = pcall
local task_wait, task_spawn = task.wait, task.spawn
local tick_ = tick
local sformat = string.format
local Vec2, Vec3 = Vector2.new, Vector3.new
local CF = CFrame.new
local C3rgb = Color3.fromRGB
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local initAttempts = 0
while not player and initAttempts < 50 do
    initAttempts = initAttempts + 1
    pcall_(function() player = Players.LocalPlayer; if player then camera = workspace.CurrentCamera end end)
    if not player then task_wait(0.1) end
end
if not player then return end
if not camera then camera = workspace.CurrentCamera end
local playerGui = player:WaitForChild("PlayerGui")
pcall_(function() setrobloxinput(true) end)
local mouse = nil
pcall_(function() mouse = player:GetMouse() end)
local errCounts = {}
local function reportErr(tag, err)
    local msg = "[" .. tag .. "] " .. tostring_(err)
    local n = (errCounts[msg] or 0) + 1
    errCounts[msg] = n
end
local function _wrap(tag, fn)
    task_spawn(function()
        while ScriptActive do
            local ok, err = pcall_(fn)
            if ok then break end
            reportErr(tag, err)
            task_wait(0.5)
        end
    end)
end
local CFG = { standRest = 60, zoomTicks = 16, zoomStep = 1, buyWindow = 0.45 }
local autoBuyActive = false
local buyDecosActive = false 
local lemonFarmActive = false
local autoStandActive = false
local _standIsTapping = false
local _isBuying = false
local _lemonZoomedIn = false
local myTycoon = nil
local UIRef = { win = nil, t = {} }
local S = { pmx = 0, pmy = 0, keyDown = {}, lastFire = {} }
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
        if r > 150 and g < 70 and b < 70 then return true end
    end
    local ok4, bColor = pcall_(function() return btn.BrickColor.Name end)
    if ok4 and type(bColor) == "string" and string.find(string.lower(bColor), "red") then return true end
    return false
end
local buttonsFolders = {}
local buttonsFolderSet = {}
local buttonsCacheReady = false
local purchasesConnSet = {}
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
                    if buyDecosActive or not isDecoration(btn) then tinsert(temp, btn) end
                end
                for _, child in ipairs_(model:GetDescendants()) do
                    if child.Name == "Button" and child ~= btn and child:IsA("BasePart") and child.Parent then
                        if buyDecosActive or not isDecoration(child) then tinsert(temp, child) end
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
    for _, v in ipairs_(buttons) do
        local key = getButtonKey(v)
        if key then
            local isBlacklisted = tempBlacklist[key] and (currentTime - blacklistTime[key]) <= 4
            if not isBlacklisted and not isGreyedOut(v) then return true end
        end
    end
    return false
end
_wrap("cash-farm", function()
    while ScriptActive do
        local character = player.Character
        local head = character and character:FindFirstChild("Head")
        if head then
            local snapshot = workspace:FindFirstChild("CashDrops")
            if snapshot then
                local headPos = head.Position
                for _, v in ipairs_(snapshot:GetDescendants()) do
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
local homesick
do
    pcall_(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/sharedechoes/Matcha-Luas/refs/heads/main/homesick.lua"))()
        homesick = _G.homesick or shared.homesick
    end)
end
if homesick then
    pcall_(function() homesick.changelogEnabled = false end)
    local window = homesick.createWindow("sell lemons", 420, 400)
    UIRef.win = window
    local tab1 = window:addTab("automation")
    local left = tab1:addSection("automation", "Left")
    UIRef.t.AutoBuy = left:addToggle("autoBuy", "auto buy", false, function(val) autoBuyActive = val end):addKeybind("1", "Toggle", true)
    UIRef.t.LemonFarm = left:addToggle("lemonFarm", "lemon farm", false, function(val) lemonFarmActive = val end):addKeybind("2", "Toggle", true)
    UIRef.t.AutoStand = left:addToggle("autoStand", "auto stand", false, function(val) autoStandActive = val end):addKeybind("3", "Toggle", true)
    local right = tab1:addSection("other", "Right")
    UIRef.t.StopAll = right:addToggle("stopAll", "stop all", false, function(val)
        if val then
            autoBuyActive = false; lemonFarmActive = false; autoStandActive = false;
            tempBlacklist = {}; blacklistTime = {}
            pcall_(function() left:getToggle("autoBuy"):SetValue(false) end)
            pcall_(function() left:getToggle("lemonFarm"):SetValue(false) end)
            pcall_(function() left:getToggle("autoStand"):SetValue(false) end)
            task.delay(0.1, function() pcall_(function() right:getToggle("stopAll"):SetValue(false) end) end)
        end
    end):addKeybind("9", "Toggle", true)
    UIRef.t.BuyDecos = right:addToggle("buyDecos", "Buy Decos", false, function(val)
        buyDecosActive = val; tempBlacklist = {}; blacklistTime = {}
    end)
    window.visible = true
    window:render()
end
_wrap("autobuy-worker", function()
    while ScriptActive do
        if not autoBuyActive or _standIsTapping then task_wait(0.05); continue end
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        if not hrp or not myTycoon or not myTycoon.Parent then 
            myTycoon = findMyTycoon()
            task_wait(0.2); continue 
        end
        local buttons = getButtonsRealTime()
        local targetBtn = nil
        local targetDist = math.huge
        local hrpPos = hrp.Position
        local currentTime = tick_()
        for _, btn in ipairs_(buttons) do
            local key = getButtonKey(btn)
            if key then
                if tempBlacklist[key] and (currentTime - blacklistTime[key]) > 4 then tempBlacklist[key] = nil end
                if not tempBlacklist[key] and not isGreyedOut(btn) then
                    local dist = (btn.Position - hrpPos).Magnitude
                    if dist < targetDist then targetDist = dist; targetBtn = btn end
                end
            end
        end
        if targetBtn then
            _isBuying = true
            local key = getButtonKey(targetBtn)
            local pos = targetBtn.Position
            local px, py, pz = pos.X, pos.Y, pos.Z
            pcall_(function() hrp.CFrame = CF(px, py + 2.5, pz) end)
            task_wait(0.02)
            local bought = false
            local t0 = tick_()
            while ScriptActive and autoBuyActive and (tick_() - t0) < CFG.buyWindow do
                pcall_(function() hrp.CFrame = CF(px, py + 0.8, pz) end)
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
    for _, tycoon in ipairs_(workspace:GetChildren()) do
        if tycoon.Name:find("Tycoon") then
            local constant = tycoon:FindFirstChild("Constant")
            if constant then
                local trees = constant:FindFirstChild("Trees")
                if trees then
                    for _, tree in ipairs_(trees:GetChildren()) do
                        for _, fruit in ipairs_(tree:GetChildren()) do
                            if fruit.Name == "Fruit" then
                                local cp = fruit:FindFirstChild("ClickPart")
                                if cp and cp:IsA("BasePart") then tinsert(temp, cp) end
                            end
                        end
                    end
                end
            end
        end
    end
    for _, obj in ipairs_(workspace:GetChildren()) do
        if obj.Name == "LemonTree" then
            for _, fruit in ipairs_(obj:GetChildren()) do
                if fruit.Name == "Fruit" then
                    local cp = fruit:FindFirstChild("ClickPart")
                    if cp and cp:IsA("BasePart") then tinsert(temp, cp) end
                end
            end
        end
    end
    return temp
end
local LSM = { mode = nil, standBusyT = 0, lastBot = 0 }
local function lemonGone(v)
    return not (v and v.Parent and v:IsDescendantOf(workspace))
end
local function lsmSilent(v)
    local cd
    pcall_(function() cd = v:FindFirstChildOfClass("ClickDetector") end)
    if not cd then return false end
    if type(fireclickdetector) == "function" then
        local ok = pcall_(fireclickdetector, cd)
        if ok then
            task_wait(0.12)
            if lemonGone(v) then return true end
        end
    end
    if type(firesignal) == "function" then
        local ok = pcall_(function() firesignal(cd.MouseClick, player) end)
        if ok then
            task_wait(0.12)
            if lemonGone(v) then return true end
        end
    end
    return false
end
local function lsmTouch(v, hrp)
    if not hrp then return false end
    pcall_(function() hrp.CFrame = CF(v.Position.X, v.Position.Y, v.Position.Z) end)
    task_wait(0.12)
    if lemonGone(v) then return true end
    return false
end
local function lsmZoom(dir)
    if LSM.mode == "cd" or LSM.mode == "sig" then return end
    if type(mousescroll) == "function" then
        for _ = 1, CFG.zoomTicks do pcall_(mousescroll, CFG.zoomStep * dir); task_wait(0.02) end
    end
end
local LEMON_HITBOX_SIZE = Vec3(50, 50, 50)
local function processLemon(v, hrp)
    if not lemonFarmActive then return false end
    if not v or not v:IsDescendantOf(workspace) then return false end
    if not _windowFocused() then return false end
    if autoStandActive and (tick_() - (LSM.standBusyT or 0)) < 4 then return false end
    if lsmSilent(v) then return true end
    if lsmTouch(v, hrp) then return true end
    local origSize = v.Size
    pcall_(function() v.CanCollide = false; v.Transparency = 1; v.Size = LEMON_HITBOX_SIZE end)
    local vp = v.Position
    local tpX, tpY, tpZ = vp.X, vp.Y - 4, vp.Z
    pcall_(function()
        hrp.CFrame = CF(tpX, tpY, tpZ)
        task_wait(0.008)
        camera.CFrame = CFrame.lookAt(Vec3(tpX, tpY, tpZ), Vec3(vp.X, vp.Y + 10, vp.Z))
        task_wait(0.008)
        local vps = camera.ViewportSize
        if type(mousemoveabs) == "function" and type(mouse1click) == "function" then
            mousemoveabs(mfloor(vps.X / 2), mfloor(vps.Y / 2))
            mouse1click()
            task_wait(0.005); mouse1click()
        end
    end)
    local collected = lemonGone(v)
    if not collected then pcall_(function() v.Size = origSize end) end
    return collected
end
_wrap("lemon-farm", function()
    local lemonFailCount = {}
    while ScriptActive do
        if not lemonFarmActive then
            if _lemonZoomedIn then lsmZoom(-1); _lemonZoomedIn = false end
            task_wait(0.1)
            continue
        end
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local buyBusy = _isBuying
        local standBusy = autoStandActive and (tick_() - (LSM.standBusyT or 0)) < 4
        if hrp and not buyBusy and not standBusy then
            if not _lemonZoomedIn then lsmZoom(1); _lemonZoomedIn = true end
            local snapshot = getLemonsFast()
            for _, cp in ipairs_(snapshot) do
                if not lemonFarmActive or _isBuying or (autoStandActive and (tick_() - (LSM.standBusyT or 0)) < 4) then break end
                local key = getButtonKey(cp) or tostring_(math.random(1, 99999))
                local fails = lemonFailCount[key] or 0
                if fails < 3 then
                    local ok = processLemon(cp, hrp)
                    if ok then lemonFailCount[key] = nil else lemonFailCount[key] = fails + 1 end
                end
            end
        end
        task_wait(0.1)
    end
end)
local STAND_E_DURATION = 1.5
local STAND_E_INTERVAL = 0.015
local STAND_LOOP_DELAY = 0.1
_wrap("auto-stand", function()
    while ScriptActive do
        if not autoStandActive then task_wait(0.25); continue end
        if not myTycoon or not myTycoon.Parent then
            myTycoon = findMyTycoon()
            task_wait(0.5); continue
        end
        if autoBuyActive and _anyLiveButtons() then task_wait(0.3); continue end
        local purchases; pcall_(function() purchases = myTycoon:FindFirstChild("Purchases") end)
        if purchases then
            for _, f in ipairs_(purchases:GetChildren()) do
                if not autoStandActive then break end
                if f.Name:lower():find("lemon") then
                    local pos
                    for _, d in ipairs_(f:GetDescendants()) do
                        if d:IsA("BasePart") then pos = d.Position; break end
                    end
                    if pos then
                        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
                        if hrp then
                            LSM.standBusyT = tick_()
                            _standIsTapping = true
                            pcall_(function() hrp.CFrame = CF(pos.X, pos.Y + 3, pos.Z) end)
                            task_wait(0.1)
                            local t0 = tick_()
                            while autoStandActive and (tick_() - t0) < STAND_E_DURATION do
                                if type(keypress) == "function" then
                                    pcall_(function()
                                        keypress(0x45)
                                        task_wait(STAND_E_INTERVAL)
                                        keyrelease(0x45)
                                    end)
                                else
                                    pcall_(function()
                                        local vim = game:GetService("VirtualInputManager")
                                        vim:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                                        task_wait(STAND_E_INTERVAL)
                                        vim:SendKeyEvent(false, Enum.KeyCode.E, false, game)
                                    end)
                                end
                            end
                            _standIsTapping = false
                        end
                    end
                end
            end
        end
        task_wait(CFG.standRest)
    end
end)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Q then
        if UIRef.win then
            UIRef.win.visible = not UIRef.win.visible
            pcall_(function() UIRef.win:render() end)
        end
    end
end)
local rsConn = RunService.RenderStepped:Connect(function()
    if not ScriptActive then return end
    if lemonFarmActive and LSM.mode ~= "cd" and LSM.mode ~= "sig" then
        local chr = player.Character
        local hrp = chr and chr:FindFirstChild("HumanoidRootPart")
        if hrp then pcall_(function() hrp.AssemblyLinearVelocity = Vec3(0, 2, 0) end) end
    end
    local focused = _windowFocused()
    local nowA = tick_()
    if focused then
        local mx, my = S.pmx, S.pmy
        if mouse then pcall_(function() mx = mouse.X; my = mouse.Y end) end
        local m1 = false; pcall_(function() m1 = ismouse1pressed() end)
        if (nowA - LSM.lastBot) > 0.35 then
            if mx ~= S.pmx or my ~= S.pmy or m1 then end
        end
        S.pmx, S.pmy = mx, my
    end
    _lemonWasActive = lemonFarmActive
end)
_G.MatchaCleanup = function()
    ScriptActive = false
    _G.SellLemonsActive = false
    pcall_(function() rsConn:Disconnect() end)
    pcall_(function() if UIRef.win then UIRef.win.visible = false end end)
end
