local VERSION = "3.2.0"
local EXECUTE_URL = "https://raw.githubusercontent.com/Faludaddd/PS2-Hub/main/main.lua"
local REPO_URL = "https://github.com/Faludaddd/PS2-Hub"

local Services = {}
local function GetService(name)
        if not Services[name] then
                Services[name] = game:GetService(name)
        end
        return Services[name]
end

local Players = GetService("Players")
local RunService = GetService("RunService")
local UserInputService = GetService("UserInputService")
local Workspace = GetService("Workspace")
local Lighting = GetService("Lighting")
local TeleportService = GetService("TeleportService")
local TweenService = GetService("TweenService")
local HttpService = GetService("HttpService")
local Stats = GetService("Stats")
local CoreGui = GetService("CoreGui")
local ReplicatedStorage = GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local Logger = {}
do
        local levels = { debug = -1, info = 0, warn = 1, error = 2 }
        Logger.history = {}
        Logger.minLevel = 0
        Logger.debugEnabled = false
        local onLog = nil

        local function push(level, msg)
                local entry = "[" .. os.date("%H:%M:%S") .. "] [" .. string.upper(level) .. "] " .. tostring(msg)
                table.insert(Logger.history, entry)
                if #Logger.history > 300 then
                        table.remove(Logger.history, 1)
                end
                if levels[level] >= Logger.minLevel then
                        print("[PS2 Hub] " .. entry)
                end
                if onLog then
                        pcall(onLog, entry)
                end
        end

        function Logger.setOnLog(fn)
                onLog = fn
        end

        function Logger.info(msg) push("info", msg) end
        function Logger.warn(msg) push("warn", msg) end
        function Logger.error(msg) push("error", msg) end
        function Logger.debug(msg)
                if Logger.debugEnabled then
                        push("debug", msg)
                end
        end
        function Logger.getHistory()
                return table.concat(Logger.history, "\n")
        end
        function Logger.clear()
                Logger.history = {}
        end
end

local State = {}
do
        local store = {}

        function State.get(key, default)
                if store[key] == nil then
                        return default
                end
                return store[key]
        end

        function State.set(key, value)
                store[key] = value
                return value
        end

        function State.toggle(key)
                local v = not store[key]
                store[key] = v
                return v
        end
end

-- Central registry for connections, instances and loops; emergency stop, reload and re-execute clean up through it
local Tracker = {}
do
        local connections = {}
        local instances = {}
        local running = {}

        function Tracker.track(conn, label)
                if conn and typeof(conn) == "RBXScriptConnection" then
                        table.insert(connections, { conn = conn, label = label or "" })
                end
                return conn
        end

        function Tracker.trackInstance(inst, label)
                if inst then
                        table.insert(instances, { inst = inst, label = label or "" })
                end
                return inst
        end

        function Tracker.setRunning(name, value)
                running[name] = value and true or nil
        end

        function Tracker.isRunning(name)
                return running[name] == true
        end

        function Tracker.cleanup(prefix)
                local removed = 0
                for i = #connections, 1, -1 do
                        local entry = connections[i]
                        if not prefix or entry.label == prefix or entry.label:sub(1, #prefix) == prefix then
                                pcall(function() entry.conn:Disconnect() end)
                                table.remove(connections, i)
                                removed += 1
                        end
                end
                for i = #instances, 1, -1 do
                        local entry = instances[i]
                        local instName = ""
                        pcall(function() instName = entry.inst.Name end)
                        if not prefix or entry.label == prefix or entry.label:sub(1, #prefix) == prefix or instName:sub(1, #prefix) == prefix then
                                pcall(function() entry.inst:Destroy() end)
                                table.remove(instances, i)
                                removed += 1
                        end
                end
                return removed
        end

        function Tracker.cleanupAll()
                local removed = Tracker.cleanup()
                for k in pairs(running) do
                        running[k] = nil
                end
                Logger.info("Tracker cleaned " .. removed .. " resources")
        end

        function Tracker.stats()
                local loopCount = 0
                for _ in pairs(running) do
                        loopCount += 1
                end
                return #connections, loopCount
        end

        getgenv().PS2Hub_TrackerCleanup = Tracker.cleanupAll
end


local Signal = {}
do
        Signal.__index = Signal

        function Signal.new()
                return setmetatable({ handlers = {} }, Signal)
        end

        function Signal:Connect(fn)
                local handler = { fn = fn, connected = true }
                table.insert(self.handlers, handler)
                return {
                        Disconnect = function()
                                handler.connected = false
                                for i, h in ipairs(self.handlers) do
                                        if h == handler then
                                                table.remove(self.handlers, i)
                                                break
                                        end
                                end
                        end,
                }
        end

        function Signal:Fire(...)
                for _, handler in ipairs(self.handlers) do
                        if handler.connected then
                                task.spawn(handler.fn, ...)
                        end
                end
        end
end

local Util = {}
do
        function Util.safe(fn, ...)
                local ok, err = pcall(fn, ...)
                if not ok then
                        Logger.warn("safe call failed: " .. tostring(err))
                end
                return ok, err
        end

        function Util.round(n, decimals)
                local mult = 10 ^ (decimals or 0)
                return math.floor(n * mult + 0.5) / mult
        end

        function Util.formatNumber(n)
                local formatted = tostring(math.floor(n))
                while true do
                        local k
                        formatted, k = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
                        if k == 0 then break end
                end
                return formatted
        end

        function Util.getCharacter(player)
                player = player or LocalPlayer
                return player and player.Character
        end

        function Util.getHumanoid(player)
                local char = Util.getCharacter(player)
                return char and char:FindFirstChildOfClass("Humanoid")
        end

        function Util.getRoot(player)
                local char = Util.getCharacter(player)
                return char and (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart)
        end

        function Util.getBackpack(player)
                player = player or LocalPlayer
                if not player then return nil end
                return player:FindFirstChildOfClass("Backpack")
        end

        function Util.getEquippedTool(player)
                local humanoid = Util.getHumanoid(player)
                return humanoid and humanoid:FindFirstChildOfClass("Tool")
        end

        function Util.getTools(player)
                local list = {}
                local humanoid = Util.getHumanoid(player)
                if humanoid then
                        for _, t in ipairs(humanoid:GetChildren()) do
                                if t:IsA("Tool") then table.insert(list, t) end
                        end
                end
                local backpack = Util.getBackpack(player)
                if backpack then
                        for _, t in ipairs(backpack:GetChildren()) do
                                if t:IsA("Tool") then table.insert(list, t) end
                        end
                end
                return list
        end

        function Util.getCharacterParts(player)
                local parts = {}
                local char = Util.getCharacter(player)
                if char then
                        for _, p in ipairs(char:GetDescendants()) do
                                if p:IsA("BasePart") then table.insert(parts, p) end
                        end
                end
                return parts
        end

        function Util.distanceTo(part)
                local root = Util.getRoot()
                if root and part then
                        return (root.Position - part.Position).Magnitude
                end
                return math.huge
        end

        function Util.isAlive(player)
                local humanoid = Util.getHumanoid(player)
                return humanoid and humanoid.Health > 0
        end

        -- Executor-agnostic HTTP request; syn, fluxus and http_request executors name it differently
        function Util.request(opts)
                local req = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or (request)
                if not req then
                        return nil
                end
                local ok, result = pcall(req, opts)
                if ok then return result end
                return nil
        end

        function Util.httpGet(url)
                local ok, result = pcall(function() return game:HttpGet(url) end)
                if ok then return result end
                local resp = Util.request({ Url = url, Method = "GET" })
                if resp and resp.Body then return resp.Body end
                return nil
        end

        function Util.jsonDecode(text)
                if not text then return nil end
                local ok, data = pcall(HttpService.JSONDecode, HttpService, text)
                if ok then return data end
                return nil
        end

        function Util.jsonEncode(data)
                local ok, text = pcall(HttpService.JSONEncode, HttpService, data)
                if ok then return text end
                return nil
        end

        function Util.setClipboard(text)
                local setCb = setclipboard or toclipboard or set_clipboard
                if setCb then
                        pcall(setCb, text)
                        return true
                end
                return false
        end

        function Util.getPing()
                local ok, ping = pcall(function()
                        return Stats.Network.ServerStatsItem["Data Ping"]:GetValue()
                end)
                if ok and ping then
                        return Util.round(ping, 0)
                end
                return -1
        end

        function Util.notify(title, content, duration)
                if State.get("notifications") == false then return end
                local window = _G.RayfieldInstance
                if window and window.Notify then
                        pcall(function()
                                window:Notify({
                                        title = title or "PS2 Hub",
                                        content = content or "",
                                        duration = duration or State.get("notifDuration", 3),
                                })
                        end)
                end
        end

        function Util.toast(title, duration)
                if State.get("notifications") == false then return end
                local window = _G.RayfieldInstance
                if window and window.Toast then
                        pcall(function()
                                window:Toast({
                                        title = title or "PS2 Hub",
                                        duration = duration or State.get("notifDuration", 3),
                                })
                        end)
                end
        end

        function Util.trim(s)
                local text = tostring(s or "")
                text = text:gsub("^%s+", "")
                text = text:gsub("%s+$", "")
                return text
        end

        function Util.copyTable(t)
                local copy = {}
                for k, v in pairs(t) do
                        if type(v) == "table" then
                                copy[k] = Util.copyTable(v)
                        else
                                copy[k] = v
                        end
                end
                return copy
        end
end

local GameProfile = {}
do
        local loaded = false
        local onLoadHandlers = {}

        -- registering after a load still fires immediately, so call order can never drop a handler
        function GameProfile.onLoad(fn)
                if type(fn) ~= "function" then
                        return
                end
                if loaded then
                        pcall(fn)
                        return
                end
                table.insert(onLoadHandlers, fn)
        end


        GameProfile.gameName = "Project Slayers 2"
        GameProfile.targetPlaceIds = {}
        GameProfile.ready = true
        GameProfile.status = "ACTIVE"
        GameProfile.lockReason = ""

        -- Paths verified against the analyzed client dump (project slayers 2.rbxl)
        GameProfile.data = {
                npcs = {
                        -- live npc registry: Regions/<Region>/ActiveNpcs/<Npc>/<Model> holds the real mob models
                        activeScan = "Workspace/Humanoids/Regions",
                        stationaryScan = "Workspace/Debree/Regions",
                        bossMarker = "BossInfo",
                },
                teleportPoints = {
                        { name = "Spawn", path = "Workspace/SpawnLocation" },
                        { name = "Windy Peak Crystal", path = "Workspace/Debree/Regions/Windy Peak/SpawnCrystal" },
                        { name = "Iceveil Settlement Crystal", path = "Workspace/Debree/Regions/Iceveil Valley/SpawnCrystal - Iceveil Settlement" },
                        { name = "Mistfall Harbor Crystal", path = "Workspace/Debree/Regions/Mistfall Harbor/SpawnCrystal" },
                        { name = "Bamboo Grove Crystal", path = "Workspace/Debree/Regions/Bamboo Grove/SpawnCrystal" },
                        { name = "Bamboo Sanctuary Crystal", path = "Workspace/Debree/Regions/Bamboo Grove/SpawnCrystal - Bamboo Grove Sanctuary" },
                        { name = "Butterfly Estate Crystal", path = "Workspace/Debree/Regions/Butterfly Estate/SpawnCrystal" },
                        { name = "Final Selection Crystal", path = "Workspace/Debree/Regions/Final Selection Plains/SpawnCrystal - Final Selection" },
                        { name = "Hidden Mist Village Crystal", path = "Workspace/Debree/Regions/Hidden Mist Village/SpawnCrystal" },
                        { name = "Muzan's Lair", path = "Workspace/Map/DetachedMaps/Muzan's Lair" },
                        { name = "Training: Boulder Push", path = "Workspace/Training/Boulder Push" },
                        { name = "Training: Squat Rack", path = "Workspace/Training/Squat Rack" },
                        { name = "Training: Aim Training", path = "Workspace/Training/Aim Training" },
                        { name = "Training: Boulder Split", path = "Workspace/Training/Boulder Split" },
                        { name = "Training: Cup Game", path = "Workspace/Training/Cup Game" },
                        { name = "Training: Meditation", path = "Workspace/Training/Meditation" },
                        { name = "Training: Pushups", path = "Workspace/Training/Pushups" },
                        { name = "Training: Parkour Dungeon", path = "Workspace/Training/Parkour Dungeon" },
                },
                quests = {
                        definitions = "ReplicatedStorage/QuestStates",
                        holder = "Quests/Holder",
                        -- replicated quest giver name list: Ouwland/Content/<Region>/NpcContents/Dialogues/Quests
                        giverNames = "ReplicatedStorage/Ouwland/Content",
                },
                remotes = {
                        signalEvent = "ReplicatedStorage/Communication/ServerAndClient/Signals/SignalEvent/Event",
                        signalFunction = "ReplicatedStorage/Communication/ServerAndClient/Signals/SignalFunction/Function",
                },
                mobs = {
                        -- name fragments verified on live ActiveNpcs entries (Bandit, High Demon, Mizunoto...)
                        patterns = { "Bandit", "Demon", "Bear", "Mizunoto", "Mizunoe", "Kanoe", "Subordinate", "Trainee", "Slayer" },
                },
                bosses = {
                        marker = "BossInfo",
                        -- bosses observed alive with BossInfo markers in the instance dump
                        known = { "Zuko", "Kaiden", "Hoyuzo", "Mother Bear", "Fujiko", "Muzan", "Akazo", "Reaper", "Tengai", "Yahari" },
                },
                spiderLilies = {
                        workspaceName = "Spider Lily",
                },
                clans = {
                        -- clans observed on live players in the dump; the full pool lives in the spin menu
                        clanList = {
                                "None", "Agatsuma", "Ando", "Aokawa", "Douma", "Sabito",
                                "Shinazugawa", "Susumaru", "Ubuyashiki", "Urokodaki", "Yukimori",
                        },
                        menuGui = "",
                        rerollButton = "",
                        rerollRemote = "",
                        clanLabel = "",
                },
                stats = {
                        archiveBosses = "Archives/Bosses",
                        expCurrent = "Exp/Current",
                        expGoal = "Exp/Goal",
                },
        }

        -- fires handler list exactly once; late onLoad registrations run immediately instead
        function GameProfile.load(profileData)
                if loaded then
                        return true
                end
                if type(profileData) ~= "table" then
                        Logger.warn("GameProfile.load expects a table")
                        return false
                end
                loaded = true
                for key, value in pairs(profileData) do
                        GameProfile.data[key] = value
                end
                if profileData.placeIds then
                        GameProfile.targetPlaceIds = profileData.placeIds
                end
                GameProfile.ready = true
                GameProfile.status = "ACTIVE"
                GameProfile.lockReason = ""
                Logger.info("GameProfile loaded: " .. tostring(profileData.name or "unnamed"))
                for _, fn in ipairs(onLoadHandlers) do
                        pcall(fn)
                end
                onLoadHandlers = {}
                return true
        end

        function GameProfile.isLoaded()
                return loaded == true
        end

        function GameProfile.get(path)
                local node = GameProfile.data
                for segment in string.gmatch(path, "[^.]+") do
                        if type(node) ~= "table" then
                                return nil
                        end
                        node = node[segment]
                end
                return node
        end

        function GameProfile.resolvePath(path)
                if not path or path == "" then
                        return nil
                end
                local node = game
                for segment in string.gmatch(path, "[^/]+") do
                        if node == nil then
                                return nil
                        end
                        node = node:FindFirstChild(segment)
                end
                return node
        end

        function GameProfile.getPlayerSlot()
                local ps = ReplicatedStorage:FindFirstChild("Player_Service")
                local data = ps and ps:FindFirstChild("Data")
                local playerFolder = data and data:FindFirstChild(LocalPlayer.Name)
                if not playerFolder then
                        return nil
                end
                local equipped = 1
                local eq = playerFolder:FindFirstChild("slotEquipped")
                if eq and tonumber(eq.Value) and eq.Value > 0 then
                        equipped = math.floor(eq.Value)
                end
                local slots = playerFolder:FindFirstChild("slots")
                if not slots then
                        return nil
                end
                return slots:FindFirstChild("Slot" .. equipped)
        end
end

local GameDetector = {}
do
        local detected = nil

        -- PS2 is identified by its replicated folder structure; place ids stay optional
        local function structureMatches()
                if ReplicatedStorage:FindFirstChild("Player_Service") == nil then
                        return false
                end
                if Workspace:FindFirstChild("Humanoids") == nil then
                        return false
                end
                return true
        end

        function GameDetector.detect()
                if detected and detected.inPS2 then
                        return detected
                end
                local placeId = game.PlaceId
                local jobId = game.JobId
                local matched = structureMatches()
                if not matched then
                        for _, id in ipairs(GameProfile.targetPlaceIds) do
                                if id == placeId then
                                        matched = true
                                        break
                                end
                        end
                end
                -- game.Creator does not exist on a live DataModel (it crashed detect() and every
                -- requireGame feature); CreatorId/CreatorType are the valid identification members
                detected = {
                        placeId = placeId,
                        jobId = jobId,
                        gameName = (placeId > 0 and game.Name) or "Unknown",
                        creatorId = game.CreatorId,
                        creatorType = (typeof(game.CreatorType) == "EnumItem" and game.CreatorType.Name) or tostring(game.CreatorType),
                        inPS2 = matched,
                        supported = matched,
                }
                return detected
        end

        function GameDetector.getStatusText()
                local info = GameDetector.detect()
                if info.supported then
                        return "Supported"
                end
                return "Not in Project Slayers 2"
        end

        function GameDetector.isGameReady()
                return GameDetector.detect().supported
        end

        function GameDetector.requireGame(featureName)
                if GameDetector.isGameReady() then
                        return true
                end
                local status = GameDetector.getStatusText()
                Util.notify(featureName or "Feature", "Locked - " .. status .. ". Open Project Slayers 2 to use this feature.", 5)
                Logger.warn((featureName or "feature") .. " blocked: " .. status)
                return false
        end
        -- Called at the very end of the script so every controller and UI onLoad handler exists
        -- before the profile fires. task.defer would fire at the first yield (the Rayfield HttpGet),
        -- dropping handlers that register later and leaving game dropdowns empty.
        function GameDetector.ensureLoaded()
                if GameProfile.isLoaded() then
                        return true
                end
                if GameDetector.isGameReady() then
                        GameProfile.load({ name = "baked" })
                        return true
                end
                -- replication may still be streaming in right after join; poll briefly
                if Tracker.isRunning("gamedetect") then
                        return false
                end
                Tracker.setRunning("gamedetect", true)
                task.spawn(function()
                        local attempts = 0
                        while Tracker.isRunning("gamedetect") and attempts < 200 do
                                attempts += 1
                                task.wait(3)
                                if not Tracker.isRunning("gamedetect") then
                                        break
                                end
                                if GameDetector.isGameReady() then
                                        GameProfile.load({ name = "baked" })
                                        break
                                end
                        end
                        Tracker.setRunning("gamedetect", false)
                end)
                return false
        end
end

-- Shared travel engine: Auto Quest, Auto Demon, Auto Boss and the Teleports tab all move
-- through here. Instant jumps to the objective, Tween glides; neither ever walks or pathfinds.
local MovementHandler = {}
do
        MovementHandler.settings = {
                method = "Instant",
                tweenSpeed = 60,
                arrivalDistance = 4,
                retargetDistance = 8,
        }

        local activeTween = nil
        local tweenGoal = nil
        local followTarget = nil
        local followToken = 0
        local followOwner = nil

        -- accepts an Instance (model/part), a CFrame, or nil
        local function resolveGoalCFrame(target)
                if typeof(target) == "CFrame" then
                        return target
                end
                if typeof(target) ~= "Instance" then
                        return nil
                end
                local ok, cf = pcall(function()
                        if target:IsA("Model") then
                                return target:GetPivot()
                        end
                        return target.CFrame
                end)
                if ok and cf then
                        return cf
                end
                local part = nil
                pcall(function()
                        for _, d in ipairs(target:GetDescendants()) do
                                if d:IsA("BasePart") then
                                        part = d
                                        break
                                end
                        end
                end)
                if part then
                        local ok2, cf2 = pcall(function()
                                return part.CFrame
                        end)
                        if ok2 then
                                return cf2
                        end
                end
                return nil
        end

        local function stopTween()
                if activeTween then
                        pcall(function()
                                activeTween:Cancel()
                        end)
                        activeTween = nil
                        tweenGoal = nil
                end
        end

        -- lands near the goal facing it; arrival 0 lands directly on top
        local function instantTo(root, goal, arrival)
                pcall(function()
                        local landing = goal.Position
                        local delta = root.Position - goal.Position
                        local flat = Vector3.new(delta.X, 0, delta.Z)
                        if arrival > 0 and flat.Magnitude > 0.01 then
                                landing = goal.Position + flat.Unit * math.min(arrival, flat.Magnitude)
                        end
                        local lookAt = Vector3.new(goal.Position.X, landing.Y, goal.Position.Z)
                        root.CFrame = CFrame.new(landing + Vector3.new(0, 2, 0), lookAt)
                end)
        end

        local function startTween(root, goal)
                stopTween()
                local ok, tween = pcall(function()
                        local distance = (goal.Position - root.Position).Magnitude
                        local duration = math.max(distance / math.max(MovementHandler.settings.tweenSpeed, 1), 0.1)
                        local landing = goal.Position + Vector3.new(0, 1, 0)
                        local t = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), { CFrame = CFrame.new(landing) })
                        t:Play()
                        return t
                end)
                if ok then
                        activeTween = tween
                        tweenGoal = goal.Position
                end
        end

        function MovementHandler.setMethod(method)
                MovementHandler.settings.method = (method == "Tween") and "Tween" or "Instant"
                return MovementHandler.settings.method
        end

        function MovementHandler.setTweenSpeed(value)
                MovementHandler.settings.tweenSpeed = math.clamp(value, 5, 1000)
        end

        function MovementHandler.setArrivalDistance(value)
                MovementHandler.settings.arrivalDistance = math.clamp(value, 1, 40)
        end

        function MovementHandler.isFollowing(target)
                return Tracker.isRunning("mhfollow") and followTarget == target
        end

        -- stop(nil) halts everything (emergency stop, manual teleport); stop(owner) only
        -- halts when that feature owns the movement, so parallel engines never fight
        function MovementHandler.stop(owner)
                if owner ~= nil and followOwner ~= nil and followOwner ~= owner then
                        return false
                end
                followToken += 1
                followTarget = nil
                followOwner = nil
                Tracker.setRunning("mhfollow", false)
                stopTween()
                return true
        end

        -- one-shot travel used by the Teleports tab
        function MovementHandler.travelTo(target)
                MovementHandler.stop()
                local root = Util.getRoot()
                local goal = resolveGoalCFrame(target)
                if root == nil or goal == nil then
                        return false
                end
                if MovementHandler.settings.method == "Tween" then
                        startTween(root, goal)
                else
                        instantTo(root, goal, 0)
                end
                return true
        end

        -- continuous travel toward a (possibly moving) objective; loop callers re-invoke safely.
        -- owner tags the calling feature so its own stop never kills another engine's travel
        function MovementHandler.follow(target, owner)
                if target == nil then
                        return false
                end
                if MovementHandler.isFollowing(target) then
                        return true
                end
                local goal = resolveGoalCFrame(target)
                if goal == nil then
                        return false
                end
                MovementHandler.stop()
                followTarget = target
                followOwner = owner or "default"
                followToken += 1
                local myToken = followToken
                Tracker.setRunning("mhfollow", true)
                task.spawn(function()
                        while Tracker.isRunning("mhfollow") and followToken == myToken do
                                local root = Util.getRoot()
                                local goal = resolveGoalCFrame(target)
                                if root == nil or goal == nil or target.Parent == nil then
                                        break
                                end
                                local distance = (goal.Position - root.Position).Magnitude
                                if distance <= MovementHandler.settings.arrivalDistance then
                                        stopTween()
                                elseif MovementHandler.settings.method == "Tween" then
                                        local drifted = tweenGoal == nil
                                                or (goal.Position - tweenGoal).Magnitude > MovementHandler.settings.retargetDistance
                                        if activeTween == nil or drifted then
                                                startTween(root, goal)
                                        end
                                else
                                        instantTo(root, goal, MovementHandler.settings.arrivalDistance)
                                end
                                task.wait(0.25)
                        end
                        if followToken == myToken then
                                MovementHandler.stop()
                        end
                end)
                return true
        end

        function MovementHandler.getStatusText()
                if Tracker.isRunning("mhfollow") then
                        return "Method: " .. MovementHandler.settings.method .. " - moving to objective"
                end
                return "Method: " .. MovementHandler.settings.method .. " - idle"
        end
end

local MovementController = {}
do
                MovementController.walkSpeed = 16
                MovementController.jumpPower = 50
                MovementController.jumpHeight = 7.2
                MovementController.jumpMode = "Auto"
                MovementController.flySpeed = 60
                MovementController.sprintSpeed = 32
                MovementController.sprintKey = Enum.KeyCode.LeftShift
                MovementController.lockStats = false
                MovementController.flyMethod = "WASD"

                local flyBodyVel = nil
                local flyBodyGyro = nil
                local sprintActive = false

                local function applyWalkSpeed()
                                local humanoid = Util.getHumanoid()
                                if humanoid then
                                                humanoid.WalkSpeed = MovementController.walkSpeed
                                end
                end

                local function applyJumpPower()
                                local humanoid = Util.getHumanoid()
                                if not humanoid then
                                                return
                                end
                                local usePower
                                if MovementController.jumpMode == "Power" then
                                                usePower = true
                                elseif MovementController.jumpMode == "Height" then
                                                usePower = false
                                else
                                                usePower = humanoid.UseJumpPower
                                end
                                if usePower then
                                                humanoid.UseJumpPower = true
                                                humanoid.JumpPower = MovementController.jumpPower
                                else
                                                humanoid.UseJumpPower = false
                                                humanoid.JumpHeight = MovementController.jumpHeight
                                end
                end

                function MovementController.setWalkSpeed(value)
                                MovementController.walkSpeed = value
                                if not sprintActive then
                                                applyWalkSpeed()
                                end
                end

                function MovementController.setJumpPower(value)
                                MovementController.jumpPower = value
                                applyJumpPower()
                end

                function MovementController.setJumpHeight(value)
                                MovementController.jumpHeight = value
                                applyJumpPower()
                end

                function MovementController.setJumpMode(mode)
                                MovementController.jumpMode = mode or "Auto"
                                applyJumpPower()
                end

                function MovementController.setFlySpeed(value)
                                MovementController.flySpeed = value
                end

                function MovementController.setClickTp(enabled)
                        local want = enabled and true or false
                        if Tracker.isRunning("clicktp") == want then
                                return
                        end
                        Tracker.setRunning("clicktp", enabled)
                        if enabled then
                                local conn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                                        if gameProcessed then
                                                return
                                        end
                                        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                                                local root = Util.getRoot()
                                                local camera = Workspace.CurrentCamera
                                                if not root or not camera then
                                                                return
                                                end
                                                local ray = camera:ScreenPointToRay(input.Position.X, input.Position.Y)
                                                local params = RaycastParams.new()
                                                        params.FilterType = Enum.RaycastFilterType.Exclude
                                                        local filter = { root }
                                                        if LocalPlayer.Character then
                                                                table.insert(filter, LocalPlayer.Character)
                                                        end
                                                        params.FilterDescendantsInstances = filter
                                                local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
                                                if result then
                                                        root.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
                                                end
                                        end
                                end)
                                Tracker.track(conn, "clicktp")
                        else
                                Tracker.cleanup("clicktp")
                        end
                end

                function MovementController.setFlyMethod(method)
                        if method == "Camera (mobile)" then
                                MovementController.flyMethod = "Camera"
                        else
                                MovementController.flyMethod = "WASD"
                        end
                end


                local function applySprintSpeed()
                                local humanoid = Util.getHumanoid()
                                if humanoid then
                                                humanoid.WalkSpeed = sprintActive and MovementController.sprintSpeed or MovementController.walkSpeed
                                end
                end

                function MovementController.setSprintSpeed(value)
                                MovementController.sprintSpeed = value
                                if sprintActive then
                                                applySprintSpeed()
                                end
                end

                function MovementController.setLockStats(enabled)

                local want = enabled and true or false

                        if Tracker.isRunning("lockstats") == want then

                                return

                        end

                Tracker.setRunning("lockstats", enabled)

                                MovementController.lockStats = enabled and true or false
                                if enabled then
                                                -- Re-applied every frame because the game can overwrite speed and jump at any moment
                                                local conn
                                                conn = RunService.Heartbeat:Connect(function()
                                                                local humanoid = Util.getHumanoid()
                                                                if humanoid then
                                                                                if not sprintActive and humanoid.WalkSpeed ~= MovementController.walkSpeed then
                                                                                                humanoid.WalkSpeed = MovementController.walkSpeed
                                                                                end
                                                                                applyJumpPower()
                                                                end
                                                end)
                                                Tracker.track(conn, "lockstats")
                                else
                                                Tracker.cleanup("lockstats")
                                end
                end

                function MovementController.setInfiniteJump(enabled)

                local want = enabled and true or false

                        if Tracker.isRunning("infjump") == want then

                                return

                        end

                Tracker.setRunning("infjump", enabled)

                                if enabled then
                                                local conn = UserInputService.JumpRequest:Connect(function()
                                                                local humanoid = Util.getHumanoid()
                                                                if humanoid and humanoid.Health > 0 then
                                                                                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
                                                                end
                                                end)
                                                Tracker.track(conn, "infjump")
                                else
                                                Tracker.cleanup("infjump")
                                end
                end

                function MovementController.setNoclip(enabled)

                local want = enabled and true or false

                        if Tracker.isRunning("noclip") == want then

                                return

                        end

                Tracker.setRunning("noclip", enabled)

                                if enabled then
                                                -- Stepped fires before physics, keeping collisions disabled each frame
                                                local conn = RunService.Stepped:Connect(function()
                                                                local char = LocalPlayer.Character
                                                                if not char then return end
                                                                for _, part in ipairs(char:GetDescendants()) do
                                                                                if part:IsA("BasePart") and part.CanCollide then
                                                                                                part.CanCollide = false
                                                                                end
                                                                end
                                                end)
                                                Tracker.track(conn, "noclip")
                                else
                                                Tracker.cleanup("noclip")
                                                local char = LocalPlayer.Character
                                                if char then
                                                                for _, part in ipairs(char:GetDescendants()) do
                                                                                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                                                                                                part.CanCollide = true
                                                                                end
                                                                end
                                                end
                                end
                end

                local function flyStep()
                                if not flyBodyVel or not flyBodyVel.Parent then return end
                                local root = Util.getRoot()
                                if not root then return end
                                local camera = Workspace.CurrentCamera
                                if not camera then return end
                                local moveDir = Vector3.zero
                                if MovementController.flyMethod == "Camera" then
                                        moveDir = camera.CFrame.LookVector
                                        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                                                moveDir += Vector3.yAxis * 0.5
                                        end
                                        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                                                moveDir -= Vector3.yAxis * 0.5
                                        end
                                elseif UserInputService:IsKeyDown(Enum.KeyCode.W) then
                                                moveDir += camera.CFrame.LookVector
                                end
                                if UserInputService:IsKeyDown(Enum.KeyCode.S) then
                                                moveDir -= camera.CFrame.LookVector
                                end
                                if UserInputService:IsKeyDown(Enum.KeyCode.A) then
                                                moveDir -= camera.CFrame.RightVector
                                end
                                if UserInputService:IsKeyDown(Enum.KeyCode.D) then
                                                moveDir += camera.CFrame.RightVector
                                end
                                if UserInputService:IsKeyDown(Enum.KeyCode.Space) then
                                                moveDir += Vector3.yAxis
                                end
                                if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
                                                moveDir -= Vector3.yAxis
                                end
                                if moveDir.Magnitude > 0 then
                                                flyBodyVel.Velocity = moveDir.Unit * MovementController.flySpeed
                                else
                                                flyBodyVel.Velocity = Vector3.zero
                                end
                                if flyBodyGyro and flyBodyGyro.Parent then
                                                local flatLook = Vector3.new(camera.CFrame.LookVector.X, 0, camera.CFrame.LookVector.Z)
                                                if flatLook.Magnitude > 0.01 then
                                                                flyBodyGyro.CFrame = CFrame.new(root.Position, root.Position + flatLook.Unit)
                                                end
                                end
                end

                function MovementController.setFly(enabled)

                local want = enabled and true or false

                        if Tracker.isRunning("fly") == want then

                                return true

                        end

                Tracker.setRunning("fly", enabled)

                                if enabled then
                                                local root = Util.getRoot()
                                                local humanoid = Util.getHumanoid()
                                                if not root or not humanoid then
                                                                Util.notify("Fly", "Character not found")
                                                                return false
                                                end
                                                humanoid:ChangeState(Enum.HumanoidStateType.Physics)
                                                Tracker.setRunning("fly", true)
                                                flyBodyVel = Instance.new("BodyVelocity")
                                                flyBodyVel.Name = "PS2HubFly"
                                                flyBodyVel.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                                                flyBodyVel.Velocity = Vector3.zero
                                                flyBodyVel.Parent = root
                                                flyBodyGyro = Instance.new("BodyGyro")
                                                flyBodyGyro.Name = "PS2HubGyro"
                                                flyBodyGyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
                                                flyBodyGyro.P = 9e4
                                                flyBodyGyro.CFrame = root.CFrame
                                                flyBodyGyro.Parent = root
                                                Tracker.trackInstance(flyBodyVel, "fly")
                                                Tracker.trackInstance(flyBodyGyro, "fly")
                                                local conn = RunService.RenderStepped:Connect(flyStep)
                                                Tracker.track(conn, "fly")
                                                return true
                                else
                                                Tracker.cleanup("fly")
                                                Tracker.setRunning("fly", false)
                                                flyBodyVel = nil
                                                flyBodyGyro = nil
                                                local humanoid = Util.getHumanoid()
                                                if humanoid then
                                                                humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                                                end
                                                return true
                                end
                end

                function MovementController.setSprintKey(keyCode)
                                MovementController.sprintKey = keyCode or Enum.KeyCode.LeftShift
                end

                local sprintInputConn
                function MovementController.setSprint(enabled)
                local want = enabled and true or false
                        if Tracker.isRunning("sprint") == want then
                                return
                        end
                Tracker.setRunning("sprint", enabled)

                                if enabled then
                                                sprintInputConn = UserInputService.InputBegan:Connect(function(input, gameProcessed)
                                                                if gameProcessed then return end
                                                                if input.KeyCode == MovementController.sprintKey then
                                                                                sprintActive = true
                                                                                applySprintSpeed()
                                                                end
                                                end)
                                                Tracker.track(sprintInputConn, "sprint")
                                                sprintInputConn = UserInputService.InputEnded:Connect(function(input)
                                                                if input.KeyCode == MovementController.sprintKey then
                                                                                sprintActive = false
                                                                                applySprintSpeed()
                                                                end
                                                end)
                                                Tracker.track(sprintInputConn, "sprint")
                                else
                                                Tracker.cleanup("sprint")
                                                sprintActive = false
                                                applyWalkSpeed()
                                end
                end

                local respawnConn
                function MovementController.init()
                                respawnConn = LocalPlayer.CharacterAdded:Connect(function()
                                                task.wait(0.5)
                                                applyWalkSpeed()
                                                applyJumpPower()
                                                if Tracker.isRunning("fly") and flyBodyVel then
                                                                MovementController.setFly(false)
                                                                MovementController.setFly(true)
                                                end
                                end)
                                Tracker.track(respawnConn, "respawn")
                end
end

local CharacterController = {}
do
                function CharacterController.setGod(enabled)
                local want = enabled and true or false
                        if Tracker.isRunning("god") == want then
                                return
                        end
                Tracker.setRunning("god", enabled)

                                if enabled then
                                                local conn
                                                conn = RunService.Heartbeat:Connect(function()
                                                                local humanoid = Util.getHumanoid()
                                                                if humanoid and humanoid.Health > 0 and humanoid.Health < humanoid.MaxHealth then
                                                                                humanoid.Health = humanoid.MaxHealth
                                                                end
                                                end)
                                                Tracker.track(conn, "god")
                                else
                                                Tracker.cleanup("god")
                                end
                end

                function CharacterController.setAntiAFK(enabled)

                local want = enabled and true or false

                        if Tracker.isRunning("antiafk") == want then

                                return

                        end

                Tracker.setRunning("antiafk", enabled)

                                if enabled then
                                                local VirtualUser = GetService("VirtualUser")
                                                local conn = LocalPlayer.Idled:Connect(function()
                                                                VirtualUser:CaptureController()
                                                                VirtualUser:ClickButton2(Vector2.new())
                                                end)
                                                Tracker.track(conn, "antiafk")
                                else
                                                Tracker.cleanup("antiafk")
                                end
                end

                function CharacterController.reset()
                                local humanoid = Util.getHumanoid()
                                if humanoid then
                                                humanoid.Health = 0
                                end
                end

                local DEFAULT_FOV = 70

                function CharacterController.setFov(value)
                                local camera = Workspace.CurrentCamera
                                if camera then
                                                camera.FieldOfView = math.clamp(value, 30, 120)
                                end
                end

                function CharacterController.resetFov()
                                local camera = Workspace.CurrentCamera
                                if camera then
                                                camera.FieldOfView = DEFAULT_FOV
                                end
                                return DEFAULT_FOV
                end
end

local PlayerController = {}
do
                PlayerController.selected = ""

                local function refreshCallback() end
                function PlayerController.onRefresh(fn)
                                refreshCallback = fn or function() end
                end

                function PlayerController.getPlayerNames()
                                local names = {}
                                for _, player in ipairs(Players:GetPlayers()) do
                                                if player ~= LocalPlayer then
                                                                table.insert(names, player.Name)
                                                end
                                end
                                return names
                end

                function PlayerController.select(name)
                                PlayerController.selected = name or ""
                end

                function PlayerController.teleportToSelected(mode)
                                local target = Players:FindFirstChild(PlayerController.selected)
                                if not target then
                                                Util.notify("Teleport", "Select a player first")
                                                return false
                                end
                                local rootTarget = Util.getRoot(target)
                                local root = Util.getRoot()
                                if not rootTarget or not root then
                                                Util.notify("Teleport", "Target position unavailable")
                                                return false
                                end
                                if mode == "behind" then
                                                root.CFrame = rootTarget.CFrame * CFrame.new(0, 0, -3)
                                elseif mode == "above" then
                                                root.CFrame = CFrame.new(rootTarget.Position + Vector3.new(0, 12, 0), rootTarget.Position)
                                else
                                                root.CFrame = rootTarget.CFrame * CFrame.new(0, 0, 3)
                                end
                                return true
                end

                local spectating = false
                local savedSubject = nil

                function PlayerController.spectate(name)
                                local target = Players:FindFirstChild(name or PlayerController.selected)
                                if not target then
                                                Util.notify("Spectate", "Select a player first")
                                                return false
                                end
                                local humanoid = Util.getHumanoid(target)
                                local camera = Workspace.CurrentCamera
                                if not humanoid or not camera then
                                                Util.notify("Spectate", "Target has no character yet")
                                                return false
                                end
                                if not spectating and camera.CameraSubject and camera.CameraSubject ~= humanoid then
                                                savedSubject = camera.CameraSubject
                                end
                                camera.CameraSubject = humanoid
                                spectating = true
                                return true
                end

                function PlayerController.stopSpectate()
                                local camera = Workspace.CurrentCamera
                                if not camera then
                                                spectating = false
                                                savedSubject = nil
                                                return
                                end
                                if savedSubject and savedSubject.Parent then
                                                camera.CameraSubject = savedSubject
                                else
                                                local myHumanoid = Util.getHumanoid()
                                                if myHumanoid then
                                                                camera.CameraSubject = myHumanoid
                                                end
                                end
                                spectating = false
                                savedSubject = nil
                end


                function PlayerController.setFollow(enabled)

                        local want = enabled and true or false

                        if Tracker.isRunning("follow") == want then

                                return

                        end

                        Tracker.setRunning("follow", enabled)

                        if enabled then

                                local conn = RunService.Heartbeat:Connect(function()

                                        local target = Players:FindFirstChild(PlayerController.selected)

                                        local rootTarget = target and Util.getRoot(target)

                                        local root = Util.getRoot()

                                        if rootTarget and root and Util.isAlive() then

                                                local delta = rootTarget.Position - root.Position

                                                if delta.Magnitude > 4 then

                                                        local step = delta.Unit * math.min(delta.Magnitude - 3, 1)

                                                        root.CFrame = CFrame.new(root.Position + step, rootTarget.Position)

                                                end

                                        end

                                end)

                                Tracker.track(conn, "follow")

                        else

                                Tracker.cleanup("follow")

                        end

                end


                local connAdded, connRemoving
                function PlayerController.init()
                                connAdded = Players.PlayerAdded:Connect(function()
                                                task.wait(1)
                                                refreshCallback()
                                end)
                                Tracker.track(connAdded, "playerlist")
                                connRemoving = Players.PlayerRemoving:Connect(function()
                                                task.wait(1)
                                                refreshCallback()
                                end)
                                Tracker.track(connRemoving, "playerlist")
                end
end

local ToolController = {}
do
                ToolController.autoEquip = false
                ToolController.lastToolName = ""
                ToolController.selected = ""

                local refreshCallback = function() end
                function ToolController.onRefresh(fn)
                                refreshCallback = fn or function() end
                end

                function ToolController.getToolNames()
                                local names = {}
                                for _, tool in ipairs(Util.getTools()) do
                                                table.insert(names, tool.Name)
                                end
                                return names
                end

                function ToolController.select(name)
                                ToolController.selected = name or ""
                end

                function ToolController.equipSelected()
                                local humanoid = Util.getHumanoid()
                                if not humanoid then
                                                Util.notify("Equip", "No character")
                                                return false
                                end
                                for _, tool in ipairs(Util.getTools()) do
                                                if tool.Name == ToolController.selected then
                                                                ToolController.lastToolName = tool.Name
                                                                humanoid:EquipTool(tool)
                                                                return true
                                                end
                                end
                                Util.notify("Equip", "Tool not found: " .. tostring(ToolController.selected))
                                return false
                end

                function ToolController.unequip()
                                local humanoid = Util.getHumanoid()
                                if humanoid then
                                                humanoid:UnequipTools()
                                end
                end

                function ToolController.setAutoEquip(enabled)
                                ToolController.autoEquip = enabled and true or false
                                if enabled then
                                                local conn = LocalPlayer.CharacterAdded:Connect(function()
                                                                task.wait(1)
                                                                if ToolController.autoEquip and ToolController.lastToolName ~= "" then
                                                                                for _, tool in ipairs(Util.getTools()) do
                                                                                                if tool.Name == ToolController.lastToolName then
                                                                                                                local humanoid = Util.getHumanoid()
                                                                                                                if humanoid then
                                                                                                                                humanoid:EquipTool(tool)
                                                                                                                end
                                                                                                                break
                                                                                                end
                                                                                end
                                                                end
                                                end)
                                                Tracker.track(conn, "autoequip")
                                else
                                                Tracker.cleanup("autoequip")
                                end
                end

                local backpackConn
                function ToolController.init()
                                local backpack = Util.getBackpack()
                                if backpack then
                                                backpackConn = backpack.ChildAdded:Connect(function()
                                                                task.wait(0.2)
                                                                refreshCallback()
                                                end)
                                                Tracker.track(backpackConn, "toollist")
                                end
                                local charConn = LocalPlayer.CharacterAdded:Connect(function()
                                                task.wait(1)
                                                local newBackpack = Util.getBackpack()
                                                if newBackpack then
                                                                Tracker.cleanup("toollist")
                                                                backpackConn = newBackpack.ChildAdded:Connect(function()
                                                                                task.wait(0.2)
                                                                                refreshCallback()
                                                                end)
                                                                Tracker.track(backpackConn, "toollist")
                                                end
                                                refreshCallback()
                                end)
                                Tracker.track(charConn, "toollist")
                end
end

local WebhookController = {}
do
        -- Two fully independent webhook systems; clan and boss each keep their own URL and settings
        local TEST_COOLDOWN = 3

        WebhookController.clan = {
                enabled = false,
                url = "",
                notifyDesired = true,
                status = "Not configured",
        }
        WebhookController.boss = {
                enabled = false,
                url = "",
                notifyKills = true,
                status = "Not configured",
        }

        local clanTesting = false
        local bossTesting = false
        local clanLastTest = 0
        local bossLastTest = 0
        local clanFailAnnounced = false
        local bossFailAnnounced = false

        local function accountSpoiler()
                return "||" .. LocalPlayer.Name .. "||"
        end

        local function validWebhookUrl(url)
                local trimmed = Util.trim(url)
                if trimmed == "" then
                        return nil, "Webhook URL required"
                end
                local ok1 = trimmed:find("^https://[%w%.%-]*discord%.com/api/webhooks/")
                local ok2 = trimmed:find("^https://[%w%.%-]*discordapp%.com/api/webhooks/")
                if not (ok1 or ok2) then
                        return nil, "Invalid Discord webhook URL"
                end
                return trimmed, nil
        end

        local function postWebhook(url, payload)
                local body = Util.jsonEncode(payload)
                if body == nil then
                        return false
                end
                local resp = Util.request({
                        Url = url,
                        Method = "POST",
                        Headers = { ["Content-Type"] = "application/json" },
                        Body = body,
                })
                if resp == nil then
                        return false
                end
                local code = tonumber(resp.StatusCode or resp.status_code or resp.code) or 0
                if code >= 200 and code < 300 then
                        return true
                end
                Logger.warn("webhook rejected (HTTP " .. tostring(code) .. ")")
                return false
        end

        local function baseEmbed(title, color, description)
                return {
                        title = title,
                        description = description,
                        color = color,
                        footer = { text = "PS2 Hub v" .. VERSION },
                }
        end

        function WebhookController.buildClanTestPayload()
                local embed = baseEmbed("Clan Webhook Test", 3447003, "This is a test notification - no real clan was obtained.")
                embed.fields = {
                        { name = "Account", value = accountSpoiler(), inline = true },
                        { name = "Result", value = "Webhook working correctly", inline = true },
                }
                return { username = "PS2 Hub", embeds = { embed } }
        end

        function WebhookController.buildClanObtainedPayload(clanName, spins)
                local embed = baseEmbed("Desired Clan Obtained", 5763719, "The selected Desired Clan was just obtained.")
                embed.fields = {
                        { name = "Clan", value = tostring(clanName or "?"), inline = true },
                        { name = "Account", value = accountSpoiler(), inline = true },
                }
                if spins ~= nil then
                        table.insert(embed.fields, { name = "Spins (session)", value = tostring(spins), inline = true })
                end
                return { username = "PS2 Hub", embeds = { embed } }
        end

        function WebhookController.buildBossTestPayload()
                local embed = baseEmbed("Boss Farm Webhook Test", 3447003, "This is a test notification - no boss was killed.")
                embed.fields = {
                        { name = "Account", value = accountSpoiler(), inline = true },
                        { name = "Result", value = "Webhook working correctly", inline = true },
                }
                return { username = "PS2 Hub", embeds = { embed } }
        end

        function WebhookController.buildBossKillPayload(bossName, drops)
                local embed = baseEmbed("Boss Farm Kill", 15158332, nil)
                embed.fields = {
                        { name = "Boss", value = tostring(bossName or "?"), inline = true },
                        { name = "Account", value = accountSpoiler(), inline = true },
                }
                if type(drops) == "table" and #drops > 0 then
                        table.insert(embed.fields, { name = "Drops", value = table.concat(drops, ", "), inline = false })
                elseif type(drops) == "string" and drops ~= "" then
                        table.insert(embed.fields, { name = "Drops", value = drops, inline = false })
                end
                return { username = "PS2 Hub", embeds = { embed } }
        end

        function WebhookController.setClanEnabled(enabled)
                WebhookController.clan.enabled = enabled and true or false
                if WebhookController.clan.enabled and Util.trim(WebhookController.clan.url) == "" then
                        WebhookController.clan.status = "Webhook URL required"
                elseif WebhookController.clan.enabled then
                        WebhookController.clan.status = "Ready - waiting for the Desired Clan"
                end
                return WebhookController.clan.enabled
        end

        function WebhookController.setClanUrl(url)
                WebhookController.clan.url = Util.trim(url or "")
                if WebhookController.clan.url == "" then
                        WebhookController.clan.status = "Webhook URL required"
                else
                        WebhookController.clan.status = "URL set - send a test to verify"
                end
                return WebhookController.clan.url
        end

        function WebhookController.setClanNotifyDesired(enabled)
                WebhookController.clan.notifyDesired = enabled and true or false
                return WebhookController.clan.notifyDesired
        end

        function WebhookController.setBossEnabled(enabled)
                WebhookController.boss.enabled = enabled and true or false
                if WebhookController.boss.enabled and Util.trim(WebhookController.boss.url) == "" then
                        WebhookController.boss.status = "Webhook URL required"
                elseif WebhookController.boss.enabled then
                        WebhookController.boss.status = "Ready - waiting for boss kills"
                end
                return WebhookController.boss.enabled
        end

        function WebhookController.setBossUrl(url)
                WebhookController.boss.url = Util.trim(url or "")
                if WebhookController.boss.url == "" then
                        WebhookController.boss.status = "Webhook URL required"
                else
                        WebhookController.boss.status = "URL set - send a test to verify"
                end
                return WebhookController.boss.url
        end

        function WebhookController.setBossNotifyKills(enabled)
                WebhookController.boss.notifyKills = enabled and true or false
                return WebhookController.boss.notifyKills
        end

        function WebhookController.testClanWebhook()
                if clanTesting then
                        return false
                end
                if os.clock() - clanLastTest < TEST_COOLDOWN then
                        WebhookController.clan.status = "Please wait a moment before testing again"
                        return false
                end
                local url, err = validWebhookUrl(WebhookController.clan.url)
                if url == nil then
                        WebhookController.clan.status = err
                        Util.notify("Clan Webhook", err)
                        return false
                end
                clanTesting = true
                clanLastTest = os.clock()
                WebhookController.clan.status = "Testing webhook..."
                task.spawn(function()
                        local ok = postWebhook(url, WebhookController.buildClanTestPayload())
                        WebhookController.clan.status = ok and "Webhook sent successfully" or "Webhook failed"
                        clanTesting = false
                end)
                return true
        end

        function WebhookController.testBossWebhook()
                if bossTesting then
                        return false
                end
                if os.clock() - bossLastTest < TEST_COOLDOWN then
                        WebhookController.boss.status = "Please wait a moment before testing again"
                        return false
                end
                local url, err = validWebhookUrl(WebhookController.boss.url)
                if url == nil then
                        WebhookController.boss.status = err
                        Util.notify("Boss Farm Webhook", err)
                        return false
                end
                bossTesting = true
                bossLastTest = os.clock()
                WebhookController.boss.status = "Testing webhook..."
                task.spawn(function()
                        local ok = postWebhook(url, WebhookController.buildBossTestPayload())
                        WebhookController.boss.status = ok and "Webhook sent successfully" or "Webhook failed"
                        bossTesting = false
                end)
                return true
        end

        -- Called by ClanController (both spin paths) when the result equals the Desired Clan
        function WebhookController.notifyClanObtained(clanName, spins)
                if not WebhookController.clan.enabled or not WebhookController.clan.notifyDesired then
                        return false
                end
                local url, err = validWebhookUrl(WebhookController.clan.url)
                if url == nil then
                        WebhookController.clan.status = err
                        return false
                end
                WebhookController.clan.status = "Sending clan notification..."
                task.spawn(function()
                        local ok = postWebhook(url, WebhookController.buildClanObtainedPayload(clanName, spins))
                        if ok then
                                WebhookController.clan.status = "Clan notification sent"
                        else
                                WebhookController.clan.status = "Webhook failed"
                                if not clanFailAnnounced then
                                        clanFailAnnounced = true
                                        Logger.warn("clan webhook notification failed - no auto retry, will try again on the next obtain")
                                end
                        end
                end)
                return true
        end

        -- Entry point for Auto Boss kill detection once instance data confirms kills and drops
        function WebhookController.notifyBossKilled(bossName, drops)
                if not WebhookController.boss.enabled or not WebhookController.boss.notifyKills then
                        return false
                end
                local url, err = validWebhookUrl(WebhookController.boss.url)
                if url == nil then
                        WebhookController.boss.status = err
                        return false
                end
                WebhookController.boss.status = "Sending boss kill notification..."
                task.spawn(function()
                        local ok = postWebhook(url, WebhookController.buildBossKillPayload(bossName, drops))
                        if ok then
                                WebhookController.boss.status = "Boss kill notification sent"
                        else
                                WebhookController.boss.status = "Webhook failed"
                                if not bossFailAnnounced then
                                        bossFailAnnounced = true
                                        Logger.warn("boss webhook notification failed - no auto retry, will try again on the next kill")
                                end
                        end
                end)
                return true
        end

        function WebhookController.getClanStatusText()
                return WebhookController.clan.status
        end

        function WebhookController.getBossStatusText()
                return WebhookController.boss.status
        end
end

local ESPController = {}
do
        ESPController.options = {
                players = false,
                npcs = false,
                bosses = false,
                questNpcs = false,
                items = false,
                names = true,
                distance = true,
                healthBars = true,
                teamColor = false,
                tracers = false,
                box = false,
                highlight = true,
                maxDistance = 250,
                updateRate = 0,
        }
        ESPController.stats = { drawn = 0, total = 0 }
        ESPController.rendererMode = "Highlight"

        local targets = {}
        local espGui = nil
        -- Drawing renderer is PC-only; boxes and tracers fall back to Highlight elsewhere
        local drawingAvailable = false
        local updateConn = nil
        local playerConns = {}

        local COLORS = {
                player = Color3.fromRGB(255, 170, 0),
                npc = Color3.fromRGB(0, 255, 128),
                boss = Color3.fromRGB(235, 60, 60),
                quest = Color3.fromRGB(190, 90, 255),
                item = Color3.fromRGB(255, 220, 90),
                text = Color3.fromRGB(255, 255, 255),
        }

        local function categoryColor(category)
                if category == "players" then return COLORS.player end
                if category == "bosses" then return COLORS.boss end
                if category == "questnpcs" then return COLORS.quest end
                if category == "items" then return COLORS.item end
                return COLORS.npc
        end

        local function getEspGui()
                if espGui and espGui.Parent then
                        return espGui
                end
                local gui = Instance.new("ScreenGui")
                gui.Name = "PS2HubESP"
                gui.DisplayOrder = 999999
                gui.IgnoreGuiInset = true
                local ok = pcall(function()
                        gui.Parent = CoreGui
                end)
                if not ok then
                        gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
                end
                espGui = gui
                Tracker.trackInstance(gui, "esp")
                return gui
        end

        local function makeTracer()
                if not drawingAvailable then
                        return nil
                end
                local ok, line = pcall(function()
                        local l = Drawing.new("Line")
                        l.Thickness = 1
                        l.Transparency = 1
                        l.Color = COLORS.player
                        l.Visible = false
                        return l
                end)
                if ok then
                        return line
                end
                return nil
        end

        local function makeBox(color)
                if not drawingAvailable then
                        return nil
                end
                local ok, square = pcall(function()
                        local s = Drawing.new("Square")
                        s.Thickness = 1
                        s.Transparency = 1
                        s.Color = color or COLORS.player
                        s.Filled = false
                        s.Visible = false
                        return s
                end)
                if ok then
                        return square
                end
                return nil
        end

        local function addTarget(model, category, playerName)
                if targets[model] then
                        return
                end
                local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model:FindFirstChild("Handle") or model.PrimaryPart
                if not root then
                        return
                end
                local humanoid = model:FindFirstChildOfClass("Humanoid")
                if category ~= "items" and not humanoid then
                        return
                end
                local highlight
                if ESPController.options.highlight then
                        highlight = Instance.new("Highlight")
                        highlight.Name = "PS2HubESP_Highlight"
                        highlight.Adornee = model
                        highlight.FillTransparency = 0.7
                        highlight.OutlineTransparency = 0
                        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                        local baseColor = categoryColor(category)
                        if category == "players" and ESPController.options.teamColor then
                                local player = Players:GetPlayerFromCharacter(model)
                                if player and player.Team then
                                        baseColor = player.Team.TeamColor.Color
                                end
                        end
                        highlight.FillColor = baseColor
                        highlight.OutlineColor = baseColor
                        pcall(function()
                                highlight.Parent = getEspGui()
                        end)
                end

                local nameLabel
                local distLabel
                local healthBack
                local healthFill
                local bb
                if ESPController.options.names or ESPController.options.distance or ESPController.options.healthBars then
                        local baseColor = categoryColor(category)
                        if category == "players" and ESPController.options.teamColor then
                                local player = Players:GetPlayerFromCharacter(model)
                                if player and player.Team then
                                        baseColor = player.Team.TeamColor.Color
                                end
                        end
                        bb = Instance.new("BillboardGui")
                        bb.Name = "PS2HubESP_Label"
                        bb.Adornee = root
                        bb.AlwaysOnTop = true
                        bb.Size = UDim2.new(0, 220, 0, 46)
                        bb.StudsOffset = Vector3.new(0, 2.5, 0)
                        nameLabel = Instance.new("TextLabel")
                        nameLabel.BackgroundTransparency = 1
                        nameLabel.Size = UDim2.new(1, 0, 0, 20)
                        nameLabel.Font = Enum.Font.Code
                        nameLabel.TextSize = 14
                        nameLabel.TextColor3 = baseColor
                        nameLabel.TextStrokeTransparency = 0.4
                        nameLabel.Text = playerName or model.Name
                        nameLabel.Parent = bb
                        distLabel = Instance.new("TextLabel")
                        distLabel.BackgroundTransparency = 1
                        distLabel.Position = UDim2.new(0, 0, 0, 22)
                        distLabel.Size = UDim2.new(1, 0, 0, 16)
                        distLabel.Font = Enum.Font.Code
                        distLabel.TextSize = 12
                        distLabel.TextColor3 = COLORS.text
                        distLabel.TextStrokeTransparency = 0.6
                        distLabel.Text = ""
                        distLabel.Parent = bb
                        if humanoid then
                                healthBack = Instance.new("Frame")
                                healthBack.Name = "PS2HubESP_Health"
                                healthBack.AnchorPoint = Vector2.new(0.5, 0)
                                healthBack.Position = UDim2.new(0.5, 0, 0, 41)
                                healthBack.Size = UDim2.new(0, 120, 0, 4)
                                healthBack.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
                                healthBack.BackgroundTransparency = 0.25
                                healthBack.BorderSizePixel = 0
                                healthBack.Parent = bb
                                healthFill = Instance.new("Frame")
                                healthFill.Size = UDim2.new(1, 0, 1, 0)
                                healthFill.BackgroundColor3 = Color3.fromRGB(0, 255, 128)
                                healthFill.BorderSizePixel = 0
                                healthFill.Parent = healthBack
                        end
                        bb.Parent = getEspGui()
                end

                local tracer
                if ESPController.options.tracers and category == "players" and drawingAvailable then
                        tracer = makeTracer()
                end
                local box
                if ESPController.options.box and drawingAvailable then
                        box = makeBox(categoryColor(category))
                end

                targets[model] = {
                        category = category,
                        highlight = highlight,
                        billboard = bb,
                        nameLabel = nameLabel,
                        distLabel = distLabel,
                        healthBack = healthBack,
                        healthFill = healthFill,
                        tracer = tracer,
                        box = box,
                        root = root,
                        humanoid = humanoid,
                }
        end

        local function removeTarget(model)
                local entry = targets[model]
                if not entry then
                        return
                end
                if entry.highlight then
                        pcall(function() entry.highlight:Destroy() end)
                end
                if entry.billboard then
                        pcall(function() entry.billboard:Destroy() end)
                end
                if entry.tracer then
                        pcall(function() entry.tracer:Remove() end)
                end
                if entry.box then
                        pcall(function() entry.box:Remove() end)
                end
                targets[model] = nil
        end

        local function clearCategory(category)
                for model, entry in pairs(targets) do
                        if entry.category == category then
                                removeTarget(model)
                        end
                end
        end

        local function rebuildTargets()
                local rebuild = {}
                for model, entry in pairs(targets) do
                        local displayName = nil
                        if entry.category == "players" then
                                local player = Players:GetPlayerFromCharacter(model)
                                displayName = player and player.DisplayName or nil
                        end
                        table.insert(rebuild, { model = model, category = entry.category, name = displayName })
                end
                for _, item in ipairs(rebuild) do
                        removeTarget(item.model)
                        if item.model.Parent then
                                addTarget(item.model, item.category, item.name)
                        end
                end
        end

        local function trackPlayer(player)
                if player == LocalPlayer then
                        return
                end
                local function onCharacter(char)
                        task.wait(0.5)
                        if ESPController.options.players then
                                addTarget(char, "players", player.DisplayName)
                        end
                end
                if player.Character then
                        onCharacter(player.Character)
                end
                table.insert(playerConns, player.CharacterAdded:Connect(function(char)
                        onCharacter(char)
                end))
                table.insert(playerConns, player.CharacterRemoving:Connect(function()
                        if player.Character then
                                removeTarget(player.Character)
                        end
                end))
        end

        local function updateAll()
                local camera = Workspace.CurrentCamera
                if not camera then
                        return
                end
                local myRoot = Util.getRoot()
                local screenSize = camera.ViewportSize
                local drawn = 0
                local total = 0
                for model, entry in pairs(targets) do
                        total += 1
                        local root = entry.root
                        local dead = entry.humanoid and entry.humanoid.Health <= 0
                        if not root or not root.Parent or dead then
                                removeTarget(model)
                        else
                                local dist = myRoot and (root.Position - myRoot.Position).Magnitude or 0
                                local inRange = dist <= ESPController.options.maxDistance
                                if inRange then
                                        drawn += 1
                                end
                                if entry.highlight then
                                        entry.highlight.Enabled = inRange and ESPController.options.highlight
                                end
                                if entry.billboard then
                                        entry.billboard.Enabled = inRange
                                        if entry.distLabel then
                                                entry.distLabel.Visible = ESPController.options.distance
                                                if ESPController.options.distance then
                                                        entry.distLabel.Text = tostring(Util.round(dist, 0)) .. " studs"
                                                end
                                        end
                                        if entry.nameLabel then
                                                entry.nameLabel.Visible = ESPController.options.names
                                        end
                                        if entry.healthBack then
                                                entry.healthBack.Visible = ESPController.options.healthBars
                                                if ESPController.options.healthBars and entry.humanoid and entry.humanoid.MaxHealth > 0 then
                                                        local pct = math.clamp(entry.humanoid.Health / entry.humanoid.MaxHealth, 0, 1)
                                                        entry.healthFill.Size = UDim2.new(pct, 0, 1, 0)
                                                        entry.healthFill.BackgroundColor3 = Color3.fromRGB(255 * (1 - pct), 255 * pct, 60)
                                                end
                                        end
                                end
                                if entry.box then
                                        if inRange then
                                                local topPos, topOn = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 3, 0))
                                                local bottomPos, bottomOn = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3, 0))
                                                if (topOn or bottomOn) and topPos.Y ~= bottomPos.Y then
                                                        local height = math.abs(bottomPos.Y - topPos.Y)
                                                        local width = math.max(height * 0.6, 8)
                                                        local midX = (topPos.X + bottomPos.X) / 2
                                                        local midY = (topPos.Y + bottomPos.Y) / 2
                                                        entry.box.Size = Vector2.new(width, height)
                                                        entry.box.Position = Vector2.new(midX - width / 2, midY - height / 2)
                                                        entry.box.Visible = true
                                                else
                                                        entry.box.Visible = false
                                                end
                                        else
                                                entry.box.Visible = false
                                        end
                                end
                                if entry.tracer then
                                        if inRange then
                                                local pos, onScreen = camera:WorldToViewportPoint(root.Position)
                                                if onScreen then
                                                        entry.tracer.Visible = true
                                                        entry.tracer.From = Vector2.new(screenSize.X / 2, screenSize.Y)
                                                        entry.tracer.To = Vector2.new(pos.X, pos.Y)
                                                        entry.tracer.Color = entry.highlight and entry.highlight.OutlineColor or COLORS.player
                                                else
                                                        entry.tracer.Visible = false
                                                end
                                        else
                                                entry.tracer.Visible = false
                                        end
                                end
                        end
                end
                ESPController.stats.drawn = drawn
                ESPController.stats.total = total
        end

        function ESPController.setPlayers(enabled)
                local want = enabled and true or false
                if Tracker.isRunning("espplayers") == want then
                        return
                end
                ESPController.options.players = want
                Tracker.setRunning("espplayers", enabled)
                if enabled then
                        for _, player in ipairs(Players:GetPlayers()) do
                                trackPlayer(player)
                        end
                        table.insert(playerConns, Players.PlayerAdded:Connect(function(player)
                                trackPlayer(player)
                        end))
                        table.insert(playerConns, Players.PlayerRemoving:Connect(function(player)
                                if player.Character then
                                        removeTarget(player.Character)
                                end
                        end))
                        for _, conn in ipairs(playerConns) do
                                Tracker.track(conn, "espplayers")
                        end
                else
                        for _, conn in ipairs(playerConns) do
                                pcall(function() conn:Disconnect() end)
                        end
                        playerConns = {}
                        Tracker.cleanup("espplayers")
                        clearCategory("players")
                end
        end

        local function isQuestGiver(model)
                for _, d in ipairs(model:GetDescendants()) do
                        if d:IsA("Dialog") or d:IsA("ProximityPrompt") then
                                return true
                        end
                end
                return false
        end

        local function scanNpcs()
                local playerChars = {}
                for _, player in ipairs(Players:GetPlayers()) do
                        if player.Character then
                                playerChars[player.Character] = true
                        end
                end
                local found = {}
                local scanned = 0
                local maxDist = ESPController.options.maxDistance * 2
                local options = ESPController.options
                local function scanContainer(container, depth)
                        if depth > 3 or scanned > 2500 then
                                return
                        end
                        for _, child in ipairs(container:GetChildren()) do
                                scanned += 1
                                if child:IsA("Tool") then
                                        if options.items and not playerChars[child.Parent] and Util.distanceTo(child) <= maxDist then
                                                found[child] = true
                                                addTarget(child, "items")
                                        end
                                elseif child:IsA("Model") then
                                        if not playerChars[child] and child ~= LocalPlayer.Character then
                                                local humanoid = child:FindFirstChildOfClass("Humanoid")
                                                if humanoid and humanoid.Health > 0 then
                                                        local root = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
                                                        if root and Util.distanceTo(root) <= maxDist then
                                                                local category = nil
                                                                if options.bosses and humanoid.MaxHealth >= 1000 then
                                                                        category = "bosses"
                                                                elseif options.questNpcs and isQuestGiver(child) then
                                                                        category = "questnpcs"
                                                                elseif options.npcs then
                                                                        category = "npcs"
                                                                end
                                                                if category then
                                                                        found[child] = true
                                                                        addTarget(child, category)
                                                                end
                                                        end
                                                end
                                        end
                                        scanContainer(child, depth + 1)
                                elseif child:IsA("Folder") then
                                        scanContainer(child, depth + 1)
                                end
                        end
                end
                scanContainer(Workspace, 1)
                for model, entry in pairs(targets) do
                        if entry.category ~= "players" and not found[model] then
                                removeTarget(model)
                        end
                end
        end

        local scanLoopActive = false
        local function ensureScanLoop()
                local options = ESPController.options
                local any = options.npcs or options.bosses or options.questNpcs or options.items
                Tracker.setRunning("npcscan", any and true or nil)
                if any and not scanLoopActive then
                        scanLoopActive = true
                        task.spawn(function()
                                while scanLoopActive do
                                        local opts = ESPController.options
                                        if not (opts.npcs or opts.bosses or opts.questNpcs or opts.items) then
                                                break
                                        end
                                        local ok, err = pcall(scanNpcs)
                                        if not ok then
                                                Logger.warn("npc scan failed: " .. tostring(err))
                                        end
                                        task.wait(2)
                                end
                                scanLoopActive = false
                        end)
                end
        end

        local function setNpcCategory(category, enabled)
                ESPController.options[category] = enabled and true or false
                if not enabled then
                        clearCategory(category)
                end
                ensureScanLoop()
        end

        function ESPController.setNpcs(enabled)
                setNpcCategory("npcs", enabled)
        end

        function ESPController.setBosses(enabled)
                setNpcCategory("bosses", enabled)
        end

        function ESPController.setQuestNpcs(enabled)
                setNpcCategory("questNpcs", enabled)
        end

        function ESPController.setItems(enabled)
                setNpcCategory("items", enabled)
        end

        function ESPController.setNames(enabled)
                ESPController.options.names = enabled and true or false
                if enabled then
                        rebuildTargets()
                else
                        for _, entry in pairs(targets) do
                                if entry.nameLabel then
                                        entry.nameLabel.Visible = false
                                end
                        end
                end
        end

        function ESPController.setDistance(enabled)
                ESPController.options.distance = enabled and true or false
                for _, entry in pairs(targets) do
                        if entry.distLabel then
                                entry.distLabel.Text = ESPController.options.distance and entry.distLabel.Text or ""
                        end
                end
        end

        function ESPController.setTeamColor(enabled)
                ESPController.options.teamColor = enabled and true or false
                for model, entry in pairs(targets) do
                        if entry.category == "players" then
                                local color = COLORS.player
                                if enabled then
                                        local player = Players:GetPlayerFromCharacter(model)
                                        if player and player.Team then
                                                color = player.Team.TeamColor.Color
                                        end
                                end
                                if entry.highlight then
                                        entry.highlight.FillColor = color
                                        entry.highlight.OutlineColor = color
                                end
                                if entry.nameLabel then
                                        entry.nameLabel.TextColor3 = color
                                end
                        end
                end
        end

        function ESPController.setTracers(enabled)
                local want = enabled and true or false
                if ESPController.options.tracers == want then
                        return true
                end
                if enabled and not drawingAvailable then
                        Util.notify("Tracers", "Drawing API not supported on this platform")
                        return false
                end
                ESPController.options.tracers = enabled and true or false
                if not enabled then
                        for model, entry in pairs(targets) do
                                if entry.tracer then
                                        pcall(function() entry.tracer:Remove() end)
                                        entry.tracer = nil
                                end
                        end
                end
                return true
        end

        function ESPController.setHealthBars(enabled)
                ESPController.options.healthBars = enabled and true or false
                if enabled then
                        rebuildTargets()
                end
        end

        function ESPController.setMaxDistance(value)
                ESPController.options.maxDistance = value
        end

        function ESPController.setHighlight(enabled)
                ESPController.options.highlight = enabled and true or false
                if enabled then
                        rebuildTargets()
                else
                        for _, entry in pairs(targets) do
                                if entry.highlight then
                                        entry.highlight.Enabled = false
                                end
                        end
                end
        end

        function ESPController.setBox(enabled)
                local want = enabled and true or false
                if ESPController.options.box == want then
                        return true
                end
                if enabled and not drawingAvailable then
                        Util.notify("Box ESP", "Drawing API not supported on this platform")
                        return false
                end
                ESPController.options.box = want
                if not want then
                        for _, entry in pairs(targets) do
                                if entry.box then
                                        pcall(function() entry.box:Remove() end)
                                        entry.box = nil
                                end
                        end
                else
                        rebuildTargets()
                end
                return true
        end

        function ESPController.setUpdateRate(value)
                ESPController.options.updateRate = value
        end

        local function recolor(category, color)
                for model, entry in pairs(targets) do
                        if entry.category == category then
                                if entry.highlight then
                                        entry.highlight.FillColor = color
                                        entry.highlight.OutlineColor = color
                                end
                                if entry.nameLabel then
                                        entry.nameLabel.TextColor3 = color
                                end
                                if entry.box then
                                        entry.box.Color = color
                                end
                        end
                end
        end

        function ESPController.setPlayerColor(color)
                COLORS.player = color
                recolor("players", color)
        end

        function ESPController.setNpcColor(color)
                COLORS.npc = color
                recolor("npcs", color)
        end

        function ESPController.setBossColor(color)
                COLORS.boss = color
                recolor("bosses", color)
        end

        function ESPController.getTargetCount()
                local total = 0
                for _ in pairs(targets) do
                        total += 1
                end
                return total
        end

        function ESPController.getStatusText()
                local any = ESPController.options.players or ESPController.options.npcs
                        or ESPController.options.bosses or ESPController.options.questNpcs or ESPController.options.items
                if not any then
                        return "ESP off"
                end
                return string.format("Renderer: %s · %d/%d shown",
                        ESPController.rendererMode,
                        ESPController.stats.drawn or 0,
                        ESPController.stats.total or 0)
        end

        function ESPController.init()
                drawingAvailable = (typeof(Drawing) == "table" and typeof(Drawing.new) == "function") or false
                ESPController.rendererMode = drawingAvailable and "Drawing" or "Highlight"
                local lastUpdate = 0
                updateConn = RunService.Heartbeat:Connect(function()
                        local rate = ESPController.options.updateRate or 0
                        if rate > 0 then
                                local now = os.clock()
                                if now - lastUpdate < rate then
                                        return
                                end
                                lastUpdate = now
                        end
                        local ok, err = pcall(updateAll)
                        if not ok then
                                Logger.warn("esp update failed: " .. tostring(err))
                        end
                end)
                Tracker.track(updateConn, "espupdate")
        end

        function ESPController.stopAll()
                ESPController.setPlayers(false)
                ESPController.options.npcs = false
                ESPController.options.bosses = false
                ESPController.options.questNpcs = false
                ESPController.options.items = false
                scanLoopActive = false
                Tracker.setRunning("npcscan", nil)
                Tracker.cleanup("esp")
                for model in pairs(targets) do
                        removeTarget(model)
                end
        end
end

local ServerController = {}
do
        ServerController.hopMode = "lowest"
        ServerController.COOLDOWN = 5
        ServerController.lowMax = 3
        ServerController.rememberVisited = true

        local lastHopAt = 0
        local visited = {}

        local function loadVisited()
                if not (isfolder and isfile and readfile) then
                        return
                end
                pcall(function()
                        makefolder("PS2Hub")
                        if isfile("PS2Hub/visited.json") then
                                local data = Util.jsonDecode(readfile("PS2Hub/visited.json"))
                                if type(data) == "table" then
                                        for _, id in ipairs(data) do
                                                visited[id] = true
                                        end
                                end
                        end
                end)
        end

        local function saveVisited()
                if not writefile then
                        return
                end
                if not ServerController.rememberVisited then
                        return
                end
                pcall(function()
                        local list = {}
                        for id in pairs(visited) do
                                table.insert(list, id)
                        end
                        writefile("PS2Hub/visited.json", Util.jsonEncode(list) or "[]")
                end)
        end

        local function queueReexecute()
                if queue_on_teleport then
                        pcall(queue_on_teleport, 'loadstring(game:HttpGet("' .. EXECUTE_URL .. '"))()')
                        Logger.info("re-execute queued on teleport")
                else
                        Logger.warn("queue_on_teleport not supported, manual re-execute needed after hop")
                end
        end

        -- games.roblox.com now reports the count in `playing`; `players` became a token array
        local function serverPlayerCount(server)
                if type(server.playing) == "number" then
                        return server.playing
                end
                if type(server.players) == "number" then
                        return server.players
                end
                if type(server.players) == "table" then
                        return #server.players
                end
                return 0
        end

        -- Studio play tests have no teleport token, so client teleports are rejected outright
        local function studioBlocked(feature)
                local isStudio = false
                pcall(function()
                        isStudio = RunService:IsStudio()
                end)
                if isStudio then
                        Util.notify(feature, "Not available in a Studio play test - teleports need a live server")
                        Logger.warn(feature .. " blocked: Studio play test has no teleport token")
                        return true
                end
                return false
        end

        -- one attempt only; TeleportInitFailed surfaces the real engine reason without retries
        local function attemptTeleport(feature, teleportFn)
                local failure = nil
                local conn
                pcall(function()
                        conn = TeleportService.TeleportInitFailed:Connect(function(_, message)
                                failure = tostring(message or "teleport rejected")
                        end)
                end)
                local ok, err = pcall(teleportFn)
                task.wait(0.5)
                if conn then
                        pcall(function()
                                conn:Disconnect()
                        end)
                end
                if failure then
                        Util.notify(feature, "Teleport rejected: " .. failure)
                        Logger.warn(feature .. " teleport failed: " .. failure)
                        return false
                end
                if not ok then
                        Util.notify(feature, "Teleport failed: " .. tostring(err))
                        Logger.warn(feature .. " teleport error: " .. tostring(err))
                        return false
                end
                return true
        end

        function ServerController.rejoin()
                if studioBlocked("Rejoin") then
                        return false
                end
                local placeId = game.PlaceId
                local jobId = game.JobId
                Util.notify("Rejoin", "Rejoining current server...")
                queueReexecute()
                task.wait(0.3)
                return attemptTeleport("Rejoin", function()
                        if jobId ~= "" then
                                TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
                        else
                                TeleportService:Teleport(placeId, LocalPlayer)
                        end
                end)
        end

        local function fetchServers()
                local placeId = game.PlaceId
                local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=2&limit=100"
                local body = Util.httpGet(url)
                local data = Util.jsonDecode(body)
                if not data or not data.data then
                        return nil
                end
                return data.data
        end

        function ServerController.hop(mode)
                mode = mode or ServerController.hopMode
                local now = os.clock()
                if now - lastHopAt < ServerController.COOLDOWN then
                        local waitLeft = Util.round(ServerController.COOLDOWN - (now - lastHopAt), 1)
                        Util.notify("Server Hop", "Cooling down - " .. waitLeft .. "s left")
                        return false
                end
                if studioBlocked("Server Hop") then
                        return false
                end
                lastHopAt = now
                Util.notify("Server Hop", "Looking for a server...")
                local servers = fetchServers()
                if not servers then
                        Util.notify("Server Hop", "Could not fetch the server list")
                        return false
                end
                local best = nil
                local bestCount = 0
                for _, server in ipairs(servers) do
                        local count = serverPlayerCount(server)
                        if server.id ~= game.JobId and count < (server.maxPlayers or 0) then
                                if ServerController.rememberVisited and visited[server.id] then
                                        continue
                                end
                                local skip = false
                                if mode == "lowest" and count > ServerController.lowMax then
                                        skip = true
                                end
                                if not skip then
                                        if mode == "lowest" then
                                                if not best or count < bestCount then
                                                        best = server
                                                        bestCount = count
                                                end
                                        elseif mode == "highest" then
                                                if not best or count > bestCount then
                                                        best = server
                                                        bestCount = count
                                                end
                                        else
                                                best = server
                                                bestCount = count
                                                break
                                        end
                                end
                        end
                end
                if not best then
                        Util.notify("Server Hop", "No joinable server found")
                        return false
                end
                if game.JobId ~= "" then
                        visited[game.JobId] = true
                end
                visited[best.id] = true
                saveVisited()
                Util.notify("Server Hop", "Joining server with " .. bestCount .. " players")
                queueReexecute()
                task.wait(0.3)
                return attemptTeleport("Server Hop", function()
                        TeleportService:TeleportToPlaceInstance(game.PlaceId, best.id, LocalPlayer)
                end)
        end

        function ServerController.setHopMode(mode)
                ServerController.hopMode = mode or "lowest"
        end

        function ServerController.setCooldown(value)
                ServerController.COOLDOWN = math.clamp(value, 0, 120)
        end

        function ServerController.setLowMax(value)
                ServerController.lowMax = math.clamp(value, 1, 100)
        end

        function ServerController.setRememberVisited(enabled)
                ServerController.rememberVisited = enabled and true or false
                if not enabled then
                        visited = {}
                end
        end

        function ServerController.init()
                loadVisited()
        end

        function ServerController.getInfo()
                local ping = Util.getPing()
                return {
                        placeId = game.PlaceId,
                        jobId = game.JobId ~= "" and game.JobId or "Studio",
                        playerCount = #Players:GetPlayers(),
                        maxPlayers = Players.MaxPlayers,
                        ping = ping,
                }
        end
end

local ClanController = {}
do
        ClanController.settings = {
                enabled = false,
                mode = "Spin Once",
                target = "",
                delay = 1.5,
                maxRerolls = 10,
        }
        ClanController.sessionRerolls = 0
        ClanController.lastClan = "Unknown"
        local spinObtained = false
        local watcherArmed = false

        -- Reads the live Clan value from the player data slot
        local function getClanValue()
                local slot = GameProfile.getPlayerSlot()
                if slot == nil then
                        return nil
                end
                local clan = slot:FindFirstChild("Clan")
                if clan and clan:IsA("StringValue") then
                        return clan
                end
                return nil
        end

        local function getSpinsFolder()
                local slot = GameProfile.getPlayerSlot()
                if slot == nil then
                        return nil
                end
                return slot:FindFirstChild("Spinning")
        end

        function ClanController.getCurrentClan()
                if not GameDetector.isGameReady() then
                        return "Locked"
                end
                local value = getClanValue()
                if value then
                        return tostring(value.Value or "Unknown")
                end
                return "Unknown"
        end

        function ClanController.getSpinsText()
                local folder = getSpinsFolder()
                if folder == nil then
                        return "-"
                end
                local spins = folder:FindFirstChild("Spins")
                local free = folder:FindFirstChild("FreeClanSpins")
                local freeOther = folder:FindFirstChild("FreeOtherSpins")
                return tostring(spins and math.floor(spins.Value + 0.5) or 0)
                        .. " spins | " .. tostring(free and math.floor(free.Value + 0.5) or 0) .. " free clan"
                        .. " | " .. tostring(freeOther and math.floor(freeOther.Value + 0.5) or 0) .. " free other"
        end

        function ClanController.getClanOptions()
                local list = GameProfile.get("clans.clanList")
                if type(list) == "table" and #list > 0 then
                        return list
                end
                return { "None loaded" }
        end

        -- Finds the spin button inside the open clan menu (the menu UI is built on demand)
        local function findSpinButton()
                local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
                if playerGui == nil then
                        return nil
                end
                local found = nil
                local scanned = 0
                local function scanContainer(container, depth)
                        if found or depth > 6 or scanned > 2000 then
                                return
                        end
                        for _, child in ipairs(container:GetChildren()) do
                                scanned += 1
                                if child:IsA("GuiButton") then
                                        local label = child.Name
                                        pcall(function()
                                                if child:IsA("TextButton") and child.Text then
                                                        label = child.Text
                                                end
                                        end)
                                        local lower = tostring(label or ""):lower()
                                        if lower:find("spin", 1, true) and not lower:find("spins:", 1, true) then
                                                found = child
                                                return
                                        end
                                end
                                if #child:GetChildren() > 0 then
                                        scanContainer(child, depth + 1)
                                end
                        end
                end
                pcall(scanContainer, playerGui, 1)
                return found
        end

        -- firesignal -> getconnections -> Activate chain covers different executors
        local function triggerButton(button)
                if button == nil then
                        return false
                end
                local fired = false
                if firesignal then
                        local ok = pcall(firesignal, button, "MouseButton1Click")
                        fired = ok
                end
                if not fired and getconnections then
                        local ok, conns = pcall(getconnections, button.MouseButton1Click)
                        if ok and type(conns) == "table" then
                                for _, conn in ipairs(conns) do
                                        pcall(function()
                                                conn:Fire()
                                        end)
                                end
                                fired = #conns > 0
                        end
                end
                if not fired then
                        pcall(function()
                                button:Activate()
                        end)
                        fired = true
                end
                return fired
        end

        function ClanController.doReroll()
                if not GameDetector.requireGame("Auto Spin Clan") then
                        return nil
                end
                local button = findSpinButton()
                if button == nil then
                        Util.notify("Auto Spin Clan", "Open the clan spin menu in-game first", 5)
                        return nil
                end
                if not triggerButton(button) then
                        Util.notify("Auto Spin Clan", "Spin button could not be fired")
                        return nil
                end
                ClanController.sessionRerolls += 1
                task.wait(ClanController.settings.delay)
                return ClanController.getCurrentClan()
        end

        local rerollLoopActive = false

        -- Stops the Spin Until Target loop after the watcher confirms the desired clan
        local function markObtained(clanName)
                if spinObtained then
                        return
                end
                spinObtained = true
                Util.notify("Auto Spin Clan", "Desired clan obtained: " .. tostring(clanName), 6)
                WebhookController.notifyClanObtained(clanName, ClanController.sessionRerolls)
                if ClanController.settings.enabled and ClanController.settings.mode == "Spin Until Target" then
                        ClanController.setEnabled(false)
                end
        end

        function ClanController.setEnabled(enabled)
                local want = enabled and true or false
                if ClanController.settings.enabled == want then
                        return want
                end
                if enabled then
                        if not GameDetector.requireGame("Auto Spin Clan") then
                                return false
                        end
                        ClanController.settings.enabled = true
                        spinObtained = false
                        Tracker.setRunning("clan", true)
                        if ClanController.settings.mode == "Spin Until Target" then
                                if ClanController.settings.target == "" then
                                        Util.notify("Auto Spin Clan", "Pick a Desired Clan first", 5)
                                        ClanController.settings.enabled = false
                                        Tracker.setRunning("clan", false)
                                        return false
                                end
                                rerollLoopActive = true
                                task.spawn(function()
                                        local attempts = 0
                                        while rerollLoopActive and Tracker.isRunning("clan") and not spinObtained do
                                                if attempts >= ClanController.settings.maxRerolls then
                                                        Util.notify("Auto Spin Clan", "Spin limit reached (" .. attempts .. ")")
                                                        break
                                                end
                                                attempts += 1
                                                local result = ClanController.doReroll()
                                                if result == nil then
                                                        task.wait(2)
                                                end
                                                task.wait(0.2)
                                        end
                                        rerollLoopActive = false
                                        if ClanController.settings.enabled then
                                                ClanController.setEnabled(false)
                                        end
                                end)
                        elseif ClanController.settings.mode == "Fixed Count" then
                                rerollLoopActive = true
                                task.spawn(function()
                                        local attempts = 0
                                        while rerollLoopActive and Tracker.isRunning("clan") and attempts < ClanController.settings.maxRerolls do
                                                attempts += 1
                                                ClanController.doReroll()
                                                if ClanController.settings.target ~= "" and spinObtained then
                                                        break
                                                end
                                        end
                                        rerollLoopActive = false
                                        Util.notify("Auto Spin Clan", "Done - " .. attempts .. " spin(s)")
                                        if ClanController.settings.enabled then
                                                ClanController.setEnabled(false)
                                        end
                                end)
                        else
                                task.spawn(function()
                                        ClanController.doReroll()
                                        if ClanController.settings.enabled then
                                                ClanController.setEnabled(false)
                                        end
                                end)
                        end
                        return true
                else
                        ClanController.settings.enabled = false
                        rerollLoopActive = false
                        Tracker.setRunning("clan", false)
                        return true
                end
        end

        function ClanController.setMode(mode)
                local value = mode or "Spin Once"
                if value == "Reroll Once" then
                        value = "Spin Once"
                elseif value == "Reroll Until Target" then
                        value = "Spin Until Target"
                end
                ClanController.settings.mode = value
        end

        function ClanController.setTarget(clan)
                ClanController.settings.target = clan or ""
        end

        function ClanController.setDelay(value)
                ClanController.settings.delay = value
        end

        function ClanController.setMaxRerolls(value)
                ClanController.settings.maxRerolls = math.clamp(value, 1, 500)
        end

        function ClanController.rerollOnce()
                if not GameDetector.requireGame("Auto Spin Clan") then
                        return false, "Open Project Slayers 2"
                end
                local result = ClanController.doReroll()
                if result == nil then
                        return false, "Open the clan spin menu first"
                end
                return true, result
        end

        function ClanController.getStatusText()
                if GameDetector.isGameReady() then
                        return "Current clan: " .. ClanController.getCurrentClan()
                                .. " | " .. ClanController.getSpinsText()
                                .. " | Spins this session: " .. tostring(ClanController.sessionRerolls)
                end
                return "Open Project Slayers 2 to use clan features. Spins this session: " .. tostring(ClanController.sessionRerolls)
        end

        -- Arms the clan change watcher: updates status and fires the webhook on the desired clan
        GameProfile.onLoad(function()
                if watcherArmed then
                        return
                end
                watcherArmed = true
                task.spawn(function()
                        local attempts = 0
                        while attempts < 30 do
                                attempts += 1
                                local value = getClanValue()
                                if value then
                                        ClanController.lastClan = tostring(value.Value or "Unknown")
                                        local ok = pcall(function()
                                                local conn = value:GetPropertyChangedSignal("Value"):Connect(function()
                                                        local newClan = tostring(value.Value or "Unknown")
                                                        Logger.info("clan changed: " .. tostring(ClanController.lastClan) .. " -> " .. newClan)
                                                        ClanController.lastClan = newClan
                                                        if ClanController.settings.target ~= "" and newClan == ClanController.settings.target then
                                                                markObtained(newClan)
                                                        end
                                                end)
                                                Tracker.track(conn, "clanwatch")
                                        end)
                                        if ok then
                                                Logger.info("clan watcher armed on the player data slot")
                                                return
                                        end
                                end
                                task.wait(1)
                        end
                end)
        end)
end

-- forward declarations: AutomationController debug utilities read the detectors
local QuestDetector

local AutomationController = {}
do
        AutomationController.settings = {
                target = "",
                exclusions = {},
                maxRange = 2000,
                interactMode = "Auto",
                interactDelay = 0.5,
                interactRange = 10,
                autoAttack = false,
                attackDelay = 0.35,
                scanInterval = 2,
                tickInterval = 0.25,
        }
        AutomationController.lastTargetName = ""
        AutomationController.lastTargetHealthPct = 0

        function AutomationController.setTarget(name)
                AutomationController.settings.target = name or ""
        end

        function AutomationController.setExclusions(selected)
                local list = {}
                if type(selected) == "table" then
                        for _, name in ipairs(selected) do
                                if name and name ~= "" then
                                        table.insert(list, name)
                                end
                        end
                end
                AutomationController.settings.exclusions = list
        end

        function AutomationController.setMaxRange(value)
                AutomationController.settings.maxRange = value
        end

        function AutomationController.setInteractMode(mode)
                AutomationController.settings.interactMode = mode or "Auto"
        end

        function AutomationController.setInteractDelay(value)
                AutomationController.settings.interactDelay = value
        end

        function AutomationController.setInteractRange(value)
                AutomationController.settings.interactRange = value
        end

        function AutomationController.setScanInterval(value)
                AutomationController.settings.scanInterval = math.max(value, 0.5)
        end

        function AutomationController.setTickInterval(value)
                AutomationController.settings.tickInterval = math.max(value, 0.05)
        end

        function AutomationController.setAutoAttack(enabled)
                AutomationController.settings.autoAttack = enabled and true or false
        end

        function AutomationController.setAttackDelay(value)
                AutomationController.settings.attackDelay = value
        end

        function AutomationController.getStatusText()
                if not GameDetector.isGameReady() then
                        return "Automation locked - open Project Slayers 2"
                end
                return "Automation ready"
        end

        -- Returns the currently equipped data slot for the local player
        function AutomationController.getSlot()
                return GameProfile.getPlayerSlot()
        end

        -- Scans live mobs. The game keeps every live npc under
        -- Humanoids/Regions/<Region>/ActiveNpcs/<Npc>/<Model>, so the registry is walked
        -- directly; a deeper generic Workspace scan only serves as a fallback.
        function AutomationController.scanMobModels(matchFn)
                local found = {}
                local scanned = 0
                local exclusions = {}
                for _, name in ipairs(AutomationController.settings.exclusions) do
                        exclusions[name:lower()] = true
                end
                local function tryModel(model, displayName)
                        if not model:IsA("Model") then
                                return
                        end
                        if Players:GetPlayerFromCharacter(model) then
                                return
                        end
                        local humanoid = model:FindFirstChildOfClass("Humanoid")
                        if not humanoid or humanoid.Health <= 0 then
                                return
                        end
                        if exclusions[displayName:lower()] then
                                return
                        end
                        if matchFn ~= nil and not matchFn(displayName) and not matchFn(model.Name) then
                                return
                        end
                        local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                        if root == nil then
                                for _, d in ipairs(model:GetDescendants()) do
                                        if d:IsA("BasePart") then
                                                root = d
                                                break
                                        end
                                end
                        end
                        if root == nil then
                                return
                        end
                        table.insert(found, {
                                model = model,
                                humanoid = humanoid,
                                root = root,
                                name = displayName ~= "" and displayName or model.Name,
                                dist = Util.distanceTo(root),
                                healthPct = humanoid.MaxHealth > 0 and (humanoid.Health / humanoid.MaxHealth * 100) or 0,
                        })
                end

                -- primary: the replicated npc registry
                local regions = Workspace:FindFirstChild("Humanoids")
                regions = regions and regions:FindFirstChild("Regions")
                if regions then
                        for _, region in ipairs(regions:GetChildren()) do
                                local active = region:FindFirstChild("ActiveNpcs")
                                if active then
                                        for _, npcFolder in ipairs(active:GetChildren()) do
                                                scanned += 1
                                                for _, child in ipairs(npcFolder:GetChildren()) do
                                                        if child:IsA("Model") then
                                                                tryModel(child, npcFolder.Name)
                                                        end
                                                end
                                        end
                                end
                        end
                end

                -- fallback: deep generic scan for models outside the registry
                local seen = {}
                for _, entry in ipairs(found) do
                        seen[entry.model] = true
                end
                local function scanContainer(container, depth)
                        if depth > 7 or scanned > 2500 then
                                return
                        end
                        for _, child in ipairs(container:GetChildren()) do
                                scanned += 1
                                if child:IsA("Model") then
                                        if not seen[child] then
                                                seen[child] = true
                                                tryModel(child, child.Name)
                                        end
                                        scanContainer(child, depth + 1)
                                elseif child:IsA("Folder") then
                                        scanContainer(child, depth + 1)
                                end
                        end
                end
                pcall(scanContainer, Workspace, 1)
                table.sort(found, function(a, b)
                        return a.dist < b.dist
                end)
                return found
        end

        -- Keyword matcher built from quest/task/boss words (e.g. "Bandits remaining" -> "bandit")
        function AutomationController.makeKeywordMatcher(words)
                local lowered = {}
                for _, word in ipairs(words) do
                        local w = tostring(word or ""):lower()
                        w = w:gsub("%s+", "")
                        w = w:gsub("s$", "")
                        if #w >= 3 then
                                table.insert(lowered, w)
                        end
                end
                return function(name)
                        if name == nil then
                                return false
                        end
                        local n = tostring(name):lower():gsub("%s+", "")
                        for _, w in ipairs(lowered) do
                                if n:sub(1, #w) == w or n:find(w, 1, true) then
                                        return true
                                end
                        end
                        return false
                end
        end

        function AutomationController.makeMobMatcher()
                -- matches the mob patterns from the game profile
                local patterns = GameProfile.get("mobs.patterns") or {}
                return function(name)
                        if name == nil then
                                return false
                        end
                        local n = tostring(name):lower()
                        for _, pattern in ipairs(patterns) do
                                if n:find(tostring(pattern):lower(), 1, true) then
                                        return true
                                end
                        end
                        return false
                end
        end

        -- All automation travel routes through the shared MovementHandler (Instant or Tween only);
        -- the owner tag keeps parallel engines from stopping each other's movement
        function AutomationController.moveTo(targetModel, owner)
                AutomationController.stopMovement(owner)
                local ok = MovementHandler.follow(targetModel, owner)
                if ok then
                        Tracker.setRunning("automove", true)
                end
                return ok
        end

        function AutomationController.stopMovement(owner)
                Tracker.setRunning("automove", false)
                MovementHandler.stop(owner)
        end

        -- Fires the nearest interaction prompt on a model (quest givers, crystals)
        function AutomationController.interactWith(model)
                if model == nil then
                        return false
                end
                local prompt
                pcall(function()
                        prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true)
                end)
                if prompt == nil then
                        return false
                end
                if fireproximityprompt then
                        local ok = pcall(fireproximityprompt, prompt)
                        if ok then
                                return true
                        end
                end
                pcall(function()
                        prompt:InputHoldBegin()
                        task.wait(0.1)
                        prompt:InputHoldEnd()
                end)
                return true
        end

        -- The accept choice inside a dialogue window (PlayerGui scan, same trick as the
        -- clan spin button: the UI is built on demand so it is not in the place file)
        local function findDialogueButton()
                local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
                if playerGui == nil then
                        return nil
                end
                local positive = { accept = true, quest = true, yes = true, sure = true, okay = true, ok = true, continue = true, take = true, help = true, talk = true }
                local negative = { decline = true, cancel = true, no = true, later = true, close = true, goodbye = true, bye = true, exit = true, shop = true, sell = true, buy = true, leave = true }
                local found = nil
                local scanned = 0
                local function scanContainer(container, depth)
                        if found or depth > 7 or scanned > 2500 then
                                return
                        end
                        for _, child in ipairs(container:GetChildren()) do
                                scanned += 1
                                if child:IsA("GuiButton") then
                                        local label = child.Name
                                        pcall(function()
                                                if child:IsA("TextButton") and child.Text then
                                                        label = child.Text
                                                end
                                        end)
                                        local lower = tostring(label or ""):lower()
                                        local hit = false
                                        for word in string.gmatch(lower, "%a+") do
                                                if negative[word] then
                                                        hit = false
                                                        break
                                                end
                                                if positive[word] then
                                                        hit = true
                                                end
                                        end
                                        if hit then
                                                found = child
                                                return
                                        end
                                end
                                if #child:GetChildren() > 0 then
                                        scanContainer(child, depth + 1)
                                end
                        end
                end
                pcall(scanContainer, playerGui, 1)
                return found
        end

        -- firesignal -> getconnections -> Activate chain covers different executors
        local function fireGuiButton(button)
                if button == nil then
                        return false
                end
                local fired = false
                if firesignal then
                        local ok = pcall(firesignal, button, "MouseButton1Click")
                        fired = ok
                end
                if not fired and getconnections then
                        local ok, conns = pcall(getconnections, button.MouseButton1Click)
                        if ok and type(conns) == "table" then
                                for _, conn in ipairs(conns) do
                                        pcall(function()
                                                conn:Fire()
                                        end)
                                end
                                fired = #conns > 0
                        end
                end
                if not fired then
                        pcall(function()
                                button:Activate()
                        end)
                        fired = true
                end
                return fired
        end

        -- Opens the quest dialogue (prompt) and tries to press its accept button
        function AutomationController.tryDialogueAccept(giverModel)
                if giverModel ~= nil then
                        AutomationController.interactWith(giverModel)
                        task.wait(0.4)
                end
                local button = findDialogueButton()
                if button == nil then
                        return false
                end
                return fireGuiButton(button)
        end

        function AutomationController.scanQuestSystem()
                -- quest givers via the replicated dialogue registry + stationary scan
                local givers = {}
                pcall(function()
                        for _, giver in ipairs(QuestDetector.findQuestGivers()) do
                                local path = giver.name
                                pcall(function()
                                        path = giver.model:GetFullName()
                                end)
                                table.insert(givers, { name = giver.name, path = path })
                        end
                end)
                -- live quest state from the player data slot
                local quest = QuestDetector.getActiveQuest()
                local active = "none"
                if quest then
                        active = quest.name
                end
                local progress = ""
                local done, needed = QuestDetector.getQuestProgress(quest)
                if done ~= nil then
                        progress = " (" .. done .. "/" .. needed .. ")"
                end
                Logger.info("quest scan: " .. #givers .. " giver(s), active quest: " .. active .. progress)
                for i, giver in ipairs(givers) do
                        if i <= 15 then
                                Logger.info("  giver " .. string.format("%02d", i) .. ": " .. giver.name .. "  path=" .. giver.path)
                        end
                end
                local summary = #givers .. " giver(s), active: " .. active .. progress .. " - details in the log console"
                Util.notify("Quest Scan", summary, 6)
                return summary
        end
end

QuestDetector = {}
do
        QuestDetector.status = "Idle"

        local function getHolder()
                local slot = AutomationController.getSlot()
                if slot == nil then
                        return nil
                end
                local quests = slot:FindFirstChild("Quests")
                return quests and quests:FindFirstChild("Holder")
        end

        function QuestDetector.getPlayerLevel()
                local slot = AutomationController.getSlot()
                if slot == nil then
                        return nil
                end
                local exp = slot:FindFirstChild("Exp")
                local current = exp and exp:FindFirstChild("Current")
                local goal = exp and exp:FindFirstChild("Goal")
                if current and goal and goal.Value > 0 then
                        return math.floor(current.Value / goal.Value * 100)
                end
                return nil
        end

        -- Quest definitions live as modules under ReplicatedStorage/QuestStates
        function QuestDetector.getQuestOptions()
                local list = {}
                local defs = GameProfile.resolvePath(GameProfile.get("quests.definitions") or "")
                if defs then
                        pcall(function()
                                for _, child in ipairs(defs:GetChildren()) do
                                        if child:IsA("ModuleScript") and child.Name ~= "" then
                                                table.insert(list, child.Name)
                                        end
                                end
                        end)
                end
                table.sort(list)
                return list
        end

        -- Reads the live quest from the data slot holder (newest entry wins: repeated
        -- accepts leave older configs behind, and children are insertion-ordered)
        function QuestDetector.getActiveQuest()
                local holder = getHolder()
                if holder == nil then
                        return nil
                end
                local children = holder:GetChildren()
                local questConfig = children[#children]
                if questConfig == nil then
                        return nil
                end
                local quest = { name = questConfig.Name, questString = "", tasks = {} }
                pcall(function()
                        local qs = questConfig:FindFirstChild("QuestString")
                        if qs then
                                quest.questString = tostring(qs.Value or "")
                        end
                end)
                pcall(function()
                        local tasks = questConfig:FindFirstChild("Tasks")
                        if tasks then
                                for _, taskConfig in ipairs(tasks:GetChildren()) do
                                        local taskEntry = { name = taskConfig.Name, code = "", value = nil, max = nil }
                                        local code = taskConfig:FindFirstChild("Code")
                                        if code then
                                                taskEntry.code = tostring(code.Value or "")
                                        end
                                        local value = taskConfig:FindFirstChild("Value")
                                        if value and type(value.Value) == "number" then
                                                taskEntry.value = value.Value
                                        end
                                        local max = taskConfig:FindFirstChild("Max")
                                        if max and type(max.Value) == "number" then
                                                taskEntry.max = max.Value
                                        end
                                        table.insert(quest.tasks, taskEntry)
                                end
                        end
                end)
                return quest
        end

        -- Sums task progress; nil when the game exposes no counters for the quest
        function QuestDetector.getQuestProgress(quest)
                if quest == nil then
                        return nil
                end
                local done, needed = 0, 0
                local readable = false
                for _, taskEntry in ipairs(quest.tasks or {}) do
                        if taskEntry.value ~= nil and taskEntry.max ~= nil then
                                readable = true
                                done += taskEntry.value
                                needed += taskEntry.max
                        end
                end
                if not readable then
                        return nil
                end
                return done, needed
        end

        function QuestDetector.hasQuestData()
                return GameDetector.isGameReady()
        end

        -- Quest giver names are replicated under Ouwland/Content/<Region>/NpcContents/Dialogues/Quests
        function QuestDetector.getQuestGiverNames()
                local names = {}
                local content = GameProfile.resolvePath(GameProfile.get("quests.giverNames") or "")
                if content == nil then
                        return names
                end
                pcall(function()
                        for _, region in ipairs(content:GetChildren()) do
                                local npcContents = region:FindFirstChild("NpcContents")
                                local dialogues = npcContents and npcContents:FindFirstChild("Dialogues")
                                local quests = dialogues and dialogues:FindFirstChild("Quests")
                                if quests then
                                        for _, giver in ipairs(quests:GetChildren()) do
                                                if giver.Name ~= "" and not names[giver.Name] then
                                                        names[giver.Name] = true
                                                end
                                        end
                                end
                        end
                end)
                local list = {}
                for name in pairs(names) do
                        table.insert(list, name)
                end
                table.sort(list)
                return list
        end

        -- Finds live quest giver models: stationary registry first, then any matching
        -- model in Workspace that carries an interaction prompt
        function QuestDetector.findQuestGivers()
                local givers = {}
                local wanted = {}
                for _, name in ipairs(QuestDetector.getQuestGiverNames()) do
                        wanted[name:lower()] = true
                end
                if next(wanted) == nil then
                        return givers
                end
                local function addIfGiver(model)
                        if model:IsA("Model") and wanted[model.Name:lower()] then
                                local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
                                if root then
                                        table.insert(givers, { name = model.Name, model = model, dist = Util.distanceTo(root) })
                                end
                        end
                end
                local regions = GameProfile.resolvePath(GameProfile.get("npcs.stationaryScan") or "")
                if regions then
                        pcall(function()
                                for _, region in ipairs(regions:GetChildren()) do
                                        local npcs = region:FindFirstChild("StationaryNpcs")
                                        if npcs then
                                                for _, npc in ipairs(npcs:GetChildren()) do
                                                        addIfGiver(npc)
                                                end
                                        end
                                end
                        end)
                end
                if #givers == 0 then
                        -- quest giver models can also spawn outside the stationary folders
                        local function scanContainer(container, depth)
                                if depth > 7 then
                                        return
                                end
                                for _, child in ipairs(container:GetChildren()) do
                                        addIfGiver(child)
                                        if #givers > 0 then
                                                break
                                        end
                                        scanContainer(child, depth + 1)
                                end
                        end
                        pcall(scanContainer, Workspace, 1)
                end
                table.sort(givers, function(a, b)
                        return a.dist < b.dist
                end)
                return givers
        end
end

local BossDetector = {}
do
        BossDetector.status = "Idle"

        -- Live boss registry: ActiveNpcs folders that carry a BossInfo child.
        -- Includes the live model + distance so Auto mode can pick the nearest boss.
        function BossDetector.scanBossFolders()
                local bosses = {}
                local regions = GameProfile.resolvePath(GameProfile.get("npcs.activeScan") or "")
                if regions == nil then
                        return bosses
                end
                local marker = GameProfile.get("npcs.bossMarker") or "BossInfo"
                pcall(function()
                        for _, region in ipairs(regions:GetChildren()) do
                                local active = region:FindFirstChild("ActiveNpcs")
                                if active then
                                        for _, npc in ipairs(active:GetChildren()) do
                                                if npc:FindFirstChild(marker) then
                                                        local model = nil
                                                        local dist = nil
                                                        for _, child in ipairs(npc:GetChildren()) do
                                                                if child:IsA("Model") then
                                                                        model = child
                                                                        local root = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
                                                                        if root then
                                                                                dist = Util.distanceTo(root)
                                                                        end
                                                                        break
                                                                end
                                                        end
                                                        table.insert(bosses, {
                                                                name = npc.Name,
                                                                folder = npc,
                                                                model = model,
                                                                dist = dist or math.huge,
                                                                region = region.Name,
                                                        })
                                                end
                                        end
                                end
                        end
                end)
                table.sort(bosses, function(a, b)
                        return (a.dist or math.huge) < (b.dist or math.huge)
                end)
                return bosses
        end

        function BossDetector.getBossOptions()
                local list = { "Auto" }
                local seen = { Auto = true }
                for _, name in ipairs(BossDetector.scanBossFolders()) do
                        if not seen[name.name] then
                                seen[name.name] = true
                                table.insert(list, name.name)
                        end
                end
                for _, name in ipairs(GameProfile.get("bosses.known") or {}) do
                        if not seen[name] then
                                seen[name] = true
                                table.insert(list, name)
                        end
                end
                return list
        end

        function BossDetector.hasBossData()
                return GameDetector.isGameReady()
        end

        function BossDetector.scan()
                local folders = BossDetector.scanBossFolders()
                if #folders == 0 then
                        return {}
                end
                local words = {}
                for _, f in ipairs(folders) do
                        table.insert(words, f.name)
                end
                local matcher = AutomationController.makeKeywordMatcher(words)
                return AutomationController.scanMobModels(matcher)
        end

        -- Confirmed kills come from the game's own archive list (Archives/Bosses on the slot)
        function BossDetector.isArchived(bossName)
                local slot = AutomationController.getSlot()
                if slot == nil then
                        return false
                end
                local archives = slot:FindFirstChild("Archives")
                local bosses = archives and archives:FindFirstChild("Bosses")
                if bosses == nil or not bosses:IsA("StringValue") then
                        return false
                end
                local wanted = tostring(bossName or ""):lower()
                for name in tostring(bosses.Value or ""):gmatch("[^,]+") do
                        if Util.trim(name):lower() == wanted then
                                return true
                        end
                end
                return false
        end
end

local SpiderLilyDetector = {}
do
        SpiderLilyDetector.status = "Idle"

        function SpiderLilyDetector.hasSpiderLilyData()
                return GameDetector.isGameReady()
        end

        -- Spider Lilies spawn as named models directly under Workspace
        function SpiderLilyDetector.scan()
                local lilies = {}
                local wanted = (GameProfile.get("spiderLilies.workspaceName") or "Spider Lily"):lower()
                pcall(function()
                        local function scanContainer(container, depth)
                                if depth > 2 then
                                        return
                                end
                                for _, child in ipairs(container:GetChildren()) do
                                        if child:IsA("Model") and child.Name:lower() == wanted then
                                                local root = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
                                                if root == nil then
                                                        for _, d in ipairs(child:GetDescendants()) do
                                                                if d:IsA("BasePart") then
                                                                        root = d
                                                                        break
                                                                end
                                                        end
                                                end
                                                if root then
                                                        table.insert(lilies, { model = child, root = root, dist = Util.distanceTo(root) })
                                                end
                                        end
                                        if child:IsA("Folder") or child:IsA("Model") then
                                                scanContainer(child, depth + 1)
                                        end
                                end
                        end
                        scanContainer(Workspace, 1)
                end)
                table.sort(lilies, function(a, b)
                        return a.dist < b.dist
                end)
                return lilies
        end

        function SpiderLilyDetector.getDetectedCount()
                return #SpiderLilyDetector.scan()
        end
end

local CombatHandler = {}
do
        CombatHandler.questMethod = "Melee"
        CombatHandler.bossMethod = "Melee"
        local combatNotified = false
        local lastSwing = 0

        local function validMethod(method)
                return method == "Melee" or method == "Sword"
        end

        function CombatHandler.setQuestMethod(method)
                if validMethod(method) then
                        CombatHandler.questMethod = method
                end
                return CombatHandler.questMethod
        end

        function CombatHandler.setBossMethod(method)
                if validMethod(method) then
                        CombatHandler.bossMethod = method
                end
                return CombatHandler.bossMethod
        end

        local function ensureWeapon()
                local humanoid = Util.getHumanoid()
                if humanoid == nil then
                        return nil
                end
                local tool = Util.getEquippedTool()
                if tool then
                        return tool
                end
                -- equip the selected tool, or fall back to the first weapon in the backpack
                if ToolController.selected ~= "" then
                        ToolController.equipSelected()
                        tool = Util.getEquippedTool()
                end
                if tool == nil then
                        local backpack = Util.getBackpack()
                        if backpack then
                                for _, t in ipairs(backpack:GetChildren()) do
                                        if t:IsA("Tool") then
                                                pcall(function()
                                                        humanoid:EquipTool(t)
                                                end)
                                                task.wait(0.1)
                                                tool = Util.getEquippedTool()
                                                break
                                        end
                                end
                        end
                end
                return tool
        end

        local function swingMouse()
                local camera = Workspace.CurrentCamera
                local x, y = 960, 540
                if camera and camera.ViewportSize then
                        x = camera.ViewportSize.X / 2
                        y = camera.ViewportSize.Y / 2
                end
                local ok = pcall(function()
                        local vim = GetService("VirtualInputManager")
                        vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
                        task.wait(0.05)
                        vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
                end)
                return ok
        end

        -- method "Melee" fights bare-handed (unequips so fists swing), "Sword" swings a tool.
        -- Both use the game's real input path: tool Activate + a center-screen click.
        function CombatHandler.attack(target, method)
                if target == nil then
                        return false
                end
                if not GameDetector.isGameReady() then
                        return false
                end
                local now = os.clock()
                if now - lastSwing < 0.1 then
                        return false
                end
                lastSwing = now
                if method ~= "Sword" then
                        -- Melee: fists, so nothing may stay equipped
                        local humanoid = Util.getHumanoid()
                        if humanoid then
                                pcall(function()
                                        humanoid:UnequipTools()
                                end)
                        end
                        swingMouse()
                        return true
                end
                local tool = ensureWeapon()
                if tool == nil then
                        if not combatNotified then
                                combatNotified = true
                                Logger.warn("no weapon found in backpack - equip a weapon for combat")
                                Util.notify("Combat", "No weapon found - equip one or pick it under Main > Targets")
                        end
                        return false
                end
                pcall(function()
                        tool:Activate()
                end)
                swingMouse()
                return true
        end
end

local AutoQuestController = {}
do
        AutoQuestController.STATUS_STATES = {
                "Disabled",
                "Searching for Quest",
                "Quest Found",
                "Quest Active",
                "Completing Quest",
                "No Suitable Quest Found",
        }
        AutoQuestController.settings = {
                enabled = false,
                selectedQuest = "Auto Detect",
                autoDetect = true,
                autoAccept = true,
                autoTurnIn = true,
        }
        AutoQuestController.status = {
                state = "Disabled",
                quest = "None",
                target = "None",
                progress = "-",
                healthPct = 0,
        }
        AutoQuestController.currentTarget = nil

        local function validState(state)
                for _, known in ipairs(AutoQuestController.STATUS_STATES) do
                        if known == state then
                                return true
                        end
                end
                return false
        end

        function AutoQuestController.setState(state)
                if validState(state) then
                        AutoQuestController.status.state = state
                end
                return AutoQuestController.status.state
        end

        function AutoQuestController.resetStatus()
                AutoQuestController.status.state = "Disabled"
                AutoQuestController.status.quest = "None"
                AutoQuestController.status.target = "None"
                AutoQuestController.status.progress = "-"
                AutoQuestController.status.healthPct = 0
                AutoQuestController.currentTarget = nil
        end

        local function questKeywords(quest)
                local words = {}
                if quest then
                        for word in quest.name:gmatch("%a+") do
                                table.insert(words, word)
                        end
                        for _, taskEntry in ipairs(quest.tasks or {}) do
                                for word in tostring(taskEntry.name):gmatch("%a+") do
                                        table.insert(words, word)
                                end
                                -- the task Code (e.g. KaruVillageBandit) names the exact mob type
                                for word in tostring(taskEntry.code or ""):gmatch("%u%l+") do
                                        table.insert(words, word)
                                end
                        end
                end
                return words
        end

        -- Full cycle: accept at the giver, hunt the objective, turn in when the counters fill
        local function autoQuestLoop()
                local lastQuestName = nil
                local lastNoticeAt = 0
                while Tracker.isRunning("autoquest") do
                        task.wait(math.max(AutomationController.settings.tickInterval, 0.25))
                        local quest = QuestDetector.getActiveQuest()
                        if quest == nil then
                                -- Phase 1: no active quest -> travel to the nearest giver and accept
                                AutoQuestController.setState("Searching for Quest")
                                AutoQuestController.status.quest = "None"
                                AutoQuestController.status.target = "None"
                                AutoQuestController.status.progress = "-"
                                AutoQuestController.currentTarget = nil
                                if not AutoQuestController.settings.autoAccept then
                                        AutomationController.stopMovement("autoquest")
                                else
                                        local givers = QuestDetector.findQuestGivers()
                                        if #givers == 0 then
                                                AutoQuestController.setState("No Suitable Quest Found")
                                                AutomationController.stopMovement("autoquest")
                                        else
                                                local giver = givers[1]
                                                AutoQuestController.status.target = giver.name .. " (accepting)"
                                                AutomationController.moveTo(giver.model, "autoquest")
                                                local root = Util.getRoot()
                                                local giverRoot = nil
                                                pcall(function()
                                                        giverRoot = giver.model:FindFirstChild("HumanoidRootPart") or giver.model.PrimaryPart
                                                end)
                                                local close = root and giverRoot
                                                        and (giverRoot.Position - root.Position).Magnitude <= 12
                                                if close then
                                                        AutomationController.stopMovement("autoquest")
                                                        local ok = AutomationController.tryDialogueAccept(giver.model)
                                                        local now = os.clock()
                                                        if not ok and now - lastNoticeAt > 15 then
                                                                lastNoticeAt = now
                                                                Util.notify("Auto Quest", "Dialogue opened at " .. giver.name .. " - accept manually if it needs you", 5)
                                                        end
                                                end
                                        end
                                end
                        else
                                if lastQuestName ~= quest.name then
                                        lastQuestName = quest.name
                                        Util.notify("Auto Quest", "Quest active: " .. quest.name, 4)
                                end
                                AutoQuestController.setState("Quest Active")
                                AutoQuestController.status.quest = quest.name
                                local done, needed = QuestDetector.getQuestProgress(quest)
                                if done ~= nil then
                                        AutoQuestController.status.progress = done .. "/" .. needed
                                else
                                        AutoQuestController.status.progress = "-"
                                end
                                if done ~= nil and needed > 0 and done >= needed then
                                        -- Phase 3: counters full -> turn the quest back in at the giver
                                        AutoQuestController.setState("Completing Quest")
                                        AutoQuestController.status.target = "Turning in " .. quest.name
                                        AutoQuestController.currentTarget = nil
                                        AutomationController.stopMovement("autoquest")
                                        if AutoQuestController.settings.autoTurnIn then
                                                local givers = QuestDetector.findQuestGivers()
                                                if #givers > 0 then
                                                        local giver = givers[1]
                                                        AutomationController.moveTo(giver.model, "autoquest")
                                                        local root = Util.getRoot()
                                                        local giverRoot = nil
                                                        pcall(function()
                                                                giverRoot = giver.model:FindFirstChild("HumanoidRootPart") or giver.model.PrimaryPart
                                                        end)
                                                        if root and giverRoot and (giverRoot.Position - root.Position).Magnitude <= 12 then
                                                                AutomationController.stopMovement("autoquest")
                                                                AutomationController.interactWith(giver.model)
                                                                AutomationController.tryDialogueAccept(giver.model)
                                                        end
                                                end
                                        end
                                else
                                        -- Phase 2: hunt the objective mobs
                                        local matcher = AutomationController.makeKeywordMatcher(questKeywords(quest))
                                        local mobs = AutomationController.scanMobModels(matcher)
                                        if #mobs == 0 then
                                                AutoQuestController.status.target = "No targets nearby"
                                                AutoQuestController.status.healthPct = 0
                                                AutoQuestController.currentTarget = nil
                                                AutomationController.stopMovement("autoquest")
                                        else
                                                local mob = mobs[1]
                                                AutoQuestController.currentTarget = mob.model
                                                AutoQuestController.status.target = mob.name
                                                AutoQuestController.status.healthPct = mob.healthPct
                                                if AutomationController.settings.autoAttack then
                                                        AutomationController.moveTo(mob.model, "autoquest")
                                                        CombatHandler.attack(mob.model, CombatHandler.questMethod)
                                                end
                                        end
                                end
                        end
                end
        end

        function AutoQuestController.setEnabled(enabled)
                local want = enabled and true or false
                if AutoQuestController.settings.enabled == want then
                        return want
                end
                if enabled then
                        if not GameDetector.requireGame("Auto Quest") then
                                return false
                        end
                        AutoQuestController.settings.enabled = true
                        AutoQuestController.setState("Searching for Quest")
                        Tracker.setRunning("autoquest", true)
                        task.spawn(autoQuestLoop)
                        return true
                end
                AutoQuestController.settings.enabled = false
                Tracker.setRunning("autoquest", false)
                AutomationController.stopMovement("autoquest")
                AutoQuestController.resetStatus()
                return true
        end

        function AutoQuestController.setQuest(name)
                AutoQuestController.settings.selectedQuest = name or "Auto Detect"
        end

        function AutoQuestController.setAutoDetect(enabled)
                AutoQuestController.settings.autoDetect = enabled and true or false
        end

        function AutoQuestController.setAutoAccept(enabled)
                AutoQuestController.settings.autoAccept = enabled and true or false
        end

        function AutoQuestController.setAutoTurnIn(enabled)
                AutoQuestController.settings.autoTurnIn = enabled and true or false
        end

        function AutoQuestController.getTargetModel()
                return AutoQuestController.currentTarget
        end

        function AutoQuestController.getStatusText()
                return AutoQuestController.status.state
        end

        function AutoQuestController.getQuestText()
                return AutoQuestController.status.quest
        end

        function AutoQuestController.getTargetText()
                return AutoQuestController.status.target
        end

        function AutoQuestController.getProgressText()
                return AutoQuestController.status.progress
        end

        function AutoQuestController.getTargetHealthPct()
                return AutoQuestController.status.healthPct or 0
        end
end

local AutoDemonController = {}
do
        AutoDemonController.STATUS_STATES = {
                "Disabled",
                "Detecting Spider Lilies",
                "Collecting Spider Lily",
                "No Spider Lilies Found",
        }
        AutoDemonController.settings = {
                enabled = false,
                autoCollect = true,
        }
        AutoDemonController.status = {
                state = "Disabled",
                currentLily = "None",
                detection = "Idle",
                collected = 0,
        }
        AutoDemonController.currentTarget = nil

        local function validState(state)
                for _, known in ipairs(AutoDemonController.STATUS_STATES) do
                        if known == state then
                                return true
                        end
                end
                return false
        end

        function AutoDemonController.setState(state)
                if validState(state) then
                        AutoDemonController.status.state = state
                end
                return AutoDemonController.status.state
        end

        local function autoDemonLoop()
                local collected = {}
                while Tracker.isRunning("autodemon") do
                        task.wait(1)
                        local lilies = SpiderLilyDetector.scan()
                        if #lilies == 0 then
                                AutoDemonController.status.detection = "Scanning"
                                AutoDemonController.setState("No Spider Lilies Found")
                                AutoDemonController.status.currentLily = "None"
                                AutoDemonController.currentTarget = nil
                                AutomationController.stopMovement("autodemon")
                        else
                                local lily = lilies[1]
                                AutoDemonController.status.detection = "Found " .. #lilies
                                AutoDemonController.setState("Collecting Spider Lily")
                                AutoDemonController.status.currentLily = "Spider Lily (" .. Util.round(lily.dist, 0) .. " studs)"
                                AutoDemonController.currentTarget = lily.model
                                if AutoDemonController.settings.autoCollect then
                                        AutomationController.moveTo(lily.model, "autodemon")
                                        -- lilies expose no prompt in the replicated tree, so the
                                        -- pickup is touch based: land exactly on the flower
                                        local root = Util.getRoot()
                                        if root and lily.root and (lily.root.Position - root.Position).Magnitude <= 6 then
                                                AutomationController.stopMovement("autodemon")
                                                MovementHandler.travelTo(lily.model)
                                                AutomationController.interactWith(lily.model)
                                                if lily.model.Parent == nil and not collected[lily.model] then
                                                        collected[lily.model] = true
                                                        AutoDemonController.status.collected += 1
                                                end
                                        end
                                end
                        end
                end
        end

        function AutoDemonController.setEnabled(enabled)
                local want = enabled and true or false
                if AutoDemonController.settings.enabled == want then
                        return want
                end
                if enabled then
                        if not GameDetector.requireGame("Auto Demon") then
                                return false
                        end
                        AutoDemonController.settings.enabled = true
                        AutoDemonController.status.detection = "Detecting"
                        AutoDemonController.setState("Detecting Spider Lilies")
                        Tracker.setRunning("autodemon", true)
                        task.spawn(autoDemonLoop)
                        return true
                end
                AutoDemonController.settings.enabled = false
                Tracker.setRunning("autodemon", false)
                AutomationController.stopMovement("autodemon")
                AutoDemonController.setState("Disabled")
                AutoDemonController.status.currentLily = "None"
                AutoDemonController.status.detection = "Idle"
                AutoDemonController.currentTarget = nil
                return true
        end

        function AutoDemonController.setAutoCollect(enabled)
                AutoDemonController.settings.autoCollect = enabled and true or false
        end

        function AutoDemonController.getTargetModel()
                return AutoDemonController.currentTarget
        end

        function AutoDemonController.getStatusText()
                return AutoDemonController.status.state
        end

        function AutoDemonController.getLilyText()
                return AutoDemonController.status.currentLily
        end

        function AutoDemonController.getDetectionText()
                return AutoDemonController.status.detection
        end

        function AutoDemonController.getCollected()
                return AutoDemonController.status.collected
        end
end

local AutoBossController = {}
do
        AutoBossController.STATUS_STATES = {
                "Disabled",
                "Detecting Boss",
                "Boss Found",
                "Attacking Boss",
                "No Boss Found",
        }
        AutoBossController.settings = {
                enabled = false,
                selectedBoss = "Auto",
                autoAttack = false,
                detection = false,
        }
        AutoBossController.status = {
                state = "Disabled",
                currentBoss = "None",
                healthPct = 0,
        }
        AutoBossController.currentTarget = nil

        local function validState(state)
                for _, known in ipairs(AutoBossController.STATUS_STATES) do
                        if known == state then
                                return true
                        end
                end
                return false
        end

        function AutoBossController.setState(state)
                if validState(state) then
                        AutoBossController.status.state = state
                end
                return AutoBossController.status.state
        end

        function AutoBossController.resetStatus()
                AutoBossController.status.state = "Disabled"
                AutoBossController.status.currentBoss = "None"
                AutoBossController.status.healthPct = 0
                AutoBossController.currentTarget = nil
        end

        -- Resolves the boss to hunt: the selection, or every live BossInfo npc for Auto mode
        local function resolveBossNames()
                local selected = AutoBossController.settings.selectedBoss
                if selected ~= "" and selected ~= "Auto" then
                        return { selected }
                end
                local names = {}
                for _, folder in ipairs(BossDetector.scanBossFolders()) do
                        table.insert(names, folder.name)
                end
                return names
        end

        local function autoBossLoop()
                local defeatedLogged = {}
                while Tracker.isRunning("autoboss") do
                        task.wait(math.max(AutomationController.settings.tickInterval, 0.25))
                        local bossNames = resolveBossNames()
                        if #bossNames == 0 then
                                AutoBossController.setState("No Boss Found")
                                AutoBossController.status.currentBoss = "None"
                                AutoBossController.status.healthPct = 0
                                AutoBossController.currentTarget = nil
                                AutomationController.stopMovement("autoboss")
                        else
                                local matcher = AutomationController.makeKeywordMatcher(bossNames)
                                local mobs = AutomationController.scanMobModels(matcher)
                                if #mobs == 0 then
                                        -- no live model: the boss is not spawned right now, not dead
                                        AutoBossController.setState("Detecting Boss")
                                        AutoBossController.status.healthPct = 0
                                        AutoBossController.currentTarget = nil
                                        AutomationController.stopMovement("autoboss")
                                        if AutoBossController.settings.selectedBoss ~= "" and AutoBossController.settings.selectedBoss ~= "Auto" then
                                                AutoBossController.status.currentBoss = AutoBossController.settings.selectedBoss .. " (not spawned)"
                                        end
                                else
                                        local boss = mobs[1]
                                        local bossName = boss.name
                                        -- kill is only confirmed by the game's own archive list
                                        if BossDetector.isArchived(bossName) then
                                                AutoBossController.setState("Boss Found")
                                                AutoBossController.status.currentBoss = bossName .. " (defeated - archived)"
                                                if not defeatedLogged[bossName] then
                                                        defeatedLogged[bossName] = true
                                                        Util.notify("Auto Boss", bossName .. " defeated (confirmed by archive)", 4)
                                                end
                                                AutomationController.stopMovement("autoboss")
                                                AutoBossController.currentTarget = nil
                                        else
                                                AutoBossController.currentTarget = boss.model
                                                AutoBossController.setState("Attacking Boss")
                                                AutoBossController.status.currentBoss = bossName
                                                AutoBossController.status.healthPct = boss.healthPct
                                                if boss.healthPct <= 0 and not defeatedLogged[bossName] then
                                                        defeatedLogged[bossName] = true
                                                        Util.notify("Auto Boss", bossName .. " is down - waiting for the kill to be archived", 4)
                                                end
                                                if AutoBossController.settings.autoAttack then
                                                        AutomationController.moveTo(boss.model, "autoboss")
                                                        CombatHandler.attack(boss.model, CombatHandler.bossMethod)
                                                end
                                        end
                                end
                        end
                end
        end

        function AutoBossController.setEnabled(enabled)
                local want = enabled and true or false
                if AutoBossController.settings.enabled == want then
                        return want
                end
                if enabled then
                        if not GameDetector.requireGame("Auto Boss") then
                                return false
                        end
                        AutoBossController.settings.enabled = true
                        AutoBossController.setState("Detecting Boss")
                        Tracker.setRunning("autoboss", true)
                        task.spawn(autoBossLoop)
                        return true
                end
                AutoBossController.settings.enabled = false
                Tracker.setRunning("autoboss", false)
                AutomationController.stopMovement("autoboss")
                AutoBossController.resetStatus()
                return true
        end

        function AutoBossController.setBoss(name)
                AutoBossController.settings.selectedBoss = name or "Auto"
        end

        function AutoBossController.setAutoAttack(enabled)
                AutoBossController.settings.autoAttack = enabled and true or false
        end

        function AutoBossController.setDetection(enabled)
                AutoBossController.settings.detection = enabled and true or false
        end

        function AutoBossController.getBossOptions()
                return BossDetector.getBossOptions()
        end

        function AutoBossController.getTargetModel()
                return AutoBossController.currentTarget
        end

        function AutoBossController.getStatusText()
                return AutoBossController.status.state
        end

        function AutoBossController.getBossText()
                return AutoBossController.status.currentBoss
        end

        function AutoBossController.getHealthPct()
                return AutoBossController.status.healthPct or 0
        end

        -- Watches Archives/Bosses on the data slot; feeds the boss webhook on new kills
        function AutoBossController.startArchiveWatch()
                if Tracker.isRunning("bossarchive") then
                        return
                end
                Tracker.setRunning("bossarchive", true)
                task.spawn(function()
                        local knownBosses = {}
                        while Tracker.isRunning("bossarchive") do
                                local ok = pcall(function()
                                        local ps = ReplicatedStorage:FindFirstChild("Player_Service")
                                        local data = ps and ps:FindFirstChild("Data")
                                        local playerFolder = data and data:FindFirstChild(LocalPlayer.Name)
                                        local archives = playerFolder and playerFolder:FindFirstChild("Archives")
                                        local bosses = archives and archives:FindFirstChild("Bosses")
                                        if bosses and bosses:IsA("StringValue") then
                                                local text = tostring(bosses.Value or "")
                                                for name in text:gmatch("[^,]+") do
                                                        name = Util.trim(name)
                                                        if name ~= "" and not knownBosses[name] then
                                                                knownBosses[name] = true
                                                                Logger.info("boss archive: " .. name .. " defeated")
                                                                if WebhookController.boss.enabled and WebhookController.boss.notifyKills then
                                                                        WebhookController.notifyBossKilled(name, nil)
                                                                end
                                                        end
                                                end
                                        end
                                end)
                                if not ok then
                                        Tracker.setRunning("bossarchive", false)
                                        return
                                end
                                task.wait(2)
                        end
                end)
        end
end

local KillAuraController = {}
do
        KillAuraController.settings = {
                enabled = false,
                range = 12,
                interval = 0.25,
        }
        KillAuraController.status = {
                state = "Disabled",
                targetName = "None",
        }
        KillAuraController.currentTarget = nil

        function KillAuraController.setCurrentTarget(target)
                KillAuraController.currentTarget = target
                local name = "None"
                if typeof(target) == "Instance" then
                        name = target.Name
                end
                KillAuraController.status.targetName = name
        end

        function KillAuraController.getCurrentTarget()
                return KillAuraController.currentTarget
        end

        local function resolveTarget()
                -- Provides the current Auto Quest target to Kill Aura, falling back to Auto Boss
                local target = AutoQuestController.getTargetModel()
                if target ~= nil then
                        return target, CombatHandler.questMethod
                end
                target = AutoBossController.getTargetModel()
                if target ~= nil then
                        return target, CombatHandler.bossMethod
                end
                return nil, CombatHandler.questMethod
        end

        local function killAuraLoop()
                while Tracker.isRunning("killaura") do
                        task.wait(KillAuraController.settings.interval)
                        local target, method = resolveTarget()
                        if target == nil then
                                -- no quest/boss target: attack the nearest mob inside the aura range
                                local matcher = AutomationController.makeMobMatcher()
                                local mobs = AutomationController.scanMobModels(matcher)
                                for _, mob in ipairs(mobs) do
                                        if mob.dist <= KillAuraController.settings.range then
                                                target = mob.model
                                                break
                                        end
                                end
                        end
                        if target ~= nil and target.Parent ~= nil then
                                KillAuraController.setCurrentTarget(target)
                                local targetRoot = nil
                                pcall(function()
                                        targetRoot = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
                                end)
                                local myRoot = Util.getRoot()
                                if targetRoot and myRoot then
                                        local distance = (targetRoot.Position - myRoot.Position).Magnitude
                                        if distance <= KillAuraController.settings.range then
                                                CombatHandler.attack(target, method)
                                        end
                                else
                                        CombatHandler.attack(target, method)
                                end
                        end
                end
        end

        function KillAuraController.setEnabled(enabled)
                local want = enabled and true or false
                if KillAuraController.settings.enabled == want then
                        return want
                end
                if enabled then
                        if not GameDetector.requireGame("Kill Aura") then
                                return false
                        end
                        KillAuraController.settings.enabled = true
                        KillAuraController.status.state = "Armed"
                        Tracker.setRunning("killaura", true)
                        task.spawn(killAuraLoop)
                        return true
                end
                KillAuraController.settings.enabled = false
                Tracker.setRunning("killaura", false)
                KillAuraController.status.state = "Disabled"
                KillAuraController.currentTarget = nil
                KillAuraController.status.targetName = "None"
                return true
        end

        function KillAuraController.setRange(value)
                KillAuraController.settings.range = math.clamp(value, 4, 100)
                return KillAuraController.settings.range
        end

        function KillAuraController.setInterval(value)
                KillAuraController.settings.interval = math.clamp(value, 0.05, 2)
                return KillAuraController.settings.interval
        end

        function KillAuraController.getStatusText()
                if KillAuraController.settings.enabled then
                        return KillAuraController.status.state .. " - " .. KillAuraController.status.targetName
                end
                return "Disabled"
        end
end

-- Boss archive watch arms as soon as the game structure is detected
GameProfile.onLoad(function()
        AutoBossController.startArchiveWatch()
end)

local DiscoveryController = {}
do
        DiscoveryController.lastSummary = "No scan yet"

        -- Logs nearby mobs (name/hp/dist) for debugging target scans; uses the same
        -- registry-first scan the automation engines run on
        function DiscoveryController.dump()
                local found = AutomationController.scanMobModels(nil)
                Logger.info("target dump: " .. #found .. " candidate(s) within " .. AutomationController.settings.maxRange .. " studs")
                for i, entry in ipairs(found) do
                        if i <= 25 then
                                Logger.info(string.format("  %02d: %s  hp=%d/%d  dist=%d",
                                        i, entry.name, entry.humanoid.Health, entry.humanoid.MaxHealth, Util.round(entry.dist, 0)))
                        end
                end
                if #found > 25 then
                        Logger.info("  ... and " .. (#found - 25) .. " more")
                end
                DiscoveryController.lastSummary = #found .. " candidate(s) - details in the log console"
                Util.notify("Target Dump", DiscoveryController.lastSummary, 6)
                return DiscoveryController.lastSummary
        end
end

local LocationDetector = {}
do
        LocationDetector.scanning = false
        local locations = {}
        local seenNames = {}

        local function cleanName(raw)
                local name = Util.trim(raw)
                if name == "" then
                        return nil
                end
                return name
        end

        function LocationDetector.addLocation(name, source, path)
                local clean = cleanName(name)
                if clean == nil or seenNames[clean] then
                        return false
                end
                seenNames[clean] = true
                table.insert(locations, {
                        name = clean,
                        source = source or "scan",
                        path = path or "",
                })
                return true
        end

        function LocationDetector.reset()
                locations = {}
                seenNames = {}
        end

        -- Collects teleport points: baked profile paths + live Workspace structure
        function LocationDetector.ScanLocations()
                local found = {}

                for _, point in ipairs(GameProfile.data.teleportPoints or {}) do
                        table.insert(found, { name = point.name, path = point.path })
                end

                pcall(function()
                        -- live region scan: each region folder and its fast-travel crystal
                        local regions = Workspace:FindFirstChild("Debree")
                        regions = regions and regions:FindFirstChild("Regions")
                        if regions then
                                for _, region in ipairs(regions:GetChildren()) do
                                        table.insert(found, { name = region.Name .. " (Region)", path = region:GetFullName() })
                                        for _, child in ipairs(region:GetChildren()) do
                                                if child:IsA("Model") and child.Name:find("SpawnCrystal") then
                                                        table.insert(found, { name = child.Name, path = child:GetFullName() })
                                                end
                                        end
                                end
                        end
                        -- training areas
                        local training = Workspace:FindFirstChild("Training")
                        if training then
                                for _, area in ipairs(training:GetChildren()) do
                                        table.insert(found, { name = "Training: " .. area.Name, path = area:GetFullName() })
                                end
                        end
                        -- detached maps (Muzan's Lair etc.)
                        local maps = Workspace:FindFirstChild("Map")
                        maps = maps and maps:FindFirstChild("DetachedMaps")
                        if maps then
                                for _, area in ipairs(maps:GetChildren()) do
                                        table.insert(found, { name = area.Name, path = area:GetFullName() })
                                end
                        end
                        -- global spawn
                        if Workspace:FindFirstChild("SpawnLocation") then
                                table.insert(found, { name = "Spawn", path = "Workspace/SpawnLocation" })
                        end
                end)
                return found
        end

        function LocationDetector.GetLocations()
                local list = {}
                for _, entry in ipairs(locations) do
                        table.insert(list, entry.name)
                end
                return list
        end

        function LocationDetector.getLocationCount()
                return #locations
        end

        function LocationDetector.findLocation(name)
                for _, entry in ipairs(locations) do
                        if entry.name == name then
                                return entry
                        end
                end
                return nil
        end
end

local TeleportController = {}
do
        TeleportController.settings = {
                selectedLocation = "",
                autoRefresh = false,
        }
        TeleportController.status = "Ready"
        local AUTO_REFRESH_INTERVAL = 30
        local locationsChanged = function() end

        function TeleportController.onLocationsChanged(fn)
                if type(fn) == "function" then
                        locationsChanged = fn
                end
        end

        function TeleportController.setSelectedLocation(name)
                TeleportController.settings.selectedLocation = name or ""
                if TeleportController.settings.selectedLocation ~= "" then
                        TeleportController.status = "Ready"
                end
                return TeleportController.settings.selectedLocation
        end

        function TeleportController.RefreshLocations()
                if LocationDetector.scanning then
                        return LocationDetector.getLocationCount()
                end
                LocationDetector.scanning = true
                TeleportController.status = "Scanning map..."
                local scanned = LocationDetector.ScanLocations()
                LocationDetector.reset()
                for _, found in ipairs(scanned) do
                        LocationDetector.addLocation(found.name, "scan", found.path)
                end
                LocationDetector.scanning = false
                local count = LocationDetector.getLocationCount()
                TeleportController.status = "Locations found: " .. count
                Logger.info("location refresh: " .. count .. " location(s)")
                pcall(locationsChanged, count)
                return count
        end

        -- Resolves a teleport target to a CFrame position (model pivot or part)
        local function resolveCFrame(instance)
                if instance == nil then
                        return nil
                end
                local ok, result = pcall(function()
                        if instance:IsA("Model") then
                                return instance:GetPivot()
                        end
                        return instance.CFrame
                end)
                if ok and result then
                        return result
                end
                -- fallback: first BasePart descendant
                local part
                pcall(function()
                        for _, d in ipairs(instance:GetDescendants()) do
                                if d:IsA("BasePart") then
                                        part = d
                                        break
                                end
                        end
                end)
                if part then
                        local ok2, cf = pcall(function()
                                return part.CFrame
                        end)
                        if ok2 then
                                return cf
                        end
                end
                return nil
        end

        function TeleportController.TeleportToLocation()
                local selected = TeleportController.settings.selectedLocation
                if selected == "" then
                        TeleportController.status = "Location unavailable"
                        Util.notify("Teleports", "Select a location first")
                        return false
                end
                local location = LocationDetector.findLocation(selected)
                if location == nil then
                        TeleportController.status = "Location unavailable"
                        Util.notify("Teleports", "That location is not in the current list - refresh and pick again")
                        return false
                end
                if not GameDetector.requireGame("Teleports") then
                        TeleportController.status = "Location unavailable"
                        return false
                end
                local instance = GameProfile.resolvePath(location.path or "")
                if instance == nil then
                        TeleportController.status = "Location unavailable"
                        Util.notify("Teleports", "Could not resolve that location in the current map")
                        return false
                end
                local root = Util.getRoot()
                if root == nil then
                        TeleportController.status = "No character"
                        Util.notify("Teleports", "Character not found")
                        return false
                end
                local cf = resolveCFrame(instance)
                if cf == nil then
                        TeleportController.status = "Location unavailable"
                        Util.notify("Teleports", "Could not read a position for that location")
                        return false
                end
                TeleportController.status = "Teleporting..."
                -- travels through the shared MovementHandler: Instant jumps, Tween glides
                local ok = MovementHandler.travelTo(cf)
                if ok then
                        if MovementHandler.settings.method == "Tween" then
                                TeleportController.status = "Traveling to " .. selected
                                Util.toast("Traveling to " .. selected .. " (tween)")
                        else
                                TeleportController.status = "Teleported to " .. selected
                                Util.toast("Teleported to " .. selected)
                        end
                        Logger.info("teleported to " .. selected .. " (" .. location.path .. ")")
                        return true
                end
                TeleportController.status = "Teleport failed"
                Util.notify("Teleports", "Teleport failed - the game may block direct movement")
                return false
        end

        function TeleportController.setAutoRefresh(enabled)
                local want = enabled and true or false
                if TeleportController.settings.autoRefresh == want then
                        return want
                end
                if enabled then
                        TeleportController.settings.autoRefresh = true
                        Tracker.setRunning("tpautorefresh", true)
                        task.spawn(function()
                                while Tracker.isRunning("tpautorefresh") do
                                        task.wait(AUTO_REFRESH_INTERVAL)
                                        if Tracker.isRunning("tpautorefresh") then
                                                TeleportController.RefreshLocations()
                                        end
                                end
                        end)
                        return true
                end
                TeleportController.settings.autoRefresh = false
                Tracker.setRunning("tpautorefresh", false)
                return true
        end

        function TeleportController.getLocationOptions()
                return LocationDetector.GetLocations()
        end

        function TeleportController.getStatusText()
                return TeleportController.status
        end
end

local SettingsController = {}
do
                local lightingBackup = nil
                local fpsBoostLevel = "off"
                local particleBackups = {}
                local textureBackups = {}

                local function backupLighting()
                                if lightingBackup then
                                                return
                                end
                                lightingBackup = {
                                                Brightness = Lighting.Brightness,
                                                ClockTime = Lighting.ClockTime,
                                                FogEnd = Lighting.FogEnd,
                                                GlobalShadows = Lighting.GlobalShadows,
                                                OutdoorAmbient = Lighting.OutdoorAmbient,
                                                ExposureCompensation = Lighting.ExposureCompensation,
                                }
                end

                function SettingsController.setNotifications(enabled)
                                State.set("notifications", enabled and true or false)
                end

                function SettingsController.setAutoReexecute(enabled)
                                State.set("autoReexecute", enabled and true or false)
                end

                function SettingsController.isAutoReexecute()
                                return State.get("autoReexecute", true) ~= false
                end

                function SettingsController.setFullbright(enabled)
                                if enabled then
                                                backupLighting()
                                                Lighting.Brightness = 2
                                                Lighting.ClockTime = 14
                                                Lighting.FogEnd = 100000
                                                Lighting.GlobalShadows = false
                                                Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
                                else
                                                if lightingBackup then
                                                                Lighting.Brightness = lightingBackup.Brightness
                                                                Lighting.ClockTime = lightingBackup.ClockTime
                                                                Lighting.FogEnd = lightingBackup.FogEnd
                                                                Lighting.GlobalShadows = lightingBackup.GlobalShadows
                                                                Lighting.OutdoorAmbient = lightingBackup.OutdoorAmbient
                                                end
                                end
                end

                local function applyFpsBoost(level)
                                local conn
                                if level == "off" then
                                                Lighting.GlobalShadows = lightingBackup and lightingBackup.GlobalShadows or true
                                                for emitter, state in pairs(particleBackups) do
                                                                pcall(function() emitter.Enabled = state end)
                                                end
                                                particleBackups = {}
                                                if level == "off" then
                                                                for part, texId in pairs(textureBackups) do
                                                                                pcall(function() part.TextureID = texId end)
                                                                end
                                                                textureBackups = {}
                                                end
                                                return
                                end
                                backupLighting()
                                Lighting.GlobalShadows = false
                                local scan = function()
                                                local count = 0
                                                for _, obj in ipairs(Workspace:GetDescendants()) do
                                                                if obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
                                                                                if particleBackups[obj] == nil then
                                                                                                particleBackups[obj] = obj.Enabled
                                                                                                obj.Enabled = false
                                                                                                count += 1
                                                                                end
                                                                elseif level == "full" and obj:IsA("MeshPart") and obj.TextureID ~= "" then
                                                                                if textureBackups[obj] == nil then
                                                                                                textureBackups[obj] = obj.TextureID
                                                                                                obj.TextureID = ""
                                                                                                count += 1
                                                                                end
                                                                end
                                                                if count > 800 then
                                                                                break
                                                                end
                                                end
                                end
                                local ok, err = pcall(scan)
                                if not ok then
                                                Logger.warn("fps boost scan failed: " .. tostring(err))
                                end
                                conn = Workspace.DescendantAdded:Connect(function(obj)
                                                task.defer(function()
                                                                if obj:IsA("ParticleEmitter") or obj:IsA("Beam") or obj:IsA("Trail") or obj:IsA("Fire") or obj:IsA("Smoke") or obj:IsA("Sparkles") then
                                                                                particleBackups[obj] = obj.Enabled
                                                                                obj.Enabled = false
                                                                end
                                                end)
                                end)
                                Tracker.track(conn, "fpsboost")
                end

                function SettingsController.setFpsBoost(level)
                                fpsBoostLevel = level
                                Tracker.cleanup("fpsboost")
                                applyFpsBoost(level)
                                if level ~= "off" then
                                                Logger.info("fps boost applied: " .. level)
                                end
                end

                function SettingsController.getFpsBoostLevel()
                                return fpsBoostLevel
                end

                local fpsValue = 0

                function SettingsController.startFpsCounter()
                                local frames = 0
                                Tracker.setRunning("fpscounter", true)
                                local conn = RunService.RenderStepped:Connect(function()
                                                frames += 1
                                end)
                                Tracker.track(conn, "fpscounter")
                                task.spawn(function()
                                                while Tracker.isRunning("fpscounter") do
                                                                task.wait(1)
                                                                fpsValue = frames
                                                                frames = 0
                                                end
                                end)
                end

                function SettingsController.getFps()
                                return fpsValue
                end

                function SettingsController.copyLogs()
                                local ok = Util.setClipboard(Logger.getHistory())
                                Util.notify("Debug", ok and "Logs copied to clipboard" or "Clipboard not supported")
                end

                function SettingsController.clearLogs()
                                Logger.clear()
                                Util.notify("Debug", "Logs cleared")
                end

                function SettingsController.checkUpdate()
                                Util.notify("Update", "Checking for updates...")
                                local body = Util.httpGet(EXECUTE_URL)
                                if not body then
                                                Util.notify("Update", "Could not reach the source")
                                                return
                                end
                                local remoteVersion = body:match('local VERSION = "(.-)"')
                                if not remoteVersion then
                                                Util.notify("Update", "Could not read remote version")
                                                return
                                end
                                if remoteVersion == VERSION then
                                                Util.notify("Update", "You are up to date (" .. VERSION .. ")")
                                else
                                                Util.notify("Update", "Update available: " .. remoteVersion .. " (current: " .. VERSION .. ")", 6)
                                end
                end

                function SettingsController.copySource()
                                local ok = Util.setClipboard(EXECUTE_URL)
                                Util.notify("Project", ok and "Execute URL copied" or "Clipboard not supported")
                end

                -- Removes the Gen 2 .rfld config plus the legacy Gen 1 Config.rbxl
                function SettingsController.resetConfig()
                                local ok = false
                                if isfolder and delfile then
                                                pcall(function()
                                                                makefolder("PS2Hub")
                                                                if isfile and isfile("PS2Hub/Config.rbxl") then
                                                                                delfile("PS2Hub/Config.rbxl")
                                                                end
                                                                local window = _G.RayfieldInstance
                                                                if window and window.GetPath then
                                                                                local _, fullPath = window:GetPath()
                                                                                if fullPath and fullPath ~= "" then
                                                                                                delfile(fullPath)
                                                                                end
                                                                end
                                                                ok = true
                                                end)
                                end
                                Util.notify("Config", ok and "Saved config removed. Rejoin to see defaults." or "File API not supported on this executor")
                end

                function SettingsController.destroyUi()
                                Util.notify("PS2 Hub", "Shutting down...")
                                ESPController.stopAll()
                                Tracker.cleanupAll()
                                local window = _G.RayfieldInstance
                                if window then
                                                pcall(function()
                                                                window:Unload()
                                                end)
                                end
                                _G.RayfieldInstance = nil
                                getgenv().PS2Hub_Loaded = nil
                end

                function SettingsController.reloadScript()
                                Util.notify("PS2 Hub", "Reloading...")
                                task.wait(0.3)
                                ESPController.stopAll()
                                Tracker.cleanupAll()
                                local window = _G.RayfieldInstance
                                if window then
                                                pcall(function()
                                                                window:Unload()
                                                end)
                                end
                                _G.RayfieldInstance = nil
                                getgenv().PS2Hub_Loaded = nil
                                local ok, exec = pcall(function()
                                                return loadstring(game:HttpGet(EXECUTE_URL))
                                end)
                                if ok and exec then
                                                task.spawn(exec)
                                else
                                                print("[PS2 Hub] reload failed, could not fetch source")
                                end
                end

                function SettingsController.setNotifDuration(value)
                                State.set("notifDuration", math.clamp(value, 1, 15))
                end

                -- perfScale stretches the Home and ESP status loops when FPS drops
                function SettingsController.setAutoPerformance(enabled)
                                if enabled then
                                                if Tracker.isRunning("autoperf") then
                                                                return
                                                end
                                                Tracker.setRunning("autoperf", true)
                                                task.spawn(function()
                                                                while Tracker.isRunning("autoperf") do
                                                                                task.wait(5)
                                                                                local fps = fpsValue
                                                                                local scale = State.get("perfScale", 1)
                                                                                if fps > 0 and fps < 25 and scale < 4 then
                                                                                                local newScale = scale * 2
                                                                                                State.set("perfScale", newScale)
                                                                                                Logger.info("auto performance: intervals x" .. newScale .. " (fps " .. fps .. ")")
                                                                                elseif fps >= 55 and scale > 1 then
                                                                                                local newScale = math.max(math.floor(scale / 2), 1)
                                                                                                State.set("perfScale", newScale)
                                                                                                Logger.info("auto performance: intervals x" .. newScale .. " (fps " .. fps .. ")")
                                                                                end
                                                                end
                                                end)
                                else
                                                Tracker.setRunning("autoperf", false)
                                                State.set("perfScale", 1)
                                end
                end

                -- New loop-backed features must be registered here or emergency stop will miss them
                function SettingsController.emergencyStop()
                                local ok = pcall(function()
                                                AutoQuestController.setEnabled(false)
                                                AutoDemonController.setEnabled(false)
                                                AutoBossController.setEnabled(false)
                                                KillAuraController.setEnabled(false)
                                                MovementHandler.stop()
                                                TeleportController.setAutoRefresh(false)
                                                ClanController.setEnabled(false)
                                                MovementController.setFly(false)
                                                MovementController.setNoclip(false)
                                                MovementController.setInfiniteJump(false)
                                                MovementController.setSprint(false)
                                                MovementController.setClickTp(false)
                                                MovementController.setLockStats(false)
                                                CharacterController.setGod(false)
                                                CharacterController.setAntiAFK(false)
                                                CharacterController.resetFov()
                                                PlayerController.setFollow(false)
                                                PlayerController.stopSpectate()
                                                ToolController.setAutoEquip(false)
                                                ESPController.stopAll()
                                                SettingsController.setFullbright(false)
                                                SettingsController.setFpsBoost("off")
                                end)
                                if ok then
                                                Util.notify("Emergency Stop", "All active features stopped", 5)
                                else
                                                Util.notify("Emergency Stop", "Some features may still run - check the console", 5)
                                end
                                Logger.warn("emergency stop triggered")
                end
end

if getgenv().PS2Hub_Loaded then
        pcall(function()
                getgenv().PS2Hub_TrackerCleanup()
        end)
        print("[PS2 Hub] previous session cleaned")
end
getgenv().PS2Hub_Loaded = true

pcall(function()
        local queueOnTeleport = queue_on_teleport
        if typeof(queueOnTeleport) == "function" and SettingsController.isAutoReexecute() then
                queueOnTeleport('loadstring(game:HttpGet("' .. EXECUTE_URL .. '"))()')
        end
end)

local Rayfield = nil
do
        local attempts = 0
        while not Rayfield and attempts < 3 do
                attempts += 1
                local ok, result = pcall(function()
                        return loadstring(game:HttpGet("https://sirius.menu/gen2"))()
                end)
                if ok and type(result) == "table" and type(result.CreateWindow) == "function" then
                        Rayfield = result
                end
        end
end
if not Rayfield then
        print("[PS2 Hub] failed to load Rayfield Gen 2 after 3 attempts. Check your connection or executor HttpGet support.")
        return
end

local Window = Rayfield:CreateWindow({
        name = "PS2 Hub",
        subtitle = "Project Slayers 2 · v" .. VERSION,
        sidebarLayout = true,
        profile = "by Faludaddd",
        showName = "PS2 Hub",
        theme = "ember",
        configuration = {
                autoSave = true,
                autoLoad = true,
                fileName = "Config",
                customFolder = "PS2Hub",
        },
})

_G.RayfieldInstance = Window

pcall(function()
        Window:CreateTag({
                text = "v" .. VERSION,
                color = Color3.fromRGB(110, 120, 140),
                order = 1,
        })
        local statusText = GameDetector.getStatusText()
        local statusColor = Color3.fromRGB(235, 140, 50)
        if statusText == "Supported" then
                statusColor = Color3.fromRGB(70, 180, 110)
        end
        Window:CreateTag({
                text = statusText,
                color = statusColor,
                order = 2,
        })
end)

MovementController.init()
PlayerController.init()
ToolController.init()
ESPController.init()
ServerController.init()
SettingsController.startFpsCounter()

pcall(function()
        Window:CreateSection({ name = "General" })
end)
local HomeTab = Window:CreateTab({ name = "Home" })
local UniversalTab = Window:CreateTab({ name = "Universal" })
local EspTab = Window:CreateTab({ name = "ESP" })
local ServerTab = Window:CreateTab({ name = "Server" })
pcall(function()
        Window:CreateSection({ name = "Game" })
end)
local MainTab = Window:CreateTab({ name = "Main" })
local TeleportsTab = Window:CreateTab({ name = "Teleports" })
local ClanTab = Window:CreateTab({ name = "Auto Spin Clan" })
pcall(function()
        Window:CreateSection({ name = "System" })
end)
local ConfigTab = Window:CreateTab({ name = "Config" })
local SettingsTab = Window:CreateTab({ name = "Settings" })

-- Rayfield autoLoad restores saved values by re-firing callbacks, so controller toggles must stay idempotent
local Elements = {}

local function normalizeChoice(choice)
        if type(choice) == "table" then
                return choice[1] or ""
        end
        return choice or ""
end

local function normalizeMulti(choice)
        if type(choice) == "table" then
                return choice
        end
        if choice == nil or choice == "" then
                return {}
        end
        return { choice }
end

local function tryCreate(obj, method, props)
        local ok, handle = pcall(function()
                return obj[method](obj, props)
        end)
        if ok then
                return handle
        end
        Logger.warn(method .. " not available in this Rayfield build - element skipped")
        return nil
end

local lockedElements = {}

local function lockReasonText()
        if not GameProfile.ready then
                return GameProfile.lockReason
        end
        return "Not in Project Slayers 2 - open the game to use this feature"
end

-- Game-specific elements lock natively and unlock automatically when GameProfile.load fires
local function lockUntilRelease(element)
        if element == nil or GameDetector.isGameReady() then
                return
        end
        table.insert(lockedElements, element)
        pcall(function()
                element:Lock(lockReasonText())
        end)
end

GameProfile.onLoad(function()
        for _, element in ipairs(lockedElements) do
                pcall(function()
                        element:Unlock()
                end)
        end
        lockedElements = {}
end)

-- true = skip callback so UI refreshes never re-trigger controllers
local function safeSet(element, value)
        if element == nil then
                return
        end
        pcall(function()
                element:Set(value, true)
        end)
end

local function syncAllOff()
        local keys = {
                "flyToggle", "noclipToggle", "infjumpToggle", "sprintToggle", "lockstatsToggle",
                "clicktpToggle", "godToggle", "antiafkToggle", "followToggle", "autoequipToggle",
                "autoQuestToggle", "autoDemonToggle", "autoBossToggle", "killAuraToggle", "teleportAutoRefresh", "clanToggle", "espPlayersToggle", "espNpcsToggle",
                "espBossesToggle", "espQuestToggle", "espItemsToggle", "fullbrightToggle",
        }
        for _, key in ipairs(keys) do
                safeSet(Elements[key], false)
        end
end

-- Tab builders are isolated so one failing element reports loudly instead of blanking every later tab
local function buildTab(label, builder)
        local ok, err = pcall(builder)
        if not ok then
                Logger.error("UI build failed for " .. label .. " tab: " .. tostring(err))
                Util.notify("PS2 Hub", label .. " tab failed to build - open Config > Debug for the error", 8)
        end
        return ok
end

buildTab("Home", function()
        HomeTab:CreateSection({ name = "Session" })

        Elements.homeGame = HomeTab:CreateText({
                name = "Current Game",
                text = "Detecting...",
        })
        Elements.homePlayer = HomeTab:CreateText({
                name = "Player",
                text = LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")",
        })
        Elements.homeStatus = HomeTab:CreateText({
                name = "Status",
                text = "v" .. VERSION .. " - " .. GameDetector.getStatusText(),
        })

        HomeTab:CreateSection({ name = "Live Stats" })

        local grid = HomeTab:CreateGroup()
        local left = grid:CreateGroup({ direction = "column" })
        local right = grid:CreateGroup({ direction = "column" })
        Elements.statFps = left:CreateStat({ name = "FPS", value = 0 })
        Elements.statPing = left:CreateStat({ name = "Ping", value = 0, suffix = " ms" })
        Elements.statTargets = left:CreateStat({ name = "ESP Targets", value = 0 })
        Elements.statPlayers = right:CreateStat({ name = "Players", value = 0 })
        Elements.statModules = right:CreateStat({ name = "Active Modules", value = 0 })
        Elements.statUptime = right:CreateStat({ name = "Uptime", value = 0, suffix = " s" })

        HomeTab:CreateSection({ name = "Activity" })

        Elements.homeTask = HomeTab:CreateText({
                name = "Task",
                text = "Idle - automation off",
        })
        Elements.homeProgress = tryCreate(HomeTab, "CreateProgress", {
                name = "Target Health",
                range = { 0, 100 },
                value = 0,
        })

        local function countActive()
                local activeModules = 0
                local names = {
                        "autoquest", "autodemon", "autoboss", "killaura", "clan", "fly", "noclip",
                        "infjump", "god", "antiafk", "sprint", "npcscan", "espplayers", "lockstats",
                        "follow", "clicktp", "autoperf",
                }
                for _, name in ipairs(names) do
                        if Tracker.isRunning(name) then
                                activeModules += 1
                        end
                end
                return activeModules
        end

        local bootTime = os.clock()
        Tracker.setRunning("homerefresh", true)
        task.spawn(function()
                while Tracker.isRunning("homerefresh") do
                        task.wait(1 * State.get("perfScale", 1))
                        local info = ServerController.getInfo()
                        local gameName = "?"
                        pcall(function()
                                gameName = GameDetector.detect().gameName or "?"
                        end)
                        local taskLine = "Idle - automation off"
                        if Tracker.isRunning("autoquest") then
                                taskLine = "Auto Quest: " .. AutoQuestController.getStatusText()
                                if AutoQuestController.getQuestText() ~= "None" then
                                        taskLine = taskLine .. " - " .. AutoQuestController.getQuestText()
                                end
                        elseif Tracker.isRunning("autodemon") then
                                taskLine = "Auto Demon: " .. AutoDemonController.getStatusText()
                        elseif Tracker.isRunning("autoboss") then
                                taskLine = "Auto Boss: " .. AutoBossController.getBossText()
                        elseif Tracker.isRunning("clan") then
                                taskLine = "Auto Spin Clan active - " .. tostring(ClanController.sessionRerolls) .. " spin(s)"
                        end
                        pcall(function()
                                Elements.homeGame:Set(gameName)
                                Elements.homeStatus:Set("v" .. VERSION .. " - " .. GameDetector.getStatusText())
                                Elements.statFps:Set(SettingsController.getFps())
                                Elements.statPing:Set(math.max(info.ping, 0))
                                Elements.statTargets:Set(ESPController.getTargetCount())
                                Elements.statPlayers:Set(info.playerCount)
                                Elements.statModules:Set(countActive())
                                Elements.statUptime:Set(math.floor(os.clock() - bootTime))
                                Elements.homeTask:Set(taskLine)
                                local targetHealth = AutoBossController.getHealthPct()
                                if targetHealth <= 0 then
                                        targetHealth = AutoQuestController.getTargetHealthPct()
                                end
                                Elements.homeProgress:Set(math.floor(targetHealth))
                        end)
                end
        end)

        HomeTab:CreateSection({ name = "Game Support" })
        HomeTab:CreateText({
                name = "Project Slayers 2",
                text = "Auto Quest, Auto Demon, Auto Boss, Kill Aura, Teleports and Auto Spin Clan are built from the analyzed Project Slayers 2 instance and only run inside that game. Universal features work everywhere.",
        })
        HomeTab:CreateButton({
                name = "Check for Updates",
                callback = function()
                        SettingsController.checkUpdate()
                end,
        })
end)

buildTab("Universal", function()
        UniversalTab:CreateSection({ name = "Movement" })

        local toggleRowA = UniversalTab:CreateGroup()
        local lockstatsToggle
        lockstatsToggle = toggleRowA:CreateToggle({
                name = "Lock Stats",
                description = "Re-applies speed and jump values when the game resets them",
                value = false,
                flag = "Univ_LockStats",
                callback = function(value)
                        MovementController.setLockStats(value)
                end,
        })
        Elements.lockstatsToggle = lockstatsToggle
        local flyToggle
        flyToggle = toggleRowA:CreateToggle({
                name = "Fly",
                value = false,
                flag = "Univ_Fly",
                callback = function(value)
                        local ok = MovementController.setFly(value)
                        if value and not ok then
                                safeSet(flyToggle, false)
                        end
                end,
        })
        Elements.flyToggle = flyToggle
        local noclipToggle
        noclipToggle = toggleRowA:CreateToggle({
                name = "Noclip",
                value = false,
                flag = "Univ_Noclip",
                callback = function(value)
                        MovementController.setNoclip(value)
                end,
        })
        Elements.noclipToggle = noclipToggle

        local toggleRowB = UniversalTab:CreateGroup()
        local clicktpToggle
        clicktpToggle = toggleRowB:CreateToggle({
                name = "Click Teleport",
                description = "Click anywhere to teleport there while enabled",
                value = false,
                flag = "Univ_ClickTp",
                callback = function(value)
                        MovementController.setClickTp(value)
                end,
        })
        Elements.clicktpToggle = clicktpToggle
        local infjumpToggle
        infjumpToggle = toggleRowB:CreateToggle({
                name = "Infinite Jump",
                value = false,
                flag = "Univ_InfJump",
                callback = function(value)
                        MovementController.setInfiniteJump(value)
                end,
        })
        Elements.infjumpToggle = infjumpToggle
        local sprintToggle
        sprintToggle = toggleRowB:CreateToggle({
                name = "Sprint (hold key)",
                description = "Hold the Sprint Key below while moving",
                value = false,
                flag = "Univ_Sprint",
                callback = function(value)
                        MovementController.setSprint(value)
                end,
        })
        Elements.sprintToggle = sprintToggle

        local sliderRowA = UniversalTab:CreateGroup()
        sliderRowA:CreateSlider({
                name = "Walk Speed",
                range = { 16, 300 },
                increment = 1,
                suffix = " sps",
                value = MovementController.walkSpeed,
                flag = "Univ_WalkSpeed",
                callback = function(value)
                        MovementController.setWalkSpeed(value)
                end,
        })
        sliderRowA:CreateSlider({
                name = "Jump Power",
                range = { 20, 300 },
                increment = 1,
                suffix = " power",
                value = MovementController.jumpPower,
                flag = "Univ_JumpPower",
                callback = function(value)
                        MovementController.setJumpPower(value)
                end,
        })

        local sliderRowB = UniversalTab:CreateGroup()
        sliderRowB:CreateSlider({
                name = "Jump Height",
                range = { 1, 100 },
                increment = 0.5,
                suffix = " studs",
                value = MovementController.jumpHeight,
                flag = "Univ_JumpHeight",
                callback = function(value)
                        MovementController.setJumpHeight(value)
                end,
        })
        sliderRowB:CreateSlider({
                name = "Fly Speed",
                range = { 10, 250 },
                increment = 1,
                suffix = " sps",
                value = MovementController.flySpeed,
                flag = "Univ_FlySpeed",
                callback = function(value)
                        MovementController.setFlySpeed(value)
                end,
        })

        local sliderRowC = UniversalTab:CreateGroup()
        sliderRowC:CreateSlider({
                name = "Sprint Speed",
                range = { 17, 300 },
                increment = 1,
                suffix = " sps",
                value = MovementController.sprintSpeed,
                flag = "Univ_SprintSpeed",
                callback = function(value)
                        MovementController.setSprintSpeed(value)
                end,
        })
        sliderRowC:CreateSlider({
                name = "Field of View",
                range = { 30, 120 },
                increment = 1,
                suffix = " deg",
                value = 70,
                flag = "Univ_FOV",
                callback = function(value)
                        CharacterController.setFov(value)
                end,
        })

        UniversalTab:CreateDropdown({
                name = "Fly Method",
                options = { "WASD", "Camera (mobile)" },
                value = "WASD",
                flag = "Univ_FlyMethod",
                callback = function(option)
                        MovementController.setFlyMethod(normalizeChoice(option))
                end,
        })
        UniversalTab:CreateDropdown({
                name = "Jump Mode",
                options = { "Auto", "Power", "Height" },
                value = "Auto",
                description = "Auto applies the mode the game's Humanoid actually uses",
                flag = "Univ_JumpMode",
                callback = function(option)
                        MovementController.setJumpMode(normalizeChoice(option))
                end,
        })

        UniversalTab:CreateKeybind({
                name = "Fly Key",
                description = "Toggles fly - WASD to move, Space/LeftControl for vertical",
                value = Enum.KeyCode.F,
                flag = "Univ_FlyKey",
                callback = function()
                        local newValue = not Tracker.isRunning("fly")
                        local ok = MovementController.setFly(newValue)
                        if newValue and not ok then
                                newValue = false
                        end
                        safeSet(flyToggle, newValue)
                end,
        })
        UniversalTab:CreateKeybind({
                name = "Noclip Key",
                value = Enum.KeyCode.N,
                flag = "Univ_NoclipKey",
                callback = function()
                        local newValue = not Tracker.isRunning("noclip")
                        MovementController.setNoclip(newValue)
                        safeSet(noclipToggle, newValue)
                end,
        })
        UniversalTab:CreateKeybind({
                name = "Sprint Key",
                value = MovementController.sprintKey,
                flag = "Univ_SprintKey",
                onChanged = function(key)
                        if typeof(key) == "EnumItem" then
                                MovementController.setSprintKey(key)
                        elseif type(key) == "string" then
                                local ok, keyCode = pcall(function()
                                        return Enum.KeyCode[key]
                                end)
                                if ok and keyCode then
                                        MovementController.setSprintKey(keyCode)
                                end
                        end
                end,
        })

        UniversalTab:CreateSection({ name = "Character & Camera" })

        local charRow = UniversalTab:CreateGroup()
        local godToggle
        godToggle = charRow:CreateToggle({
                name = "God Mode",
                description = "Keeps your health topped up",
                value = false,
                flag = "Univ_God",
                callback = function(value)
                        CharacterController.setGod(value)
                end,
        })
        Elements.godToggle = godToggle
        local antiafkToggle
        antiafkToggle = charRow:CreateToggle({
                name = "Anti-AFK",
                description = "Blocks the idle kick",
                value = false,
                flag = "Univ_AntiAFK",
                callback = function(value)
                        CharacterController.setAntiAFK(value)
                end,
        })
        Elements.antiafkToggle = antiafkToggle

        local utilRow = UniversalTab:CreateGroup()
        utilRow:CreateButton({
                name = "Reset Character",
                callback = function()
                        CharacterController.reset()
                end,
        })
        utilRow:CreateButton({
                name = "Reset FOV",
                callback = function()
                        CharacterController.resetFov()
                end,
        })

        UniversalTab:CreateSection({ name = "Players" })

        local playerDropdown = UniversalTab:CreateDropdown({
                name = "Select Player",
                options = PlayerController.getPlayerNames(),
                placeholder = "None",
                description = "Type to search - refreshes on join/leave",
                forgetState = true,
                callback = function(option)
                        PlayerController.select(normalizeChoice(option))
                end,
        })
        PlayerController.onRefresh(function()
                pcall(function()
                        playerDropdown:Refresh(PlayerController.getPlayerNames())
                end)
        end)

        local tpRow = UniversalTab:CreateGroup()
        tpRow:CreateButton({
                name = "Teleport To",
                callback = function()
                        PlayerController.teleportToSelected("to")
                end,
        })
        tpRow:CreateButton({
                name = "Behind",
                callback = function()
                        PlayerController.teleportToSelected("behind")
                end,
        })
        tpRow:CreateButton({
                name = "Above",
                callback = function()
                        PlayerController.teleportToSelected("above")
                end,
        })

        local viewRow = UniversalTab:CreateGroup()
        viewRow:CreateButton({
                name = "Spectate",
                callback = function()
                        PlayerController.spectate()
                end,
        })
        viewRow:CreateButton({
                name = "Stop Spectate",
                callback = function()
                        PlayerController.stopSpectate()
                end,
        })
        viewRow:CreateButton({
                name = "Refresh List",
                callback = function()
                        pcall(function()
                                playerDropdown:Refresh(PlayerController.getPlayerNames())
                        end)
                end,
        })

        local followToggle
        followToggle = UniversalTab:CreateToggle({
                name = "Follow Selected Player",
                value = false,
                flag = "Univ_Follow",
                callback = function(value)
                        PlayerController.setFollow(value)
                end,
        })
        Elements.followToggle = followToggle

        UniversalTab:CreateSection({ name = "Tools" })

        local toolDropdown = UniversalTab:CreateDropdown({
                name = "Select Tool",
                options = ToolController.getToolNames(),
                placeholder = "None",
                description = "Type to search - refreshes when your tools change",
                forgetState = true,
                callback = function(option)
                        ToolController.select(normalizeChoice(option))
                end,
        })
        ToolController.onRefresh(function()
                pcall(function()
                        toolDropdown:Refresh(ToolController.getToolNames())
                end)
        end)
        local toolRow = UniversalTab:CreateGroup()
        toolRow:CreateButton({
                name = "Equip Selected Tool",
                callback = function()
                        ToolController.equipSelected()
                end,
        })
        toolRow:CreateButton({
                name = "Unequip Tool",
                callback = function()
                        ToolController.unequip()
                end,
        })
        local autoequipToggle
        autoequipToggle = UniversalTab:CreateToggle({
                name = "Auto Re-equip on Respawn",
                value = false,
                flag = "Univ_AutoEquip",
                callback = function(value)
                        ToolController.setAutoEquip(value)
                end,
        })
        Elements.autoequipToggle = autoequipToggle
end)

buildTab("Main", function()
        MainTab:CreateSection({ name = "Auto Quest" })
        MainTab:CreateText({
                name = "Locked",
                text = "Auto Quest reads your active quest from the game and hunts its targets. Auto Demon collects Spider Lilies from the map. Auto Boss hunts bosses (boss NPCs carry a BossInfo marker). Kill Aura swings your weapon at quest and boss targets inside its range. All of it only works inside Project Slayers 2.",
        })
        local autoQuestToggle
        autoQuestToggle = MainTab:CreateToggle({
                name = "Auto Quest",
                description = "Follows your active quest, hunts its targets, then returns to the giver to turn it in",
                value = false,
                flag = "QuestEnable",
                callback = function(value)
                        local ok = AutoQuestController.setEnabled(value)
                        if value and not ok then
                                safeSet(autoQuestToggle, false)
                        end
                end,
        })
        Elements.autoQuestToggle = autoQuestToggle
        lockUntilRelease(autoQuestToggle)
        if autoQuestToggle.value and not GameDetector.isGameReady() then
                safeSet(autoQuestToggle, false)
        end
        local questDropdown
        questDropdown = MainTab:CreateDropdown({
                name = "Quest Selection",
                options = { "Auto Detect" },
                value = "Auto Detect",
                placeholder = "Auto Detect",
                description = "Auto Detect follows your active quest; picking one is informational",
                forgetState = true,
                callback = function(option)
                        AutoQuestController.setQuest(normalizeChoice(option))
                end,
        })
        local questRow = MainTab:CreateGroup()
        local questDetectToggle
        questDetectToggle = questRow:CreateToggle({
                name = "Auto Detect Quest",
                description = "Picks the quest that fits your current level",
                value = true,
                flag = "QuestAutoDetect",
                callback = function(value)
                        AutoQuestController.setAutoDetect(value)
                end,
        })
        Elements.questDetectToggle = questDetectToggle
        local autoAcceptToggle
        autoAcceptToggle = questRow:CreateToggle({
                name = "Auto Accept",
                value = true,
                flag = "QuestAutoAccept",
                callback = function(value)
                        AutoQuestController.setAutoAccept(value)
                end,
        })
        Elements.autoAcceptToggle = autoAcceptToggle
        local autoTurnInToggle
        autoTurnInToggle = questRow:CreateToggle({
                name = "Auto Turn-In",
                value = true,
                flag = "QuestAutoTurnIn",
                callback = function(value)
                        AutoQuestController.setAutoTurnIn(value)
                end,
        })
        Elements.autoTurnInToggle = autoTurnInToggle
        Elements.questBlock = MainTab:CreateText({
                name = "Quest Status",
                text = "State: " .. AutoQuestController.getStatusText()
                        .. "\nQuest: " .. AutoQuestController.getQuestText()
                        .. "\nTarget: " .. AutoQuestController.getTargetText()
                        .. "\nProgress: " .. AutoQuestController.getProgressText(),
        })
        local questActionRow = MainTab:CreateGroup()
        local refreshQuestsButton
        refreshQuestsButton = questActionRow:CreateButton({
                name = "Refresh Quests",
                callback = function()
                        if not GameDetector.requireGame("Quest Selection") then
                                return
                        end
                        local options = { "Auto Detect" }
                        for _, quest in ipairs(QuestDetector.getQuestOptions()) do
                                table.insert(options, quest)
                        end
                        pcall(function()
                                questDropdown:Refresh(options)
                        end)
                        Util.notify("Auto Quest", #options - 1 .. " quest(s) loaded")
                end,
        })
        lockUntilRelease(refreshQuestsButton)
        questActionRow:CreateButton({
                name = "Detect Quest System",
                description = "Scans quest givers and objective labels now, reports to the console",
                callback = function()
                        task.spawn(function()
                                AutomationController.scanQuestSystem()
                        end)
                end,
        })

        MainTab:CreateSection({ name = "Auto Demon" })
        local autoDemonToggle
        autoDemonToggle = MainTab:CreateToggle({
                name = "Auto Demon",
                description = "Finds every Spider Lily and collects it",
                value = false,
                flag = "DemonEnable",
                callback = function(value)
                        local ok = AutoDemonController.setEnabled(value)
                        if value and not ok then
                                safeSet(autoDemonToggle, false)
                        end
                end,
        })
        Elements.autoDemonToggle = autoDemonToggle
        lockUntilRelease(autoDemonToggle)
        if autoDemonToggle.value and not GameDetector.isGameReady() then
                safeSet(autoDemonToggle, false)
        end
        local collectToggle
        collectToggle = MainTab:CreateToggle({
                name = "Auto Collect Spider Lilies",
                value = true,
                flag = "DemonCollectLilies",
                callback = function(value)
                        AutoDemonController.setAutoCollect(value)
                end,
        })
        Elements.collectToggle = collectToggle
        Elements.demonBlock = MainTab:CreateText({
                name = "Spider Lily Status",
                text = "State: " .. AutoDemonController.getStatusText()
                        .. "\nCurrent: " .. AutoDemonController.getLilyText()
                        .. "\nDetection: " .. AutoDemonController.getDetectionText(),
        })
        local demonStatRow = MainTab:CreateGroup()
        Elements.statLilies = demonStatRow:CreateStat({ name = "Spider Lilies Collected", value = 0 })

        MainTab:CreateSection({ name = "Auto Boss" })
        local autoBossToggle
        autoBossToggle = MainTab:CreateToggle({
                name = "Auto Boss",
                description = "Fights the selected boss automatically",
                value = false,
                flag = "BossEnable",
                callback = function(value)
                        local ok = AutoBossController.setEnabled(value)
                        if value and not ok then
                                safeSet(autoBossToggle, false)
                        end
                end,
        })
        Elements.autoBossToggle = autoBossToggle
        lockUntilRelease(autoBossToggle)
        if autoBossToggle.value and not GameDetector.isGameReady() then
                safeSet(autoBossToggle, false)
        end
        local bossDropdown
        bossDropdown = MainTab:CreateDropdown({
                name = "Boss Selection",
                options = {},
                placeholder = "Select Boss",
                description = "Auto hunts the nearest boss; boss NPCs are detected via their BossInfo marker",
                forgetState = true,
                callback = function(option)
                        AutoBossController.setBoss(normalizeChoice(option))
                end,
        })
        local bossOptionsRow = MainTab:CreateGroup()
        local bossAttackToggle
        bossAttackToggle = bossOptionsRow:CreateToggle({
                name = "Auto Attack Boss",
                value = false,
                flag = "BossAutoAttack",
                callback = function(value)
                        AutoBossController.setAutoAttack(value)
                end,
        })
        Elements.bossAttackToggle = bossAttackToggle
        local bossDetectToggle
        bossDetectToggle = bossOptionsRow:CreateToggle({
                name = "Boss Detection",
                value = false,
                flag = "BossDetection",
                callback = function(value)
                        AutoBossController.setDetection(value)
                end,
        })
        Elements.bossDetectToggle = bossDetectToggle
        Elements.bossBlock = MainTab:CreateText({
                name = "Boss Status",
                text = "State: " .. AutoBossController.getStatusText()
                        .. "\nBoss: " .. AutoBossController.getBossText(),
        })
        Elements.bossHealth = tryCreate(MainTab, "CreateProgress", {
                name = "Boss Health",
                range = { 0, 100 },
                value = 0,
        })
        local bossActionRow = MainTab:CreateGroup()
        local refreshBossesButton
        refreshBossesButton = bossActionRow:CreateButton({
                name = "Refresh Bosses",
                callback = function()
                        if not GameDetector.requireGame("Boss Selection") then
                                return
                        end
                        local options = AutoBossController.getBossOptions()
                        if #options > 0 then
                                pcall(function()
                                        bossDropdown:Refresh(options)
                                end)
                                Util.notify("Auto Boss", #options .. " boss(es) loaded")
                        else
                                Util.notify("Auto Boss", "No boss data in game profile yet")
                        end
                end,
        })
        lockUntilRelease(refreshBossesButton)

        MainTab:CreateSection({ name = "Kill Aura" })
        local killAuraToggle
        killAuraToggle = MainTab:CreateToggle({
                name = "Kill Aura",
                description = "Automatically attacks the current Auto Quest target or the selected boss",
                value = false,
                flag = "SetKillAura",
                callback = function(value)
                        local ok = KillAuraController.setEnabled(value)
                        if value and not ok then
                                safeSet(killAuraToggle, false)
                        end
                end,
        })
        Elements.killAuraToggle = killAuraToggle
        lockUntilRelease(killAuraToggle)
        if killAuraToggle.value and not GameDetector.isGameReady() then
                safeSet(killAuraToggle, false)
        end
        Elements.killAuraStatus = MainTab:CreateText({
                name = "Kill Aura Status",
                text = KillAuraController.getStatusText(),
        })

        tryCreate(MainTab, "CreateDivider", {})

        MainTab:CreateSection({ name = "Targets" })
        local targetDropdown = MainTab:CreateDropdown({
                name = "Selected Target",
                options = {},
                placeholder = "None loaded",
                forgetState = true,
                callback = function(option)
                        AutomationController.setTarget(normalizeChoice(option))
                end,
        })
        MainTab:CreateDropdown({
                name = "Exclude Targets",
                options = {},
                multiSelect = true,
                placeholder = "None",
                description = "Excluded targets are never auto-acquired",
                forgetState = true,
                callback = function(selected)
                        AutomationController.setExclusions(normalizeMulti(selected))
                end,
        })
        local targetRow = MainTab:CreateGroup()
        targetRow:CreateSlider({
                name = "Max Range",
                range = { 100, 10000 },
                increment = 50,
                suffix = " studs",
                value = 2000,
                flag = "FarmMaxRange",
                callback = function(value)
                        AutomationController.setMaxRange(value)
                end,
        })
        local refreshTargetsButton = targetRow:CreateButton({
                name = "Refresh",
                callback = function()
                        if not GameDetector.requireGame("Automation") then
                                return
                        end
                        local mobs = GameProfile.data.mobs
                        if type(mobs) == "table" and #mobs > 0 then
                                pcall(function()
                                        targetDropdown:Refresh(mobs)
                                end)
                        else
                                Util.notify("Automation", "No mob data in game profile yet")
                        end
                end,
        })
        lockUntilRelease(refreshTargetsButton)

        MainTab:CreateSection({ name = "Movement" })
        -- shared MovementHandler: every automation and the Teleports tab travel through it
        MainTab:CreateDropdown({
                name = "Movement Method",
                options = { "Instant", "Tween" },
                value = "Instant",
                description = "Instant snaps you to the objective; Tween glides there smoothly. Never walks.",
                flag = "FarmMoveMethod",
                callback = function(option)
                        MovementHandler.setMethod(normalizeChoice(option))
                end,
        })
        local moveRow = MainTab:CreateGroup()
        moveRow:CreateSlider({
                name = "Tween Speed",
                description = "Travel speed used by the Tween method",
                range = { 5, 300 },
                increment = 1,
                suffix = " sps",
                value = 60,
                flag = "FarmMoveSpeed",
                callback = function(value)
                        MovementHandler.setTweenSpeed(value)
                end,
        })
        moveRow:CreateSlider({
                name = "Arrival Distance",
                range = { 2, 20 },
                increment = 1,
                suffix = " studs",
                value = 4,
                flag = "FarmDistance",
                callback = function(value)
                        MovementHandler.setArrivalDistance(value)
                end,
        })

        MainTab:CreateSection({ name = "Interaction" })
        MainTab:CreateDropdown({
                name = "Interaction Mode",
                options = { "Auto", "ProximityPrompt", "ClickDetector", "Off" },
                value = "Auto",
                description = "Auto tries prompts, then click detectors",
                flag = "FarmInteractMode",
                callback = function(option)
                        AutomationController.setInteractMode(normalizeChoice(option))
                end,
        })
        local interRow = MainTab:CreateGroup()
        interRow:CreateSlider({
                name = "Interaction Delay",
                range = { 0.1, 5 },
                increment = 0.1,
                suffix = " s",
                value = 0.5,
                flag = "FarmInteractDelay",
                callback = function(value)
                        AutomationController.setInteractDelay(value)
                end,
        })
        interRow:CreateSlider({
                name = "Interaction Range",
                range = { 4, 40 },
                increment = 1,
                suffix = " studs",
                value = 10,
                flag = "FarmInteractRange",
                callback = function(value)
                        AutomationController.setInteractRange(value)
                end,
        })
        local attackRow = MainTab:CreateGroup()
        local autoAttackToggle
        autoAttackToggle = attackRow:CreateToggle({
                name = "Auto Attack",
                description = "Activates the equipped combat tool on cadence",
                value = false,
                flag = "FarmAutoAttack",
                callback = function(value)
                        AutomationController.setAutoAttack(value)
                end,
        })
        Elements.autoAttackToggle = autoAttackToggle
        attackRow:CreateSlider({
                name = "Attack Interval",
                range = { 0.1, 2 },
                increment = 0.05,
                suffix = " s",
                value = 0.35,
                flag = "FarmAttackDelay",
                callback = function(value)
                        AutomationController.setAttackDelay(value)
                end,
        })

        MainTab:CreateSection({ name = "Advanced" })
        local advancedRow = MainTab:CreateGroup()
        advancedRow:CreateSlider({
                name = "Target Scan Interval",
                range = { 0.5, 10 },
                increment = 0.5,
                suffix = " s",
                value = 2,
                flag = "FarmScanInterval",
                callback = function(value)
                        AutomationController.setScanInterval(value)
                end,
        })
        advancedRow:CreateSlider({
                name = "Automation Tick Interval",
                range = { 0.1, 1 },
                increment = 0.05,
                suffix = " s",
                value = 0.25,
                flag = "FarmTickInterval",
                callback = function(value)
                        AutomationController.setTickInterval(value)
                end,
        })
        MainTab:CreateText({
                name = "Recovery",
                text = "Movement Method applies to Auto Quest, Auto Demon, Auto Boss and Teleports. Instant teleports directly onto the objective; Tween glides there at the configured speed. If you rubber-band, the game is validating movement - switch methods or move manually.",
        })

        -- Game-data dropdowns populate the moment the profile loads
        GameProfile.onLoad(function()
                pcall(function()
                        local options = { "Auto Detect" }
                        for _, quest in ipairs(QuestDetector.getQuestOptions()) do
                                table.insert(options, quest)
                        end
                        questDropdown:Refresh(options)
                end)
                pcall(function()
                        bossDropdown:Refresh(AutoBossController.getBossOptions())
                end)
        end)

        -- One loop syncs every automation status card instead of per-element loops
        Tracker.setRunning("automationstatus", true)
        task.spawn(function()
                local lastValues = {}
                local function syncText(key, value)
                        if lastValues[key] ~= value and Elements[key] then
                                lastValues[key] = value
                                pcall(function()
                                        Elements[key]:Set(value)
                                end)
                        end
                end
                local lastLilies = -1
                local lastBossHealth = -1
                while Tracker.isRunning("automationstatus") do
                        task.wait(2)
                        syncText("questBlock", "State: " .. AutoQuestController.getStatusText()
                                .. "\nQuest: " .. AutoQuestController.getQuestText()
                                .. "\nTarget: " .. AutoQuestController.getTargetText()
                                .. "\nProgress: " .. AutoQuestController.getProgressText())
                        syncText("demonBlock", "State: " .. AutoDemonController.getStatusText()
                                .. "\nCurrent: " .. AutoDemonController.getLilyText()
                                .. "\nDetection: " .. AutoDemonController.getDetectionText())
                        syncText("bossBlock", "State: " .. AutoBossController.getStatusText()
                                .. "\nBoss: " .. AutoBossController.getBossText())
                        syncText("killAuraStatus", KillAuraController.getStatusText())
                        local lilies = AutoDemonController.getCollected()
                        if lilies ~= lastLilies then
                                lastLilies = lilies
                                pcall(function()
                                        Elements.statLilies:Set(lilies)
                                end)
                        end
                        local bossHealth = math.floor(AutoBossController.getHealthPct())
                        if bossHealth ~= lastBossHealth then
                                lastBossHealth = bossHealth
                                pcall(function()
                                        Elements.bossHealth:Set(bossHealth)
                                end)
                        end
                end
        end)
end)

buildTab("Teleports", function()
        TeleportsTab:CreateSection({ name = "Locations" })
        TeleportsTab:CreateText({
                name = "Location Detection",
                text = "Locations come from the live map: region crystals, training areas and detached maps. Refresh re-scans, Teleport moves you on top of the selected location. Works only inside Project Slayers 2.",
        })
        local locationDropdown
        locationDropdown = TeleportsTab:CreateDropdown({
                name = "Location",
                options = TeleportController.getLocationOptions(),
                placeholder = "Select Location",
                description = "Type to search - filled automatically by the map scan",
                forgetState = true,
                callback = function(option)
                        TeleportController.setSelectedLocation(normalizeChoice(option))
                end,
        })
        TeleportController.onLocationsChanged(function()
                pcall(function()
                        locationDropdown:Refresh(TeleportController.getLocationOptions())
                end)
        end)
        local syncLocationStatus = function() end
        local teleportRow = TeleportsTab:CreateGroup()
        teleportRow:CreateButton({
                name = "Refresh Locations",
                callback = function()
                        task.spawn(function()
                                local count = TeleportController.RefreshLocations()
                                Util.toast("Locations found: " .. count)
                                syncLocationStatus()
                        end)
                end,
        })
        teleportRow:CreateButton({
                name = "Teleport",
                callback = function()
                        task.spawn(function()
                                TeleportController.TeleportToLocation()
                                syncLocationStatus()
                        end)
                end,
        })
        local teleportAutoRefreshToggle
        teleportAutoRefreshToggle = TeleportsTab:CreateToggle({
                name = "Auto Refresh Locations",
                description = "Re-scans the map every 30 s while enabled",
                value = false,
                flag = "TeleportAutoRefresh",
                callback = function(value)
                        TeleportController.setAutoRefresh(value)
                end,
        })
        Elements.teleportAutoRefresh = teleportAutoRefreshToggle
        Elements.locationStatus = TeleportsTab:CreateText({
                name = "Location Status",
                text = TeleportController.getStatusText(),
        })
        syncLocationStatus = function()
                pcall(function()
                        Elements.locationStatus:Set(TeleportController.getStatusText())
                end)
        end

        GameProfile.onLoad(function()
                task.spawn(function()
                        TeleportController.RefreshLocations()
                end)
        end)

        Tracker.setRunning("teleportstatus", true)
        task.spawn(function()
                local lastStatus = nil
                while Tracker.isRunning("teleportstatus") do
                        task.wait(2)
                        local status = TeleportController.getStatusText()
                        if status ~= lastStatus then
                                lastStatus = status
                                pcall(function()
                                        Elements.locationStatus:Set(status)
                                end)
                        end
                end
        end)
end)

buildTab("Auto Spin Clan", function()
        ClanTab:CreateSection({ name = "Auto Spin Clan" })
        ClanTab:CreateText({
                name = "How It Works",
                text = "Clan spins in Project Slayers 2 run through the game's main menu. Pick a Desired Clan, and Auto Spin keeps spinning until it lands. The Clan Webhook below is completely separate from the Boss Farm Webhook in Config.",
        })
        local clanToggle
        clanToggle = ClanTab:CreateToggle({
                name = "Auto Spin Clan",
                description = "Spins until the Desired Clan or the spin limit",
                value = false,
                flag = "ClanEnable",
                callback = function(value)
                        local ok = ClanController.setEnabled(value)
                        if value and not ok then
                                safeSet(clanToggle, false)
                        end
                end,
        })
        Elements.clanToggle = clanToggle
        lockUntilRelease(clanToggle)
        if clanToggle.value and not GameDetector.isGameReady() then
                safeSet(clanToggle, false)
        end

        local clanDropdown
        clanDropdown = ClanTab:CreateDropdown({
                name = "Desired Clan",
                options = ClanController.getClanOptions(),
                placeholder = "Select Clan",
                description = "Clans observed in-game; the watcher fires the webhook when you land it",
                forgetState = true,
                callback = function(option)
                        ClanController.setTarget(normalizeChoice(option))
                end,
        })
        GameProfile.onLoad(function()
                pcall(function()
                        clanDropdown:Refresh(ClanController.getClanOptions())
                end)
        end)
        local refreshClansButton
        refreshClansButton = ClanTab:CreateButton({
                name = "Refresh Clan List",
                callback = function()
                        if not GameDetector.requireGame("Auto Spin Clan") then
                                return
                        end
                        pcall(function()
                                clanDropdown:Refresh(ClanController.getClanOptions())
                        end)
                        Util.notify("Auto Spin Clan", #ClanController.getClanOptions() .. " clan option(s) loaded")
                end,
        })
        lockUntilRelease(refreshClansButton)

        ClanTab:CreateDropdown({
                name = "Stop Mode",
                options = { "Spin Once", "Fixed Count", "Spin Until Target" },
                value = "Spin Once",
                flag = "ClanMode",
                callback = function(option)
                        ClanController.setMode(normalizeChoice(option))
                end,
        })

        local clanRow = ClanTab:CreateGroup()
        clanRow:CreateSlider({
                name = "Max Spins",
                range = { 1, 200 },
                increment = 1,
                value = 10,
                flag = "ClanMaxRerolls",
                callback = function(value)
                        ClanController.setMaxRerolls(value)
                end,
        })
        local clanStatusText
        local spinButton
        spinButton = clanRow:CreateButton({
                name = "Spin Once",
                description = "Fires one spin right now, no loop",
                callback = function()
                        task.spawn(function()
                                local ok, msg = ClanController.rerollOnce()
                                if ok then
                                        Util.notify("Auto Spin Clan", "Spin fired (" .. tostring(ClanController.sessionRerolls) .. " total) - " .. tostring(msg))
                                else
                                        Util.notify("Auto Spin Clan", tostring(msg))
                                end
                                pcall(function()
                                        clanStatusText:Set(ClanController.getStatusText())
                                end)
                        end)
                end,
        })
        lockUntilRelease(spinButton)

        local clanRow2 = ClanTab:CreateGroup()
        clanRow2:CreateSlider({
                name = "Spin Delay",
                range = { 0.5, 10 },
                increment = 0.5,
                suffix = " s",
                value = 1.5,
                flag = "ClanDelay",
                callback = function(value)
                        ClanController.setDelay(value)
                end,
        })
        Elements.statRerolls = clanRow2:CreateStat({ name = "Spins", value = 0 })

        Elements.clanCurrent = ClanTab:CreateText({
                name = "Current Clan",
                text = ClanController.getCurrentClan(),
        })
        clanStatusText = ClanTab:CreateText({
                name = "Spin Status",
                text = ClanController.getStatusText(),
        })
        Elements.clanStatus = clanStatusText

        ClanTab:CreateSection({ name = "Clan Webhook" })
        ClanTab:CreateText({
                name = "Separate Webhook",
                text = "This webhook is independent from the Boss Farm Webhook in Config - it needs its own URL. With Desired Clan Notification on, a message fires only when the Desired Clan above is actually obtained (account hidden behind a spoiler), never for ordinary spins.",
        })
        local clanWebhookToggle
        clanWebhookToggle = ClanTab:CreateToggle({
                name = "Enable Clan Webhook",
                value = false,
                flag = "ClanWebhookEnable",
                callback = function(value)
                        WebhookController.setClanEnabled(value)
                end,
        })
        Elements.clanWebhookToggle = clanWebhookToggle
        tryCreate(ClanTab, "CreateInput", {
                name = "Webhook URL",
                placeholder = "https://discord.com/api/webhooks/...",
                flag = "ClanWebhookUrl",
                callback = function(text)
                        WebhookController.setClanUrl(text)
                end,
        })
        local clanNotifyToggle
        clanNotifyToggle = ClanTab:CreateToggle({
                name = "Desired Clan Notification",
                description = "Webhook fires only when the Desired Clan is obtained",
                value = true,
                flag = "ClanWebhookNotifyDesired",
                callback = function(value)
                        WebhookController.setClanNotifyDesired(value)
                end,
        })
        Elements.clanNotifyToggle = clanNotifyToggle
        local clanWebhookRow = ClanTab:CreateGroup()
        clanWebhookRow:CreateButton({
                name = "Test Webhook",
                description = "Sends a clearly labeled test message - no clan is announced",
                callback = function()
                        WebhookController.testClanWebhook()
                end,
        })
        Elements.clanWebhookStatus = ClanTab:CreateText({
                name = "Webhook Status",
                text = WebhookController.getClanStatusText(),
        })

        Tracker.setRunning("clanstatus", true)
        task.spawn(function()
                local lastValues = {}
                local function syncText(key, value)
                        if lastValues[key] ~= value and Elements[key] then
                                lastValues[key] = value
                                pcall(function()
                                        Elements[key]:Set(value)
                                end)
                        end
                end
                while Tracker.isRunning("clanstatus") do
                        task.wait(2)
                        syncText("clanStatus", ClanController.getStatusText())
                        syncText("clanCurrent", ClanController.getCurrentClan())
                        syncText("clanWebhookStatus", WebhookController.getClanStatusText())
                        syncText("bossWebhookStatus", WebhookController.getBossStatusText())
                        local spins = ClanController.sessionRerolls
                        if lastValues.spins ~= spins then
                                lastValues.spins = spins
                                pcall(function()
                                        Elements.statRerolls:Set(spins)
                                end)
                        end
                end
        end)
end)

buildTab("ESP", function()
        EspTab:CreateSection({ name = "ESP" })
        Elements.espStatus = EspTab:CreateText({
                name = "Status",
                text = ESPController.getStatusText(),
        })

        Tracker.setRunning("espstatus", true)
        task.spawn(function()
                local lastLine = nil
                while Tracker.isRunning("espstatus") do
                        task.wait(2 * State.get("perfScale", 1))
                        local line = ESPController.getStatusText()
                        if line ~= lastLine then
                                lastLine = line
                                pcall(function()
                                        Elements.espStatus:Set(line)
                                end)
                        end
                end
        end)

        EspTab:CreateSection({ name = "Players" })
        local espRowA = EspTab:CreateGroup()
        local espPlayersToggle
        espPlayersToggle = espRowA:CreateToggle({
                name = "Player ESP",
                value = false,
                flag = "EspPlayers",
                callback = function(value)
                        ESPController.setPlayers(value)
                end,
        })
        Elements.espPlayersToggle = espPlayersToggle
        local espNamesToggle
        espNamesToggle = espRowA:CreateToggle({
                name = "Show Names",
                value = true,
                flag = "EspNames",
                callback = function(value)
                        ESPController.setNames(value)
                end,
        })
        Elements.espNamesToggle = espNamesToggle
        local espDistanceToggle
        espDistanceToggle = espRowA:CreateToggle({
                name = "Show Distance",
                value = true,
                flag = "EspDistance",
                callback = function(value)
                        ESPController.setDistance(value)
                end,
        })
        Elements.espDistanceToggle = espDistanceToggle

        local espRowB = EspTab:CreateGroup()
        local espHealthToggle
        espHealthToggle = espRowB:CreateToggle({
                name = "Health Bars",
                value = true,
                flag = "EspHealthBars",
                callback = function(value)
                        ESPController.setHealthBars(value)
                end,
        })
        Elements.espHealthToggle = espHealthToggle
        local espTeamToggle
        espTeamToggle = espRowB:CreateToggle({
                name = "Team Colors",
                value = false,
                flag = "EspTeamColor",
                callback = function(value)
                        ESPController.setTeamColor(value)
                end,
        })
        Elements.espTeamToggle = espTeamToggle
        local tracerToggle
        tracerToggle = espRowB:CreateToggle({
                name = "Tracers (PC only)",
                description = "Needs the Drawing API, which only PC executors provide",
                value = false,
                flag = "EspTracers",
                callback = function(value)
                        local ok = ESPController.setTracers(value)
                        if value and not ok then
                                safeSet(tracerToggle, false)
                        end
                end,
        })
        Elements.tracerToggle = tracerToggle

        EspTab:CreateSection({ name = "Categories" })
        local catRowA = EspTab:CreateGroup()
        local espNpcsToggle
        espNpcsToggle = catRowA:CreateToggle({
                name = "NPC / Mob ESP",
                description = "All non-player humanoids in range",
                value = false,
                flag = "EspNpcs",
                callback = function(value)
                        ESPController.setNpcs(value)
                end,
        })
        Elements.espNpcsToggle = espNpcsToggle
        local espBossesToggle
        espBossesToggle = catRowA:CreateToggle({
                name = "Boss ESP",
                description = "Humanoids with 1000+ max health",
                value = false,
                flag = "EspBosses",
                callback = function(value)
                        ESPController.setBosses(value)
                end,
        })
        Elements.espBossesToggle = espBossesToggle
        local espQuestToggle
        espQuestToggle = catRowA:CreateToggle({
                name = "Quest NPC ESP",
                description = "Humanoids with a Dialog or ProximityPrompt",
                value = false,
                flag = "EspQuestNpcs",
                callback = function(value)
                        ESPController.setQuestNpcs(value)
                end,
        })
        Elements.espQuestToggle = espQuestToggle
        local espItemsToggle
        espItemsToggle = catRowA:CreateToggle({
                name = "Item / Drop ESP",
                description = "Tools dropped in the workspace",
                value = false,
                flag = "EspItems",
                callback = function(value)
                        ESPController.setItems(value)
                end,
        })
        Elements.espItemsToggle = espItemsToggle

        EspTab:CreateSection({ name = "Display" })
        local dispRow = EspTab:CreateGroup()
        local highlightToggle
        highlightToggle = dispRow:CreateToggle({
                name = "Highlight",
                description = "The Roblox Highlight overlay",
                value = true,
                flag = "EspHighlight",
                callback = function(value)
                        ESPController.setHighlight(value)
                end,
        })
        Elements.highlightToggle = highlightToggle
        local boxToggle
        boxToggle = dispRow:CreateToggle({
                name = "Boxes (PC only)",
                description = "Drawing API screen-space boxes",
                value = false,
                flag = "EspBox",
                callback = function(value)
                        local ok = ESPController.setBox(value)
                        if value and not ok then
                                safeSet(boxToggle, false)
                        end
                end,
        })
        Elements.boxToggle = boxToggle

        EspTab:CreateSection({ name = "Visuals" })
        tryCreate(EspTab, "CreateColorPicker", {
                name = "Player Color",
                color = Color3.fromRGB(255, 170, 0),
                flag = "EspColorPlayers",
                callback = function(color)
                        ESPController.setPlayerColor(color)
                end,
        })
        tryCreate(EspTab, "CreateColorPicker", {
                name = "NPC Color",
                color = Color3.fromRGB(0, 255, 128),
                flag = "EspColorNpcs",
                callback = function(color)
                        ESPController.setNpcColor(color)
                end,
        })
        tryCreate(EspTab, "CreateColorPicker", {
                name = "Boss Color",
                color = Color3.fromRGB(235, 60, 60),
                flag = "EspColorBosses",
                callback = function(color)
                        ESPController.setBossColor(color)
                end,
        })

        EspTab:CreateSection({ name = "General" })
        local espSliders = EspTab:CreateGroup()
        espSliders:CreateSlider({
                name = "Update Rate",
                range = { 0, 0.5 },
                increment = 0.05,
                suffix = " s",
                value = 0,
                description = "0 = every frame, higher = lighter on FPS",
                flag = "EspUpdateRate",
                callback = function(value)
                        ESPController.setUpdateRate(value)
                end,
        })
        espSliders:CreateSlider({
                name = "Max Distance",
                range = { 50, 2000 },
                increment = 25,
                suffix = " studs",
                value = 250,
                flag = "EspMaxDistance",
                callback = function(value)
                        ESPController.setMaxDistance(value)
                end,
        })
end)

buildTab("Server", function()
        ServerTab:CreateSection({ name = "Server Actions" })
        local actionRow = ServerTab:CreateGroup()
        actionRow:CreateButton({
                name = "Rejoin",
                callback = function()
                        task.spawn(function()
                                ServerController.rejoin()
                        end)
                end,
        })
        actionRow:CreateButton({
                name = "Server Hop",
                description = "Skips servers you already visited this session",
                callback = function()
                        task.spawn(function()
                                ServerController.hop(ServerController.hopMode)
                        end)
                end,
        })
        actionRow:CreateButton({
                name = "Low Player Hop",
                description = "Only servers at or below the player filter",
                callback = function()
                        task.spawn(function()
                                ServerController.hop("lowest")
                        end)
                end,
        })

        ServerTab:CreateSection({ name = "Filters" })
        ServerTab:CreateDropdown({
                name = "Hop Preference",
                options = { "lowest", "highest", "any" },
                value = "lowest",
                flag = "ServerHopMode",
                callback = function(option)
                        ServerController.setHopMode(normalizeChoice(option))
                end,
        })
        ServerTab:CreateDropdown({
                name = "Maximum Players",
                options = { "1", "2", "3", "4", "5", "6", "8", "10" },
                value = "3",
                description = "Low Hop only accepts servers at or below this count",
                flag = "ServerLowMax",
                callback = function(option)
                        local value = tonumber(normalizeChoice(option)) or 3
                        ServerController.setLowMax(value)
                end,
        })
        local hopRow = ServerTab:CreateGroup()
        hopRow:CreateSlider({
                name = "Hop Cooldown",
                range = { 0, 60 },
                increment = 5,
                suffix = " s",
                value = 5,
                flag = "ServerCooldown",
                callback = function(value)
                        ServerController.setCooldown(value)
                end,
        })
        local rememberToggle
        rememberToggle = hopRow:CreateToggle({
                name = "Remember Visited",
                description = "Persists the visited list to disk when the executor allows it",
                value = true,
                flag = "ServerRememberVisited",
                callback = function(value)
                        ServerController.setRememberVisited(value)
                end,
        })
        Elements.rememberToggle = rememberToggle

        ServerTab:CreateSection({ name = "Information" })
        local serverText = ServerTab:CreateText({
                name = "Server Info",
                text = "Loading...",
        })
        local function refreshServerInfo()
                local info = ServerController.getInfo()
                pcall(function()
                        serverText:Set("PlaceId: " .. tostring(info.placeId)
                                .. "\nJobId: " .. info.jobId
                                .. "\nPlayers: " .. info.playerCount .. "/" .. info.maxPlayers
                                .. "\nPing: " .. (info.ping >= 0 and info.ping .. " ms" or "unavailable"))
                end)
        end
        refreshServerInfo()
        ServerTab:CreateButton({
                name = "Refresh Server Info",
                callback = function()
                        refreshServerInfo()
                end,
        })
end)

buildTab("Config", function()
        ConfigTab:CreateSection({ name = "Auto Quest Config" })
        ConfigTab:CreateDropdown({
                name = "Quest Combat Method",
                options = { "Melee", "Sword" },
                value = "Melee",
                description = "Melee fights bare-handed; Sword equips and swings your weapon",
                flag = "SetQuestCombat",
                callback = function(option)
                        CombatHandler.setQuestMethod(normalizeChoice(option))
                end,
        })

        ConfigTab:CreateSection({ name = "Auto Boss Config" })
        ConfigTab:CreateDropdown({
                name = "Boss Combat Method",
                options = { "Melee", "Sword" },
                value = "Melee",
                description = "Melee fights bare-handed; Sword equips and swings your weapon",
                flag = "SetBossCombat",
                callback = function(option)
                        CombatHandler.setBossMethod(normalizeChoice(option))
                end,
        })

        ConfigTab:CreateSection({ name = "Kill Aura Config" })
        local killAuraRow = ConfigTab:CreateGroup()
        killAuraRow:CreateSlider({
                name = "Kill Aura Range",
                range = { 4, 100 },
                increment = 1,
                suffix = " studs",
                value = 12,
                description = "Attacks targets within this distance",
                flag = "SetKillAuraRange",
                callback = function(value)
                        KillAuraController.setRange(value)
                end,
        })
        killAuraRow:CreateSlider({
                name = "Kill Aura Interval",
                range = { 0.05, 2 },
                increment = 0.05,
                suffix = " s",
                value = 0.25,
                description = "Time between attacks",
                flag = "SetKillAuraInterval",
                callback = function(value)
                        KillAuraController.setInterval(value)
                end,
        })

        ConfigTab:CreateSection({ name = "Boss Farm Webhook" })
        ConfigTab:CreateText({
                name = "Separate Webhook",
                text = "Independent from the Clan Webhook in the Auto Spin Clan tab - it needs its own URL. Fires when a farmed boss dies, with drops and a spoiler-hidden account name once the game data is wired up.",
        })
        local bossWebhookToggle
        bossWebhookToggle = ConfigTab:CreateToggle({
                name = "Enable Boss Farm Webhook",
                value = false,
                flag = "BossWebhookEnable",
                callback = function(value)
                        WebhookController.setBossEnabled(value)
                end,
        })
        Elements.bossWebhookToggle = bossWebhookToggle
        tryCreate(ConfigTab, "CreateInput", {
                name = "Webhook URL",
                placeholder = "https://discord.com/api/webhooks/...",
                flag = "BossWebhookUrl",
                callback = function(text)
                        WebhookController.setBossUrl(text)
                end,
        })
        local bossNotifyToggle
        bossNotifyToggle = ConfigTab:CreateToggle({
                name = "Boss Kill Notifications",
                description = "Webhook fires when a farmed boss dies",
                value = true,
                flag = "BossWebhookNotifyKills",
                callback = function(value)
                        WebhookController.setBossNotifyKills(value)
                end,
        })
        Elements.bossNotifyToggle = bossNotifyToggle
        local bossWebhookRow = ConfigTab:CreateGroup()
        bossWebhookRow:CreateButton({
                name = "Test Webhook",
                description = "Sends a clearly labeled test message - no kill is announced",
                callback = function()
                        WebhookController.testBossWebhook()
                end,
        })
        Elements.bossWebhookStatus = ConfigTab:CreateText({
                name = "Webhook Status",
                text = WebhookController.getBossStatusText(),
        })

        tryCreate(ConfigTab, "CreateDivider", {})

        ConfigTab:CreateSection({ name = "Performance" })
        ConfigTab:CreateDropdown({
                name = "FPS Boost",
                options = { "off", "basic", "full" },
                value = "off",
                flag = "SetFpsBoost",
                callback = function(option)
                        SettingsController.setFpsBoost(normalizeChoice(option))
                end,
        })
        local fullbrightToggle
        fullbrightToggle = ConfigTab:CreateToggle({
                name = "Fullbright",
                value = false,
                flag = "SetFullbright",
                callback = function(value)
                        SettingsController.setFullbright(value)
                end,
        })
        Elements.fullbrightToggle = fullbrightToggle
        local autoPerfToggle
        autoPerfToggle = ConfigTab:CreateToggle({
                name = "Auto Performance",
                description = "Slows update loops when FPS drops, restores on recovery",
                value = false,
                flag = "SetAutoPerformance",
                callback = function(value)
                        SettingsController.setAutoPerformance(value)
                end,
        })
        Elements.autoPerfToggle = autoPerfToggle

        ConfigTab:CreateSection({ name = "Debug" })
        local logConsole = ConfigTab:CreateConsole({
                name = "Log Console",
                height = 140,
                follow = true,
                maxLines = 200,
        })
        Logger.setOnLog(function(line)
                pcall(function()
                        logConsole:Append(line)
                end)
        end)
        pcall(function()
                logConsole:Set(Logger.getHistory())
        end)
        local consoleRow = ConfigTab:CreateGroup()
        consoleRow:CreateButton({
                name = "Copy Logs",
                callback = function()
                        SettingsController.copyLogs()
                end,
        })
        consoleRow:CreateButton({
                name = "Clear Logs",
                callback = function()
                        SettingsController.clearLogs()
                        pcall(function()
                                logConsole:Clear()
                        end)
                end,
        })
        local debugRow = ConfigTab:CreateGroup()
        local debugToggle
        debugToggle = debugRow:CreateToggle({
                name = "Debug Logging",
                description = "Shows [DEBUG] lines - off by default so users are not flooded",
                value = false,
                flag = "SetDebugLogging",
                callback = function(value)
                        Logger.debugEnabled = value and true or false
                        Logger.info("debug logging " .. (value and "enabled" or "disabled"))
                end,
        })
        Elements.debugToggle = debugToggle
        -- dropdowns cannot live inside a row group in Rayfield Gen2 (rows only hold button/toggle/stat/slider)
        ConfigTab:CreateDropdown({
                name = "Minimum Level",
                options = { "INFO", "WARN", "ERROR" },
                value = "INFO",
                flag = "SetLogLevel",
                callback = function(option)
                        local level = normalizeChoice(option)
                        if level == "WARN" then
                                Logger.minLevel = 1
                        elseif level == "ERROR" then
                                Logger.minLevel = 2
                        else
                                Logger.minLevel = 0
                        end
                end,
        })
        ConfigTab:CreateButton({
                name = "Dump Discovered Targets",
                description = "Prints every nearby humanoid candidate - the tool that fills GameProfile",
                callback = function()
                        task.spawn(function()
                                DiscoveryController.dump()
                        end)
                end,
        })
        local trackerStats = ConfigTab:CreateGroup()
        Elements.statConnections = trackerStats:CreateStat({ name = "Connections", value = 0 })
        Elements.statLoops = trackerStats:CreateStat({ name = "Loops", value = 0 })
        Tracker.setRunning("debugstats", true)
        task.spawn(function()
                while Tracker.isRunning("debugstats") do
                        task.wait(2)
                        local connections, loops = Tracker.stats()
                        pcall(function()
                                Elements.statConnections:Set(connections)
                                Elements.statLoops:Set(loops)
                        end)
                end
        end)

        ConfigTab:CreateSection({ name = "Project" })
        ConfigTab:CreateText({
                name = "PS2 Hub " .. VERSION,
                text = "Made by Faludaddd. Source: " .. REPO_URL,
        })
        local autoReexecToggle
        autoReexecToggle = ConfigTab:CreateToggle({
                name = "Auto Re-execute on Teleport",
                value = true,
                flag = "SetAutoReexecute",
                callback = function(value)
                        SettingsController.setAutoReexecute(value)
                end,
        })
        Elements.autoReexecToggle = autoReexecToggle
        ConfigTab:CreateKeybind({
                name = "Emergency Stop Key",
                description = "Global panic key - kills every active feature instantly",
                value = Enum.KeyCode.P,
                flag = "SetEmergencyKey",
                callback = function()
                        SettingsController.emergencyStop()
                        syncAllOff()
                end,
        })
        local lifecycleRow = ConfigTab:CreateGroup()
        lifecycleRow:CreateButton({
                name = "Emergency Stop",
                description = "Kills automation, fly, noclip, speed, ESP and more",
                callback = function()
                        SettingsController.emergencyStop()
                        syncAllOff()
                end,
        })
        lifecycleRow:CreateButton({
                name = "Reload",
                description = "Clean shutdown, then re-execute",
                callback = function()
                        SettingsController.reloadScript()
                end,
        })
        lifecycleRow:CreateButton({
                name = "Destroy",
                callback = function()
                        pcall(function()
                                Window:Popup({
                                        title = "Destroy the UI?",
                                        content = "Every feature stops, all connections and loops are cleaned up, and the UI is destroyed. You will need to re-execute the script to bring it back.",
                                        options = {
                                                { text = "Cancel" },
                                                {
                                                        text = "Destroy",
                                                        style = "danger",
                                                        callback = function()
                                                                SettingsController.destroyUi()
                                                        end,
                                                },
                                        },
                                })
                        end)
                end,
        })
        ConfigTab:CreateButton({
                name = "Check for Updates",
                callback = function()
                        SettingsController.checkUpdate()
                end,
        })
        ConfigTab:CreateButton({
                name = "Copy Execute URL",
                callback = function()
                        SettingsController.copySource()
                end,
        })
end)

buildTab("Settings", function()
        SettingsTab:CreateSection({ name = "Configuration" })
        local configDropdown
        local configName
        configDropdown = SettingsTab:CreateDropdown({
                name = "Saved Configs",
                options = {},
                placeholder = "None saved yet",
                description = "Selecting pre-fills the name field below",
                forgetState = true,
                callback = function(option)
                        local name = normalizeChoice(option)
                        if name ~= "" and configName then
                                safeSet(configName, name)
                        end
                end,
        })
        configName = tryCreate(SettingsTab, "CreateInput", {
                name = "Config Name",
                placeholder = "e.g. Questing",
                flag = "ConfigName",
                callback = function(text)
                        Logger.debug("config name set: " .. tostring(text))
                end,
        })
        local function refreshConfigs()
                pcall(function()
                        local list = Window:ListConfigs() or {}
                        configDropdown:Refresh(list)
                end)
        end
        refreshConfigs()
        local manageRow = SettingsTab:CreateGroup()
        manageRow:CreateButton({
                name = "Save",
                description = "Snapshot current state",
                callback = function()
                        local name = Util.trim(configName and configName.value or "")
                        local ok = false
                        pcall(function()
                                if name ~= "" then
                                        ok = Window:Save(name)
                                else
                                        ok = Window:Save()
                                end
                        end)
                        if ok then
                                Util.toast("Saved " .. (name ~= "" and name or "default"))
                        else
                                Util.notify("Configs", "Save failed")
                        end
                        refreshConfigs()
                end,
        })
        manageRow:CreateButton({
                name = "Load",
                description = "Applies through every element",
                callback = function()
                        local name = Util.trim(configName and configName.value or "")
                        local ok = false
                        pcall(function()
                                if name ~= "" then
                                        ok = Window:Load(name)
                                else
                                        ok = Window:Load()
                                end
                        end)
                        if ok then
                                Util.toast("Loaded " .. (name ~= "" and name or "default"))
                        else
                                Util.notify("Configs", "Load failed - check the name")
                        end
                end,
        })
        manageRow:CreateButton({
                name = "Delete",
                callback = function()
                        local name = Util.trim(configName and configName.value or "")
                        if name == "" then
                                Util.notify("Configs", "Enter a config name to delete")
                                return
                        end
                        local ok = false
                        pcall(function()
                                ok = Window:DeleteConfig(name)
                        end)
                        if ok then
                                Util.toast("Deleted " .. name)
                        else
                                Util.notify("Configs", "Delete failed - check the name")
                        end
                        refreshConfigs()
                end,
        })
        local configRow = SettingsTab:CreateGroup()
        configRow:CreateButton({
                name = "Refresh List",
                callback = function()
                        refreshConfigs()
                end,
        })
        configRow:CreateButton({
                name = "Reset Saved Config",
                callback = function()
                        SettingsController.resetConfig()
                end,
        })

        SettingsTab:CreateSection({ name = "Notifications" })
        local notificationsToggle
        notificationsToggle = SettingsTab:CreateToggle({
                name = "Notifications",
                description = "Cards for meaningful events",
                value = true,
                flag = "SetNotifications",
                callback = function(value)
                        SettingsController.setNotifications(value)
                end,
        })
        Elements.notificationsToggle = notificationsToggle
        SettingsTab:CreateSlider({
                name = "Notification Duration",
                range = { 1, 15 },
                increment = 1,
                suffix = " s",
                value = 3,
                flag = "SetNotifDuration",
                callback = function(value)
                        SettingsController.setNotifDuration(value)
                end,
        })

        SettingsTab:CreateSection({ name = "Appearance" })
        local THEMES = { "default", "cobalt", "ember", "amethyst", "frost", "rose" }
        SettingsTab:CreateDropdown({
                name = "Theme",
                options = THEMES,
                value = "ember",
                flag = "UITheme",
                callback = function(theme)
                        pcall(function()
                                Window:ChangeTheme(normalizeChoice(theme))
                        end)
                end,
        })
        SettingsTab:CreateKeybind({
                name = "UI Toggle",
                description = "Show / hide the window",
                value = Enum.KeyCode.RightControl,
                flag = "UIToggleKey",
                callback = function()
                        pcall(function()
                                Window:ToggleHide()
                        end)
                end,
        })
end)

Logger.info("PS2 Hub " .. VERSION .. " loaded")
Util.notify("PS2 Hub", "Loaded v" .. VERSION .. " - game status: " .. GameDetector.getStatusText(), 4)

-- must stay last: fires the game profile after every controller and UI onLoad handler registered
GameDetector.ensureLoaded()
