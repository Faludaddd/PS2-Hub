

local VERSION       = "1.3.0"
local BUILD_DATE    = "2026-09-14"
local PROJECT_NAME  = "PS2 Hub"

local RAYFIELD_URL  = "https://sirius.menu/gen2"

local SECURE_MODE   = false

local EXECUTE_URL = "https://raw.githubusercontent.com/Faludaddd/PS2-Hub/main/main.lua"

local GENV_KEY      = "PS2HUB_ACTIVE"

local GameProfile = {
    name        = "Project Slayers 2",

    PLACE_ID    = 16205713724,
    GAME_ID     = 5595353122,

                DATA_READY  = false,

        aliases     = { "project slayers 2", "slayers 2", "ps2" },

        NPC = {
                                containers = {
            "NPCs", "NPC", "Enemies", "Enemy", "Mobs", "Monsters",
            "Bandits", "Demons", "Slayers", "Bosses", "Entities",
        },

                tags = {
            "NPC", "Enemy", "Mob", "Monster", "Boss", "Farmable",
        },

                        namePatterns = {
            "npc", "bandit", "demon", "slayer", "enemy", "mob",
            "monster", "boss", "trainer", "fighter", "rogue", "thief",
        },

                bossPatterns = { "boss", "upper moon", "lower moon", "hydra", "king", "lord" },

                        targetAttributes = { "IsNPC", "IsEnemy", "NPC" },

                bossAttribute = "IsBoss",

                requireHumanoid  = true,
        requireRootPart  = true,

                excludePatterns = { "dummy", "training", "shop", "merchant", "quest" },
    },

                    CLAN = {
        enabled = false,

                        clanStatNames = { "Clan", "ClanName" },

        reroll = {
                                    npcNamePatterns = {},
            promptPatterns  = {},

                        remoteName = "",
            remoteArgs = {},
        },

                knownClans = {},
    },

                        QUEST = {
        enabled        = true,
        containers     = { "Quests", "Quest", "NPCs", "NPC" },
        tags           = { "Quest", "QuestGiver" },
        giverPatterns  = { "quest", "giver", "task", "job" },
        promptPatterns = { "talk", "accept", "quest", "turn in", "turn-in", "interact", "complete" },
        objectiveUIPatterns = { "quest", "objective", "task" },
        completionPatterns = { "complete", "completed", "done", "turn in", "return to", "finish", "reward" },
                objectiveSources = {},
    },

            ITEMS = {
        tags = { "Item", "Drop", "Loot", "Pickup" },
        namePatterns = {
            "drop", "item", "yen", "coin", "gold", "money", "loot",
            "potion", "chest", "ore", "crystal", "shard",
        },
    },

        INTERACTION = {
                        toolNamePatterns = { "sword", "blade", "katana", "weapon", "scythe", "nichirin" },
                                remoteNames = {},
    },

        PLAYER_DATA = {
                        currencyNames = { "yen", "coins", "gold", "money", "cash", "wen", "ryo" },
                levelNames    = { "level", "lvl", "power", "rank", "mastery" },
    },
}

GameProfile.CONFIGURED = (GameProfile.PLACE_ID ~= 0 or GameProfile.GAME_ID ~= 0)

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local HttpService       = game:GetService("HttpService")

local LocalPlayer       = Players.LocalPlayer

local Logger = nil

local Util = {}

function Util.safe(scope, fn, ...)
    local args = table.pack(...)
    local results = table.pack(pcall(function(...)
        return fn(...)
    end, table.unpack(args, 1, args.n)))
    if not results[1] then
        if Logger then Logger:error(scope .. " failed: " .. tostring(results[2])) end
        return false, nil
    end
    return true, table.unpack(results, 2, results.n)
end

function Util.clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

function Util.round(v, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(v * mult + 0.5) / mult
end

function Util.formatInt(n)
    local s = tostring(math.floor(n))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    formatted = formatted:gsub("^,", "")
    return formatted
end

function Util.formatDuration(seconds)
    seconds = math.floor(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    if h > 0 then
        return string.format("%dh %02dm", h, m)
    elseif m > 0 then
        return string.format("%dm %02ds", m, s)
    end
    return string.format("%ds", s)
end

function Util.trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function Util.matchAny(list, name)
    if type(name) ~= "string" then return false end
    local lower = name:lower()
    for _, pattern in ipairs(list) do
        if lower:find(pattern, 1, true) or lower:find(pattern) then
            return true
        end
    end
    return false
end

function Util.instanceValid(inst)
    return typeof(inst) == "Instance" and inst.Parent ~= nil
end

function Util.getCharacter()
    return LocalPlayer.Character
end

function Util.getHumanoid(char)
    char = char or Util.getCharacter()
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

function Util.getRoot(char)
    char = char or Util.getCharacter()
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

function Util.findRootOf(model)
    if not (typeof(model) == "Instance" and model:IsA("Model")) then return nil end
    local root = model:FindFirstChild("HumanoidRootPart")
    if not root then root = model.PrimaryPart end
    if not root then
        for _, part in ipairs(model:GetChildren()) do
            if part:IsA("BasePart") then
                root = part
                break
            end
        end
    end
    return root
end

function Util.humanoidOf(model)
    if typeof(model) ~= "Instance" then return nil end
    if model:IsA("Humanoid") then return model end
    if not model:IsA("Model") then return nil end
    return model:FindFirstChildOfClass("Humanoid")
end

function Util.isAlive(model)
    local hum = Util.humanoidOf(model)
    if not hum then return false end
    return hum.Health > 0
end

function Util.aliveLocal()
    local hum = Util.getHumanoid()
    return hum ~= nil and hum.Health > 0
end

function Util.distanceBetween(a, b)
    if not (a and b) then return math.huge end
    return (a.Position - b.Position).Magnitude
end

function Util.localRootDistance()
    local root = Util.getRoot()
    return root and root.Position or nil
end

function Util.spamGuard(store, key, cooldownMs)
    local now = os.clock() * 1000
    local last = store[key]
    if last and (now - last) < cooldownMs then
        return true
    end
    store[key] = now
    return false
end

function Util.copy(t)
    if type(t) ~= "table" then return t end
    local out = {}
    for k, v in pairs(t) do out[k] = Util.copy(v) end
    return out
end

function Util.countKeys(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

local Signal = {}
Signal.__index = Signal

function Signal.new()
    return setmetatable({ _binds = {}, _dead = false }, Signal)
end

function Signal:Connect(fn)
    assert(type(fn) == "function", "Signal:Connect expects a function")
    if self._dead then
        return { Disconnect = function() end, Connected = false }
    end
    local bind = { fn = fn, connected = true }
    table.insert(self._binds, bind)
    local connection = {}
    function connection:Disconnect()
        bind.connected = false
    end
    connection.Connected = bind.connected
    return connection
end

function Signal:Fire(...)
    if self._dead then return end
    for _, bind in ipairs(Util.copy(self._binds)) do
        if bind.connected then
            local ok, err = pcall(bind.fn, ...)
            if not ok and Logger then
                Logger:error("Signal handler failed: " .. tostring(err))
            end
        end
    end
end

function Signal:Destroy()
    self._dead = true
    for _, bind in ipairs(self._binds) do bind.connected = false end
    self._binds = {}
end

Logger = {}

Logger.LEVELS = { DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4 }

Logger.minLevel     = Logger.LEVELS.INFO
Logger.debugEnabled = false
Logger.buffer       = {}
Logger.maxBuffer    = 300
Logger._console     = nil
Logger._spamStore   = {}

local function stamp()
    return os.date("%H:%M:%S")
end

function Logger:bindConsole(consoleElement)
    self._console = consoleElement
        if consoleElement then
        for _, line in ipairs(self.buffer) do
            consoleElement:Append(line)
        end
    end
end

function Logger:shouldLog(levelName)
    local level = self.LEVELS[levelName] or 2
    if level == self.LEVELS.DEBUG then
                        return self.debugEnabled == true
    end
    return level >= self.minLevel
end

function Logger:log(levelName, message)
    if not self:shouldLog(levelName) then return end
    local line = string.format("[%s] [%s] %s", stamp(), levelName, tostring(message))
    table.insert(self.buffer, line)
    while #self.buffer > self.maxBuffer do
        table.remove(self.buffer, 1)
    end
    if self._console then
        self._console:Append(line)
    end
end

function Logger:debug(msg) self:log("DEBUG", msg) end
function Logger:info(msg)  self:log("INFO",  msg)  end
function Logger:warn(msg)  self:log("WARN",  msg)  end
function Logger:error(msg) self:log("ERROR", msg) end

function Logger:warnOnce(msg)
    if Util.spamGuard(self._spamStore, msg, 10000) then return end
    self:warn(msg)
end

function Logger:errorOnce(msg)
    if Util.spamGuard(self._spamStore, msg, 15000) then return end
    self:error(msg)
end

function Logger:clear()
    self.buffer = {}
    if self._console then self._console:Clear() end
end

local Tracker = {}

Tracker.connections  = {}
Tracker.loops        = {}
Tracker.shuttingDown = false

function Tracker.connect(scope, signal, fn)
    local conn
    local ok = pcall(function()
        conn = signal:Connect(fn)
    end)
    if not ok or not conn then
        Logger:warnOnce("Tracker.connect failed: " .. tostring(scope))
        return nil
    end
    local record = { scope = scope, conn = conn }
    table.insert(Tracker.connections, record)
    local handle = {}
    function handle:Disconnect()
        pcall(function() conn:Disconnect() end)
        for i, r in ipairs(Tracker.connections) do
            if r == record then
                table.remove(Tracker.connections, i)
                break
            end
        end
    end
    handle.Connected = conn.Connected
    return handle
end

function Tracker.loop(scope, interval, fn)
    local getInterval
    if type(interval) == "function" then
        getInterval = interval
    else
        getInterval = function()
            return interval
        end
    end
    local record = {
        scope    = scope,
        running  = true,
    }
    local handle = {}
    function handle:Stop()
        record.running = false
        for i, r in ipairs(Tracker.loops) do
            if r == record then
                table.remove(Tracker.loops, i)
                break
            end
        end
    end
    function handle:IsRunning() return record.running end

    record.handle = handle
    table.insert(Tracker.loops, record)

    task.spawn(function()
        while record.running and not Tracker.shuttingDown do
            local ok, err = pcall(fn)
            local wait = getInterval()
            if not ok then
                Logger:errorOnce("Loop [" .. scope .. "] error: " .. tostring(err))
                wait = math.max(wait, 1.0)
            end
            task.wait(wait)
        end
        record.running = false
    end)
    return handle
end

function Tracker.delay(scope, seconds, fn)
    task.spawn(function()
        task.wait(seconds)
        if Tracker.shuttingDown then return end
        local ok, err = pcall(fn)
        if not ok then
            Logger:error("Delayed task [" .. scope .. "] error: " .. tostring(err))
        end
    end)
end

function Tracker.stopAllLoops()
    for _, record in ipairs(Util.copy(Tracker.loops)) do
        record.running = false
    end
    Tracker.loops = {}
end

function Tracker.disconnectAll()
    for _, record in ipairs(Tracker.connections) do
        pcall(function() record.conn:Disconnect() end)
    end
    Tracker.connections = {}
end

function Tracker.beginShutdown()
    Tracker.shuttingDown = true
    Tracker.stopAllLoops()
    Tracker.disconnectAll()
end

function Tracker.stats()
    return #Tracker.connections, #Tracker.loops
end

local State = {
        rayfield   = nil,
    window     = nil,
    gameVerified = false,

        automation = {
        enabled   = false,
        mode      = "Nearest",
        taskState = "Idle",
        target    = nil,
        kills     = 0,
        interactions = 0,
    },
    esp        = { enabled = false },
    server     = {
        hopping    = false,
        lastHop    = 0,
        visited    = {},
        visitedOrder = {},
    },
    character  = {
        walkSpeedEnabled = false,
        walkSpeed        = 16,
        walkMethod       = "Auto",
        walkResolved     = "—",
        flyEnabled       = false,
        flyMethod        = "Auto",
        flyResolved      = "—",
        noclip           = false,
    },
}

State.intervals = {
    homeStats   = 1.0,
    targetScan  = 2.0,
    automation  = 0.25,
    serverInfo  = 2.0,
    espUpdate   = 0.1,
}

State.settings = {
    notificationsEnabled = true,
    notificationDuration = 5,
    toastsEnabled        = true,
    autoLoadConfig       = false,
    rememberVisitedServers = true,
    autoRefreshPlayers   = true,
    debugLogging         = false,
    logLevel             = "INFO",
    autoPerformance      = true,
}

local UIState = {}

UIState.lowHopMode       = "3"
UIState.lowHopCustomValue = 8

function UIState.dropdownFirst(dropdown)
    if not dropdown then return nil end
    local ok, v = pcall(function() return dropdown.value end)
    if not ok then return nil end
    if type(v) == "table" then return v[1] end
    return v
end

function UIState.lowHopMax()
    local mode = UIState.lowHopMode or "3"
    if mode == "Custom" then
        return Util.clamp(tonumber(UIState.lowHopCustomValue) or 8, 1, 200)
    end
    return tonumber(mode) or 3
end

local Emergency = {}

local Rayfield = nil

local Http = {}

Http.available = false

local function detectRequest()
    local impl =
        (syn and syn.request) or
        (http and http.request) or
        http_request or
        (fluxus and fluxus.request) or
        (request)
    return impl
end

function Http.init()
    Http.impl = detectRequest()
    Http.available = type(Http.impl) == "function"
    if not Http.available then
        Logger:warn("HTTP request API not found — server hop disabled in this executor")
    end
    return Http.available
end

function Http.getJson(url)
    if not Http.available then
        return nil, "http unavailable"
    end
    local ok, response = pcall(Http.impl, {
        Url     = url,
        Method  = "GET",
        Headers = { ["Accept"] = "application/json" },
    })
    if not ok or type(response) ~= "table" then
        return nil, "request failed"
    end
    local body = response.Body or ""
    if response.StatusCode and response.StatusCode >= 400 then
        return nil, "status " .. tostring(response.StatusCode)
    end
    local okDecode, data = pcall(HttpService.JSONDecode, HttpService, body)
    if not okDecode then
        return nil, "bad json"
    end
    return data, nil
end

local ModuleManager = {}

ModuleManager.modules    = {}
ModuleManager.loadedList = {}

function ModuleManager.register(name, module, initFn)
    table.insert(ModuleManager.modules, {
        name    = name,
        module  = module,
        init    = initFn,
        started = false,
    })
end

function ModuleManager.initAll()
    for _, entry in ipairs(ModuleManager.modules) do
        local ok, err = pcall(function()
            if entry.init then entry.init(entry.module) end
            if type(entry.module.Start) == "function" then
                entry.module:Start()
            end
        end)
        if ok then
            entry.started = true
            table.insert(ModuleManager.loadedList, entry.name)
            Logger:debug("Module ready: " .. entry.name)
        else
                        Logger:error("Module [" .. entry.name .. "] failed to start: " .. tostring(err))
        end
    end
    Logger:info(string.format(
        "Initialized %d/%d modules (%s)",
        #ModuleManager.loadedList,
        #ModuleManager.modules,
        table.concat(ModuleManager.loadedList, ", ")
    ))
end

function ModuleManager.stopAll()
    for i = #ModuleManager.modules, 1, -1 do
        local entry = ModuleManager.modules[i]
        if entry.started then
            pcall(function()
                if type(entry.module.Stop) == "function" then
                    entry.module:Stop()
                end
                if type(entry.module.Cleanup) == "function" then
                    entry.module:Cleanup()
                end
            end)
            entry.started = false
        end
    end
end

function ModuleManager.isLoaded(name)
    for _, n in ipairs(ModuleManager.loadedList) do
        if n == name then return true end
    end
    return false
end

local Notify = {}

Notify._dedupe  = {}
Notify._window  = nil

function Notify.init(window)
    Notify._window = window
end

function Notify.enabled()
    return State.settings.notificationsEnabled
end

function Notify.notify(title, content, duration)
    if not (Notify._window and Notify.enabled()) then return end
    pcall(function()
        Notify._window:Notify({
            title   = title,
            content = content,
            duration = duration or State.settings.notificationDuration or 5,
        })
    end)
end

function Notify.toast(title, subtitle)
    if not (Notify._window and State.settings.toastsEnabled) then return end
    pcall(function()
        Notify._window:Toast({ title = title, subtitle = subtitle })
    end)
end

function Notify.error(context, err)
    local msg = tostring(err or "unknown error")
    if Util.spamGuard(Notify._dedupe, context .. msg, 30000) then return end
    Logger:error(context .. ": " .. msg)
    Notify.notify("Error — " .. context, msg, 6)
end

local GameDetector = {}

GameDetector.verified   = false
GameDetector.reason     = "not configured"

local function nameMatches()
    local placeName = game.Name or ""
    local lower = placeName:lower()
    if lower == GameProfile.name:lower() then return true end
    for _, alias in ipairs(GameProfile.aliases or {}) do
        if lower == alias:lower() then return true end
    end
    return false
end

function GameDetector.check()
    if not GameProfile.CONFIGURED then
        GameDetector.verified = false
        GameDetector.reason = "GameProfile not configured (set PLACE_ID)"
        Logger:info("Game profile unconfigured — running universal-only")
        return false
    end

    if GameProfile.PLACE_ID ~= 0 and game.PlaceId == GameProfile.PLACE_ID then
        GameDetector.verified = true
        GameDetector.reason = "PlaceId match"
    elseif GameProfile.GAME_ID ~= 0 and game.GameId == GameProfile.GAME_ID then
        GameDetector.verified = true
        GameDetector.reason = "GameId match"
    elseif nameMatches() then
        GameDetector.verified = true
        GameDetector.reason = "name match (verify PlaceId!)"
    else
        GameDetector.verified = false
        GameDetector.reason = "different game"
    end

    if GameDetector.verified then
        if GameProfile.DATA_READY then
            Logger:info("Game verified: " .. game.Name .. " (" .. GameDetector.reason .. ")")
        else
            Logger:info("Game matched: " .. game.Name .. " (" .. GameDetector.reason
                .. ") — game data pending release, game-specific features stay locked")
        end
    else
        Logger:warn("Wrong game detected — PS2 automation locked")
    end
    return GameDetector.verified
end

function GameDetector.shouldEnableGameFeatures()
                return GameDetector.verified and GameProfile.DATA_READY == true
end

function GameDetector.gameLockReason()
    if GameProfile.DATA_READY ~= true then
        return "Slayers 2 not released yet — awaiting game instance data"
    end
    if not GameDetector.verified then
        return "Only runs in Project Slayers 2"
    end
    return nil
end

local UserInputService   = game:GetService("UserInputService")
local VirtualUser        = game:GetService("VirtualUser")
local Workspace          = game:GetService("Workspace")

local Camera             = Workspace.CurrentCamera

local CharacterController = {}

CharacterController.walk = {
    enabled  = false,
    speed    = 16,
    method   = "Auto",
    resolved = nil,
    _applyGuard = false,
    _resetCount = 0,
    _resetWindow = 0,
    _humanoidConn = nil,
    _velocityLoop = nil,
}

CharacterController.jump = {
    enabled = false,
    power   = 50,
    height  = 7.2,
    usePower = true,
}

CharacterController.fly = {
    enabled  = false,
    speed    = 60,
    method   = "Auto",
    resolved = nil,
    _loop    = nil,
    _parts   = nil,
    _input   = {},
    _inputConn = {},
}

CharacterController.flags = {
    infiniteJump = false,
    noclip       = false,
    antiAFK      = false,
}

CharacterController.camera = {
    fov = nil,
    defaultFov = 70,
}

CharacterController.onMethodChanged = Signal.new()

local MOVE_KEYS = {
    [Enum.KeyCode.W] = Vector3.new(0, 0, -1),
    [Enum.KeyCode.S] = Vector3.new(0, 0, 1),
    [Enum.KeyCode.A] = Vector3.new(-1, 0, 0),
    [Enum.KeyCode.D] = Vector3.new(1, 0, 0),
    [Enum.KeyCode.E] = Vector3.new(0, 1, 0),
    [Enum.KeyCode.Space] = Vector3.new(0, 1, 0),
    [Enum.KeyCode.Q] = Vector3.new(0, -1, 0),
    [Enum.KeyCode.LeftControl] = Vector3.new(0, -1, 0)
}

local function trackInput()
    table.insert(CharacterController.fly._inputConn, Tracker.connect(
        "fly.InputBegan",
        UserInputService.InputBegan,
        function(input, gameProcessed)
            if gameProcessed then return end
            if MOVE_KEYS[input.KeyCode] then
                CharacterController.fly._input[input.KeyCode] = true
            end
        end
    ))
    table.insert(CharacterController.fly._inputConn, Tracker.connect(
        "fly.InputEnded",
        UserInputService.InputEnded,
        function(input)
            if MOVE_KEYS[input.KeyCode] then
                CharacterController.fly._input[input.KeyCode] = nil
            end
        end
    ))
end

local function flyMoveVector()
    local x, y, z = 0, 0, 0
    for key, held in pairs(CharacterController.fly._input) do
        if held then
            local dir = MOVE_KEYS[key]
            if dir then
                x = x + dir.X
                y = y + dir.Y
                z = z + dir.Z
            end
        end
    end
    local flat = Vector3.new(x, 0, z)
    local camCF = Camera.CFrame
    local move = Vector3.zero
    if flat.Magnitude > 0 then
        local flatLook = camCF.LookVector * Vector3.new(1, 0, 1)
        if flatLook.Magnitude > 0.01 then
            local cfFlat = CFrame.lookAt(camCF.Position, camCF.Position + flatLook.Unit)
            move = cfFlat:VectorToWorldSpace(flat.Unit)
        end
    end
    if y ~= 0 then
        move = move + Vector3.new(0, y, 0)
    end
    if move.Magnitude > 1 then
        move = move.Unit
    end
    return move
end

local function applyHumanoidSpeed(hum, speed)
    CharacterController.walk._applyGuard = true
    hum.WalkSpeed = speed
    CharacterController.walk._applyGuard = false
end

local function startHumanoidMethod()
    local walk = CharacterController.walk
    local hum = Util.getHumanoid()
    if not hum then return false end

    applyHumanoidSpeed(hum, walk.speed)

    walk._humanoidConn = Tracker.connect("walk.humanoidProp", hum:GetPropertyChangedSignal("WalkSpeed"), function()
        if not walk.enabled or walk.resolved ~= "Humanoid" then return end
        if CharacterController.walk._applyGuard then return end
        local hum2 = Util.getHumanoid()
        if not hum2 then return end
                if math.abs(hum2.WalkSpeed - walk.speed) > 0.01 then
            walk._resetCount = walk._resetCount + 1
            Logger:debug(string.format("WalkSpeed reset by game (%d) — re-applying", walk._resetCount))
            applyHumanoidSpeed(hum2, walk.speed)
            if walk.method == "Auto" and walk._resetCount >= 3 then
                Logger:warn("WalkSpeed: game enforces Humanoid.WalkSpeed — switching to Velocity method")
                CharacterController:setWalkMethod("Velocity", true)
            end
        end
    end)
    return true
end

local function stopHumanoidMethod()
    local walk = CharacterController.walk
    if walk._humanoidConn then
        walk._humanoidConn:Disconnect()
        walk._humanoidConn = nil
    end
        local hum = Util.getHumanoid()
    if hum then hum.WalkSpeed = 16 end
end

local function startVelocityMethod()
    local walk = CharacterController.walk
    walk._velocityLoop = Tracker.loop("walk.velocity", 0, function()
        if not walk.enabled or walk.resolved ~= "Velocity" then return end
        if CharacterController.fly.enabled then return end
        local root = Util.getRoot()
        local hum = Util.getHumanoid()
        if not (root and hum) then return end
        local dir = hum.MoveDirection
        local vy = root.AssemblyLinearVelocity.Y
        if dir.Magnitude > 0.01 then
            root.AssemblyLinearVelocity = Vector3.new(dir.X * walk.speed, vy, dir.Z * walk.speed)
        else
            root.AssemblyLinearVelocity = Vector3.new(0, vy, 0)
        end
    end)
end

local function stopVelocityMethod()
    local walk = CharacterController.walk
    if walk._velocityLoop then
        walk._velocityLoop:Stop()
        walk._velocityLoop = nil
    end
end

function CharacterController:setWalkEnabled(enabled)
    local walk = self.walk
    local wasEnabled = walk.enabled
    walk.enabled = enabled and true or false
    if enabled then
        self:applyWalk()
        Logger:info(string.format("WalkSpeed enabled (%d, method %s)", walk.speed, walk.method))
    else
        if not wasEnabled then return end
        stopVelocityMethod()
        stopHumanoidMethod()
        walk.resolved = nil
        Logger:info("WalkSpeed disabled — restored default")
    end
    State.character.walkSpeedEnabled = walk.enabled
    State.character.walkResolved = walk.resolved or "—"
    self.onMethodChanged:Fire()
end

function CharacterController:setWalkSpeed(speed)
    self.walk.speed = Util.clamp(speed or 16, 1, 1000)
    if self.walk.enabled then
        local hum = Util.getHumanoid()
        if hum and self.walk.resolved == "Humanoid" then
            applyHumanoidSpeed(hum, self.walk.speed)
        end
    end
    State.character.walkSpeed = self.walk.speed
end

function CharacterController:setWalkMethod(method, silent)
    local walk = self.walk
    if walk.method == method and not silent then return end
    walk.method = method
    if not walk.enabled then return end
    stopVelocityMethod()
    stopHumanoidMethod()
    walk.resolved = nil
    walk._resetCount = 0
    self:applyWalk()
end

function CharacterController:applyWalk()
    local walk = self.walk
    if not walk.enabled then return end
    local hum = Util.getHumanoid()
    if not hum then
        Logger:warnOnce("WalkSpeed: no character yet — will apply on respawn")
        return
    end
    local method = walk.method
    if method == "Auto" then
                walk.resolved = "Humanoid"
        startHumanoidMethod()
        applyHumanoidSpeed(hum, walk.speed)
        task.delay(0.25, function()
            local hum2 = Util.getHumanoid()
            if walk.enabled and walk.resolved == "Humanoid" and hum2
               and math.abs(hum2.WalkSpeed - walk.speed) > 0.01 then
                Logger:warn("WalkSpeed Auto: property rejected — using Velocity method")
                stopHumanoidMethod()
                walk.resolved = "Velocity"
                startVelocityMethod()
                self.onMethodChanged:Fire()
            end
        end)
    elseif method == "Humanoid" then
        walk.resolved = "Humanoid"
        startHumanoidMethod()
        applyHumanoidSpeed(hum, walk.speed)
    elseif method == "Velocity" then
        walk.resolved = "Velocity"
        startVelocityMethod()
    end
    State.character.walkResolved = walk.resolved or "—"
    self.onMethodChanged:Fire()
end

function CharacterController:detectJumpMode()
    local hum = Util.getHumanoid()
    if hum then
        self.jump.usePower = hum.UseJumpPower
    end
    return self.jump.usePower
end

function CharacterController:setJumpEnabled(enabled)
    local wasEnabled = self.jump.enabled
    self.jump.enabled = enabled and true or false
    if enabled then
        self:applyJump()
        Logger:info(string.format(
            "Jump override enabled (%s = %s)",
            self.jump.usePower and "JumpPower" or "JumpHeight",
            self.jump.usePower and tostring(self.jump.power) or tostring(self.jump.height)
        ))
    else
        if not wasEnabled then return end
        local hum = Util.getHumanoid()
        if hum then
            if hum.UseJumpPower then hum.JumpPower = 50 else hum.JumpHeight = 7.2 end
        end
        Logger:info("Jump override disabled — restored default")
    end
end

function CharacterController:applyJump()
    if not self.jump.enabled then return end
    local hum = Util.getHumanoid()
    if not hum then return end
    if hum.UseJumpPower then
        hum.JumpPower = self.jump.power
    else
        hum.JumpHeight = self.jump.height
    end
end

function CharacterController:setJumpPower(v)
    self.jump.power = Util.clamp(v or 50, 1, 1000)
    self:applyJump()
end

function CharacterController:setJumpHeight(v)
    self.jump.height = Util.clamp(v or 7.2, 1, 500)
    self:applyJump()
end

function CharacterController:setInfiniteJump(enabled)
    self.flags.infiniteJump = enabled and true or false
    if self._jumpConn then
        self._jumpConn:Disconnect()
        self._jumpConn = nil
    end
    if enabled then
        self._jumpConn = Tracker.connect("char.jumpRequest", UserInputService.JumpRequest, function()
            if not self.flags.infiniteJump then return end
            local hum = Util.getHumanoid()
            if hum then
                hum.Jump = true
                pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
            end
        end)
        Logger:info("Infinite jump enabled")
    else
        Logger:info("Infinite jump disabled")
    end
end

function CharacterController:setNoclip(enabled)
    self.flags.noclip = enabled and true or false
    if self._noclipConn then
        self._noclipConn:Disconnect()
        self._noclipConn = nil
    end
    if enabled then
        self._noclipConn = Tracker.connect("char.noclip", RunService.Stepped, function()
            if not self.flags.noclip then return end
            local char = Util.getCharacter()
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end)
        Logger:info("Noclip enabled")
    else
        local char = Util.getCharacter()
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                    part.CanCollide = true
                end
            end
        end
        Logger:info("Noclip disabled")
    end
    State.character.noclip = self.flags.noclip
end

local function flyDestroyParts(fly)
    if fly._parts then
        for _, obj in ipairs(fly._parts) do
            pcall(function() obj:Destroy() end)
        end
    end
    fly._parts = nil
    local root = Util.getRoot()
    if root then
        root.AssemblyLinearVelocity = Vector3.zero
    end
end

local function flyStepCFrame(dt)
    local fly = CharacterController.fly
    local root = Util.getRoot()
    if not root then return end
    local move = flyMoveVector()
    local delta = move * fly.speed * dt
    root.AssemblyLinearVelocity = Vector3.zero
    local newPos = root.Position + delta
    if move.Magnitude > 0.01 then
        root.CFrame = CFrame.lookAt(newPos, newPos + move)
    else
        root.CFrame = CFrame.new(newPos)
    end
end

local function flyStepBodyVelocity(dt)
    local fly = CharacterController.fly
    local root = Util.getRoot()
    if not root then return end
    local move = flyMoveVector() * fly.speed
    fly._velocityObject.Velocity = move
    fly._gyroObject.CFrame = Camera.CFrame
end

local function flyStepLinearVelocity(dt)
    local fly = CharacterController.fly
    local root = Util.getRoot()
    if not root then return end
    local move = flyMoveVector() * fly.speed
    fly._velocityObject.VectorVelocity = move
    fly._alignObject.CFrame = Camera.CFrame
end

local FLY_STEPS = {
    CFrame         = flyStepCFrame,
    BodyVelocity   = flyStepBodyVelocity,
    LinearVelocity = flyStepLinearVelocity,
}

local function flyStart(method)
    local fly = CharacterController.fly
    local root = Util.getRoot()
    if not root then return false end
    flyDestroyParts(fly)

    if method == "BodyVelocity" then
        local gyro = Instance.new("BodyGyro")
        gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
        gyro.P = 9e4
        gyro.D = 500
        gyro.CFrame = Camera.CFrame
        gyro.Parent = root

        local vel = Instance.new("BodyVelocity")
        vel.MaxForce = Vector3.new(9e9, 9e9, 9e9)
        vel.Velocity = Vector3.zero
        vel.Parent = root

        fly._gyroObject = gyro
        fly._velocityObject = vel
        fly._parts = { gyro, vel }
    elseif method == "LinearVelocity" then
        local attachment = Instance.new("Attachment")
        attachment.Parent = root

        local align = Instance.new("AlignOrientation")
        align.Mode = Enum.OrientationAlignmentMode.OneAttachment
        align.Attachment0 = attachment
        align.MaxTorque = 9e9
        align.MaxAngularVelocity = 120
        align.RigidityEnabled = false
        align.CFrame = Camera.CFrame
        align.Parent = root

        local vel = Instance.new("LinearVelocity")
        vel.Attachment0 = attachment
        vel.ForceLimitMode = Enum.ForceLimitMode.Magnitude
        vel.MaxForce = 1e9
        vel.VectorVelocity = Vector3.zero
        vel.RelativeTo = Enum.ActuatorRelativeTo.World
        vel.Parent = root

        fly._alignObject = align
        fly._velocityObject = vel
        fly._parts = { attachment, align, vel }
    end

    fly.resolved = method
        fly._loop = Tracker.connect("fly." .. method, RunService.Heartbeat, function(dt)
        if not fly.enabled then return end
        local step = FLY_STEPS[fly.resolved]
        if step then
            step(dt)
        end
    end)
    return true
end

local function flyStop()
    local fly = CharacterController.fly
    if fly._loop then
        fly._loop:Disconnect()
        fly._loop = nil
    end
    flyDestroyParts(fly)
    fly.resolved = nil
end

function CharacterController:setFlyEnabled(enabled)
    local fly = self.fly
    local wasEnabled = fly.enabled
    fly.enabled = enabled and true or false
    if enabled then
        local hum = Util.getHumanoid()
        if hum then
            pcall(function() hum:ChangeState(Enum.HumanoidStateType.Freefall) end)
        end
        self:applyFly()
        Logger:info(string.format("Fly enabled (%d, method %s)", fly.speed, fly.method))
    else
        if wasEnabled then
            flyStop()
            Logger:info("Fly disabled")
        end
    end
    State.character.flyEnabled = fly.enabled
    State.character.flyResolved = fly.resolved or "—"
    self.onMethodChanged:Fire()
end

function CharacterController:setFlySpeed(speed)
    self.fly.speed = Util.clamp(speed or 60, 1, 1000)
end

function CharacterController:setFlyMethod(method, silent)
    local fly = self.fly
    if fly.method == method and not silent then return end
    fly.method = method
    if fly.enabled then
        flyStop()
        self:applyFly()
    end
end

function CharacterController:applyFly()
    local fly = self.fly
    if not fly.enabled then return end
    local root = Util.getRoot()
    if not root then
        Logger:warnOnce("Fly: no character yet — will attach on respawn")
        return
    end

    local method = fly.method
    if method == "Auto" then
        method = "CFrame"
    end
    flyStart(method)

    if fly.method == "Auto" then
                local startY = root.Position.Y
        task.delay(0.35, function()
            if not fly.enabled or fly.resolved ~= "CFrame" then return end
            local root2 = Util.getRoot()
            if not root2 then return end
            if root2.AssemblyLinearVelocity.Y < -60 or root2.Position.Y < startY - 4 then
                Logger:warn("Fly Auto: CFrame method rejected — trying BodyVelocity")
                flyStop()
                flyStart("BodyVelocity")
                State.character.flyResolved = fly.resolved or "—"
                task.delay(0.35, function()
                    if not fly.enabled or fly.resolved ~= "BodyVelocity" then return end
                    local root3 = Util.getRoot()
                    if not root3 then return end
                    if root3.AssemblyLinearVelocity.Y < -60 then
                        Logger:warn("Fly Auto: BodyVelocity rejected — trying LinearVelocity")
                        flyStop()
                        flyStart("LinearVelocity")
                        State.character.flyResolved = fly.resolved or "—"
                        self.onMethodChanged:Fire()
                    end
                end)
                self.onMethodChanged:Fire()
            end
        end)
    end
    State.character.flyResolved = fly.resolved or "—"
    self.onMethodChanged:Fire()
end

function CharacterController:setAntiAFK(enabled)
    self.flags.antiAFK = enabled and true or false
    if self._afkConn then
        self._afkConn:Disconnect()
        self._afkConn = nil
    end
    if enabled then
        self._afkConn = Tracker.connect("char.antiAFK", LocalPlayer.Idled, function()
            if not self.flags.antiAFK then return end
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.new())
            end)
        end)
        Logger:info("Anti-AFK enabled")
    else
        Logger:info("Anti-AFK disabled")
    end
end

function CharacterController:resetCharacter()
    local hum = Util.getHumanoid()
    if hum then
        hum.Health = 0
        Logger:info("Character reset requested")
    else
        local char = Util.getCharacter()
        if char then
            char:BreakJoints()
            Logger:info("Character reset (BreakJoints fallback)")
        else
            Logger:warn("Reset failed: no character")
        end
    end
end

function CharacterController:setFOV(fov)
    self.camera.fov = Util.clamp(fov, 30, 120)
    Camera.FieldOfView = self.camera.fov
end

function CharacterController:resetFOV()
    Camera.FieldOfView = self.camera.defaultFov
    self.camera.fov = nil
end

function CharacterController:bindCharacter()
    Tracker.connect("char.characterAdded", LocalPlayer.CharacterAdded, function(char)
        Logger:info("Character spawned — re-applying active features")
                local root = char:WaitForChild("HumanoidRootPart", 5)
        local hum = char:WaitForChild("Humanoid", 5)
        if not (root and hum) then
            Logger:warn("Character parts missing after respawn")
            return
        end
        task.wait(0.2)
        self:detectJumpMode()
        if self.walk.enabled then self:applyWalk() end
        if self.jump.enabled then self:applyJump() end
        if self.fly.enabled then
            flyStop()
            self:applyFly()
        end
    end)
end

function CharacterController:Start()
    self:detectJumpMode()
    self:bindCharacter()
    trackInput()
        Tracker.connect("char.cameraChanged", workspace:GetPropertyChangedSignal("CurrentCamera"), function()
        local newCam = workspace.CurrentCamera
        if newCam then
            Camera = newCam
        end
    end)
end

function CharacterController:stopAll()
    self:setWalkEnabled(false)
    self:setInfiniteJump(false)
    self:setNoclip(false)
    self:setFlyEnabled(false)
    self:setAntiAFK(false)
    self:setJumpEnabled(false)
end

function CharacterController:Cleanup()
    self:stopAll()
    self.onMethodChanged:Destroy()
end

local PlayerController = {}

PlayerController._listHandle = nil
PlayerController._refreshPending = false
PlayerController.spectating = nil
PlayerController._savedSubject = nil
PlayerController._watchConn = {}

function PlayerController.getPlayerNames()
    local names = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            table.insert(names, player.Name)
        end
    end
    table.sort(names)
    return names
end

function PlayerController.findPlayer(name)
    if type(name) ~= "string" then return nil end
    return Players:FindFirstChild(name)
end

function PlayerController:bindList(handle)
    self._listHandle = handle
        self:refreshList()
        Tracker.connect("players.added", Players.PlayerAdded, function()
        self:scheduleRefresh()
    end)
    Tracker.connect("players.removed", Players.PlayerRemoving, function(leaving)
        if self.spectating == leaving then
            self:stopSpectate("player left")
        end
        self:scheduleRefresh()
    end)
    Logger:info(string.format("Player list tracking active (%d players)", #Players:GetPlayers()))
end

function PlayerController:scheduleRefresh()
    if State.settings.autoRefreshPlayers == false then return end
    if self._refreshPending then return end
    self._refreshPending = true
    Tracker.delay("players.refresh", 0.5, function()
        self._refreshPending = false
        self:refreshList()
    end)
end

function PlayerController:refreshList()
    if not self._listHandle then return end
    local ok = pcall(function()
        self._listHandle:Refresh(self.getPlayerNames())
    end)
    if ok then
        Logger:debug("Player dropdown refreshed")
    else
        Logger:warnOnce("Player dropdown refresh failed")
    end
end

local function rootOfPlayer(player)
    local char = player and player.Character
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
end

function PlayerController:teleportTo(name, mode)
    local player = self.findPlayer(name)
    local targetRoot = rootOfPlayer(player)
    local myRoot = Util.getRoot()
    if not (targetRoot and myRoot) then
        Logger:warn("Teleport failed: character missing (you or target)")
        return false
    end

    local cf
    if mode == "behind" then
        local behind = targetRoot.CFrame.LookVector * -3
        cf = CFrame.lookAt(targetRoot.Position + behind + Vector3.new(0, 2, 0), targetRoot.Position)
    elseif mode == "above" then
        cf = CFrame.new(targetRoot.Position + Vector3.new(0, 12, 0))
    else
        cf = targetRoot.CFrame + Vector3.new(0, 3, 0)
    end

    myRoot.AssemblyLinearVelocity = Vector3.zero
    myRoot.CFrame = cf
    Logger:info(string.format("Teleported %s %s", mode or "to", player.Name))
    return true
end

function PlayerController:spectate(name)
    local player = self.findPlayer(name)
    if not player then
        Logger:warn("Spectate failed: player not found")
        return false
    end

    local hum = Util.humanoidOf(player.Character)
    if not hum then
        Logger:warn("Spectate failed: target has no humanoid (may be loading)")
        return false
    end

        if not self.spectating then
        self._savedSubject = workspace.CurrentCamera.CameraSubject
    end

    workspace.CurrentCamera.CameraSubject = hum
    self.spectating = player

        self:_clearWatch()
    self._watchConn[#self._watchConn + 1] = Tracker.connect(
        "spectate.charRemoving",
        player.CharacterRemoving,
        function() self:stopSpectate("target respawned") end
    )
    Logger:info("Spectating " .. player.Name)
    return true
end

function PlayerController:stopSpectate(reason)
    if not self.spectating then
        return false
    end
    local was = self.spectating
    self.spectating = nil
    self:_clearWatch()

    local cam = workspace.CurrentCamera
    local myHum = Util.getHumanoid()
    if self._savedSubject and self._savedSubject.Parent then
        cam.CameraSubject = self._savedSubject
    elseif myHum then
        cam.CameraSubject = myHum
    end
    self._savedSubject = nil
    Logger:info("Stopped spectating " .. was.Name .. (reason and (" (" .. reason .. ")") or ""))
    return true
end

function PlayerController:_clearWatch()
    for _, conn in ipairs(self._watchConn) do
        pcall(function() conn:Disconnect() end)
    end
    self._watchConn = {}
end

function PlayerController:Start()
    end

function PlayerController:Stop()
    self:stopSpectate("controller stopping")
end

function PlayerController:Cleanup()
    self:stopSpectate("cleanup")
    self._listHandle = nil
end

local TeleportService = game:GetService("TeleportService")
local Stats           = game:GetService("Stats")

local ServerController = {}

ServerController.VISITED_MAX   = 12
ServerController.COOLDOWN      = 5
ServerController.BACKOFF_MAX   = 60

ServerController.lastAttempt   = 0
ServerController.backoff       = 0
ServerController.attempts      = 0
ServerController._teleportWatchBound = false
ServerController._failedCount  = 0

local SERVER_API = "https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=2&limit=100"

local FILE_OK  = typeof(writefile) == "function" and typeof(readfile) == "function"
                 and typeof(isfile) == "function"

local VISITED_PATH = "PS2Hub/visited_servers.json"

local function persistVisited()
    if not FILE_OK or not State.settings.rememberVisitedServers then return end
    pcall(function()
        local payload = { jobIds = State.server.visitedOrder }
        writefile(VISITED_PATH, HttpService:JSONEncode(payload))
    end)
end

local function loadVisited()
    if not FILE_OK then return end
    pcall(function()
        if not isfile(VISITED_PATH) then return end
        local data = HttpService:JSONDecode(readfile(VISITED_PATH))
        if type(data.jobIds) == "table" then
            for _, jobId in ipairs(data.jobIds) do
                if not State.server.visited[jobId] then
                    State.server.visited[jobId] = true
                    table.insert(State.server.visitedOrder, jobId)
                end
            end
            Logger:info(string.format("Loaded %d visited server ids from disk", #data.jobIds))
        end
    end)
end

function ServerController:markVisited(jobId)
    if not jobId or jobId == "" or State.server.visited[jobId] then return end
    State.server.visited[jobId] = true
    table.insert(State.server.visitedOrder, jobId)
    while #State.server.visitedOrder > self.VISITED_MAX do
        local old = table.remove(State.server.visitedOrder, 1)
        State.server.visited[old] = nil
    end
    persistVisited()
end

function ServerController:getInfo()
    local info = {
        jobId      = game.JobId,
        placeId    = game.PlaceId,
        gameId     = game.GameId,
        players    = #Players:GetPlayers(),
        maxPlayers = Players.MaxPlayers,
        age        = 0,
        ping       = nil,
    }
    pcall(function() info.age = workspace.DistributedGameTime end)
    pcall(function()
        info.ping = math.floor(Stats.Network.ServerStatsItem["Data Ping"].Value)
    end)
    return info
end

function ServerController:fetchServers(pages)
    pages = pages or 3
    local candidates = {}
    local cursor = ""
    for _ = 1, pages do
        local url = string.format(SERVER_API, game.PlaceId)
        if cursor ~= "" then
            url = url .. "&cursor=" .. cursor
        end
        local data, err = Http.getJson(url)
        if not data then
            Logger:warn("Server list fetch failed: " .. tostring(err))
            break
        end
        if type(data.data) ~= "table" or #data.data == 0 then
            Logger:debug("Server page empty — stopping pagination")
            break
        end
        for _, server in ipairs(data.data) do
            if type(server.id) == "string" and server.id ~= game.JobId then
                table.insert(candidates, {
                    jobId      = server.id,
                    playing    = server.playing or 0,
                    maxPlayers = server.maxPlayers or Players.MaxPlayers,
                })
            end
        end
        cursor = data.nextPageCursor or ""
        if cursor == "" or cursor == nil then break end
    end
    Logger:debug(string.format("Fetched %d candidate servers", #candidates))
    return candidates
end

local function filterCandidates(candidates, maxPlaying, includeFull)
    local out = {}
    for _, server in ipairs(candidates) do
        if not State.server.visited[server.jobId] then
            local notFull = server.playing < server.maxPlayers
            if includeFull or notFull then
                if server.playing <= maxPlaying then
                    table.insert(out, server)
                end
            end
        end
    end
    return out
end

function ServerController:bindTeleportWatch()
    if self._teleportWatchBound then return end
    self._teleportWatchBound = true
    Tracker.connect("server.teleportFailed", TeleportService.TeleportInitFailed, function(player, result, errorMessage)
        if player ~= LocalPlayer then return end
        if not State.server.hopping then return end
        self._failedCount = self._failedCount + 1
        Logger:warn(string.format("Teleport failed (%s): %s", tostring(result), tostring(errorMessage)))
            end)
end

function ServerController:teleportTo(jobId)
    local ok, err = pcall(function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, jobId, LocalPlayer)
    end)
    if not ok then
        Logger:warn("Teleport call failed: " .. tostring(err))
        return false
    end
    return true
end

local function cooldownRemaining(self)
    local base = self.COOLDOWN + self.backoff
    local elapsed = os.clock() - self.lastAttempt
    return math.max(0, base - elapsed)
end

function ServerController:canHop()
    if State.server.hopping then
        return false, "hop already in progress"
    end
    local remaining = cooldownRemaining(self)
    if remaining > 0 then
        return false, string.format("cooldown %.0fs", remaining)
    end
    if not Http.available then
        return false, "HTTP API unavailable in this executor"
    end
    if game.JobId == "" then
        return false, "not supported in Studio"
    end
    return true
end

function ServerController:hop(mode, maxPlaying)
    mode = mode or "any"
    maxPlaying = maxPlaying or math.huge

    local ok, reason = self:canHop()
    if not ok then
        Logger:warn("Hop blocked: " .. reason)
        Notify.toast("Server hop", reason)
        return false
    end

    State.server.hopping = true
    self.lastAttempt = os.clock()
    self:bindTeleportWatch()

    local label = (mode == "low") and "Low server hop" or "Server hop"
    Notify.notify(label .. " started", "Searching for a target server…")
    Logger:info(label .. " started")

        self:markVisited(game.JobId)

    task.spawn(function()
        local attemptsLeft = 3
        local succeeded = false

        while attemptsLeft > 0 and not succeeded and not Tracker.shuttingDown do
            local candidates = ServerController:fetchServers(3)
            if mode == "low" then
                                table.sort(candidates, function(a, b) return a.playing < b.playing end)
            end
            local pool = filterCandidates(candidates, maxPlaying, false)

            if #pool == 0 then
                                if mode == "any" then
                    pool = filterCandidates(candidates, math.huge, false)
                end
                if #pool == 0 then
                    pool = filterCandidates(candidates, maxPlaying, true)
                end
            end

            if #pool == 0 then
                Logger:warn("No eligible servers found (all visited/full)")
                Notify.notify(label .. " failed", "No eligible servers found. Try again shortly.")
                break
            end

            local candidate = pool[math.random(#pool)]
            Logger:info(string.format(
                "Hop target: %s (%d/%d players, attempt %d)",
                candidate.jobId:sub(1, 8) .. "…", candidate.playing, candidate.maxPlayers, 4 - attemptsLeft
            ))

            local before = ServerController._failedCount
            local okTeleport = ServerController:teleportTo(candidate.jobId)

            if okTeleport then
                                local waited = 0
                while waited < 8 and not Tracker.shuttingDown do
                    task.wait(0.5)
                    waited = waited + 0.5
                    if ServerController._failedCount > before then
                        break
                    end
                end
                if ServerController._failedCount > before then
                                        ServerController:markVisited(candidate.jobId)
                    attemptsLeft = attemptsLeft - 1
                    ServerController.backoff = math.min(ServerController.backoff * 2 + 2, ServerController.BACKOFF_MAX)
                    task.wait(1)
                else
                    succeeded = true
                    Notify.notify(label .. " successful", "Teleporting…")
                    Logger:info("Teleport initiated to " .. candidate.jobId)
                end
            else
                ServerController:markVisited(candidate.jobId)
                attemptsLeft = attemptsLeft - 1
                ServerController.backoff = math.min(ServerController.backoff * 2 + 2, ServerController.BACKOFF_MAX)
                task.wait(1)
            end
        end

        if not succeeded then
            Notify.notify(label .. " gave up", "Retried with backoff. You are still in this server.")
        end
        State.server.hopping = false
    end)

    return true
end

function ServerController:rejoin()
    if game.JobId == "" then
        Logger:warn("Rejoin not supported in Studio")
        Notify.toast("Rejoin", "Not supported in Studio")
        return false
    end
    Notify.notify("Rejoin started", "Rejoining the current server…")
    Logger:info("Rejoin initiated")
    local ok, err = pcall(function()
        if game.JobId ~= "" then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        else
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        end
    end)
    if not ok then
        Notify.error("Rejoin", err)
    end
    return ok
end

function ServerController:Start()
    loadVisited()
    self:bindTeleportWatch()
    Logger:info("Server controller ready")
end

function ServerController:Stop()
    State.server.hopping = false
end

function ServerController:Cleanup()
    State.server.hopping = false
end

local CollectionService = game:GetService("CollectionService")

local DiscoveryController = {}

DiscoveryController.cache      = {}
DiscoveryController.byName     = {}
DiscoveryController.containers = {}
DiscoveryController.onCacheUpdated = Signal.new()
DiscoveryController._scanLoop  = nil
DiscoveryController._deepEvery = 5
DiscoveryController._scanCount = 0
DiscoveryController.lastSummary = "no scans yet"

local function isPlayerCharacter(model)
    local character = LocalPlayer and LocalPlayer.Character
    return model == character
end

local function looksLikeTarget(model, npcConfig)
    if not model:IsA("Model") then return false end
    if isPlayerCharacter(model) then return false end

    local name = model.Name or ""

        for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == model then return false end
    end

    if Util.matchAny(npcConfig.excludePatterns, name) then
        return false
    end

    local humanoid = model:FindFirstChildOfClass("Humanoid")
    if npcConfig.requireHumanoid and not humanoid then
        return false
    end

    local root = Util.findRootOf(model)
    if npcConfig.requireRootPart and not root then
        return false
    end

        local tagged = false
    for _, tag in ipairs(npcConfig.tags or {}) do
        if CollectionService:HasTag(model, tag) then
            tagged = true
            break
        end
    end
    local attributed = false
    for _, attr in ipairs(npcConfig.targetAttributes or {}) do
        if model:GetAttribute(attr) ~= nil then
            attributed = true
            break
        end
    end
    local nameMatched = Util.matchAny(npcConfig.namePatterns, name)

    if not (tagged or attributed or nameMatched) then
        return false
    end

        local isBoss = Util.matchAny(npcConfig.bossPatterns, name)
        or (npcConfig.bossAttribute and model:GetAttribute(npcConfig.bossAttribute) == true)

    return true, humanoid, root, isBoss
end

local function refreshContainers()
    DiscoveryController.containers = {}
    local wanted = GameProfile.NPC.containers or {}
    for _, child in ipairs(workspace:GetChildren()) do
        if child:IsA("Folder") or child:IsA("Model") or child:IsA("Configuration") then
            for _, wantedName in ipairs(wanted) do
                if child.Name == wantedName then
                    table.insert(DiscoveryController.containers, child)
                    break
                end
            end
        end
    end
end

local function addRecord(model, humanoid, root, isBoss)
        for _, existing in ipairs(DiscoveryController.cache) do
        if existing.model == model then
            return false
        end
    end
    local entry = {
        model    = model,
        name     = model.Name,
        humanoid = humanoid or model:FindFirstChildOfClass("Humanoid"),
        root     = root or Util.findRootOf(model),
        isBoss   = isBoss and true or false,
        category = isBoss and "Boss" or "NPC",
        distance = math.huge,
        path     = model:GetFullName(),
    }
    if not entry.humanoid then return false end
    if not entry.root then return false end
    table.insert(DiscoveryController.cache, entry)
    DiscoveryController.byName[entry.name] = entry
    return true
end

local function scanTagged()
    local added = 0
    for _, tag in ipairs(GameProfile.NPC.tags or {}) do
        local ok, tagged = pcall(function() return CollectionService:GetTagged(tag) end)
        if ok and tagged then
            for _, inst in ipairs(tagged) do
                if inst:IsA("Model") then
                    local qualifies, hum, root, isBoss = looksLikeTarget(inst, GameProfile.NPC)
                    if qualifies and addRecord(inst, hum, root, isBoss) then
                        added = added + 1
                    end
                end
            end
        end
    end
    return added
end

local function scanContainers()
    local added = 0
    for _, container in ipairs(DiscoveryController.containers) do
        local ok, descendants = pcall(function() return container:GetDescendants() end)
        if ok and descendants then
            for _, inst in ipairs(descendants) do
                if inst:IsA("Model") then
                    local qualifies, hum, root, isBoss = looksLikeTarget(inst, GameProfile.NPC)
                    if qualifies and addRecord(inst, hum, root, isBoss) then
                        added = added + 1
                    end
                end
            end
        end
    end
    return added
end

local function scanDeep()
            local added = 0
    local ok, descendants = pcall(function() return workspace:GetDescendants() end)
    if ok and descendants then
        for _, inst in ipairs(descendants) do
            if inst:IsA("Model") then
                local qualifies, hum, root, isBoss = looksLikeTarget(inst, GameProfile.NPC)
                if qualifies and addRecord(inst, hum, root, isBoss) then
                    added = added + 1
                end
            end
        end
    end
    return added
end

local function revalidate()
    local removed = 0
    for i = #DiscoveryController.cache, 1, -1 do
        local entry = DiscoveryController.cache[i]
        local valid = pcall(function()
            return entry.model.Parent ~= nil
                and entry.humanoid.Parent ~= nil
                and entry.root.Parent ~= nil
        end)
        if not valid then
            if DiscoveryController.byName[entry.name] == entry then
                DiscoveryController.byName[entry.name] = nil
            end
            table.remove(DiscoveryController.cache, i)
            removed = removed + 1
        else
                        local myPos = Util.localRootDistance()
            if myPos then
                local ok = pcall(function()
                    entry.distance = (entry.root.Position - myPos).Magnitude
                end)
                if not ok then
                    entry.distance = math.huge
                end
            end
        end
    end
    return removed
end

local function runScan()
    DiscoveryController._scanCount = DiscoveryController._scanCount + 1
    local removed = revalidate()
    refreshContainers()

    local added = scanTagged() + scanContainers()

        if #DiscoveryController.containers == 0
       and (DiscoveryController._scanCount % DiscoveryController._deepEvery) == 0 then
        added = added + scanDeep()
    end

    if added > 0 or removed > 0 then
        DiscoveryController.lastSummary = string.format(
            "%d targets cached (%d added, %d expired this scan)",
            #DiscoveryController.cache, added, removed
        )
        if added > 0 then
            Logger:info(string.format("Found %d new potential targets", added))
        end
        DiscoveryController.onCacheUpdated:Fire(DiscoveryController.cache)
    else
        DiscoveryController.lastSummary = string.format(
            "%d targets cached (stable)", #DiscoveryController.cache
        )
    end
        Logger:debug(DiscoveryController.lastSummary)
end

function DiscoveryController:names()
    local out = {}
    for _, entry in ipairs(self.cache) do
        table.insert(out, entry.name)
    end
    table.sort(out)
    return out
end

function DiscoveryController:bossNames()
    local out = {}
    for _, entry in ipairs(self.cache) do
        if entry.isBoss then
            table.insert(out, entry.name)
        end
    end
    table.sort(out)
    return out
end

function DiscoveryController:dumpToConsole()
    Logger:info("===== DISCOVERED TARGET DUMP =====")
    if #self.cache == 0 then
        Logger:info("(nothing discovered — adjust GameProfile.NPC patterns)")
    end
    for i, entry in ipairs(self.cache) do
        local hum = entry.humanoid
        Logger:info(string.format(
            "%02d. %s  [%s] hp=%d/%d  path=%s",
            i, entry.name, entry.category,
            math.floor(hum.Health or 0), math.floor(hum.MaxHealth or 0),
            entry.path
        ))
    end
    Logger:info("===== END DUMP =====")
end

function DiscoveryController:Start()
    Logger:info("Target manager initialized (discovery layer)")
    self._scanLoop = Tracker.loop("discovery.scan", function() return State.intervals.targetScan end, function()
        runScan()
    end)
        task.spawn(runScan)
end

function DiscoveryController:Stop()
    if self._scanLoop then
        self._scanLoop:Stop()
        self._scanLoop = nil
    end
end

function DiscoveryController:Cleanup()
    self:Stop()
    self.cache = {}
    self.byName = {}
    self.onCacheUpdated:Destroy()
end

local TargetManager = {}

TargetManager.mode        = "Nearest"
TargetManager.selected    = nil
TargetManager.exclusions  = {}
TargetManager.skipUntil   = {}
TargetManager.maxRange    = 2000
TargetManager.onTargetChanged = Signal.new()

function TargetManager:setMode(mode)
    self.mode = mode
    Logger:debug("Target mode: " .. tostring(mode))
end

function TargetManager:setSelected(name)
    self.selected = name
    Logger:info("Selected target: " .. tostring(name))
end

function TargetManager:setExclusions(list)
    self.exclusions = {}
    for _, name in ipairs(list or {}) do
        self.exclusions[name] = true
    end
    Logger:debug("Exclusions updated: " .. tostring(#list) .. " entries")
end

function TargetManager:setMaxRange(range)
    self.maxRange = Util.clamp(range or 2000, 50, 100000)
end

function TargetManager:isValid(entry)
    if type(entry) ~= "table" then return false, "not a record" end
    local ok = pcall(function()
        if entry.model.Parent == nil then error("instance removed") end
        if entry.humanoid.Parent == nil then error("humanoid removed") end
        if entry.root.Parent == nil then error("root removed") end
    end)
    if not ok then return false, "instance gone" end
    if entry.humanoid.Health <= 0 then return false, "defeated" end
    if entry.distance > self.maxRange then return false, "out of range" end
    if self.exclusions[entry.name] then return false, "excluded" end
    local skip = self.skipUntil[entry.name]
    if skip and os.clock() < skip then return false, "temporarily skipped" end
    if entry.model == (LocalPlayer and LocalPlayer.Character) then return false, "local player" end
    return true
end

function TargetManager:skipTemporarily(name, seconds)
    self.skipUntil[name] = os.clock() + (seconds or 15)
end

local function smartScore(entry)
    local healthRatio = entry.humanoid.MaxHealth > 0
        and (entry.humanoid.Health / entry.humanoid.MaxHealth) or 0
    local score = entry.distance * (1.2 - healthRatio * 0.2)
    if entry.isBoss then
        score = score - 300
    end
    return score
end

function TargetManager:acquire()
    local cache = DiscoveryController.cache
    if #cache == 0 then
        return nil, "no targets discovered"
    end

    local best, bestScore, bestDist = nil, math.huge, math.huge

    if self.mode == "Selected" then
        local entry = self.selected and DiscoveryController.byName[self.selected] or nil
        if not entry then
            return nil, "selected target not present"
        end
        local ok, reason = self:isValid(entry)
        if ok then return entry end
        return nil, "selected target invalid (" .. reason .. ")"

    elseif self.mode == "Boss" then
        for _, entry in ipairs(cache) do
            if entry.isBoss then
                local ok = self:isValid(entry)
                if ok and entry.distance < bestDist then
                    best, bestDist = entry, entry.distance
                end
            end
        end
        if best then return best end
        return nil, "no boss targets discovered"

    elseif self.mode == "Smart" then
        for _, entry in ipairs(cache) do
            local ok = self:isValid(entry)
            if ok then
                local score = smartScore(entry)
                if score < bestScore then
                    best, bestScore = entry, score
                end
            end
        end
        if best then return best end
        return nil, "no valid targets (smart)"

    else
        for _, entry in ipairs(cache) do
            local ok = self:isValid(entry)
            if ok and entry.distance < bestDist then
                best, bestDist = entry, entry.distance
            end
        end
        if best then return best end
        return nil, "no valid targets in range"
    end
end

function TargetManager:Start()
        DiscoveryController.onCacheUpdated:Connect(function()
        local current = State.automation.target
        if current then
            local ok, reason = TargetManager:isValid(current)
            if not ok then
                Logger:debug("Target became invalid (" .. reason .. ") — will re-acquire")
                State.automation.target = nil
            end
        end
    end)
end

function TargetManager:Cleanup()
    self.onTargetChanged:Destroy()
end

local TweenService       = game:GetService("TweenService")
local PathfindingService = game:GetService("PathfindingService")

local MovementController = {}

MovementController.method   = "Auto"
MovementController.resolved = nil
MovementController.speed   = 60
MovementController.arrival = 4
MovementController.timeout = 20

MovementController._active  = false
MovementController._entry   = nil
MovementController._tween   = nil
MovementController._path    = nil
MovementController._waypoints, MovementController._wpIndex = nil, 0
MovementController._startedAt = 0
MovementController._lastPos, MovementController._lastProgress = nil, 0
MovementController.onMethodSwitched = Signal.new()

local STUCK_DISTANCE = 1.5
local STUCK_WINDOW   = 2.5

local function cancelTween()
    if MovementController._tween then
        pcall(function() MovementController._tween:Cancel() end)
        MovementController._tween = nil
    end
end

local function cancelPath()
    MovementController._path = nil
    MovementController._waypoints = nil
    MovementController._wpIndex = 0
end

local function resolveMethod()
    local m = MovementController.method
    if m ~= "Auto" then
        MovementController.resolved = m
        return m
    end
    return "Walk"
end

local function switchMethod(reason, newMethod)
    if MovementController.resolved == newMethod then return end
    Logger:warn("Movement method failed (" .. reason .. ") — switching to " .. newMethod)
    MovementController.resolved = newMethod
    cancelTween()
    cancelPath()
    MovementController.onMethodSwitched:Fire(newMethod)
end

local function stepWalk(targetPos, dist)
    local hum = Util.getHumanoid()
    local root = Util.getRoot()
    if not (hum and root) then return "failed" end
    hum:MoveTo(targetPos)
    return dist <= MovementController.arrival and "arrived" or "moving"
end

local function stepPathfind(targetPos, dist)
    local hum = Util.getHumanoid()
    if not hum then return "failed" end

    local needsPath = MovementController._waypoints == nil
    if MovementController._waypoints and MovementController._pathEnd then
        if (MovementController._pathEnd - targetPos).Magnitude > 12 then
            needsPath = true
        end
    end

    if needsPath then
        local ok, path = pcall(function()
            local p = PathfindingService:CreatePath({
                AgentRadius = 2.5,
                AgentHeight = 6,
                AgentCanJump = true,
                Costs = { Water = 20 },
            })
            p:ComputeAsync(Util.getRoot().Position, targetPos)
            return p
        end)
        if not ok or not path or path.Status ~= Enum.PathStatus.Success then
            return "failed"
        end
        MovementController._path = path
        MovementController._waypoints = path:GetWaypoints()
        MovementController._wpIndex = 2
        MovementController._pathEnd = targetPos
        Logger:debug(string.format("Path computed: %d waypoints", #MovementController._waypoints))
    end

    local wps = MovementController._waypoints
    if not wps then return "failed" end

    local wp = wps[MovementController._wpIndex]
    if not wp then
        return dist <= MovementController.arrival + 2 and "arrived" or "failed"
    end
    local root = Util.getRoot()
    if not root then return "failed" end
    if (wp.Position - root.Position).Magnitude < 3 then
        MovementController._wpIndex = MovementController._wpIndex + 1
        wp = wps[MovementController._wpIndex]
        if not wp then
            return dist <= MovementController.arrival + 2 and "arrived" or "failed"
        end
    end
    if wp.Action == Enum.PathWaypointAction.Jump then
        local hum2 = Util.getHumanoid()
        if hum2 then hum2.Jump = true end
    end
    hum:MoveTo(wp.Position)
    return "moving"
end

local function stepTween(targetPos, dist)
    local root = Util.getRoot()
    if not root then return "failed" end

    if MovementController._tween then
        return dist <= MovementController.arrival and "arrived" or "moving"
    end

    local distance = (targetPos - root.Position).Magnitude
    if distance <= MovementController.arrival then
        return "arrived"
    end

    local duration = math.max(0.1, distance / MovementController.speed)
    local ok, tween = pcall(function()
        local t = TweenService:Create(
            root,
            TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out),
            { CFrame = CFrame.lookAt(targetPos, targetPos + Vector3.new(0, 0, -1)) }
        )
        t:Play()
        return t
    end)
    if not ok then return "failed" end
    MovementController._tween = tween
    MovementController._tweenEnd = targetPos
    Logger:debug(string.format("Tween started: %.1f studs over %.1fs", distance, duration))
    return "moving"
end

local function stepCFrame(targetPos, dist, dt)
    local root = Util.getRoot()
    if not root then return "failed" end
    if dist <= MovementController.arrival then
        return "arrived"
    end
        local step = math.min(MovementController.speed * dt, dist - 0.05)
    if step <= 0 then
        return "arrived"
    end
    local dir = (targetPos - root.Position).Unit
    root.AssemblyLinearVelocity = Vector3.zero
    root.CFrame = CFrame.lookAt(root.Position + dir * step, targetPos)
    return "moving"
end

function MovementController:begin(entry)
    self._active = true
    self._entry = entry
    self._startedAt = os.clock()
    self._lastPos = nil
    self._lastProgress = os.clock()
    self.resolved = resolveMethod()
    cancelTween()
    cancelPath()
    self.onMethodSwitched:Fire(self.resolved)
    Logger:debug(string.format("Movement: %s -> %s (%.0f studs)",
        self.resolved, entry.name, entry.distance))
end

function MovementController:cancel(reason)
    if not self._active then return end
    self._active = false
    self._entry = nil
    cancelTween()
    cancelPath()
    Logger:debug("Movement cancelled" .. (reason and (" (" .. reason .. ")") or ""))
end

function MovementController:tick(dt)
    dt = dt or 1 / 30
    local entry = self._entry
    if not self._active or not entry then return "failed" end

        local ok = pcall(function()
        if entry.model.Parent == nil or entry.root.Parent == nil then error("gone") end
    end)
    if not ok then return "failed" end

        if CharacterController.fly.enabled then
        return "moving"
    end

    local root = Util.getRoot()
    if not root then return "failed" end
    local targetPos = entry.root.Position
    local dist = (targetPos - root.Position).Magnitude

        if self._tween and self._tweenEnd and (self._tweenEnd - targetPos).Magnitude > 8 then
        cancelTween()
    end

        if os.clock() - self._startedAt > self.timeout then
        return "failed"
    end

        local pos = root.Position
    if self._lastPos then
        local moved = (pos - self._lastPos).Magnitude
        if moved > STUCK_DISTANCE then
            self._lastProgress = os.clock()
        elseif os.clock() - self._lastProgress > STUCK_WINDOW then
            if self.resolved == "Walk" then
                switchMethod("stuck", "Pathfind")
            elseif self.resolved == "Pathfind" then
                switchMethod("stuck on route", "Tween")
            end
            self._lastProgress = os.clock()
        end
    end
    self._lastPos = pos

    local status
    local method = self.resolved or "Walk"
    if method == "Walk" then
        status = stepWalk(targetPos, dist)
    elseif method == "Pathfind" then
        status = stepPathfind(targetPos, dist)
    elseif method == "Tween" then
        status = stepTween(targetPos, dist)
    else
        status = stepCFrame(targetPos, dist, dt)
    end

    if status == "failed" and self.method == "Auto" then
        if self.resolved == "Walk" then
            switchMethod("walk failed", "Pathfind")
            status = "moving"
        elseif self.resolved == "Pathfind" then
            switchMethod("no path", "Tween")
            status = "moving"
        end
    end

    if status == "arrived" then
        self._active = false
        cancelTween()
        cancelPath()
    end
    return status
end

function MovementController:Stop()
    self:cancel("controller stopping")
end

function MovementController:Cleanup()
    self:cancel("cleanup")
    self.onMethodSwitched:Destroy()
end

local InteractionController = {}

InteractionController.mode           = "Auto"
InteractionController.delay          = 0.5
InteractionController.range          = 10
InteractionController.autoAttack     = true
InteractionController.attackInterval = 0.4

InteractionController._lastInteract = 0
InteractionController._lastAttack   = 0
InteractionController._equippedTool = nil

local function findPrompt(entry)
    local prompt
    pcall(function()
        prompt = entry.model:FindFirstChildWhichIsA("ProximityPrompt", true)
    end)
    return prompt
end

local function findClickDetector(entry)
    local click
    pcall(function()
        click = entry.model:FindFirstChildWhichIsA("ClickDetector", true)
    end)
    return click
end

local function findCombatTool()
    local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
    local char = Util.getCharacter()
    local candidates = {}
    for _, container in ipairs({ char, backpack }) do
        if container then
            for _, tool in ipairs(container:GetChildren()) do
                if tool:IsA("Tool") and Util.matchAny(GameProfile.INTERACTION.toolNamePatterns, tool.Name) then
                    table.insert(candidates, tool)
                end
            end
        end
    end
    return candidates[1]
end

local function equipTool(tool)
    local hum = Util.getHumanoid()
    if not (hum and tool) then return false end
    if tool.Parent == Util.getCharacter() then
        return true
    end
    local ok = pcall(function() hum:EquipTool(tool) end)
    return ok
end

local function doPrompt(entry)
    local prompt = findPrompt(entry)
    if not prompt then return false end
    local ok = pcall(function() prompt:FirePrompt() end)
    if ok then
        Logger:debug("Interacted (ProximityPrompt) with " .. entry.name)
    end
    return ok
end

local function doClick(entry)
    local click = findClickDetector(entry)
    if not click then return false end
    local ok = pcall(function() click:FireServer(Vector3.new()) end)
    if ok then
        Logger:debug("Interacted (ClickDetector) with " .. entry.name)
    end
    return ok
end

local function doToolAttack(entry)
    local tool = findCombatTool()
    if not tool then return false end
    if not equipTool(tool) then return false end
    InteractionController._equippedTool = tool
    local ok = pcall(function() tool:Activate() end)
    if ok then
        Logger:debug("Tool activated (" .. tool.Name .. ") on " .. entry.name)
    end
    return ok
end

function InteractionController:inRange(entry)
    local root = Util.getRoot()
    if not (root and entry and entry.root and entry.root.Parent) then
        return false
    end
    return (entry.root.Position - root.Position).Magnitude <= self.range
end

function InteractionController:tick(entry)
    if not entry then return false end
    if not self:inRange(entry) then return false end

    local now = os.clock()
    local acted = false

        if self.autoAttack then
        if now - self._lastAttack >= self.attackInterval then
            if doToolAttack(entry) then
                self._lastAttack = now
                acted = true
            end
        end
    end

    if now - self._lastInteract >= self.delay then
        local mode = self.mode
        if mode == "Auto" then
            if doPrompt(entry) or doClick(entry) then
                self._lastInteract = now
                acted = true
            end
        elseif mode == "ProximityPrompt" then
            if doPrompt(entry) then
                self._lastInteract = now
                acted = true
            end
        elseif mode == "ClickDetector" then
            if doClick(entry) then
                self._lastInteract = now
                acted = true
            end
        elseif mode == "Tool" then
            if doToolAttack(entry) then
                self._lastInteract = now
                acted = true
            end
        end
    end

    return acted
end

function InteractionController:reset()
    self._lastInteract = 0
    self._lastAttack = 0
    self._equippedTool = nil
end

function InteractionController:Stop()
        self:reset()
end

function InteractionController:Cleanup()
    self:reset()
end

local AutomationController = {}
local QuestController = {}

AutomationController.enabled      = false
AutomationController._loop        = nil
AutomationController._lastLoggedTarget = nil
AutomationController._questWarned = false

function AutomationController:isModeAvailable(mode)
    if mode == "Quest" then
        return QuestController.isAvailable()
    end
    return true
end

local function farmTick()
    local state = State.automation

        local target = state.target
    if target then
        local ok, reason = TargetManager:isValid(target)
        if not ok then
            Logger:debug("Target lost: " .. tostring(reason))
            state.target = nil
            target = nil
        end
    end
    if not target then
        local entry, reason = TargetManager:acquire()
        if entry then
            state.target = entry
            if AutomationController._lastLoggedTarget ~= entry.name then
                Logger:info("Current target: " .. entry.name)
                AutomationController._lastLoggedTarget = entry.name
            end
        else
            if state.taskState ~= "Searching" then
                state.taskState = "Searching"
                Logger:debug("No target: " .. tostring(reason))
            end
            return
        end
    end

    target = state.target

        if not InteractionController:inRange(target) then
        if not MovementController._active or MovementController._entry ~= target then
            MovementController:begin(target)
        end
        local status = MovementController:tick(0.25)
        if status == "failed" then
            Logger:warn("Movement to target failed — acquiring another")
            TargetManager:skipTemporarily(target.name, 15)
            state.target = nil
            state.taskState = "Searching"
            return
        end
        if state.taskState ~= "Moving" then
            state.taskState = "Moving"
        end
        return
    end

        if MovementController._active then
        MovementController:cancel("in range")
    end

    local acted = InteractionController:tick(target)
    state.taskState = "Attacking"
    if acted then
        state.interactions = state.interactions + 1
    end

        if target.humanoid.Health <= 0 then
        state.kills = state.kills + 1
        Logger:info(string.format("Target defeated: %s (total %d)", target.name, state.kills))
        state.target = nil
        state.taskState = "Searching"
    end
end

local function tickAutomation()
    local auto = AutomationController
    local state = State.automation

    if not auto.enabled then return end

        if not Util.aliveLocal() then
        if state.taskState ~= "WaitingRespawn" then
            state.taskState = "WaitingRespawn"
            MovementController:cancel("player defeated")
            Logger:info("Player defeated — waiting for respawn")
        end
        return
    end
    if state.taskState == "WaitingRespawn" then
        Logger:info("Respawned — automation resuming")
        state.taskState = "Searching"
    end

            local mode = TargetManager.mode
    if mode == "Quest" then
        if not QuestController.isAvailable() then
            if not auto._questWarned then
                auto._questWarned = true
                Logger:warn("Quest mode unavailable — game data pending release")
                Notify.toast("Automation", "Quest mode awaiting game release data")
            end
            state.taskState = "Idle"
            return
        end
                if QuestController.state ~= "Active"
           and MovementController._active
           and not QuestController:isGiver(MovementController._entry) then
            MovementController:cancel("quest: heading to giver")
        end
        QuestController:tick()
        local questState = QuestController.state
        if questState == "Active" then
            farmTick()
        else
            state.target = nil
        end
        state.taskState = "Quest: " .. questState
        return
    end

    farmTick()
end

function AutomationController:start()
    if self.enabled then return end
    if not GameDetector.shouldEnableGameFeatures() then
        local reason = GameDetector.gameLockReason() or "Only runs in Project Slayers 2"
        Logger:warn("Automation locked: " .. reason)
        Notify.toast("Automation", "Locked — " .. reason)
        return false
    end
    self.enabled = true
    self._questWarned = false
    State.automation.enabled = true
    State.automation.taskState = "Searching"
    InteractionController:reset()
    Notify.notify("Automation enabled", "Mode: " .. TargetManager.mode)
    Logger:info("Automation enabled (mode " .. TargetManager.mode .. ")")

    self._loop = Tracker.loop("automation.tick", function() return State.intervals.automation end, function()
        tickAutomation()
    end)
    return true
end

function AutomationController:stop()
    if not self.enabled then
        return
    end
    self.enabled = false
    if self._loop then
        self._loop:Stop()
        self._loop = nil
    end
    MovementController:cancel("automation stopped")
    State.automation.enabled = false
    State.automation.taskState = "Idle"
    State.automation.target = nil
    Notify.notify("Automation disabled", "Farm loop stopped cleanly")
    Logger:info("Automation disabled")
end

function AutomationController:Stop()
    self:stop()
end

function AutomationController:Cleanup()
    self:stop()
end

QuestController.enabled     = false
QuestController.autoAccept  = true
QuestController.autoTurnIn  = true
QuestController.state       = "Idle"
QuestController.givers      = {}
QuestController.objectiveText = ""
QuestController.active      = false

QuestController._loop        = nil
QuestController._objectiveLabel = nil
QuestController._lastObjective  = ""
QuestController._giverScanAt    = 0
QuestController._uiScanAt       = 0
QuestController._nextFireAt     = 0
QuestController._giverSkip      = {}

function QuestController.isAvailable()
            return GameDetector.shouldEnableGameFeatures() and GameProfile.QUEST.enabled == true
end

function QuestController:detectQuestUI(force)
    if not force and self._objectiveLabel and self._objectiveLabel.Parent then
        return self._objectiveLabel
    end
    self._objectiveLabel = nil

    local okGui, gui = pcall(function() return LocalPlayer:FindFirstChild("PlayerGui") end)
    if not okGui or not gui then
        return nil, "PlayerGui not found"
    end
    local okD, labels = pcall(function() return gui:GetDescendants() end)
    if not okD or type(labels) ~= "table" then
        return nil, "PlayerGui not readable"
    end

    local best, bestScore = nil, 0
    for _, inst in ipairs(labels) do
        local isLabel = false
        pcall(function() isLabel = inst:IsA("TextLabel") end)
        if isLabel then
            local text = ""
            pcall(function() text = tostring(inst.Text or "") end)
            if #Util.trim(text) > 0 then
                local path, name = "", ""
                pcall(function() path = string.lower(inst:GetFullName()) end)
                pcall(function() name = string.lower(inst.Name) end)
                local score = 0
                if Util.matchAny(GameProfile.QUEST.objectiveUIPatterns, path) then
                    score = 3
                elseif Util.matchAny(GameProfile.QUEST.objectiveUIPatterns, name) then
                    score = 2
                elseif Util.matchAny(GameProfile.QUEST.objectiveUIPatterns, text) then
                    score = 1
                end
                if score > bestScore then
                    best, bestScore = inst, score
                end
            end
        end
    end
    if best then
        self._objectiveLabel = best
        return best
    end
    return nil, "no quest UI detected"
end

function QuestController:readObjective()
    local label = self:detectQuestUI(false)
    if not label then return "" end
    local ok, text = pcall(function() return label.Text end)
    if not ok then return "" end
    return Util.trim(tostring(text or ""))
end

local function qualifyGiver(model, tagged)
    if not (typeof(model) == "Instance" and model:IsA("Model")) then
        return nil
    end
    local root = Util.findRootOf(model)
    if not root then return nil end

    local prompt
    pcall(function() prompt = model:FindFirstChildWhichIsA("ProximityPrompt", true) end)
    if not prompt then return nil end

    if not tagged then
        local qualifies = Util.matchAny(GameProfile.QUEST.giverPatterns, model.Name or "")
        if not qualifies then
            local promptText = ""
            pcall(function()
                promptText = string.format(
                    "%s %s",
                    tostring(prompt.ActionText or ""),
                    tostring(prompt.ObjectText or "")
                )
            end)
            qualifies = Util.matchAny(GameProfile.QUEST.promptPatterns, promptText)
        end
        if not qualifies then return nil end
    end

    local hum
    pcall(function() hum = model:FindFirstChildOfClass("Humanoid") end)
    return {
        model    = model,
        name     = model.Name,
        root     = root,
        humanoid = hum,
        prompt   = prompt,
        distance = math.huge,
        path     = model:GetFullName(),
    }
end

function QuestController:scanGivers(force)
    local now = os.clock()
    if not force and now - self._giverScanAt < 5 then
        return self.givers
    end
    self._giverScanAt = now

    local givers = {}
    local seen = {}

        for _, tag in ipairs(GameProfile.QUEST.tags or {}) do
        local ok, tagged = pcall(function() return CollectionService:GetTagged(tag) end)
        if ok and type(tagged) == "table" then
            for _, inst in ipairs(tagged) do
                if not seen[inst] then
                    local giver = qualifyGiver(inst, true)
                    if giver then
                        seen[inst] = true
                        table.insert(givers, giver)
                    end
                end
            end
        end
    end

            local okC, children = pcall(function() return workspace:GetChildren() end)
    if okC and type(children) == "table" then
        for _, child in ipairs(children) do
            local isCandidate = false
            for _, wanted in ipairs(GameProfile.QUEST.containers or {}) do
                if child.Name == wanted then
                    isCandidate = true
                    break
                end
            end
            if not isCandidate and Util.matchAny(GameProfile.QUEST.giverPatterns, child.Name or "") then
                isCandidate = true
            end
            if isCandidate then
                local okD, kids = pcall(function() return child:GetDescendants() end)
                if okD and type(kids) == "table" then
                    for _, inst in ipairs(kids) do
                        if not seen[inst] then
                            local giver = qualifyGiver(inst, false)
                            if giver then
                                seen[inst] = true
                                table.insert(givers, giver)
                            end
                        end
                    end
                end
            end
        end
    end

    self.givers = givers
    return givers
end

function QuestController:nearestGiver()
    local myRoot = Util.getRoot()
    if not myRoot then return nil end
    local now = os.clock()
    local best, bestDist = nil, math.huge
    for _, giver in ipairs(self.givers) do
        local alive = false
        pcall(function()
            alive = giver.model.Parent ~= nil and giver.root.Parent ~= nil
        end)
        if not alive then
                    elseif self._giverSkip[giver.name] and now < self._giverSkip[giver.name] then
                    else
            local ok, dist = pcall(function()
                return (giver.root.Position - myRoot.Position).Magnitude
            end)
            if ok and dist < bestDist then
                best, bestDist = giver, dist
            end
        end
    end
    return best
end

function QuestController:isGiver(entry)
    return type(entry) == "table" and entry.prompt ~= nil
end

local function fireGiverPrompt(giver)
    local prompt = giver.prompt
    if not (prompt and prompt.Parent) then
        pcall(function()
            giver.prompt = giver.model:FindFirstChildWhichIsA("ProximityPrompt", true)
            prompt = giver.prompt
        end)
    end
    if not prompt then return false end
    local ok = pcall(function() prompt:FirePrompt() end)
    if ok then
        Logger:debug("Quest prompt fired: " .. tostring(giver.name))
    end
    return ok
end

function QuestController:approach(giver)
    local myRoot = Util.getRoot()
    if not (myRoot and giver.root and giver.root.Parent) then
        return false
    end

    local range = 8
    pcall(function()
        local maxDist = giver.prompt and giver.prompt.MaxActivationDistance
        if type(maxDist) == "number" and maxDist > 0 then
            range = math.max(4, math.min(12, maxDist - 0.5))
        end
    end)
    local dist
    local okD, d = pcall(function() return (giver.root.Position - myRoot.Position).Magnitude end)
    dist = okD and d or math.huge

    if dist <= range then
        if MovementController._active then
            MovementController:cancel("quest giver in range")
        end
        return fireGiverPrompt(giver)
    end

        if MovementController._active and MovementController._entry ~= giver then
        return false
    end

    if not MovementController._active or MovementController._entry ~= giver then
        giver.distance = dist
        MovementController:begin(giver)
    end
    local status = MovementController:tick(0.5)
    if status == "failed" then
        MovementController:cancel("quest walk failed")
        self._giverSkip[giver.name] = os.clock() + 20
        Logger:warn("Quest: walking to " .. tostring(giver.name) .. " failed — trying another giver")
    end
    return false
end

function QuestController:tick()
    if not self.enabled then return end

    if not Util.aliveLocal() then
        if self.state ~= "WaitingRespawn" then
            self.state = "WaitingRespawn"
            MovementController:cancel("quest: player defeated")
        end
        return
    end

        if State.automation.enabled and TargetManager.mode ~= "Quest" then
        if self.state ~= "Paused (automation active)" then
            self.state = "Paused (automation active)"
            Logger:debug("Quest loop paused — automation owns movement")
        end
        return
    end

    local now = os.clock()
    if now - self._uiScanAt > 5 then
        self._uiScanAt = now
        self:detectQuestUI(true)
        self:scanGivers(false)
    end

    local objective = self:readObjective()
    if objective ~= self._lastObjective and objective ~= "" then
        self._lastObjective = objective
        Logger:info("Quest objective: " .. objective)
    end
    self.objectiveText = objective

        if objective ~= "" and self.autoTurnIn
       and Util.matchAny(GameProfile.QUEST.completionPatterns, string.lower(objective)) then
        self.state = "TurningIn"
        if now >= self._nextFireAt then
            local giver = self:nearestGiver()
            if giver and self:approach(giver) then
                self._nextFireAt = now + 1.5
                Notify.toast("Quest", "Turn-in prompt fired")
            end
        end
        return
    end

        if objective == "" then
        if self.autoAccept and now >= self._nextFireAt then
            local giver = self:nearestGiver()
            if giver then
                self.state = "GoingToGiver"
                if self:approach(giver) then
                    self._nextFireAt = now + 2
                    self.state = "Active"
                end
            else
                if self.state ~= "NoQuest" then
                    self.state = "NoQuest"
                    Logger:debug("Quest: no givers found near you")
                end
            end
        else
            self.state = "NoQuest"
        end
        return
    end

            self.state = "Active"
end

function QuestController:start()
    if self.enabled then return end
    if not self.isAvailable() then
        Logger:warn("Quest loop locked — " .. (GameDetector.gameLockReason() or "GameProfile.QUEST disabled"))
        return false
    end
    self.enabled = true
    self.active = true
    self.state = "NoQuest"
    self._nextFireAt = 0
    self:scanGivers(true)
    self:detectQuestUI(true)
    self._loop = Tracker.loop("quest.tick", 0.5, function()
        QuestController:tick()
    end)
    Notify.notify("Quest loop enabled", string.format(
        "%d quest giver(s) detected", #self.givers))
    Logger:info(string.format("Quest loop enabled (%d givers, objective %s)",
        #self.givers, self.objectiveText ~= "" and "found" or "not found"))
    return true
end

function QuestController:stop()
    if self._loop then
        self._loop:Stop()
        self._loop = nil
    end
    local wasEnabled = self.enabled
    self.enabled = false
    self.active = false
    self.state = "Idle"
    if not State.automation.enabled then
        MovementController:cancel("quest stopped")
    end
    if wasEnabled then
        Logger:info("Quest loop disabled")
    end
end

function QuestController:setLoop(enabled)
    if enabled then
        local ok = self:start()
        return ok ~= false
    end
    self:stop()
    return true
end

function QuestController:detectCurrentQuest()
            local label, reason = self:detectQuestUI(true)
    if not label then
        return nil, reason
    end
    local text = self:readObjective()
    return { text = text, label = label }, nil
end

function QuestController:findQuestGivers()
        self:scanGivers(true)
    if #self.givers == 0 then
        return self.givers, "no quest givers detected (try standing near one)"
    end
    return self.givers, nil
end

function QuestController:Start()
    if self.isAvailable() then
        Logger:info("Quest controller ready (generic detection patterns)")
    else
        Logger:info("Quest controller dormant — game data pending release")
    end
end

function QuestController:Stop()
    self:stop()
end

function QuestController:Cleanup()
    self:stop()
    self.givers = {}
    self._objectiveLabel = nil
end

local ClanController = {}

ClanController.enabled      = false
ClanController.mode         = "Count"
ClanController.targetClan   = ""
ClanController.maxRerolls   = 10
ClanController.delay        = 1.5
ClanController.rerollCount  = 0
ClanController.currentClan  = ""
ClanController.state        = "Idle"

ClanController._loop        = nil
ClanController._nextRerollAt = 0
ClanController._rerollNpc   = nil
ClanController._npcScanAt   = 0

function ClanController.isAvailable()
    return GameDetector.shouldEnableGameFeatures()
        and GameProfile.CLAN.enabled == true
end

function ClanController:readCurrentClan()
    local names = GameProfile.CLAN.clanStatNames or {}

    local okS, stats = pcall(function()
        return LocalPlayer:FindFirstChild("leaderstats")
    end)
    if okS and stats then
        for _, statName in ipairs(names) do
            local okC, child = pcall(function()
                return stats:FindFirstChild(statName)
            end)
            if okC and child then
                local okV, value = pcall(function() return child.Value end)
                if okV and type(value) == "string" and Util.trim(value) ~= "" then
                    return Util.trim(value)
                end
            end
        end
    end

    for _, attrName in ipairs(names) do
        local okA, value = pcall(function()
            return LocalPlayer:GetAttribute(attrName)
        end)
        if okA and type(value) == "string" and Util.trim(value) ~= "" then
            return Util.trim(value)
        end
    end
    return ""
end

function ClanController:findRerollNPC()
    local profile = GameProfile.CLAN.reroll or {}
    local namePatterns = profile.npcNamePatterns or {}
    local promptPatterns = profile.promptPatterns or {}
    if #namePatterns == 0 and #promptPatterns == 0 then
        return nil
    end

    local now = os.clock()
    if now - self._npcScanAt < 5 and self._rerollNpc then
        local alive = false
        pcall(function()
            alive = self._rerollNpc.model.Parent ~= nil
        end)
        if alive then
            return self._rerollNpc
        end
    end
    self._npcScanAt = now

    local okC, children = pcall(function() return workspace:GetChildren() end)
    if not (okC and type(children) == "table") then
        return nil
    end

    for _, child in ipairs(children) do
        local isModel = false
        pcall(function() isModel = child:IsA("Model") end)
        if isModel then
            local matched = false
            pcall(function()
                matched = Util.matchAny(namePatterns, child.Name or "")
            end)
            if matched then
                local root = Util.findRootOf(child)
                local prompt
                pcall(function()
                    prompt = child:FindFirstChildWhichIsA("ProximityPrompt", true)
                end)
                if root and prompt then
                    local promptText = ""
                    pcall(function()
                        promptText = string.format(
                            "%s %s",
                            tostring(prompt.ActionText or ""),
                            tostring(prompt.ObjectText or "")
                        )
                    end)
                    if #promptPatterns == 0 or Util.matchAny(promptPatterns, promptText) then
                        local path = tostring(child.Name)
                        pcall(function() path = child:GetFullName() end)
                        self._rerollNpc = {
                            model = child,
                            name = child.Name,
                            root = root,
                            humanoid = nil,
                            prompt = prompt,
                            distance = math.huge,
                            path = path,
                        }
                        return self._rerollNpc
                    end
                end
            end
        end
    end
    self._rerollNpc = nil
    return nil
end

function ClanController:fireRemote()
    local profile = GameProfile.CLAN.reroll or {}
    local remoteName = profile.remoteName or ""
    if remoteName == "" then
        return false
    end
    local okS, storage = pcall(function()
        return game:GetService("ReplicatedStorage")
    end)
    if not (okS and storage) then
        return false
    end
    local okF, remote = pcall(function()
        return storage:FindFirstChild(remoteName, true)
    end)
    if not (okF and remote) then
        Logger:warn("Clan reroll remote not found: " .. remoteName)
        return false
    end
    local args = profile.remoteArgs or {}
    local ok = pcall(function()
        remote:FireServer(table.unpack(args))
    end)
    if ok then
        Logger:debug("Clan reroll remote fired: " .. remoteName)
    end
    return ok
end

function ClanController:performReroll()
    if (GameProfile.CLAN.reroll or {}).remoteName ~= "" then
        return self:fireRemote()
    end
    local npc = self:findRerollNPC()
    if not npc then
        return false
    end
    return QuestController:approach(npc) == true
end

function ClanController:rerollOnce()
    if not self.isAvailable() then
        return false, GameDetector.gameLockReason() or "Clan reroll unavailable"
    end
    if not Util.aliveLocal() then
        return false, "No character yet"
    end
    if (GameProfile.CLAN.reroll or {}).remoteName ~= "" then
        if self:fireRemote() then
            self.rerollCount = self.rerollCount + 1
            self.currentClan = self:readCurrentClan()
            return true
        end
        return false, "Reroll remote not found"
    end
    local npc = self:findRerollNPC()
    if not npc then
        return false, "No reroll NPC detected — patterns arrive with release data"
    end
    local myRoot = Util.getRoot()
    if not (myRoot and npc.root and npc.prompt) then
        return false, "Reroll NPC not reachable right now"
    end
    local range = 8
    pcall(function()
        local maxDist = npc.prompt.MaxActivationDistance
        if type(maxDist) == "number" and maxDist > 0 then
            range = math.max(4, math.min(12, maxDist - 0.5))
        end
    end)
    local dist
    local okD, d = pcall(function()
        return (npc.root.Position - myRoot.Position).Magnitude
    end)
    dist = okD and d or math.huge
    if dist > range then
        return false, "Too far from " .. tostring(npc.name) .. " (enable Auto Reroll to walk)"
    end
    local ok = pcall(function() npc.prompt:FirePrompt() end)
    if ok then
        self.rerollCount = self.rerollCount + 1
        self.currentClan = self:readCurrentClan()
        Logger:debug("Manual clan reroll fired (" .. self.rerollCount .. " total)")
        return true
    end
    return false, "Reroll prompt failed to fire"
end

function ClanController:_finish(finalState, title, content)
    self.state = finalState
    self.enabled = false
    if self._loop then
        self._loop:Stop()
        self._loop = nil
    end
    Notify.notify(title, content)
    Logger:info(title .. " — " .. content)
end

function ClanController:tick()
    if not self.enabled then return end

    if not self.isAvailable() then
        self.state = "AwaitingData"
        return
    end
    if not Util.aliveLocal() then
        if self.state ~= "WaitingRespawn" then
            self.state = "WaitingRespawn"
            MovementController:cancel("clan: player defeated")
        end
        return
    end

    local now = os.clock()
    if now < self._nextRerollAt then return end

    self.currentClan = self:readCurrentClan()
    if self.mode == "UntilTarget" and self.targetClan ~= "" and self.currentClan ~= "" then
        if self.currentClan:lower() == self.targetClan:lower() then
            self:_finish(
                "TargetReached",
                "Clan reroll done",
                string.format("Target clan reached: %s (%d reroll%s)",
                    self.currentClan, self.rerollCount,
                    self.rerollCount == 1 and "" or "s")
            )
            return
        end
    end
    if self.maxRerolls > 0 and self.rerollCount >= self.maxRerolls then
        self:_finish(
            "LimitReached",
            "Clan reroll stopped",
            string.format("Reroll limit reached (%d) — current clan: %s",
                self.maxRerolls,
                self.currentClan ~= "" and self.currentClan or "unknown")
        )
        return
    end

    self.state = "Rerolling"
    local ok = self:performReroll()
    self._nextRerollAt = now + math.max(0.2, self.delay)
    if ok then
        self.rerollCount = self.rerollCount + 1
        Logger:debug(string.format("Clan reroll %d fired (%s)",
            self.rerollCount, self.currentClan ~= "" and self.currentClan or "clan unreadable"))
    end
end

function ClanController:setEnabled(enabled)
    enabled = enabled and true or false
    if enabled == self.enabled then
        return true
    end

    if enabled then
        if not self.isAvailable() then
            local reason = GameDetector.gameLockReason() or "Clan data not configured"
            Logger:warn("Clan reroll locked: " .. reason)
            Notify.toast("Clan", "Locked — " .. reason)
            return false
        end
        self.enabled = true
        self.rerollCount = 0
        self.state = "Rerolling"
        self._nextRerollAt = 0
        self._rerollNpc = nil
        self.currentClan = self:readCurrentClan()
        self._loop = Tracker.loop("clan.tick", 0.5, function()
            ClanController:tick()
        end)
                                if not self.enabled and self._loop then
            self._loop:Stop()
            self._loop = nil
        end
        Notify.notify("Clan reroll enabled", "Mode: "
            .. (self.mode == "UntilTarget" and ("until " .. self.targetClan) or ("up to " .. self.maxRerolls)))
        Logger:info("Clan reroll loop enabled (mode " .. self.mode .. ")")
    else
        self.enabled = false
        if self._loop then
            self._loop:Stop()
            self._loop = nil
        end
        if not State.automation.enabled then
            MovementController:cancel("clan reroll stopped")
        end
        self.state = "Idle"
        Logger:info("Clan reroll loop disabled")
    end
    return true
end

function ClanController:stop()
    self:setEnabled(false)
end

function ClanController:Start()
    if self.isAvailable() then
        Logger:info("Clan controller ready (reroll paths configured)")
    else
        Logger:info("Clan controller dormant — awaiting the released game's instance data")
    end
end

function ClanController:Stop()
    self:stop()
end

function ClanController:Cleanup()
    self:stop()
    self._rerollNpc = nil
end

local ESPController = {}

ESPController.settings = {
    updateRate   = 0.1,
    maxDistance  = 2000,
}

ESPController.enabled      = false
ESPController.rendererMode = nil
ESPController.stats        = { total = 0, drawn = 0 }

ESPController._loop     = nil
ESPController._pool     = {}
ESPController._folder   = nil
ESPController._items    = {}
ESPController._itemScan = 0

local ITEM_COLOR = Color3.fromRGB(200, 200, 215)
local ITEM_SCAN_EVERY = 5
local ITEM_SCAN_CAP   = 3000

local function drawingAvailable()
    return type(Drawing) == "table" and type(Drawing.new) == "function"
end

local function espFolder()
    if ESPController._folder and ESPController._folder.Parent then
        return ESPController._folder
    end
    local folder
    pcall(function()
        folder = Instance.new("Folder")
        folder.Name = "PS2Hub_ESP"
        folder.Parent = game:GetService("CoreGui")
    end)
    if not (folder and folder.Parent) then
        pcall(function()
            folder = Instance.new("Folder")
            folder.Name = "PS2Hub_ESP"
            folder.Parent = workspace
        end)
    end
    ESPController._folder = folder
    return folder
end

local function dset(obj, key, value)
    if obj then
        pcall(function() obj[key] = value end)
    end
end

local function newDrawing(kind)
    local ok, obj = pcall(function() return Drawing.new(kind) end)
    if ok and obj then
        return obj
    end
    return nil
end

local function removeDrawing(obj)
    if obj then
        pcall(function() obj:Remove() end)
    end
end

local function removeInstance(obj)
    if obj then
        pcall(function() obj:Destroy() end)
    end
end

local function colorFor(entry)
    local colors = State.esp.colors or {}
    if entry.isPlayer then
        return colors.Players or Color3.fromRGB(80, 200, 120)
    end
    if entry.category == "Bosses" or entry.category == "Boss" then
        return colors.Bosses or Color3.fromRGB(230, 70, 70)
    end
    if entry.category == "Items" then
        return ITEM_COLOR
    end
    return colors.NPCs or Color3.fromRGB(255, 170, 60)
end

local function healthColor(ratio)
    ratio = Util.clamp(ratio, 0, 1)
    local r, g
    if ratio >= 0.5 then
        local t = (ratio - 0.5) * 2
        r = 255 - 175 * t
        g = 220
    else
        local t = ratio * 2
        r = 255
        g = 60 + 160 * t
    end
    return Color3.fromRGB(math.floor(r + 0.5), math.floor(g + 0.5), 60)
end

local function modelExtent(entry)
    local center, sizeY
    if entry.model and entry.model:IsA("Model") then
        local ok, cf, size = pcall(function() return entry.model:GetBoundingBox() end)
        if ok and cf then
            center = cf.Position
            sizeY = math.max(size.Y, 2)
        end
    end
    if not center then
        local ok, pos = pcall(function() return entry.root.Position end)
        if not ok then return nil, nil end
        center = pos
        sizeY = 5
    end
    return center, sizeY
end

local function textFor(entry, dist, display)
    local parts = {}
    if display.name then
        table.insert(parts, tostring(entry.name))
    end
    if display.distance then
        table.insert(parts, string.format("%dm", math.floor(dist)))
    end
    if display.health and entry.humanoid then
        pcall(function()
            table.insert(parts, string.format("%d/%d",
                math.floor(entry.humanoid.Health),
                math.floor(entry.humanoid.MaxHealth)))
        end)
    end
    return table.concat(parts, " · ")
end

local function newRecord()
    return {
        boxOutline = nil, box = nil, healthBg = nil, healthFill = nil,
        tracer = nil, text = nil,
        highlight = nil, bbGui = nil, bbLabel = nil,
    }
end

local function destroyRecord(rec)
    if not rec then return end
    removeDrawing(rec.boxOutline)
    removeDrawing(rec.box)
    removeDrawing(rec.healthBg)
    removeDrawing(rec.healthFill)
    removeDrawing(rec.tracer)
    removeDrawing(rec.text)
    removeInstance(rec.highlight)
    removeInstance(rec.bbGui)
end

local function hideRecord(rec)
    dset(rec.boxOutline, "Visible", false)
    dset(rec.box, "Visible", false)
    dset(rec.healthBg, "Visible", false)
    dset(rec.healthFill, "Visible", false)
    dset(rec.tracer, "Visible", false)
    dset(rec.text, "Visible", false)
    dset(rec.highlight, "Enabled", false)
    dset(rec.bbGui, "Enabled", false)
end

local function ensureHighlight(rec, entry, display)
    if not display.highlight then
        if rec.highlight then
            removeInstance(rec.highlight)
            rec.highlight = nil
        end
        return
    end
    if not rec.highlight then
        local ok, hl = pcall(function()
            local h = Instance.new("Highlight")
            h.Name = "PS2Hub_ESP"
            h.FillTransparency = 0.6
            h.OutlineTransparency = 0
            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            h.Adornee = entry.model
            h.Parent = espFolder()
            return h
        end)
        if ok then
            rec.highlight = hl
        end
    end
    if rec.highlight then
        dset(rec.highlight, "FillColor", colorFor(entry))
        dset(rec.highlight, "Enabled", true)
    end
end

local function ensureBillboard(rec, entry, center, sizeY, dist, settings, display)
    local wantText = display.name or display.distance or display.health
    if not wantText then
        if rec.bbGui then
            removeInstance(rec.bbGui)
            rec.bbGui, rec.bbLabel = nil, nil
        end
        return
    end
    if not rec.bbGui then
        local ok, gui, label = pcall(function()
            local bb = Instance.new("BillboardGui")
            bb.Name = "PS2Hub_ESP"
            bb.Size = UDim2.new(0, 220, 0, 60)
            bb.StudsOffsetWorldSpace = Vector3.new(0, sizeY / 2 + 1.5, 0)
            bb.AlwaysOnTop = true
            bb.MaxDistance = settings.maxDistance
            bb.Adornee = entry.root
            bb.Parent = espFolder()

            local tl = Instance.new("TextLabel")
            tl.BackgroundTransparency = 1
            tl.Size = UDim2.new(1, 0, 1, 0)
            tl.TextColor3 = colorFor(entry)
            tl.TextStrokeTransparency = 0.4
            tl.TextSize = 13
            tl.Font = Enum.Font.Code
            tl.Text = ""
            tl.Parent = bb
            return bb, tl
        end)
        if ok and gui then
            rec.bbGui, rec.bbLabel = gui, label
        end
    end
    if rec.bbGui then
        dset(rec.bbGui, "MaxDistance", settings.maxDistance)
        dset(rec.bbLabel, "Text", textFor(entry, dist, display))
        dset(rec.bbLabel, "TextColor3", colorFor(entry))
        dset(rec.bbGui, "Enabled", true)
    end
end

local function draw2D(rec, entry, camera, viewport, dist, settings, display)
    local center, sizeY = modelExtent(entry)
    if not center then
        hideRecord(rec)
        return
    end

    local okT, top2, onT = pcall(function()
        return camera:WorldToViewportPoint(center + Vector3.new(0, sizeY / 2 + 0.4, 0))
    end)
    local okB, bot2, onB = pcall(function()
        return camera:WorldToViewportPoint(center - Vector3.new(0, sizeY / 2 + 0.4, 0))
    end)
    if not (okT and okB and top2 and bot2) then
        hideRecord(rec)
        return
    end
    if not (onT or onB) then
        hideRecord(rec)
        return
    end

    local h = math.abs(top2.Y - bot2.Y)
    local w = math.max(h * 0.55, 10)
    local cx = (top2.X + bot2.X) / 2
    local cy = (top2.Y + bot2.Y) / 2
    local color = colorFor(entry)

        if display.box then
        if not rec.box then
            rec.boxOutline = newDrawing("Square")
            rec.box = newDrawing("Square")
            dset(rec.boxOutline, "Color", Color3.new(0, 0, 0))
            dset(rec.box, "Thickness", 1)
        end
        dset(rec.boxOutline, "Thickness", 2)
        dset(rec.boxOutline, "Filled", false)
        dset(rec.boxOutline, "Position", Vector2.new(cx - w / 2 - 1, cy - h / 2 - 1))
        dset(rec.boxOutline, "Size", Vector2.new(w + 2, h + 2))
        dset(rec.boxOutline, "Visible", true)
        dset(rec.box, "Color", color)
        dset(rec.box, "Filled", false)
        dset(rec.box, "Position", Vector2.new(cx - w / 2, cy - h / 2))
        dset(rec.box, "Size", Vector2.new(w, h))
        dset(rec.box, "Visible", true)
    else
        dset(rec.boxOutline, "Visible", false)
        dset(rec.box, "Visible", false)
    end

        local ratio
    if entry.humanoid then
        pcall(function()
            ratio = entry.humanoid.MaxHealth > 0
                and entry.humanoid.Health / entry.humanoid.MaxHealth
                or 0
        end)
    end
    if display.health and ratio then
        ratio = Util.clamp(ratio, 0, 1)
        if not rec.healthBg then
            rec.healthBg = newDrawing("Square")
            rec.healthFill = newDrawing("Square")
            dset(rec.healthBg, "Color", Color3.new(0, 0, 0))
            dset(rec.healthBg, "Filled", true)
            dset(rec.healthFill, "Filled", true)
        end
        local bx = cx + w / 2 + 3
        local fillH = h * ratio
        dset(rec.healthBg, "Position", Vector2.new(bx, cy - h / 2))
        dset(rec.healthBg, "Size", Vector2.new(3, h))
        dset(rec.healthBg, "Visible", true)
        dset(rec.healthFill, "Color", healthColor(ratio))
        dset(rec.healthFill, "Position", Vector2.new(bx, cy + h / 2 - fillH))
        dset(rec.healthFill, "Size", Vector2.new(3, fillH))
        dset(rec.healthFill, "Visible", true)
    else
        dset(rec.healthBg, "Visible", false)
        dset(rec.healthFill, "Visible", false)
    end

        if display.tracer and viewport then
        if not rec.tracer then
            rec.tracer = newDrawing("Line")
        end
        dset(rec.tracer, "Color", color)
        dset(rec.tracer, "Thickness", 1)
        dset(rec.tracer, "From", Vector2.new(viewport.X / 2, viewport.Y))
        dset(rec.tracer, "To", Vector2.new(cx, cy + h / 2))
        dset(rec.tracer, "Visible", true)
    else
        dset(rec.tracer, "Visible", false)
    end

        local label = textFor(entry, dist, display)
    if label ~= "" then
        if not rec.text then
            rec.text = newDrawing("Text")
            dset(rec.text, "Size", 13)
            dset(rec.text, "Center", true)
            dset(rec.text, "Outline", true)
            dset(rec.text, "OutlineColor", Color3.new(0, 0, 0))
        end
        dset(rec.text, "Text", label)
        dset(rec.text, "Color", color)
        dset(rec.text, "Position", Vector2.new(cx, cy - h / 2 - 18))
        dset(rec.text, "Visible", true)
    else
        dset(rec.text, "Visible", false)
    end
end

local function looksLikeItem(inst)
    local name = inst.Name or ""
    if Util.matchAny(GameProfile.ITEMS.namePatterns, name) then
        return true
    end
    for _, tag in ipairs(GameProfile.ITEMS.tags or {}) do
        local has = false
        pcall(function() has = CollectionService:HasTag(inst, tag) end)
        if has then return true end
    end
    return false
end

local function addItemRecord(items, seen, inst)
    if seen[inst] then return end
    local ok, alive = pcall(function() return inst.Parent ~= nil end)
    if not ok or not alive then return end
    local root
    if inst:IsA("BasePart") then
        root = inst
    elseif inst:IsA("Model") then
        root = Util.findRootOf(inst)
    end
    if not root then return end
    seen[inst] = true
    table.insert(items, {
        model = inst,
        name = inst.Name,
        root = root,
        humanoid = nil,
        category = "Items",
        isPlayer = false,
    })
end

local function refreshItems()
    local items = {}
    local seen = {}

    for _, tag in ipairs(GameProfile.ITEMS.tags or {}) do
        local ok, tagged = pcall(function() return CollectionService:GetTagged(tag) end)
        if ok and type(tagged) == "table" then
            for _, inst in ipairs(tagged) do
                addItemRecord(items, seen, inst)
            end
        end
    end

    local scanned = 0
    local okC, children = pcall(function() return workspace:GetChildren() end)
    if okC and type(children) == "table" then
        for _, child in ipairs(children) do
            local okD, kids = pcall(function() return child:GetChildren() end)
            if okD and type(kids) == "table" then
                for _, inst in ipairs(kids) do
                    scanned = scanned + 1
                    if scanned > ITEM_SCAN_CAP then break end
                    if looksLikeItem(inst) then
                        addItemRecord(items, seen, inst)
                    end
                end
            end
            if scanned > ITEM_SCAN_CAP then break end
        end
    end

    ESPController._items = items
end

function ESPController:collectEntries()
    local entries = {}
    local enabledCats = State.esp.categories or {}

    if enabledCats.Players then
        for _, player in ipairs(Players:GetPlayers()) do
            if player ~= LocalPlayer and player.Character then
                local root = player.Character:FindFirstChild("HumanoidRootPart")
                local hum = player.Character:FindFirstChildOfClass("Humanoid")
                if root and hum then
                    table.insert(entries, {
                        model = player.Character,
                        name = player.Name,
                        root = root,
                        humanoid = hum,
                        category = "Players",
                        isPlayer = true,
                    })
                end
            end
        end
    end

    if enabledCats.NPCs or enabledCats.Bosses then
        for _, entry in ipairs(DiscoveryController.cache) do
            local cat = entry.category
            if cat == "Boss" and enabledCats.Bosses then
                table.insert(entries, {
                    model = entry.model, name = entry.name, root = entry.root,
                    humanoid = entry.humanoid, category = "Bosses", isPlayer = false,
                })
            elseif cat == "NPC" and enabledCats.NPCs then
                table.insert(entries, {
                    model = entry.model, name = entry.name, root = entry.root,
                    humanoid = entry.humanoid, category = "NPCs", isPlayer = false,
                })
            end
        end
    end

    if enabledCats.QuestNPCs then
        for _, giver in ipairs(QuestController.givers) do
            local alive = false
            pcall(function()
                alive = giver.model.Parent ~= nil and giver.root.Parent ~= nil
            end)
            if alive then
                table.insert(entries, {
                    model = giver.model, name = giver.name, root = giver.root,
                    humanoid = giver.humanoid, category = "QuestNPCs", isPlayer = false,
                })
            end
        end
    end

    if enabledCats.Items then
        for _, item in ipairs(self._items) do
            local alive = false
            pcall(function() alive = item.root.Parent ~= nil end)
            if alive then
                table.insert(entries, item)
            end
        end
    end

    return entries
end

function ESPController:drawFrame()
    local camera = workspace.CurrentCamera
    if not camera then return end

    if (State.esp.categories or {}).Items then
        self._itemScan = self._itemScan + 1
        if self._itemScan >= ITEM_SCAN_EVERY then
            self._itemScan = 0
            refreshItems()
        end
    end

    local settings = self.settings
    local display = State.esp.display or {}
    local entries = self:collectEntries()
    local pool = self._pool
    local active = {}
    local drawn = 0

    local viewport
    local okV, vp = pcall(function() return camera.ViewportSize end)
    if okV then viewport = vp end
    local camPos
    local okC, cp = pcall(function() return camera.CFrame.Position end)
    if okC then camPos = cp end

    for _, entry in ipairs(entries) do
        local okAlive, alive = pcall(function()
            return entry.model.Parent ~= nil and entry.root.Parent ~= nil
        end)
        if not (okAlive and alive) then
            continue
        end
        local okPos, pos = pcall(function() return entry.root.Position end)
        if not okPos then
            continue
        end
        local dist = camPos and (pos - camPos).Magnitude or 0
        if dist > settings.maxDistance then
            continue
        end

        local rec = pool[entry.model]
        if not rec then
            rec = newRecord()
            pool[entry.model] = rec
        end
        active[entry.model] = true

        if self.rendererMode == "drawing" then
            draw2D(rec, entry, camera, viewport, dist, settings, display)
        else
            local center, sizeY = modelExtent(entry)
            ensureBillboard(rec, entry, center, sizeY, dist, settings, display)
        end
        ensureHighlight(rec, entry, display)
        drawn = drawn + 1
    end

    for model, rec in pairs(pool) do
        if not active[model] then
            destroyRecord(rec)
            pool[model] = nil
        end
    end

    self.stats.total = #entries
    self.stats.drawn = drawn
end

function ESPController:setEnabled(enabled)
    enabled = enabled and true or false
    if enabled == self.enabled then
        return true
    end

    if enabled then
        self.rendererMode = drawingAvailable() and "drawing" or "highlight"
        self._pool = {}
        self._items = {}
        self._itemScan = 0
        self.enabled = true
        State.esp.enabled = true
        self._loop = Tracker.loop("esp.update", function()
            return State.intervals.espUpdate
        end, function()
            if not ESPController.enabled then return end
            local ok, err = pcall(function()
                ESPController:drawFrame()
            end)
            if not ok then
                Logger:errorOnce("ESP frame error: " .. tostring(err))
            end
        end)
        Notify.notify("ESP enabled", "Renderer: " .. self.rendererMode)
        Logger:info("ESP enabled — renderer " .. self.rendererMode)
    else
        if self._loop then
            self._loop:Stop()
            self._loop = nil
        end
        for _, rec in pairs(self._pool) do
            destroyRecord(rec)
        end
        self._pool = {}
        self._items = {}
        removeInstance(self._folder)
        self._folder = nil
        self.enabled = false
        self.rendererMode = nil
        State.esp.enabled = false
        self.stats = { total = 0, drawn = 0 }
        Logger:info("ESP disabled — every object removed")
    end
    return true
end

function ESPController:Stop()
    self:setEnabled(false)
end

function ESPController:Cleanup()
    self:setEnabled(false)
end

State.esp.categories = {
    Players   = false,
    NPCs      = false,
    Bosses    = false,
    QuestNPCs = false,
    Items     = false,
}

State.esp.display = {
    name      = true,
    distance  = true,
    health    = true,
    box       = true,
    tracer    = true,
    highlight = true,
}

State.esp.colors = {
    Players = Color3.fromRGB(80, 200, 120),
    NPCs    = Color3.fromRGB(255, 170, 60),
    Bosses  = Color3.fromRGB(230, 70, 70),
}

local HomeStats = {}

HomeStats.handles   = {}
HomeStats.texts     = {}
HomeStats.progress  = nil
HomeStats._loop     = nil
HomeStats._last     = {}

HomeStats._fpsAvg    = 60
HomeStats._perfScale = 1

local function readLeaderstats()
    local out = {}
    local stats = LocalPlayer:FindFirstChild("leaderstats")
    if not stats then return out end
    for _, child in ipairs(stats:GetChildren()) do
        if child:IsA("IntValue") or child:IsA("NumberValue") then
            table.insert(out, { name = child.Name, value = child.Value })
        end
    end
    return out
end

local function findPlayerData()
    local level, currency
    local stats = readLeaderstats()
    for _, entry in ipairs(stats) do
        local lower = entry.name:lower()
        if not currency and Util.matchAny(GameProfile.PLAYER_DATA.currencyNames, lower) then
            currency = entry
        elseif not level and Util.matchAny(GameProfile.PLAYER_DATA.levelNames, lower) then
            level = entry
        end
    end
        if not currency and #stats > 0 then currency = stats[1] end
    if not level and #stats > 1 then level = stats[2] end
    return level, currency
end

local BASE_INTERVALS = nil

local function applyPerfScale(scale)
    if HomeStats._perfScale == scale then return end
    HomeStats._perfScale = scale
    if not BASE_INTERVALS then
        BASE_INTERVALS = Util.copy(State.intervals)
    end
    for key, base in pairs(BASE_INTERVALS) do
        State.intervals[key] = base * scale
    end
    Logger:info(string.format("Performance: intervals x%.0f (fps %.0f)", scale, HomeStats._fpsAvg))
end

local function tickPerformance()
    local ok, fps = pcall(function() return workspace:GetRealisticFPS() end)
    if not (ok and type(fps) == "number") then return end
        HomeStats._fpsAvg = HomeStats._fpsAvg * 0.9 + fps * 0.1
    if not State.settings.autoPerformance then
        applyPerfScale(1)
        return
    end
    local avg = HomeStats._fpsAvg
    if avg < 25 then
        applyPerfScale(3)
    elseif avg < 40 then
        applyPerfScale(2)
    elseif avg > 55 then
        applyPerfScale(1)
    end
end

local function setStat(name, value)
    local handle = HomeStats.handles[name]
    if not handle then return end
    if HomeStats._last[name] == value then return end
    HomeStats._last[name] = value
    pcall(function() handle:Set(value) end)
end

local function setText(name, text)
    local handle = HomeStats.texts[name]
    if not handle then return end
    if HomeStats._last[name] == text then return end
    HomeStats._last[name] = text
    pcall(function() handle:Set(text) end)
end

local function setProgress(mode, value)
    local handle = HomeStats.progress
    if not handle then return end
    if mode == "indeterminate" then
        if HomeStats._last._progIndet then return end
        HomeStats._last._progIndet = true
        HomeStats._last._progVal = nil
        pcall(function() handle:SetIndeterminate(true) end)
        return
    end
    HomeStats._last._progIndet = nil
    if HomeStats._last._progVal == value then return end
    HomeStats._last._progVal = value
        pcall(function() handle:Set(value) end)
end

local function tickHome()
    tickPerformance()

    local info = ServerController:getInfo()
    setStat("players", info.players)
    setStat("ping", info.ping or 0)
    setStat("kills", State.automation.kills)
    setStat("targets", #DiscoveryController.cache)

        local gameSuffix = ""
    if not State.gameVerified then
        gameSuffix = " (unverified)"
    elseif not GameProfile.DATA_READY then
        gameSuffix = " (game data pending release)"
    end
    setText("game", string.format(
        "%s%s  ·  PlaceId %d",
        game.Name or "?",
        gameSuffix,
        game.PlaceId
    ))
    local level, currency = findPlayerData()
    local playerLine = LocalPlayer.Name
    if level then
        playerLine = playerLine .. string.format("  ·  %s: %s", level.name, Util.formatInt(level.value))
    end
    if currency then
        playerLine = playerLine .. string.format("  ·  %s: %s", currency.name, Util.formatInt(currency.value))
    end
    setText("player", playerLine)

        local auto = State.automation
    local target = auto.target
    local taskLine
    if not auto.enabled then
        taskLine = "Idle — automation off"
    else
        taskLine = auto.taskState or "…"
    end
    if target then
        taskLine = taskLine .. string.format("  ·  Target: %s", target.name)
    end
        if QuestController.active and not auto.enabled then
        taskLine = "Quest: " .. (QuestController.state or "…")
        if QuestController.objectiveText ~= "" then
            taskLine = taskLine .. "  ·  " .. QuestController.objectiveText
        end
    end
        if ClanController.enabled and not auto.enabled then
        taskLine = string.format("Clan: %s  ·  %d reroll(s)",
            ClanController.state or "…", ClanController.rerollCount)
        if ClanController.currentClan ~= "" then
            taskLine = taskLine .. "  ·  " .. ClanController.currentClan
        end
    end
    setText("task", taskLine)

        if target and target.humanoid and target.humanoid.Parent then
        local maxHealth = math.max(1, target.humanoid.MaxHealth)
        setProgress("value", Util.round(target.humanoid.Health / maxHealth * 100, 1))
    elseif auto.enabled then
        setProgress("indeterminate")
    else
        setProgress("value", 0)
    end
end

function HomeStats:Start()
    self._loop = Tracker.loop("home.stats", function() return State.intervals.homeStats end, function()
        tickHome()
    end)
end

function HomeStats:Stop()
    if self._loop then
        self._loop:Stop()
        self._loop = nil
    end
end

function HomeStats:Cleanup()
    self:Stop()
    self.handles = {}
    self.texts = {}
    self.progress = nil
end

local ConfigController = {}

ConfigController._dropdown = nil
ConfigController._input    = nil

function ConfigController:bind(dropdown, input)
    self._dropdown = dropdown
    self._input = input
    self:refresh()
end

function ConfigController:list()
    local ok, list = pcall(function() return State.window:ListConfigs() end)
    if ok and type(list) == "table" then
        return list
    end
    return {}
end

function ConfigController:refresh()
    if not self._dropdown then return end
    local list = self:list()
    local ok = pcall(function()
        self._dropdown:Refresh(list)
    end)
    if ok then
        Logger:debug(string.format("Config list refreshed (%d saved)", #list))
    end
end

function ConfigController:name()
    if self._input then
        return Util.trim(self._input.value or "")
    end
    return ""
end

function ConfigController:save()
    local name = self:name()
    if name == "" then
        Notify.toast("Config", "Enter a name first")
        return
    end
    local ok = pcall(function() State.window:Save(name) end)
    if ok then
        Notify.notify("Configuration saved", name)
        Logger:info("Configuration saved: " .. name)
        self:refresh()
    else
        Notify.error("Config save", "save failed")
    end
end

function ConfigController:load(name)
    name = name or self:name()
    if name == "" then
        Notify.toast("Config", "Enter or select a name first")
        return
    end
    local ok = pcall(function() State.window:Load(name) end)
    if ok then
        Notify.notify("Configuration loaded", name .. " — features updated")
        Logger:info("Configuration loaded: " .. name)
                if self._input then
            self._input:Set(name, true)
        end
    else
        Notify.error("Config load", "load failed (missing?)")
    end
end

function ConfigController:delete(name)
    name = name or self:name()
    if name == "" then
        Notify.toast("Config", "Enter or select a name first")
        return
    end
        State.window:Popup({
        title = "Delete configuration?",
        content = "This permanently removes the saved configuration \"" .. name .. "\".",
        options = {
            { text = "Cancel" },
            {
                text = "Delete",
                style = "danger",
                callback = function()
                    local ok = pcall(function() State.window:DeleteConfig(name) end)
                    if ok then
                        Notify.toast("Config deleted", name)
                        Logger:info("Configuration deleted: " .. name)
                        ConfigController:refresh()
                    end
                end,
            },
        },
    })
end

function ConfigController:tryAutoLoad()
    if not State.settings.autoLoadConfig then return end
    local lastName = self:name()
    if lastName == "" then return end
    local list = self:list()
    local found = false
    for _, name in ipairs(list) do
        if name == lastName then
            found = true
            break
        end
    end
    if not found then
        Logger:debug("Auto-load: last config not found (" .. lastName .. ")")
        return
    end
    Tracker.delay("config.autoLoad", 1.0, function()
        ConfigController:load(lastName)
    end)
end

function ConfigController:Cleanup()
    self._dropdown = nil
    self._input = nil
end

local UI = {}

local Elements = {}

local function syncAutomationToggle(value)
    if Elements.autoMaster then
        pcall(function() Elements.autoMaster:Set(value and true or false, true) end)
    end
end

local function buildHome(window)
    local tab = window:CreateTab({ name = "Home" })

    tab:CreateSection({ name = "Session" })

    Elements.homeGame = tab:CreateText({
        name = "Current Game",
        text = "Detecting…",
    })
    Elements.homePlayer = tab:CreateText({
        name = "Player",
        text = LocalPlayer.Name,
    })

    local statusLine = "v" .. VERSION .. " · universal mode (GameProfile not set)"
    if State.gameVerified then
        if GameProfile.DATA_READY then
            statusLine = "v" .. VERSION .. " · PS2 verified — game features active"
        else
            statusLine = "v" .. VERSION .. " · PS2 detected — data pending, game features locked"
        end
    elseif GameProfile.CONFIGURED then
        statusLine = "v" .. VERSION .. " · wrong game — universal features only"
    end
    tab:CreateText({
        name = "Status",
        text = statusLine,
    })

    local grid = tab:CreateGroup()
    local left = grid:CreateGroup({ direction = "column" })
    local right = grid:CreateGroup({ direction = "column" })

    Elements.statPlayers = left:CreateStat({ name = "Server Players", value = 0 })
    Elements.statPing = left:CreateStat({ name = "Ping", value = 0, suffix = " ms" })
    Elements.statTargets = right:CreateStat({ name = "Targets Found", value = 0 })
    Elements.statKills = right:CreateStat({ name = "Kills", value = 0 })

    tab:CreateSection({ name = "Activity" })

    Elements.homeTask = tab:CreateText({
        name = "Task",
        text = "Idle — automation off",
    })
    Elements.homeProgress = tab:CreateProgress({
        name = "Target Health",
        range = { 0, 100 },
        value = 0,
    })

    return tab
end

local function buildUniversal(window)
    local tab = window:CreateTab({ name = "Universal" })

    tab:CreateSection({ name = "Movement" })

    local moveRow = tab:CreateGroup()
    moveRow:CreateToggle({
        name = "Walk Speed",
        flag = "Univ_WalkSpeed_Enabled",
        callback = function(value)
            CharacterController:setWalkEnabled(value)
        end,
    })
    local flyToggle = moveRow:CreateToggle({
        name = "Fly",
        flag = "Univ_Fly_Enabled",
        callback = function(value)
            CharacterController:setFlyEnabled(value)
        end,
    })
    local noclipToggle = moveRow:CreateToggle({
        name = "Noclip",
        flag = "Univ_Noclip",
        callback = function(value)
            CharacterController:setNoclip(value)
        end,
    })

    local speedRow = tab:CreateGroup()
    speedRow:CreateSlider({
        name = "Speed",
        range = { 16, 500 },
        increment = 1,
        value = 16,
        suffix = " sps",
        flag = "Univ_WalkSpeed_Value",
        callback = function(value)
            CharacterController:setWalkSpeed(value)
        end,
    })
    speedRow:CreateSlider({
        name = "Fly Speed",
        range = { 1, 500 },
        value = 60,
        suffix = " sps",
        flag = "Univ_Fly_Speed",
        callback = function(value)
            CharacterController:setFlySpeed(value)
        end,
    })

    tab:CreateDropdown({
        name = "Walk Speed Method",
        options = { "Auto", "Humanoid (Property)", "Velocity (Physics)" },
        value = "Auto",
        description = "Auto probes the property and falls back if the game enforces it",
        flag = "Univ_WalkSpeed_Method",
        callback = function(option)
            if option == "Humanoid (Property)" then
                CharacterController:setWalkMethod("Humanoid")
            elseif option == "Velocity (Physics)" then
                CharacterController:setWalkMethod("Velocity")
            else
                CharacterController:setWalkMethod("Auto")
            end
        end,
    })
    tab:CreateDropdown({
        name = "Fly Method",
        options = { "Auto", "CFrame", "BodyVelocity", "LinearVelocity" },
        value = "Auto",
        description = "Auto verifies airtime and falls back through the methods",
        flag = "Univ_Fly_Method",
        callback = function(option)
            CharacterController:setFlyMethod(option)
        end,
    })
    tab:CreateKeybind({
        name = "Fly Key",
        description = "WASD to move, E/Q or Space/LeftControl for vertical",
        value = Enum.KeyCode.F,
        flag = "Univ_Fly_Key",
        callback = function()
            local newValue = not CharacterController.fly.enabled
            CharacterController:setFlyEnabled(newValue)
            if flyToggle then
                flyToggle:Set(newValue, true)
            end
        end,
    })
    tab:CreateKeybind({
        name = "Noclip Key",
        value = Enum.KeyCode.N,
        flag = "Univ_Noclip_Key",
        callback = function()
            local newValue = not CharacterController.flags.noclip
            CharacterController:setNoclip(newValue)
            if noclipToggle then
                noclipToggle:Set(newValue, true)
            end
        end,
    })

        Elements.activeMethods = tab:CreateText({
        name = "Active Methods",
        text = "Walk: — · Fly: —",
    })
    local function refreshMethodsText()
        if not Elements.activeMethods then return end
        pcall(function()
            Elements.activeMethods:Set(string.format(
                "Walk: %s · Fly: %s",
                State.character.walkResolved or "—",
                State.character.flyResolved or "—"
            ))
        end)
    end
    CharacterController.onMethodChanged:Connect(refreshMethodsText)
    refreshMethodsText()

    tab:CreateSection({ name = "Jumping" })

    local jumpRow = tab:CreateGroup()
    jumpRow:CreateToggle({
        name = "Modify Jump",
        description = "Applies the mode the game's Humanoid actually uses (auto-detected)",
        flag = "Univ_Jump_Enabled",
        callback = function(value)
            CharacterController:setJumpEnabled(value)
        end,
    })
    jumpRow:CreateToggle({
        name = "Infinite Jump",
        flag = "Univ_InfJump",
        callback = function(value)
            CharacterController:setInfiniteJump(value)
        end,
    })

    local jumpSliders = tab:CreateGroup()
    jumpSliders:CreateSlider({
        name = "JumpPower",
        range = { 1, 500 },
        value = 50,
        flag = "Univ_JumpPower",
        callback = function(value)
            CharacterController:setJumpPower(value)
        end,
    })
    jumpSliders:CreateSlider({
        name = "JumpHeight",
        range = { 1, 100 },
        increment = 0.5,
        value = 7.5,
        suffix = " studs",
        flag = "Univ_JumpHeight",
        callback = function(value)
            CharacterController:setJumpHeight(value)
        end,
    })

    tab:CreateSection({ name = "Character & Camera" })

    tab:CreateToggle({
        name = "Anti-AFK",
        description = "Fakes controller input when Roblox marks you idle",
        flag = "Univ_AntiAFK",
        callback = function(value)
            CharacterController:setAntiAFK(value)
        end,
    })
    Elements.fovSlider = tab:CreateSlider({
        name = "Field of View",
        range = { 30, 120 },
        value = 70,
        suffix = "°",
        description = "Commits when you release the slider",
        flag = "Univ_Camera_FOV",
        callback = function(value, dragging)
            if dragging then return end
            CharacterController:setFOV(value)
        end,
    })
    local utilRow = tab:CreateGroup()
    utilRow:CreateButton({
        name = "Reset Character",
        callback = function()
            CharacterController:resetCharacter()
        end,
    })
    utilRow:CreateButton({
        name = "Reset FOV",
        callback = function()
            CharacterController:resetFOV()
            if Elements.fovSlider then
                Elements.fovSlider:Set(70, true)
            end
        end,
    })

    tab:CreateSection({ name = "Players" })

    Elements.playerDropdown = tab:CreateDropdown({
        name = "Select Player",
        options = PlayerController.getPlayerNames(),
        placeholder = "None",
        description = "Type to search — refreshes on join/leave",
        forgetState = true,
    })

    local tpRow = tab:CreateGroup()
    tpRow:CreateButton({
        name = "Teleport To",
        callback = function()
            local name = UIState.dropdownFirst(Elements.playerDropdown)
            if name then PlayerController:teleportTo(name, "to") end
        end,
    })
    tpRow:CreateButton({
        name = "Behind",
        callback = function()
            local name = UIState.dropdownFirst(Elements.playerDropdown)
            if name then PlayerController:teleportTo(name, "behind") end
        end,
    })
    tpRow:CreateButton({
        name = "Above",
        callback = function()
            local name = UIState.dropdownFirst(Elements.playerDropdown)
            if name then PlayerController:teleportTo(name, "above") end
        end,
    })

    local viewRow = tab:CreateGroup()
    viewRow:CreateButton({
        name = "Spectate",
        callback = function()
            local name = UIState.dropdownFirst(Elements.playerDropdown)
            if name then PlayerController:spectate(name) end
        end,
    })
    viewRow:CreateButton({
        name = "Stop Spectate",
        callback = function()
            PlayerController:stopSpectate()
        end,
    })
    viewRow:CreateButton({
        name = "Refresh List",
        callback = function()
            PlayerController:refreshList()
        end,
    })

    return tab
end

local function buildServer(window)
    local tab = window:CreateTab({ name = "Server" })

    tab:CreateSection({ name = "Server Actions" })

    local actionsRow = tab:CreateGroup()
    actionsRow:CreateButton({
        name = "Rejoin",
        callback = function()
            ServerController:rejoin()
        end,
    })
    actionsRow:CreateButton({
        name = "Server Hop",
        description = "Skips servers you already visited this session",
        callback = function()
            ServerController:hop("any")
        end,
    })
    actionsRow:CreateButton({
        name = "Low Hop",
        description = "Only servers at or below the player filter",
        callback = function()
            ServerController:hop("low", UIState.lowHopMax())
        end,
    })

    tab:CreateSection({ name = "Filters" })

    tab:CreateDropdown({
        name = "Maximum Players",
        options = { "1", "2", "3", "4", "5", "6", "Custom" },
        value = "3",
        description = "Low Hop only accepts servers at or below this count",
        flag = "Server_LowMax",
        callback = function(option)
            UIState.lowHopMode = option
        end,
    })
    tab:CreateInput({
        name = "Custom Maximum Players",
        numeric = true,
        value = "8",
        placeholder = "Enter a number",
        flag = "Server_LowCustom",
        callback = function(text)
            UIState.lowHopCustomValue = tonumber(text) or 8
        end,
    })
    local hopRow = tab:CreateGroup()
    hopRow:CreateSlider({
        name = "Hop Cooldown",
        range = { 5, 60 },
        value = 5,
        suffix = " s",
        flag = "Server_Cooldown",
        callback = function(value)
            ServerController.COOLDOWN = value
        end,
    })
    hopRow:CreateToggle({
        name = "Remember Visited",
        description = "Persists the visited list to disk when the executor allows it",
        value = true,
        flag = "Server_RememberVisited",
        callback = function(value)
            State.settings.rememberVisitedServers = value and true or false
        end,
    })

    tab:CreateSection({ name = "Information" })

    tab:CreateText({
        name = "Identity",
        text = string.format(
            "JobId %s  ·  PlaceId %d",
            game.JobId ~= "" and game.JobId:sub(1, 12) .. "…" or "(Studio)",
            game.PlaceId
        ),
    })
    Elements.serverInfo = tab:CreateText({
        name = "Live",
        text = "…",
    })

    return tab
end

local function buildAutoFarm(window)
    local tab = window:CreateTab({ name = "Auto Farm" })

    tab:CreateSection({ name = "Automation" })

    local masterToggle
    masterToggle = tab:CreateToggle({
        name = "Automation",
        description = "Target -> move -> interact loop with full recovery",
        flag = "Auto_Master",
        callback = function(value)
            if value then
                local ok = AutomationController:start()
                if not ok and masterToggle then
                                        masterToggle:Set(false, true)
                end
            else
                AutomationController:stop()
            end
        end,
    })
    Elements.autoMaster = masterToggle

    local modeDropdown
    modeDropdown = tab:CreateDropdown({
        name = "Farm Mode",
        options = { "Nearest", "Selected", "Boss", "Smart", "Quest" },
        value = "Nearest",
        description = "Smart weighs distance, health, boss status; Quest runs the quest loop",
        flag = "Auto_Mode",
        callback = function(option)
            if option == "Quest" and not AutomationController:isModeAvailable("Quest") then
                Notify.toast("Quest mode", "Unlocks with the released game's data")
                Logger:warn("Quest mode unavailable — staying on the previous mode")
                if modeDropdown then
                    modeDropdown:Set(TargetManager.mode, true)
                end
                return
            end
            TargetManager:setMode(option)
        end,
    })

    tab:CreateSection({ name = "Targets" })

    local targetDropdown = tab:CreateDropdown({
        name = "Selected Target",
        options = {},
        placeholder = "None discovered",
        description = "Populated live from the discovery cache",
        forgetState = true,
        callback = function(option)
            TargetManager:setSelected(option)
                        if State.automation.target and State.automation.target.name ~= option then
                State.automation.target = nil
            end
            Notify.toast("Target selected", option)
        end,
    })
    Elements.targetDropdown = targetDropdown

    local excludeDropdown = tab:CreateDropdown({
        name = "Exclude Targets",
        options = {},
        multiSelect = true,
        placeholder = "None",
        description = "Excluded targets are never auto-acquired",
        forgetState = true,
        callback = function(selected)
            TargetManager:setExclusions(selected)
        end,
    })
    Elements.excludeDropdown = excludeDropdown

    local targetRow = tab:CreateGroup()
    targetRow:CreateSlider({
        name = "Max Range",
        range = { 100, 10000 },
        increment = 50,
        value = 2000,
        suffix = " studs",
        flag = "Auto_MaxRange",
        callback = function(value)
            TargetManager:setMaxRange(value)
        end,
    })
    targetRow:CreateButton({
        name = "Refresh",
        callback = function()
            UI.refreshTargetDropdowns()
            Notify.toast("Targets", DiscoveryController.lastSummary)
        end,
    })

    tab:CreateSection({ name = "Movement" })

    tab:CreateDropdown({
        name = "Movement Method",
        options = { "Auto", "Walk", "Pathfind", "Tween", "CFrame" },
        value = "Auto",
        description = "Auto escalates Walk -> Pathfind -> Tween when stuck",
        flag = "Auto_MoveMethod",
        callback = function(option)
            MovementController.method = option
            MovementController.resolved = nil
            Logger:debug("Movement method set: " .. option)
        end,
    })
    local moveRow = tab:CreateGroup()
    moveRow:CreateSlider({
        name = "Movement Speed",
        description = "Used by the Tween and CFrame methods",
        range = { 5, 300 },
        value = 60,
        suffix = " sps",
        flag = "Auto_MoveSpeed",
        callback = function(value)
            MovementController.speed = value
        end,
    })
    moveRow:CreateSlider({
        name = "Arrival Range",
        range = { 2, 20 },
        increment = 0.5,
        value = 4,
        suffix = " studs",
        flag = "Auto_Arrival",
        callback = function(value)
            MovementController.arrival = value
        end,
    })

    tab:CreateSection({ name = "Interaction" })

    tab:CreateDropdown({
        name = "Interaction Mode",
        options = { "Auto", "ProximityPrompt", "ClickDetector", "Tool" },
        value = "Auto",
        description = "Auto tries prompts, then clickdetectors, then tools",
        flag = "Auto_InteractMode",
        callback = function(option)
            InteractionController.mode = option
        end,
    })
    local interRow = tab:CreateGroup()
    interRow:CreateSlider({
        name = "Interaction Delay",
        range = { 0.1, 5 },
        increment = 0.1,
        value = 0.5,
        suffix = " s",
        flag = "Auto_InteractDelay",
        callback = function(value)
            InteractionController.delay = value
        end,
    })
    interRow:CreateSlider({
        name = "Interaction Range",
        range = { 4, 40 },
        value = 10,
        suffix = " studs",
        flag = "Auto_InteractRange",
        callback = function(value)
            InteractionController.range = value
        end,
    })
    local attackRow = tab:CreateGroup()
    attackRow:CreateToggle({
        name = "Auto Attack",
        description = "Activates the equipped combat tool on cadence",
        value = true,
        flag = "Auto_Attack",
        callback = function(value)
            InteractionController.autoAttack = value
        end,
    })
    attackRow:CreateSlider({
        name = "Attack Interval",
        range = { 0.1, 2 },
        increment = 0.05,
        value = 0.4,
        suffix = " s",
        flag = "Auto_AttackInterval",
        callback = function(value)
            InteractionController.attackInterval = value
        end,
    })

    tab:CreateSection({ name = "Quest" })

    Elements.questStatus = tab:CreateText({
        name = "Status",
        text = "Quest loop off",
    })
    local lastQuestLine
    Tracker.loop("quest.status", 1, function()
        if not Elements.questStatus then return end
        local line
        if QuestController.active then
            line = "Quest: " .. (QuestController.state or "…")
            if QuestController.objectiveText ~= "" then
                line = line .. "  ·  " .. QuestController.objectiveText
            end
        elseif not QuestController.isAvailable() then
            line = "Quest off — " .. (GameDetector.gameLockReason() or "unavailable")
        else
            line = string.format("Quest loop off · %d giver(s) detected", #QuestController.givers)
        end
        if line ~= lastQuestLine then
            lastQuestLine = line
            pcall(function() Elements.questStatus:Set(line) end)
        end
    end)

    local loopToggle
    loopToggle = tab:CreateToggle({
        name = "Auto Quest Loop",
        description = "Accept -> progress -> turn in -> repeat",
        flag = "Quest_Loop",
        callback = function(value)
            local ok = QuestController:setLoop(value)
            if not ok and loopToggle then
                loopToggle:Set(false, true)
            end
        end,
    })
    local questRow = tab:CreateGroup()
    questRow:CreateToggle({
        name = "Auto Accept",
        value = true,
        flag = "Quest_AutoAccept",
        callback = function(value)
            QuestController.autoAccept = value and true or false
        end,
    })
    questRow:CreateToggle({
        name = "Auto Turn-In",
        value = true,
        flag = "Quest_AutoTurnIn",
        callback = function(value)
            QuestController.autoTurnIn = value and true or false
        end,
    })
    tab:CreateButton({
        name = "Detect Quest System",
        description = "Scans the quest UI and quest givers now, reports to the console",
        callback = function()
            local quest, reason = QuestController:detectCurrentQuest()
            local givers = QuestController:findQuestGivers()
            Logger:info(string.format(
                "Quest scan: %d giver(s), objective %s",
                #givers,
                quest and ("\"" .. tostring(quest.text) .. "\"") or (reason or "not found")
            ))
            for i, giver in ipairs(givers) do
                if i <= 10 then
                    Logger:info(string.format("  giver %02d: %s  path=%s", i, giver.name, giver.path))
                end
            end
            if quest then
                Notify.toast("Quest system", "Objective: " .. tostring(quest.text))
            else
                Notify.toast("Quest system", #givers > 0
                    and (#givers .. " giver(s) found, no objective UI")
                    or (reason or "nothing detected"))
            end
        end,
    })

    tab:CreateSection({ name = "Advanced" })

    local advancedRow = tab:CreateGroup()
    advancedRow:CreateSlider({
        name = "Target Scan Interval",
        range = { 0.5, 10 },
        increment = 0.5,
        value = 2,
        suffix = " s",
        description = "Discovery rescan rate (also feeds ESP)",
        flag = "Perf_TargetScan",
        callback = function(value)
            State.intervals.targetScan = value
        end,
    })
    advancedRow:CreateSlider({
        name = "Automation Tick Interval",
        range = { 0.1, 1 },
        increment = 0.05,
        value = 0.25,
        suffix = " s",
        flag = "Perf_AutoInterval",
        callback = function(value)
            State.intervals.automation = value
        end,
    })
    tab:CreateText({
        name = "Recovery",
        text = "Built-in: death pauses and resumes on respawn, vanished targets "
            .. "are re-acquired, failed movement escalates methods then skips "
            .. "the target for 15 s.",
    })

            local lockReason = GameDetector.gameLockReason()
    if lockReason then
        masterToggle:Lock(lockReason)
        loopToggle:Lock(lockReason)
    end

    return tab
end

local CLAN_STATE_TEXT = {
    TargetReached  = "Target clan reached",
    LimitReached   = "Reroll limit reached",
    WaitingRespawn = "Waiting for respawn",
}

local function buildClan(window)
    local tab = window:CreateTab({ name = "Clan" })

    tab:CreateSection({ name = "Clan Reroll" })

    Elements.clanStatus = tab:CreateText({
        name = "Status",
        text = GameDetector.gameLockReason() or "Clan reroll off",
    })

    local lastClanLine
    local clanUiOn = false
    Tracker.loop("clan.status", 1, function()
        if not Elements.clanStatus then return end
        local line
        if ClanController.enabled then
            line = string.format("%s · %d reroll(s)",
                ClanController.state or "…", ClanController.rerollCount)
            if ClanController.currentClan ~= "" then
                line = line .. " · " .. ClanController.currentClan
            end
        else
            local why = GameDetector.gameLockReason()
            if why and not ClanController.isAvailable() then
                line = why
            elseif ClanController.state ~= "Idle" then
                line = CLAN_STATE_TEXT[ClanController.state] or ClanController.state
            else
                line = "Clan reroll off"
            end
        end
        if line ~= lastClanLine then
            lastClanLine = line
            pcall(function() Elements.clanStatus:Set(line) end)
        end
        if Elements.statRerolls and Elements.statRerolls.value ~= ClanController.rerollCount then
            pcall(function() Elements.statRerolls:Set(ClanController.rerollCount) end)
        end
        if Elements.clanToggle and clanUiOn ~= ClanController.enabled then
            clanUiOn = ClanController.enabled
            pcall(function() Elements.clanToggle:Set(clanUiOn, true) end)
        end
    end)

    local clanToggle
    clanToggle = tab:CreateToggle({
        name = "Auto Reroll",
        description = "Rerolls until the target clan or the reroll limit",
        flag = "Clan_Auto",
        callback = function(value)
            if value then
                local ok = ClanController:setEnabled(true)
                if not ok and clanToggle then
                    clanToggle:Set(false, true)
                end
            else
                ClanController:setEnabled(false)
            end
        end,
    })
    Elements.clanToggle = clanToggle

    tab:CreateDropdown({
        name = "Stop Mode",
        options = { "Fixed Count", "Until Target Clan" },
        value = "Fixed Count",
        flag = "Clan_Mode",
        callback = function(option)
            ClanController.mode = option == "Until Target Clan" and "UntilTarget" or "Count"
        end,
    })

    tab:CreateInput({
        name = "Target Clan",
        placeholder = "Clan name (case-insensitive)",
        flag = "Clan_Target",
        callback = function(text)
            ClanController.targetClan = Util.trim(tostring(text or ""))
        end,
    })

    local clanRow = tab:CreateGroup()
    clanRow:CreateSlider({
        name = "Max Rerolls",
        range = { 1, 200 },
        value = 10,
        flag = "Clan_Max",
        callback = function(value)
            ClanController.maxRerolls = value
        end,
    })
    local rerollButton
    rerollButton = clanRow:CreateButton({
        name = "Reroll Once",
        description = "Fires the reroll right now (no walking)",
        callback = function()
            local ok, msg = ClanController:rerollOnce()
            if ok then
                Notify.toast("Clan", string.format("Reroll fired (%d total)", ClanController.rerollCount))
            else
                Notify.toast("Clan", msg or "Reroll failed")
            end
        end,
    })

    local clanRow2 = tab:CreateGroup()
    clanRow2:CreateSlider({
        name = "Reroll Delay",
        range = { 0.5, 10 },
        increment = 0.5,
        value = 1.5,
        suffix = " s",
        flag = "Clan_Delay",
        callback = function(value)
            ClanController.delay = value
        end,
    })
    Elements.statRerolls = clanRow2:CreateStat({ name = "Rerolls", value = 0 })

        local clanLockReason = GameDetector.gameLockReason()
    if clanLockReason then
        clanToggle:Lock(clanLockReason)
        rerollButton:Lock(clanLockReason)
    end

    return tab
end

local function buildESP(window)
    local tab = window:CreateTab({ name = "ESP" })

    tab:CreateSection({ name = "ESP" })

    Elements.espStatus = tab:CreateText({
        name = "Status",
        text = "ESP off",
    })

    tab:CreateToggle({
        name = "Enable ESP",
        description = "Drawing renderer when the executor supports it, Highlight mode otherwise",
        flag = "ESP_Master",
        callback = function(value)
            ESPController:setEnabled(value)
        end,
    })

    local lastEspLine
    Tracker.loop("esp.status", 2, function()
        if not Elements.espStatus then return end
        local line
        if ESPController.enabled then
            line = string.format(
                "Renderer: %s · %d/%d shown · %d ms rate",
                ESPController.rendererMode or "?",
                ESPController.stats.drawn or 0,
                ESPController.stats.total or 0,
                math.floor((State.intervals.espUpdate or 0.1) * 1000)
            )
        else
            line = "ESP off"
        end
        if line ~= lastEspLine then
            lastEspLine = line
            pcall(function() Elements.espStatus:Set(line) end)
        end
    end)

    tab:CreateSection({ name = "Categories" })

    local categories = {
        { id = "Players",   flag = "ESP_Cat_Players",   help = "All players" },
        { id = "NPCs",      flag = "ESP_Cat_NPCs",      help = "Discovery cache NPCs" },
        { id = "Bosses",    flag = "ESP_Cat_Bosses",    help = "Boss-class targets" },
        { id = "QuestNPCs", flag = "ESP_Cat_Quest",     help = "Detected quest givers" },
        { id = "Items",     flag = "ESP_Cat_Items",     help = "Generic pickup scan (drops, chests, ore)" },
    }
    local catRowA = tab:CreateGroup()
    local catRowB = tab:CreateGroup()
    for index, cat in ipairs(categories) do
        local row = index <= 3 and catRowA or catRowB
        row:CreateToggle({
            name = cat.id,
            description = cat.help,
            flag = cat.flag,
            callback = function(value)
                State.esp.categories[cat.id] = value and true or false
            end,
        })
    end

    tab:CreateSection({ name = "Display" })

    local hasDrawing = type(Drawing) == "table" and type(Drawing.new) == "function"
    local display = {
        { label = "Name",      key = "name",      flag = "ESP_Show_Name" },
        { label = "Distance",  key = "distance",  flag = "ESP_Show_Distance" },
        { label = "Health",    key = "health",    flag = "ESP_Show_Health" },
        { label = "Box",       key = "box",       flag = "ESP_Show_Box",    drawing = true },
        { label = "Tracer",    key = "tracer",    flag = "ESP_Show_Tracer", drawing = true },
        { label = "Highlight", key = "highlight", flag = "ESP_Show_Highlight" },
    }
    local dispRowA = tab:CreateGroup()
    local dispRowB = tab:CreateGroup()
    for index, option in ipairs(display) do
        local row = index <= 3 and dispRowA or dispRowB
        local toggle = row:CreateToggle({
            name = option.label,
            value = true,
            flag = option.flag,
            callback = function(value)
                State.esp.display[option.key] = value and true or false
            end,
        })
        if option.drawing and not hasDrawing then
            toggle:Lock("Needs the Drawing API — this executor renders Highlight mode")
        end
    end

    tab:CreateSection({ name = "Visuals" })

    local colorDefs = {
        { label = "Player Color", key = "Players", color = Color3.fromRGB(80, 200, 120),  flag = "ESP_Color_Players" },
        { label = "NPC Color",    key = "NPCs",    color = Color3.fromRGB(255, 170, 60),   flag = "ESP_Color_NPCs" },
        { label = "Boss Color",   key = "Bosses",  color = Color3.fromRGB(230, 70, 70),    flag = "ESP_Color_Bosses" },
    }
    for _, def in ipairs(colorDefs) do
        tab:CreateColorPicker({
            name = def.label,
            color = def.color,
            flag = def.flag,
            callback = function(color)
                State.esp.colors[def.key] = color
            end,
        })
    end

    local espSliders = tab:CreateGroup()
    espSliders:CreateSlider({
        name = "Update Rate",
        range = { 0.05, 1 },
        increment = 0.05,
        value = 0.1,
        suffix = " s",
        flag = "ESP_UpdateRate",
        callback = function(value)
            ESPController.settings.updateRate = value
            State.intervals.espUpdate = value
        end,
    })
    espSliders:CreateSlider({
        name = "Max Distance",
        range = { 100, 5000 },
        increment = 50,
        value = 2000,
        suffix = " studs",
        flag = "ESP_MaxDistance",
        callback = function(value)
            ESPController.settings.maxDistance = value
        end,
    })

    return tab
end

local THEMES = { "default", "cobalt", "ember", "amethyst", "frost", "rose" }

local function buildSettings(window)
    local tab = window:CreateTab({ name = "Settings" })

    tab:CreateSection({ name = "Configuration" })

    local configDropdown = tab:CreateDropdown({
        name = "Saved Configs",
        options = {},
        placeholder = "None saved yet",
        description = "Selecting pre-fills the name field below",
        forgetState = true,
        callback = function(option)
            if Elements.configName then
                Elements.configName:Set(option, true)
            end
        end,
    })
    Elements.configDropdown = configDropdown

    local nameInput = tab:CreateInput({
        name = "Config Name",
        placeholder = "e.g. Farming",
        flag = "Config_Name",
        callback = function(text)
            Logger:debug("Config name set: " .. tostring(text))
        end,
    })
    Elements.configName = nameInput

    local manageRow = tab:CreateGroup()
    manageRow:CreateButton({
        name = "Save",
        description = "Snapshot current state (.rfld)",
        callback = function()
            ConfigController:save()
        end,
    })
    manageRow:CreateButton({
        name = "Load",
        description = "Applies through every element (callbacks fire)",
        callback = function()
            ConfigController:load()
        end,
    })
    manageRow:CreateButton({
        name = "Delete",
        callback = function()
            ConfigController:delete()
        end,
    })

    tab:CreateToggle({
        name = "Auto-Load On Start",
        description = "Loads the last-used config one second after boot",
        value = false,
        flag = "Config_AutoLoad",
        callback = function(value)
            State.settings.autoLoadConfig = value and true or false
        end,
    })

    tab:CreateSection({ name = "Interface" })

    tab:CreateDropdown({
        name = "Theme",
        options = THEMES,
        value = "default",
        flag = "UI_Theme",
        callback = function(theme)
            pcall(function()
                State.window:ChangeTheme(theme)
            end)
            Logger:debug("Theme changed: " .. theme)
        end,
    })
    tab:CreateKeybind({
        name = "UI Toggle",
        description = "Show / hide the window",
        value = Enum.KeyCode.RightControl,
        flag = "UI_ToggleKey",
        callback = function()
            pcall(function()
                State.window:ToggleHide()
            end)
        end,
    })
    local notifRow = tab:CreateGroup()
    notifRow:CreateToggle({
        name = "Notifications",
        description = "Cards for meaningful events (start/stop, hops, configs)",
        value = true,
        flag = "UI_Notifications",
        callback = function(value)
            State.settings.notificationsEnabled = value and true or false
        end,
    })
    notifRow:CreateToggle({
        name = "Toasts",
        description = "Small pills for quick confirmations",
        value = true,
        flag = "UI_Toasts",
        callback = function(value)
            State.settings.toastsEnabled = value and true or false
        end,
    })
    tab:CreateSlider({
        name = "Notification Duration",
        range = { 2, 15 },
        value = 5,
        suffix = " s",
        flag = "UI_NotifDuration",
        callback = function(value)
            State.settings.notificationDuration = value
        end,
    })

    tab:CreateSection({ name = "Performance" })

    local perfRow = tab:CreateGroup()
    perfRow:CreateSlider({
        name = "Home Update Interval",
        range = { 0.5, 5 },
        increment = 0.25,
        value = 1,
        suffix = " s",
        flag = "Perf_HomeInterval",
        callback = function(value)
            State.intervals.homeStats = value
        end,
    })
    perfRow:CreateToggle({
        name = "Auto Performance",
        description = "Slows update loops when FPS drops, restores on recovery",
        value = true,
        flag = "Perf_Auto",
        callback = function(value)
            State.settings.autoPerformance = value and true or false
        end,
    })

    tab:CreateSection({ name = "Project" })

    tab:CreateText({
        name = "Info",
        text = string.format(
            "%s v%s (built %s)\nGame: %s  ·  PlaceId %d  ·  JobId %s\nModules loaded: %s",
            PROJECT_NAME, VERSION, BUILD_DATE,
            game.Name or "?", game.PlaceId,
            game.JobId ~= "" and game.JobId:sub(1, 12) .. "…" or "Studio",
            table.concat(ModuleManager.loadedList, ", ")
        ),
    })
    tab:CreateKeybind({
        name = "Emergency Stop Key",
        description = "Global panic key — works regardless of the tab you are on",
        value = Enum.KeyCode.P,
        flag = "Settings_EmergencyKey",
        callback = function()
            Emergency.stop()
        end,
    })
    local lifecycleRow = tab:CreateGroup()
    lifecycleRow:CreateButton({
        name = "Emergency Stop",
        description = "Kills every active feature instantly (automation, fly, noclip, speed)",
        callback = function()
            Emergency.stop()
        end,
    })
    lifecycleRow:CreateButton({
        name = "Reload",
        description = "Clean shutdown, then re-execute",
        callback = function()
            Emergency.reload()
        end,
    })
    lifecycleRow:CreateButton({
        name = "Destroy",
        description = "Full cleanup and UI removal",
        callback = function()
            State.window:Popup({
                title = "Destroy the project?",
                content = "Every feature stops, all connections and loops are "
                    .. "cleaned up, and the UI is destroyed. You will need to "
                    .. "re-execute the script to bring it back.",
                options = {
                    { text = "Cancel" },
                    {
                        text = "Destroy",
                        style = "danger",
                        callback = function()
                            Emergency.destroy()
                        end,
                    },
                },
            })
        end,
    })

    tab:CreateSection({ name = "Debug" })

    local console = tab:CreateConsole({
        name = "Log Console",
        height = 300,
        follow = true,
        maxLines = 200,
    })
    Logger:bindConsole(console)

    local consoleRow = tab:CreateGroup()
    consoleRow:CreateButton({
        name = "Clear",
        callback = function()
            Logger:clear()
        end,
    })
    consoleRow:CreateButton({
        name = "Copy Log",
        callback = function()
            local ok = console:Copy()
            if ok == false then
                Notify.toast("Console", "Clipboard unavailable in this executor")
            end
        end,
    })

    tab:CreateToggle({
        name = "Debug Logging",
        description = "Shows [DEBUG] lines — off by default so users are not flooded",
        value = false,
        flag = "Debug_Enabled",
        callback = function(value)
            Logger.debugEnabled = value and true or false
            State.settings.debugLogging = Logger.debugEnabled
            Logger:info("Debug logging " .. (value and "enabled" or "disabled"))
        end,
    })
    tab:CreateDropdown({
        name = "Minimum Level",
        options = { "INFO", "WARN", "ERROR" },
        value = "INFO",
        description = "DEBUG is controlled by the toggle above (no flag overlap)",
        flag = "Debug_Level",
        callback = function(level)
            Logger.minLevel = Logger.LEVELS[level] or Logger.LEVELS.INFO
            State.settings.logLevel = level
        end,
    })
    tab:CreateButton({
        name = "Dump Discovered Targets",
        description = "Prints every cached target — the tool that fills GameProfile",
        callback = function()
            DiscoveryController:dumpToConsole()
        end,
    })

    local trackerStats = tab:CreateGroup()
    Elements.statConnections = trackerStats:CreateStat({ name = "Connections", value = 0 })
    Elements.statLoops = trackerStats:CreateStat({ name = "Loops", value = 0 })

        Tracker.loop("debug.tracker", 2, function()
        local connections, loops = Tracker.stats()
        if Elements.statConnections and Elements.statConnections.value ~= connections then
            pcall(function() Elements.statConnections:Set(connections) end)
        end
        if Elements.statLoops and Elements.statLoops.value ~= loops then
            pcall(function() Elements.statLoops:Set(loops) end)
        end
    end)

    ConfigController:bind(configDropdown, nameInput)

    return tab
end

function UI.refreshTargetDropdowns()
    local names = DiscoveryController:names()
    if Elements.targetDropdown then
        pcall(function()
            Elements.targetDropdown:Refresh(names)
        end)
    end
    if Elements.excludeDropdown then
        pcall(function()
            Elements.excludeDropdown:Refresh(names)
        end)
    end
    Logger:debug("Target dropdowns refreshed (" .. #names .. " entries)")
end

function UI.createWindow()
    local window = Rayfield:CreateWindow({
        name = PROJECT_NAME,
        subtitle = GameProfile.name .. " · v" .. VERSION,
        sidebarLayout = true,
        profile = "Rayfield Gen2 · stable",
        showName = PROJECT_NAME,
        configuration = {
            autoSave = true,
            autoLoad = true,
            fileName = "PS2Hub",
            customFolder = "ProjectSlayers2",
        },
    })
    State.window = window
    State.rayfield = Rayfield
    Notify.init(window)

    window:CreateTag({
        text = "v" .. VERSION,
        color = Color3.fromRGB(110, 120, 140),
        order = 1,
    })
    Elements.gameTag = window:CreateTag({
        text = State.gameVerified
            and (GameProfile.DATA_READY and "PS2" or "PS2 · AWAITING DATA")
            or "UNVERIFIED",
        color = State.gameVerified
            and (GameProfile.DATA_READY
                and Color3.fromRGB(70, 180, 110)
                or Color3.fromRGB(235, 140, 50))
            or Color3.fromRGB(235, 140, 50),
        order = 2,
    })
    return window
end

function UI.buildTabs(window)
        buildHome(window)
    buildUniversal(window)
    buildAutoFarm(window)
    buildClan(window)
    buildESP(window)
    buildServer(window)
    buildSettings(window)

        HomeStats.handles = {
        players = Elements.statPlayers,
        ping    = Elements.statPing,
        kills   = Elements.statKills,
        targets = Elements.statTargets,
    }
    HomeStats.texts = {
        game    = Elements.homeGame,
        player  = Elements.homePlayer,
        task    = Elements.homeTask,
    }
    HomeStats.progress = Elements.homeProgress

        PlayerController:bindList(Elements.playerDropdown)

        DiscoveryController.onCacheUpdated:Connect(function()
        UI.refreshTargetDropdowns()
    end)
    UI.refreshTargetDropdowns()

        local lastServerLine
    Tracker.loop("server.info", function() return State.intervals.serverInfo end, function()
        if not Elements.serverInfo then return end
        local info = ServerController:getInfo()
        local line = string.format(
            "%d / %d players · age %s · ping %s",
            info.players, info.maxPlayers,
            Util.formatDuration(info.age),
            info.ping and (info.ping .. " ms") or "n/a"
        )
        if line ~= lastServerLine then
            lastServerLine = line
            pcall(function() Elements.serverInfo:Set(line) end)
        end
    end)
end

function Emergency.stop()
    Logger:warn("EMERGENCY STOP — killing all active features")
    AutomationController:stop()
    syncAutomationToggle(false)
    QuestController:stop()
    ClanController:stop()
    ESPController:setEnabled(false)
    CharacterController:stopAll()
    MovementController:cancel("emergency stop")
    Notify.notify("Emergency Stop", "All features stopped. UI remains usable.")
end

function Emergency.reload()
    Emergency.stop()
    Notify.notify("Reloading", "Project is shutting down cleanly…")
    if EXECUTE_URL ~= "" and type(loadstring) == "function" then
        Logger:info("Reload: re-executing from EXECUTE_URL")
        pcall(function()
            State.window:Unload()
        end)
        local ok, err = pcall(function()
            loadstring(game:HttpGet(EXECUTE_URL))()
        end)
        if not ok then
                        warn("[PS2 Hub] reload failed: " .. tostring(err))
        end
    else
        Logger:info("Reload: no EXECUTE_URL configured — clean shutdown only")
        Notify.toast("Reload", "Re-execute the script to restart")
        pcall(function()
            State.window:Unload()
        end)
    end
end

function Emergency.destroy()
    Emergency.stop()
    Notify.notify("Destroying project", "All modules, loops and connections cleaned up.")
    Logger:info("Project destroying — full teardown")
    ModuleManager.stopAll()
    Tracker.beginShutdown()
    local genv = (typeof(getgenv) == "function" and getgenv()) or _G
    if genv then
        genv[GENV_KEY] = nil
    end
    pcall(function()
        State.window:Unload()
    end)
end

local function getGenv()
    if typeof(getgenv) == "function" then
        local ok, env = pcall(getgenv)
        if ok then return env end
    end
    return _G
end

local function unloadPrevious()
    local genv = getGenv()
    local existing = genv[GENV_KEY]
    if type(existing) == "table" and type(existing.destroy) == "function" then
        Logger:info("Previous instance detected — unloading it")
        pcall(existing.destroy)
        task.wait(0.5)
    end
end

local function loadRayfield()
    if SECURE_MODE then
        local genv = getGenv()
        genv.RAYFIELD_SECURE = true
    end
    local ok, result = pcall(function()
        return loadstring(game:HttpGet(RAYFIELD_URL))()
    end)
    if not ok or type(result) ~= "table" then
        warn("[PS2 Hub] Rayfield Gen2 failed to load: " .. tostring(result))
        return nil
    end
    Rayfield = result
    Logger:info("Rayfield Gen2 loaded (stable channel)")
    return result
end

local function registerModules()
    ModuleManager.register("CharacterController", CharacterController)
    ModuleManager.register("PlayerController", PlayerController)
    ModuleManager.register("ServerController", ServerController)
    ModuleManager.register("DiscoveryController", DiscoveryController)
    ModuleManager.register("TargetManager", TargetManager)
    ModuleManager.register("MovementController", MovementController)
    ModuleManager.register("InteractionController", InteractionController)
    ModuleManager.register("AutomationController", AutomationController)
    ModuleManager.register("QuestController", QuestController)
    ModuleManager.register("ClanController", ClanController)
    ModuleManager.register("ESPController", ESPController)
    ModuleManager.register("HomeStats", HomeStats)
    ModuleManager.register("ConfigController", ConfigController)
end

local function main()
    Logger:info(string.format(
        "Project initialized — %s v%s (%s)",
        PROJECT_NAME, VERSION, BUILD_DATE
    ))

    unloadPrevious()

    if not loadRayfield() then
        return
    end

        Http.init()
    GameDetector.check()
    State.gameVerified = GameDetector.verified

        local window = UI.createWindow()

        registerModules()
    ModuleManager.initAll()

        UI.buildTabs(window)

        ConfigController:tryAutoLoad()

        if EXECUTE_URL ~= "" and typeof(queue_on_teleport) == "function" then
        pcall(function()
            queue_on_teleport(EXECUTE_URL)
        end)
        Logger:info("Teleport re-execution queued (" .. EXECUTE_URL .. ")")
    end

        local genv = getGenv()
    genv[GENV_KEY] = {
        version = VERSION,
        stop = function() Emergency.stop() end,
        destroy = function() Emergency.destroy() end,
    }

        Logger:info(string.format(
        "Game: %s (%s) — PS2 features %s",
        game.Name or "?",
        GameDetector.reason,
        GameDetector.shouldEnableGameFeatures() and "UNLOCKED" or ("LOCKED (" .. (GameDetector.gameLockReason() or "?") .. ")")
    ))
    Logger:info("Tip: Debug tab -> 'Dump Discovered Targets' fills GameProfile")

    if GameDetector.shouldEnableGameFeatures() then
        Notify.notify("Project loaded", PROJECT_NAME .. " v" .. VERSION .. " — game verified, automation ready.")
    elseif State.gameVerified then
        Notify.notify("Project loaded", PROJECT_NAME .. " v" .. VERSION
            .. " — Slayers 2 detected. Game-specific features (auto farm, "
            .. "quests, clan reroll) stay locked until the game releases and "
            .. "its instance data is provided.")
    elseif GameProfile.CONFIGURED then
        Notify.notify("Wrong game detected", "Universal features work; PS2 automation stays locked.")
    else
        Notify.notify(
            "Project loaded (universal mode)",
            "GameProfile is unconfigured. Universal features work; automation, "
                .. "quests and ESP unlock once you set the PS2 PlaceId."
        )
    end
end

main()
