local VERSION = "2.5.0"
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
local HttpService = GetService("HttpService")
local Stats = GetService("Stats")
local CoreGui = GetService("CoreGui")

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
                local onLoadHandlers = {}

                function GameProfile.onLoad(fn)
                        if type(fn) == "function" then
                                table.insert(onLoadHandlers, fn)
                        end
                end

                GameProfile.gameName = "Project Slayers 2"
                GameProfile.targetPlaceIds = {}
                GameProfile.ready = false
                GameProfile.status = "PENDING_RELEASE"
                GameProfile.lockReason = "Project Slayers 2 is not released yet. Game-specific features stay locked until the instance data is provided."

                GameProfile.data = {
                                npcs = {},
                                teleportPoints = {},
                                quests = {},
                                remotes = {},
                                mobs = {},
                                bosses = {},
                                spiderLilies = {},
                                clans = {
                                                menuGui = "",
                                                rerollButton = "",
                                                rerollRemote = "",
                                                clanLabel = "",
                                                clanList = {},
                                },
                                stats = {},
                }

                function GameProfile.load(profileData)
                                if type(profileData) ~= "table" then
                                                Logger.warn("GameProfile.load expects a table")
                                                return false
                                end
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
                                return true
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
                                for segment in string.gmatch(path, "[^./]+") do
                                                if node == nil then
                                                                return nil
                                                end
                                                node = node:FindFirstChild(segment)
                                end
                                return node
                end
end

local GameDetector = {}
do
                local detected = nil

                function GameDetector.detect()
                                if detected then return detected end
                                local placeId = game.PlaceId
                                local jobId = game.JobId
                                local matched = nil
                                for _, id in ipairs(GameProfile.targetPlaceIds) do
                                                if id == placeId then
                                                                matched = true
                                                                break
                                                end
                                end
                                detected = {
                                                placeId = placeId,
                                                jobId = jobId,
                                                gameName = (placeId > 0 and game.Name) or "Unknown",
                                                creator = (placeId > 0 and game.Creator.Name) or "",
                                                inPS2 = matched == true,
                                                supported = GameProfile.ready and matched == true,
                                }
                                return detected
                end

                function GameDetector.getStatusText()
                                local info = GameDetector.detect()
                                if info.supported then
                                                return "Supported"
                                end
                                if not GameProfile.ready then
                                                return "Awaiting release"
                                end
                                return "Wrong game"
                end

                function GameDetector.isGameReady()
                                local info = GameDetector.detect()
                                return info.supported
                end

                function GameDetector.requireGame(featureName)
                                if GameDetector.isGameReady() then
                                                return true
                                end
                                local status = GameDetector.getStatusText()
                                Util.notify(featureName or "Feature", "Locked - " .. status .. ". " .. GameProfile.lockReason, 5)
                                Logger.warn((featureName or "feature") .. " blocked: " .. status)
                                return false
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

        function ServerController.rejoin()
                local placeId = game.PlaceId
                local jobId = game.JobId
                Util.notify("Rejoin", "Rejoining current server...")
                queueReexecute()
                task.wait(0.3)
                if jobId ~= "" then
                        TeleportService:TeleportToPlaceInstance(placeId, jobId, LocalPlayer)
                else
                        TeleportService:Teleport(placeId, LocalPlayer)
                end
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
                lastHopAt = now
                Util.notify("Server Hop", "Looking for a server...")
                local servers = fetchServers()
                if not servers then
                        Util.notify("Server Hop", "Could not fetch the server list")
                        return false
                end
                local best = nil
                for _, server in ipairs(servers) do
                        if server.id ~= game.JobId and server.players < server.maxPlayers then
                                if ServerController.rememberVisited and visited[server.id] then
                                        continue
                                end
                                local skip = false
                                if mode == "lowest" and server.players > ServerController.lowMax then
                                        skip = true
                                end
                                if not skip then
                                        if mode == "lowest" then
                                                if not best or server.players < best.players then
                                                        best = server
                                                end
                                        elseif mode == "highest" then
                                                if not best or server.players > best.players then
                                                        best = server
                                                end
                                        else
                                                best = server
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
                Util.notify("Server Hop", "Joining server with " .. best.players .. " players")
                queueReexecute()
                task.wait(0.3)
                TeleportService:TeleportToPlaceInstance(game.PlaceId, best.id, LocalPlayer)
                return true
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
                mode = "Reroll Once",
                target = "",
                delay = 1.5,
                maxRerolls = 10,
        }
        ClanController.sessionRerolls = 0

        local function readCurrentClan()
                local clanLabel = GameProfile.get("clans.clanLabel")
                local label = GameProfile.resolvePath(clanLabel)
                if label and label:IsA("TextLabel") then
                        return label.Text
                end
                return nil
        end

        local function triggerRerollButton()
                local buttonPath = GameProfile.get("clans.rerollButton")
                local button = GameProfile.resolvePath(buttonPath)
                if not button or not button:IsA("GuiButton") then
                        Logger.warn("clan reroll button not found: " .. tostring(buttonPath))
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

        local function fireRerollRemote()
                local remotePath = GameProfile.get("clans.rerollRemote")
                local remote = GameProfile.resolvePath(remotePath)
                if not remote then
                        return false
                end
                if remote:IsA("RemoteEvent") then
                        remote:FireServer()
                        return true
                end
                if remote:IsA("RemoteFunction") then
                        pcall(function() remote:InvokeServer() end)
                        return true
                end
                if remote:IsA("UnboundRemoteEvent") then
                        pcall(function() remote:FireServer() end)
                        return true
                end
                return false
        end

        function ClanController.doReroll()
                if not GameDetector.requireGame("Clan Reroll") then
                        return nil
                end
                if GameProfile.get("clans.rerollRemote") and GameProfile.get("clans.rerollRemote") ~= "" then
                        fireRerollRemote()
                elseif GameProfile.get("clans.rerollButton") and GameProfile.get("clans.rerollButton") ~= "" then
                        if not triggerRerollButton() then
                                Util.notify("Clan Reroll", "Reroll button not reachable")
                                return nil
                        end
                else
                        Util.notify("Clan Reroll", "No reroll action data in profile yet")
                        return nil
                end
                ClanController.sessionRerolls += 1
                task.wait(ClanController.settings.delay)
                return readCurrentClan()
        end

        local rerollLoopActive = false
        function ClanController.setEnabled(enabled)
                local want = enabled and true or false
                if ClanController.settings.enabled == want then
                        return want
                end
                if enabled then
                        if not GameDetector.requireGame("Clan Reroll") then
                                return false
                        end
                        local hasRemote = (GameProfile.get("clans.rerollRemote") or "") ~= ""
                        local hasButton = (GameProfile.get("clans.rerollButton") or "") ~= ""
                        if not hasRemote and not hasButton then
                                Util.notify("Clan Reroll", "Locked until clan menu instance data is added", 5)
                                return false
                        end
                        ClanController.settings.enabled = true
                        Tracker.setRunning("clan", true)
                        if ClanController.settings.mode == "Reroll Until Target" then
                                rerollLoopActive = true
                                task.spawn(function()
                                        local attempts = 0
                                        while rerollLoopActive and Tracker.isRunning("clan") do
                                                if attempts >= ClanController.settings.maxRerolls then
                                                        Util.notify("Clan Reroll", "Reroll limit reached (" .. attempts .. ")")
                                                        break
                                                end
                                                attempts += 1
                                                local result = ClanController.doReroll()
                                                if result and ClanController.settings.target ~= "" and result == ClanController.settings.target then
                                                        Util.notify("Clan Reroll", "Target clan obtained: " .. result)
                                                        break
                                                end
                                                task.wait(0.2)
                                        end
                                        rerollLoopActive = false
                                end)
                        elseif ClanController.settings.mode == "Fixed Count" then
                                rerollLoopActive = true
                                task.spawn(function()
                                        local attempts = 0
                                        while rerollLoopActive and Tracker.isRunning("clan") and attempts < ClanController.settings.maxRerolls do
                                                attempts += 1
                                                ClanController.doReroll()
                                        end
                                        rerollLoopActive = false
                                        Util.notify("Clan Reroll", "Done - " .. attempts .. " reroll(s)")
                                end)
                        else
                                task.spawn(function()
                                        ClanController.doReroll()
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
                ClanController.settings.mode = mode or "Reroll Once"
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
                if not GameDetector.requireGame("Clan Reroll") then
                        return false, "Locked until release"
                end
                local result = ClanController.doReroll()
                if result == nil then
                        return false, "Reroll could not fire"
                end
                return true, result
        end

        function ClanController.getCurrentClan()
                if not GameDetector.isGameReady() then
                        return "Locked"
                end
                return readCurrentClan() or "Unknown"
        end

        function ClanController.getClanOptions()
                local list = GameProfile.get("clans.clanList")
                if type(list) == "table" and #list > 0 then
                        return list
                end
                return { "None loaded" }
        end

        function ClanController.getStatusText()
                if GameDetector.isGameReady() then
                        return "Current clan: " .. ClanController.getCurrentClan() .. " | Rerolls this session: " .. tostring(ClanController.sessionRerolls)
                end
                return "Clan reroll runs through the in-game main menu. Locked until release - menu instance data required. Rerolls this session: " .. tostring(ClanController.sessionRerolls)
        end
end

local DiscoveryController = {}
do
        DiscoveryController.lastSummary = "No scan yet"

        function DiscoveryController.dump()
                local found = {}
                local scanned = 0
                local function scanContainer(container, depth)
                        if depth > 3 or scanned > 2500 then
                                return
                        end
                        for _, child in ipairs(container:GetChildren()) do
                                scanned += 1
                                if child:IsA("Model") then
                                        local player = Players:GetPlayerFromCharacter(child)
                                        if not player then
                                                local humanoid = child:FindFirstChildOfClass("Humanoid")
                                                if humanoid then
                                                        local root = child:FindFirstChild("HumanoidRootPart") or child.PrimaryPart
                                                        if root then
                                                                local dist = Util.distanceTo(root)
                                                                if dist <= 3000 then
                                                                        table.insert(found, {
                                                                                name = child.Name,
                                                                                path = child:GetFullName(),
                                                                                health = humanoid.Health,
                                                                                maxHealth = humanoid.MaxHealth,
                                                                                dist = Util.round(dist, 0),
                                                                        })
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
                table.sort(found, function(a, b)
                        return a.dist < b.dist
                end)
                Logger.info("target dump: " .. #found .. " candidate(s) within 3000 studs")
                for i, entry in ipairs(found) do
                        if i <= 25 then
                                Logger.info(string.format("  %02d: %s  hp=%d/%d  dist=%d  path=%s",
                                        i, entry.name, entry.health, entry.maxHealth, entry.dist, entry.path))
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

local AutomationController = {}
do
        AutomationController.settings = {
                target = "",
                exclusions = {},
                maxRange = 2000,
                moveMethod = "Magnitize",
                moveSpeed = 60,
                distance = 4,
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

        function AutomationController.setMoveMethod(method)
                AutomationController.settings.moveMethod = method or "Magnitize"
        end

        function AutomationController.setMoveSpeed(value)
                AutomationController.settings.moveSpeed = value
        end

        function AutomationController.setDistance(value)
                AutomationController.settings.distance = value
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
                        return "Automation locked - PS2 instance data required after release"
                end
                return "Automation ready - quest and boss engines arrive with the game instance file"
        end

        function AutomationController.scanQuestSystem()
                local givers = {}
                local scanned = 0
                local function scanContainer(container, depth)
                        if depth > 3 or scanned > 2500 then
                                return
                        end
                        for _, child in ipairs(container:GetChildren()) do
                                scanned += 1
                                if child:IsA("Model") then
                                        local humanoid = child:FindFirstChildOfClass("Humanoid")
                                        if humanoid then
                                                local hasDialog = child:FindFirstChildOfClass("Dialog") ~= nil
                                                local hasPrompt = false
                                                for _, d in ipairs(child:GetDescendants()) do
                                                        if d:IsA("ProximityPrompt") then
                                                                hasPrompt = true
                                                                break
                                                        end
                                                end
                                                if hasDialog or hasPrompt then
                                                        table.insert(givers, { name = child.Name, path = child:GetFullName(), dialog = hasDialog, prompt = hasPrompt })
                                                end
                                        end
                                        scanContainer(child, depth + 1)
                                elseif child:IsA("Folder") then
                                        scanContainer(child, depth + 1)
                                end
                        end
                end
                scanContainer(Workspace, 1)
                local objectives = {}
                pcall(function()
                        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
                        if not playerGui then
                                return
                        end
                        for _, gui in ipairs(playerGui:GetDescendants()) do
                                if gui:IsA("TextLabel") and gui.Text ~= "" then
                                        local lower = gui.Text:lower()
                                        if lower:find("quest") or lower:find("objective") or lower:find("slay") or lower:find("defeat") or lower:find("collect") then
                                                table.insert(objectives, { text = gui.Text, path = gui:GetFullName() })
                                                if #objectives >= 10 then
                                                        break
                                                end
                                        end
                                end
                        end
                end)
                Logger.info("quest scan: " .. #givers .. " giver candidate(s), " .. #objectives .. " objective label(s)")
                for i, giver in ipairs(givers) do
                        if i <= 15 then
                                local tags = (giver.dialog and " [Dialog]" or "") .. (giver.prompt and " [Prompt]" or "")
                                Logger.info("  giver " .. string.format("%02d", i) .. ": " .. giver.name .. "  path=" .. giver.path .. tags)
                        end
                end
                for _, objective in ipairs(objectives) do
                        Logger.info("  objective: \"" .. objective.text .. "\"  path=" .. objective.path)
                end
                local summary = #givers .. " giver(s), " .. #objectives .. " objective label(s) - details in the log console"
                Util.notify("Quest Scan", summary, 6)
                return summary
        end
end

local QuestDetector = {}
do
        QuestDetector.status = "Idle"

        function QuestDetector.getPlayerLevel()
                return nil
        end

        function QuestDetector.findQuestGivers()
                return {}
        end

        function QuestDetector.selectQuestForLevel(level)
                return nil
        end

        function QuestDetector.hasQuestData()
                local quests = GameProfile.data.quests
                return type(quests) == "table" and next(quests) ~= nil
        end

        function QuestDetector.getQuestOptions()
                local quests = GameProfile.data.quests
                local list = {}
                if type(quests) ~= "table" then
                        return list
                end
                if #quests > 0 then
                        for _, quest in ipairs(quests) do
                                local label = type(quest) == "table" and (quest.name or quest.Name) or nil
                                table.insert(list, label or tostring(quest))
                        end
                else
                        for name in pairs(quests) do
                                table.insert(list, name)
                        end
                        table.sort(list)
                end
                return list
        end
end

local BossDetector = {}
do
        BossDetector.status = "Idle"

        function BossDetector.hasBossData()
                local bosses = GameProfile.data.bosses
                return type(bosses) == "table" and next(bosses) ~= nil
        end

        function BossDetector.getBossOptions()
                local bosses = GameProfile.data.bosses
                local list = {}
                if type(bosses) ~= "table" then
                        return list
                end
                if #bosses > 0 then
                        for _, boss in ipairs(bosses) do
                                local label = type(boss) == "table" and (boss.name or boss.Name) or nil
                                table.insert(list, label or tostring(boss))
                        end
                else
                        for name in pairs(bosses) do
                                table.insert(list, name)
                        end
                        table.sort(list)
                end
                return list
        end

        function BossDetector.scan()
                return {}
        end
end

local SpiderLilyDetector = {}
do
        SpiderLilyDetector.status = "Idle"

        function SpiderLilyDetector.hasSpiderLilyData()
                local lilies = GameProfile.data.spiderLilies
                return type(lilies) == "table" and next(lilies) ~= nil
        end

        function SpiderLilyDetector.scan()
                return {}
        end

        function SpiderLilyDetector.getDetectedCount()
                return 0
        end
end

local CombatHandler = {}
do
        CombatHandler.questMethod = "Melee"
        CombatHandler.bossMethod = "Melee"
        local combatNotified = false

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

        function CombatHandler.attack(target)
                if target == nil then
                        return false
                end
                if not combatNotified then
                        combatNotified = true
                        Logger.info("combat handler armed - attack logic pending the game instance file")
                end
                return false
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

        local function autoQuestLoop()
                local announced = false
                while Tracker.isRunning("autoquest") do
                        task.wait(1)
                        if not announced then
                                announced = true
                                Logger.info("auto quest placeholder running - engine logic arrives with the game instance file")
                        end
                        if QuestDetector.hasQuestData() then
                                AutoQuestController.setState("Searching for Quest")
                        else
                                AutoQuestController.setState("No Suitable Quest Found")
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
                        if not QuestDetector.hasQuestData() then
                                Util.notify("Auto Quest", "No quest data in game profile yet")
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
                local announced = false
                while Tracker.isRunning("autodemon") do
                        task.wait(1)
                        if not announced then
                                announced = true
                                Logger.info("auto demon placeholder running - spider lily logic arrives with the game instance file")
                        end
                        if SpiderLilyDetector.hasSpiderLilyData() then
                                AutoDemonController.status.detection = "Detecting"
                                AutoDemonController.setState("Detecting Spider Lilies")
                        else
                                AutoDemonController.status.detection = "No data"
                                AutoDemonController.setState("No Spider Lilies Found")
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
                        if not SpiderLilyDetector.hasSpiderLilyData() then
                                Util.notify("Auto Demon", "No Spider Lily data in game profile yet")
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
                selectedBoss = "",
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

        local function autoBossLoop()
                local announced = false
                while Tracker.isRunning("autoboss") do
                        task.wait(1)
                        if not announced then
                                announced = true
                                Logger.info("auto boss placeholder running - boss logic arrives with the game instance file")
                        end
                        if AutoBossController.settings.selectedBoss ~= "" or BossDetector.hasBossData() then
                                AutoBossController.setState("Detecting Boss")
                        else
                                AutoBossController.setState("No Boss Found")
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
                        if AutoBossController.settings.selectedBoss == "" and not BossDetector.hasBossData() then
                                Util.notify("Auto Boss", "No boss selected and no boss data in game profile yet")
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
                AutoBossController.resetStatus()
                return true
        end

        function AutoBossController.setBoss(name)
                AutoBossController.settings.selectedBoss = name or ""
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
end

local KillAuraController = {}
do
        KillAuraController.settings = {
                enabled = false,
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
                local target = AutoQuestController.getTargetModel()
                if target == nil then
                        target = AutoBossController.getTargetModel()
                end
                return target
        end

        local function killAuraLoop()
                while Tracker.isRunning("killaura") do
                        task.wait(0.25)
                        local target = resolveTarget()
                        if target ~= nil then
                                KillAuraController.setCurrentTarget(target)
                                CombatHandler.attack(target)
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

        function KillAuraController.getStatusText()
                if KillAuraController.settings.enabled then
                        return KillAuraController.status.state .. " - " .. KillAuraController.status.targetName
                end
                return "Disabled"
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

        function LocationDetector.ScanLocations()
                local found = {}
                local points = GameProfile.data.teleportPoints
                if type(points) ~= "table" then
                        return found
                end
                if #points > 0 then
                        for _, point in ipairs(points) do
                                if type(point) == "table" then
                                        table.insert(found, {
                                                name = point.name or point.Name,
                                                path = point.path or point.Path or "",
                                        })
                                else
                                        table.insert(found, { name = point, path = "" })
                                end
                        end
                else
                        for name, path in pairs(points) do
                                if type(name) == "string" then
                                        table.insert(found, {
                                                name = name,
                                                path = type(path) == "string" and path or "",
                                        })
                                end
                        end
                end
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
        local scanAnnounced = false
        local teleportAnnounced = false
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
                if not scanAnnounced then
                        scanAnnounced = true
                        Logger.info("location framework ready - Workspace map detection arrives with the game instance file")
                end
                Logger.info("location refresh: " .. count .. " location(s)")
                pcall(locationsChanged, count)
                return count
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
                TeleportController.status = "Teleporting..."
                if not GameDetector.requireGame("Teleports") then
                        TeleportController.status = "Location unavailable"
                        return false
                end
                if not teleportAnnounced then
                        teleportAnnounced = true
                        Logger.info("teleport framework armed - movement method arrives with the game instance file")
                end
                TeleportController.status = "Location unavailable"
                Util.notify("Teleports", "Teleport execution arrives with the game instance file")
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

                function SettingsController.emergencyStop()
                                local ok = pcall(function()
                                                AutoQuestController.setEnabled(false)
                                                AutoDemonController.setEnabled(false)
                                                AutoBossController.setEnabled(false)
                                                KillAuraController.setEnabled(false)
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
local ClanTab = Window:CreateTab({ name = "Clan" })
pcall(function()
        Window:CreateSection({ name = "System" })
end)
local SettingsTab = Window:CreateTab({ name = "Settings" })
local UiSettingsTab = Window:CreateTab({ name = "UI Settings" })

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

do
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
                                taskLine = "Clan reroll active - " .. tostring(ClanController.sessionRerolls) .. " reroll(s)"
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
                text = "Game-specific features (Auto Quest, Auto Demon, Auto Boss, Kill Aura, Clan Reroll) stay locked until the game releases and the instance data is added. Teleports runs as a framework now and fills its location list once the map detection arrives. Universal features work in every game.",
        })
        HomeTab:CreateButton({
                name = "Check for Updates",
                callback = function()
                        SettingsController.checkUpdate()
                end,
        })
end

do
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
end

do
        MainTab:CreateSection({ name = "Auto Quest" })
        MainTab:CreateText({
                name = "Locked",
                text = "Auto Quest, Auto Demon and Auto Boss need Project Slayers 2 instance data (quests, NPCs, bosses, Spider Lilies, remotes) and unlock automatically once the game profile loads. Teleports is live as a framework - it finds no locations until the map detection arrives with the instance file.",
        })
        local autoQuestToggle
        autoQuestToggle = MainTab:CreateToggle({
                name = "Auto Quest",
                description = "Finds the right quest for your level, completes it, then continues to the next one",
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
                description = "Populated from the game profile once the instance file is loaded",
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
                description = "Populated with the bosses detected from the game once the instance file is loaded",
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

        tryCreate(MainTab, "CreateDivider", {})

        MainTab:CreateSection({ name = "Teleports" })
        local locationDropdown
        locationDropdown = MainTab:CreateDropdown({
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
        local teleportRow = MainTab:CreateGroup()
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
        teleportAutoRefreshToggle = MainTab:CreateToggle({
                name = "Auto Refresh Locations",
                description = "Re-scans the map every 30 s while enabled",
                value = false,
                flag = "TeleportAutoRefresh",
                callback = function(value)
                        TeleportController.setAutoRefresh(value)
                end,
        })
        Elements.teleportAutoRefresh = teleportAutoRefreshToggle
        Elements.locationStatus = MainTab:CreateText({
                name = "Location Status",
                text = TeleportController.getStatusText(),
        })
        syncLocationStatus = function()
                pcall(function()
                        Elements.locationStatus:Set(TeleportController.getStatusText())
                end)
        end

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
        MainTab:CreateDropdown({
                name = "Movement Method",
                options = { "Auto", "Magnitize", "Teleport", "Tween", "Walk" },
                value = "Auto",
                description = "Auto escalates to teleport when stuck",
                flag = "FarmMoveMethod",
                callback = function(option)
                        AutomationController.setMoveMethod(normalizeChoice(option))
                end,
        })
        local moveRow = MainTab:CreateGroup()
        moveRow:CreateSlider({
                name = "Movement Speed",
                description = "Used by the Tween method",
                range = { 5, 300 },
                increment = 1,
                suffix = " sps",
                value = 60,
                flag = "FarmMoveSpeed",
                callback = function(value)
                        AutomationController.setMoveSpeed(value)
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
                        AutomationController.setDistance(value)
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
                text = "Recovery behaviors (respawn resume, stuck movement escalation, target re-acquisition) return together with the quest and boss engines once the game instance file is loaded.",
        })

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
                task.spawn(function()
                        TeleportController.RefreshLocations()
                end)
        end)

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
                        syncText("locationStatus", TeleportController.getStatusText())
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
end

do
        ClanTab:CreateSection({ name = "Clan Reroll" })
        ClanTab:CreateText({
                name = "Main Menu Reroll",
                text = "Clan reroll in Project Slayers 2 is done through the game's main menu (no NPC involved). This module triggers the menu's reroll action. Locked until release - needs the menu GUI and reroll remote paths from the instance file.",
        })
        tryCreate(ClanTab, "CreateInput", {
                name = "Target Clan",
                placeholder = "Clan name (case-insensitive)",
                flag = "ClanTarget",
                callback = function(text)
                        ClanController.setTarget(Util.trim(text))
                end,
        })
        Elements.clanStatus = ClanTab:CreateText({
                name = "Status",
                text = ClanController.getStatusText(),
        })
        local clanToggle
        clanToggle = ClanTab:CreateToggle({
                name = "Auto Reroll",
                description = "Rerolls until the target clan or the reroll limit",
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

        ClanTab:CreateDropdown({
                name = "Stop Mode",
                options = { "Reroll Once", "Fixed Count", "Reroll Until Target" },
                value = "Reroll Once",
                flag = "ClanMode",
                callback = function(option)
                        ClanController.setMode(normalizeChoice(option))
                end,
        })

        local clanRow = ClanTab:CreateGroup()
        clanRow:CreateSlider({
                name = "Max Rerolls",
                range = { 1, 200 },
                increment = 1,
                value = 10,
                flag = "ClanMaxRerolls",
                callback = function(value)
                        ClanController.setMaxRerolls(value)
                end,
        })
        local rerollButton
        rerollButton = clanRow:CreateButton({
                name = "Reroll Once",
                description = "Fires the reroll right now, no loop",
                callback = function()
                        task.spawn(function()
                                local ok, msg = ClanController.rerollOnce()
                                if ok then
                                        Util.notify("Clan", "Reroll fired (" .. tostring(ClanController.sessionRerolls) .. " total) - " .. tostring(msg))
                                else
                                        Util.notify("Clan", tostring(msg))
                                end
                                pcall(function()
                                        Elements.clanStatus:Set(ClanController.getStatusText())
                                end)
                        end)
                end,
        })
        lockUntilRelease(rerollButton)

        local clanRow2 = ClanTab:CreateGroup()
        clanRow2:CreateSlider({
                name = "Reroll Delay",
                range = { 0.5, 10 },
                increment = 0.5,
                suffix = " s",
                value = 1.5,
                flag = "ClanDelay",
                callback = function(value)
                        ClanController.setDelay(value)
                end,
        })
        Elements.statRerolls = clanRow2:CreateStat({ name = "Rerolls", value = 0 })

        ClanTab:CreateButton({
                name = "Refresh Clan Status",
                callback = function()
                        pcall(function()
                                Elements.clanStatus:Set(ClanController.getStatusText())
                        end)
                end,
        })

        Tracker.setRunning("clanstatus", true)
        task.spawn(function()
                local lastLine = nil
                local lastRerolls = -1
                while Tracker.isRunning("clanstatus") do
                        task.wait(2)
                        local line = ClanController.getStatusText()
                        local rerolls = ClanController.sessionRerolls
                        if line ~= lastLine or rerolls ~= lastRerolls then
                                lastLine = line
                                lastRerolls = rerolls
                                pcall(function()
                                        Elements.clanStatus:Set(line)
                                        Elements.statRerolls:Set(rerolls)
                                end)
                        end
                end
        end)
end

do
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
end

do
        ServerTab:CreateSection({ name = "Server Actions" })
        local actionRow = ServerTab:CreateGroup()
        actionRow:CreateButton({
                name = "Rejoin",
                callback = function()
                        ServerController.rejoin()
                end,
        })
        actionRow:CreateButton({
                name = "Server Hop",
                description = "Skips servers you already visited this session",
                callback = function()
                        ServerController.hop(ServerController.hopMode)
                end,
        })
        actionRow:CreateButton({
                name = "Low Player Hop",
                description = "Only servers at or below the player filter",
                callback = function()
                        ServerController.hop("lowest")
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
end

do
        SettingsTab:CreateSection({ name = "Auto Quest Settings" })
        SettingsTab:CreateDropdown({
                name = "Quest Combat Method",
                options = { "Melee", "Sword" },
                value = "Melee",
                description = "How Auto Quest fights quest mobs - wired up with the game instance file",
                flag = "SetQuestCombat",
                callback = function(option)
                        CombatHandler.setQuestMethod(normalizeChoice(option))
                end,
        })

        SettingsTab:CreateSection({ name = "Auto Boss Settings" })
        SettingsTab:CreateDropdown({
                name = "Boss Combat Method",
                options = { "Melee", "Sword" },
                value = "Melee",
                description = "How Auto Boss fights bosses - wired up with the game instance file",
                flag = "SetBossCombat",
                callback = function(option)
                        CombatHandler.setBossMethod(normalizeChoice(option))
                end,
        })

        SettingsTab:CreateSection({ name = "Kill Aura" })
        local killAuraToggle
        killAuraToggle = SettingsTab:CreateToggle({
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
        Elements.killAuraStatus = SettingsTab:CreateText({
                name = "Kill Aura Status",
                text = KillAuraController.getStatusText(),
        })

        tryCreate(SettingsTab, "CreateDivider", {})

        SettingsTab:CreateSection({ name = "Performance" })
        SettingsTab:CreateDropdown({
                name = "FPS Boost",
                options = { "off", "basic", "full" },
                value = "off",
                flag = "SetFpsBoost",
                callback = function(option)
                        SettingsController.setFpsBoost(normalizeChoice(option))
                end,
        })
        local fullbrightToggle
        fullbrightToggle = SettingsTab:CreateToggle({
                name = "Fullbright",
                value = false,
                flag = "SetFullbright",
                callback = function(value)
                        SettingsController.setFullbright(value)
                end,
        })
        Elements.fullbrightToggle = fullbrightToggle
        local autoPerfToggle
        autoPerfToggle = SettingsTab:CreateToggle({
                name = "Auto Performance",
                description = "Slows update loops when FPS drops, restores on recovery",
                value = false,
                flag = "SetAutoPerformance",
                callback = function(value)
                        SettingsController.setAutoPerformance(value)
                end,
        })
        Elements.autoPerfToggle = autoPerfToggle

        SettingsTab:CreateSection({ name = "Debug" })
        local logConsole = SettingsTab:CreateConsole({
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
        local consoleRow = SettingsTab:CreateGroup()
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
        local debugRow = SettingsTab:CreateGroup()
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
        debugRow:CreateDropdown({
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
        SettingsTab:CreateButton({
                name = "Dump Discovered Targets",
                description = "Prints every nearby humanoid candidate - the tool that fills GameProfile",
                callback = function()
                        task.spawn(function()
                                DiscoveryController.dump()
                        end)
                end,
        })
        local trackerStats = SettingsTab:CreateGroup()
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

        SettingsTab:CreateSection({ name = "Project" })
        SettingsTab:CreateText({
                name = "PS2 Hub " .. VERSION,
                text = "Made by Faludaddd. Source: " .. REPO_URL,
        })
        local autoReexecToggle
        autoReexecToggle = SettingsTab:CreateToggle({
                name = "Auto Re-execute on Teleport",
                value = true,
                flag = "SetAutoReexecute",
                callback = function(value)
                        SettingsController.setAutoReexecute(value)
                end,
        })
        Elements.autoReexecToggle = autoReexecToggle
        SettingsTab:CreateKeybind({
                name = "Emergency Stop Key",
                description = "Global panic key - kills every active feature instantly",
                value = Enum.KeyCode.P,
                flag = "SetEmergencyKey",
                callback = function()
                        SettingsController.emergencyStop()
                        syncAllOff()
                end,
        })
        local lifecycleRow = SettingsTab:CreateGroup()
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
        SettingsTab:CreateButton({
                name = "Check for Updates",
                callback = function()
                        SettingsController.checkUpdate()
                end,
        })
        SettingsTab:CreateButton({
                name = "Copy Execute URL",
                callback = function()
                        SettingsController.copySource()
                end,
        })
end

do
        UiSettingsTab:CreateSection({ name = "Configuration" })
        local configDropdown
        local configName
        configDropdown = UiSettingsTab:CreateDropdown({
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
        configName = tryCreate(UiSettingsTab, "CreateInput", {
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
        local manageRow = UiSettingsTab:CreateGroup()
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
        local configRow = UiSettingsTab:CreateGroup()
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

        UiSettingsTab:CreateSection({ name = "Notifications" })
        local notificationsToggle
        notificationsToggle = UiSettingsTab:CreateToggle({
                name = "Notifications",
                description = "Cards for meaningful events",
                value = true,
                flag = "SetNotifications",
                callback = function(value)
                        SettingsController.setNotifications(value)
                end,
        })
        Elements.notificationsToggle = notificationsToggle
        UiSettingsTab:CreateSlider({
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

        UiSettingsTab:CreateSection({ name = "Appearance" })
        local THEMES = { "default", "cobalt", "ember", "amethyst", "frost", "rose" }
        UiSettingsTab:CreateDropdown({
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
        UiSettingsTab:CreateKeybind({
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
end

Logger.info("PS2 Hub " .. VERSION .. " loaded")
Util.notify("PS2 Hub", "Loaded v" .. VERSION .. " - game status: " .. GameDetector.getStatusText(), 4)
