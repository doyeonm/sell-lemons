-- [[ Sell Lemons Ultimate - External UI + Q Toggle + Auto Cash ]] --
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

-- ==================== DEBUG / LOGGING ====================
local DEBUG  = false
local rprint = print
local print  = function(...) if DEBUG then rprint(...) end end

-- ==================== ERROR RECOVERY WRAPPER ====================
local errCounts = {}
local function reportErr(tag, err)
    local msg = "[" .. tag .. "] " .. tostring_(err)
    local n = (errCounts[msg] or 0) + 1
    errCounts[msg] = n
    if n <= 3 or n % 50 == 0 then
        rprint("[SellLemons][ERROR] " .. msg .. (n > 1 and ("  (x"..n..")") or ""))
    end
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

-- ==================== CONFIG ====================
local CFG = {
    standRest = 60,
    zoomTicks = 16,
    zoomStep  = 1,
    buyWindow = 0.45,
}

-- ==================== STATE ====================
local autoBuyActive   = false
local buyDecosActive  = false 
local lemonFarmActive = false
local autoStandActive = false
local _standIsTapping = false

local _lemonZoomedIn  = false
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

-- ==================== WINDOW FOCUS GUARD ====================
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
    print("[SellLemons] Blacklist reset")
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
    local bl = buyBlacklist[key]
    if not bl then return false end
    if v and bl ~= true and bl ~= v then
        buyBlacklist[key] = nil
        return false
    end
    return true
end

local function anyGivenUpButtons(buttons)
    for _, v in ipairs_(buttons) do
        local key = getButtonKey(v)
        if key then
            local a = buyAttempt[key]
            if a and a.inst and a.inst ~= v then buyAttempt[key] = nil
            elseif a and a.n >= 6 and not isBlacklisted(key, v) then return true end
        end
    end
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

-- [FIXED] 데코레이션 다이내믹 필터
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
    for _, v in ipairs_(buttons) do
        local key = getButtonKey(v)
        if key then
            local a = buyAttempt[key]
            if a and a.inst and a.inst ~= v then buyAttempt[key] = nil; a = nil end
            if not isBlacklisted(key, v) and not isGreyedOut(v) and not (a and a.n >= 6) then
                return true
            end
        end
    end
    return false
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

-- ==================== LEMON TREE CACHE ====================
local lemonTrees          = {}
local lemonTreeSet        = {}
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
                    if cp and cp:IsA("BasePart") and cp.Position.Y <= LEMON_MAX_FRUIT_HEIGHT then
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

-- ==================== LEMON SILENT MODE CASCADE ====================
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
    if (LSM.mode == nil or LSM.mode == "cd") and type(fireclickdetector) == "function" then
        local ok = pcall_(fireclickdetector, cd)
        if ok then
            task_wait(0.12)
            if lemonGone(v) then
                if LSM.mode == nil then LSM.mode = "cd"; rprint("[Lemon] mode: fireclickdetector") end
                return true
            end
        end
    end
    if (LSM.mode == nil or LSM.mode == "sig") and type(firesignal) == "function" then
        local ok = pcall_(function() firesignal(cd.MouseClick, player) end)
        if ok then
            task_wait(0.12)
            if lemonGone(v) then
                if LSM.mode == nil then LSM.mode = "sig"; rprint("[Lemon] mode: firesignal") end
                return true
            end
        end
    end
    return false
end

local function lsmTouch(v, hrp)
    if not hrp then return false end
    local vp = v.Position
    pcall_(function() hrp.CFrame = CF(vp.X, vp.Y, vp.Z) end)
    task_wait(0.12)
    if lemonGone(v) then
        if LSM.mode == nil then LSM.mode = "touch"; rprint("[Lemon] mode: touch TP") end
        return true
    end
    return false
end

local function lsmZoom(dir)
    if LSM.mode == "cd" or LSM.mode == "sig" then return end
    if type(mousescroll) == "function" then
        for _ = 1, CFG.zoomTicks do
            pcall_(mousescroll, CFG.zoomStep * dir)
            task_wait(0.02)
        end
    end
end

-- ==================== LEMON TREE CANQUERY HELPERS ====================
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

-- ==================== LEMON COLLECT ====================
local LEMON_HITBOX_SIZE  = Vec3(50, 50, 50)
local LEMON_TP_WAIT      = 0.008
local LEMON_CAM_WAIT     = 0.008
local LEMON_CLICK_GAP    = 0.005
local LEMON_POST_WAIT    = 0
local LEMON_DOUBLE_CLICK = true
local lemonFailCount     = {}
local LEMON_MAX_FAILS    = 3

local function lemonKey(v)
    local pos = v.Position
    return mfloor(pos.X+0.5)..","..mfloor(pos.Y+0.5)..","..mfloor(pos.Z+0.5)
end

local function processLemon(v, hrp)
    if not v or not v:IsDescendantOf(workspace) then return false end

    if not _windowFocused() then return false end
    if autoStandActive and (tick_() - LSM.standBusyT) < 4 then return false end

    if LSM.mode ~= "classic" then
        if lsmSilent(v) then return true end
        if LSM.mode == "cd" or LSM.mode == "sig" then return false end
        if lsmTouch(v, hrp) then return true end
        if LSM.mode == "touch" then return false end
        if LSM.mode == nil then
            LSM.mode = "classic"
            rprint("[Lemon] mode: classic (TP+camera+click)")
        end
    end

    local origSize, origTransp, origCanColl
    pcall_(function()
        origSize    = v.Size
        origTransp  = v.Transparency
        origCanColl = v.CanCollide
        v.CanCollide   = false
        v.Transparency = 1
        v.Size         = LEMON_HITBOX_SIZE
    end)

    local vp = v.Position
    local tpX, tpY, tpZ = vp.X, vp.Y - 4, vp.Z

    LSM.lastBot = tick_()
    pcall_(function()
        hrp.CFrame = CF(tpX, tpY, tpZ)
        task_wait(LEMON_TP_WAIT)
        camera.CFrame = CFrame.lookAt(Vec3(tpX, tpY, tpZ), Vec3(vp.X, vp.Y + 10, vp.Z))
        task_wait(LEMON_CAM_WAIT)
        local vps = camera.ViewportSize
        mousemoveabs(mfloor(vps.X / 2), mfloor(vps.Y / 2))
        mouse1click()
        if LEMON_DOUBLE_CLICK then task_wait(LEMON_CLICK_GAP); mouse1click() end
    end)

    local collected = lemonGone(v)

    if not collected then
        pcall_(function()
            if origSize    ~= nil then v.Size         = origSize    end
            if origTransp  ~= nil then v.Transparency = origTransp  end
            if origCanColl ~= nil then v.CanCollide   = origCanColl end
        end)
    end

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
        if autoBuyActive and (#localQueue - queueIndex + 1) > 0 then break end
        if autoStandActive and (tick_() - LSM.standBusyT) < 4 then break end

        local fruits = groups[tree]
        local excludeSet = {}
        for i = 1, #fruits do excludeSet[fruits[i]] = true end

        local modified, modN = {}, 0
        if tree and LSM.mode ~= "cd" and LSM.mode ~= "sig" then
            modified, modN = disableTreeCanQuery(tree, excludeSet)
        end

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

-- ==================== AUTO STAND / AUTO UPGRADE ====================
local STAND_KEY            = 0x45
local STAND_E_DURATION     = 1.5
local STAND_E_INTERVAL     = 0.015
local STAND_CYCLE_PAUSE    = 0.02
local STAND_TP_Y_OFFSET    = 3
local STAND_LOOP_DELAY     = 0.1
local STAND_FOLDER_PREFIX  = "Lemon"
local STAND_MANAGE_PATH    = {"Manage", "ManageMenu", "Body", "Frame", "Manage"}
local STAND_BLANK_PREFIX   = "Blank"
local STAND_CACHE_TTL      = 5.0

local standCache          = {}
local _standInactiveSince = {}
local STAND_INACTIVE_RETEST = 8

local GUI_BG_COLOR_OFFSET   = 0x540
local STAND_INACTIVE_RGB    = {0.49, 0.49, 0.49}
local STAND_COLOR_TOLERANCE = 0.06

local function _shouldSkipInactive(name)
    local t = _standInactiveSince[name]
    if not t then return false end
    if (tick_() - t) > STAND_INACTIVE_RETEST then _standInactiveSince[name] = nil; return false end
    return true
end
local function _markInactive(name) _standInactiveSince[name] = tick_() end
local function _markActive(name)   _standInactiveSince[name] = nil end

local function _isUpgradeActive(upg)
    if not upg then return nil end
    local addr; pcall_(function() addr = tonumber_(upg.Address) end)
    if not addr or addr <= 4096 then return nil end
    if type(memory_read) ~= "function" then return nil end
    local okR, r = pcall_(memory_read, "float", addr + GUI_BG_COLOR_OFFSET)
    local okG, g = pcall_(memory_read, "float", addr + GUI_BG_COLOR_OFFSET + 4)
    local okB, b = pcall_(memory_read, "float", addr + GUI_BG_COLOR_OFFSET + 8)
    if not okR or not okG or not okB then return nil end
    if type(r) ~= "number" or type(g) ~= "number" or type(b) ~= "number" then return nil end
    if r < -0.01 or r > 1.01 or g < -0.01 or g > 1.01 or b < -0.01 or b > 1.01 then return nil end
    local tol = STAND_COLOR_TOLERANCE
    local ir, ig, ib = STAND_INACTIVE_RGB[1], STAND_INACTIVE_RGB[2], STAND_INACTIVE_RGB[3]
    if mabs(r-ir) <= tol and mabs(g-ig) <= tol and mabs(b-ib) <= tol then return false, r, g, b end
    return true, r, g, b
end

local function _readUpgradeState(upgBtn)
    if not upgBtn then return "" end
    local parts = {}
    for _, childName in ipairs_({"Count", "Price", "Stack"}) do
        local c; pcall_(function() c = upgBtn:FindFirstChild(childName) end)
        tinsert(parts, c and tostring_(c.Text or "") or "")
    end
    return table.concat(parts, "|")
end

local function _isPlaceholderModel(model)
    if not model then return true end
    local ok, kids = pcall_(function() return model:GetChildren() end)
    if not ok or not kids or #kids == 0 then return true end
    if #kids > 1 then return false end
    local c = kids[1]
    if c:IsA("BasePart") then return c.Name == model.Name end
    if c:IsA("Model") then return _isPlaceholderModel(c) end
    return true
end

local function _findStandModel(folder)
    local ok, kids = pcall_(function() return folder:GetChildren() end)
    if kids then
        for _, c in ipairs_(kids) do
            if c:IsA("Model") and c.Name == folder.Name and not _isPlaceholderModel(c) then return c end
        end
        for _, c in ipairs_(kids) do
            if c:IsA("Model") and not _isPlaceholderModel(c) then return c end
        end
    end
    local ok2, desc = pcall_(function() return folder:GetDescendants() end)
    if desc then
        for _, d in ipairs_(desc) do
            if d:IsA("Model") and d.PrimaryPart and not _isPlaceholderModel(d) then return d end
        end
    end
    return nil
end

local function _modelPivotPos(model)
    if not model then return nil end
    local pp = model.PrimaryPart
    if pp then local ok, p = pcall_(function() return pp.Position end); if p then return p end end
    local ok, piv = pcall_(function() return model:GetPivot() end)
    if piv then local ok2, p = pcall_(function() return piv.Position end); if p then return p end end
    local ok2, desc = pcall_(function() return model:GetDescendants() end)
    if desc then
        for _, d in ipairs_(desc) do
            if d:IsA("BasePart") then local ok3, p = pcall_(function() return d.Position end); if p then return p end end
        end
    end
    return nil
end

local function _findScrollAncestor(obj)
    local cur = obj
    while cur and cur.Parent do
        cur = cur.Parent
        if cur:IsA("ScrollingFrame") then return cur end
        if cur:IsA("ScreenGui") then break end
    end
    return nil
end

local function _ensureVisibleInScroll(child)
    if not child or not child.Parent then return false end
    local sf = _findScrollAncestor(child)
    if not sf then return true end
    pcall_(function()
        local childY    = child.AbsolutePosition.Y
        local sfY       = sf.AbsolutePosition.Y
        local viewportH = sf.AbsoluteWindowSize.Y
        local childH    = child.AbsoluteSize.Y
        local relTop    = childY - sfY
        local relBot    = relTop + childH
        local cur       = sf.CanvasPosition
        if relTop < 0 then
            sf.CanvasPosition = Vec2(cur.X, math.max(0, cur.Y + relTop - 4))
        elseif relBot > viewportH then
            sf.CanvasPosition = Vec2(cur.X, cur.Y + (relBot - viewportH) + 4)
        end
    end)
    task_wait(); task_wait()
    return true
end

local function _tpHrpTo(pos)
    if autoStandActive then LSM.standBusyT = tick_() end
    local chr = player.Character
    local hrp = chr and chr:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    return pcall_(function() hrp.CFrame = CF(pos.X, pos.Y + STAND_TP_Y_OFFSET, pos.Z) end)
end

local function _spamE(durationSec)
    if not _windowFocused() then task_wait(0.2); return false end
    _standIsTapping = true
    local t0 = tick_()
    while autoStandActive and (tick_() - t0) < durationSec do
        if not _windowFocused() then break end
        keypress(STAND_KEY); task_wait(STAND_E_INTERVAL)
        keyrelease(STAND_KEY); task_wait(STAND_E_INTERVAL)
    end
    keyrelease(STAND_KEY)
    _standIsTapping = false
    return true
end

local function _getManageRoot()
    local pg; pcall_(function() pg = player:FindFirstChildOfClass("PlayerGui") end)
    if not pg then return nil end
    local node = pg
    for _, seg in ipairs_(STAND_MANAGE_PATH) do
        local nxt; pcall_(function() nxt = node:FindFirstChild(seg) end)
        if not nxt then return nil end
        node = nxt
    end
    return node
end

local _standPriceDiagShown = {}

local function _getManageStands()
    local out = {}
    local root = _getManageRoot()
    if not root then return out end
    local kids; pcall_(function() kids = root:GetChildren() end)
    if not kids then return out end
    for _, c in ipairs_(kids) do
        if c:IsA("Frame") then
            local nm = tostring_(c.Name)
            if nm:sub(1, #STAND_BLANK_PREFIX) ~= STAND_BLANK_PREFIX then
                local upg; pcall_(function() upg = c:FindFirstChild("Upgrade") end)
                if upg and upg:IsA("GuiButton") then
                    tinsert(out, {frame=c, upgrade=upg, name=nm})
                end
            end
        end
    end
    return out
end

local function _findPurchaseFolder(standName)
    if not myTycoon then return nil end
    local purchases; pcall_(function() purchases = myTycoon:FindFirstChild("Purchases") end)
    if not purchases then return nil end
    local f; pcall_(function() f = purchases:FindFirstChild(standName) end)
    if f then return f end
    local target = standName:gsub("%s+",""):lower()
    local kids; pcall_(function() kids = purchases:GetChildren() end)
    if not kids then return nil end
    for _, c in ipairs_(kids) do
        if tostring_(c.Name):gsub("%s+",""):lower() == target then return c end
    end
    return nil
end

local function runUpgradePass(verbose)
    local stands = _getManageStands()
    if #stands == 0 then
        if verbose then rprint("[AutoUpgrade] Manage menu empty — open it at least once.") end
        return "done"
    end
    if verbose then rprint(sformat("[AutoUpgrade] Pass start, %d stands", #stands)) end

    local tapped, skipped_color, skipped_cache, fallback_used = 0, 0, 0, 0
    local prefix = STAND_FOLDER_PREFIX:lower()

    for i, s in ipairs_(stands) do
        if not autoStandActive then return "off" end
        if prefix ~= "" and tostring_(s.name):lower():sub(1, #prefix) ~= prefix then continue end

        _ensureVisibleInScroll(s.frame)

        local active, cr, cg, cb = _isUpgradeActive(s.upgrade)
        if active == false then skipped_color = skipped_color + 1; task_wait(0.005); continue end

        local useFallback = (active == nil)
        if useFallback then
            fallback_used = fallback_used + 1
            if _shouldSkipInactive(s.name) then skipped_cache = skipped_cache + 1; task_wait(0.005); continue end
            if not _standPriceDiagShown[s.name] then
                _standPriceDiagShown[s.name] = true
                rprint("[AutoUpgrade][DIAG] memory_read unavailable for: " .. tostring_(s.name))
            end
        end

        local folder = _findPurchaseFolder(s.name)
        if not folder then task_wait(STAND_CYCLE_PAUSE); continue end

        local now = tick_()
        local cached = standCache[folder]
        local model, pos
        if cached and (now - cached.ts) < STAND_CACHE_TTL then
            model, pos = cached.model, cached.pos
        else
            model = _findStandModel(folder)
            pos   = model and _modelPivotPos(model) or nil
            standCache[folder] = {model=model, pos=pos, ts=now}
        end
        if not pos then task_wait(STAND_CYCLE_PAUSE); continue end

        local before = useFallback and _readUpgradeState(s.upgrade) or nil
        if not _tpHrpTo(pos) then task_wait(STAND_CYCLE_PAUSE); continue end

        task_wait(0.05)
        _spamE(STAND_E_DURATION)
        tapped = tapped + 1

        if useFallback then
            local after = _readUpgradeState(s.upgrade)
            if before == after then _markInactive(s.name) else _markActive(s.name) end
        end
        task_wait(STAND_CYCLE_PAUSE)
    end

    if verbose then
        rprint(sformat("[AutoUpgrade] Pass end. tapped=%d skip_color=%d skip_cache=%d fallback=%d",
            tapped, skipped_color, skipped_cache, fallback_used))
    end
    return "done"
end

local function runUpgradePassTP(verbose)
    if not myTycoon then return "done" end
    local purchases; pcall_(function() purchases = myTycoon:FindFirstChild("Purchases") end)
    if not purchases then return "done" end
    local kids; pcall_(function() kids = purchases:GetChildren() end)
    if not kids or #kids == 0 then return "done" end
    local prefix = STAND_FOLDER_PREFIX:lower()
    local tapped = 0
    for _, folder in ipairs_(kids) do
        if not autoStandActive then return "off" end
        local nm = tostring_(folder.Name)
        if prefix ~= "" and nm:lower():sub(1, #prefix) ~= prefix then continue end
        local now = tick_()
        local cached = standCache[folder]
        local model, pos
        if cached and (now - cached.ts) < STAND_CACHE_TTL then
            model, pos = cached.model, cached.pos
        else
            model = _findStandModel(folder)
            pos   = model and _modelPivotPos(model) or nil
            standCache[folder] = {model=model, pos=pos, ts=now}
        end
        if pos and _tpHrpTo(pos) then
            task_wait(0.05); _spamE(STAND_E_DURATION); tapped = tapped + 1
        end
        task_wait(STAND_CYCLE_PAUSE)
    end
    if verbose then rprint(sformat("[AutoUpgrade] TP-pass end. tapped=%d", tapped)) end
    return "done"
end

-- ==================== AUTO BUY QUEUE ====================
local localQueue    = {}
local queueIndex    = 1
local totalBought   = 0
local totalFailed   = 0
local lastResetTime = 0
local emptyStreak   = 0

local function appendNewButtons()
    if not myTycoon or not myTycoon.Parent then return 0 end

    local buttons = getButtonsRealTime()
    local existingKeys = {}
    for i = queueIndex, #localQueue do
        local it = localQueue[i]
        if it and it.key then existingKeys[it.key] = true end
    end

    local chr = player.Character
    local hrp = chr and chr:FindFirstChild("HumanoidRootPart")
    local hrpPos = hrp and hrp.Position or nil
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

local function cleanupQueue()
    if queueIndex > 20 then
        local newQueue, n = {}, 0
        for i = queueIndex, #localQueue do n = n + 1; newQueue[n] = localQueue[i] end
        localQueue = newQueue; queueIndex = 1
    end
end

-- ==================== AUTO CASH FARM (항시 적용) ====================
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

-- ==================== LOAD EXTERNAL UI ====================
local homesick
do
    local ok, err = pcall_(function()
        loadstring(game:HttpGet("https://raw.githubusercontent.com/sharedechoes/Matcha-Luas/refs/heads/main/homesick.lua"))()
    end)
    homesick = _G.homesick or shared.homesick
    if not homesick then rprint("[SellLemons] homesick failed to load: " .. tostring_(err)) end
end

if homesick then
    pcall_(function() homesick.changelogEnabled = false end)
    local window = homesick.createWindow("sell lemons", 420, 400)
    
    -- [요청 사항 적용] 설정 탭 내부에 지저분하게 뜨던 테마/저장 기능 싹 다 삭제
    -- pcall_(function() window:autoloadConfig("selllemons_config") end)
    -- pcall_(function() window:autoloadTheme("theme") end)
    
    UIRef.win = window

    local tab1 = window:addTab("automation")
    local left = tab1:addSection("automation", "Left")

    UIRef.t.AutoBuy = left:addToggle("autoBuy", "auto buy", false, function(val)
        task_spawn(function()
            autoBuyActive = val
        end)
    end):addKeybind("1", "Toggle", true)

    UIRef.t.LemonFarm = left:addToggle("lemonFarm", "lemon farm", false, function(val)
        task_spawn(function()
            lemonFarmActive = val
            if not val then lsmZoom(-1) end
        end)
    end):addKeybind("2", "Toggle", true)

    UIRef.t.AutoStand = left:addToggle("autoStand", "auto stand", false, function(val)
        task_spawn(function()
            autoStandActive = val
        end)
    end):addKeybind("3", "Toggle", true)

    local right = tab1:addSection("other", "Right")

    UIRef.t.StopAll = right:addToggle("stopAll", "stop all", false, function(val)
        task_spawn(function()
            if val then
                autoBuyActive = false; lemonFarmActive = false
                autoStandActive = false;
                resetBuyBlacklist()
                lsmZoom(-1)
                pcall_(function() UIRef.t.AutoBuy:SetValue(false)   end)
                pcall_(function() UIRef.t.BuyDecos:SetValue(false)  end)
                pcall_(function() UIRef.t.LemonFarm:SetValue(false) end)
                pcall_(function() UIRef.t.AutoStand:SetValue(false) end)
                task.delay(0.1, function()
                    pcall_(function() UIRef.t.StopAll:SetValue(false) end)
                end)
            end
        end)
    end):addKeybind("9", "Toggle", true)

    UIRef.t.BuyDecos = right:addToggle("buyDecos", "Buy Decos", false, function(val)
        task_spawn(function()
            buyDecosActive = val
            resetBuyBlacklist()
            localQueue = {}
            queueIndex = 1
        end)
    end)

    window.visible = true
    window:render()
    rprint("[SellLemons] UI loaded successfully")
end

-- ==================== AUTO BUY WORKER ====================
_wrap("autobuy-worker", function()
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
                        allDead = false
                        break
                    end
                end
            end

            if allDead then
                if anyGivenUpButtons(buttons) then
                    local now = tick_()
                    if now - lastResetTime > 2 then
                        lastResetTime = now
                        resetBuyBlacklist()
                        localQueue = {}; queueIndex = 1
                        appendNewButtons()
                    end
                else
                    task_wait(0.3)
                end
            else
                emptyStreak = emptyStreak + 1
                if emptyStreak > 10 then
                    emptyStreak = 0
                    appendNewButtons()
                end
            end
            task_wait(0.05); continue
        end

        if not autoBuyActive then continue end

        emptyStreak = 0

        local key = item.key
        local btn = item.btn
        local pos = btn.Position
        local px, py, pz = pos.X, pos.Y, pos.Z

        pcall_(function() hrp.CFrame = CF(px, py + 2.5, pz) end)
        task_wait(0.02)

        local bought = false
        local t0 = tick_()
        
        while ScriptActive and autoBuyActive and (tick_() - t0) < CFG.buyWindow do
            pcall_(function() hrp.CFrame = CF(px, py + 0.8, pz) end)
            task_wait(0.03)
            local gone = true
            pcall_(function() gone = not (btn and btn.Parent and btn:IsDescendantOf(myTycoon)) end)
            if gone then bought = true; break end
            if isGreyedOut(btn) then break end
        end

        if bought then
            buyBlacklist[key] = btn
            failedButtons[key] = nil
            buyAttempt[key] = nil
            totalBought = totalBought + 1
            print("[AutoBuy] BOUGHT: "..key.." | Total: "..totalBought)
        elseif autoBuyActive then
            markBuyFail(key, btn)
            totalFailed = totalFailed + 1
        end

        if totalBought % 20 == 0 then cleanupQueue() end
    end
end)

-- Auto buy coordinator
_wrap("autobuy-coord", function()
    while ScriptActive do
        if not autoBuyActive or _standIsTapping then task_wait(0.2); continue end

        if not myTycoon or not myTycoon.Parent then
            myTycoon = findMyTycoon()
            if myTycoon then
                resetBuyBlacklist(); 
                localQueue = {}; queueIndex = 1
            else
                task_wait(0.5); continue
            end
        end

        local remaining = #localQueue - queueIndex + 1
        if remaining == 0 and autoBuyActive then
            local added = appendNewButtons()
            if added == 0 and autoBuyActive then
                local buttons = getButtonsRealTime()
                local allDead = true
                for _, v in ipairs_(buttons) do
                    local key = getButtonKey(v)
                    if key then
                        local a = buyAttempt[key]
                        if a and a.inst and a.inst ~= v then buyAttempt[key] = nil; a = nil end
                        if not isBlacklisted(key, v) and not isGreyedOut(v) and not (a and a.n >= 6) then
                            allDead = false
                            break
                        end
                    end
                end

                if allDead then
                    if anyGivenUpButtons(buttons) then
                        local now = tick_()
                        if now - lastResetTime > 2 then
                            lastResetTime = now
                            resetBuyBlacklist();
                            localQueue = {}; queueIndex = 1
                            appendNewButtons()
                        else task_wait(0.5) end
                    else task_wait(0.5) end
                else task_wait(0.3) end
            else task_wait(0.05) end
        else task_wait(0.3) end
    end
end)

-- ==================== LEMON FARM LOOP ====================
_wrap("lemon-farm", function()
    local LEMON_MAX_PASSES     = 6
    local LEMON_VERIFY_WAIT    = 0.15
    local LEMON_VERIFY_PASSES  = 3
    local LEMON_PASS_WAIT      = 0.04

    while ScriptActive do
        local character = player.Character
        local hrp = character and character:FindFirstChild("HumanoidRootPart")

        local buyBusy   = lemonFarmActive and autoBuyActive and (#localQueue - queueIndex + 1) > 0
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

            lemonFailCount = {}
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
                    lemonFailCount = {}
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

-- ==================== AUTO STAND LOOP ====================
_wrap("auto-stand", function()
    local firstRun = true
    while ScriptActive do
        if not autoStandActive then firstRun = true; task_wait(0.25); continue end

        if not myTycoon or not myTycoon.Parent then
            myTycoon = findMyTycoon()
            if not myTycoon then task_wait(0.5); continue end
        end

        if autoBuyActive and _anyLiveButtons() then task_wait(0.3); continue end

        local manageStands = _getManageStands()
        local res
        if #manageStands > 0 then
            res = runUpgradePass(firstRun)
            if res ~= "off" then res = runUpgradePassTP(firstRun) end
        else
            if firstRun then rprint("[AutoUpgrade] Manage empty — TP mode. Open Manage for best results.") end
            res = runUpgradePassTP(firstRun)
        end

        firstRun = false
        if res == "off" then task_wait(0.05); continue end
        local rest = lemonFarmActive and CFG.standRest or STAND_LOOP_DELAY
        LSM_standNextT = tick_() + rest
        task_wait(rest)
    end
end)

-- ==================== Q KEY TOGGLE UI ====================
UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if not gameProcessed and input.KeyCode == Enum.KeyCode.Q then
        if UIRef.win then
            UIRef.win.visible = not UIRef.win.visible
            pcall_(function() UIRef.win:render() end)
        end
    end
end)

-- ==================== ANTIGRAV + INPUT LOGIC ====================
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

-- ==================== CLEANUP ====================
_G.MatchaCleanup = function()
    ScriptActive = false
    _G.SellLemonsActive = false
    pcall_(function() rsConn:Disconnect() end)
    pcall_(function() if UIRef.win then UIRef.win.visible = false end end)
    rprint("[SellLemons] Cleanup done")
end

rprint("sell lemons loaded — CLEAN EXTERNAL UI + AUTO CASH + Q TOGGLE")
