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
local Players, RunService, player, camera
local initAttempts = 0
while not player and initAttempts < 50 do
    initAttempts = initAttempts + 1
    pcall_(function()
        Players = game:GetService("Players")
        RunService = game:GetService("RunService")
        player = Players.LocalPlayer
        if player then camera = workspace.CurrentCamera end
    end)
    if not player then task_wait(0.1) end
end
if not player then return end
if not camera then camera = workspace.CurrentCamera end
local playerGui = player:WaitForChild("PlayerGui")
local UserInputService = game:GetService("UserInputService")
pcall_(function() setrobloxinput(true) end)

pcall_(function()
    local VirtualUser = game:GetService("VirtualUser")
    player.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

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
local _lemonWasActive = false
local myTycoon = nil
local UIRef = { win = nil, t = {} }
local S = { pmx = 0, pmy = 0, keyDown = {}, lastFire = {} }
local function UXfire(id)
    local now = tick_()
    if S.lastFire[id] and (now - S.lastFire[id]) < 0.30 then return false end
    S.lastFire[id] = now
    return true
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
local function resetBuyBlacklist()
    tempBlacklist = {}
    blacklistTime = {}
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
local lemonTrees = {}
local lemonTreeSet = {}
local lemonTreeCacheReady = false
local function _removeTree(tree)
    if not lemonTreeSet[tree] then return end
    lemonTreeSet[tree] = nil
    for i = #lemonTrees, 1, -1 do
        if lemonTrees[i] == tree then table.remove(lemonTrees, i); break end
    end
end
local function addLemonTree(tree)
    if not tree or lemonTreeSet[tree] then return end
    lemonTreeSet[tree] = true
    tinsert(lemonTrees, tree)
    pcall_(function()
        tree.AncestryChanged:Connect(function(_, parent)
            if not parent then _removeTree(tree) end
        end)
    end)
end
local function hookTreesFolder(treesFolder)
    if not treesFolder then return end
    for _, t in ipairs_(treesFolder:GetChildren()) do addLemonTree(t) end
    pcall_(function()
        treesFolder.ChildAdded:Connect(function(newTree) addLemonTree(newTree) end)
    end)
end
local function hookTycoonForTrees(tycoon)
    if not tycoon or not tycoon.Name then return end
    if not tycoon.Name:find("Tycoon") then return end
    local constant = tycoon:FindFirstChild("Constant")
    if constant then
        local trees = constant:FindFirstChild("Trees")
        if trees then hookTreesFolder(trees) end
        pcall_(function()
            constant.ChildAdded:Connect(function(child)
                if child.Name == "Trees" then hookTreesFolder(child) end
            end)
        end)
    end
    pcall_(function()
        tycoon.ChildAdded:Connect(function(child)
            if child.Name == "Constant" then
                local trees = child:FindFirstChild("Trees")
                if trees then hookTreesFolder(trees) end
                pcall_(function()
                    child.ChildAdded:Connect(function(c2)
                        if c2.Name == "Trees" then hookTreesFolder(c2) end
                    end)
                end)
            end
        end)
    end)
end
local function buildLemonTreeCache()
    lemonTrees, lemonTreeSet = {}, {}
    local rootLT = workspace:FindFirstChild("LemonTree")
    if rootLT then addLemonTree(rootLT) end
    pcall_(function()
        workspace.ChildAdded:Connect(function(child)
            if child.Name == "LemonTree" then addLemonTree(child)
            elseif child.Name and child.Name:find("Tycoon") then hookTycoonForTrees(child) end
        end)
    end)
    for _, tycoon in ipairs_(workspace:GetChildren()) do hookTycoonForTrees(tycoon) end
    lemonTreeCacheReady = true
end
buildLemonTreeCache()
local LEMON_MAX_FRUIT_HEIGHT = 14
local function getLemonsFast()
    if not lemonTreeCacheReady then buildLemonTreeCache() end
    local temp = {}
    for ti = 1, #lemonTrees do
        local tree = lemonTrees[ti]
        if tree and tree.Parent then
            for _, fruit in ipairs_(tree:GetChildren()) do
                if fruit.Name == "Fruit" then
                    local cp = fruit:FindFirstChild("ClickPart")
                    if cp and cp:IsA("BasePart") then
                        tinsert(temp, cp)
                    end
                end
            end
        end
    end
    return temp
end
local function getCashDropsFast()
    local folder = workspace:FindFirstChild("CashDrops")
    if not folder then return {} end
    local temp = {}
    for _, v in ipairs_(folder:GetDescendants()) do
        if v.Name == "TouchInterest" and v.Parent and v.Parent:IsA("BasePart") then
            tinsert(temp, v.Parent)
        end
    end
    return temp
end
local LSM = { mode = nil, standBusyT = 0, lastBot = 0 }
local function lemonGone(v)
    return not (v and v.Parent and v:IsDescendantOf(workspace))
end
local function findClickDetector(v)
    local cd
    pcall_(function() cd = v:FindFirstChildOfClass("ClickDetector") end)
    if cd then return cd end
    pcall_(function()
        local par = v.Parent
        if par then
            cd = par:FindFirstChildOfClass("ClickDetector")
            if not cd then
                for _, d in ipairs_(par:GetDescendants()) do
                    if d:IsA("ClickDetector") then cd = d; break end
                end
            end
        end
    end)
    return cd
end
local function lsmSilent(v)
    local cd = findClickDetector(v)
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
    local vp = v.Position
    pcall_(function() hrp.CFrame = CF(vp.X, vp.Y, vp.Z) end)
    task_wait(0.12)
    if lemonGone(v) then return true end
    return false
end
local function lsmZoom(dir)
    if type(mousescroll) == "function" then
        for _ = 1, CFG.zoomTicks do pcall_(mousescroll, CFG.zoomStep * dir); task_wait(0.02) end
    end
end
local function disableTreeCanQuery(tree, excludeSet)
    local modified, n = {}, 0
    for _, part in ipairs_(tree:GetDescendants()) do
        if part:IsA("BasePart") and not excludeSet[part] then
            pcall_(function()
                if part.CanQuery then
                    part.CanQuery = false
                    n = n + 1
                    modified[n] = part
                end
            end)
        end
    end
    return modified, n
end
local function restoreTreeCanQuery(modified, n)
    for i = 1, n do pcall_(function() modified[i].CanQuery = true end) end
end
local function findTreeOf(clickPart)
    local n = clickPart.Parent
    if n then return n.Parent end
    return nil
end
local LEMON_HITBOX_SIZE = Vec3(50, 50, 50)
local LEMON_TP_WAIT = 0.008
local LEMON_CAM_WAIT = 0.008
local LEMON_CLICK_GAP = 0.005
local LEMON_POST_WAIT = 0
local LEMON_DOUBLE_CLICK = true
local lemonFailCount = {}
local LEMON_MAX_FAILS = 3
local function lemonKey(v)
    local pos = v.Position
    return mfloor(pos.X+0.5)..","..mfloor(pos.Y+0.5)..","..mfloor(pos.Z+0.5)
end
local function processLemon(v, hrp)
    if not v or not v:IsDescendantOf(workspace) then return false end
    if autoStandActive and (tick_() - LSM.standBusyT) < 4 then return false end
    if lsmSilent(v) then return true end
    if lsmTouch(v, hrp) then return true end
    local origSize = v.Size
    pcall_(function() v.CanCollide = false; v.Transparency = 1; v.Size = LEMON_HITBOX_SIZE end)
    local vp = v.Position
    local tpX, tpY, tpZ = vp.X, vp.Y - 4, vp.Z
    LSM.lastBot = tick_()
    pcall_(function()
        hrp.CFrame = CF(tpX, tpY, tpZ)
        task_wait(LEMON_TP_WAIT)
        camera.CFrame = CFrame.lookAt(Vec3(tpX, tpY, tpZ), Vec3(vp.X, vp.Y + 10, vp.Z))
        task_wait(LEMON_CAM_WAIT)
        local vps = camera.ViewportSize
        if type(mousemoveabs) == "function" and type(mouse1click) == "function" then
            mousemoveabs(mfloor(vps.X / 2), mfloor(vps.Y / 2))
            mouse1click()
            task_wait(LEMON_CLICK_GAP)
            mouse1click()
        end
    end)
    local collected = lemonGone(v)
    if not collected then pcall_(function() v.Size = origSize end) end
    if LEMON_POST_WAIT > 0 then task_wait(LEMON_POST_WAIT) end
    return collected
end
local function processSnapshot(snapshot, hrp)
    local groups, groupOrder = {}, {}
    for i = 1, #snapshot do
        local v = snapshot[i]
        if v and v.Parent and v:IsDescendantOf(workspace) then
            local tree = findTreeOf(v)
            local key = (tree and tree.Parent and tree) or v.Parent
            if key then
                local g = groups[key]
                if not g then g = {}; groups[key] = g; tinsert(groupOrder, key) end
                tinsert(g, v)
            end
        end
    end
    local collectedCount = 0
    for _, tree in ipairs_(groupOrder) do
        if not lemonFarmActive then break end
        if _isBuying then break end
        if autoStandActive and (tick_() - LSM.standBusyT) < 4 then break end
        local fruits = groups[tree]
        local excludeSet = {}
        for i = 1, #fruits do excludeSet[fruits[i]] = true end
        local modified, modN = {}, 0
        modified, modN = disableTreeCanQuery(tree, excludeSet)
        for i = 1, #fruits do
            if not lemonFarmActive then break end
            local v = fruits[i]
            if v and v:IsDescendantOf(workspace) then
                local lk = lemonKey(v)
                local fails = lemonFailCount[lk] or 0
                if fails < LEMON_MAX_FAILS then
                    local ok = processLemon(v, hrp)
                    if ok then lemonFailCount[lk] = nil; collectedCount = collectedCount + 1
                    else lemonFailCount[lk] = fails + 1 end
                end
            end
        end
        if modN > 0 then restoreTreeCanQuery(modified, modN) end
    end
    return collectedCount
end
_wrap("cash-farm", function()
    while ScriptActive do
        local character = player.Character
        local head = character and character:FindFirstChild("Head")
        if head then
            local snapshot = getCashDropsFast()
            local headPos = head.Position
            for i = 1, #snapshot do
                local p = snapshot[i]
                if p and p.Parent then pcall_(function() p.Position = headPos end) end
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
        local result = loadstring(game:HttpGet("https://raw.githubusercontent.com/sharedechoes/Matcha-Luas/refs/heads/main/homesick.lua"))()
        homesick = _G.homesick or shared.homesick or result
    end)
end
if homesick then
    pcall_(function() homesick.changelogEnabled = false end)
    local window = homesick.createWindow("sell lemons", 420, 400)
    UIRef.win = window
    local tab1 = window:addTab("automation")
    local left = tab1:addSection("automation", "Left")
    UIRef.t.AutoBuy = left:addToggle("autoBuy", "auto buy", false, function(val)
        task_spawn(function() autoBuyActive = val end)
    end):addKeybind("1", "Toggle", true)
    UIRef.t.LemonFarm = left:addToggle("lemonFarm", "lemon farm", false, function(val)
        task_spawn(function()
            lemonFarmActive = val
            if not val then lsmZoom(-1) end
        end)
    end):addKeybind("2", "Toggle", true)
    UIRef.t.AutoStand = left:addToggle("autoStand", "auto stand", false, function(val)
        task_spawn(function() autoStandActive = val end)
    end):addKeybind("3", "Toggle", true)
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
_wrap("lemon-farm", function()
    local LEMON_MAX_PASSES = 6
    local LEMON_VERIFY_WAIT = 0.15
    local LEMON_VERIFY_PASSES = 3
    local LEMON_PASS_WAIT = 0.04
    while ScriptActive do
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")
        local buyBusy = _isBuying
        local standBusy = autoStandActive and (tick_() - LSM.standBusyT) < 4
        if not lemonFarmActive and _lemonZoomedIn then
            lsmZoom(-1)
            _lemonZoomedIn = false
        end
        if lemonFarmActive and hrp and not buyBusy and not standBusy then
            if not _lemonZoomedIn then
                lsmZoom(1)
                _lemonZoomedIn = true
            end
            local pass, lastSeen, sameStreak = 0, -1, 0
            while ScriptActive and lemonFarmActive and pass < LEMON_MAX_PASSES do
                pass = pass + 1
                local snapshot = getLemonsFast()
                local count = #snapshot
                if count == 0 then break end
                if count == lastSeen then sameStreak = sameStreak + 1; if sameStreak >= 2 then break end
                else sameStreak = 0; lastSeen = count end
                local chr2 = player.Character
                hrp = chr2 and chr2:FindFirstChild("HumanoidRootPart")
                if not hrp then break end
                processSnapshot(snapshot, hrp)
                task_wait(LEMON_PASS_WAIT)
            end
            if lemonFarmActive then
                for _ = 1, LEMON_VERIFY_PASSES do
                    if not lemonFarmActive then break end
                    task_wait(LEMON_VERIFY_WAIT)
                    local chr3 = player.Character
                    local hrp3 = chr3 and chr3:FindFirstChild("HumanoidRootPart")
                    if not hrp3 then break end
                    local snap = getLemonsFast()
                    if #snap == 0 then break end
                    if processSnapshot(snap, hrp3) == 0 then break end
                end
            end
            task_wait(0.1)
        else
            task_wait(0.05)
        end
    end
end)
local STAND_E_DURATION = 1.5
local STAND_E_INTERVAL = 0.015
local STAND_LOOP_DELAY = 0.1
_wrap("auto-stand", function()
    local firstRun = true
    while ScriptActive do
        if not autoStandActive then firstRun = true; task_wait(0.25); continue end
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
_G.MatchaCleanup = function()
    ScriptActive = false
    _G.SellLemonsActive = false
    pcall_(function() if UIRef.win then UIRef.win.visible = false end end)
end
