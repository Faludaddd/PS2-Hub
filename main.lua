local VERSION = "2.0.0"
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
	local levels = { info = 0, warn = 1, error = 2 }
	Logger.history = {}
	Logger.minLevel = 0

	local function push(level, msg)
		local entry = "[" .. os.date("%H:%M:%S") .. "] [" .. string.upper(level) .. "] " .. tostring(msg)
		table.insert(Logger.history, entry)
		if #Logger.history > 300 then
			table.remove(Logger.history, 1)
		end
		if levels[level] >= Logger.minLevel then
			print("[PS2 Hub] " .. entry)
		end
	end

	function Logger.info(msg) push("info", msg) end
	function Logger.warn(msg) push("warn", msg) end
	function Logger.error(msg) push("error", msg) end
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
		local Rayfield = _G.RayfieldInstance
		if Rayfield and Rayfield.Notify then
			pcall(Rayfield.Notify, Rayfield, {
				Title = title or "PS2 Hub",
				Content = content or "",
				Duration = duration or 3,
			})
		end
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
        MovementController.flySpeed = 60
        MovementController.sprintSpeed = 32
        MovementController.sprintKey = Enum.KeyCode.LeftShift
        MovementController.lockStats = false

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
                if humanoid then
                        humanoid.UseJumpPower = true
                        humanoid.JumpPower = MovementController.jumpPower
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

        function MovementController.setFlySpeed(value)
                MovementController.flySpeed = value
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
                MovementController.lockStats = enabled and true or false
                if enabled then
                        local conn
                        conn = RunService.Heartbeat:Connect(function()
                                local humanoid = Util.getHumanoid()
                                if humanoid then
                                        if not sprintActive and humanoid.WalkSpeed ~= MovementController.walkSpeed then
                                                humanoid.WalkSpeed = MovementController.walkSpeed
                                        end
                                        if humanoid.JumpPower ~= MovementController.jumpPower then
                                                humanoid.UseJumpPower = true
                                                humanoid.JumpPower = MovementController.jumpPower
                                        end
                                end
                        end)
                        Tracker.track(conn, "lockstats")
                else
                        Tracker.cleanup("lockstats")
                end
        end

        function MovementController.setInfiniteJump(enabled)
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
                if UserInputService:IsKeyDown(Enum.KeyCode.W) then
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

        function PlayerController.teleportToSelected()
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
                root.CFrame = rootTarget.CFrame * CFrame.new(0, 0, 3)
                return true
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
		names = true,
		distance = true,
		teamColor = false,
		tracers = false,
		maxDistance = 250,
	}

	local targets = {}
	local espGui = nil
	local drawingAvailable = false
	local updateConn = nil
	local playerConns = {}

	local COLORS = {
		player = Color3.fromRGB(255, 170, 0),
		npc = Color3.fromRGB(0, 255, 128),
		text = Color3.fromRGB(255, 255, 255),
	}

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

	local function addTarget(model, category, playerName)
		if targets[model] then
			return
		end
		local root = model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso") or model.PrimaryPart
		if not root then
			return
		end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end
		local highlight = Instance.new("Highlight")
		highlight.Name = "PS2HubESP_Highlight"
		highlight.Adornee = model
		highlight.FillTransparency = 0.7
		highlight.OutlineTransparency = 0
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		local baseColor = category == "players" and COLORS.player or COLORS.npc
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

		local nameLabel
		local distLabel
		local bb
		if ESPController.options.names or ESPController.options.distance then
			bb = Instance.new("BillboardGui")
			bb.Name = "PS2HubESP_Label"
			bb.Adornee = root
			bb.AlwaysOnTop = true
			bb.Size = UDim2.new(0, 220, 0, 44)
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
			bb.Parent = getEspGui()
		end

		local tracer
		if ESPController.options.tracers and category == "players" then
			tracer = makeTracer()
		end

		targets[model] = {
			category = category,
			highlight = highlight,
			billboard = bb,
			nameLabel = nameLabel,
			distLabel = distLabel,
			tracer = tracer,
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
		targets[model] = nil
	end

	local function clearCategory(category)
		for model, entry in pairs(targets) do
			if entry.category == category then
				removeTarget(model)
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
		for model, entry in pairs(targets) do
			local root = entry.root
			if not root or not root.Parent or not entry.humanoid or entry.humanoid.Health <= 0 then
				removeTarget(model)
			else
				local dist = myRoot and (root.Position - myRoot.Position).Magnitude or 0
				local inRange = dist <= ESPController.options.maxDistance
				if entry.highlight then
					entry.highlight.Enabled = inRange
				end
				if entry.billboard then
					entry.billboard.Enabled = inRange
					if entry.distLabel and ESPController.options.distance then
						entry.distLabel.Text = tostring(Util.round(dist, 0)) .. " studs"
					end
					if entry.nameLabel then
						entry.nameLabel.Visible = ESPController.options.names
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
	end

	function ESPController.setPlayers(enabled)
		ESPController.options.players = enabled and true or false
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

	local function scanNpcs()
		local playerChars = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				playerChars[player.Character] = true
			end
		end
		local found = {}
		for _, model in ipairs(Workspace:GetChildren()) do
			if model:IsA("Model") and not playerChars[model] and model ~= LocalPlayer.Character then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
					if root and Util.distanceTo(root) <= ESPController.options.maxDistance * 2 then
						found[model] = true
						addTarget(model, "npcs")
					end
				end
			end
		end
		for model, entry in pairs(targets) do
			if entry.category == "npcs" and not found[model] then
				removeTarget(model)
			end
		end
	end

	function ESPController.setNpcs(enabled)
		ESPController.options.npcs = enabled and true or false
		if enabled then
			Tracker.setRunning("npcscan", true)
			task.spawn(function()
				while Tracker.isRunning("npcscan") do
					local ok, err = pcall(scanNpcs)
					if not ok then
						Logger.warn("npc scan failed: " .. tostring(err))
					end
					task.wait(2)
				end
			end)
		else
			Tracker.setRunning("npcscan", false)
			clearCategory("npcs")
		end
	end

	function ESPController.setNames(enabled)
		ESPController.options.names = enabled and true or false
		for _, entry in pairs(targets) do
			if entry.nameLabel then
				entry.nameLabel.Visible = ESPController.options.names
			end
		end
		if enabled then
			for model, entry in pairs(targets) do
				if not entry.billboard then
					local category = entry.category
					local displayName = nil
					if category == "players" then
						local player = Players:GetPlayerFromCharacter(model)
						displayName = player and player.DisplayName or nil
					end
					removeTarget(model)
					addTarget(model, category, displayName)
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

	function ESPController.setMaxDistance(value)
		ESPController.options.maxDistance = value
	end

	function ESPController.init()
		drawingAvailable = (typeof(Drawing) == "table" and typeof(Drawing.new) == "function") or false
		updateConn = RunService.Heartbeat:Connect(function()
			local ok, err = pcall(updateAll)
			if not ok then
				Logger.warn("esp update failed: " .. tostring(err))
			end
		end)
		Tracker.track(updateConn, "espupdate")
		LocalPlayer.CharacterAdded:Connect(function()
			task.wait(1)
		end)
	end

	function ESPController.stopAll()
		ESPController.setPlayers(false)
		ESPController.setNpcs(false)
		Tracker.cleanup("esp")
		for model in pairs(targets) do
			removeTarget(model)
		end
	end
end

local ServerController = {}
do
	ServerController.hopMode = "lowest"

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
		Util.notify("Server Hop", "Looking for a server...")
		local servers = fetchServers()
		if not servers then
			Util.notify("Server Hop", "Could not fetch the server list")
			return false
		end
		local best = nil
		for _, server in ipairs(servers) do
			if server.id ~= game.JobId and server.players < server.maxPlayers then
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
		if not best then
			Util.notify("Server Hop", "No joinable server found")
			return false
		end
		Util.notify("Server Hop", "Joining server with " .. best.players .. " players")
		queueReexecute()
		task.wait(0.3)
		TeleportService:TeleportToPlaceInstance(game.PlaceId, best.id, LocalPlayer)
		return true
	end

	function ServerController.setHopMode(mode)
		ServerController.hopMode = mode or "lowest"
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

local FarmController = {}
do
	FarmController.settings = {
		enabled = false,
		mode = "Nearest",
		target = "",
		moveMethod = "Magnitize",
		distance = 4,
		autoAttack = false,
		autoQuest = false,
		attackDelay = 0.35,
	}

	local function findTargets()
		local mobNames = GameProfile.data.mobs
		local list = {}
		if type(mobNames) ~= "table" or #mobNames == 0 then
			return list
		end
		local playerChars = {}
		for _, player in ipairs(Players:GetPlayers()) do
			if player.Character then
				playerChars[player.Character] = true
			end
		end
		for _, model in ipairs(Workspace:GetChildren()) do
			if model:IsA("Model") and not playerChars[model] then
				local humanoid = model:FindFirstChildOfClass("Humanoid")
				if humanoid and humanoid.Health > 0 then
					for _, name in ipairs(mobNames) do
						if model.Name == name or model.Name:find(name) then
							table.insert(list, { model = model, humanoid = humanoid })
							break
						end
					end
				end
			end
		end
		return list
	end

	local function pickTarget(list)
		if #list == 0 then
			return nil
		end
		if FarmController.settings.mode == "Selected" and FarmController.settings.target ~= "" then
			for _, entry in ipairs(list) do
				if entry.model.Name == FarmController.settings.target then
					return entry
				end
			end
			return nil
		end
		if FarmController.settings.mode == "Lowest HP" then
			local best = list[1]
			for _, entry in ipairs(list) do
				if entry.humanoid.Health < best.humanoid.Health then
					best = entry
				end
			end
			return best
		end
		local best = list[1]
		local bestDist = math.huge
		local myRoot = Util.getRoot()
		if myRoot then
			for _, entry in ipairs(list) do
				local root = entry.model:FindFirstChild("HumanoidRootPart") or entry.model.PrimaryPart
				if root then
					local d = (root.Position - myRoot.Position).Magnitude
					if d < bestDist then
						bestDist = d
						best = entry
					end
				end
			end
		end
		return best
	end

	local function moveTo(targetRoot)
		local myRoot = Util.getRoot()
		if not myRoot then
			return
		end
		local dist = FarmController.settings.distance
		if FarmController.settings.moveMethod == "Teleport" then
			myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, dist)
		else
			local offset = (myRoot.Position - targetRoot.Position).Unit * dist
			myRoot.CFrame = CFrame.new(targetRoot.Position + offset, targetRoot.Position)
		end
	end

	local function attack()
		local humanoid = Util.getHumanoid()
		if not humanoid then
			return
		end
		local tool = Util.getEquippedTool()
		if not tool then
			local tools = Util.getTools()
			if #tools > 0 then
				humanoid:EquipTool(tools[1])
				tool = tools[1]
				task.wait(0.1)
			end
		end
		if tool then
			tool:Activate()
		end
	end

	local function farmLoop()
		while Tracker.isRunning("farm") do
			task.wait(FarmController.settings.attackDelay > 0.05 and FarmController.settings.attackDelay or 0.2)
			if not Util.isAlive() then
				task.wait(1)
			else
				local list = findTargets()
				local target = pickTarget(list)
				if target then
					local root = target.model:FindFirstChild("HumanoidRootPart") or target.model.PrimaryPart
					if root then
						moveTo(root)
						if FarmController.settings.autoAttack then
							attack()
						end
					end
				else
					task.wait(0.5)
				end
			end
		end
	end

	function FarmController.setEnabled(enabled)
		if enabled then
			if not GameDetector.requireGame("Auto Farm") then
				return false
			end
			if type(GameProfile.data.mobs) ~= "table" or #GameProfile.data.mobs == 0 then
				Util.notify("Auto Farm", "No mob data in game profile yet")
				return false
			end
			FarmController.settings.enabled = true
			Tracker.setRunning("farm", true)
			task.spawn(farmLoop)
			return true
		else
			FarmController.settings.enabled = false
			Tracker.setRunning("farm", false)
			return true
		end
	end

	function FarmController.setMode(mode)
		FarmController.settings.mode = mode or "Nearest"
	end

	function FarmController.setTarget(name)
		FarmController.settings.target = name or ""
	end

	function FarmController.setMoveMethod(method)
		FarmController.settings.moveMethod = method or "Magnitize"
	end

	function FarmController.setDistance(value)
		FarmController.settings.distance = value
	end

	function FarmController.setAutoAttack(enabled)
		FarmController.settings.autoAttack = enabled and true or false
	end

	function FarmController.setAutoQuest(enabled)
		if enabled then
			if not GameDetector.requireGame("Auto Quest") then
				return false
			end
			if not GameProfile.data.quests or next(GameProfile.data.quests) == nil then
				Util.notify("Auto Quest", "No quest data in game profile yet")
				return false
			end
		end
		FarmController.settings.autoQuest = enabled and true or false
		return true
	end

	function FarmController.setAttackDelay(value)
		FarmController.settings.attackDelay = value
	end
end

local ClanController = {}
do
	ClanController.settings = {
		enabled = false,
		mode = "Reroll Once",
		target = "",
		delay = 1.5,
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
					while rerollLoopActive and Tracker.isRunning("clan") do
						local result = ClanController.doReroll()
						if result and ClanController.settings.target ~= "" and result == ClanController.settings.target then
							Util.notify("Clan Reroll", "Target clan obtained: " .. result)
							break
						end
						task.wait(0.2)
					end
					rerollLoopActive = false
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
                                delfile("PS2Hub/Config.rbxl")
                                ok = true
                        end)
                end
                Util.notify("Config", ok and "Saved config removed. Rejoin to see defaults." or "File API not supported on this executor")
        end

        function SettingsController.destroyUi()
                Util.notify("PS2 Hub", "Shutting down...")
                ESPController.stopAll()
                Tracker.cleanupAll()
                local Rayfield = _G.RayfieldInstance
                if Rayfield then
                        pcall(function()
                                Rayfield:Destroy()
                        end)
                end
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

local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()
if not Rayfield then
	error("[PS2 Hub] failed to load Rayfield UI")
end
_G.RayfieldInstance = Rayfield

local Window = Rayfield:CreateWindow({
	Name = "PS2 Hub",
	LoadingTitle = "PS2 Hub " .. VERSION,
	LoadingSubtitle = "by Faludaddd",
	Theme = "Amber",
	ToggleUIKeybind = Enum.KeyCode.RightControl,
	ConfigurationSaving = {
		Enabled = true,
		FolderName = "PS2Hub",
		FileName = "Config",
	},
	KeySystem = false,
})

MovementController.init()
PlayerController.init()
ToolController.init()
ESPController.init()
SettingsController.startFpsCounter()

local HomeTab = Window:CreateTab("Home", "home")
local UniversalTab = Window:CreateTab("Universal", "person-standing")
local FarmTab = Window:CreateTab("Auto Farm", "swords")
local ClanTab = Window:CreateTab("Clan", "shield")
local EspTab = Window:CreateTab("ESP", "eye")
local ServerTab = Window:CreateTab("Server", "server")
local SettingsTab = Window:CreateTab("Settings", "settings")

local function normalizeChoice(choice)
	if type(choice) == "table" then
		return choice[1] or ""
	end
	return choice or ""
end

local HomeParagraph
do
	HomeTab:CreateSection("Overview")
	HomeParagraph = HomeTab:CreateParagraph({
		Title = "PS2 Hub " .. VERSION,
		Content = "Loading status...",
	})
	local activeModules = 0
	local function countActive()
		activeModules = 0
		if Tracker.isRunning("farm") then activeModules += 1 end
		if Tracker.isRunning("clan") then activeModules += 1 end
		if Tracker.isRunning("fly") then activeModules += 1 end
		if Tracker.isRunning("noclip") then activeModules += 1 end
		if Tracker.isRunning("infjump") then activeModules += 1 end
		if Tracker.isRunning("god") then activeModules += 1 end
		if Tracker.isRunning("antiafk") then activeModules += 1 end
		if Tracker.isRunning("sprint") then activeModules += 1 end
		if Tracker.isRunning("npcscan") then activeModules += 1 end
		return activeModules
	end
	Tracker.setRunning("homerefresh", true)
	task.spawn(function()
		while Tracker.isRunning("homerefresh") do
			task.wait(1)
			local detector = GameDetector.detect()
			local info = ServerController.getInfo()
			local content = "Version: " .. VERSION
				.. "\nGame: " .. detector.gameName
				.. "\nGame status: " .. GameDetector.getStatusText()
				.. "\nPlayer: " .. LocalPlayer.DisplayName .. " (@" .. LocalPlayer.Name .. ")"
				.. "\nServer: " .. info.playerCount .. "/" .. info.maxPlayers
				.. " players"
				.. "\nFPS: " .. tostring(SettingsController.getFps())
				.. " | Ping: " .. (info.ping >= 0 and info.ping .. "ms" or "n/a")
				.. "\nActive modules: " .. tostring(countActive())
			pcall(function()
				HomeParagraph:Set({ Title = "PS2 Hub " .. VERSION, Content = content })
			end)
		end
	end)
	HomeTab:CreateSection("Game Support")
	HomeTab:CreateParagraph({
		Title = "Project Slayers 2",
		Content = "Game-specific features (Auto Farm, Clan Reroll, quest automation) stay locked until the game releases and the instance data is added. Universal features work in every game.",
	})
	HomeTab:CreateButton({
		Name = "Check for Updates",
		Callback = function()
			SettingsController.checkUpdate()
		end,
	})
end

do
	UniversalTab:CreateSection("Movement")
	UniversalTab:CreateSlider({
		Name = "Walk Speed",
		Range = { 16, 300 },
		Increment = 1,
		Suffix = "studs/s",
		CurrentValue = MovementController.walkSpeed,
		Flag = "UniversalWalkSpeed",
		Callback = function(value)
			MovementController.setWalkSpeed(value)
		end,
	})
	UniversalTab:CreateSlider({
		Name = "Jump Power",
		Range = { 20, 300 },
		Increment = 1,
		Suffix = "power",
		CurrentValue = MovementController.jumpPower,
		Flag = "UniversalJumpPower",
		Callback = function(value)
			MovementController.setJumpPower(value)
		end,
	})
	UniversalTab:CreateToggle({
		Name = "Lock Stats",
		CurrentValue = false,
		Flag = "UniversalLockStats",
		Callback = function(value)
			MovementController.setLockStats(value)
		end,
	})
	local flyToggle
	flyToggle = UniversalTab:CreateToggle({
		Name = "Fly",
		CurrentValue = false,
		Flag = "UniversalFly",
		Callback = function(value)
			local ok = MovementController.setFly(value)
			if value and not ok then
				flyToggle:Set(false)
			end
		end,
	})
	UniversalTab:CreateSlider({
		Name = "Fly Speed",
		Range = { 10, 250 },
		Increment = 1,
		Suffix = "studs/s",
		CurrentValue = MovementController.flySpeed,
		Flag = "UniversalFlySpeed",
		Callback = function(value)
			MovementController.setFlySpeed(value)
		end,
	})
	UniversalTab:CreateToggle({
		Name = "Noclip",
		CurrentValue = false,
		Flag = "UniversalNoclip",
		Callback = function(value)
			MovementController.setNoclip(value)
		end,
	})
	UniversalTab:CreateToggle({
		Name = "Infinite Jump",
		CurrentValue = false,
		Flag = "UniversalInfJump",
		Callback = function(value)
			MovementController.setInfiniteJump(value)
		end,
	})
	UniversalTab:CreateToggle({
		Name = "Sprint (hold key)",
		CurrentValue = false,
		Flag = "UniversalSprint",
		Callback = function(value)
			MovementController.setSprint(value)
		end,
	})
	UniversalTab:CreateSlider({
		Name = "Sprint Speed",
		Range = { 17, 300 },
		Increment = 1,
		Suffix = "studs/s",
		CurrentValue = MovementController.sprintSpeed,
		Flag = "UniversalSprintSpeed",
		Callback = function(value)
			MovementController.setSprintSpeed(value)
		end,
	})
	UniversalTab:CreateKeybind({
		Name = "Sprint Key",
		CurrentKeybind = "LeftShift",
		HoldToInteract = false,
		Flag = "UniversalSprintKey",
		Callback = function(keybind)
			local ok, keyCode = pcall(function()
				return Enum.KeyCode[keybind]
			end)
			if ok and keyCode then
				MovementController.setSprintKey(keyCode)
			end
		end,
	})

	UniversalTab:CreateSection("Character")
	UniversalTab:CreateToggle({
		Name = "God Mode",
		CurrentValue = false,
		Flag = "UniversalGod",
		Callback = function(value)
			CharacterController.setGod(value)
		end,
	})
	UniversalTab:CreateToggle({
		Name = "Anti-AFK",
		CurrentValue = true,
		Flag = "UniversalAntiAFK",
		Callback = function(value)
			CharacterController.setAntiAFK(value)
		end,
	})
	UniversalTab:CreateButton({
		Name = "Reset Character",
		Callback = function()
			CharacterController.reset()
		end,
	})

	UniversalTab:CreateSection("Players")
	local playerDropdown = UniversalTab:CreateDropdown({
		Name = "Select Player",
		Options = PlayerController.getPlayerNames(),
		CurrentOption = {},
		Flag = "UniversalPlayerSelect",
		Callback = function(option)
			PlayerController.select(normalizeChoice(option))
		end,
	})
	PlayerController.onRefresh(function()
		pcall(function()
			playerDropdown:Set(PlayerController.getPlayerNames())
		end)
	end)
	UniversalTab:CreateButton({
		Name = "Teleport to Player",
		Callback = function()
			PlayerController.teleportToSelected()
		end,
	})
	UniversalTab:CreateButton({
		Name = "Refresh Player List",
		Callback = function()
			pcall(function()
				playerDropdown:Set(PlayerController.getPlayerNames())
			end)
		end,
	})

	UniversalTab:CreateSection("Tools")
	local toolDropdown = UniversalTab:CreateDropdown({
		Name = "Select Tool",
		Options = ToolController.getToolNames(),
		CurrentOption = {},
		Flag = "UniversalToolSelect",
		Callback = function(option)
			ToolController.select(normalizeChoice(option))
		end,
	})
	ToolController.onRefresh(function()
		pcall(function()
			toolDropdown:Set(ToolController.getToolNames())
		end)
	end)
	UniversalTab:CreateButton({
		Name = "Equip Selected Tool",
		Callback = function()
			ToolController.equipSelected()
		end,
	})
	UniversalTab:CreateButton({
		Name = "Unequip Tool",
		Callback = function()
			ToolController.unequip()
		end,
	})
	UniversalTab:CreateToggle({
		Name = "Auto Re-equip on Respawn",
		CurrentValue = false,
		Flag = "UniversalAutoEquip",
		Callback = function(value)
			ToolController.setAutoEquip(value)
		end,
	})
end

do
	FarmTab:CreateSection("Automation")
	FarmTab:CreateParagraph({
		Title = "Locked",
		Content = "Auto Farm needs Project Slayers 2 instance data (mob models, quest remotes). It unlocks automatically once the game profile is loaded after release.",
	})
	local farmToggle
	farmToggle = FarmTab:CreateToggle({
		Name = "Enable Auto Farm",
		CurrentValue = false,
		Flag = "FarmEnable",
		Callback = function(value)
			local ok = FarmController.setEnabled(value)
			if value and not ok then
				farmToggle:Set(false)
			end
		end,
	})
	FarmTab:CreateDropdown({
		Name = "Target Mode",
		Options = { "Nearest", "Selected", "Lowest HP" },
		CurrentOption = { "Nearest" },
		Flag = "FarmMode",
		Callback = function(option)
			FarmController.setMode(normalizeChoice(option))
		end,
	})
	local targetDropdown = FarmTab:CreateDropdown({
		Name = "Target",
		Options = { "None loaded" },
		CurrentOption = { "None loaded" },
		Flag = "FarmTarget",
		Callback = function(option)
			FarmController.setTarget(normalizeChoice(option))
		end,
	})
	FarmTab:CreateButton({
		Name = "Refresh Targets",
		Callback = function()
			if not GameDetector.requireGame("Auto Farm") then
				return
			end
			local mobs = GameProfile.data.mobs
			if type(mobs) == "table" and #mobs > 0 then
				pcall(function()
					targetDropdown:Set(mobs)
				end)
			else
				Util.notify("Auto Farm", "No mob data in game profile yet")
			end
		end,
	})

	FarmTab:CreateSection("Movement")
	FarmTab:CreateDropdown({
		Name = "Move Method",
		Options = { "Magnitize", "Teleport" },
		CurrentOption = { "Magnitize" },
		Flag = "FarmMoveMethod",
		Callback = function(option)
			FarmController.setMoveMethod(normalizeChoice(option))
		end,
	})
	FarmTab:CreateSlider({
		Name = "Target Distance",
		Range = { 2, 15 },
		Increment = 1,
		Suffix = "studs",
		CurrentValue = 4,
		Flag = "FarmDistance",
		Callback = function(value)
			FarmController.setDistance(value)
		end,
	})

	FarmTab:CreateSection("Interaction")
	FarmTab:CreateToggle({
		Name = "Auto Attack",
		CurrentValue = false,
		Flag = "FarmAutoAttack",
		Callback = function(value)
			FarmController.setAutoAttack(value)
		end,
	})
	local autoQuestToggle
	autoQuestToggle = FarmTab:CreateToggle({
		Name = "Auto Quest",
		CurrentValue = false,
		Flag = "FarmAutoQuest",
		Callback = function(value)
			local ok = FarmController.setAutoQuest(value)
			if value and not ok then
				autoQuestToggle:Set(false)
			end
		end,
	})

	FarmTab:CreateSection("Advanced")
	FarmTab:CreateSlider({
		Name = "Attack Delay",
		Range = { 0.1, 2 },
		Increment = 0.05,
		Suffix = "s",
		CurrentValue = 0.35,
		Flag = "FarmAttackDelay",
		Callback = function(value)
			FarmController.setAttackDelay(value)
		end,
	})
end

do
	ClanTab:CreateSection("Clan Reroll")
	ClanTab:CreateParagraph({
		Title = "Main Menu Reroll",
		Content = "Clan reroll in Project Slayers 2 is done through the game's main menu (no NPC involved). This module triggers the menu's reroll action and, in loop mode, rerolls until your target clan. Locked until release - needs the menu GUI and reroll remote paths from the instance file.",
	})
	local clanToggle
	clanToggle = ClanTab:CreateToggle({
		Name = "Enable Clan Reroll",
		CurrentValue = false,
		Flag = "ClanEnable",
		Callback = function(value)
			local ok = ClanController.setEnabled(value)
			if value and not ok then
				clanToggle:Set(false)
			end
		end,
	})
	ClanTab:CreateDropdown({
		Name = "Mode",
		Options = { "Reroll Once", "Reroll Until Target" },
		CurrentOption = { "Reroll Once" },
		Flag = "ClanMode",
		Callback = function(option)
			ClanController.setMode(normalizeChoice(option))
		end,
	})
	local clanTargetDropdown = ClanTab:CreateDropdown({
		Name = "Target Clan",
		Options = ClanController.getClanOptions(),
		CurrentOption = {},
		Flag = "ClanTarget",
		Callback = function(option)
			ClanController.setTarget(normalizeChoice(option))
		end,
	})
	ClanTab:CreateSlider({
		Name = "Delay Between Rerolls",
		Range = { 0.5, 10 },
		Increment = 0.5,
		Suffix = "s",
		CurrentValue = 1.5,
		Flag = "ClanDelay",
		Callback = function(value)
			ClanController.setDelay(value)
		end,
	})
	ClanTab:CreateSection("Status")
	local clanStatus = ClanTab:CreateParagraph({
		Title = "Status",
		Content = ClanController.getStatusText(),
	})
	ClanTab:CreateButton({
		Name = "Refresh Clan Status",
		Callback = function()
			pcall(function()
				clanStatus:Set({ Title = "Status", Content = ClanController.getStatusText() })
			end)
		end,
	})
	ClanTab:CreateButton({
		Name = "Reload Clan List",
		Callback = function()
			if not GameDetector.requireGame("Clan Reroll") then
				return
			end
			local options = ClanController.getClanOptions()
			pcall(function()
				clanTargetDropdown:Set(options)
			end)
		end,
	})
end

do
	EspTab:CreateSection("Players")
	EspTab:CreateToggle({
		Name = "Player ESP",
		CurrentValue = false,
		Flag = "EspPlayers",
		Callback = function(value)
			ESPController.setPlayers(value)
		end,
	})
	EspTab:CreateToggle({
		Name = "Show Names",
		CurrentValue = true,
		Flag = "EspNames",
		Callback = function(value)
			ESPController.setNames(value)
		end,
	})
	EspTab:CreateToggle({
		Name = "Show Distance",
		CurrentValue = true,
		Flag = "EspDistance",
		Callback = function(value)
			ESPController.setDistance(value)
		end,
	})
	EspTab:CreateToggle({
		Name = "Team Colors",
		CurrentValue = false,
		Flag = "EspTeamColor",
		Callback = function(value)
			ESPController.setTeamColor(value)
		end,
	})
	local tracerToggle
	tracerToggle = EspTab:CreateToggle({
		Name = "Tracers (PC only)",
		CurrentValue = false,
		Flag = "EspTracers",
		Callback = function(value)
			local ok = ESPController.setTracers(value)
			if value and not ok then
				tracerToggle:Set(false)
			end
		end,
	})

	EspTab:CreateSection("NPCs")
	EspTab:CreateToggle({
		Name = "NPC / Mob ESP",
		CurrentValue = false,
		Flag = "EspNpcs",
		Callback = function(value)
			ESPController.setNpcs(value)
		end,
	})

	EspTab:CreateSection("General")
	EspTab:CreateSlider({
		Name = "Max Distance",
		Range = { 50, 2000 },
		Increment = 25,
		Suffix = "studs",
		CurrentValue = 250,
		Flag = "EspMaxDistance",
		Callback = function(value)
			ESPController.setMaxDistance(value)
		end,
	})
end

do
	ServerTab:CreateSection("Actions")
	ServerTab:CreateButton({
		Name = "Rejoin Server",
		Callback = function()
			ServerController.rejoin()
		end,
	})
	ServerTab:CreateButton({
		Name = "Server Hop",
		Callback = function()
			ServerController.hop(ServerController.hopMode)
		end,
	})
	ServerTab:CreateButton({
		Name = "Low Player Hop",
		Callback = function()
			ServerController.hop("lowest")
		end,
	})
	ServerTab:CreateSection("Filters")
	ServerTab:CreateDropdown({
		Name = "Hop Preference",
		Options = { "lowest", "highest", "any" },
		CurrentOption = { "lowest" },
		Flag = "ServerHopMode",
		Callback = function(option)
			ServerController.setHopMode(normalizeChoice(option))
		end,
	})
	ServerTab:CreateSection("Info")
	local serverParagraph = ServerTab:CreateParagraph({
		Title = "Server Info",
		Content = "Loading...",
	})
	local function refreshServerInfo()
		local info = ServerController.getInfo()
		pcall(function()
			serverParagraph:Set({
				Title = "Server Info",
				Content = "PlaceId: " .. tostring(info.placeId)
					.. "\nJobId: " .. info.jobId
					.. "\nPlayers: " .. info.playerCount .. "/" .. info.maxPlayers
					.. "\nPing: " .. (info.ping >= 0 and info.ping .. "ms" or "unavailable"),
			})
		end)
	end
	refreshServerInfo()
	ServerTab:CreateButton({
		Name = "Refresh Server Info",
		Callback = function()
			refreshServerInfo()
		end,
	})
end

do
	SettingsTab:CreateSection("Configuration")
	SettingsTab:CreateToggle({
		Name = "Notifications",
		CurrentValue = true,
		Flag = "SetNotifications",
		Callback = function(value)
			SettingsController.setNotifications(value)
		end,
	})
	SettingsTab:CreateToggle({
		Name = "Auto Re-execute on Teleport",
		CurrentValue = true,
		Flag = "SetAutoReexecute",
		Callback = function(value)
			SettingsController.setAutoReexecute(value)
		end,
	})
	SettingsTab:CreateButton({
		Name = "Reset Saved Config",
		Callback = function()
			SettingsController.resetConfig()
		end,
	})

	SettingsTab:CreateSection("Performance")
	SettingsTab:CreateDropdown({
		Name = "FPS Boost",
		Options = { "off", "basic", "full" },
		CurrentOption = { "off" },
		Flag = "SetFpsBoost",
		Callback = function(option)
			SettingsController.setFpsBoost(normalizeChoice(option))
		end,
	})
	SettingsTab:CreateToggle({
		Name = "Fullbright",
		CurrentValue = false,
		Flag = "SetFullbright",
		Callback = function(value)
			SettingsController.setFullbright(value)
		end,
	})

	SettingsTab:CreateSection("Debug")
	SettingsTab:CreateButton({
		Name = "Copy Logs",
		Callback = function()
			SettingsController.copyLogs()
		end,
	})
	SettingsTab:CreateButton({
		Name = "Clear Logs",
		Callback = function()
			SettingsController.clearLogs()
		end,
	})

	SettingsTab:CreateSection("Project")
	SettingsTab:CreateParagraph({
		Title = "PS2 Hub " .. VERSION,
		Content = "Made by Faludaddd. Source: " .. REPO_URL,
	})
	SettingsTab:CreateButton({
		Name = "Check for Updates",
		Callback = function()
			SettingsController.checkUpdate()
		end,
	})
	SettingsTab:CreateButton({
		Name = "Copy Execute URL",
		Callback = function()
			SettingsController.copySource()
		end,
	})
	SettingsTab:CreateButton({
		Name = "Destroy UI",
		Callback = function()
			SettingsController.destroyUi()
		end,
	})
end

Logger.info("PS2 Hub " .. VERSION .. " loaded")
Util.notify("PS2 Hub", "Loaded v" .. VERSION .. " - game status: " .. GameDetector.getStatusText(), 4)
