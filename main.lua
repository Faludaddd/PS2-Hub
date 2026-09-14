

local VERSION       = "1.0.0"
local BUILD_DATE    = "2026-09-14"
local PROJECT_NAME  = "PS2 Hub"

local RAYFIELD_URL  = "https://sirius.menu/gen2"

local SECURE_MODE   = false

local EXECUTE_URL = "https://raw.githubusercontent.com/Faludaddd/PS2-Hub/main/main.lua"

local GENV_KEY      = "PS2HUB_ACTIVE"

local GameProfile = {
    name        = "Project Slayers 2",

            PLACE_ID    = 0,
    GAME_ID     = 0,

        aliases     = { "project slayers 2", "ps2" },

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

                QUEST = {
        enabled        = false,
        containers     = { "Quests", "Quest" },
        tags           = { "Quest", "QuestGiver" },
        giverPatterns  = { "quest", "giver" },
                objectiveSources = {},
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
    uptime     = os.clock(),
}

State.intervals = {
    homeStats   = 1.0,
    targetScan  = 2.0,
    automation  = 0.25,
    serverInfo  = 2.0,
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
        Logger:info("Game verified: " .. game.Name .. " (" .. GameDetector.reason .. ")")
    else
        Logger:warn("Wrong game detected — PS2 automation locked")
    end
    return GameDetector.verified
end

function GameDetector.shouldEnableGameFeatures()
        return GameDetector.verified
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
    if mode == "Quest" and not QuestController.isAvailable() then
        if not auto._questWarned then
            auto._questWarned = true
            Logger:warn("Quest mode unavailable — needs GameProfile.QUEST data")
            Notify.toast("Automation", "Quest mode awaiting game data")
        end
        state.taskState = "Idle"
        return
    end

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

function AutomationController:start()
    if self.enabled then return end
    if not GameDetector.shouldEnableGameFeatures() then
        Logger:warn("Automation requires the target game (profile unconfigured or mismatched)")
        Notify.toast("Automation", "Locked until the game profile is configured")
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

function QuestController.isAvailable()
    return GameProfile.QUEST.enabled == true
end

function QuestController:detectCurrentQuest()
    if not self.isAvailable() then
        return nil, "quest system not configured"
    end
            return nil, "not implemented — awaiting game data"
end

function QuestController:findQuestGivers()
    if not self.isAvailable() then
        return {}, "quest system not configured"
    end
            return {}, "not implemented — awaiting game data"
end

function QuestController:Start()
    if self.isAvailable() then
        Logger:info("Quest controller enabled (profile configured)")
    else
        Logger:info("Quest controller dormant — awaiting GameProfile.QUEST data")
    end
end

function QuestController:Cleanup() end

local ESPController = {}

ESPController.categories = {
    { id = "Players",    label = "Players",     source = "players" },
    { id = "NPCs",       label = "NPCs",        source = "discovery" },
    { id = "Bosses",     label = "Bosses",      source = "discovery" },
    { id = "QuestNPCs",  label = "Quest NPCs",  source = "discovery" },
    { id = "Items",      label = "Items & Drops", source = "none" },
}

ESPController.settings = {
    updateRate   = 0.1,
    maxDistance  = 2000,
}

ESPController._provider = nil
ESPController._loop     = nil
ESPController.enabled   = false

function ESPController:integrate(provider)
        self._provider = provider
    Logger:info("ESP render provider integrated")
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

    if enabledCats.NPCs or enabledCats.Bosses or enabledCats.QuestNPCs then
        for _, entry in ipairs(DiscoveryController.cache) do
            local cat = entry.category
            if cat == "Boss" and enabledCats.Bosses then
                table.insert(entries, {
                    model = entry.model, name = entry.name, root = entry.root,
                    humanoid = entry.humanoid, category = "Bosses", isPlayer = false,
                })
            elseif cat == "NPC" and (enabledCats.NPCs or (entry.isQuest and enabledCats.QuestNPCs)) then
                table.insert(entries, {
                    model = entry.model, name = entry.name, root = entry.root,
                    humanoid = entry.humanoid,
                    category = enabledCats.QuestNPCs and entry.isQuest and "QuestNPCs" or "NPCs",
                    isPlayer = false,
                })
            end
        end
    end

    return entries
end

function ESPController:setEnabled(enabled)
    if enabled and not self._provider then
        Logger:warn("ESP disabled: render provider not integrated (send your ESP source)")
        Notify.toast("ESP", "Awaiting ESP source integration")
        return false
    end
    self.enabled = enabled and true or false
    State.esp.enabled = self.enabled
    if self.enabled then
        self._loop = Tracker.loop("esp.update", self.settings.updateRate, function()
            if not ESPController.enabled then return end
            local ok, err = pcall(function()
                ESPController._provider:DrawFrame(
                    ESPController:collectEntries(),
                    ESPController.settings
                )
            end)
            if not ok then
                Logger:errorOnce("ESP frame error: " .. tostring(err))
            end
        end)
        pcall(function() self._provider:Start() end)
        Logger:info("ESP enabled")
    else
        if self._loop then
        self._loop:Stop()
        self._loop = nil
    end
        pcall(function()
            if self._provider then self._provider:Stop() end
        end)
        Logger:info("ESP disabled — objects cleaned up")
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
    setStat("uptime", math.floor(os.clock() - State.uptime))
    setStat("kills", State.automation.kills)
    setStat("interactions", State.automation.interactions)
    setStat("targets", #DiscoveryController.cache)

        setText("game", string.format(
        "%s%s  ·  PlaceId %d",
        game.Name or "?",
        State.gameVerified and "" or " (unverified)",
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
    setText("task", taskLine)

        local methodLine = string.format(
        "Walk: %s  ·  Fly: %s  ·  Move: %s  ·  Interact: %s",
        CharacterController.walk.resolved or (CharacterController.walk.enabled and "…" or "off"),
        CharacterController.fly.resolved or (CharacterController.fly.enabled and "…" or "off"),
        MovementController.resolved or "—",
        InteractionController.mode
    )
    setText("methods", methodLine)

        if target and target.humanoid and target.humanoid.Parent then
        local maxHealth = math.max(1, target.humanoid.MaxHealth)
        setProgress("value", Util.round(target.humanoid.Health / maxHealth * 100, 1))
    elseif auto.enabled then
        setProgress("indeterminate")
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

local function startAutomationFromUI()
    local ok = AutomationController:start()
    syncAutomationToggle(ok)
    return ok
end

local function stopAutomationFromUI()
    AutomationController:stop()
    syncAutomationToggle(false)
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

    local grid = tab:CreateGroup()
    local left = grid:CreateGroup({ direction = "column" })
    local right = grid:CreateGroup({ direction = "column" })

    Elements.statPlayers = left:CreateStat({ name = "Server Players", value = 0 })
    Elements.statPing = left:CreateStat({ name = "Ping", value = 0, suffix = " ms" })
    Elements.statUptime = left:CreateStat({ name = "Uptime", value = 0, suffix = " s" })

    Elements.statTargets = right:CreateStat({ name = "Targets Found", value = 0 })
    Elements.statKills = right:CreateStat({ name = "Kills", value = 0 })
    Elements.statInteractions = right:CreateStat({ name = "Interactions", value = 0 })

    tab:CreateSection({ name = "Automation Status" })

    Elements.homeTask = tab:CreateText({
        name = "Task",
        text = "Idle — automation off",
    })
    Elements.homeMethods = tab:CreateText({
        name = "Active Methods",
        text = "Walk: off · Fly: off · Move: — · Interact: Auto",
    })

    Elements.homeProgress = tab:CreateProgress({
        name = "Target Health",
        range = { 0, 100 },
        value = 0,
    })

    tab:CreateSection({ name = "Quick Controls" })

    local startRow = tab:CreateGroup()
    startRow:CreateButton({
        name = "Start Automation",
        description = "Begin the farm loop with the current mode",
        callback = function()
            startAutomationFromUI()
        end,
    })
    startRow:CreateButton({
        name = "Stop Automation",
        description = "Stop the loop cleanly (movement cancels, state resets)",
        callback = function()
            stopAutomationFromUI()
        end,
    })

    tab:CreateDivider({ text = "server" })

    local serverRow = tab:CreateGroup()
    serverRow:CreateButton({
        name = "Rejoin",
        callback = function()
            ServerController:rejoin()
        end,
    })
    serverRow:CreateButton({
        name = "Server Hop",
        callback = function()
            ServerController:hop("any")
        end,
    })
    serverRow:CreateButton({
        name = "Low Server Hop",
        callback = function()
            ServerController:hop("low", UIState.lowHopMax())
        end,
    })

    tab:CreateButton({
        name = "Emergency Stop",
        description = "Kills every active feature instantly (automation, fly, noclip, speed)",
        callback = function()
            Emergency.stop()
        end,
    })

    tab:CreateKeybind({
        name = "Emergency Stop Keybind",
        description = "Global panic key — works regardless of the tab you are on",
        value = Enum.KeyCode.P,
        flag = "Home_EmergencyKey",
        callback = function()
            Emergency.stop()
        end,
    })

    return tab
end

local function buildUniversal(window)
    local tab = window:CreateTab({ name = "Universal" })

    tab:CreateSection({ name = "Walk Speed" })

    tab:CreateToggle({
        name = "Enable Walk Speed",
        description = "Two real methods: property override or physics velocity",
        flag = "Univ_WalkSpeed_Enabled",
        callback = function(value)
            CharacterController:setWalkEnabled(value)
        end,
    })
    tab:CreateSlider({
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

    tab:CreateSection({ name = "Jump" })

    tab:CreateToggle({
        name = "Modify Jump",
        description = "Applies the mode the game's Humanoid actually uses (auto-detected)",
        flag = "Univ_Jump_Enabled",
        callback = function(value)
            CharacterController:setJumpEnabled(value)
        end,
    })
    tab:CreateSlider({
        name = "JumpPower",
        description = "Used when Humanoid.UseJumpPower is true",
        range = { 1, 500 },
        value = 50,
        flag = "Univ_JumpPower",
        callback = function(value)
            CharacterController:setJumpPower(value)
        end,
    })
    tab:CreateSlider({
        name = "JumpHeight",
        description = "Used when the game uses JumpHeight instead",
        range = { 1, 100 },
        increment = 0.5,
        value = 7.5,
        suffix = " studs",
        flag = "Univ_JumpHeight",
        callback = function(value)
            CharacterController:setJumpHeight(value)
        end,
    })

    tab:CreateSection({ name = "Infinite Jump" })

    tab:CreateToggle({
        name = "Infinite Jump",
        flag = "Univ_InfJump",
        callback = function(value)
            CharacterController:setInfiniteJump(value)
        end,
    })

    tab:CreateSection({ name = "Fly" })

    local flyToggle
    flyToggle = tab:CreateToggle({
        name = "Enable Fly",
        description = "E/Q or Space/LeftControl for vertical, WASD to move",
        flag = "Univ_Fly_Enabled",
        callback = function(value)
            CharacterController:setFlyEnabled(value)
        end,
    })
    tab:CreateSlider({
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
        name = "Fly Toggle Keybind",
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

    tab:CreateSection({ name = "Noclip" })

    local noclipToggle
    noclipToggle = tab:CreateToggle({
        name = "Noclip",
        flag = "Univ_Noclip",
        callback = function(value)
            CharacterController:setNoclip(value)
        end,
    })
    tab:CreateKeybind({
        name = "Noclip Toggle Keybind",
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

    tab:CreateSection({ name = "Character" })

    tab:CreateToggle({
        name = "Anti-AFK",
        description = "Fakes controller input when Roblox marks you idle",
        flag = "Univ_AntiAFK",
        callback = function(value)
            CharacterController:setAntiAFK(value)
        end,
    })

    local charRow = tab:CreateGroup()
    charRow:CreateButton({
        name = "Reset Character",
        callback = function()
            CharacterController:resetCharacter()
        end,
    })
    charRow:CreateButton({
        name = "Rejoin",
        callback = function()
            ServerController:rejoin()
        end,
    })
    charRow:CreateButton({
        name = "Server Hop",
        callback = function()
            ServerController:hop("any")
        end,
    })
    charRow:CreateButton({
        name = "Low Hop",
        callback = function()
            ServerController:hop("low", UIState.lowHopMax())
        end,
    })

    tab:CreateSection({ name = "Camera" })

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
    tab:CreateButton({
        name = "Reset FOV",
        callback = function()
            CharacterController:resetFOV()
            if Elements.fovSlider then
                Elements.fovSlider:Set(70, true)
            end
        end,
    })

    return tab
end

local function buildPlayers(window)
    local tab = window:CreateTab({ name = "Players" })

    tab:CreateSection({ name = "Player List" })

    local playerDropdown = tab:CreateDropdown({
        name = "Select Player",
        options = PlayerController.getPlayerNames(),
        placeholder = "None",
        description = "Type to search — the list refreshes on join/leave",
        forgetState = true,
    })
    Elements.playerDropdown = playerDropdown

    tab:CreateButton({
        name = "Refresh List",
        callback = function()
            PlayerController:refreshList()
        end,
    })
    tab:CreateToggle({
        name = "Auto-Refresh On Join / Leave",
        description = "On by default — the list tracks membership without polling",
        value = true,
        flag = "Players_AutoRefresh",
        callback = function(value)
            UIState.autoRefreshPlayers = value and true or false
        end,
    })

    tab:CreateSection({ name = "Teleport" })

    local tpRow = tab:CreateGroup()
    tpRow:CreateButton({
        name = "Teleport To",
        callback = function()
            local name = UIState.dropdownFirst(Elements.playerDropdown)
            if name then PlayerController:teleportTo(name, "to") end
        end,
    })
    tpRow:CreateButton({
        name = "Teleport Behind",
        callback = function()
            local name = UIState.dropdownFirst(Elements.playerDropdown)
            if name then PlayerController:teleportTo(name, "behind") end
        end,
    })
    tpRow:CreateButton({
        name = "Teleport Above",
        callback = function()
            local name = UIState.dropdownFirst(Elements.playerDropdown)
            if name then PlayerController:teleportTo(name, "above") end
        end,
    })

    tab:CreateSection({ name = "Spectate" })

    local specRow = tab:CreateGroup()
    specRow:CreateButton({
        name = "Spectate",
        callback = function()
            local name = UIState.dropdownFirst(Elements.playerDropdown)
            if name then PlayerController:spectate(name) end
        end,
    })
    specRow:CreateButton({
        name = "Stop Spectating",
        callback = function()
            PlayerController:stopSpectate()
        end,
    })

    return tab
end

local function buildServer(window)
    local tab = window:CreateTab({ name = "Server" })

    tab:CreateSection({ name = "Information" })

    Elements.serverJobId = tab:CreateText({
        name = "Job ID",
        text = game.JobId ~= "" and game.JobId or "(Studio)",
    })
    Elements.serverPlaceId = tab:CreateText({
        name = "Place ID",
        text = tostring(game.PlaceId),
    })
    Elements.serverInfo = tab:CreateText({
        name = "Live",
        text = "…",
    })

    tab:CreateSection({ name = "Server Hop" })

    tab:CreateButton({
        name = "Server Hop",
        description = "Skips servers you already visited this session",
        callback = function()
            ServerController:hop("any")
        end,
    })
    tab:CreateSlider({
        name = "Hop Cooldown",
        range = { 5, 60 },
        value = 5,
        suffix = " s",
        flag = "Server_Cooldown",
        callback = function(value)
            ServerController.COOLDOWN = value
        end,
    })
    tab:CreateToggle({
        name = "Remember Visited Servers",
        description = "Persists the visited list to disk when the executor allows it",
        value = true,
        flag = "Server_RememberVisited",
        callback = function(value)
            State.settings.rememberVisitedServers = value and true or false
        end,
    })

    tab:CreateSection({ name = "Low Server Hop" })

    tab:CreateDropdown({
        name = "Maximum Players",
        options = { "1", "2", "3", "4", "5", "6", "Custom" },
        value = "3",
        description = "Only servers at or below this count are accepted",
        flag = "Server_LowMax",
        callback = function(option)
            UIState.lowHopMode = option
        end,
    })
    Elements.lowHopCustom = tab:CreateInput({
        name = "Custom Maximum Players",
        numeric = true,
        value = "8",
        placeholder = "Enter a number",
        flag = "Server_LowCustom",
        callback = function(text)
            UIState.lowHopCustomValue = tonumber(text) or 8
        end,
    })

    tab:CreateButton({
        name = "Low Server Hop",
        callback = function()
            ServerController:hop("low", UIState.lowHopMax())
        end,
    })

    tab:CreateSection({ name = "Rejoin" })

    tab:CreateButton({
        name = "Rejoin",
        callback = function()
            ServerController:rejoin()
        end,
    })

    return tab
end

local LOCK_REASON_GAME = "Awaiting game profile — set PlaceId in GameProfile"

local function buildAutomation(window)
    local tab = window:CreateTab({ name = "Automation" })

    tab:CreateSection({ name = "Main" })

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
        name = "Automation Mode",
        options = { "Nearest", "Selected", "Boss", "Smart", "Quest" },
        value = "Nearest",
        description = "Smart weighs distance, health and boss status",
        flag = "Auto_Mode",
        callback = function(option)
            if option == "Quest" and not AutomationController:isModeAvailable("Quest") then
                Notify.toast("Quest mode", "Awaiting GameProfile.QUEST data")
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

    tab:CreateButton({
        name = "Refresh Target List",
        callback = function()
            UI.refreshTargetDropdowns()
            Notify.toast("Targets", DiscoveryController.lastSummary)
        end,
    })

    tab:CreateSlider({
        name = "Target Max Range",
        range = { 100, 10000 },
        increment = 50,
        value = 2000,
        suffix = " studs",
        flag = "Auto_MaxRange",
        callback = function(value)
            TargetManager:setMaxRange(value)
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
    tab:CreateSlider({
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
    tab:CreateSlider({
        name = "Arrival Range",
        description = "Distance considered 'in range' of the target",
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
    tab:CreateSlider({
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
    tab:CreateSlider({
        name = "Interaction Range",
        range = { 4, 40 },
        value = 10,
        suffix = " studs",
        flag = "Auto_InteractRange",
        callback = function(value)
            InteractionController.range = value
        end,
    })
    tab:CreateToggle({
        name = "Auto Attack (Tool)",
        description = "Activates the equipped combat tool on cadence",
        value = true,
        flag = "Auto_Attack",
        callback = function(value)
            InteractionController.autoAttack = value
        end,
    })
    tab:CreateSlider({
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

    tab:CreateDivider()

    tab:CreateSection({ name = "Recovery Behavior" })

    tab:CreateText({
        name = "Built-in",
        text = "Player death pauses the loop and resumes on respawn. Vanishing "
            .. "targets are re-acquired automatically. Failed movement escalates "
            .. "methods, then skips that target for 15 s. Nothing here needs a toggle.",
    })

        if not GameDetector.shouldEnableGameFeatures() then
        masterToggle:Lock(LOCK_REASON_GAME)
    end

    return tab
end

local LOCK_REASON_ESP = "Awaiting ESP source integration"

local function buildESP(window)
    local tab = window:CreateTab({ name = "ESP" })

    tab:CreateSection({ name = "Status" })

    tab:CreateText({
        name = "Scaffold",
        text = "The ESP architecture is wired (categories, settings, update "
            .. "loop, cleanup) but renders nothing until your existing ESP "
            .. "source is analyzed and integrated. Nothing pretends to work.",
    })

    tab:CreateSection({ name = "Master" })

    local espMaster = tab:CreateToggle({
        name = "Enable ESP",
        flag = "ESP_Master",
        callback = function(value)
            ESPController:setEnabled(value)
        end,
    })
    espMaster:Lock(LOCK_REASON_ESP)

    tab:CreateSection({ name = "Categories" })

    local categories = {
        { id = "Players",   flag = "ESP_Cat_Players",   help = "All players" },
        { id = "NPCs",      flag = "ESP_Cat_NPCs",      help = "Discovery cache NPCs" },
        { id = "Bosses",    flag = "ESP_Cat_Bosses",    help = "Boss-class targets" },
        { id = "QuestNPCs", flag = "ESP_Cat_Quest",     help = "Quest givers (once known)" },
        { id = "Items",     flag = "ESP_Cat_Items",     help = "Drops and items (once known)" },
    }
    for _, cat in ipairs(categories) do
        local toggle = tab:CreateToggle({
            name = cat.id,
            description = cat.help,
            flag = cat.flag,
            callback = function(value)
                State.esp.categories[cat.id] = value
            end,
        })
        toggle:Lock(LOCK_REASON_ESP)
    end

    tab:CreateSection({ name = "Display" })

    local display = {
        { label = "Name",     flag = "ESP_Show_Name" },
        { label = "Distance", flag = "ESP_Show_Distance" },
        { label = "Health",   flag = "ESP_Show_Health" },
        { label = "Box",      flag = "ESP_Show_Box" },
        { label = "Tracer",   flag = "ESP_Show_Tracer" },
        { label = "Highlight", flag = "ESP_Show_Highlight" },
    }
    for _, option in ipairs(display) do
        local toggle = tab:CreateToggle({
            name = option.label,
            flag = option.flag,
            callback = function(value)
                State.esp.display = State.esp.display or {}
                State.esp.display[option.flag] = value
            end,
        })
        toggle:Lock(LOCK_REASON_ESP)
    end

    tab:CreateSection({ name = "Visuals" })

    local playerColor = tab:CreateColorPicker({
        name = "Player Color",
        color = Color3.fromRGB(80, 200, 120),
        flag = "ESP_Color_Players",
        callback = function(color)
            State.esp.colors = State.esp.colors or {}
            State.esp.colors.Players = color
        end,
    })
    playerColor:Lock(LOCK_REASON_ESP)

    local npcColor = tab:CreateColorPicker({
        name = "NPC Color",
        color = Color3.fromRGB(255, 170, 60),
        flag = "ESP_Color_NPCs",
        callback = function(color)
            State.esp.colors = State.esp.colors or {}
            State.esp.colors.NPCs = color
        end,
    })
    npcColor:Lock(LOCK_REASON_ESP)

    local bossColor = tab:CreateColorPicker({
        name = "Boss Color",
        color = Color3.fromRGB(230, 70, 70),
        flag = "ESP_Color_Bosses",
        callback = function(color)
            State.esp.colors = State.esp.colors or {}
            State.esp.colors.Bosses = color
        end,
    })
    bossColor:Lock(LOCK_REASON_ESP)

    local updateRate = tab:CreateSlider({
        name = "ESP Update Rate",
        range = { 0.05, 1 },
        increment = 0.05,
        value = 0.1,
        suffix = " s",
        flag = "ESP_UpdateRate",
        callback = function(value)
            ESPController.settings.updateRate = value
        end,
    })
    updateRate:Lock(LOCK_REASON_ESP)

    local maxDistance = tab:CreateSlider({
        name = "ESP Max Distance",
        range = { 100, 5000 },
        increment = 50,
        value = 2000,
        suffix = " studs",
        flag = "ESP_MaxDistance",
        callback = function(value)
            ESPController.settings.maxDistance = value
        end,
    })
    maxDistance:Lock(LOCK_REASON_ESP)

    return tab
end

local LOCK_REASON_QUEST = "Awaiting GameProfile.QUEST data"

local function buildQuest(window)
    local tab = window:CreateTab({ name = "Quest" })

    tab:CreateText({
        name = "Scaffold",
        text = "Quest support activates once Project Slayers 2 exposes its "
            .. "quest structure. Fill GameProfile.QUEST (enabled, containers, "
            .. "tags, giver patterns, objective sources) and the Quest mode, "
            .. "this tab, and the QuestController unlock automatically.",
    })

    local loopToggle = tab:CreateToggle({
        name = "Auto Quest Loop",
        description = "Accept -> complete -> turn in -> repeat",
        flag = "Quest_Loop",
        callback = function(value)
            Logger:debug("Quest loop requested: " .. tostring(value))
        end,
    })
    loopToggle:Lock(LOCK_REASON_QUEST)

    local acceptToggle = tab:CreateToggle({
        name = "Auto Accept Quest",
        flag = "Quest_AutoAccept",
        callback = function() end,
    })
    acceptToggle:Lock(LOCK_REASON_QUEST)

    local turnInToggle = tab:CreateToggle({
        name = "Auto Turn-In",
        flag = "Quest_AutoTurnIn",
        callback = function() end,
    })
    turnInToggle:Lock(LOCK_REASON_QUEST)

    tab:CreateButton({
        name = "Detect Quest System",
        description = "Probes the current game and reports findings to the console",
        callback = function()
            local quest, reason = QuestController:detectCurrentQuest()
            if quest then
                Logger:info("Quest detected: " .. tostring(quest))
                Notify.toast("Quest system", "Detected — see console")
            else
                Logger:info("Quest detection: " .. tostring(reason))
                Notify.toast("Quest system", reason or "not found")
            end
        end,
    })

    return tab
end

local function buildConfig(window)
    local tab = window:CreateTab({ name = "Config" })

    tab:CreateSection({ name = "Configurations" })

    local configDropdown = tab:CreateDropdown({
        name = "Saved Configs",
        options = {},
        placeholder = "None saved yet",
        forgetState = true,
        callback = function(option)
                        if Elements.configName then
                Elements.configName:Set(option, true)
            end
        end,
    })
    Elements.configDropdown = configDropdown

    tab:CreateButton({
        name = "Refresh List",
        callback = function()
            ConfigController:refresh()
        end,
    })

    tab:CreateSection({ name = "Manage" })

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
        description = "Writes current state to the named config (.rfld)",
        callback = function()
            ConfigController:save()
        end,
    })
    manageRow:CreateButton({
        name = "Load",
        description = "Applies the config through every element (callbacks fire)",
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

    tab:CreateSection({ name = "Automation" })

    tab:CreateToggle({
        name = "Auto-Load On Start",
        description = "Loads the last-used config one second after boot",
        value = false,
        flag = "Config_AutoLoad",
        callback = function(value)
            State.settings.autoLoadConfig = value and true or false
        end,
    })

    tab:CreateText({
        name = "How saving works",
        text = "Every toggle/slider/dropdown/keybind saves itself under a "
            .. "stable flag (Rayfield Gen2 built-in persistence) and restores "
            .. "on the next launch. Named configurations above are snapshots "
            .. "on top of that — and Rayfield's own settings tab also gains a "
            .. "Configurations section automatically.",
    })

    ConfigController:bind(configDropdown, nameInput)

    return tab
end

local THEMES = { "default", "cobalt", "ember", "amethyst", "frost", "rose" }

local function buildSettings(window)
    local tab = window:CreateTab({ name = "Settings" })

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

    tab:CreateToggle({
        name = "Notifications",
        description = "Cards for meaningful events only (start/stop, hops, configs)",
        value = true,
        flag = "UI_Notifications",
        callback = function(value)
            State.settings.notificationsEnabled = value and true or false
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
    tab:CreateToggle({
        name = "Toasts",
        description = "Small pills for quick confirmations",
        value = true,
        flag = "UI_Toasts",
        callback = function(value)
            State.settings.toastsEnabled = value and true or false
        end,
    })
    tab:CreateText({
        name = "Mobile",
        text = "Rayfield Gen2 adapts the layout per device automatically "
            .. "(the sidebar rail collapses to icons on narrow screens), so "
            .. "there is no separate compact mode to fake here.",
    })

    tab:CreateSection({ name = "Performance" })

    tab:CreateSlider({
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
    tab:CreateSlider({
        name = "Target Scan Interval",
        range = { 0.5, 10 },
        increment = 0.5,
        value = 2,
        suffix = " s",
        flag = "Perf_TargetScan",
        callback = function(value)
            State.intervals.targetScan = value
        end,
    })
    tab:CreateSlider({
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
    tab:CreateToggle({
        name = "Auto Performance Mode",
        description = "Slows update loops when FPS drops, restores when it recovers",
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

    local projectRow = tab:CreateGroup()
    projectRow:CreateButton({
        name = "Reload Project",
        description = "Clean shutdown, then re-execute (see console for details)",
        callback = function()
            Emergency.reload()
        end,
    })
    projectRow:CreateButton({
        name = "Destroy Project",
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

    return tab
end

local function buildDebug(window)
    local tab = window:CreateTab({ name = "Debug" })

    tab:CreateSection({ name = "Console" })

    local console = tab:CreateConsole({
        name = "Log Console",
        height = 320,
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

    tab:CreateSection({ name = "Log Settings" })

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

    tab:CreateSection({ name = "Diagnostics" })

    tab:CreateButton({
        name = "Dump Discovered Targets",
        description = "Prints every cached target — the tool that fills GameProfile",
        callback = function()
            DiscoveryController:dumpToConsole()
        end,
    })

    Elements.statConnections = tab:CreateStat({
        name = "Tracked Connections",
        value = 0,
    })
    Elements.statLoops = tab:CreateStat({
        name = "Active Loops",
        value = 0,
    })

        Tracker.loop("debug.tracker", 2, function()
        local connections, loops = Tracker.stats()
        if Elements.statConnections and Elements.statConnections.value ~= connections then
            pcall(function() Elements.statConnections:Set(connections) end)
        end
        if Elements.statLoops and Elements.statLoops.value ~= loops then
            pcall(function() Elements.statLoops:Set(loops) end)
        end
    end)

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
        text = State.gameVerified and "PS2" or "UNVERIFIED",
        color = State.gameVerified
            and Color3.fromRGB(70, 180, 110)
            or Color3.fromRGB(235, 140, 50),
        order = 2,
    })
    return window
end

function UI.buildTabs(window)
        window:CreateSection({ name = "Main" })
    buildHome(window)

    window:CreateSection({ name = "Features" })
    buildUniversal(window)
    buildPlayers(window)
    buildServer(window)
    buildESP(window)

    window:CreateSection({ name = "Game" })
    buildAutomation(window)
    buildQuest(window)

    window:CreateSection({ name = "System" })
    buildConfig(window)
    buildSettings(window)
    buildDebug(window)

        HomeStats.handles = {
        players       = Elements.statPlayers,
        ping          = Elements.statPing,
        uptime        = Elements.statUptime,
        kills         = Elements.statKills,
        interactions  = Elements.statInteractions,
        targets       = Elements.statTargets,
    }
    HomeStats.texts = {
        game    = Elements.homeGame,
        player  = Elements.homePlayer,
        task    = Elements.homeTask,
        methods = Elements.homeMethods,
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
        State.gameVerified and "UNLOCKED" or "LOCKED"
    ))
    Logger:info("Tip: Debug tab -> 'Dump Discovered Targets' fills GameProfile")

    if State.gameVerified then
        Notify.notify("Project loaded", PROJECT_NAME .. " v" .. VERSION .. " — game verified, automation ready.")
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
