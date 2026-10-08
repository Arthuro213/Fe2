-- ==============================================================================
-- Flood GUI v4 (Upgraded) + Built-in TAS Player (Merged)
-- Description: Full exploit GUI for Flood Escape 2 with integrated TAS Player
-- Credits: 
--      TAS System: Tomato (Base by Voiz#5668)
--      Reverse Engineering/Base GUI: Tomato
--      UI Library: xHeptc (Kavo)
--      Lobby Tools (Boosts/Voting/Auto-Join): rokfx (merged from FE2 Troll)
--      Config Save/Load, Auto-Rejoin Watchdog, TAS Library: added in merge
--      Run Tracking, Discord Notifications, TAS Prefetch, Floating Button: added in merge
--      Quick Farm (remote-based farm, Fast Load, God Mode): adapted from tomato.txt's quickfarm
-- ==============================================================================

-- ==============================================================================
-- [1] INSTANCE CLEARING & SETUP
-- ==============================================================================
if getgenv().FloodGUI_Connections or getgenv().TomatoConnections or getgenv().TASConnections then
    print("[Flood GUI]: Overriding previous instance...")
    for _, connection in pairs(getgenv().FloodGUI_Connections or {}) do
        if connection then pcall(function() connection:Disconnect() end) end
    end
    for _, connection in pairs(getgenv().TomatoConnections or {}) do
        if connection then pcall(function() connection:Disconnect() end) end
    end
    for _, connection in pairs(getgenv().TASConnections or {}) do
        if connection then pcall(function() connection:Disconnect() end) end
    end
    if getgenv().TAS_RestoreAnim then
        pcall(getgenv().TAS_RestoreAnim)
        getgenv().TAS_RestoreAnim = nil
    end
    _G.LoopCancel = true
    if getgenv().FloodGUI_FloatingBtn then
        pcall(function() getgenv().FloodGUI_FloatingBtn:Destroy() end)
        getgenv().FloodGUI_FloatingBtn = nil
    end
    getgenv().TomatoAutoFarm = false
    getgenv().IsTASPlaying = false
    getgenv().TASPaused = false
    task.wait(0.2)
end

getgenv().FloodGUI_Connections = {}
getgenv().TomatoConnections = getgenv().FloodGUI_Connections
getgenv().TASConnections = {}
getgenv().TasFileCache = {}
getgenv().TasDataCache = {}
getgenv().TomatoAutoFarm = false
getgenv().IsTASPlaying = false
getgenv().TASPaused = false
_G.LoopCancel = false

local function TrackConnection(connection)
    table.insert(getgenv().FloodGUI_Connections, connection)
    return connection
end

-- Safe OnClientEvent when remote may be nil (FE2CM)
local function SafeChildAdded(parent)
    if parent then
        return parent.ChildAdded
    end
    return {
        Connect = function(_, _fn)
            return { Disconnect = function() end }
        end
    }
end

local function SafeOnClient(remote)
    if remote then
        return remote.OnClientEvent
    end
    return {
        Connect = function(_, _fn)
            return { Disconnect = function() end }
        end
    }
end

local function AddTASConnection(conn)
    table.insert(getgenv().TASConnections, conn)
    return conn
end

-- ==============================================================================
-- [2] SERVICES & CONSTANTS
-- ==============================================================================
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local CoreGui = game:GetService("CoreGui")

local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-- FE2CM (Community Maps) + main FE2 compatibility
-- Hard WaitForChild on missing remotes freezes the whole script on FE2CM.
local FE2CM_PLACE_IDS = {
    [11951199229] = true, -- Flood Escape 2 Community Maps
}
local IS_FE2CM = FE2CM_PLACE_IDS[game.PlaceId] == true
if not IS_FE2CM then
    pcall(function()
        local info = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId)
        local n = string.lower(tostring(info and info.Name or ""))
        if string.find(n, "community", 1, true) or string.find(n, "fe2cm", 1, true) then
            IS_FE2CM = true
        end
    end)
end

local function WaitChild(parent, name, timeout)
    if not parent then return nil end
    local existing = parent:FindFirstChild(name)
    if existing then return existing end
    return parent:WaitForChild(name, timeout or 5)
end

local Multiplayer = WaitChild(Workspace, "Multiplayer", 15) or Workspace:FindFirstChild("Multiplayer")
local RemoteFolder = WaitChild(ReplicatedStorage, "Remote", 10) or ReplicatedStorage:FindFirstChild("Remote")

-- Some builds (and FE2CM) use obfuscated remote names. Known alternates are tried
-- instantly, before waiting for the plain name to appear.
local REMOTE_ALIASES = {
    PressedMapButton = { "igzyswprgEbMOxwZWHUxvFWNJhDtaODb" },
    UpdGoalLocator = { "FiIxfRCqDOTWRKHqFMoRjSaAxXOutMzD", "SetButtonLocator" },
    ReqRebirth = { "rebirth", "LxWowhVdggjbxLTozuicVKHltFbUuVUg" },
    AddedWaiting = { "dKgyIXnLdhwvSyEorkEWJJAkgUslGCtR", "sTYfsJjxNdIpKgbXIuymAQiYcmAaORRN" },
}

local function FindRemoteNow(name)
    if not RemoteFolder then return nil end
    local names = { name }
    for _, alt in ipairs(REMOTE_ALIASES[name] or {}) do
        names[#names + 1] = alt
    end
    for _, n in ipairs(names) do
        local obj = RemoteFolder:FindFirstChild(n) or RemoteFolder:FindFirstChild(n, true)
        if obj and (obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction")) then
            return obj
        end
    end
    return nil
end

local function Remote(name, hardTimeout)
    if not RemoteFolder then return nil end
    local found = FindRemoteNow(name)
    if found then return found end
    local t = hardTimeout
    if t == nil then t = IS_FE2CM and 3 or 8 end
    return WaitChild(RemoteFolder, name, t) or FindRemoteNow(name)
end

local ReqPasskey = Remote("ReqPasskey")
local ReqRebirth = Remote("ReqRebirth")
local NewMapVote = Remote("NewMapVote")
local UpdMapVote = Remote("UpdMapVote")
local AddedWaiting = Remote("AddedWaiting")
local AlertRemote = Remote("Alert")
local AddMapEventRemote = Remote("AddMapEvent", 2)
local BoostIntensity = Remote("BoostIntensity", 2)
local ReqTele = Remote("ReqTele", 2)
local RemoveWaiting = Remote("RemoveWaiting", 2)
local PressedMapButton = Remote("PressedMapButton", 3)
local UpdGoalLocator = Remote("UpdGoalLocator", 3)
local SurvivedRemote = Remote("Survived", 3)
local LoadedMapRemote = Remote("LoadedMap", 2)

if IS_FE2CM then
    print("[Flood GUI]: FE2CM detected (PlaceId " .. tostring(game.PlaceId) .. ") — soft remote binding enabled")
end

local CONFIG = {
    UI_LIBRARY = "https://github.com/tomatotxt/Kavo-UI-Library/raw/refs/heads/main/source.lua",
    TAS_BASE_URL = "https://raw.githubusercontent.com/tomatotxt/Flood-GUI/refs/heads/v4beta/TAS%20FILES/", 
    TAS_API_URL = "https://api.github.com/repos/tomatotxt/Flood-GUI/contents/TAS%20FILES?ref=v4beta",
    TAS_CREATOR_URL = "https://raw.githubusercontent.com/tomatotxt/Flood-GUI/refs/heads/v4beta/TAS/CREATOR/creator.luau",
    DISCORD_INVITE = "https://discord.gg/8N2M9fHJqa"
}

local DIFFICULTY_RANKS = {
    ["None"] = 999, ["Easy"] = 1, ["Normal"] = 2, ["Hard"] = 3, ["Insane"] = 4, ["Crazy"] = 5, ["Crazy+"] = 6
}

local SAFE_ROOM_CFRAME = CFrame.new(-100.5, -222.95, -36.5)

local PLACE_IDS = {
    Pro = 1273079594,
    Normal = 738339342,
    FE2CM = 11951199229
}

local COLORS = {
    System  = Color3.fromRGB(180, 0, 20),
    Success = Color3.fromRGB(200, 0, 25),
    Warning = Color3.fromRGB(190, 10, 20),
    Error   = Color3.fromRGB(160, 0, 15),
    Info    = Color3.fromRGB(200, 15, 30),
    Item    = Color3.fromRGB(175, 0, 25)
}

local KAVO_THEME = {
    SchemeColor = Color3.fromRGB(180, 20, 30),   -- red accent
    Background = Color3.fromRGB(12, 12, 12),     -- near black
    Header = Color3.fromRGB(8, 8, 8),            -- deeper black
    TextColor = Color3.fromRGB(245, 245, 245),   -- light text
    ElementColor = Color3.fromRGB(28, 28, 28)    -- dark elements
}

-- ==============================================================================
-- [3] STATE MANAGEMENT
-- ==============================================================================
local State = {
    AutoPlay = false,        
    FallbackToFarm = false,  
    AutoFarm = false,        
    AutoCollect = false,
    AutoRebirth = false, 
    AutoLeave = false,
    UIEnabled = true,
    
    Mode = "Farm", 
    TargetDifficulty = "Normal",
    TargetMapName = "", 
    EnforceDifficulty = false, 
    CurrentlyFarming = false,
    Escaped = false,
    ResettingForDifficulty = false,
    
    WalkSpeed = 20,
    JumpPower = 50,
    Noclip = false,
    AirJump = false,
    SwimEnabled = false,
    TASSpeed = 1, -- 1 = normal, lower = faster, higher = slower

    -- Lobby tools
    AutoBoost = false,
    AutoEvent = false,
    AutoVoting = false,
    AutoFullVote = false,
    CustomVoteTarget = 4,
    AutoTeleport = false,
    AutoReqTele = false,
    TargetUsername = "",
    TargetUserId = nil,
    SelectedPlaceType = "Pro",

    -- Config / Safety
    AutoRejoinDisconnect = false,
    AutoRejoinStall = false,
    StallMinutes = 8,
    ReloadSource = "",
    AutoSaveConfig = false,

    -- Run tracking / notifications / mobile
    MaxTasFails = 3,
    WebhookURL = "",
    WebhookEnabled = false,
    FloatingButton = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled,

    -- Quick farm
    FastLoad = false,
    GodMode = false,
    PlayAfterButtons = false,
    ResetAfterEscape = false,
    StartDelay = 0,
    ResetDelay = 0,
    CycleChallenges = false,

    -- Rejoin cooldown (FE2 blocks rejoining for ~10s after leaving/disconnecting)
    RejoinDelay = 11,
    RejoinPendingAt = 0,

    -- Map Tools
    MapTPFloat = true,
    MapTPInterval = 0.05,

    -- FE2 extras
    ButtonAura = false,
    AuraUseDistance = true,
    AuraDist = 7,
    AntiVoid = false,
    ClickTP = false,
    AfkFps = 15
}

local PauseButtonGui = nil

local RunStats = {
    Maps = {}, SessionOk = 0, SessionFail = 0,
    Escapes = 0, MapsSeen = 0, LastEscape = 0, StartedAt = os.clock()
}
local Notify = {}
local TasPrefetch = {}
local Rebirth = {}
local Currency = {}
local Afk = { Active = false }
local QF = {
    Goal = nil, Button = nil, Next = nil, Passkey = nil,
    ExitPhase = false, Escaped = false, DelayOverride = false, ResettingCharacter = false,
    UpdTarget = nil, LockIndices = {}, OrigUpd = nil, OrigNewAlert = nil, NoclipConn = nil
}

-- ==============================================================================
-- [4] UTILITIES & ALERT SYSTEM
-- ==============================================================================
local PlayerScripts = LocalPlayer:FindFirstChild("PlayerScripts") or LocalPlayer:WaitForChild("PlayerScripts", 10)
local CLMAIN = nil
if PlayerScripts then
    CLMAIN = PlayerScripts:FindFirstChild("CL_MAIN_GameScript")
        or PlayerScripts:WaitForChild("CL_MAIN_GameScript", IS_FE2CM and 5 or 15)
end
local CLMAINenv = nil
if CLMAIN then
    pcall(function() CLMAINenv = getsenv(CLMAIN) end)
else
    warn("[Flood GUI]: CL_MAIN_GameScript not found — alerts/TAS anim hooks limited (common on FE2CM variants)")
end

local function Alert(Text, ColorType)
    local Output = tostring(Text)
    local SelectedColor = COLORS[ColorType] or COLORS.System
    local alertFn = QF.OrigNewAlert or (CLMAINenv and CLMAINenv.newAlert)
    if alertFn then
        pcall(function() alertFn(Output, SelectedColor, nil, nil) end)
    end
    print("[Flood GUI]: " .. Output)
end

local function LoadExternalScript(url)
    local success, response = pcall(function() return game:HttpGet(url) end)
    if success and response then
        local func = loadstring(response)
        if func then func() end
    end
end

local function isRandomString(str)
    if #str == 0 then return false end
    for i = 1, #str do
        local ltr = str:sub(i, i)
        if ltr:lower() == ltr then return false end
    end
    return true
end

local function CleanMapName(name)
    if not name then return "" end
    return (name:gsub("\160", " "):gsub("^%s*(.-)%s*$", "%1"))
end

local function GetChar()
    return LocalPlayer.Character or (LocalPlayer.CharacterAdded:wait() and LocalPlayer.Character)
end

local function Noclip(Toggle)
    local char = GetChar()
    if char then
        for _, v in pairs(char:GetChildren()) do
            if v:IsA("BasePart") and v.Name ~= "HumanoidRootPart" then 
                v.CanCollide = not Toggle 
            end
        end
    end
end

local function Check(Flag)
    local char = GetChar()
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end
    
    if Flag == "InLift" then
        return (hrp.Position.X < 50 and hrp.Position.Z > 70)
    elseif Flag == "InGame" then
        return QF.DelayOverride or (hrp.Position.X > 50)
    end
    return false
end

local function GetSessionKey()
    if not ReqPasskey then return nil end
    local success, key = pcall(function() return ReqPasskey:InvokeServer() end)
    return success and -key or nil
end

local function CheckGithubForFile(rawName)
    local mapName = CleanMapName(rawName)
    if getgenv().TasFileCache[mapName] ~= nil then return getgenv().TasFileCache[mapName] end
    
    local encoded = HttpService:UrlEncode(mapName)
    local url = CONFIG.TAS_BASE_URL .. encoded .. ".json"
    local success, response = pcall(function() return game:HttpGet(url) end)
    local exists = (success and #response > 200 and not response:find("404: Not Found"))
    
    getgenv().TasFileCache[mapName] = exists
    return exists
end

-- Downloads a TAS file's raw JSON, trying both repo branches. Returns the string or nil.
local function FetchTasRaw(rawName)
    local names = { rawName }
    local cleaned = CleanMapName(rawName)
    if cleaned ~= rawName then names[#names + 1] = cleaned end
    for _, name in ipairs(names) do
        local encoded = HttpService:UrlEncode(name)
        local urls = {
            "https://raw.githubusercontent.com/tomatotxt/Flood-GUI/refs/heads/testing/TAS%20FILES/" .. encoded .. ".json",
            CONFIG.TAS_BASE_URL .. encoded .. ".json",
        }
        for _, url in ipairs(urls) do
            local ok, body = pcall(function() return game:HttpGet(url) end)
            if ok and type(body) == "string" and #body >= 50 and not body:find("404: Not Found", 1, true) then
                return body
            end
        end
    end
    return nil
end

local function GetRandomPointInPart(Part)
    local Size = Part.Size
    local CFramePos = Part.CFrame
    local Rx = (math.random() - 0.5) * (Size.X * 0.9)
    local Ry = (math.random() - 0.5) * (Size.Y * 0.9)
    local Rz = (math.random() - 0.5) * (Size.Z * 0.9)
    return CFramePos * CFrame.new(Rx, Ry, Rz)
end

-- ==================== PAUSE SYSTEM ====================
local function CreatePauseButton()
    -- old right-side pause removed; use left panel (Pause / Zipline / Slide)
    return
end

local function DestroyPauseButton()
    if PauseButtonGui then
        PauseButtonGui:Destroy()
        PauseButtonGui = nil
    end
    if getgenv()._TAS_MobileGui then
        pcall(function() getgenv()._TAS_MobileGui:Destroy() end)
        getgenv()._TAS_MobileGui = nil
    end
    getgenv().TASPaused = false
end

local function TogglePauseManual()
    if not getgenv().IsTASPlaying then
        Alert("TAS is not currently playing!", "Warning")
        return
    end

    getgenv().TASPaused = not getgenv().TASPaused

    if PauseButtonGui and PauseButtonGui:FindFirstChild("PauseBtn") then
        local btn = PauseButtonGui.PauseBtn
        if getgenv().TASPaused then
            btn.Text = "▶"
            btn.BackgroundColor3 = Color3.fromRGB(0, 140, 60)
            Alert("TAS Paused", "Warning")
        else
            btn.Text = "⏸"
            btn.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
            Alert("TAS Resumed", "Success")
        end
    else
        if getgenv().TASPaused then
            Alert("TAS Paused", "Warning")
        else
            Alert("TAS Resumed", "Success")
        end
    end
end

-- ==============================================================================
-- [5] BUILT-IN TAS PLAYER (from newtasplayer.luau)
-- ==============================================================================
local function StartBuiltInTASPlayer()
    if getgenv().IsTASPlaying then return end
    
    local TimeModifier = State.TASSpeed or 1
    local DynamicTimeScale = 1
    local SwimSmoothness = 0.04
    local PausedCFrame = nil

    getgenv().IsTASPlaying = true
    getgenv().TASPaused = false
    getgenv().TAS_ManualStop = false
    getgenv().TASCurrentMoveDir = Vector3.new(0,0,0)

    local NewV = Vector3.new
    local NewC = CFrame.new
    local AngC = CFrame.fromEulerAnglesXYZ
    local LP = LocalPlayer
    local Multi = Workspace.Multiplayer
    local RS = RunService

    local Theme = {
        System = Color3.fromRGB(150, 150, 255),
        Info = Color3.fromRGB(220, 220, 220),
        Success = Color3.fromRGB(80, 220, 120),
        Warning = Color3.fromRGB(255, 170, 0),
        Error = Color3.fromRGB(255, 60, 60),
        Highlight = Color3.fromRGB(0, 200, 255)
    }

    local function Log(msg, category)
        local color = Theme[category] or Theme.Info
        local text = "[TAS] " .. msg
        print(text)
        if CLMAINenv and type(CLMAINenv.newAlert) == "function" then
            CLMAINenv.newAlert(text, color)
        end
    end

    Log("Built-in TAS Player started!", "System")

    -- // MAP EVENT LISTENER (speedup / slowdown) — from official Tomato V65 //
    task.spawn(function()
        local PlayerGui = LP:WaitForChild("PlayerGui", 10)
        local GameGui = PlayerGui and PlayerGui:WaitForChild("GameGui", 10)
        local HUD = GameGui and GameGui:WaitForChild("HUD", 10)
        local MapEventInfo = HUD and HUD:WaitForChild("MapEventInfo", 10)

        if MapEventInfo then
            AddTASConnection(MapEventInfo:GetPropertyChangedSignal("Text"):Connect(function()
                local currentText = MapEventInfo.Text
                local Events = {}
                for rawEventName in string.gmatch(currentText, ">(.-)</font>") do
                    local formattedEventName = string.lower(rawEventName):gsub("%s+", "")
                    table.insert(Events, formattedEventName)
                end

                if #Events > 0 then
                    DynamicTimeScale = 1
                    for _, eventName in ipairs(Events) do
                        if eventName == "speedup" then
                            DynamicTimeScale = DynamicTimeScale * (1 / 1.1225)
                        elseif eventName == "slowdown" then
                            DynamicTimeScale = DynamicTimeScale * (1 / (1 - 0.1091))
                        end
                    end
                    local speedMultiplier = 1 / DynamicTimeScale
                    Log(string.format("Map event! Game speed adjusted to %.2fx", speedMultiplier), "Highlight")
                end
            end))
            Log("Map event listener ready (speedup/slowdown).", "Info")
        end
    end)

    -- Water detection
    local WaterParts = {}
    local function CacheWaterParts(MapFolder)
        WaterParts = {}
        local attempts = 0
        repeat
            for _, v in pairs(MapFolder:GetDescendants()) do
                if v:IsA("BasePart") and (string.find(v.Name, "_Water") or v.Parent.Name == "Waters") then
                    if not table.find(WaterParts, v) then
                        table.insert(WaterParts, v)
                    end
                end
            end
            if #WaterParts == 0 then 
                attempts = attempts + 1
                task.wait(0.5) 
            end
        until #WaterParts > 0 or attempts > 10
    end

    local function IsInWater(Position)
        for _, water in pairs(WaterParts) do
            local halfSize = water.Size * 0.5
            local objSpace = water.CFrame:PointToObjectSpace(Position)
            if math.abs(objSpace.Y) <= halfSize.Y and math.abs(objSpace.X) <= halfSize.X and math.abs(objSpace.Z) <= halfSize.Z then
                local waterState = water:FindFirstChild("WaterState")
                if not waterState or waterState:GetAttribute("NoSwim") ~= true then
                    return true
                end
            end
        end
        return false
    end

    -- Animation
    if not LP.Character or not LP.Character:FindFirstChild("Animate") then
        LP.CharacterAdded:Wait()
        LP.Character:WaitForChild("Animate", 10)
    end

    local Animate, OriginalPlayAnim
    local SuccessHook = pcall(function()
        local AnimateScript = LP.Character.Animate
        Animate = getsenv(AnimateScript)
        OriginalPlayAnim = Animate.playAnimation
        
        getgenv().TAS_RestoreAnim = function()
            if Animate and OriginalPlayAnim then
                Animate.playAnimation = OriginalPlayAnim
            end
        end
    end)

    if not SuccessHook or not Animate then
        Log("Warning: Could not connect to the game's animation system.", "Warning")
        Animate = { setAnimationSpeed = function() end, playAnimation = function() end }
        OriginalPlayAnim = function() end
    end

    local function toggleSlide(newValue)
        if not LP.Character then return end
        if newValue == true then
            if LP.Character:FindFirstChild("HumanoidRootPart") then LP.Character.HumanoidRootPart.Size = NewV(2, 1, 1) end
            if LP.Character:FindFirstChild("FE2_Hitbox") then LP.Character.FE2_Hitbox.Size = NewV(2, 1, 1) end
            if LP.Character:FindFirstChild("Humanoid") then LP.Character.Humanoid.HipHeight = -1.5 end
        else
            if LP.Character:FindFirstChild("HumanoidRootPart") then LP.Character.HumanoidRootPart.Size = NewV(2, 2, 1) end
            if LP.Character:FindFirstChild("FE2_Hitbox") then LP.Character.FE2_Hitbox.Size = NewV(2, 2, 1) end
            if LP.Character:FindFirstChild("Humanoid") then LP.Character.Humanoid.HipHeight = 0 end
        end
        if LP.Character and LP.Character:FindFirstChild("Animate") and LP.Character.Animate:FindFirstChild("Sliding") then
            LP.Character.Animate.Sliding:Fire(newValue)
        end
    end

    if not getgenv().TASHookApplied then
        getgenv().TASHookApplied = true
        local oldIndex
        oldIndex = hookmetamethod(game, "__index", function(self, key)
            if getgenv().IsTASPlaying and key == "MoveDirection" then
                if self:IsA("Humanoid") and self.Parent == LP.Character then
                    return getgenv().TASCurrentMoveDir
                end
            end
            return oldIndex(self, key)
        end)
    end

    local LastPlayedAnim = nil
    local IsSliding = false
    local SlideStartTime = 0
    local LastSlideEndTime = -3.0
    local SLIDE_DEBOUNCE = 3.0
    local IsCurrentlySwimming = false
    local IsCurrentlyZiplining = false
    -- Manual key overrides (same as Tomato V65)
    local IsManualZipline = false
    local IsManualSlide = false

    local LiftCheckPos = Vector3.new(-25, -144, 139)
    local CleanedUp = false
    
    local RunMapName, RunStartedAt, RunDied = nil, 0, false

    local function Cleanup(resetCharacter)
        if CleanedUp then return end
        CleanedUp = true
        if RunMapName then
            local info = {
                map = RunMapName, startedAt = RunStartedAt,
                died = RunDied, manual = getgenv().TAS_ManualStop == true
            }
            RunMapName = nil
            task.spawn(RunStats.Finish, info)
        end
        pcall(function()
            if getgenv()._TAS_RestoreZiplines then getgenv()._TAS_RestoreZiplines() end
        end)
        getgenv().IsTASPlaying = false
        getgenv().TASPaused = false
        getgenv().TAS_Stop = nil
        
        IsSliding = false
        IsCurrentlyZiplining = false
        IsManualZipline = false
        IsManualSlide = false
        
        if getgenv().TASConnections then
            for _, connection in pairs(getgenv().TASConnections) do
                if connection then connection:Disconnect() end
            end
            getgenv().TASConnections = {}
        end

        if getgenv().TAS_RestoreAnim then
            pcall(getgenv().TAS_RestoreAnim)
            getgenv().TAS_RestoreAnim = nil
        end

        if LP.Character then
            if LP.Character:FindFirstChild("Animate") and LP.Character.Animate:FindFirstChild("ToggleSwim") then
                pcall(function() LP.Character.Animate.ToggleSwim:Fire(false) end)
            end
            if LP.Character:FindFirstChild("Humanoid") then LP.Character.Humanoid.AutoRotate = true end
            toggleSlide(false)
        end

        DestroyPauseButton()

        if resetCharacter and LP.Character and LP.Character:FindFirstChild("Humanoid") then
            Log("You reset or died. Halting the run...", "Error")
            QF.ResettingCharacter = true
            LP.Character.Humanoid.Health = 0
        end
    end

    getgenv().TAS_Stop = function()
        getgenv().TAS_ManualStop = true
        Cleanup(false)
        Log("TAS stopped manually.", "Warning")
    end

    if LP.Character and LP.Character:FindFirstChild("Humanoid") then
        AddTASConnection(LP.Character.Humanoid.Died:Connect(function() RunDied = true Cleanup(false) end))
    end
    AddTASConnection(LP.CharacterRemoving:Connect(function() Cleanup(false) end))

    -- Wait for map
    local Map = nil
    while not Map and not CleanedUp do
        local ConditionsMet = false
        Log("Waiting for you to step into the lift...", "Warning")
        
        repeat
            task.wait(0.2)
            local Root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if Root then
                local Dist = (Root.Position - LiftCheckPos).Magnitude
                if Dist <= 30 or Dist > 800 then ConditionsMet = true end
            end
        until ConditionsMet or CleanedUp
        
        if CleanedUp then return end
        Log("Lift entered! Waiting for the map to load.", "System")
        
        while ConditionsMet and not Map and not CleanedUp do
            task.wait(0.1)
            local FoundMap = Multi:FindFirstChild("NewMap")
            if FoundMap then 
                Map = FoundMap
                break 
            end
            
            local Root = LP.Character and LP.Character:FindFirstChild("HumanoidRootPart")
            if Root then
                local Dist = (Root.Position - LiftCheckPos).Magnitude
                if Dist > 30 and Dist < 800 then
                    Log("You left the lift! Pausing until you return.", "Warning")
                    ConditionsMet = false
                end
            end
        end
    end

    if CleanedUp or not Map then return end

    -- Load TAS
    local realMapName = Map:WaitForChild('Settings'):GetAttribute("MapName")
    local mapName = HttpService:UrlEncode(realMapName)

    if RunStats.IsBenched(CleanMapName(realMapName)) then
        Log("TAS for '" .. realMapName .. "' is benched after repeated failures. Skipping this map.", "Warning")
        Cleanup(true)
        return
    end

    local success, path
    if isfolder("Flood-GUI") and isfolder("Flood-GUI/TAS FILES") then
        local TargetTASPath = "Flood-GUI/TAS FILES/" .. realMapName .. ".json"
        if isfile(TargetTASPath) then path = readfile(TargetTASPath); success = true end
    end

    if not path then
        local prefetched = getgenv().TasDataCache[CleanMapName(realMapName)]
        if prefetched then path = prefetched; success = true end
    end

    if not path then
        success, path = pcall(function()
            return game:HttpGet("https://raw.githubusercontent.com/tomatotxt/Flood-GUI/refs/heads/testing/TAS%20FILES/".. mapName .. ".json")
        end)
        if not success or #path < 50 then
            local raw = FetchTasRaw(realMapName) -- also tries the other repo branch
            if raw then success, path = true, raw end
        end
    end

    if not success or #path < 50 then
        Log("Oops! We don't have a TAS file for '".. realMapName .."'.", "Error")
        Cleanup(true)
        return
    end

    local TAS
    local DecodeSuccess = pcall(function() TAS = HttpService:JSONDecode(path) end)
    if not TAS or not DecodeSuccess then
        Log("Uh oh, the TAS file for this map seems corrupted.", "Error")
        Cleanup(true)
        return
    end

    local OriginalFrameCount = #TAS
    Log("Loaded run for " .. realMapName .. " (" .. OriginalFrameCount .. " frames).", "Info")
    RunMapName, RunStartedAt = CleanMapName(realMapName), os.clock()
    repeat task.wait() until Map.Name == "Map" or CleanedUp
    if CleanedUp then return end

    local SpawnPoint = nil
    for _,v in ipairs(Map:GetChildren()) do
        if v.Name == "Part" then
            local c; c = v:GetPropertyChangedSignal("Rotation"):Connect(function() c:Disconnect(); SpawnPoint = v end)
        end
    end

    local t = 0
    repeat task.wait(0.1); t=t+0.1; if not SpawnPoint then SpawnPoint = Map:FindFirstChild("Spawn", true) end
    until SpawnPoint or t > 10 or CleanedUp

    if not SpawnPoint then Log("Hmm, couldn't find where to spawn on this map.", "Error") Cleanup(true) return end

    CacheWaterParts(Map)

    -- zipline disable helpers + call

    -- Disable real map ziplines so game physics doesn't fight TAS CFrame (camera shake fix)
    local DisabledZiplineParts = {}
    local function DisableMapZiplines(mapFolder)
        table.clear(DisabledZiplineParts)
        if not mapFolder then return end
        local nameHints = {
            zipline=true, zip=true, swing=true, rope=true, cable=true,
            zipstart=true, zipend=true, ziplinestart=true, ziplineend=true,
            zippoint=true, zippart=true, zipnode=true, zipattach=true,
        }
        for _, inst in ipairs(mapFolder:GetDescendants()) do
            local lname = string.lower(inst.Name)
            local hit = nameHints[lname]
            if not hit then
                for hint in pairs(nameHints) do
                    if string.find(lname, hint, 1, true) then hit = true break end
                end
            end
            if hit and inst:IsA("BasePart") then
                DisabledZiplineParts[#DisabledZiplineParts+1] = {
                    part = inst,
                    CanTouch = inst.CanTouch,
                    CanQuery = inst.CanQuery,
                    CanCollide = inst.CanCollide,
                }
                pcall(function()
                    inst.CanTouch = false
                    inst.CanQuery = false
                    -- keep CanCollide as-is usually; only block touch triggers
                end)
                -- kill touch transmitters if present
                for _, ch in ipairs(inst:GetChildren()) do
                    if ch.ClassName == "TouchTransmitter" then
                        pcall(function() ch:Destroy() end)
                    end
                end
            elseif hit and (inst:IsA("ProximityPrompt") or inst:IsA("ClickDetector")) then
                pcall(function() inst.Enabled = false end)
            end
        end
        Log(string.format("Disabled %d real zipline trigger(s) for TAS.", #DisabledZiplineParts), "Info")
    end
    local function RestoreMapZiplines()
        for _, info in ipairs(DisabledZiplineParts) do
            local p = info.part
            if p and p.Parent then
                pcall(function()
                    p.CanTouch = info.CanTouch
                    p.CanQuery = info.CanQuery
                    p.CanCollide = info.CanCollide
                end)
            end
        end
        table.clear(DisabledZiplineParts)
        getgenv()._TAS_RestoreZiplines = nil
    end
    getgenv()._TAS_RestoreZiplines = RestoreMapZiplines

    DisableMapZiplines(Map)

    for _, v in next, Map:GetDescendants() do
        if v.Name == 'ButtonIcon' then
            pcall(function()
                local p = v.Parent.Parent:FindFirstChildOfClass('Part')
                if p then p.Size = NewV(7, 7, 7) p.Transparency = 1 end
            end)
        end
    end
    Log("Map buttons and elements processed.", "Success")

    task.wait(0.1)
    Log("Starting the run! Panel: Pause / Zipline / Slide (Z / S).", "Success")
    CreatePauseButton() -- no-op (right pause removed)

    -- Black/red control panel: Pause + Hold Zipline + Hold Slide
    do
        local UIS = UserInputService
        AddTASConnection(UIS.InputBegan:Connect(function(input, gpe)
            if not getgenv().IsTASPlaying then return end
            if UIS:GetFocusedTextBox() then return end
            if input.KeyCode == Enum.KeyCode.Z then
                IsManualZipline = true
                IsCurrentlyZiplining = true
                if IsSliding then toggleSlide(false); IsSliding = false end
                LastPlayedAnim = nil
            elseif input.KeyCode == Enum.KeyCode.S then
                IsManualSlide = true
                toggleSlide(true)
                IsSliding = true
                LastPlayedAnim = nil
            elseif input.KeyCode == Enum.KeyCode.P then
                getgenv().TASPaused = not getgenv().TASPaused
                Alert(getgenv().TASPaused and "TAS Paused" or "TAS Resumed", getgenv().TASPaused and "Warning" or "Success")
            end
        end))
        AddTASConnection(UIS.InputEnded:Connect(function(input)
            if input.KeyCode == Enum.KeyCode.Z then
                IsManualZipline = false
                IsCurrentlyZiplining = false
                LastPlayedAnim = nil
                local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                if hum then
                    pcall(function()
                        hum.PlatformStand = false
                        hum:ChangeState(Enum.HumanoidStateType.Running)
                    end)
                end
            elseif input.KeyCode == Enum.KeyCode.S then
                IsManualSlide = false
                toggleSlide(false)
                IsSliding = false
                LastPlayedAnim = nil
            end
        end))

        local parentGui = LP:FindFirstChild("PlayerGui") or game:GetService("CoreGui")
        if getgenv()._TAS_MobileGui then pcall(function() getgenv()._TAS_MobileGui:Destroy() end) end
        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = "TAS_MobileControls"
        ScreenGui.ResetOnSpawn = false
        ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        pcall(function() ScreenGui.Parent = parentGui end)
        if not ScreenGui.Parent then pcall(function() ScreenGui.Parent = game:GetService("CoreGui") end) end
        getgenv()._TAS_MobileGui = ScreenGui

        local MobileFrame = Instance.new("Frame")
        MobileFrame.Name = "MobileControls"
        MobileFrame.Size = UDim2.new(0, 160, 0, 160)
        MobileFrame.Position = UDim2.new(0.02, 0, 0.35, 0)
        MobileFrame.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
        MobileFrame.BackgroundTransparency = 0.2
        MobileFrame.BorderSizePixel = 0
        MobileFrame.Parent = ScreenGui
        Instance.new("UICorner", MobileFrame).CornerRadius = UDim.new(0, 10)

        local UIListLayout = Instance.new("UIListLayout", MobileFrame)
        UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
        UIListLayout.Padding = UDim.new(0, 8)
        UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        UIListLayout.VerticalAlignment = Enum.VerticalAlignment.Center

        local function CreateMobileButton(name, text)
            local btn = Instance.new("TextButton")
            btn.Name = name
            btn.Size = UDim2.new(0.88, 0, 0, 40)
            btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            btn.Text = text
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 14
            btn.AutoButtonColor = true
            btn.Parent = MobileFrame
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
            local st = Instance.new("UIStroke")
            st.Color = Color3.fromRGB(180, 0, 20)
            st.Thickness = 1
            st.Parent = btn
            return btn
        end

        local pauseBtn = CreateMobileButton("PauseBtn", "Pause / Resume")
        local ziplineBtn = CreateMobileButton("ZiplineBtn", "Hold: Zipline")
        local slideBtn = CreateMobileButton("SlideBtn", "Hold: Slide")

        pauseBtn.Activated:Connect(function()
            if not getgenv().IsTASPlaying then return end
            getgenv().TASPaused = not getgenv().TASPaused
            Alert(getgenv().TASPaused and "TAS Paused" or "TAS Resumed", getgenv().TASPaused and "Warning" or "Success")
        end)

        ziplineBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                IsManualZipline = true
                IsCurrentlyZiplining = true
                if IsSliding then toggleSlide(false); IsSliding = false end
                LastPlayedAnim = nil
                ziplineBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            end
        end)
        ziplineBtn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                IsManualZipline = false
                IsCurrentlyZiplining = false
                LastPlayedAnim = nil
                ziplineBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
                local hum = LP.Character and LP.Character:FindFirstChildOfClass("Humanoid")
                if hum then
                    pcall(function()
                        hum.PlatformStand = false
                        hum:ChangeState(Enum.HumanoidStateType.Running)
                    end)
                end
            end
        end)

        slideBtn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                IsManualSlide = true
                toggleSlide(true)
                IsSliding = true
                LastPlayedAnim = nil
                slideBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
            end
        end)
        slideBtn.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                IsManualSlide = false
                toggleSlide(false)
                IsSliding = false
                LastPlayedAnim = nil
                slideBtn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
            end
        end)
    end

    local RootPart = LP.Character:WaitForChild("HumanoidRootPart", 10)
    local Humanoid = LP.Character:WaitForChild("Humanoid", 10)

    while (RootPart.Anchored == true) or (Humanoid.WalkSpeed <= 0) do
        if CleanedUp then return end
        task.wait()
    end

    local DelayedMaps = {
        ["Abandoned Harbour"] = true,
        ["Wildwood Waterways"] = true,
        ["Minds of Misery"] = true,
    }
    local MapStartDelay = 0
    if DelayedMaps[realMapName] then
        MapStartDelay = 0.8
        Log("Map delay active: waiting 0.7s before playback...", "Warning")
        task.wait(0.7)
    end

    if LP.Character and LP.Character:FindFirstChild("Humanoid") then
        LP.Character.Humanoid.AutoRotate = false
    end

    Animate.playAnimation = function() end

    -- 1:1 Tomato V65 activateAnimation (zipline/swing + slide)
    local function activateAnimation(AnimData, Elapsed)
        local character = LP.Character
        if not character or not character.Parent then return end
        local head = character:FindFirstChild("Head")
        local humanoid = character:FindFirstChild("Humanoid")
        if not head or not humanoid or not RootPart then return end

        local n = AnimData and AnimData[1] or nil
        local animTime = AnimData and AnimData[2] or 0.1
        Elapsed = Elapsed or 0

        local checkSubmerged = IsInWater(RootPart.Position + Vector3.new(0, 1, 0))
        -- TAS safety: a recorded swim animation is valid only while the character
        -- is actually in water. This prevents stale/incorrect TAS frames from
        -- forcing the swim animation while airborne or on solid ground.
        local humanoidState = humanoid:GetState()
        local actuallySwimming = checkSubmerged or humanoidState == Enum.HumanoidStateType.Swimming

        -- TAS state validation: FE2 can briefly report Climbing while the player
        -- is being moved by a wall-jump pad/weld. Do not let that transient state
        -- force the climbing animation.
        local walljumpWeld = RootPart:FindFirstChild("WalljumpWeld_Live")
            or RootPart:FindFirstChild("WalljumpWeld_Server")
        local walljumpFlag = getgenv().TAS_WalljumpActive == true

        local function nearClimbSurface()
            if walljumpWeld then return false end
            local ok, parts = pcall(function()
                return workspace:GetPartBoundsInRadius(RootPart.Position, 3.5)
            end)
            if not ok or type(parts) ~= "table" then return false end
            for _, part in ipairs(parts) do
                if part and part:IsA("BasePart") and part ~= RootPart then
                    if part:IsA("TrussPart") then
                        return true
                    end
                    local lowerName = string.lower(part.Name)
                    if string.find(lowerName, "truss", 1, true) or string.find(lowerName, "ladder", 1, true) then
                        return true
                    end
                    -- FE2 custom climb/wall objects commonly expose _Wall.
                    if part:FindFirstChild("_Wall") then
                        return true
                    end
                end
            end
            return false
        end

        local actuallyClimbing = humanoidState == Enum.HumanoidStateType.Climbing
            and not walljumpWeld
            and not walljumpFlag
            and nearClimbSurface()

        -- RIGOR.json records the wall-jump-pad state as `wallhang`. In the
        -- original TAS data these frames have zero velocity and occur at wall-jump
        -- contact points. A plain Roblox wall/Climbing state is not enough to
        -- justify playing wallhang, because FE2 can transiently reuse Climbing
        -- while a wall-jump pad is launching the player.
        local function nearWalljumpSurface()
            if walljumpWeld or walljumpFlag then
                return true
            end
            local ok, parts = pcall(function()
                return workspace:GetPartBoundsInRadius(RootPart.Position, 4.5)
            end)
            if not ok or type(parts) ~= "table" then return false end
            for _, part in ipairs(parts) do
                if part and part:IsA("BasePart") and part ~= RootPart then
                    local lowerName = string.lower(part.Name)
                    if part:FindFirstChild("_Wall")
                        or string.find(lowerName, "walljump", 1, true)
                        or string.find(lowerName, "wall_jump", 1, true)
                        or string.find(lowerName, "wall pad", 1, true)
                        or string.find(lowerName, "wallpad", 1, true) then
                        return true
                    end
                end
            end
            return false
        end

        local actuallyWallHanging = nearWalljumpSurface()
            and RootPart.Velocity.Magnitude <= 3.5
            and humanoidState ~= Enum.HumanoidStateType.Swimming

        local function fallbackMovementAnimation()
            if humanoid.FloorMaterial == Enum.Material.Air then
                return "fall"
            elseif RootPart.Velocity.Magnitude > 1 then
                return "walk"
            else
                return "idle"
            end
        end

        if (n == "swim" or n == "swimidle") and not actuallySwimming then
            n = nil
            IsCurrentlySwimming = false
            if character:FindFirstChild("Animate") and character.Animate:FindFirstChild("ToggleSwim") then
                pcall(function() character.Animate.ToggleSwim:Fire(false) end)
            end
            if humanoid.FloorMaterial == Enum.Material.Air then
                n = "fall"
            elseif RootPart.Velocity.Magnitude > 1 then
                n = "walk"
            else
                n = "idle"
            end
        end

        local gameSpeedMultiplier = TimeModifier * DynamicTimeScale
        local nativeSlideDuration = 0.5 / gameSpeedMultiplier

        -- MANUAL KEY OVERRIDES (Z = Zipline/Swing, S = Slide)
        if IsManualZipline then
            n = "swing"
            IsCurrentlyZiplining = true
            if IsSliding then
                toggleSlide(false)
                IsSliding = false
            end
            -- early play + return so swim/walk cannot overwrite (same fix as V3)
            if LastPlayedAnim ~= "swing" then
                -- no Physics state: Physics + hard CFrame = shake
                Animate.playAnimation = function() end
                pcall(OriginalPlayAnim, "swing", animTime, humanoid)
                pcall(OriginalPlayAnim, "zipline", animTime, humanoid)
                LastPlayedAnim = "swing"
            end
            return
        elseif IsManualSlide then
            n = "slide"
            IsSliding = true
            if LastPlayedAnim ~= "slide" then
                toggleSlide(true)
                Animate.playAnimation = function() end
                pcall(OriginalPlayAnim, "slide", animTime, humanoid)
                LastPlayedAnim = "slide"
            end
            return
        end

        -- Zipline/Swing Priority — keep TAS name (zipline OR swing), do not force-rename
        if n == "zipline" or n == "swing" then
            IsCurrentlyZiplining = true
            if IsSliding then
                toggleSlide(false)
                IsSliding = false
                LastSlideEndTime = Elapsed
            end
        end

        -- Exit zipline only when grounded AND this frame is not still zipline/swing
        if humanoid.FloorMaterial ~= Enum.Material.Air and not IsManualZipline then
            if n ~= "zipline" and n ~= "swing" then
                IsCurrentlyZiplining = false
            end
        end

        -- 1. SLIDE LOCK (nativeSlideDuration, unless Zipline or Manual Slide)
        -- Cancel slide immediately if airborne (unless player holds manual slide)
        if IsSliding and not IsManualSlide and humanoid.FloorMaterial == Enum.Material.Air then
            toggleSlide(false)
            IsSliding = false
            LastSlideEndTime = Elapsed
            n = "fall"
        end
        if IsSliding then
            if not IsManualSlide and (Elapsed - SlideStartTime >= nativeSlideDuration) then
                toggleSlide(false)
                IsSliding = false
                LastSlideEndTime = Elapsed
                if checkSubmerged then
                    IsCurrentlySwimming = true
                    if character.Animate:FindFirstChild("ToggleSwim") then
                        pcall(function() character.Animate.ToggleSwim:Fire(true) end)
                    end
                    if RootPart.Velocity.Magnitude > 1.5 then n = "swim" else n = "swimidle" end
                else
                    IsCurrentlySwimming = false
                    if character.Animate:FindFirstChild("ToggleSwim") then
                        pcall(function() character.Animate.ToggleSwim:Fire(false) end)
                    end
                    if humanoid.FloorMaterial == Enum.Material.Air then
                        n = "fall"
                    elseif RootPart.Velocity.Magnitude > 1 then
                        n = "walk"
                    else
                        n = "idle"
                    end
                end
            else
                n = "slide"
            end
        else
            -- 2. NORMAL STATES (when not sliding)
            if checkSubmerged then
                IsCurrentlySwimming = true
                if RootPart.Velocity.Magnitude > 1.5 then n = "swim" else n = "swimidle" end
                if character.Animate:FindFirstChild("ToggleSwim") then
                    pcall(function() character.Animate.ToggleSwim:Fire(true) end)
                end
            else
                IsCurrentlySwimming = false
                if character.Animate:FindFirstChild("ToggleSwim") then
                    pcall(function() character.Animate.ToggleSwim:Fire(false) end)
                end

                if not IsCurrentlyZiplining then
                    if n == "slide" then
                        local absYVel = math.abs(RootPart.Velocity.Y)
                        local canSlide = IsManualSlide or (
                            Elapsed - LastSlideEndTime >= SLIDE_DEBOUNCE
                            and absYVel <= 2
                            and humanoid.FloorMaterial ~= Enum.Material.Air
                            and humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
                            and humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
                        )
                        if canSlide then
                            toggleSlide(true)
                            IsSliding = true
                            SlideStartTime = Elapsed
                            n = "slide"
                        else
                            if humanoid.FloorMaterial == Enum.Material.Air then
                                n = "fall"
                            elseif RootPart.Velocity.Magnitude > 1 then
                                n = "walk"
                            else
                                n = "idle"
                            end
                        end
                    end
                end

                if not AnimData and not IsSliding and not IsManualZipline and not IsManualSlide then
                    return
                end

                if not IsSliding and not IsCurrentlyZiplining then
                    if humanoid:GetState() == Enum.HumanoidStateType.Physics then n = "swing" end
                    if n == "idle" or not n then
                        if RootPart.Velocity.Magnitude > 1 then
                            if humanoid.FloorMaterial ~= Enum.Material.Air then n = "walk" else n = "fall" end
                        else
                            n = "idle"
                        end
                    end
                    if n == "fall" and RootPart.Velocity.Magnitude < 0.1 then n = "swing" end
                end
            end
        end

        -- Final hard guard: never send a swim animation to the animator unless
        -- the current frame is actually swimming.
        if (n == "swim" or n == "swimidle") and not actuallySwimming then
            n = fallbackMovementAnimation()
            IsCurrentlySwimming = false
            if character:FindFirstChild("Animate") and character.Animate:FindFirstChild("ToggleSwim") then
                pcall(function() character.Animate.ToggleSwim:Fire(false) end)
            end
        end

        -- Final hard guard for climbing and wall-jump-pad animation states.
        if n == "climb" or n == "climbing" then
            if not actuallyClimbing then
                n = fallbackMovementAnimation()
            end
        elseif n == "wallhang" then
            if not actuallyWallHanging then
                n = fallbackMovementAnimation()
            end
        elseif humanoidState == Enum.HumanoidStateType.Climbing and (walljumpWeld or walljumpFlag) then
            -- Wall-jump movement is launch/contact movement, not a climb animation.
            n = fallbackMovementAnimation()
        end

        if n and (n ~= LastPlayedAnim) then
            Animate.playAnimation = function() end
            -- FE2 accepts both "zipline" and "swing"; try recorded name, fallback the other
            pcall(function()
                OriginalPlayAnim(n, animTime, humanoid)
                if n == "zipline" then
                    -- some FE2 builds only register swing
                    pcall(OriginalPlayAnim, "swing", animTime, humanoid)
                elseif n == "swing" then
                    pcall(OriginalPlayAnim, "zipline", animTime, humanoid)
                end
            end)
            if n == "walk" then pcall(function() Animate.setAnimationSpeed(.76) end) end
            LastPlayedAnim = n
        end
    end

    local Offset = SpawnPoint.Position - NewV(0, 1000, 0)
    local OldFrame = 3
    local RenderedFrames = 0
    local FinishedRun = false
    local SmoothSwimDirection = nil
    local VisualElapsed = 0
    local LastClock = os.clock()

    -- // AUTO SYNC (HUD timer) — pause-aware; DISABLED while custom speed //
    local LastSyncTime = os.clock()
    local SyncInterval = 3
    local SyncThreshold = 0.05
    local PausedGameTimeAccum = 0
    local PauseTimerAnchor = nil
    local SyncResumeGraceUntil = 0
    local AutoSyncEnabled = true -- flipped off permanently if custom speed is used
    local AutoSyncDisabledLogged = false

    local function GetGameTimer()
        local ok, result = pcall(function()
            return LP.PlayerGui.GameGui.HUD.Main.GameStats.Ingame.Info.Time.Current.Count.Text
        end)
        if not ok or not result then return nil end
        local min, sec = tostring(result):match("(%d+):(%d+%.%d+)")
        if min and sec then
            return tonumber(min) * 60 + tonumber(sec)
        end
        min, sec = tostring(result):match("(%d+):(%d+)")
        if min and sec then
            return tonumber(min) * 60 + tonumber(sec)
        end
        return nil
    end

    local function IsCustomSpeedActive()
        local s = tonumber(State.TASSpeed) or 1
        local t = tonumber(TimeModifier) or 1
        return math.abs(s - 1) > 0.001 or math.abs(t - 1) > 0.001
    end

    local function TrySync()
        if not AutoSyncEnabled then return end
        if getgenv().TASPaused then return end
        if os.clock() < SyncResumeGraceUntil then return end

        -- Custom speed must never be overwritten by HUD timer
        if IsCustomSpeedActive() then
            AutoSyncEnabled = false
            if not AutoSyncDisabledLogged then
                AutoSyncDisabledLogged = true
                Log("Auto-sync OFF (custom TAS speed active)", "Warning")
            end
            return
        end

        -- Map event timescale active → don't fight it
        if math.abs((DynamicTimeScale or 1) - 1) > 0.02 then return end

        local gameTimer = GetGameTimer()
        if not gameTimer or gameTimer < 0.15 then return end

        local adjustedTimer = gameTimer - MapStartDelay - PausedGameTimeAccum
        if adjustedTimer < 0 then adjustedTimer = 0 end

        local drift = VisualElapsed - adjustedTimer
        if math.abs(drift) > SyncThreshold then
            VisualElapsed = VisualElapsed - drift
            if VisualElapsed < 0 then VisualElapsed = 0 end
            Log(string.format("Auto-sync: corrected %.3fs drift.", drift), "Warning")
        end
    end

    -- MAIN LOOP WITH PAUSE
    local MainLoop
    MainLoop = RS.Heartbeat:Connect(function()
        if not RootPart or not RootPart.Parent or not Humanoid or not Humanoid.Parent or CleanedUp then 
            if MainLoop then MainLoop:Disconnect() end
            if not CleanedUp then
                Log("Player removed from game. Halting the run.", "Warning")
                Cleanup(false) 
            end
            return 
        end

        -- PAUSE HANDLING
        if getgenv().TASPaused then
            if not PausedCFrame then
                PausedCFrame = RootPart.CFrame
                -- Anchor HUD timer so pause doesn't count as TAS drift
                PauseTimerAnchor = GetGameTimer()
                IsCurrentlyZiplining = false
                IsSliding = false
                toggleSlide(false)
                LastPlayedAnim = "idle"
                pcall(function()
                    OriginalPlayAnim("idle", 0.1, Humanoid)
                end)
            end
            -- Stay completely still
            RootPart.CFrame = PausedCFrame
            RootPart.Velocity = Vector3.zero
            RootPart.AssemblyLinearVelocity = Vector3.zero
            RootPart.AssemblyAngularVelocity = Vector3.zero
            RootPart.RotVelocity = Vector3.zero
            getgenv().TASCurrentMoveDir = Vector3.zero
            LastClock = os.clock()
            return
        else
            if PausedCFrame then
                -- Account for HUD time that passed while paused (prevents teleport on unpause)
                local nowTimer = GetGameTimer()
                if PauseTimerAnchor and nowTimer then
                    local pausedAmount = nowTimer - PauseTimerAnchor
                    if pausedAmount > 0 then
                        PausedGameTimeAccum = PausedGameTimeAccum + pausedAmount
                    end
                end
                PauseTimerAnchor = nil
                SyncResumeGraceUntil = os.clock() + 1.5 -- no sync for 1.5s after resume

                IsCurrentlyZiplining = false
                IsSliding = false
                IsCurrentlySwimming = false
                LastPlayedAnim = nil
                Humanoid.PlatformStand = false
                Humanoid:ChangeState(Enum.HumanoidStateType.Running)
                toggleSlide(false)
                pcall(function()
                    if LP.Character and LP.Character:FindFirstChild("Animate") and LP.Character.Animate:FindFirstChild("ToggleSwim") then
                        LP.Character.Animate.ToggleSwim:Fire(false)
                    end
                    OriginalPlayAnim("walk", 0.1, Humanoid)
                    if Animate and Animate.setAnimationSpeed then
                        Animate.setAnimationSpeed(0.76)
                    end
                    LastPlayedAnim = "walk"
                end)
            end
            PausedCFrame = nil
        end

        -- Live speed update from GUI textbox
        TimeModifier = State.TASSpeed or 1
        
        RenderedFrames = RenderedFrames + 1
        
        local CurrentClock = os.clock()
        local Delta = CurrentClock - LastClock
        LastClock = CurrentClock
        
        VisualElapsed = VisualElapsed + (Delta * (1 / (TimeModifier * DynamicTimeScale)))

        -- Auto-sync to in-game HUD timer every few seconds
        if os.clock() - LastSyncTime >= SyncInterval then
            LastSyncTime = os.clock()
            TrySync()
        end
        
        -- Capture the wall-jump-pad state before the TAS loop removes FE2's
        -- wall-jump welds. The animation validator uses this for the same frame.
        local liveWeld = RootPart:FindFirstChild("WalljumpWeld_Live")
        local serverWeld = RootPart:FindFirstChild("WalljumpWeld_Server")
        getgenv().TAS_WalljumpActive = (liveWeld ~= nil or serverWeld ~= nil)
        if liveWeld then liveWeld:Destroy() end
        if serverWeld then serverWeld:Destroy() end
        -- break any live zipline constraints the game tried to attach
        for _, ch in ipairs(RootPart:GetChildren()) do
            if ch:IsA("Weld") or ch:IsA("WeldConstraint") or ch:IsA("RigidConstraint") or ch:IsA("RopeConstraint") or ch:IsA("RodConstraint") or ch:IsA("SpringConstraint") then
                local n = string.lower(ch.Name)
                if string.find(n, "zip", 1, true) or string.find(n, "swing", 1, true) or string.find(n, "rope", 1, true) then
                    pcall(function() ch:Destroy() end)
                end
            end
        end

        
        while OldFrame < #TAS and TAS[OldFrame + 1].time <= VisualElapsed do OldFrame = OldFrame + 1 end
        
        if OldFrame >= #TAS then
            if not FinishedRun then
                FinishedRun = true
                Log("Run completed — waiting 0.5s then stop.", "Success")
                Alert("TAS finished map…", "Success")
                if getgenv().TAS_RestoreAnim then 
                    pcall(getgenv().TAS_RestoreAnim)
                    getgenv().TAS_RestoreAnim = nil
                end
                pcall(function() OriginalPlayAnim("idle", 0.1, Humanoid) end)
                -- delay so end of map feels natural; do NOT set TAS_ManualStop (AutoPlay can restart)
                task.delay(0.5, function()
                    if not CleanedUp then
                        getgenv().TAS_ManualStop = false
                        Cleanup(false)
                        Alert("TAS stopped (map done).", "Success")
                    end
                end)
            end
            return
        end

        -- Stop when game reports escape (with short delay)
        if State.Escaped then
            if not FinishedRun then
                FinishedRun = true
                Log("Map escaped — stopping TAS in 0.5s.", "Success")
                task.delay(0.5, function()
                    if not CleanedUp then
                        getgenv().TAS_ManualStop = false
                        Cleanup(false)
                        Alert("Map completed — TAS stopped.", "Success")
                    end
                end)
            end
            return
        end
        -- Exit region: only when very close, then delay stop
        do
            local exitPart = Map and (Map:FindFirstChild("ExitRegion", true) or Map:FindFirstChild("Exit", true))
            if exitPart and RootPart then
                local ep = exitPart:IsA("BasePart") and exitPart or exitPart:FindFirstChildWhichIsA("BasePart", true)
                if ep and (RootPart.Position - ep.Position).Magnitude < 8 then
                    if not FinishedRun then
                        FinishedRun = true
                        Log("Reached exit — stopping TAS in 0.5s.", "Success")
                        task.delay(0.5, function()
                            if not CleanedUp then
                                getgenv().TAS_ManualStop = false
                                Cleanup(false)
                                Alert("Exit reached — TAS stopped.", "Success")
                            end
                        end)
                    end
                    return
                end
            end
        end

        local FA = TAS[OldFrame]
        local FB = TAS[OldFrame + 1] or FA
        
        local Dur = FB.time - FA.time
        local Alpha = (Dur > 0) and math.clamp((VisualElapsed - FA.time) / Dur, 0, 1) or 0

        local cfA = NewC(FA.CCFrame[1], FA.CCFrame[2], FA.CCFrame[3]) * AngC(FA.CCFrame[4], FA.CCFrame[5], FA.CCFrame[6])
        local cfB = NewC(FB.CCFrame[1], FB.CCFrame[2], FB.CCFrame[3]) * AngC(FB.CCFrame[4], FB.CCFrame[5], FB.CCFrame[6])
        
        local vA = NewV(FA.VVelocity[1], FA.VVelocity[2], FA.VVelocity[3])
        local vB = NewV(FB.VVelocity[1], FB.VVelocity[2], FB.VVelocity[3])

        local TargetVelocity = vA:Lerp(vB, Alpha)
        getgenv().TASCurrentMoveDir = TargetVelocity.Magnitude > 0 and TargetVelocity.Unit or Vector3.zero

        local TargetCFrame = cfA:Lerp(cfB, Alpha) + Offset
        
        local OverrideToSlide = false
        -- NEVER force slide while airborne
        local grounded = Humanoid.FloorMaterial ~= Enum.Material.Air
            and Humanoid:GetState() ~= Enum.HumanoidStateType.Freefall
            and Humanoid:GetState() ~= Enum.HumanoidStateType.Jumping
        if grounded then
            local startPos = TargetCFrame.Position + Vector3.new(0, 1.5, 0)
            local direction = Vector3.new(0, -4.5, 0)
            local raycastParams = RaycastParams.new()
            raycastParams.FilterType = Enum.RaycastFilterType.Exclude
            raycastParams.FilterDescendantsInstances = { LP.Character }
            local result = workspace:Raycast(startPos, direction, raycastParams)
            if result then
                local gap = TargetCFrame.Position.Y - result.Position.Y
                -- tight ground contact only
                if gap < 1.35 and TargetVelocity.Y <= 1.5 and math.abs(TargetVelocity.Y) < 8 then
                    OverrideToSlide = true
                end
            end
        end

        local AnimData = FA.AAnimation
        local onZipline = IsCurrentlyZiplining
            or IsManualZipline
            or (AnimData and (AnimData[1] == "zipline" or AnimData[1] == "swing"))

        -- Zipline/swing: pure CFrame, kill physics fight (stops local + replicated camera shake)
        if onZipline then
            SmoothSwimDirection = nil
            pcall(function()
                Humanoid.PlatformStand = false
                Humanoid.AutoRotate = false
                if Humanoid:GetState() == Enum.HumanoidStateType.Physics then
                    Humanoid:ChangeState(Enum.HumanoidStateType.Running)
                end
            end)
            RootPart.CFrame = TargetCFrame
            RootPart.Velocity = Vector3.zero
            pcall(function()
                RootPart.AssemblyLinearVelocity = Vector3.zero
                RootPart.AssemblyAngularVelocity = Vector3.zero
            end)
        elseif IsCurrentlySwimming and TargetVelocity.Magnitude > 0.5 then
            if not SmoothSwimDirection then
                SmoothSwimDirection = TargetVelocity.Unit
            else
                SmoothSwimDirection = SmoothSwimDirection:Lerp(TargetVelocity.Unit, SwimSmoothness).Unit
            end
            RootPart.CFrame = NewC(TargetCFrame.Position, TargetCFrame.Position + SmoothSwimDirection)
            RootPart.Velocity = TargetVelocity
        else
            SmoothSwimDirection = nil
            RootPart.CFrame = TargetCFrame
            RootPart.Velocity = TargetVelocity
        end

        local airborne = Humanoid.FloorMaterial == Enum.Material.Air
            or Humanoid:GetState() == Enum.HumanoidStateType.Freefall
            or Humanoid:GetState() == Enum.HumanoidStateType.Jumping

        -- V65 heuristic slide only on ground
        if OverrideToSlide and grounded and not IsCurrentlyZiplining and (not AnimData or (AnimData[1] ~= "zipline" and AnimData[1] ~= "swing")) then
            AnimData = { "slide", 0.1 }
        end

        -- Kill recorded/heuristic slide while in air → fall instead
        if airborne and AnimData and AnimData[1] == "slide" then
            AnimData = { "fall", 0.1 }
            if IsSliding and not IsManualSlide then
                toggleSlide(false)
                IsSliding = false
            end
        end

        pcall(activateAnimation, AnimData, VisualElapsed)
    end)
    AddTASConnection(MainLoop)
end

-- ==============================================================================
-- [6] AUTO FARM
-- ==============================================================================
-- Quick farm logic adapted from tomato.txt's "quickfarm" script (Flood-GUI repo).
-- Presses buttons through the PressedMapButton remote and escapes through the
-- Survived remote with the server passkey.
local debug_getupvalue = (debug and debug.getupvalue) or getupvalue
local debug_setupvalue = (debug and debug.setupvalue) or setupvalue

-- Executors disagree on getupvalue: some return (name, value), others just the value
local function GetUpvalueValue(fn, idx)
    if not debug_getupvalue or type(fn) ~= "function" then return false, nil end
    local res = table.pack(pcall(debug_getupvalue, fn, idx))
    if not res[1] then return false, nil end
    local returned = res.n - 1
    if returned >= 2 then return true, res[3] end
    if returned == 1 then return true, res[2] end
    return false, nil
end

local function ResolveToInstance(val)
    if typeof(val) == "Instance" then
        return val
    elseif type(val) == "table" then
        for _, item in pairs(val) do
            local resolved = ResolveToInstance(item)
            if resolved then return resolved end
        end
    end
    return nil
end

QF.Session = {}
getgenv().FloodGUI_QFSession = QF.Session
getgenv().FloodGUI_FastLoad = false

-- Hooks (installed once per game session; they read getgenv flags so re-running never stacks them)
function QF.InstallHooks()
    pcall(function()
        if not CLMAINenv then return end
        local env = getgenv()
        local hookfn = hookfunction or replaceclosure

        -- Detect the exit alert from the game's own UI, without our alerts triggering it
        if CLMAINenv.newAlert then
            env.FloodGUI_OrigNewAlert = env.FloodGUI_OrigNewAlert or CLMAINenv.newAlert
            QF.OrigNewAlert = env.FloodGUI_OrigNewAlert
            CLMAINenv.newAlert = function(Text, ...)
                local textStr = tostring(Text):lower()
                if QF.ExitPhase and (textStr:find("escape") or textStr:find("survive") or textStr:find("drown")) then
                    QF.Escaped = true
                end
                return QF.OrigNewAlert(Text, ...)
            end
        end

        -- Fast Load
        if hookfn and CLMAINenv.updGameState and not env.FloodGUI_FastLoadHooked then
            env.FloodGUI_FastLoadHooked = true
            local origUpd
            origUpd = hookfn(CLMAINenv.updGameState, function(newState, mapData, mapIndex)
                if newState == "loading" and env.FloodGUI_FastLoad then
                    if type(mapData) == "table" then
                        mapData.assetCount = 1
                    end
                    local valid, loadingUI = GetUpvalueValue(origUpd, 16)
                    if valid and typeof(loadingUI) == "Instance" and loadingUI:IsA("GuiObject") then
                        loadingUI.Visible = false
                    end
                end
                return origUpd(newState, mapData, mapIndex)
            end)
            env.FloodGUI_OrigUpdGameState = origUpd
        end
        QF.OrigUpd = env.FloodGUI_OrigUpdGameState

        if hookfn and CLMAINenv.screenFade and not env.FloodGUI_ScreenFadeHooked then
            env.FloodGUI_ScreenFadeHooked = true
            local origFade
            origFade = hookfn(CLMAINenv.screenFade, function(...)
                if env.FloodGUI_FastLoad then
                    local lighting = game:GetService("Lighting")
                    local blur = lighting:FindFirstChild("Fade_Blur")
                    if blur then blur.Enabled = false end
                    local colorCorrection = lighting:FindFirstChild("Fade_ColorCorrection")
                    if colorCorrection then colorCorrection.Enabled = false end
                    return
                end
                return origFade(...)
            end)
        end
    end)
end

-- Finds the boolean upvalues of updGameState (the local "already escaping" locks)
function QF.CacheGameScriptState()
    local candidates = {}
    local env = CLMAINenv
    if env and env.updGameState then candidates[#candidates + 1] = env.updGameState end
    if QF.OrigUpd then candidates[#candidates + 1] = QF.OrigUpd end

    for _, fn in ipairs(candidates) do
        local indices = {}
        for i = 1, 150 do
            local valid, value = GetUpvalueValue(fn, i)
            if valid and type(value) == "boolean" then
                indices[#indices + 1] = i
            end
        end
        if #indices > 0 then
            QF.UpdTarget, QF.LockIndices = fn, indices
            return
        end
    end
    QF.UpdTarget, QF.LockIndices = candidates[1], {}
end

function QF.SafeReset()
    QF.ResettingCharacter = true -- lets a reset through even when God Mode is on
    pcall(function()
        local hum = GetChar():FindFirstChildOfClass("Humanoid")
        if hum then hum.Health = 0 end
    end)
end

function QF.SetNoclip(on)
    if QF.NoclipConn then
        QF.NoclipConn:Disconnect()
        QF.NoclipConn = nil
    end
    if on then
        QF.NoclipConn = RunService.Stepped:Connect(function()
            local char = LocalPlayer.Character
            if char then
                for _, part in ipairs(char:GetDescendants()) do
                    if part:IsA("BasePart") and part.CanCollide then
                        part.CanCollide = false
                    end
                end
            end
        end)
        TrackConnection(QF.NoclipConn)
    else
        local char = LocalPlayer.Character
        if char then
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") then
                    part.CanCollide = true
                end
            end
        end
    end
end

-- Nearest part of the current goal (the goal can be a table of parts)
function QF.GetTargetPart()
    local goal = QF.Goal
    if not goal then return nil end

    if type(goal) == "table" then
        local closestPart, minDistance = nil, math.huge
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            for _, part in pairs(goal) do
                local resolved = ResolveToInstance(part)
                if resolved and resolved:IsA("BasePart") then
                    local offset = hrp.Position - resolved.Position
                    local dist = offset.X * offset.X + offset.Y * offset.Y + offset.Z * offset.Z
                    if dist < minDistance then
                        minDistance = dist
                        closestPart = resolved
                    end
                end
            end
        end
        return closestPart
    end

    local resolved = ResolveToInstance(goal)
    if resolved and resolved:IsA("BasePart") then
        return resolved
    end
    return nil
end

pcall(function() QF.InstallHooks() end)

TrackConnection(SafeOnClient(UpdGoalLocator):Connect(function(p1, p2, p3, p4)
    QF.Goal, QF.Button, QF.Next = p1, p2, p4
end))

TrackConnection(SafeOnClient(AlertRemote):Connect(function(msg)
    if QF.ExitPhase and type(msg) == "string" then
        local text = msg:lower()
        if text:find("escaped") or text:find("survived") then
            QF.Escaped = true
        end
    end
end))

TrackConnection(LocalPlayer.CharacterAdded:Connect(function()
    QF.ResettingCharacter = false
end))

-- God Mode is backed by the FE2 Infinite Air implementation. The old health-pinning loop was removed.

task.spawn(function()
    QF.Passkey = GetSessionKey()
end)

-- Tells the server the map has loaded (4x per second while the farm is running)
task.spawn(function()
    while getgenv().FloodGUI_QFSession == QF.Session do
        task.wait(0.25)
        if QF.Passkey and LoadedMapRemote and (State.CurrentlyFarming or (State.AutoFarm and not State.AutoPlay)) then
            pcall(function()
                if LoadedMapRemote:IsA("RemoteEvent") then
                    LoadedMapRemote:FireServer(QF.Passkey)
                end
            end)
        end
    end
end)

-- Cycle daily challenges every 10 minutes (blind)
task.spawn(function()
    local lastCycle = 0
    while getgenv().FloodGUI_QFSession == QF.Session do
        task.wait(1)
        if State.CycleChallenges and os.time() - lastCycle >= 600 then
            lastCycle = os.time()
            local cycleRemote = RemoteFolder:FindFirstChild("CycleNewChallenges")
            if cycleRemote then
                pcall(function()
                    cycleRemote:FireServer()
                    Alert("Daily challenges cycled.", "Success")
                end)
            else
                Alert("CycleNewChallenges remote not found.", "Warning")
            end
        end
    end
end)

local function StartAutoFarm(Map)
    if State.CurrentlyFarming then return end
    State.CurrentlyFarming = true
    QF.Goal, QF.Button, QF.Next = nil, nil, nil
    QF.Escaped = false
    QF.ExitPhase = false

    local function Active()
        return (State.AutoFarm or State.AutoPlay) and not _G.LoopCancel
    end

    local alternate = false
    local escapeTimer = nil

    if not QF.Passkey then QF.Passkey = GetSessionKey() end
    QF.CacheGameScriptState()

    local char = GetChar()
    local Humanoid = char:WaitForChild("Humanoid", 10)
    local HRP = char:WaitForChild("HumanoidRootPart", 10)
    if not Humanoid or not HRP then
        State.CurrentlyFarming = false
        return
    end

    if not Check("InGame") then
        Alert("Waiting for the match to start...", "Warning")
    end

    -- Wait until deployed in-game and unanchored (bails out if the map or character goes away)
    while (not Check("InGame") or HRP.Anchored) and Active() and Map.Parent and HRP.Parent do
        task.wait()
    end
    if not (Active() and Map.Parent and HRP.Parent) then
        State.CurrentlyFarming = false
        return
    end

    -- Exact map spawn (position + rotation) and camera, used by "Play after Buttons" / reset
    local spawnCFrame = HRP.CFrame
    local spawnCamCFrame = Camera and Camera.CFrame

    QF.SetNoclip(true)
    Alert("Farming started! Navigating targets.", "Success")

    if State.StartDelay > 0 then
        HRP.CFrame = CFrame.new(-25, -144, 139)
        HRP.Velocity = Vector3.zero
        QF.DelayOverride = true
        Alert("Delaying navigation for " .. tostring(State.StartDelay) .. " seconds...", "Warning")
        local remaining = State.StartDelay
        while remaining > 0 and Active() and not QF.Escaped and Map.Parent do
            task.wait(0.1)
            remaining = remaining - 0.1
        end
    end

    while RunService.Heartbeat:Wait() and Check("InGame") and Active() and not QF.Escaped and Map.Parent and HRP.Parent do
        if not State.CurrentlyFarming then break end

        local Hum = HRP.Parent:FindFirstChildOfClass("Humanoid")
        if not Hum then continue end

        local activeButton = ResolveToInstance(QF.Button)
        local activeNextButton = ResolveToInstance(QF.Next)

        local isButtonToPress = false
        if activeButton and activeButton:IsA("BasePart") then
            local nameLower = activeButton.Name:lower()
            if not nameLower:find("exit") and not nameLower:find("region") then
                isButtonToPress = true
            end
        end

        local isNextButtonToPress = false
        if activeNextButton and activeNextButton:IsA("BasePart") then
            local nameLower = activeNextButton.Name:lower()
            if not nameLower:find("exit") and not nameLower:find("region") then
                isNextButtonToPress = true
            end
        end

        local targetPart = nil
        if isButtonToPress and isNextButtonToPress then
            alternate = not alternate
            targetPart = alternate and activeButton or activeNextButton
        elseif isButtonToPress then
            targetPart = activeButton
        elseif isNextButtonToPress then
            targetPart = activeNextButton
        else
            targetPart = QF.GetTargetPart()
        end

        if targetPart then
            HRP.Anchored = false
            if Camera.CameraSubject ~= Hum then
                Camera.CameraSubject = Hum
            end
            if QF.Escaped then break end

            HRP.CFrame = CFrame.new(targetPart.Position)
            HRP.Velocity = Vector3.zero

            -- Drop the lobby-coordinates override once we've teleported to the first target
            QF.DelayOverride = false

            if isButtonToPress or isNextButtonToPress then
                escapeTimer = nil
                if isButtonToPress then
                    PressedMapButton:FireServer(activeButton)
                end
                if isNextButtonToPress then
                    PressedMapButton:FireServer(activeNextButton)
                end
                task.wait()
            else
                -- All buttons pressed
                if State.PlayAfterButtons then
                    Alert("All buttons pressed! Returning to spawn for manual play...", "Success")
                    HRP.CFrame = spawnCFrame
                    HRP.Velocity = Vector3.zero
                    if Camera and spawnCamCFrame then
                        Camera.CameraType = Enum.CameraType.Custom
                        Camera.CameraSubject = Humanoid
                        Camera.CFrame = spawnCamCFrame
                    end
                    break -- stop without firing the Survived remote
                end

                QF.ExitPhase = true
                if not escapeTimer then
                    escapeTimer = os.time()
                elseif os.time() - escapeTimer > 10 then
                    Alert("Escape phase exceeded 10 seconds! Force resetting character to prevent lock.", "Error")
                    QF.SafeReset()
                    break
                end

                -- Clear the game script's local "already escaping" locks, then report the escape
                if QF.UpdTarget and debug_setupvalue then
                    for _, idx in ipairs(QF.LockIndices) do
                        pcall(debug_setupvalue, QF.UpdTarget, idx, false)
                    end
                end
                if QF.Passkey then
                    SurvivedRemote:FireServer(QF.Passkey, 100)
                end
                task.wait()
            end
        else
            task.wait()
        end
    end

    -- Physical collision back on (and restore your own noclip toggle if it was on)
    QF.SetNoclip(false)
    if State.Noclip then Noclip(true) end

    -- Post-escape handling
    if QF.Escaped then
        if HRP and HRP.Parent then
            if State.ResetAfterEscape then
                if spawnCFrame then HRP.CFrame = spawnCFrame end
                HRP.Velocity = Vector3.zero
                Alert("Escaped successfully! Resetting soon...", "Success")
            else
                HRP.CFrame = CFrame.new(-25, -144, 139)
                HRP.Velocity = Vector3.zero
                Alert("Escaped successfully!", "Success")
            end
        end

        if State.AutoRebirth and Rebirth.CanRebirth() ~= false then
            if QF.Passkey then
                pcall(function() ReqRebirth:FireServer(QF.Passkey) end)
                Alert("Auto Rebirth request sent.", "Info")
            else
                Alert("Failed Auto Rebirth: passkey missing.", "Error")
            end
        end

        if State.ResetAfterEscape then
            task.wait(State.ResetDelay or 0)
            QF.SafeReset()
        end
    elseif not State.PlayAfterButtons then
        Alert("Map beat or terminated.", "Info")
    end

    Alert("Waiting in lobby for the next round...", "System")
    QF.ExitPhase = false
    QF.DelayOverride = false
    State.CurrentlyFarming = false
end

-- ==============================================================================
-- [6b] AUTO COLLECT (Page / Escapee) — pure V3 Touch, works ANY TIME
-- ==============================================================================
-- Toggle only. Runs anytime on map (not only at map start / not blocked by TAS).

local function Touch(Character, Part)
    -- Exact V3: teleport to part, wait, teleport back
    if not Character or not Part then return false end
    local RootPart = Character:FindFirstChild("HumanoidRootPart")
    if not RootPart then return false end

    local target = Part
    if not target:IsA("BasePart") then
        target = Part:FindFirstChild("Contact") or Part:FindFirstChildWhichIsA("BasePart", true)
    end
    if not target or not target:IsA("BasePart") then return false end

    local OriginalCFrame = RootPart.CFrame
    RootPart.CFrame = CFrame.new(target.Position)
    task.wait()
    RootPart.CFrame = OriginalCFrame
    return true
end

task.spawn(function()
    local lastMapRef = nil
    local gotPage, gotRescue = false, false

    while task.wait(0.15) do
        if not State.AutoCollect then
            lastMapRef = nil
            gotPage, gotRescue = false, false
        else
            local Map = Multiplayer:FindFirstChild("Map") or Multiplayer:FindFirstChild("NewMap")
            if Map then
                if lastMapRef ~= Map then
                    lastMapRef = Map
                    gotPage, gotRescue = false, false
                end

                local Character = LocalPlayer.Character
                if Character and Character:FindFirstChild("HumanoidRootPart") then
                    if not gotPage then
                        local LostPage = Map:FindFirstChild("_LostPage", true)
                        if LostPage then
                            if Touch(Character, LostPage) then
                                gotPage = true
                                Alert("Hidden Page Acquired.", "Item")
                                print("[Flood GUI] Got Lost Page.")
                            end
                        end
                    end

                    if not gotRescue then
                        local Rescue = Map:FindFirstChild("_Rescue", true)
                        if Rescue then
                            local contact = Rescue:FindFirstChild("Contact") or Rescue
                            if Touch(Character, contact) then
                                gotRescue = true
                                Alert("Survivor Rescued.", "Item")
                                print("[Flood GUI] Got Escapee.")
                            end
                        end
                    end
                end
            else
                lastMapRef = nil
                gotPage, gotRescue = false, false
            end
        end
    end
end)


-- ==============================================================================
-- [7] MAP LOAD EVENT & VOTING HANDLER
-- ==============================================================================
-- Auto-vote removed (was annoying)
-- Only keep Record mode launcher if needed
TrackConnection(SafeOnClient(NewMapVote):Connect(function(dataPacket)
    if State.Mode ~= "Record" then return end
    if not State.AutoFarm and not State.AutoPlay then return end
    -- Record mode still works, just no automatic voting
end))

TrackConnection(SafeChildAdded(Multiplayer):Connect(function(NewMap)
    if _G.LoopCancel or (not State.AutoFarm and not State.AutoPlay) then return end
    NewMap:GetPropertyChangedSignal("Name"):Wait()

    local Settings = NewMap:WaitForChild("Settings", 10)
    local MapName = Settings and Settings:GetAttribute("MapName") or NewMap.Name
    local cleanName = CleanMapName(MapName)
    local hasTasFile = CheckGithubForFile(cleanName) and not RunStats.IsBenched(cleanName)

    local success, result = pcall(function()
        local diffText = Workspace.Lobby.GameInfo.SurfaceGui.Frame.Difficulty.Difficulty.Text
        return diffText:split(":")[1]:gsub("^%s*(.-)%s*$", "%1")
    end)
    local currentRank = DIFFICULTY_RANKS[result] or 0
    local targetRank = DIFFICULTY_RANKS[State.TargetDifficulty] or 999

    if State.EnforceDifficulty and currentRank > targetRank then
        Alert("Map is too hard ("..result.."). Resetting...", "Error")
        State.ResettingForDifficulty = true
        task.wait(1)
        QF.SafeReset()
        return
    end

    if State.AutoPlay then
        if not hasTasFile and State.FallbackToFarm then
            Alert("No TAS found for map. Forcing Blatant Fallback...", "Warning")
            getgenv().IsTASPlaying = false
            DestroyPauseButton()
            StartAutoFarm(NewMap)
        end
        return 
    end

    if State.AutoFarm and not State.AutoPlay then
        Alert("Starting Auto-Farm operation on: " .. MapName, "Info")
        StartAutoFarm(NewMap)
    end
end))

TrackConnection(SafeOnClient(AlertRemote):Connect(function(msg)
    if type(msg) == "string" and msg:lower():match("escaped") then
        State.Escaped = true
        -- Flag only; MainLoop stops TAS after 0.5s. Do NOT set TAS_ManualStop
        -- so Auto-Play can start again on the next map without toggling.
        task.delay(1.2, function()
            State.Escaped = false
        end)
    end
end))

-- ==============================================================================
-- [8] BACKGROUND LOOPS & MODS
-- ==============================================================================
task.spawn(function()
    while task.wait(1) do
        if _G.LoopCancel then break end
        
        if State.AutoPlay and not getgenv().IsTASPlaying and not State.CurrentlyFarming then
            -- Allow restart after a natural map finish (only block if user pressed STOP)
            if getgenv().TAS_ManualStop then
                -- stay stopped until user toggles Auto-Play or Force Load
            else
                task.spawn(function()
                    local success, err = pcall(function()
                        StartBuiltInTASPlayer()
                    end)
                    if not success then
                        Alert("Failed to load TAS script: " .. tostring(err), "Error")
                        getgenv().IsTASPlaying = false
                        DestroyPauseButton()
                    end
                end)
            end
        end
        
        if not getgenv().IsTASPlaying and PauseButtonGui then
            DestroyPauseButton()
        end
    end
end)

task.spawn(function()
    while task.wait(1) do
        if _G.LoopCancel then break end
        if (State.AutoFarm or State.AutoPlay) and not State.CurrentlyFarming then
            if AddedWaiting and not Check("InLift") and not Check("InGame") then
                AddedWaiting:FireServer()
            end
        end
    end
end)

task.spawn(function()
    local lastRebirthAttempt = 0
    while task.wait(1) do
        if _G.LoopCancel then break end
        if State.AutoRebirth then
            local now = os.time()
            local canRebirth = Rebirth.CanRebirth() -- true / false / nil (unknown)
            if canRebirth ~= false and now - lastRebirthAttempt >= (canRebirth and 10 or 60) then
                local key = GetSessionKey()
                if key then
                    pcall(function()
                        ReqRebirth:FireServer(key)
                        Alert("Attempted Auto Rebirth", "Success")
                    end)
                end
                lastRebirthAttempt = now
            end
        end
    end
end)

TrackConnection(RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum then
        if not getgenv().IsTASPlaying and hum.WalkSpeed > 0 then
            if hum.WalkSpeed ~= State.WalkSpeed then hum.WalkSpeed = State.WalkSpeed end
            if hum.JumpPower ~= State.JumpPower then hum.JumpPower = State.JumpPower end
        end
    end
end))

TrackConnection(UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    
    if State.AirJump and (input.KeyCode == Enum.KeyCode.M or input.KeyCode == Enum.KeyCode.Space) then
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hum and hrp and hum:GetState() == Enum.HumanoidStateType.Freefall then
            hrp.Velocity = Vector3.new(hrp.Velocity.X, State.JumpPower * 0.8, hrp.Velocity.Z)
        end
    end

    if input.KeyCode == Enum.KeyCode.P then
        TogglePauseManual()
    end
end))

TrackConnection(Players.PlayerAdded:Connect(function(player)
    if State.AutoLeave and player ~= LocalPlayer then
        Alert(("Player '%s' joined. Auto-leaving as configured."):format(player.Name), "Warning")
        getgenv().FloodGUI_IntentionalLeave = true
        task.wait(0.5)
        pcall(LocalPlayer.Kick, LocalPlayer, "Flood GUI: Auto-Leave triggered by player joining.")
    end
end))

TrackConnection(LocalPlayer.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end))

TrackConnection(LocalPlayer.CharacterAdded:Connect(function(char)
    if State.ResettingForDifficulty then
        char:WaitForChild("HumanoidRootPart", 10)
        task.wait(0.5)
        if AddedWaiting then AddedWaiting:FireServer() end
        State.ResettingForDifficulty = false
    end
end))

if getgenv().hookmetamethod then
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", function(self, index)
        if State.SwimEnabled and index == "Position" and tostring(self) == "HumanoidRootPart" and not checkcaller() then
            return Vector3.new(-23, -153, 0)
        end
        return oldIndex(self, index)
    end)
end

-- ==============================================================================
-- [8B] LOBBY TOOLS (Boosts / Voting / Auto-Join) - merged from FE2 Troll (rokfx)
-- ==============================================================================
local Lobby = {}

do
    local function GetIsVotingEvent()
        local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
        local gameGui = playerGui and playerGui:FindFirstChild("GameGui")
        local waiting = gameGui and gameGui:FindFirstChild("Waiting")
        local clWaiting = waiting and waiting:FindFirstChild("CL_Waiting")
        return clWaiting and clWaiting:FindFirstChild("IsVoting")
    end

    local function GetDoMapVote()
        return CLMAIN and CLMAIN:FindFirstChild("DoMapVote")
    end

    function Lobby.CalculateCoinCost(voteCount)
        if voteCount <= 1 then return 0 end
        local totalCost = 0
        for voteIndex = 2, voteCount do
            totalCost = totalCost + math.clamp((voteIndex - 1) * 10, 10, 50)
        end
        return totalCost
    end

    -- ---------------------------- Vote burst ---------------------------------
    local fullVoteInProgress = false

    local function CastInstantFullVote(targetMap, startingVoteIndex)
        local doMapVote = GetDoMapVote()
        if not targetMap or not doMapVote then return end
        local maxAllowedVotes = State.CustomVoteTarget or 4
        local currentVotes = startingVoteIndex or 1

        for voteIndex = currentVotes, maxAllowedVotes - 1 do
            local extraCost = math.clamp(voteIndex * 10, 10, 50)
            doMapVote:Fire(targetMap.ID, extraCost)
        end

        local votesFired = maxAllowedVotes - currentVotes
        Alert(string.format("Vote Burst: Fired %d Extra Votes on %s!", votesFired, targetMap.name or "Map"), "Success")
    end

    local function TriggerAutoFullVote(voteData)
        if not State.AutoFullVote or not voteData or not voteData.pVotes then return end
        if fullVoteInProgress then return end

        local playerVote = voteData.pVotes[tostring(LocalPlayer.UserId)]
        if not playerVote or not playerVote.mapID or not (playerVote.voteCount > 0) then return end

        local currentVotes = playerVote.voteCount
        if currentVotes >= (State.CustomVoteTarget or 4) then return end

        local targetMap = nil
        if voteData.mapData then
            for _, map in ipairs(voteData.mapData) do
                if map.ID == playerVote.mapID then
                    targetMap = map
                    break
                end
            end
        end
        if not targetMap then return end

        fullVoteInProgress = true
        CastInstantFullVote(targetMap, currentVotes)
    end

    TrackConnection(SafeOnClient(NewMapVote):Connect(function()
        fullVoteInProgress = false
    end))

    TrackConnection(SafeOnClient(UpdMapVote):Connect(function(voteData)
        if State.AutoFullVote then
            TriggerAutoFullVote(voteData)
        end
    end))

    -- ---------------------------- Secret room TP -----------------------------
    function Lobby.TeleportToSecretRoom(character)
        if not State.AutoTeleport then return end
        local rootpart = character:WaitForChild("HumanoidRootPart", 10)
        if rootpart then
            task.wait(0.1)
            rootpart.CFrame = SAFE_ROOM_CFRAME
        end
    end

    TrackConnection(LocalPlayer.CharacterAdded:Connect(function(character)
        Lobby.TeleportToSecretRoom(character)
    end))

    -- ------------------- Auto event / auto voting (lobby) --------------------
    local eventTriggeredThisRound = false
    local votingActiveThisRound = false
    local cachedPlayersLabel = nil
    local lastLabelSearch = 0

    -- Cached + throttled so we don't do a recursive Workspace search every frame
    local function GetPlayersLabel()
        if cachedPlayersLabel and cachedPlayersLabel.Parent then
            return cachedPlayersLabel
        end
        local now = os.clock()
        if now - lastLabelSearch < 1 then return nil end
        lastLabelSearch = now

        local gameInfo = Workspace:FindFirstChild("GameInfo", true)
        if gameInfo then
            local label = gameInfo:FindFirstChild("players", true) or gameInfo:FindFirstChild("Players", true)
            if label and label:IsA("TextLabel") then
                cachedPlayersLabel = label
                return label
            end
        end
        return nil
    end

    local function RunAutoVoting()
        local char = LocalPlayer.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local humanoid = char and char:FindFirstChildOfClass("Humanoid")
        if not root or not char then return end

        local savedCFrame = root.CFrame
        local function RestorePosition()
            char:PivotTo(savedCFrame)
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
            if humanoid then
                humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
                task.defer(function()
                    humanoid:ChangeState(Enum.HumanoidStateType.Running)
                end)
            end
        end

        local teleportConn
        local hasRestored = false
        teleportConn = root:GetPropertyChangedSignal("CFrame"):Connect(function()
            if not hasRestored then
                hasRestored = true
                if teleportConn then teleportConn:Disconnect() end
                task.wait(0.05)
                RestorePosition()
            end
        end)

        if AddedWaiting then AddedWaiting:FireServer() end
        if RemoveWaiting then RemoveWaiting:FireServer() end

        task.delay(1.5, function()
            if teleportConn then teleportConn:Disconnect() end
            if not hasRestored then RestorePosition() end
        end)

        local isVotingEvent = GetIsVotingEvent()
        if isVotingEvent then
            isVotingEvent:Fire(true)
        end
    end

    TrackConnection(RunService.Heartbeat:Connect(function()
        local playersLabel = GetPlayersLabel()
        if not playersLabel then return end

        if playersLabel.Text == "Waiting for Players" then
            if State.AutoEvent and not eventTriggeredThisRound then
                eventTriggeredThisRound = true
                if AddMapEventRemote then
                    AddMapEventRemote:FireServer()
                    AddMapEventRemote:FireServer()
                end
            end
            if State.AutoVoting and not votingActiveThisRound then
                votingActiveThisRound = true
                task.spawn(RunAutoVoting)
            end
        else
            eventTriggeredThisRound = false
            fullVoteInProgress = false
            if votingActiveThisRound then
                votingActiveThisRound = false
                if State.AutoVoting then
                    local isVotingEvent = GetIsVotingEvent()
                    if isVotingEvent then
                        isVotingEvent:Fire(false)
                    end
                end
            end
        end
    end))

    -- ---------------------------- Auto boost ---------------------------------
    function Lobby.FullBoost()
        if not BoostIntensity then
            Alert("BoostIntensity remote not found.", "Error")
            return
        end
        for _ = 1, 4 do
            task.spawn(function()
                BoostIntensity:FireServer(5)
            end)
        end
    end

    function Lobby.DoubleMapEvent()
        if not AddMapEventRemote then
            Alert("AddMapEvent remote not found.", "Error")
            return
        end
        AddMapEventRemote:FireServer()
        AddMapEventRemote:FireServer()
    end

    TrackConnection(SafeChildAdded(Multiplayer):Connect(function(NewMap)
        NewMap:GetPropertyChangedSignal("Name"):Wait()
        if State.AutoBoost then
            Lobby.FullBoost()
        end
    end))

    -- ---------------------------- Auto-Join ----------------------------------
    local function DismissTeleportPrompt()
        pcall(function()
            local robloxPromptGui = CoreGui:FindFirstChild("RobloxPromptGui")
            local promptOverlay = robloxPromptGui and robloxPromptGui:FindFirstChild("promptOverlay")
            local errorPrompt = promptOverlay and promptOverlay:FindFirstChild("ErrorPrompt")
            if errorPrompt and errorPrompt.Visible then
                local messageArea = errorPrompt:FindFirstChild("MessageArea")
                local buttonContainer = messageArea and messageArea:FindFirstChild("ErrorButtonArea")
                local okButton = buttonContainer and buttonContainer:FindFirstChildWhichIsA("GuiButton", true)
                if okButton then
                    for _, conn in pairs(getconnections(okButton.MouseButton1Click)) do
                        conn:Fire()
                    end
                end
            end
        end)
    end

    function Lobby.UpdateTargetUserId(username)
        if username == "" or username == nil then
            State.TargetUsername = ""
            State.TargetUserId = nil
            Alert("Target player cleared.", "Warning")
            return
        end
        State.TargetUsername = username
        task.spawn(function()
            local success, id = pcall(function()
                return Players:GetUserIdFromNameAsync(username)
            end)
            if success and id then
                State.TargetUserId = id
                Alert("Target set: " .. username .. " (ID: " .. tostring(id) .. ")", "Success")
            else
                State.TargetUserId = nil
                Alert("Could not find user: " .. username, "Error")
            end
        end)
    end

    -- Session token: a re-execute replaces this value, which ends the old loop
    local lobbySession = {}
    getgenv().FloodGUI_LobbySession = lobbySession

    task.spawn(function()
        while getgenv().FloodGUI_LobbySession == lobbySession do
            if State.AutoReqTele and ReqTele and State.TargetUserId then
                DismissTeleportPrompt()
                local placeId = PLACE_IDS[State.SelectedPlaceType] or PLACE_IDS.Pro
                pcall(function()
                    ReqTele:FireServer(placeId, State.TargetUserId)
                end)
                task.wait(4)
            else
                task.wait(1)
            end
        end
    end)
end

-- ==============================================================================
-- [8C] CONFIG SAVE/LOAD, AUTO-REJOIN WATCHDOG & TAS LIBRARY
-- ==============================================================================
local CONFIG_FILE = "FloodGUI_Config.json"

-- UI toggle name -> State key (used to keep toggle visuals in sync with loaded config)
local TOGGLE_KEYS = {
    ["Enable Auto-Play"] = "AutoPlay",
    ["Fallback to Blatant Farm"] = "FallbackToFarm",
    ["Enable Auto-Farm"] = "AutoFarm",
    ["Auto Collect (Page-Escapee)"] = "AutoCollect",
    ["Auto Rebirth"] = "AutoRebirth",
    ["Enforce Difficulty Limiter"] = "EnforceDifficulty",
    ["Auto-Leave"] = "AutoLeave",
    ["Auto Boost (20 Gems)"] = "AutoBoost",
    ["Auto Double Map Event (15 Gems)"] = "AutoEvent",
    ["Auto TP to Secret Room"] = "AutoTeleport",
    ["Auto Open Voting"] = "AutoVoting",
    ["Custom Vote Amount"] = "AutoFullVote",
    ["Auto Teleport Request"] = "AutoReqTele",
    ["Auto-Rejoin on Disconnect"] = "AutoRejoinDisconnect",
    ["Auto-Rejoin on Stall"] = "AutoRejoinStall",
    ["Auto-Save Config"] = "AutoSaveConfig",
    ["Send Webhook Notifications"] = "WebhookEnabled",
    ["Floating UI Button"] = "FloatingButton",
    ["Fast Load"] = "FastLoad",
    ["Enable God Mode"] = "GodMode",
    ["Play after Buttons (No Escape)"] = "PlayAfterButtons",
    ["Reset after Escape"] = "ResetAfterEscape",
    ["Cycle Challenges (10 Min Blind)"] = "CycleChallenges",
    ["Float (no fall)"] = "MapTPFloat",
    ["Button Aura"] = "ButtonAura",
    ["Aura: Use Distance"] = "AuraUseDistance",
    ["Anti-Void"] = "AntiVoid",
    ["Click TP"] = "ClickTP",
}

local PERSIST_KEYS = {
    "AutoPlay", "FallbackToFarm", "AutoFarm", "AutoCollect", "AutoRebirth", "AutoLeave",
    "EnforceDifficulty", "AutoBoost", "AutoEvent", "AutoVoting", "AutoFullVote",
    "AutoTeleport", "AutoReqTele", "AutoRejoinDisconnect", "AutoRejoinStall", "AutoSaveConfig",
    "Mode", "TargetDifficulty", "TargetMapName", "WalkSpeed", "JumpPower", "TASSpeed",
    "CustomVoteTarget", "TargetUsername", "SelectedPlaceType", "StallMinutes", "ReloadSource",
    "MaxTasFails", "WebhookURL", "WebhookEnabled", "FloatingButton",
    "FastLoad", "GodMode", "PlayAfterButtons", "ResetAfterEscape", "StartDelay", "ResetDelay",
    "CycleChallenges", "RejoinDelay", "RejoinPendingAt", "MapTPFloat", "MapTPInterval",
    "ButtonAura", "AuraUseDistance", "AuraDist", "AntiVoid", "ClickTP", "AfkFps",
}

local Config = { Toggles = {}, UIToggleState = {} }
local Safety = {}
local TasLibrary = { Maps = {}, Set = {}, Loaded = false, CurrentMap = nil, OnMapChanged = nil }

do
    local lastSavedSignature = nil

    local function HasFileApi()
        return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
    end

    local function ConfigSignature()
        local parts = {}
        for _, key in ipairs(PERSIST_KEYS) do
            parts[#parts + 1] = key .. "=" .. tostring(State[key])
        end
        return table.concat(parts, "|")
    end

    function Config.Save(silent)
        if not HasFileApi() then
            if not silent then Alert("Your executor has no file API (writefile).", "Error") end
            return false
        end
        local data = {}
        for _, key in ipairs(PERSIST_KEYS) do
            data[key] = State[key]
        end
        local ok, err = pcall(function()
            writefile(CONFIG_FILE, HttpService:JSONEncode(data))
        end)
        if ok then
            lastSavedSignature = ConfigSignature()
            if not silent then Alert("Config saved to " .. CONFIG_FILE, "Success") end
        elseif not silent then
            Alert("Config save failed: " .. tostring(err), "Error")
        end
        return ok
    end

    function Config.Load(silent)
        if not HasFileApi() then
            if not silent then Alert("Your executor has no file API (readfile).", "Error") end
            return false
        end
        local okExists, exists = pcall(isfile, CONFIG_FILE)
        if not okExists or not exists then
            if not silent then Alert("No saved config found.", "Warning") end
            return false
        end
        local okRead, raw = pcall(readfile, CONFIG_FILE)
        if not okRead or type(raw) ~= "string" then
            if not silent then Alert("Could not read config file.", "Error") end
            return false
        end
        local okDecode, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if not okDecode or type(data) ~= "table" then
            Alert("Config file is corrupted. Save a new one to replace it.", "Error")
            return false
        end

        for _, key in ipairs(PERSIST_KEYS) do
            local value = data[key]
            if value ~= nil and type(value) == type(State[key]) then
                State[key] = value
            end
        end

        -- Sanity checks so a hand-edited file can't break anything
        if not (State.TASSpeed > 0) then State.TASSpeed = 1 end
        State.WalkSpeed = math.clamp(State.WalkSpeed, 1, 100)
        State.JumpPower = math.clamp(State.JumpPower, 0, 200)
        if not (State.StallMinutes >= 1) then State.StallMinutes = 8 end
        if not (State.MaxTasFails >= 0) then State.MaxTasFails = 3 end
        if not (State.StartDelay >= 0) then State.StartDelay = 0 end
        State.MapTPInterval = math.clamp(State.MapTPInterval, 0, 5)
        State.AuraDist = math.max(0, tonumber(State.AuraDist) or 0)
        State.AfkFps = math.clamp(State.AfkFps, 1, 144)
        if not (State.ResetDelay >= 0) then State.ResetDelay = 0 end
        if not (State.RejoinDelay >= 0) then State.RejoinDelay = 11 end
        if not (State.CustomVoteTarget > 0) then State.CustomVoteTarget = 4 end
        if State.Mode ~= "Farm" and State.Mode ~= "Play" and State.Mode ~= "Record" then State.Mode = "Farm" end
        if DIFFICULTY_RANKS[State.TargetDifficulty] == nil then State.TargetDifficulty = "Normal" end
        if State.SelectedPlaceType ~= "Pro" and State.SelectedPlaceType ~= "Normal" then State.SelectedPlaceType = "Pro" end

        getgenv().TomatoAutoFarm = State.AutoFarm
        getgenv().FloodGUI_FastLoad = State.FastLoad
        if State.AutoPlay then getgenv().TAS_ManualStop = false end
        if State.TargetUsername ~= "" then
            Lobby.UpdateTargetUserId(State.TargetUsername)
        end

        lastSavedSignature = ConfigSignature()
        Alert(string.format("Config loaded (WalkSpeed %s, JumpPower %s, TAS speed %s, start delay %s, reset delay %s).",
            tostring(State.WalkSpeed), tostring(State.JumpPower), tostring(State.TASSpeed),
            tostring(State.StartDelay), tostring(State.ResetDelay)), "Success")
        return true
    end

    function Config.Delete()
        if HasFileApi() and type(delfile) == "function" then
            local ok, exists = pcall(isfile, CONFIG_FILE)
            if ok and exists then
                pcall(delfile, CONFIG_FILE)
                Alert("Saved config deleted.", "Warning")
                return
            end
        end
        Alert("No saved config to delete.", "Warning")
    end

    -- Wraps NewToggle so we can (a) remember each toggle object and (b) track its visual state.
    -- Best effort: if the UI library is shaped differently, this silently does nothing.
    function Config.HookWindow(Window)
        pcall(function()
            local origNewTab = Window.NewTab
            if type(origNewTab) ~= "function" then return end
            Window.NewTab = function(self, ...)
                local tab = origNewTab(self, ...)
                if type(tab) == "table" and type(tab.NewSection) == "function" then
                    local origNewSection = tab.NewSection
                    tab.NewSection = function(selfTab, ...)
                        local sec = origNewSection(selfTab, ...)
                        if type(sec) == "table" and type(sec.NewToggle) == "function" then
                            local origNewToggle = sec.NewToggle
                            sec.NewToggle = function(selfSec, name, desc, callback)
                                local key = TOGGLE_KEYS[name]
                                local cb = callback
                                if key and type(callback) == "function" then
                                    cb = function(state)
                                        Config.UIToggleState[key] = state
                                        return callback(state)
                                    end
                                end
                                local obj = origNewToggle(selfSec, name, desc, cb)
                                Config.Toggles[name] = obj
                                return obj
                            end
                        end
                        return sec
                    end
                end
                return tab
            end
        end)
    end

    function Config.SyncUI()
        for name, key in pairs(TOGGLE_KEYS) do
            local obj = Config.Toggles[name]
            local want = State[key] == true
            local have = Config.UIToggleState[key] == true
            if obj and want ~= have and type(obj.UpdateToggle) == "function" then
                pcall(obj.UpdateToggle, obj, name, want)
                Config.UIToggleState[key] = want
            end
        end
    end

    -- Auto-save: only writes when something actually changed
    local configSession = {}
    getgenv().FloodGUI_ConfigSession = configSession
    task.spawn(function()
        while getgenv().FloodGUI_ConfigSession == configSession do
            task.wait(15)
            if State.AutoSaveConfig and ConfigSignature() ~= lastSavedSignature then
                Config.Save(true)
            end
        end
    end)
end

-- ----------------------------- Auto-Rejoin watchdog ---------------------------
do
    local GuiService = game:GetService("GuiService")
    local rejoining = false
    local queuedOnce = false
    local attempts = 0
    local lastProgress = os.clock()
    getgenv().FloodGUI_IntentionalLeave = false

    local function GetQueueFn()
        local env = getgenv()
        if type(env.queue_on_teleport) == "function" then return env.queue_on_teleport end
        if type(queue_on_teleport) == "function" then return queue_on_teleport end
        if type(env.syn) == "table" and type(env.syn.queue_on_teleport) == "function" then return env.syn.queue_on_teleport end
        return nil
    end

    -- Re-runs this script after the teleport (workspace file name OR https link)
    local function QueueReload()
        if queuedOnce then return true end
        local src = State.ReloadSource
        local queueFn = GetQueueFn()
        if type(src) ~= "string" or src == "" or src:find("]=]", 1, true) or not queueFn then
            return false
        end
        local code
        if src:match("^https?://") then
            code = "loadstring(game:HttpGet([=[" .. src .. "]=]))()"
        else
            code = "if isfile([=[" .. src .. "]=]) then loadstring(readfile([=[" .. src .. "]=]))() end"
        end
        local ok = pcall(queueFn, code)
        queuedOnce = ok
        return ok
    end

    -- opts.delay: seconds to wait before teleporting. FE2 blocks rejoining for ~10s after
    --             you leave or get kicked, so kick/disconnect rejoins wait it out first.
    -- opts.stillWanted: optional function; return false to cancel while waiting.
    function Safety.Rejoin(reason, opts)
        if rejoining then return end
        opts = opts or {}
        rejoining = true
        attempts = attempts + 1
        local delay = opts.delay or 1
        Alert("Rejoining (" .. tostring(reason) .. ") in " .. tostring(delay) .. "s...", "Warning")
        Notify.Send("Rejoining (" .. tostring(reason) .. "), waiting " .. tostring(delay) .. "s")
        task.spawn(function()
            if not QueueReload() then
                Alert("No Reload Source set (or queue_on_teleport unsupported): the script won't auto-run after rejoining.", "Warning")
            end
            task.wait(delay)
            if opts.stillWanted and not opts.stillWanted() then
                rejoining = false
                Alert("Rejoin cancelled.", "Info")
                return
            end
            -- Marks the new session as "just rejoined" so a kick on arrival is retried
            State.RejoinPendingAt = os.time()
            Config.Save(true)
            local ok, err = pcall(TeleportService.Teleport, TeleportService, game.PlaceId, LocalPlayer)
            if not ok then
                Alert("Teleport error: " .. tostring(err), "Error")
                rejoining = false
            end
        end)
    end

    TrackConnection(TeleportService.TeleportInitFailed:Connect(function(_, result)
        if not rejoining then return end
        if attempts >= 10 then
            rejoining = false
            Alert("Rejoin failed 10 times. Giving up.", "Error")
            return
        end
        Alert("Rejoin failed (" .. tostring(result) .. "). Retrying...", "Error")
        local retryDelay = math.max(State.RejoinDelay, math.min(5 * attempts, 30))
        rejoining = false
        Safety.Rejoin("retry", { delay = retryDelay })
    end))

    local function WasJustRejoined()
        return State.RejoinPendingAt > 0 and os.time() - State.RejoinPendingAt < 180
    end

    -- Kicked / disconnected (the Roblox error prompt). Also covers FE2 kicking you for
    -- rejoining too fast: wait out the cooldown, then rejoin again.
    local function OnKicked(msg)
        if type(msg) ~= "string" or msg == "" then return end
        if getgenv().FloodGUI_IntentionalLeave then return end
        local justRejoined = WasJustRejoined()
        if not (State.AutoRejoinDisconnect or justRejoined) then return end
        local reason = justRejoined and "kicked right after rejoining (anti-rejoin cooldown)" or ("disconnected: " .. msg)
        Safety.Rejoin(reason, {
            delay = State.RejoinDelay,
            stillWanted = function() return justRejoined or State.AutoRejoinDisconnect end,
        })
    end

    TrackConnection(GuiService.ErrorMessageChanged:Connect(OnKicked))

    -- The kick can already be on screen by the time this script loads
    task.delay(1.5, function()
        local ok, msg = pcall(function() return GuiService:GetErrorMessage() end)
        if ok then OnKicked(msg) end
    end)

    -- Stayed connected for a minute: the rejoin worked, clear the marker
    task.delay(60, function()
        if not rejoining and State.RejoinPendingAt > 0 then
            State.RejoinPendingAt = 0
            Config.Save(true)
        end
    end)

    -- Progress = a new map spawned or you escaped
    TrackConnection(Multiplayer.ChildAdded:Connect(function()
        lastProgress = os.clock()
    end))
    TrackConnection(SafeOnClient(AlertRemote):Connect(function(msg)
        if type(msg) == "string" and msg:lower():match("escaped") then
            lastProgress = os.clock()
        end
    end))

    local safetySession = {}
    getgenv().FloodGUI_SafetySession = safetySession
    task.spawn(function()
        while getgenv().FloodGUI_SafetySession == safetySession do
            task.wait(5)
            local active = State.AutoPlay or State.AutoFarm
            if not (State.AutoRejoinStall and active) then
                lastProgress = os.clock() -- timer only runs while armed
            else
                local limit = math.max(1, State.StallMinutes) * 60
                if os.clock() - lastProgress >= limit then
                    Alert(string.format("No progress for %s min. Rejoining in 10s (turn Auto-Rejoin off to cancel).", tostring(State.StallMinutes)), "Warning")
                    task.wait(10)
                    if State.AutoRejoinStall and (State.AutoPlay or State.AutoFarm) and os.clock() - lastProgress >= limit then
                        Safety.Rejoin("Stalled")
                    else
                        lastProgress = os.clock()
                    end
                end
            end
        end
    end)
end

-- ------------------------------- TAS Library ----------------------------------
do
    function TasLibrary.Refresh()
        local ok, body = pcall(function() return game:HttpGet(CONFIG.TAS_API_URL) end)
        if not ok or type(body) ~= "string" then return false, "request failed" end
        local okDecode, data = pcall(function() return HttpService:JSONDecode(body) end)
        if not okDecode or type(data) ~= "table" then return false, "bad response" end
        if data.message then return false, tostring(data.message) end -- e.g. GitHub rate limit

        local maps, set = {}, {}
        for _, entry in ipairs(data) do
            if type(entry) == "table" and type(entry.name) == "string" then
                local base = entry.name:match("^(.*)%.json$")
                if base then
                    local name = CleanMapName(base)
                    maps[#maps + 1] = name
                    set[name] = true
                    getgenv().TasFileCache[name] = true -- speeds up the per-map check too
                end
            end
        end
        table.sort(maps, function(a, b) return a:lower() < b:lower() end)
        TasLibrary.Maps, TasLibrary.Set, TasLibrary.Loaded = maps, set, true
        return true, #maps
    end

    -- Tells you, every round, whether the current map has a TAS file
    TrackConnection(SafeChildAdded(Multiplayer):Connect(function(NewMap)
        local renamed = false
        local conn = NewMap:GetPropertyChangedSignal("Name"):Connect(function() renamed = true end)
        local t0 = os.clock()
        while not renamed and os.clock() - t0 < 5 do task.wait(0.1) end
        conn:Disconnect()

        local Settings = NewMap:WaitForChild("Settings", 10)
        local mapName = CleanMapName(Settings and Settings:GetAttribute("MapName") or NewMap.Name)
        local has = TasLibrary.Set[mapName] == true or CheckGithubForFile(mapName) == true
        local benched = has and RunStats.IsBenched(mapName)

        TasLibrary.CurrentMap = mapName
        if benched then
            Alert("TAS benched (repeated failures): " .. mapName, "Warning")
        else
            Alert((has and "TAS available: " or "No TAS file for: ") .. mapName, has and "Success" or "Warning")
        end
        if TasLibrary.OnMapChanged then
            pcall(TasLibrary.OnMapChanged, mapName, has, benched)
        end
    end))
end

-- ------------------------------ Run tracking ----------------------------------
do
    local STATS_FILE = "FloodGUI_RunStats.json"
    local BENCH_SECONDS = 3600
    local lastEscapeCounted = -100

    local function HasFileApi()
        return type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"
    end

    local function GetRecord(name)
        local rec = RunStats.Maps[name]
        if not rec then
            rec = { ok = 0, fail = 0, streak = 0, lastFail = 0, lastReason = "" }
            RunStats.Maps[name] = rec
        end
        return rec
    end

    function RunStats.Save()
        if not HasFileApi() then return end
        pcall(function()
            writefile(STATS_FILE, HttpService:JSONEncode({ Maps = RunStats.Maps }))
        end)
    end

    function RunStats.Load()
        if not HasFileApi() then return end
        local okExists, exists = pcall(isfile, STATS_FILE)
        if not okExists or not exists then return end
        local okRead, raw = pcall(readfile, STATS_FILE)
        if not okRead or type(raw) ~= "string" then return end
        local okDecode, data = pcall(function() return HttpService:JSONDecode(raw) end)
        if not okDecode or type(data) ~= "table" or type(data.Maps) ~= "table" then return end
        for name, rec in pairs(data.Maps) do
            if type(name) == "string" and type(rec) == "table" then
                RunStats.Maps[name] = {
                    ok = tonumber(rec.ok) or 0,
                    fail = tonumber(rec.fail) or 0,
                    streak = tonumber(rec.streak) or 0,
                    lastFail = tonumber(rec.lastFail) or 0,
                    lastReason = type(rec.lastReason) == "string" and rec.lastReason or "",
                }
            end
        end
    end

    -- A map is "benched" after N failures in a row. After 60 min it gets one more try.
    function RunStats.IsBenched(name)
        local limit = State.MaxTasFails
        if limit <= 0 then return false end
        local rec = RunStats.Maps[name]
        if not rec or rec.streak < limit then return false end
        if os.time() - rec.lastFail >= BENCH_SECONDS then
            rec.streak = limit - 1
            return false
        end
        return true
    end

    -- Called when a TAS run ends. Waits a moment because the "escaped" alert can land
    -- just after the TAS stops.
    function RunStats.Finish(info)
        task.wait(3)
        local rec = GetRecord(info.map)
        if RunStats.LastEscape >= info.startedAt then
            rec.ok = rec.ok + 1
            rec.streak = 0
            RunStats.SessionOk = RunStats.SessionOk + 1
        elseif info.manual then
            return -- you stopped it yourself, so it doesn't count as a failure
        else
            rec.fail = rec.fail + 1
            rec.streak = rec.streak + 1
            rec.lastFail = os.time()
            rec.lastReason = info.died and "died" or "no escape"
            RunStats.SessionFail = RunStats.SessionFail + 1
            Alert(string.format("TAS failed on %s (%s). Fail streak: %d", info.map, rec.lastReason, rec.streak), "Error")
            Notify.Send(string.format("TAS failed on %s (%s), streak %d", info.map, rec.lastReason, rec.streak))
            local limit = State.MaxTasFails
            if limit > 0 and rec.streak >= limit then
                Alert("TAS benched for 60 min: " .. info.map, "Warning")
                Notify.Send("TAS benched for 60 min: " .. info.map)
            end
        end
        RunStats.Save()
    end

    function RunStats.Reset()
        RunStats.Maps = {}
        RunStats.SessionOk, RunStats.SessionFail = 0, 0
        RunStats.Save()
        Alert("TAS run stats reset.", "Warning")
    end

    function RunStats.FailingSummary()
        local list = {}
        for name, rec in pairs(RunStats.Maps) do
            if rec.fail > 0 then
                list[#list + 1] = { name = name, rec = rec }
            end
        end
        table.sort(list, function(a, b)
            if a.rec.streak ~= b.rec.streak then return a.rec.streak > b.rec.streak end
            return a.rec.fail > b.rec.fail
        end)
        return list
    end

    -- Session counters
    TrackConnection(Multiplayer.ChildAdded:Connect(function()
        RunStats.MapsSeen = RunStats.MapsSeen + 1
    end))
    TrackConnection(SafeOnClient(AlertRemote):Connect(function(msg)
        if type(msg) == "string" and msg:lower():match("escaped") then
            RunStats.LastEscape = os.clock()
            if os.clock() - lastEscapeCounted > 5 then
                lastEscapeCounted = os.clock()
                RunStats.Escapes = RunStats.Escapes + 1
            end
        end
    end))
end

-- ------------------------------ Notifications ---------------------------------
do
    local lastSend = 0

    local function GetRequestFn()
        local env = getgenv()
        if type(env.request) == "function" then return env.request end
        if type(env.http_request) == "function" then return env.http_request end
        if type(request) == "function" then return request end
        if type(http_request) == "function" then return http_request end
        if type(env.syn) == "table" and type(env.syn.request) == "function" then return env.syn.request end
        return nil
    end

    -- Only Discord webhook URLs are accepted
    function Notify.IsValidUrl(url)
        if type(url) ~= "string" then return false end
        return url:match("^https://[%w%.]*discord%.com/api/webhooks/%d+/[%w%-_]+$") ~= nil
            or url:match("^https://[%w%.]*discordapp%.com/api/webhooks/%d+/[%w%-_]+$") ~= nil
    end

    -- Returns true if the message was queued
    function Notify.Send(text, force)
        if not force and not State.WebhookEnabled then return false end
        if not Notify.IsValidUrl(State.WebhookURL) then return false end
        local requestFn = GetRequestFn()
        if not requestFn then return false end
        local url = State.WebhookURL
        local body = HttpService:JSONEncode({
            username = "Flood GUI",
            content = string.sub("**" .. LocalPlayer.Name .. "**: " .. tostring(text), 1, 1800),
            allowed_mentions = { parse = {} },
        })
        task.spawn(function()
            local gap = 2 - (os.clock() - lastSend)
            if gap > 0 then task.wait(gap) end
            lastSend = os.clock()
            pcall(requestFn, {
                Url = url,
                Method = "POST",
                Headers = { ["Content-Type"] = "application/json" },
                Body = body,
            })
        end)
        return true
    end
end

-- ------------------------------ TAS prefetch ----------------------------------
-- While the vote screen is up, download the TAS files of the candidate maps so the
-- run can start the instant the map loads.
do
    local order = {}
    local tried = {}
    local MAX_CACHED = 12

    local function Store(name, raw)
        local cache = getgenv().TasDataCache
        if cache[name] == nil then order[#order + 1] = name end
        cache[name] = raw
        while #order > MAX_CACHED do
            cache[table.remove(order, 1)] = nil
        end
    end

    function TasPrefetch.Map(rawName)
        local name = CleanMapName(rawName)
        if tried[name] or getgenv().TasDataCache[name] then return end
        if getgenv().TasFileCache[name] == false then return end -- known to have no TAS
        tried[name] = true
        task.spawn(function()
            local raw = FetchTasRaw(name)
            if raw then Store(name, raw) end
        end)
    end

    function TasPrefetch.FromVoteData(data)
        if not State.AutoPlay or type(data) ~= "table" or type(data.mapData) ~= "table" then return end
        local count = 0
        for _, map in ipairs(data.mapData) do
            if type(map) == "table" and type(map.name) == "string" then
                TasPrefetch.Map(map.name)
                count = count + 1
                if count >= 8 then break end
            end
        end
    end

    TrackConnection(SafeOnClient(NewMapVote):Connect(TasPrefetch.FromVoteData))
    TrackConnection(SafeOnClient(UpdMapVote):Connect(TasPrefetch.FromVoteData))
end

RunStats.Load()

-- Restore saved settings before the UI is built
Config.Load(true)

-- ==============================================================================
-- [8D] MAP TOOLS (per-map teleport spam, built for FE2CM) - from "Map TP Spam"
-- ==============================================================================
-- Each supported map is one entry in MapTools.Specs. To add a map, add a
-- MapTools.Register({...}) call: the UI toggle, status and debug output are generated.
local MapTools = {
    Specs = {},
    Enabled = {},   -- [spec.id] = true while that spam is switched on
    Matched = nil,  -- the spec currently being spammed (nil = idle)
    OnStatus = nil, -- set by the UI to update the status label
}

do
    local weak = { __mode = "k" }
    local labelScan = setmetatable({}, weak)   -- [map][specId] = { result, at }
    local targetCache = setmetatable({}, weak) -- [map][specId] = { parts, at }
    local cycleIndex = {}
    local floating = false

    local function GetHRP()
        local c = LocalPlayer.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function GetHum()
        local c = LocalPlayer.Character
        return c and c:FindFirstChildOfClass("Humanoid")
    end

    local function AsPart(inst)
        if not inst then return nil end
        if inst:IsA("BasePart") then return inst end
        return inst:FindFirstChildWhichIsA("BasePart", true)
    end

    function MapTools.Register(spec)
        MapTools.Specs[#MapTools.Specs + 1] = spec
    end

    function MapTools.GetMap()
        local mp = Workspace:FindFirstChild("Multiplayer")
        if not mp then return nil end
        return mp:FindFirstChild("Map") or mp:FindFirstChild("NewMap")
    end

    -- Cheap checks first (instance name / Settings values), then a text-label scan that is
    -- cached so we don't walk the whole workspace every tick.
    local function CheapMatch(map, names)
        for _, n in ipairs(names) do
            if map.Name:lower() == n:lower() then return true end
        end
        local settings = map:FindFirstChild("Settings")
        if settings then
            local attr = settings:GetAttribute("MapName")
            if type(attr) == "string" then
                for _, n in ipairs(names) do
                    if attr:lower() == n:lower() then return true end
                end
            end
            for _, v in ipairs(settings:GetDescendants()) do
                if v:IsA("StringValue") then
                    for _, n in ipairs(names) do
                        if tostring(v.Value):lower() == n:lower() then return true end
                    end
                end
            end
        end
        return false
    end

    local function MapMatches(map, spec)
        if not map then return false end
        if CheapMatch(map, spec.names) then return true end

        local perMap = labelScan[map]
        if not perMap then
            perMap = {}
            labelScan[map] = perMap
        end
        local entry = perMap[spec.id]
        if entry and (entry.result or os.clock() - entry.at < 3) then
            return entry.result
        end

        local result = false
        for _, v in ipairs(Workspace:GetDescendants()) do
            if v:IsA("TextLabel") or v:IsA("TextBox") then
                local text = (v.Text or ""):lower()
                for _, n in ipairs(spec.names) do
                    if text:find(n:lower(), 1, true) then
                        result = true
                        break
                    end
                end
                if result then break end
            end
        end
        perMap[spec.id] = { result = result, at = os.clock() }
        return result
    end

    local function GetTargets(map, spec, force)
        local perMap = targetCache[map]
        if not perMap then
            perMap = {}
            targetCache[map] = perMap
        end
        local entry = perMap[spec.id]
        if entry and not force and os.clock() - entry.at < 1 then
            local alive = #entry.parts > 0
            for _, p in ipairs(entry.parts) do
                if not p.Parent then alive = false break end
            end
            if alive then return entry.parts end
        end
        local ok, parts = pcall(spec.getTargets, map)
        if not ok or type(parts) ~= "table" then parts = {} end
        perMap[spec.id] = { parts = parts, at = os.clock() }
        return parts
    end

    local function TpTouch(part)
        local hrp = GetHRP()
        if not hrp or not part then return end
        pcall(function()
            hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0))
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.Velocity = Vector3.zero
            if type(firetouchinterest) == "function" then
                firetouchinterest(hrp, part, 0)
                firetouchinterest(hrp, part, 1)
            end
        end)
    end

    -- ------------------------------ Float ----------------------------------
    local function ApplyFloat()
        local hrp, hum = GetHRP(), GetHum()
        if not hrp then return end
        floating = true
        pcall(function()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.Velocity = Vector3.zero
            if hum then hum.PlatformStand = true end
        end)
    end

    function MapTools.ReleaseFloat()
        if not floating then return end
        floating = false
        local hrp, hum = GetHRP(), GetHum()
        pcall(function()
            if hum then
                hum.PlatformStand = false
                hum:ChangeState(Enum.HumanoidStateType.Running)
            end
            if hrp then hrp.Anchored = false end
        end)
    end

    -- Only floats while a spam is actually running on a matching map
    TrackConnection(RunService.Heartbeat:Connect(function()
        if State.MapTPFloat and MapTools.Matched then
            ApplyFloat()
        end
    end))

    function MapTools.SetMatched(spec)
        if MapTools.Matched == spec then return end
        MapTools.Matched = spec
        if not spec then MapTools.ReleaseFloat() end
        if spec then
            Alert("Map Tools: spamming " .. spec.label, "Success")
        end
        if MapTools.OnStatus then pcall(MapTools.OnStatus, spec) end
    end

    -- ------------------------------ Spam loop ------------------------------
    local session = {}
    getgenv().FloodGUI_MapToolsSession = session

    task.spawn(function()
        while getgenv().FloodGUI_MapToolsSession == session do
            local matchedSpec = nil
            local anyOn = false
            for _, spec in ipairs(MapTools.Specs) do
                if MapTools.Enabled[spec.id] then anyOn = true break end
            end

            if anyOn then
                local map = MapTools.GetMap()
                if map then
                    for _, spec in ipairs(MapTools.Specs) do
                        if MapTools.Enabled[spec.id] and MapMatches(map, spec) then
                            local targets = GetTargets(map, spec)
                            if #targets > 0 then
                                matchedSpec = spec
                                local part
                                if spec.cycle then
                                    local idx = cycleIndex[spec.id] or 1
                                    if idx > #targets then idx = 1 end
                                    part = targets[idx]
                                    cycleIndex[spec.id] = idx + 1
                                else
                                    part = targets[1]
                                end
                                TpTouch(part)
                            end
                        end
                    end
                end
            end

            MapTools.SetMatched(matchedSpec)
            task.wait(State.MapTPInterval)
        end
    end)

    -- ------------------------------ Buttons --------------------------------
    -- Hits every target of the current map once (first matching spec)
    function MapTools.TpOnce()
        local map = MapTools.GetMap()
        if not map then
            Alert("Map Tools: no map found.", "Warning")
            return
        end
        for _, spec in ipairs(MapTools.Specs) do
            if MapMatches(map, spec) then
                local targets = GetTargets(map, spec, true)
                if #targets == 0 then
                    Alert("Map Tools: " .. spec.label .. " matched but no targets found.", "Warning")
                    return
                end
                Alert(string.format("Map Tools: hitting %d target(s) on %s", #targets, spec.label), "Info")
                for _, part in ipairs(targets) do
                    TpTouch(part)
                    task.wait(0.1)
                end
                return
            end
        end
        Alert("Map Tools: this map isn't supported.", "Warning")
    end

    function MapTools.Debug()
        local map = MapTools.GetMap()
        print("[Map Tools] Map:", map and map:GetFullName() or "nil")
        local summary = {}
        for _, spec in ipairs(MapTools.Specs) do
            local matches = map ~= nil and MapMatches(map, spec)
            local targets = matches and GetTargets(map, spec, true) or {}
            print(string.format("[Map Tools] %s: match=%s targets=%d", spec.label, tostring(matches), #targets))
            for i, p in ipairs(targets) do
                print("   [" .. i .. "]", p.Name, p:GetFullName(), p.Position)
            end
            summary[#summary + 1] = spec.id .. " " .. (matches and (#targets .. " targets") or "no match")
        end
        Alert("Map Tools: " .. (map and map.Name or "no map") .. " | " .. table.concat(summary, " | ") .. " (see console)", "Info")
    end
end

-- ------------------------------ Supported maps --------------------------------
MapTools.Register({
    id = "SCW",
    label = "SCW - CutscenePart",
    desc = "Splendid China Wall: teleports onto the CutscenePart.",
    info = "Splendid China Wall -> CutscenePart",
    names = { "Splendid China Wall" },
    cycle = false,
    getTargets = function(map)
        local p = map:FindFirstChild("CutscenePart", true)
        if p and p:IsA("BasePart") then return { p } end
        local ninth = map:GetChildren()[9]
        if ninth then
            local cp = ninth:FindFirstChild("CutscenePart") or ninth:FindFirstChild("CutscenePart", true)
            if cp and cp:IsA("BasePart") then return { cp } end
            if ninth:IsA("BasePart") and ninth.Name == "CutscenePart" then return { ninth } end
        end
        return {}
    end,
})

MapTools.Register({
    id = "MOM",
    label = "MOM - ObjectHitbox A/B/C",
    desc = "Minds Of Misery: cycles through the three object hitboxes.",
    info = "Minds Of Misery -> cycles ObjectHitbox A, B, C",
    names = { "Minds Of Misery" },
    cycle = true,
    getTargets = function(map)
        local found = {}
        local function Consider(inst)
            if not inst then return end
            local n = inst.Name
            if (n == "ObjectHitboxA" or n == "ObjectHitboxB" or n == "ObjectHitboxC") and found[n] == nil then
                local p = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
                if p then found[n] = p end
            end
        end

        -- The map hides these under an unnamed ("") folder, so check that path first
        local empty = map:FindFirstChild("")
        if empty then
            local child2 = empty:GetChildren()[2]
            if child2 then
                local nestedEmpty = child2:FindFirstChild("")
                if nestedEmpty then
                    Consider(nestedEmpty:FindFirstChild("ObjectHitboxA"))
                    Consider(nestedEmpty:FindFirstChild("ObjectHitboxA", true))
                end
                Consider(child2:FindFirstChild("ObjectHitboxA", true))
                local c2 = child2:GetChildren()[2]
                if c2 then
                    if c2.Name == "ObjectHitboxC" then
                        Consider(c2)
                    else
                        Consider(c2:FindFirstChild("ObjectHitboxC") or c2:FindFirstChild("ObjectHitboxC", true))
                    end
                end
                Consider(child2:FindFirstChild("ObjectHitboxB", true))
                Consider(child2:FindFirstChild("ObjectHitboxC", true))
            end
            Consider(empty:FindFirstChild("ObjectHitboxA", true))
            Consider(empty:FindFirstChild("ObjectHitboxB", true))
            Consider(empty:FindFirstChild("ObjectHitboxC", true))
        end

        -- Fallback: search the whole map
        if not (found.ObjectHitboxA and found.ObjectHitboxB and found.ObjectHitboxC) then
            for _, inst in ipairs(map:GetDescendants()) do
                Consider(inst)
            end
        end

        local out = {}
        if found.ObjectHitboxA then out[#out + 1] = found.ObjectHitboxA end
        if found.ObjectHitboxB then out[#out + 1] = found.ObjectHitboxB end
        if found.ObjectHitboxC then out[#out + 1] = found.ObjectHitboxC end
        return out
    end,
})

-- ==============================================================================
-- [8E] FE2 EXTRAS: Button Aura, Smart Rebirth, Currency Tracker, Anti-Void,
--      Click TP, AFK Mode, late remote binding.
--      Ideas ported from ltseverydayyou's Fe2AutoFarm (written fresh for this GUI).
-- ==============================================================================

-- ------------------------------- Player data ----------------------------------
do
    local function DataValue(name)
        local d = LocalPlayer:FindFirstChild("Data")
        local obj = d and d:FindFirstChild(name)
        if obj and obj:IsA("ValueBase") then return obj.Value end
        return nil
    end

    local function BoardValue(...)
        local ls = LocalPlayer:FindFirstChild("leaderstats")
        if not ls then return nil end
        for _, name in ipairs({ ... }) do
            for _, child in ipairs(ls:GetChildren()) do
                if child:IsA("ValueBase") and child.Name:lower() == name:lower() then
                    return child.Value
                end
            end
        end
        return nil
    end

    -- Returns { coins, gems, level, xp, rebirth } (fields may be nil) or nil if nothing is readable
    function Rebirth.Read()
        local snap = {
            coins = tonumber(DataValue("Coins") or BoardValue("Coins")),
            gems = tonumber(DataValue("Amethysts") or BoardValue("Gems", "Amethysts")),
            level = tonumber(DataValue("Level") or BoardValue("Level")),
            xp = tonumber(DataValue("Experience")),
            rebirth = tonumber(DataValue("Rebirths") or BoardValue("Rebirths")),
        }
        if not (snap.coins or snap.gems or snap.level or snap.xp or snap.rebirth) then
            return nil
        end
        return snap
    end

    local calcLevelXP = nil
    pcall(function()
        local mods = ReplicatedStorage:FindFirstChild("Modules")
        local shared = mods and mods:FindFirstChild("Shared")
        local lib = shared and shared:FindFirstChild("FE2Library")
        if lib then
            local loaded = require(lib)
            if type(loaded) == "table" and type(loaded.calcLevelXP) == "function" then
                calcLevelXP = loaded.calcLevelXP
            end
        end
        if not calcLevelXP then
            local lib2 = mods and mods:FindFirstChild("Library")
            if lib2 then
                local loaded = require(lib2)
                if type(loaded) == "table" and type(loaded.GetLevelExperience) == "function" then
                    calcLevelXP = function(lv) return loaded.GetLevelExperience(lv) end
                end
            end
        end
    end)

    function Rebirth.NeedXp(lv, rb)
        lv, rb = tonumber(lv) or 0, tonumber(rb) or 0
        if calcLevelXP then
            local ok, xp = pcall(calcLevelXP, lv, rb)
            if ok and type(xp) == "number" then return xp end
        end
        if lv == 0 then return 1 end
        local base = math.clamp(200 + (lv - 1) * 200, 1, 12000)
        return base + base * (math.clamp(rb, 0, 30) * 0.05)
    end

    -- true = you qualify, false = you don't, nil = can't tell (no readable data)
    function Rebirth.CanRebirth()
        local s = Rebirth.Read()
        if not (s and s.level and s.rebirth and s.xp) then return nil end
        if s.rebirth >= 30 or s.level < 100 then return false end
        local req = Rebirth.NeedXp(s.level, s.rebirth)
        return req <= 0 or s.xp >= req
    end
end

-- ------------------------------ Currency tracker ------------------------------
do
    local baseline = {}
    local startedAt = os.clock()

    local function Fmt(n)
        local a = math.abs(n)
        local s
        if a >= 1e9 then
            s = string.format("%.2fB", a / 1e9)
        elseif a >= 1e6 then
            s = string.format("%.2fM", a / 1e6)
        elseif a >= 1e3 then
            s = string.format("%.1fK", a / 1e3)
        else
            s = string.format("%d", math.floor(a + 0.5))
        end
        return (n < 0 and "-" or "") .. s
    end
    Currency.Fmt = Fmt

    local function Line(label, key, value)
        if value == nil then return label .. ": n/a" end
        if baseline[key] == nil then baseline[key] = value end
        local hours = math.max((os.clock() - startedAt) / 3600, 1 / 60)
        local gain = value - baseline[key]
        return string.format("%s: %s (%s%s, %s/hr)", label, Fmt(value), gain >= 0 and "+" or "", Fmt(gain), Fmt(gain / hours))
    end

    function Currency.Uptime()
        local elapsed = os.clock() - RunStats.StartedAt
        return string.format("%dh %02dm", math.floor(elapsed / 3600), math.floor((elapsed % 3600) / 60))
    end

    -- Three short lines: coins, gems, level/xp/rebirths
    function Currency.Lines()
        local s = Rebirth.Read()
        if not s then
            return { "Coins: n/a (no player data found)", "Gems: n/a", "Level: n/a" }
        end
        local levelLine = "Level: n/a"
        if s.level then
            levelLine = "Level " .. tostring(s.level)
            if s.xp and s.rebirth then
                levelLine = levelLine .. string.format(" | XP %s/%s", Fmt(s.xp), Fmt(Rebirth.NeedXp(s.level, s.rebirth)))
            end
            if s.rebirth then
                levelLine = levelLine .. " | Rebirths " .. tostring(s.rebirth)
            end
            if Rebirth.CanRebirth() == true then
                levelLine = levelLine .. " | READY"
            end
        end
        return { Line("Coins", "coins", s.coins), Line("Gems", "gems", s.gems), levelLine }
    end

    function Currency.Summary()
        local lines = Currency.Lines()
        return string.format("Uptime %s | Maps %d | Escapes %d | TAS %d ok / %d failed\n%s\n%s\n%s",
            Currency.Uptime(), RunStats.MapsSeen, RunStats.Escapes, RunStats.SessionOk, RunStats.SessionFail,
            lines[1], lines[2], lines[3])
    end
end

-- -------------------------------- Button Aura ---------------------------------
-- Presses buttons near you (or the one the game is pointing at) while you play by hand.
do
    local lastPress = setmetatable({}, { __mode = "k" })
    local windowStart, windowCount = 0, 0
    local scanMap, scanAt, scanList = nil, 0, {}
    local session = {}
    getgenv().FloodGUI_AuraSession = session

    local function IsRandomName(s)
        if type(s) ~= "string" or #s == 0 then return false end
        for i = 1, #s do
            local c = s:sub(i, i)
            if c:lower() == c then return false end
        end
        return true
    end

    local function KnownPressed(part)
        for _, obj in ipairs({ part, part.Parent }) do
            for _, n in ipairs({ "Pressed", "IsPressed", "Completed", "Done" }) do
                if obj:GetAttribute(n) == true then return true end
                local child = obj:FindFirstChild(n)
                if child and child:IsA("ValueBase") and child.Value == true then return true end
            end
        end
        return false
    end

    -- Skips exit regions and fuse buttons (pressing a fuse button next to you can kill you)
    local function IsButtonPart(p)
        if not (p and p:IsA("BasePart") and p.Parent) then return false end
        local n = p.Name:lower()
        if n:find("exit", 1, true) or n:find("region", 1, true) then return false end
        if p:FindFirstChild("Fuse", true) or p.Parent:FindFirstChild("Fuse", true) then return false end
        return true
    end

    local function ScanButtons(map)
        local now = os.clock()
        if scanMap == map and now - scanAt < 1.5 then return scanList end
        scanMap, scanAt, scanList = map, now, {}
        for _, obj in ipairs(map:GetDescendants()) do
            if obj:IsA("Model") and (IsRandomName(obj.Name) or obj:FindFirstChildWhichIsA("BillboardGui", true)) then
                for _, ch in ipairs(obj:GetChildren()) do
                    if ch:IsA("BasePart") and tostring(ch.BrickColor) ~= "Medium stone grey"
                        and ch:FindFirstChild("TouchInterest", true) and IsButtonPart(ch) then
                        scanList[#scanList + 1] = ch
                        break
                    end
                end
            end
            if #scanList >= 80 then break end
        end
        return scanList
    end

    local function Press(part, cooldown)
        local now = os.clock()
        if lastPress[part] and now - lastPress[part] < cooldown then return end
        if now - windowStart >= 0.25 then
            windowStart, windowCount = now, 0
        end
        if windowCount >= 6 then return end
        windowCount = windowCount + 1
        lastPress[part] = now
        pcall(function() PressedMapButton:FireServer(part) end)
    end

    task.spawn(function()
        local warned = false
        while getgenv().FloodGUI_AuraSession == session do
            task.wait(0.1)
            if not State.ButtonAura or State.CurrentlyFarming or getgenv().IsTASPlaying then
                continue
            end
            if not PressedMapButton then
                if not warned then
                    warned = true
                    Alert("Button Aura: PressedMapButton remote not found.", "Warning")
                end
                continue
            end
            warned = false

            local mp = Workspace:FindFirstChild("Multiplayer")
            local map = mp and (mp:FindFirstChild("Map") or mp:FindFirstChild("NewMap"))
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            local playing = LocalPlayer:GetAttribute("IsPlaying")
            if playing == nil then playing = Check("InGame") end
            if not (map and hrp and playing) then continue end

            local function InRange(part)
                return not State.AuraUseDistance or (hrp.Position - part.Position).Magnitude <= State.AuraDist
            end

            -- The buttons the game is currently pointing you at
            for _, value in ipairs({ QF.Button, QF.Next }) do
                local part = ResolveToInstance(value)
                if part and IsButtonPart(part) and part:IsDescendantOf(map) and InRange(part) then
                    Press(part, 0.25)
                end
            end

            -- Any other button in range
            for _, part in ipairs(ScanButtons(map)) do
                if part.Parent and InRange(part) and not KnownPressed(part) then
                    Press(part, 1.5)
                end
            end
        end
    end)
end

-- ---------------------------------- Anti-Void ---------------------------------
do
    local safeCFrame = nil
    local lastRescue = 0

    TrackConnection(RunService.Heartbeat:Connect(function()
        if not State.AntiVoid or getgenv().IsTASPlaying then return end
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        if not hrp or not hum or hum.Health <= 0 then return end

        local voidY = Workspace.FallenPartsDestroyHeight
        if hrp.Position.Y > voidY + 160 then
            safeCFrame = hrp.CFrame
        elseif safeCFrame and os.clock() - lastRescue > 1 then
            lastRescue = os.clock()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            hrp.CFrame = safeCFrame + Vector3.new(0, 12, 0)
            Alert("Anti-Void: pulled you back from the void.", "Info")
        end
    end))
end

-- ----------------------------------- Click TP ---------------------------------
do
    local lastTp = 0

    local function TpToScreen(x, y)
        if not State.ClickTP or os.clock() - lastTp < 0.2 then return end
        local cam = Workspace.CurrentCamera
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not cam or not hrp then return end

        local ray = cam:ViewportPointToRay(x, y)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { char }
        local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
        if result then
            lastTp = os.clock()
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.CFrame = CFrame.new(result.Position + Vector3.new(0, 3, 0))
        end
    end

    -- Desktop: Ctrl + click
    TrackConnection(UserInputService.InputBegan:Connect(function(input, processed)
        if processed or input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
            local pos = UserInputService:GetMouseLocation()
            TpToScreen(pos.X, pos.Y)
        end
    end))

    -- Mobile: tap the world
    TrackConnection(UserInputService.TouchTapInWorld:Connect(function(position, processed)
        if processed then return end
        TpToScreen(position.X, position.Y)
    end))
end

-- ----------------------------------- AFK mode ---------------------------------
do
    local gui, statsLabel
    local previousFps = 60

    -- A previous run may have left rendering off
    pcall(function() RunService:Set3dRenderingEnabled(true) end)
    if getgenv().FloodGUI_AfkGui then
        pcall(function() getgenv().FloodGUI_AfkGui:Destroy() end)
        getgenv().FloodGUI_AfkGui = nil
    end

    function Afk.Text()
        local lines = Currency.Lines()
        return string.format("Uptime: %s\nMaps: %d | Escapes: %d\nTAS: %d ok / %d failed\n%s\n%s\n%s\n\nFPS cap: %d",
            Currency.Uptime(), RunStats.MapsSeen, RunStats.Escapes, RunStats.SessionOk, RunStats.SessionFail,
            lines[1], lines[2], lines[3], State.AfkFps)
    end

    function Afk.Disable()
        if not Afk.Active then return end
        Afk.Active = false
        pcall(function() RunService:Set3dRenderingEnabled(true) end)
        if type(setfpscap) == "function" then pcall(setfpscap, previousFps) end
        if gui then
            pcall(function() gui:Destroy() end)
            gui, statsLabel = nil, nil
            getgenv().FloodGUI_AfkGui = nil
        end
        -- keep the menu toggle in step when this was triggered from the overlay
        local toggle = Config.Toggles["AFK Mode (3D off + low FPS)"]
        if toggle and type(toggle.UpdateToggle) == "function" then
            pcall(toggle.UpdateToggle, toggle, "AFK Mode (3D off + low FPS)", false)
        end
        Alert("AFK mode off.", "Info")
    end

    function Afk.Enable()
        if Afk.Active then return end
        Afk.Active = true

        if type(getfpscap) == "function" then
            local ok, cap = pcall(getfpscap)
            if ok and type(cap) == "number" and cap > 0 then previousFps = cap end
        end

        gui = Instance.new("ScreenGui")
        gui.Name = "FloodGUI_AFK"
        gui.ResetOnSpawn = false
        gui.IgnoreGuiInset = true
        gui.DisplayOrder = 1000000
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        local bg = Instance.new("Frame")
        bg.Size = UDim2.new(1, 0, 1, 0)
        bg.BackgroundColor3 = Color3.new(0, 0, 0)
        bg.BorderSizePixel = 0
        bg.Active = true
        bg.Parent = gui

        local title = Instance.new("TextLabel")
        title.Size = UDim2.new(1, 0, 0, 40)
        title.Position = UDim2.new(0, 0, 0.12, 0)
        title.BackgroundTransparency = 1
        title.Text = "AFK MODE"
        title.TextColor3 = Color3.fromRGB(200, 25, 35)
        title.Font = Enum.Font.GothamBold
        title.TextSize = 26
        title.Parent = bg

        statsLabel = Instance.new("TextLabel")
        statsLabel.Size = UDim2.new(1, -40, 0.5, 0)
        statsLabel.Position = UDim2.new(0, 20, 0.2, 0)
        statsLabel.BackgroundTransparency = 1
        statsLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
        statsLabel.Font = Enum.Font.Gotham
        statsLabel.TextSize = 18
        statsLabel.TextWrapped = true
        statsLabel.TextYAlignment = Enum.TextYAlignment.Top
        statsLabel.Text = Afk.Text()
        statsLabel.Parent = bg

        local exit = Instance.new("TextButton")
        exit.Size = UDim2.new(0, 220, 0, 50)
        exit.Position = UDim2.new(0.5, -110, 0.82, 0)
        exit.BackgroundColor3 = Color3.fromRGB(180, 20, 30)
        exit.Text = "Exit AFK Mode"
        exit.TextColor3 = Color3.new(1, 1, 1)
        exit.Font = Enum.Font.GothamBold
        exit.TextSize = 18
        exit.Parent = bg
        Instance.new("UICorner", exit).CornerRadius = UDim.new(0, 8)
        exit.Activated:Connect(Afk.Disable)

        local parent = (type(gethui) == "function" and gethui()) or CoreGui
        local ok = pcall(function() gui.Parent = parent end)
        if not ok or not gui.Parent then
            pcall(function() gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end)
        end
        getgenv().FloodGUI_AfkGui = gui

        pcall(function() RunService:Set3dRenderingEnabled(false) end)
        if type(setfpscap) == "function" then pcall(setfpscap, State.AfkFps) end
        Alert("AFK mode on. Tap 'Exit AFK Mode' to come back.", "Success")

        task.spawn(function()
            while Afk.Active and statsLabel and statsLabel.Parent do
                pcall(function() statsLabel.Text = Afk.Text() end)
                task.wait(1)
            end
        end)
    end
end

-- ------------------------ Late remote binding (FE2CM etc.) ---------------------
-- Some remotes show up after the script starts, or only under alternate names.
do
    local session = {}
    getgenv().FloodGUI_RemoteWatchSession = session
    local goalBound = UpdGoalLocator ~= nil

    task.spawn(function()
        while getgenv().FloodGUI_RemoteWatchSession == session do
            task.wait(3)
            PressedMapButton = PressedMapButton or FindRemoteNow("PressedMapButton")
            SurvivedRemote = SurvivedRemote or FindRemoteNow("Survived")
            LoadedMapRemote = LoadedMapRemote or FindRemoteNow("LoadedMap")
            AddedWaiting = AddedWaiting or FindRemoteNow("AddedWaiting")
            RemoveWaiting = RemoveWaiting or FindRemoteNow("RemoveWaiting")
            ReqRebirth = ReqRebirth or FindRemoteNow("ReqRebirth")
            ReqPasskey = ReqPasskey or FindRemoteNow("ReqPasskey")
            if not goalBound then
                UpdGoalLocator = UpdGoalLocator or FindRemoteNow("UpdGoalLocator")
                if UpdGoalLocator then
                    goalBound = true
                    TrackConnection(UpdGoalLocator.OnClientEvent:Connect(function(p1, p2, p3, p4)
                        QF.Goal, QF.Button, QF.Next = p1, p2, p4
                    end))
                    Alert("Goal locator found; Quick Farm is ready.", "Success")
                end
            end
        end
    end)
end

-- ==============================================================================
-- [8F] EMBEDDED FE2 AUTOFARM BACKEND (SINGLE-GUI MODE)
-- The backend is isolated so an optional feature failure cannot prevent Flood GUI
-- from loading. Its standalone Topbar UI is disabled; all controls are exposed below.
-- ==============================================================================
do
    local __backendOk, __backendErr = pcall(function()
    local __exec = (function()
    	local function asFunction(value)
    		return type(value) == "function" and value or nil
    	end
    
    	return {
    		getgenv = asFunction(getgenv),
    		gethui = asFunction(gethui),
    		cloneref = asFunction(cloneref),
    		getsenv = asFunction(getsenv),
    		getfenv = asFunction(getfenv),
    		getconnections = asFunction(getconnections),
    		hookfunction = asFunction(hookfunction),
    		hookmetamethod = asFunction(hookmetamethod),
    		newcclosure = asFunction(newcclosure),
    		getgc = asFunction(getgc),
    		getinstances = asFunction(getinstances),
    		getnilinstances = asFunction(getnilinstances),
    		getupvalue = asFunction(getupvalue),
    		getupvalues = asFunction(getupvalues),
    		setupvalue = asFunction(setupvalue),
    		firetouchinterest = asFunction(firetouchinterest),
    		readfile = asFunction(readfile),
    		writefile = asFunction(writefile),
    		isfile = asFunction(isfile),
    		isfolder = asFunction(isfolder),
    		makefolder = asFunction(makefolder),
    		delfile = asFunction(delfile),
    		listfiles = asFunction(listfiles),
    		loader = asFunction(loadstring) or asFunction(load),
    	}
    end)()
    
    local __traceback = if type(debug) == "table" and type(debug.traceback) == "function" then debug.traceback else function(err)
    	return tostring(err)
    end
    
    local function __safeGlobalEnv()
    	local env = nil
    	if __exec.getgenv then
    		local ok, result = pcall(__exec.getgenv)
    		if ok and type(result) == "table" then
    			env = result
    		end
    	end
    	if type(env) == "table" then
    		return env
    	end
    	if type(_G) == "table" then
    		return _G
    	end
    	return {}
    end
    
    local __lt = (function()
    	local g = __safeGlobalEnv()
    	local sh = rawget(type(_G) == "table" and _G or {}, "shared")
    	local host = type(sh) == "table" and sh or (type(g) == "table" and g or nil)
    
    	local function fb()
    		return {
    			cs = function(n, cr)
    				local ok, svc = pcall(game.GetService, game, n)
    				if not ok or not svc then
    					return nil
    				end
    				if type(cr) == "function" then
    					local ok2, v = pcall(cr, svc)
    					if ok2 and v then
    						return v
    					end
    				end
    				return svc
    			end,
    			cm = function(s, m, ...)
    				local obj = s
    				if type(s) == "string" then
    					local ok, svc = pcall(game.GetService, game, s)
    					if not ok then
    						return nil
    					end
    					obj = svc
    				end
    				if typeof(obj) ~= "Instance" and type(obj) ~= "table" then
    					return nil
    				end
    				local fn = obj[m]
    				if type(fn) ~= "function" then
    					return nil
    				end
    				local ok, res = pcall(fn, obj, ...)
    				if ok then
    					return res
    				end
    				return nil
    			end,
    		}
    	end
    
    	if host then
    		local c = rawget(host, "__lt_service_resolver")
    		if type(c) == "table" then
    			return c
    		end
    	end
    
    	local out
    	local ok = pcall(function()
    		local ld = __exec.loader
    		if type(ld) ~= "function" then
    			error("loader unavailable")
    		end
    		local src = game:HttpGet("https://ltseverydayyou.github.io/ServiceResolver.luau")
    		local fn = ld(src, "@ServiceResolver.luau")
    		if type(fn) ~= "function" then
    			error("compile failed")
    		end
    		local t = fn()
    		if type(t) ~= "table" then
    			error("resolver load failed")
    		end
    		out = t
    	end)
    
    	if not ok or type(out) ~= "table" then
    		out = fb()
    	end
    
    	if host then
    		host.__lt_service_resolver = out
    	end
    
    	return out
    end)()
    local __NAUIProtector = (function()
    	local globalEnv = __safeGlobalEnv();
    	local sharedEnv = rawget(type(_G) == "table" and _G or {}, "shared");
    	local cacheHost = type(sharedEnv) == "table" and sharedEnv or (type(globalEnv) == "table" and globalEnv or nil);
    	if cacheHost then
    		local cached = rawget(cacheHost, "__lt_ui_protector");
    		if type(cached) == "table" then
    			return cached;
    		end;
    	end;
    	local loader = __exec.loader;
    	if type(loader) ~= "function" then
    		return nil;
    	end;
    	local okSource, source = pcall(function()
    		return game:HttpGet("https://ltseverydayyou.github.io/UIprotector.luau");
    	end);
    	if not okSource or type(source) ~= "string" or source == "" then
    		return nil;
    	end;
    	local chunk = loader(source, "@UIprotector.luau");
    	if type(chunk) ~= "function" then
    		return nil;
    	end;
    	local okLoaded, loaded = pcall(chunk);
    	if okLoaded and type(loaded) == "table" then
    		if cacheHost then
    			cacheHost.__lt_ui_protector = loaded;
    		end;
    		return loaded;
    	end;
    	return nil;
    end)();
    local g = __safeGlobalEnv()
    local sh = rawget(type(_G) == "table" and _G or {}, "shared")
    local host = type(sh) == "table" and sh or (type(g) == "table" and g or nil)
    
    if host and type(host.__lt_af_ctx) == "table" then
    	local old = host.__lt_af_ctx
    	if type(old.stop) == "function" then
    		pcall(old.stop)
    	elseif type(old.applyFeMovement) == "function" then
    		if type(old.opt) == "table" then
    			old.opt.fePhysicsOn = false
    		end
    		pcall(old.applyFeMovement, true)
    	elseif type(old.con) == "table" then
    		for _, c in old.con do
    			if c and type(c.Disconnect) == "function" then
    				pcall(function()
    					c:Disconnect()
    				end)
    			end
    		end
    	end
    	old.live = false
    	host.__lt_af_ctx = nil
    end
    
    local ctx = {
    	live = true,
    	con = {},
    	threads = {},
    	ui = {},
    	opt = {},
    	cache = {},
    	flood = {},
    	exec = __exec,
    }
    
    if host then
    	host.__lt_af_ctx = ctx
    end
    
    local __NAOriginalGetHui = __exec.gethui;
    ctx.gethui = function()
    	if __NAUIProtector and type(__NAUIProtector.huiGrabber) == "function" then
    		local ok, ui = pcall(__NAUIProtector.huiGrabber);
    		if ok and typeof(ui) == "Instance" then
    			return ui;
    		end;
    	end;
    	if type(__NAOriginalGetHui) == "function" then
    		local ok, ui = pcall(__NAOriginalGetHui);
    		if ok then
    			return ui;
    		end;
    	end;
    	return nil;
    end;
    ctx.__NAProtectUI = function(gui, options)
    	if __NAUIProtector and type(__NAUIProtector.protectUI) == "function" then
    		local ok, protected = pcall(__NAUIProtector.protectUI, gui, options);
    		if ok and protected then
    			return protected;
    		end;
    	end;
    	return nil;
    end;
    
    ctx.protectedScreen = function(name)
    	local gui = nil
    	if __NAUIProtector and type(__NAUIProtector.getScreenGui) == "function" then
    		local ok, res = pcall(__NAUIProtector.getScreenGui, name)
    		if ok and typeof(res) == "Instance" then
    			gui = res
    		end
    	end
    	if not gui then
    		gui = Instance.new("ScreenGui")
    		gui.Name = name
    		local par = nil
    		if __NAUIProtector and type(__NAUIProtector.parent) == "function" then
    			local ok, res = pcall(__NAUIProtector.parent)
    			if ok and typeof(res) == "Instance" then
    				par = res
    			end
    		end
    		if not par then
    			local cg = type(ctx.gt) == "function" and ctx.gt("CoreGui") or nil
    			local ps = type(ctx.gt) == "function" and ctx.gt("Players") or nil
    			local lp = ps and ps.LocalPlayer or nil
    			par = ctx.gethui() or cg or (lp and lp:FindFirstChildOfClass("PlayerGui"))
    		end
    		if not par then
    			return nil
    		end
    		pcall(function()
    			gui.Parent = par
    		end)
    	end
    	pcall(function()
    		gui.Name = name
    		gui.IgnoreGuiInset = true
    		gui.ResetOnSpawn = false
    		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    	end)
    	ctx.__NAProtectUI(gui, {
    		name = name,
    		keepName = true,
    		harden = true,
    		deep = true,
    		watch = true,
    		rename = false,
    	})
    	return gui
    end
    
    ctx.pruneCons = function()
    	for i = #ctx.con, 1, -1 do
    		local c = ctx.con[i]
    		if not c or c.Connected == false then
    			table.remove(ctx.con, i)
    		end
    	end
    end
    
    ctx.bind = function(c)
    	if c then
    		ctx.con[#ctx.con + 1] = c
    		if #ctx.con % 32 == 0 then
    			ctx.pruneCons()
    		end
    	end
    	return c
    end
    
    ctx.dropThread = function(th)
    	for i = #ctx.threads, 1, -1 do
    		if ctx.threads[i] == th then
    			table.remove(ctx.threads, i)
    			return
    		end
    	end
    end
    
    ctx.spawnLoop = function(fn, ...)
    	local args = table.pack(...)
    	local th
    	th = task.spawn(function()
    		local ok, err = xpcall(function()
    			return fn(table.unpack(args, 1, args.n))
    		end, __traceback)
    		args = nil
    		if not ok and (type(ctx.current) ~= "function" or ctx.current()) then
    			warn(err)
    		end
    		ctx.dropThread(th)
    	end)
    	ctx.threads[#ctx.threads + 1] = th
    	return th
    end
    
    ctx.cut = function(c)
    	if c then
    		pcall(function()
    			c:Disconnect()
    		end)
    	end
    end
    
    ctx.clearCons = function(t)
    	if type(t) ~= "table" then
    		return
    	end
    	for i = #t, 1, -1 do
    		ctx.cut(t[i])
    		t[i] = nil
    	end
    end
    
    ctx.gt = function(n)
    	local ok, svc = pcall(function()
    		return __lt.cs(n, __exec.cloneref)
    	end)
    	if ok and svc then
    		return svc
    	end
    	local ok2, svc2 = pcall(game.GetService, game, n)
    	if ok2 then
    		if __exec.cloneref then
    			local ok3, v = pcall(__exec.cloneref, svc2)
    			if ok3 and v then
    				return v
    			end
    		end
    		return svc2
    	end
    	return nil
    end
    
    local Plr = ctx.gt("Players")
    local Wsp = ctx.gt("Workspace")
    local Rsp = ctx.gt("ReplicatedStorage")
    local Run = ctx.gt("RunService")
    local Uis = ctx.gt("UserInputService")
    local Sgui = ctx.gt("StarterGui")
    local Guis = ctx.gt("GuiService")
    local Cgui = ctx.gt("CoreGui")
    local LP = Plr and Plr.LocalPlayer or nil
    
    ctx.isPremiumPlayer = function(player)
    	if not player then
    		return false
    	end
    	local okMembership, membershipType = pcall(function()
    		return player.MembershipType
    	end)
    	if okMembership then
    		return membershipType == Enum.MembershipType.Premium
    	end
    
    	local okSubscription, hasSubscription = pcall(function()
    		return player.HasRobloxSubscription
    	end)
    	return okSubscription and hasSubscription == true
    end
    
    ctx.isLocalPremium = function()
    	return ctx.isPremiumPlayer(LP)
    end
    
    ctx.compatibility = {
    	advancedEnvironment = __exec.getsenv ~= nil,
    	functionEnvironment = __exec.getfenv ~= nil,
    	signalIntrospection = __exec.getconnections ~= nil,
    	functionHooking = __exec.hookfunction ~= nil,
    	metamethodHooking = __exec.hookmetamethod ~= nil,
    	touchSimulation = __exec.firetouchinterest ~= nil,
    	filesystem = __exec.readfile ~= nil and __exec.writefile ~= nil,
    }
    ctx.compatibility.degraded = not (ctx.compatibility.advancedEnvironment and ctx.compatibility.signalIntrospection)
    
    ctx.hs = ctx.gt("HttpService")
    ctx.cfgPath = "ltseverydayyou-fe2/gay.json"
    ctx.cfgDir = "ltseverydayyou-fe2"
    ctx.gameProfiles = {
    	[323675642] = "FE2",
    	[761462079] = "FEM",
    	[4229990801] = "FE2CM",
    }
    ctx.placeProfiles = {
    	[12339127827] = "FE2_Retro",
    	[11951199229] = "FE2CM",
    	[12074120006] = "FE2CM",
    	[14708572114] = "FE2CM",
    }
    ctx.fe2cmPlaces = {
    	[11951199229] = true,
    	[12074120006] = true,
    	[14708572114] = true,
    }
    ctx.profileName = function()
    	ctx.tmpPlaceId = ctx.placeId()
    	if ctx.placeProfiles[ctx.tmpPlaceId] then
    		return ctx.placeProfiles[ctx.tmpPlaceId]
    	end
    	ctx.tmpGameId = ctx.gameId()
    	return ctx.gameProfiles[ctx.tmpGameId] or ("Game_" .. tostring(ctx.tmpGameId or "Unknown"))
    end
    
    ctx.placeId = function()
    	if ctx.cache.placeId ~= nil then
    		return ctx.cache.placeId
    	end
    	ctx.tmpPlaceId = nil
    	pcall(function()
    		ctx.tmpPlaceId = game.PlaceId
    	end)
    	ctx.cache.placeId = ctx.tmpPlaceId
    	return ctx.tmpPlaceId
    end
    
    ctx.gameId = function()
    	if ctx.cache.gameId ~= nil then
    		return ctx.cache.gameId
    	end
    	ctx.tmpGameId = nil
    	pcall(function()
    		ctx.tmpGameId = game.GameId
    	end)
    	ctx.cache.gameId = ctx.tmpGameId
    	return ctx.tmpGameId
    end
    
    ctx.hasFE2CMRuntime = function()
    	local remote = Rsp and Rsp:FindFirstChild("Remote")
    	local testFolder = remote and remote:FindFirstChild("TEST")
    	if testFolder then
    		local hasMapTesting = testFolder:FindFirstChild("ReqTestMap")
    			or testFolder:FindFirstChild("tSPOgWeVyzmFZtkPoORSawvTCEerdTpd")
    			or testFolder:FindFirstChild("wzLbxpDgodnfZRXLvbtMfaQsCyjSzVXs")
    		if hasMapTesting then
    			return true
    		end
    	end
    
    	local playerGui = LP and LP:FindFirstChildOfClass("PlayerGui")
    	local menuGui = playerGui and playerGui:FindFirstChild("MenuGui")
    	return menuGui and menuGui:FindFirstChild("MapTest") ~= nil or false
    end
    
    ctx.isFE2CMGame = function()
    	return ctx.gameId() == 4229990801
    		or ctx.fe2cmPlaces[ctx.placeId()] == true
    		or ctx.hasFE2CMRuntime()
    end
    
    ctx.isFE2Game = function()
    	return ctx.gameId() == 323675642
    		or ctx.placeId() == 12339127827
    		or ctx.isFE2CMGame()
    end
    
    ctx.isRetroGame = function()
    	return ctx.placeId() == 12339127827
    end
    
    ctx.isFEMGame = function()
    	return ctx.gameId() == 761462079
    end
    
    ctx.helperTitle = function()
    	if ctx.isFEMGame() then
    		return "FEM Helper"
    	end
    	if ctx.isFE2CMGame() then
    		return "FE2CM Helper"
    	end
    	if ctx.isRetroGame() then
    		return "FE2 Retro Helper"
    	end
    	if ctx.isFE2Game() then
    		return "FE2 Helper"
    	end
    	return "FE2 Helper"
    end
    
    ctx.helperIconName = function()
    	return (ctx.helperTitle():gsub("%s+", "_")) .. "_Dropdown"
    end
    
    ctx.support = function(k)
    	if ctx.isFEMGame() then
    		return ({
    			start = true,
    			aura = true,
    			bonus = false,
    			challenges = false,
    			flood = false,
    			paid = true,
    			shop = true,
    			clip = false,
    			rescue = false,
    			fpfx = false,
    			dev = false,
    			zip = true,
    			infAir = true,
    			infJump = true,
    			clickTp = true,
    			next = true,
    			femVote = true,
    			survive = false,
    		})[k] == true
    	end
    	if ctx.isRetroGame() then
    		return ({
    			start = true,
    			aura = true,
    			bonus = false,
    			challenges = false,
    			flood = false,
    			paid = true,
    			shop = true,
    			clip = true,
    			rescue = false,
    			fpfx = false,
    			dev = false,
    			zip = false,
    			infAir = true,
    			infJump = true,
    			clickTp = true,
    			next = true,
    			femVote = false,
    			survive = true,
    		})[k] == true
    	end
    	if ctx.isFE2CMGame() then
    		return ({
    			start = true,
    			aura = true,
    			bonus = true,
    			challenges = true,
    			flood = true,
    			paid = true,
    			shop = true,
    			clip = true,
    			rescue = true,
    			fpfx = true,
    			dev = true,
    			zip = true,
    			infAir = true,
    			infJump = true,
    			clickTp = true,
    			next = true,
    			femVote = false,
    			survive = true,
    		})[k] == true
    	end
    	if ctx.isFE2Game() then
    		return ({
    			start = true,
    			aura = true,
    			bonus = true,
    			challenges = true,
    			flood = true,
    			paid = true,
    			shop = true,
    			clip = true,
    			rescue = true,
    			fpfx = true,
    			dev = true,
    			zip = true,
    			infAir = true,
    			infJump = true,
    			clickTp = true,
    			next = true,
    			femVote = false,
    			survive = true,
    		})[k] == true
    	end
    	return k == "start" or k == "infJump" or k == "clickTp"
    end
    local MP = Wsp and (Wsp:FindFirstChild("Multiplayer") or Wsp:WaitForChild("Multiplayer", 10)) or nil
    
    local TPD = 0.05
    local BTD = 0.05
    local SCI = 0.08
    local VDY = -50
    local EXP = Vector3.new(50, -1, 50)
    local JMP = Vector3.new(0, 100, 0)
    local PSZ = Vector3.new(24, 2, 24)
    local ESY = 5
    local LFG = Vector3.new(0, 0, 100)
    local RRP = 5
    local RRG = 0.3
    local EXM = 50
    local FGM = 2
    local LHW = 8
    local PCD = 0.1 -- Button press cooldown per button/locator hit
    local RFD = { 0, 0.25, 0.75, 1.5, 3, 5 }
    local FDM = 160
    local VLM = 20
    local RCH = 12
    local LDB = 6
    local LDI = 0.1
    local BSI = 0.1 -- Direct button spam loop wait floor
    local ASI = 0.1 -- Button aura spam loop interval
    local PLI = 2 -- Loaded remote interval
    local PSI = 0.05 -- Survived remote interval while a round is active
    local PMW = 0.2 -- Passive remote loop wait / tick speed
    local FMI = 0.2
    local RSI = 3
    local SRI = 1.5
    local DRI = 6
    local RBI = 3
    local SFT = 20
    local SFI = 0.35
    local CHI = 1.5
    
    local on = false
    local cur = nil
    local tok = 0
    local aVc
    local nCc
    local nCd1
    local nCd2
    local chC
    local gui
    local btn
    local panel
    local plt
    local cTab = {}
    local locBtns = {}
    local pressTimes = setmetatable({}, { __mode = "k" })
    local fusePressed = setmetatable({}, { __mode = "k" })
    local pressWin = 0
    local pressCnt = 0
    local pressMax = 6
    local pressGap = 0.25
    local pressBudget = 2
    local bonusSeen = setmetatable({}, { __mode = "k" })
    local bMap = nil
    local bCache = nil
    local bCons = {}
    local bDirty = true
    local bScanAt = 0
    local locSeq = 0
    local roundCur = nil
    local roundTotal = nil
    local roundLeft = nil
    local roundState = nil
    local safeCf = nil
    local safeAt = 0
    local voidAt = 0
    local farmTok = 0
    local pdata = nil
    local lastData = 0
    local lastStat = 0
    local lastRb = 0
    local lastBurst = 0
    local survivedAt = 0
    local survivedSeen = false
    local statsSig = nil
    local lastFreshData = 0
    local pendingSaveSig = nil
    local saveFlushTok = 0
    local auraOn = false
    local auraUseDistance = true
    local auraDist = 7
    local auraTok = 0
    local auraList = {}
    local auraMap = nil
    local auraAt = 0
    local autoCollectBonuses = true
    local autoChallenges = false
    ctx.opt.floodOn = true
    ctx.opt.floodEnabled = true
    ctx.opt.floodRandom = false
    ctx.cache.floodTok = 0
    ctx.cache.floodHooks = setmetatable({}, { __mode = "k" })
    ctx.cache.uiTok = 0
    ctx.cache.uiHooks = setmetatable({}, { __mode = "k" })
    ctx.opt.passOn = true
    ctx.opt.paidOn = true
    ctx.opt.clipOn = false
    ctx.opt.fePhysicsOn = false
    ctx.opt.fpPartOn = false
    ctx.opt.rescueOn = false
    ctx.opt.devOn = false
    ctx.opt.wallLvl = 0
    ctx.opt.zipFastOn = false
    ctx.opt.zipSpeed = 90
    ctx.opt.zipStopOn = false
    ctx.opt.zipAutoOn = true
    ctx.opt.zipActive = false
    ctx.opt.infAirOn = false
    ctx.opt.infJumpOn = false
    ctx.opt.clickTpOn = false
    ctx.opt.femVoteOn = false
    ctx.opt.surviveLoopOn = false
    ctx.opt.claimBusy = false
    ctx.opt.shopBusy = false
    ctx.cache.zipOld = setmetatable({}, { __mode = "k" })
    ctx.cache.zipWatches = setmetatable({}, { __mode = "k" })
    ctx.cache.remoteByName = {}
    ctx.cache.auraPromptCons = {}
    ctx.cache.zipPromptCons = {}
    ctx.cache.godAt = 0
    ctx.cache.zipAt = 0
    ctx.cache.zipConn = nil
    ctx.cache.zipChar = nil
    ctx.cache.zipStateSource = nil
    ctx.cache.zipEventKnown = false
    ctx.cache.zipWasActive = false
    ctx.cache.zipMoverBaseline = setmetatable({}, { __mode = "k" })
    ctx.cache.zipDismountToken = 0
    ctx.cache.jumpHeld = false
    ctx.cache.jumpHeldUntil = 0
    ctx.cache.jumpButton = nil
    ctx.cache.jumpButtonCons = {}
    ctx.cache.airHum = nil
    ctx.cache.airHealthConn = nil
    ctx.cache.airDiedConn = nil
    ctx.cache.airHooked = false
    ctx.cache.airAlertEnv = nil
    ctx.cache.airAlertOld = nil
    ctx.cache.airFastAt = 0
    ctx.cache.airLocalAt = 0
    ctx.cache.airRemoteAt = 0
    ctx.cache.airProtectAt = 0
    ctx.cache.airFnEnv = nil
    ctx.cache.airTakeFn = nil
    ctx.cache.airSwitchFn = nil
    ctx.cache.airRegenRemote = nil
    ctx.cache.curMap = nil
    ctx.cache.curMapAt = 0
    ctx.cache.mapRef = nil
    ctx.cache.mapSettings = nil
    ctx.cache.mapExit = nil
    ctx.cache.mapExitAt = 0
    ctx.cache.femStarted = false
    ctx.cache.femVoteAt = 0
    ctx.cache.femLastVoteId = nil
    ctx.cache.femBtnStarted = false
    ctx.cache.femButtonPart = nil
    ctx.cache.femZipStarted = false
    ctx.cache.femZipStopStarted = false
    ctx.cache.femRopeData = nil
    ctx.cache.femRopeOld = setmetatable({}, { __mode = "k" })
    ctx.cache.jumpAt = 0
    ctx.cache.wallAt = 0
    ctx.cache.slideAt = 0
    ctx.flood.floodColors = {
    	water = Color3.fromHSV(0.6, 0.99, 0.99),
    	acid = Color3.fromHSV(0.33, 0.99, 0.99),
    	lava = Color3.fromHSV(0.01, 0.99, 0.99),
    }
    
    ctx.cfgKeys = {
    	"auraOn",
    	"auraUseDistance",
    	"auraDist",
    	"autoCollectBonuses",
    	"autoChallenges",
    	"floodOn",
    	"floodEnabled",
    	"floodRandom",
    	"paidOn",
    	"clipOn",
    	"fpPartOn",
    	"rescueOn",
    	"devOn",
    	"zipFastOn",
    	"zipSpeed",
    	"zipStopOn",
    	"zipAutoOn",
    	"infAirOn",
    	"infJumpOn",
    	"clickTpOn",
    	"femVoteOn",
    	"surviveLoopOn",
    }
    
    ctx.getSetting = function(k)
    	if k == "auraOn" then
    		return auraOn
    	elseif k == "auraUseDistance" then
    		return auraUseDistance
    	elseif k == "auraDist" then
    		return auraDist
    	elseif k == "autoCollectBonuses" then
    		return autoCollectBonuses
    	elseif k == "autoChallenges" then
    		return autoChallenges
    	elseif ctx.opt[k] ~= nil then
    		return ctx.opt[k]
    	end
    	return nil
    end
    
    ctx.setSetting = function(k, v)
    	if k == "auraOn" then
    		auraOn = v == true
    	elseif k == "auraUseDistance" then
    		auraUseDistance = v ~= false
    	elseif k == "auraDist" then
    		if type(v) == "number" then
    			auraDist = math.max(0, tonumber(v) or auraDist)
    		end
    	elseif k == "autoCollectBonuses" then
    		autoCollectBonuses = v == true
    	elseif k == "autoChallenges" then
    		autoChallenges = v == true
    	elseif ctx.opt[k] ~= nil then
    		if type(ctx.opt[k]) == "number" then
    			ctx.opt[k] = tonumber(v) or ctx.opt[k]
    		else
    			ctx.opt[k] = v == true
    		end
    	end
    end
    
    ctx.fs = ctx.fs or {}
    ctx.fs.dir = ctx.cfgDir
    ctx.fs.path = ctx.cfgPath
    ctx.fs.ready = function()
    	ctx.fs.hasRead = __exec.readfile ~= nil
    	ctx.fs.hasWrite = __exec.writefile ~= nil
    	ctx.fs.hasIsFile = __exec.isfile ~= nil
    	ctx.fs.hasIsFolder = __exec.isfolder ~= nil
    	ctx.fs.hasMakeFolder = __exec.makefolder ~= nil
    	ctx.fs.hasDeleteFile = __exec.delfile ~= nil
    	ctx.fs.hasListFiles = __exec.listfiles ~= nil
    	ctx.fs.hasAppendFile = type(appendfile) == "function"
    	ctx.fs.hasLoadFile = type(loadfile) == "function"
    	return ctx.fs.hasRead and ctx.fs.hasWrite and ctx.fs.hasIsFile
    end
    
    ctx.fs.jsonEncode = function(t)
    	if not ctx.hs then
    		return nil
    	end
    	ctx.fs.ok, ctx.fs.res = pcall(function()
    		return ctx.hs:JSONEncode(t)
    	end)
    	if ctx.fs.ok and type(ctx.fs.res) == "string" then
    		return ctx.fs.res
    	end
    	return nil
    end
    
    ctx.fs.jsonDecode = function(s)
    	if not ctx.hs then
    		return nil
    	end
    	ctx.fs.ok, ctx.fs.res = pcall(function()
    		return ctx.hs:JSONDecode(s)
    	end)
    	if ctx.fs.ok and type(ctx.fs.res) == "table" then
    		return ctx.fs.res
    	end
    	return nil
    end
    
    ctx.fs.ensure = function()
    	if not ctx.fs.ready() then
    		return false
    	end
    	if ctx.fs.hasIsFolder and ctx.fs.hasMakeFolder then
    		pcall(function()
    			if not __exec.isfolder(ctx.fs.dir) then
    				__exec.makefolder(ctx.fs.dir)
    			end
    		end)
    	end
    	return true
    end
    
    ctx.fs.write = function(path, txt)
    	if not ctx.fs.ensure() or type(txt) ~= "string" then
    		return false
    	end
    	ctx.fs.ok = pcall(__exec.writefile, path, txt)
    	return ctx.fs.ok == true
    end
    
    ctx.fs.read = function(path)
    	if not ctx.fs.ready() then
    		return nil
    	end
    	ctx.fs.ok, ctx.fs.res = pcall(function()
    		if not __exec.isfile(path) then
    			return nil
    		end
    		return __exec.readfile(path)
    	end)
    	if ctx.fs.ok and type(ctx.fs.res) == "string" then
    		return ctx.fs.res
    	end
    	return nil
    end
    
    ctx.readCfgRoot = function()
    	ctx.tmpTxt = ctx.fs.read(ctx.cfgPath)
    	if type(ctx.tmpTxt) ~= "string" or ctx.tmpTxt == "" then
    		return {}
    	end
    	ctx.tmpData = ctx.fs.jsonDecode(ctx.tmpTxt)
    	if type(ctx.tmpData) == "table" then
    		return ctx.tmpData
    	end
    	return {}
    end
    
    ctx.profileCfg = function(root)
    	ctx.tmpProfile = ctx.profileName()
    	if type(root) ~= "table" then
    		return {}
    	end
    	if type(root[ctx.tmpProfile]) == "table" then
    		return root[ctx.tmpProfile]
    	end
    	for _, k in ctx.cfgKeys do
    		if root[k] ~= nil then
    			return root
    		end
    	end
    	return {}
    end
    
    ctx.saveNow = function()
    	ctx.tmpRootCfg = ctx.readCfgRoot()
    	ctx.tmpProfile = ctx.profileName()
    	ctx.tmpCfg = {}
    	for _, k in ctx.cfgKeys do
    		ctx.tmpCfg[k] = ctx.getSetting(k)
    	end
    	ctx.tmpRootCfg[ctx.tmpProfile] = ctx.tmpCfg
    	ctx.tmpTxt = ctx.fs.jsonEncode(ctx.tmpRootCfg)
    	if type(ctx.tmpTxt) ~= "string" then
    		return false
    	end
    	return ctx.fs.write(ctx.cfgPath, ctx.tmpTxt)
    end
    
    ctx.saveSoon = function()
    	ctx.cache.saveTok = (ctx.cache.saveTok or 0) + 1
    	task.delay(0.2, function(tk)
    		if ctx.alive() and ctx.cache.saveTok == tk then
    			ctx.saveNow()
    		end
    	end, ctx.cache.saveTok)
    end
    
    ctx.loadSettings = function()
    	ctx.tmpRootCfg = ctx.readCfgRoot()
    	ctx.tmpData = ctx.profileCfg(ctx.tmpRootCfg)
    	if type(ctx.tmpData) ~= "table" then
    		return false
    	end
    	for _, k in ctx.cfgKeys do
    		if ctx.tmpData[k] ~= nil then
    			ctx.setSetting(k, ctx.tmpData[k])
    		end
    	end
    	return true
    end
    
    ctx.loadSettings()
    ctx.opt.fePhysicsOn = false
    local optionsOpen = false
    local chSeen = setmetatable({}, { __mode = "k" })
    local chWallSeen = setmetatable({}, { __mode = "k" })
    local chZipSeen = setmetatable({}, { __mode = "k" })
    local chSlideSeen = setmetatable({}, { __mode = "k" })
    local chMap = nil
    local chAt = 0
    local chCache = {}
    local zipBusy = false
    local chSlideAt = 0
    local chWallAt = 0
    local chZipAt = 0
    local chAirAt = 0
    local chDumpAt = 0
    local chRegAt = 0
    local chLavaAt = 0
    local chCons = {}
    local chTok = 0
    local chIndex = { air = {}, wall = {}, zip = {}, slide = {} }
    
    ctx.current = function()
    	return ctx.live and (not host or host.__lt_af_ctx == ctx)
    end
    
    ctx.alive = function()
    	return ctx.current() and LP and LP.Parent and Run ~= nil
    end
    
    ctx.killPlat = function()
    	if plt and plt.Parent then
    		pcall(function()
    			plt:Destroy()
    		end)
    	end
    	plt = nil
    end
    
    ctx.clearLocators = function()
    	locBtns = {}
    	locSeq += 1
    	pressTimes = setmetatable({}, { __mode = "k" })
    end
    
    ctx.releaseRoot = function(root)
    	if type(ctx.rh) ~= "function" and not root then
    		return
    	end
    	local r, h = root, nil
    	if not r then
    		r, h = ctx.rh(false)
    	elseif type(ctx.rh) == "function" then
    		local _, hum = ctx.rh(false)
    		h = hum
    	end
    	if r then
    		pcall(function()
    			r.Anchored = false
    			if r.AssemblyLinearVelocity.Magnitude < 0.05 then
    				r.AssemblyLinearVelocity = Vector3.new(0, 1, 0)
    			end
    		end)
    	end
    	if h then
    		pcall(function()
    			h.PlatformStand = false
    			h:ChangeState(Enum.HumanoidStateType.Running)
    		end)
    	end
    end
    
    ctx.clearBonuses = function()
    	for i = 1, #bCons do
    		ctx.cut(bCons[i])
    		bCons[i] = nil
    	end
    	bMap = nil
    	bCache = nil
    	bDirty = true
    	bScanAt = 0
    end
    
    ctx.stop = function()
    	if type(ctx.setFePhysicsFallback) == "function" then
    		ctx.setFePhysicsFallback(false)
    	end
    	if not ctx.live then
    		return
    	end
    	ctx.opt.fePhysicsOn = false
    	if type(ctx.applyFeMovement) == "function" then
    		pcall(ctx.applyFeMovement, true)
    	end
    	if type(ctx.restoreFeOptionManagers) == "function" then
    		pcall(ctx.restoreFeOptionManagers)
    	end
    	if type(ctx.setZipAttrs) == "function" then
    		pcall(ctx.setZipAttrs, false)
    	end
    	ctx.live = false
    	on = false
    	tok += 1
    	cur = nil
    	ctx.cut(aVc)
    	ctx.cut(nCc)
    	ctx.cut(nCd1)
    	ctx.cut(nCd2)
    	ctx.cut(chC)
    	ctx.cut(ctx.cache.zipConn)
    	ctx.cut(ctx.cache.infAirHb)
    	ctx.cut(ctx.cache.airHealthConn)
    	ctx.cut(ctx.cache.airDiedConn)
    	ctx.clearCons(ctx.cache.jumpButtonCons)
    	for _, th in ctx.threads do
    		if type(task.cancel) == "function" then
    			pcall(task.cancel, th)
    		end
    	end
    	ctx.threads = {}
    	aVc = nil
    	nCc = nil
    	nCd1 = nil
    	nCd2 = nil
    	chC = nil
    	ctx.cache.zipConn = nil
    	ctx.cache.infAirHb = nil
    	ctx.cache.airHealthConn = nil
    	ctx.cache.airDiedConn = nil
    	ctx.cache.airHealthHum = nil
    	ctx.cache.jumpHeld = false
    	ctx.cache.jumpHeldUntil = 0
    	ctx.cache.jumpButton = nil
    	for _, c in ctx.con do
    		ctx.cut(c)
    	end
    	ctx.con = {}
    	if type(ctx.restoreNc) == "function" then
    		ctx.restoreNc()
    	end
    	cTab = {}
    	pressTimes = setmetatable({}, { __mode = "k" })
    	bonusSeen = setmetatable({}, { __mode = "k" })
    	if ctx.clearBonuses then
    		ctx.clearBonuses()
    	end
    	if ctx.unprotectAirHealth then
    		ctx.unprotectAirHealth()
    	end
    	ctx.clearLocators()
    	auraList = {}
    	auraMap = nil
    	auraAt = 0
    	pressWin = 0
    	pressCnt = 0
    	roundCur = nil
    	roundTotal = nil
    	roundLeft = nil
    	roundState = nil
    	safeCf = nil
    	safeAt = 0
    	voidAt = 0
    	farmTok += 1
    	auraTok += 1
    	saveFlushTok += 1
    	pendingSaveSig = nil
    	ctx.killPlat()
    	ctx.releaseRoot()
    	if type(ctx.closeAuraPrompt) == "function" then
    		ctx.closeAuraPrompt()
    	elseif ctx.ui.auraPrompt then
    		pcall(function()
    			ctx.ui.auraPrompt:Destroy()
    		end)
    		ctx.ui.auraPrompt = nil
    	end
    	if type(ctx.closeZipPrompt) == "function" then
    		ctx.closeZipPrompt()
    	elseif ctx.ui.zipPrompt then
    		pcall(function()
    			ctx.ui.zipPrompt:Destroy()
    		end)
    		ctx.ui.zipPrompt = nil
    	end
    	if gui and gui.Parent then
    		pcall(function()
    			gui:Destroy()
    		end)
    	end
    	if ctx.ui.rootIcon then
    		pcall(function()
    			ctx.ui.rootIcon:destroy()
    		end)
    	end
    	if type(ctx.ui.menu) == "table" then
    		for _, ic in ctx.ui.menu do
    			if ic and type(ic.destroy) == "function" then
    				pcall(function()
    					ic:destroy()
    				end)
    			end
    		end
    	end
    	gui = nil
    	btn = nil
    	panel = nil
    	ctx.ui.optBtn = nil
    	ctx.ui.optionsFrame = nil
    	ctx.ui.auraBtn = nil
    	ctx.ui.distModeBtn = nil
    	ctx.ui.distBtn = nil
    	ctx.ui.distLabel = nil
    	ctx.ui.distRow = nil
    	ctx.ui.bonusBtn = nil
    	ctx.ui.chBtn = nil
    	ctx.ui.floodBtn = nil
    	ctx.ui.passBtn = nil
    	ctx.ui.paidBtn = nil
    	ctx.ui.buyCoinBtn = nil
    	ctx.ui.buyGemBtn = nil
    	ctx.ui.clipBtn = nil
    	ctx.ui.rescueBtn = nil
    	ctx.ui.devBtn = nil
    	ctx.ui.zipBtn = nil
    	ctx.ui.zipStopBtn = nil
    	ctx.ui.zipAutoBtn = nil
    	ctx.ui.infAirBtn = nil
    	ctx.ui.infJumpBtn = nil
    	ctx.ui.clickTpBtn = nil
    	ctx.ui.femVoteBtn = nil
    	ctx.ui.surviveBtn = nil
    	ctx.ui.nextBtn = nil
    	ctx.ui.rootIcon = nil
    	ctx.ui.menu = {}
    	ctx.cache.floodTok += 1
    	ctx.cache.uiTok += 1
    	ctx.cache.floodHooks = setmetatable({}, { __mode = "k" })
    	ctx.cache.uiHooks = setmetatable({}, { __mode = "k" })
    	chSeen = setmetatable({}, { __mode = "k" })
    	chWallSeen = setmetatable({}, { __mode = "k" })
    	chZipSeen = setmetatable({}, { __mode = "k" })
    	chSlideSeen = setmetatable({}, { __mode = "k" })
    	chMap = nil
    	chAt = 0
    	chCache = {}
    	chSlideAt = 0
    	chWallAt = 0
    	chZipAt = 0
    	chDumpAt = 0
    	chRegAt = 0
    	chLavaAt = 0
    	chTok += 1
    	for _, c in chCons do
    		ctx.cut(c)
    	end
    	chCons = {}
    	chIndex = { air = {}, wall = {}, zip = {}, slide = {} }
    	ctx.cache.remoteByName = {}
    	ctx.cache.zipOld = setmetatable({}, { __mode = "k" })
    	ctx.cache.zipWatches = setmetatable({}, { __mode = "k" })
    	ctx.cache.femRopeOld = setmetatable({}, { __mode = "k" })
    	ctx.cache.femRopeData = nil
    	ctx.cache.shopItems = nil
    	ctx.cache.airEnv = nil
    	ctx.cache.airFastAt = 0
    	ctx.cache.airLocalAt = 0
    	ctx.cache.airRemoteAt = 0
    	ctx.cache.airProtectAt = 0
    	ctx.cache.airFnEnv = nil
    	ctx.cache.airTakeFn = nil
    	ctx.cache.airSwitchFn = nil
    	ctx.cache.airRegenRemote = nil
    	ctx.cache.feApplyTok = (ctx.cache.feApplyTok or 0) + 1
    	ctx.cache.feApplying = false
    	ctx.cache.fePendingApply = false
    	ctx.cache.fePendingRestore = false
    	ctx.cache.fePatchState = nil
    	ctx.cache.feAppliedChar = nil
    	ctx.cache.buttonSpamKey = nil
    	ctx.cache.curMap = nil
    	ctx.cache.curMapAt = 0
    	ctx.cache.mapRef = nil
    	ctx.cache.mapSettings = nil
    	ctx.cache.mapExit = nil
    	ctx.cache.mapExitAt = 0
    	if host and host.__lt_af_ctx == ctx then
    		host.__lt_af_ctx = nil
    	end
    end
    
    ctx.descOf = function(obj)
    	if not obj then
    		return {}
    	end
    	local ok, res = pcall(function()
    		return obj:QueryDescendants("Instance")
    	end)
    	if ok and type(res) == "table" then
    		return res
    	end
    	return {}
    end
    
    ctx.ffc = function(obj, n, rec)
    	if not obj then
    		return nil
    	end
    	local ok, res = pcall(obj.FindFirstChild, obj, n, rec)
    	if ok then
    		return res
    	end
    	return nil
    end
    
    ctx.liveChildOf = function(obj, parent)
    	if not (obj and obj.Parent) then
    		return false
    	end
    	if not parent then
    		return true
    	end
    	local ok, res = pcall(function()
    		return obj:IsDescendantOf(parent)
    	end)
    	return ok and res == true
    end
    
    ctx.clearMapRuntime = function(nextMap)
    	ctx.clearLocators()
    	auraList = {}
    	auraMap = nil
    	auraAt = 0
    	pressTimes = setmetatable({}, { __mode = "k" })
    	fusePressed = setmetatable({}, { __mode = "k" })
    	pressWin = 0
    	pressCnt = 0
    	ctx.cache.buttonSpamKey = nil
    	bonusSeen = setmetatable({}, { __mode = "k" })
    	if bMap and bMap ~= nextMap then
    		ctx.clearBonuses()
    	end
    	if chMap and chMap ~= nextMap then
    		for _, c in chCons do
    			ctx.cut(c)
    		end
    		chCons = {}
    		chMap = nil
    		chAt = 0
    		chCache = {}
    		chIndex = { air = {}, wall = {}, zip = {}, slide = {} }
    	end
    end
    
    ctx.resetMapCache = function(map)
    	if map ~= nil and ctx.cache.mapRef == map then
    		return
    	end
    	ctx.clearMapRuntime(map)
    	ctx.cache.mapRef = map
    	ctx.cache.mapSettings = nil
    	ctx.cache.mapExit = nil
    	ctx.cache.mapExitAt = 0
    end
    
    ctx.mapSettings = function(map)
    	if not (map and map.Parent) then
    		ctx.resetMapCache(nil)
    		return nil
    	end
    	ctx.resetMapCache(map)
    	if ctx.liveChildOf(ctx.cache.mapSettings, map) then
    		return ctx.cache.mapSettings
    	end
    	ctx.cache.mapSettings = ctx.ffc(map, "Settings", false)
    	return ctx.cache.mapSettings
    end
    
    ctx.mapExit = function(map)
    	if not (map and map.Parent) then
    		ctx.resetMapCache(nil)
    		return nil
    	end
    	ctx.resetMapCache(map)
    	if ctx.liveChildOf(ctx.cache.mapExit, map) then
    		return ctx.cache.mapExit
    	end
    	local now = os.clock()
    	if now < (ctx.cache.mapExitAt or 0) then
    		return nil
    	end
    	ctx.cache.mapExit = ctx.ffc(map, "ExitRegion", true)
    	ctx.cache.mapExitAt = now + (ctx.cache.mapExit and 2 or 0.25)
    	return ctx.cache.mapExit
    end
    
    ctx.uiPar = function()
    	if type(ctx.gethui) == "function" then
    		local ok, ui = pcall(ctx.gethui)
    		if ok and typeof(ui) == "Instance" then
    			return ui
    		end
    	end
    	return Cgui or (LP and LP:FindFirstChildOfClass("PlayerGui")) or nil
    end
    
    local Cls = LP and LP:FindFirstChild("PlayerScripts") or nil
    local Clm = Cls and Cls:FindFirstChild("CL_MAIN_GameScript") or nil
    local cenv = nil
    
    if Clm and __exec.getsenv then
    	local ok, env = pcall(__exec.getsenv, Clm)
    	if ok and type(env) == "table" then
    		cenv = env
    	end
    end
    
    local alert = cenv and cenv.newAlert or nil
    
    ctx.note = function(msg)
    	msg = tostring(msg)
    
    	if type(alert) == "function" then
    		local ok = pcall(alert, msg, nil, nil, "rainbow")
    		if ok then
    			return
    		end
    		alert = nil
    	end
    
    	if Sgui then
    		for _ = 1, 3 do
    			local ok = pcall(function()
    				Sgui:SetCore("SendNotification", {
    					Title = "AutoFarm",
    					Text = msg,
    					Duration = 3,
    				})
    			end)
    			if ok then
    				return
    			end
    			task.wait(0.15)
    		end
    	end
    
    	if Guis and type(Guis.SetCore) == "function" then
    		pcall(function()
    			Guis:SetCore("SendNotification", {
    				Title = "AutoFarm",
    				Text = msg,
    				Duration = 3,
    			})
    		end)
    	end
    end
    
    local Lift = nil
    local PressRemotes = {}
    local LocatorRemotes = {}
    local RoundStatsRemotes = {}
    local LoadedMapRemotes = {}
    local SurvivedRemotes = {}
    local PlayerDataRemotes = {}
    local ItemDataRemotes = {}
    local GameStateRemotes = {}
    local ChallengeRemotes = {
    	GetAirBubble = {},
    	SwimInLava = {},
    	RegeneratedAir = {},
    	SlideCheck = {},
    	Walljumped = {},
    	RideZipline = {},
    }
    local ZiplineRemotes = {
    	RideZipline = {},
    	Zipline = {},
    }
    local WalljumpRemotes = {
    	Walljump = {},
    }
    local RebirthRemote = nil
    local PasskeyRemote = nil
    local ItemDataFunction = nil
    local ConfirmItemRemote = nil
    local PassReqSeasonData = nil
    local PassReqSeasonList = nil
    local passKey = nil
    local FE2CalcLevelXP = nil
    do
    	local mods = Rsp and Rsp:FindFirstChild("Modules")
    	local shared = mods and mods:FindFirstChild("Shared")
    	local lib = shared and shared:FindFirstChild("FE2Library")
    	if lib and type(require) == "function" then
    		local ok, loaded = pcall(require, lib)
    		if ok and type(loaded) == "table" and type(loaded.calcLevelXP) == "function" then
    			FE2CalcLevelXP = loaded.calcLevelXP
    		end
    	end
    	local lib2 = mods and mods:FindFirstChild("Library")
    	if not FE2CalcLevelXP and lib2 and type(require) == "function" then
    		local ok, loaded = pcall(require, lib2)
    		if ok and type(loaded) == "table" and type(loaded.GetLevelExperience) == "function" then
    			FE2CalcLevelXP = function(lv)
    				return loaded.GetLevelExperience(lv)
    			end
    		end
    	end
    end
    
    do
    	local remFolders = {}
    	local seenFolders = {}
    
    	local function addFolder(folder)
    		if folder and not seenFolders[folder] then
    			seenFolders[folder] = true
    			remFolders[#remFolders + 1] = folder
    		end
    	end
    
    	addFolder(Rsp and Rsp:FindFirstChild("Remote"))
    	addFolder(Rsp and Rsp:FindFirstChild("Events"))
    	local rmt = Rsp and Rsp:FindFirstChild("Remote")
    	local chFolder = rmt and rmt:FindFirstChild("Challenges")
    	local gpFolder = rmt and rmt:FindFirstChild("Gameplay")
    	addFolder(chFolder)
    	addFolder(gpFolder)
    	addFolder(rmt and rmt:FindFirstChild("TEST"))
    	addFolder(rmt and rmt:FindFirstChild("Pass"))
    	addFolder(rmt and rmt:FindFirstChild("Goals"))
    	addFolder(rmt and rmt:FindFirstChild("ClientTimelines"))
    	addFolder(rmt and rmt:FindFirstChild("Replication"))
    
    	local function scanRuntime(name, cls)
    		local scanners = {}
    		if __exec.getnilinstances then
    			scanners[#scanners + 1] = __exec.getnilinstances
    		end
    		if __exec.getinstances then
    			scanners[#scanners + 1] = __exec.getinstances
    		end
    		for _, fn in scanners do
    			local ok, list = pcall(fn)
    			if ok and type(list) == "table" then
    				for _, obj in list do
    					if typeof(obj) == "Instance" and obj.Name == name and (not cls or obj:IsA(cls)) then
    						return obj
    					end
    				end
    			end
    		end
    		return nil
    	end
    
    	local function findRemote(name, cls)
    		for _, folder in remFolders do
    			local obj = folder:FindFirstChild(name) or folder:FindFirstChild(name, true)
    			if obj and (not cls or obj:IsA(cls)) then
    				return obj
    			end
    		end
    		return scanRuntime(name, cls)
    	end
    
    	local ok, r = pcall(function()
    		return findRemote("dKgyIXnLdhwvSyEorkEWJJAkgUslGCtR", "RemoteEvent")
    			or findRemote("sTYfsJjxNdIpKgbXIuymAQiYcmAaORRN", "RemoteEvent")
    			or findRemote("AddedWaiting", "RemoteEvent")
    	end)
    	Lift = ok and r or nil
    
    	local function addRemote(list, name)
    		local obj = findRemote(name, "RemoteEvent")
    		if obj and obj:IsA("RemoteEvent") then
    			for _, old in list do
    				if old == obj then
    					return
    				end
    			end
    			list[#list + 1] = obj
    		end
    	end
    
    	local function addFolderRemote(list, folder, name)
    		local obj = folder and folder:FindFirstChild(name)
    		if obj and obj:IsA("RemoteEvent") then
    			for _, old in list do
    				if old == obj then
    					return
    				end
    			end
    			list[#list + 1] = obj
    		end
    	end
    
    	local pk = findRemote("ReqPasskey", "RemoteFunction")
    	if pk and pk:IsA("RemoteFunction") then
    		PasskeyRemote = pk
    	end
    
    	local rb = findRemote("ReqRebirth", "RemoteEvent") or findRemote("rebirth", "RemoteEvent") or findRemote("LxWowhVdggjbxLTozuicVKHltFbUuVUg", "RemoteEvent")
    	if rb and rb:IsA("RemoteEvent") then
    		RebirthRemote = rb
    	end
    
    	addRemote(PressRemotes, "PressedMapButton")
    	addRemote(PressRemotes, "igzyswprgEbMOxwZWHUxvFWNJhDtaODb")
    	addRemote(LocatorRemotes, "UpdGoalLocator")
    	addRemote(LocatorRemotes, "FiIxfRCqDOTWRKHqFMoRjSaAxXOutMzD")
    	addRemote(LocatorRemotes, "SetButtonLocator")
    	addRemote(RoundStatsRemotes, "UpdIngameStats")
    	addRemote(RoundStatsRemotes, "flDEUOrLddFXZVDiezUpxyiHWduVnlEC")
    	addRemote(RoundStatsRemotes, "UpdateGameInfo")
    	addRemote(LoadedMapRemotes, "LoadedMap")
    	addRemote(SurvivedRemotes, "Survived")
    	addRemote(PlayerDataRemotes, "UpdPlayerData")
    	addRemote(PlayerDataRemotes, "mbTUpXEtICXoMoBrBEoiHpRywCzJjtba")
    	addRemote(ItemDataRemotes, "ReqItemData")
    	addRemote(ItemDataRemotes, "jBRXdUHKhwduqDelrUCPdolYbvaFGFMi")
    	local idf = findRemote("ReqItemData", "RemoteFunction")
    	if idf and idf:IsA("RemoteFunction") then
    		ItemDataFunction = idf
    	end
    	ConfirmItemRemote = findRemote("ConfirmItem", "RemoteEvent") or findRemote("IBHzeWzRcHyDJcPNXXfEkcXARFJrSvvt", "RemoteEvent")
    	do
    		local rr = Rsp and Rsp:FindFirstChild("Remote")
    		local pf = rr and rr:FindFirstChild("Pass")
    		local rsd = pf and (pf:FindFirstChild("ReqSeasonData") or pf:FindFirstChild("wYXTxuCjheiXJfcizJPuPwrfonMOVMVJ"))
    		local rsl = pf and (pf:FindFirstChild("ReqSeasonList") or pf:FindFirstChild("eumTfRpsBhpIbMhPbsgBhNWijGPZcWZZ"))
    		PassReqSeasonData = rsd and rsd:IsA("RemoteEvent") and rsd or nil
    		PassReqSeasonList = rsl and rsl:IsA("RemoteEvent") and rsl or nil
    	end
    	addRemote(GameStateRemotes, "UpdateGameState")
    	addRemote(GameStateRemotes, "FBbJEWQDfbOPQZBNaWtXPmnKTDndEbbK")
    	addRemote(ChallengeRemotes.GetAirBubble, "GetAirBubble")
    	addRemote(ChallengeRemotes.SwimInLava, "SwimInLava")
    	addRemote(ChallengeRemotes.SwimInLava, "fvgxdrskCQyGiyAbJXnVrzFRinSqigYN")
    	addRemote(ChallengeRemotes.RegeneratedAir, "RegeneratedAir")
    	addRemote(ChallengeRemotes.RegeneratedAir, "ZdwUWbHbtYFphslKtWDPwBpPOrOQbGPZ")
    	addRemote(ChallengeRemotes.SlideCheck, "SlideCheck")
    	addRemote(ChallengeRemotes.Walljumped, "Walljumped")
    	addRemote(ChallengeRemotes.Walljumped, "cLtjGlpevadbSJSvVQMCvNicyzbFZMGj")
    	addFolderRemote(ChallengeRemotes.RideZipline, chFolder, "RideZipline")
    	addFolderRemote(ZiplineRemotes.RideZipline, rmt, "RideZipline")
    	addRemote(ZiplineRemotes.Zipline, "Zipline")
    	addFolderRemote(ZiplineRemotes.Zipline, gpFolder, "Zipline")
    	addFolderRemote(WalljumpRemotes.Walljump, gpFolder, "Walljump")
    	addRemote(WalljumpRemotes.Walljump, "Walljump")
    end
    
    ctx.chr = function(w)
    	if not LP then
    		return nil
    	end
    	local c = LP.Character
    	if c then
    		return c
    	end
    	if w then
    		local ok, res = pcall(function()
    			return LP.CharacterAdded:Wait()
    		end)
    		if ok then
    			return res
    		end
    	end
    	return nil
    end
    
    ctx.rh = function(w)
    	local c = ctx.chr(w)
    	if not c then
    		return nil, nil, nil
    	end
    	local r = c:FindFirstChild("HumanoidRootPart")
    	local h = c:FindFirstChildOfClass("Humanoid")
    	if w then
    		if not r then
    			r = c:WaitForChild("HumanoidRootPart", 10)
    		end
    		if not h then
    			h = c:WaitForChild("Humanoid", 10)
    		end
    	end
    	return r, h, c
    end
    
    ctx.pivotRootTo = function(cf, r, c)
    	if typeof(cf) ~= "CFrame" then
    		return
    	end
    	if not r or not r.Parent then
    		r = select(1, ctx.rh(false))
    	end
    	if not c or not c.Parent then
    		c = ctx.chr(false)
    	end
    	if c and c.Parent and r and r.Parent then
    		local ok, pivot = pcall(function()
    			return c:GetPivot()
    		end)
    		if ok and pivot then
    			local ok2, rel = pcall(function()
    				return r.CFrame:ToObjectSpace(pivot)
    			end)
    			pcall(function()
    				c:PivotTo(ok2 and (cf * rel) or cf)
    			end)
    			return
    		end
    	end
    	if r and r.Parent then
    		pcall(function()
    			r:PivotTo(cf)
    		end)
    	end
    end
    
    ctx.voidY = function()
    	local y = -500
    	if Wsp then
    		pcall(function()
    			local v = Wsp.FallenPartsDestroyHeight
    			if type(v) == "number" and v == v then
    				y = v
    			end
    		end)
    	end
    	return y
    end
    
    ctx.limVel = function(r, hard)
    	if not r or not r.Parent then
    		return
    	end
    	pcall(function()
    		local v = r.AssemblyLinearVelocity
    		local x = math.clamp(v.X, -VLM, VLM)
    		local y = v.Y
    		if hard then
    			y = math.clamp(y, -VLM, VLM)
    		elseif y < -VLM then
    			y = -VLM
    		end
    		local z = math.clamp(v.Z, -VLM, VLM)
    		r.AssemblyLinearVelocity = Vector3.new(x, y, z)
    		local a = r.AssemblyAngularVelocity
    		if a.Magnitude > VLM then
    			r.AssemblyAngularVelocity = a.Unit * VLM
    		end
    	end)
    end
    
    ctx.saveSafe = function(r)
    	if not r or not r.Parent then
    		return
    	end
    	local y = ctx.voidY()
    	local pos = r.Position
    	if pos.Y > y + FDM then
    		safeCf = r.CFrame
    		safeAt = os.clock()
    	end
    end
    
    ctx.safeMapCf = function(map, r)
    	local y = ctx.voidY()
    	if safeCf and safeCf.Position.Y > y + FDM then
    		return safeCf + Vector3.new(0, RCH, 0)
    	end
    	if map and map.Parent then
    		local ok, cf, sz = pcall(map.GetBoundingBox, map)
    		if ok and cf and sz then
    			local pos = cf.Position + Vector3.new(0, sz.Y / 2 + RCH, 0)
    			if pos.Y > y + FDM then
    				return CFrame.new(pos)
    			end
    		end
    	end
    	if r and r.Parent then
    		return CFrame.new(r.Position.X, y + FDM + RCH, r.Position.Z)
    	end
    	return CFrame.new(0, y + FDM + RCH, 0)
    end
    
    ctx.inState = function(nm)
    	if LP then
    		local ok, a = pcall(function()
    			return LP:GetAttribute(nm == "InLift" and "IsInLift" or "IsPlaying")
    		end)
    		if ok and a ~= nil then
    			if nm == "InGame" then
    				local survived = false
    				pcall(function()
    					survived = LP:GetAttribute("SurvivedRound") == true
    				end)
    				return a == true and not survived
    			end
    			return a == true
    		end
    	end
    
    	local r = select(1, ctx.rh(false))
    	if not r then
    		return false
    	end
    	if nm == "InLift" then
    		return r.Position.X < 50 and r.Position.Z > 70
    	elseif nm == "InGame" then
    		return r.Position.X > 50
    	end
    	return false
    end
    
    ctx.activeRun = function(map, id)
    	return ctx.alive() and on and cur == map and map and map.Parent and tok == id
    end
    
    ctx.updateRoundStats = function(stats)
    	if type(stats) ~= "table" then
    		return
    	end
    
    	local curVal = stats.currentButton
    	local newButtonMode = false
    	if curVal == nil then
    		curVal = stats.CurrentButton
    		newButtonMode = curVal ~= nil
    	end
    	if type(curVal) == "number" then
    		if newButtonMode then
    			roundLeft = curVal
    			if curVal <= 0 then
    				roundCur = 1
    				if type(roundTotal) ~= "number" then
    					roundTotal = 1
    				end
    			else
    				roundCur = curVal
    			end
    		else
    			roundCur = curVal
    		end
    	end
    
    	local totalVal = stats.totalButtons or stats.TotalButtons or stats.TotalButton or stats.ButtonsTotal
    	if type(totalVal) == "number" then
    		roundTotal = totalVal
    	end
    
    	local stateVal = stats.gameStatus or stats.GameStatus or stats.GameState or stats.State
    	if type(stateVal) == "string" then
    		local st = stateVal:lower()
    		roundState = st
    		if st == "ingame" then
    			survivedSeen = false
    		elseif st == "survived" then
    			ctx.markSurvived("round")
    		end
    	end
    end
    
    ctx.buttonsDone = function()
    	if roundState and roundState ~= "ingame" then
    		return false
    	end
    	if type(roundLeft) == "number" then
    		return roundLeft <= 0
    	end
    	if type(roundCur) == "number" and type(roundTotal) == "number" then
    		return roundCur >= roundTotal
    	end
    	return false
    end
    
    ctx.isRoundIngame = function()
    	local physical = ctx.inState("InGame")
    	if type(roundState) == "string" then
    		return roundState:lower() == "ingame" or physical
    	end
    	return physical
    end
    
    ctx.isRand = function(s)
    	if type(s) ~= "string" or #s == 0 then
    		return false
    	end
    	for i = 1, #s do
    		local c = s:sub(i, i)
    		if c:lower() == c then
    			return false
    		end
    	end
    	return true
    end
    
    ctx.mkPlat = function(r)
    	local c = ctx.chr(false)
    	if not c or not r or not r.Parent then
    		return
    	end
    	local ok, cf, sz = pcall(c.GetBoundingBox, c)
    	if not ok or not cf or not sz then
    		return
    	end
    	local y = cf.Position.Y - sz.Y / 2
    	if not (plt and plt.Parent) then
    		local p = Instance.new("Part")
    		p.Name = "AF_SafePlatform"
    		p.Size = PSZ
    		p.Anchored = true
    		p.CanCollide = true
    		p.Transparency = 1
    		p:PivotTo(CFrame.new(r.Position.X, y - PSZ.Y / 2 - 0.05, r.Position.Z))
    		p.Parent = Wsp
    		plt = p
    	else
    		plt:PivotTo(CFrame.new(r.Position.X, y - PSZ.Y / 2 - 0.05, r.Position.Z))
    	end
    end
    
    ctx.anyPart = function(obj)
    	if not obj then
    		return nil
    	end
    	if obj:IsA("BasePart") then
    		return obj
    	end
    	if obj:IsA("Model") then
    		if obj.PrimaryPart then
    			return obj.PrimaryPart
    		end
    		for _, d in ctx.descOf(obj) do
    			if d:IsA("BasePart") then
    				return d
    			end
    		end
    	end
    	return nil
    end
    
    ctx.moveTo = function(obj, r)
    	if not obj or not r or not r.Parent then
    		return false
    	end
    	local p = ctx.anyPart(obj)
    	if not p then
    		return false
    	end
    	local moved = false
    	if __exec.firetouchinterest ~= nil and p:IsA("BasePart") then
    		pcall(function()
    			__exec.firetouchinterest(r, p, 0)
    			task.wait()
    			__exec.firetouchinterest(r, p, 1)
    		end)
    	end
    	if obj:IsA("Model") then
    		moved = pcall(function()
    			obj:PivotTo(r.CFrame)
    		end)
    	else
    		moved = pcall(function()
    			p:PivotTo(r.CFrame)
    		end)
    	end
    	if p.Parent and r.Parent then
    		moved = pcall(function()
    			r.CFrame = p.CFrame + Vector3.new(0, 1.5, 0)
    			r.AssemblyLinearVelocity = Vector3.zero
    		end) or moved
    	end
    	return moved
    end
    
    ctx.bKind = function(obj)
    	if not obj then
    		return nil
    	end
    	local nm = obj.Name
    	if type(nm) ~= "string" then
    		return nil
    	end
    	nm = nm:lower()
    	if nm == "_lostpage" or nm == "lostpage" or string.find(nm, "lostpage", 1, true) or string.find(nm, "lost_page", 1, true) then
    		return "pg"
    	end
    	if nm == "contact" or nm == "escapeecontact" or (string.find(nm, "escapee", 1, true) and string.find(nm, "contact", 1, true)) then
    		return "ct"
    	end
    	if nm == "npc" or (string.find(nm, "escapee", 1, true) and (obj:IsA("Model") or obj:IsA("BasePart"))) then
    		return "npc"
    	end
    	return nil
    end
    
    ctx.addBonus = function(obj)
    	if not bCache or not obj then
    		return
    	end
    	local k = ctx.bKind(obj)
    	if k == "pg" then
    		if not (bCache.pg and bCache.pg.Parent) then
    			bCache.pg = obj
    		end
    	elseif k == "ct" then
    		if not (bCache.ct and bCache.ct.Parent) then
    			bCache.ct = obj
    		end
    	elseif k == "npc" then
    		if not (bCache.npc and bCache.npc.Parent) then
    			bCache.npc = obj
    		end
    		if not (bCache.ct and bCache.ct.Parent) and obj.Parent then
    			local ok, ct = pcall(function()
    				return obj.Parent:FindFirstChild("Contact")
    			end)
    			if ok and ct then
    				bCache.ct = ct
    			end
    		end
    	end
    end
    
    ctx.scanBonuses = function(map)
    	if not bCache then
    		bCache = {}
    	end
    	bCache.pg = nil
    	bCache.ct = nil
    	bCache.npc = nil
    	for _, obj in ctx.descOf(map) do
    		ctx.addBonus(obj)
    		if bCache.pg and bCache.ct then
    			break
    		end
    	end
    	if not bCache.ct and bCache.npc and bCache.npc.Parent then
    		local ok, ct = pcall(function()
    			return bCache.npc.Parent:FindFirstChild("Contact")
    		end)
    		if ok and ct then
    			bCache.ct = ct
    		end
    	end
    	bDirty = false
    end
    
    ctx.getBonuses = function(map)
    	if not (map and map.Parent) then
    		ctx.clearBonuses()
    		return nil
    	end
    	if map ~= bMap then
    		ctx.clearBonuses()
    		bMap = map
    		bCache = {}
    		bDirty = true
    		bCons[#bCons + 1] = map.DescendantAdded:Connect(function(obj)
    			if not bCache then
    				return
    			end
    			local k = ctx.bKind(obj)
    			if k then
    				ctx.addBonus(obj)
    			end
    		end)
    		bCons[#bCons + 1] = map.DescendantRemoving:Connect(function(obj)
    			if bCache and (obj == bCache.pg or obj == bCache.ct or obj == bCache.npc) then
    				if obj == bCache.pg then
    					bCache.pg = nil
    				end
    				if obj == bCache.ct then
    					bCache.ct = nil
    				end
    				if obj == bCache.npc then
    					bCache.npc = nil
    				end
    				bDirty = true
    			end
    		end)
    	end
    	local now = os.clock()
    	if bDirty and now >= bScanAt then
    		bScanAt = now + 0.3
    		ctx.scanBonuses(map)
    	end
    	return bCache
    end
    
    ctx.takeBonus = function(obj, r, notify, msg)
    	if not (obj and obj.Parent) then
    		return false
    	end
    	local now = os.clock()
    	if bonusSeen[obj] and now - bonusSeen[obj] <= 2 then
    		return false
    	end
    	bonusSeen[obj] = now
    	local ok = ctx.moveTo(obj, r)
    	if ok then
    		if notify then
    			ctx.note(msg)
    		end
    		task.wait(TPD)
    	end
    	return ok
    end
    
    ctx.collectMapBonuses = function(map, r, notify)
    	if not (map and map.Parent) then
    		return false
    	end
    	if not (r and r.Parent) then
    		r = select(1, ctx.rh(false))
    	end
    	if not (r and r.Parent) then
    		return false
    	end
    	local bc = ctx.getBonuses(map)
    	if not bc then
    		return false
    	end
    	local moved = false
    	if bc.pg and not bc.pg.Parent then
    		bc.pg = nil
    		bDirty = true
    	end
    	if bc.ct and not bc.ct.Parent then
    		bc.ct = nil
    		bDirty = true
    	end
    	if not bc.ct and bc.npc and bc.npc.Parent then
    		local ok, ct = pcall(function()
    			return bc.npc.Parent:FindFirstChild("Contact")
    		end)
    		if ok and ct then
    			bc.ct = ct
    		end
    	end
    	moved = ctx.takeBonus(bc.pg, r, nil, "Got Lost Page.") or moved
    	moved = ctx.takeBonus(bc.ct, r, nil, "Got Escapee.") or moved
    	return moved
    end
    
    ctx.addBtnEntry = function(t, src, hit, loc, retro)
    	if not hit or not hit:IsA("BasePart") then
    		return
    	end
    	t[#t + 1] = {
    		src = src or hit,
    		hit = hit,
    		loc = loc and true or false,
    		retro = retro and true or false,
    	}
    end
    
    ctx.scanBtns = function(map)
    	local t = {}
    	for _, obj in ctx.descOf(map) do
    		if obj.ClassName == "Model" then
    			if ctx.isRetroGame() and tostring(obj.Name):match("^_Button%d+$") then
    				local hit = obj:FindFirstChild("Hitbox", true)
    				if hit and hit:IsA("BasePart") then
    					ctx.addBtnEntry(t, obj, hit, false, true)
    				end
    				continue
    			end
    			local hit = nil
    			local hasUi = obj:FindFirstChildWhichIsA("BillboardGui", true) ~= nil
    			local hasFuse = ctx.ffc(obj, "Fuse", true) ~= nil
    			for _, ch in obj:GetChildren() do
    				if ch:IsA("BasePart") and tostring(ch.BrickColor) ~= "Medium stone grey" then
    					hit = ch
    					break
    				end
    			end
    			local hasTouch = hit and ctx.ffc(hit, "TouchInterest", true) ~= nil
    			if hit and ctx.buttonHitAllowed(hit, map) and (ctx.isRand(obj.Name) or hasUi or hasFuse or hasTouch) then
    				if ctx.isRand(hit.Name) then
    					hit.Name = "Hitbox"
    				end
    				ctx.addBtnEntry(t, obj, hit, false)
    			end
    		end
    	end
    	if ctx.isRetroGame() then
    		table.sort(t, function(a, b)
    			local aSrc = a and (a.src or a.hit)
    			local bSrc = b and (b.src or b.hit)
    			local aNum = tonumber(tostring(aSrc and aSrc.Name or ""):match("%d+"))
    			local bNum = tonumber(tostring(bSrc and bSrc.Name or ""):match("%d+"))
    			if aNum and bNum then
    				return aNum < bNum
    			end
    			if aNum then
    				return true
    			end
    			if bNum then
    				return false
    			end
    			return false
    		end)
    	end
    	return t
    end
    
    ctx.valOf = function(obj, names)
    	if not obj then
    		return nil
    	end
    	for _, n in names do
    		local ok, v = pcall(function()
    			return obj:GetAttribute(n)
    		end)
    		if ok and v ~= nil then
    			return v
    		end
    	end
    	for _, d in ctx.descOf(obj) do
    		if d:IsA("ValueBase") then
    			local nm = d.Name:lower():gsub("[^%w]", "")
    			for _, n in names do
    				if nm == n:lower():gsub("[^%w]", "") then
    					return d.Value
    				end
    			end
    		end
    	end
    	return nil
    end
    
    ctx.numOf = function(obj)
    	local v = ctx.valOf(obj, { "ButtonID", "ButtonId", "ButtonIndex", "ButtonNumber", "ButtonNum", "Number", "ID", "Index", "Order" })
    	v = tonumber(v)
    	if v then
    		return v
    	end
    	local nm = obj and tostring(obj.Name) or ""
    	local a = nm:match("%d+")
    	return tonumber(a)
    end
    
    ctx.guiOn = function(obj)
    	if not obj then
    		return false
    	end
    	for _, d in ctx.descOf(obj) do
    		if d:IsA("BillboardGui") and d.Enabled then
    			return true
    		end
    	end
    	return false
    end
    
    ctx.truthyValue = function(v)
    	if v == nil then
    		return nil
    	end
    	if type(v) == "boolean" then
    		return v
    	end
    	if type(v) == "number" then
    		return v ~= 0
    	end
    	local s = tostring(v):lower()
    	if s == "true" or s == "yes" or s == "on" or s == "enabled" or s == "active" or s == "pressed" or s == "done" or s == "complete" or s == "completed" then
    		return true
    	end
    	if s == "false" or s == "no" or s == "off" or s == "disabled" or s == "inactive" or s == "unpressed" or s == "pending" then
    		return false
    	end
    	return nil
    end
    
    ctx.buttonHitAllowed = function(hit, map)
    	if not (hit and hit.Parent and hit:IsA("BasePart")) then
    		return false
    	end
    	if map and not hit:IsDescendantOf(map) then
    		return false
    	end
    	local src = hit.Parent or hit
    	if tostring(hit.Name) == "AirTank" or tostring(src.Name) == "AirTank" then
    		return false
    	end
    	if tostring(hit.Name) == "Hitbox" and hit.Parent and tostring(hit.Parent.Name) == "AirTank" then
    		return false
    	end
    	local hasUi = false
    	pcall(function()
    		hasUi = (src and src:FindFirstChildWhichIsA("BillboardGui", true) ~= nil) or hit:FindFirstChildWhichIsA("BillboardGui", true) ~= nil
    	end)
    	local hasFuse = ctx.ffc(src, "Fuse", true) ~= nil or ctx.ffc(hit, "Fuse", true) ~= nil
    	local hasTouch = ctx.ffc(hit, "TouchInterest", true) ~= nil or ctx.ffc(src, "TouchInterest", true) ~= nil
    	return ctx.isRand(tostring(src.Name)) or ctx.isRand(tostring(hit.Name)) or hasUi or hasFuse or hasTouch
    end
    
    ctx.entryKnownPressed = function(entry)
    	local src = entry and entry.src
    	local hit = entry and entry.hit
    	local v = ctx.valOf(src, { "Pressed", "IsPressed", "Completed", "Complete", "Done", "Finished", "Activated", "Triggered" })
    	if v == nil then
    		v = ctx.valOf(hit, { "Pressed", "IsPressed", "Completed", "Complete", "Done", "Finished", "Activated", "Triggered" })
    	end
    	local b = ctx.truthyValue(v)
    	return b == true
    end
    
    ctx.entryReady = function(entry, map, sent)
    	local hit = entry and entry.hit
    	local src = entry and entry.src
    	if not (hit and hit.Parent and hit:IsA("BasePart")) then
    		return false
    	end
    	if map and not hit:IsDescendantOf(map) then
    		return false
    	end
    	if entry.loc then
    		return locBtns[hit] == entry
    	end
    	if sent and sent[hit] then
    		return false
    	end
    	if not ctx.buttonHitAllowed(hit, map) then
    		return false
    	end
    	if ctx.entryKnownPressed(entry) then
    		return false
    	end
    	if type(ctx.fuseUnsafe) == "function" and ctx.fuseUnsafe(src, hit, map) then
    		return false
    	end
    	if entry.retro then
    		return true
    	end
    	local av = ctx.valOf(src, { "Active", "IsActive", "Enabled", "Pressable", "CanPress", "Current", "Selected" })
    	if av ~= nil then
    		return ctx.truthyValue(av) == true
    	end
    	if type(roundCur) == "number" then
    		local n = ctx.numOf(src) or ctx.numOf(hit)
    		if n then
    			return n == roundCur or n == roundCur + 1
    		end
    	end
    	if ctx.isFuseBtn(src) then
    		return ctx.ffc(hit, "TouchInterest", true) ~= nil
    	end
    	return ctx.guiOn(src) or ctx.guiOn(hit) or ctx.ffc(hit, "TouchInterest", true) ~= nil
    end
    
    ctx.hasReadyEntry = function(entries, map, sent)
    	entries = type(entries) == "table" and entries or {}
    	for _, entry in entries do
    		if ctx.entryReady(entry, map, sent) then
    			return true
    		end
    	end
    	return false
    end
    
    ctx.allButtonsHandled = function(entries, map, sent)
    	entries = type(entries) == "table" and entries or {}
    	local sawButton = false
    	for _, entry in entries do
    		local hit = entry and entry.hit
    		local src = entry and entry.src
    		if hit and hit.Parent and (not map or hit:IsDescendantOf(map)) and not entry.loc then
    			sawButton = true
    			local handled = (sent and sent[hit]) or ctx.entryKnownPressed(entry) or (type(ctx.fuseUnsafe) == "function" and ctx.fuseUnsafe(src, hit, map))
    			if not handled then
    				return false
    			end
    		end
    	end
    	return sawButton
    end
    
    ctx.auraReady = function(entry)
    	local hit = entry and entry.hit
    	local src = entry and entry.src
    	if not (hit and hit.Parent) then
    		return false
    	end
    	if ctx.entryKnownPressed(entry) then
    		return false
    	end
    	if type(ctx.fuseUnsafe) == "function" and ctx.fuseUnsafe(src, hit) then
    		return false
    	end
    	if entry.retro then
    		return true
    	end
    	if entry.loc then
    		return true
    	end
    	local av = ctx.valOf(src, { "Active", "IsActive", "Enabled", "Pressable", "CanPress", "Current", "Selected" })
    	if av ~= nil then
    		return av == true or av == 1 or tostring(av):lower() == "true"
    	end
    	if type(roundCur) == "number" then
    		local n = ctx.numOf(src) or ctx.numOf(hit)
    		if n then
    			return n == roundCur or n == roundCur + 1
    		end
    	end
    	if ctx.isFuseBtn(src) then
    		return ctx.ffc(hit, "TouchInterest", true) ~= nil
    	end
    	if ctx.guiOn(src) or ctx.guiOn(hit) then
    		return true
    	end
    	return ctx.ffc(hit, "TouchInterest", true) ~= nil
    end
    
    ctx.auraEntries = function(map)
    	local t = ctx.locatorEntries(map)
    	if #t > 0 then
    		return t, true
    	end
    	local now = os.clock()
    	if auraMap ~= map or now - auraAt > 0.6 then
    		auraMap = map
    		auraAt = now
    		auraList = {}
    		local ok, res = pcall(ctx.scanBtns, map)
    		if ok and type(res) == "table" then
    			for _, entry in res do
    				if ctx.auraReady(entry) then
    					auraList[#auraList + 1] = entry
    				end
    			end
    		end
    	end
    	for i = #auraList, 1, -1 do
    		local entry = auraList[i]
    		local hit = entry and entry.hit
    		if not (hit and hit.Parent and hit:IsDescendantOf(map) and ctx.auraReady(entry)) then
    			table.remove(auraList, i)
    		end
    	end
    	return auraList, false
    end
    
    ctx.asPart = function(v)
    	if typeof(v) == "Instance" and v:IsA("BasePart") then
    		return v
    	end
    	if type(v) ~= "table" then
    		return nil
    	end
    	local r = select(1, ctx.rh(false))
    	local best = nil
    	local bestDist = math.huge
    	for _, obj in v do
    		if typeof(obj) == "Instance" and obj:IsA("BasePart") then
    			local dist = r and (r.Position - obj.Position).Magnitude or 0
    			if dist < bestDist then
    				best = obj
    				bestDist = dist
    			end
    		end
    	end
    	return best
    end
    
    ctx.addLocatorBtn = function(hit, nextHit)
    	ctx.clearLocators()
    	hit = ctx.asPart(hit)
    	nextHit = ctx.asPart(nextHit)
    	if not hit then
    		return
    	end
    	local src = hit.Parent or hit
    	locBtns[hit] = {
    		src = src,
    		hit = hit,
    		loc = true,
    		next = nextHit,
    		seq = locSeq,
    	}
    end
    
    ctx.locatorEntries = function(map)
    	local t = {}
    	for hit, entry in locBtns do
    		if hit and hit.Parent and (not map or hit:IsDescendantOf(map)) then
    			t[#t + 1] = entry
    		else
    			locBtns[hit] = nil
    		end
    	end
    	return t
    end
    
    ctx.nearestEntry = function(entries, pos)
    	local best = nil
    	local bestDist = math.huge
    	if not pos then
    		return nil
    	end
    	for _, entry in entries do
    		local hit = entry and entry.hit
    		if hit and hit.Parent then
    			local dist = (pos - hit.Position).Magnitude
    			if dist < bestDist then
    				best = entry
    				bestDist = dist
    			end
    		end
    	end
    	return best
    end
    
    ctx.pressAuraEntries = function(entries, map, allowNearestFallback)
    	local hb = type(ctx.rootPart) == "function" and ctx.rootPart() or nil
    	local maxDist = math.max(0, tonumber(auraDist) or 7)
    	local pressed = false
    	local used = 0
    	if not hb and auraUseDistance then
    		return false
    	end
    
    	if not auraUseDistance and allowNearestFallback then
    		if not (hb and hb.Parent) then
    			return false
    		end
    		local entry = ctx.nearestEntry(entries, hb and hb.Position or nil)
    		local hit = entry and entry.hit
    		if hit and hit.Parent and (not map or hit:IsDescendantOf(map)) then
    			return ctx.pressMapButton(hit) == true
    		end
    		return false
    	end
    
    	for i = #entries, 1, -1 do
    		local entry = entries[i]
    		local hit = entry and entry.hit
    		if not (hit and hit.Parent and (not map or hit:IsDescendantOf(map))) then
    			table.remove(entries, i)
    		elseif used < pressBudget and (not auraUseDistance or (hb and hb.Parent and (hb.Position - hit.Position).Magnitude <= maxDist)) then
    			used += 1
    			if type(ctx.pressMapButton) == "function" and ctx.pressMapButton(hit) then
    				pressed = true
    			end
    		end
    	end
    	return pressed
    end
    
    ctx.mergeLocatorBtns = function(t, map)
    	local seen = {}
    	for _, entry in t do
    		if entry.hit and (not entry.loc or locBtns[entry.hit] == entry) then
    			seen[entry.hit] = true
    		end
    	end
    	for hit, entry in locBtns do
    		if not (hit and hit.Parent) then
    			locBtns[hit] = nil
    		elseif not seen[hit] and (not map or hit:IsDescendantOf(map)) then
    			t[#t + 1] = entry
    			seen[hit] = true
    		end
    	end
    	return t
    end
    
    ctx.isFuseBtn = function(src)
    	local f = ctx.ffc(src, "Fuse", true)
    	if not f and src and src.Parent then
    		f = ctx.ffc(src.Parent, "Fuse", true)
    	end
    	return f and f:IsA("ValueBase")
    end
    
    ctx.fuseValueTarget = function(src, hit)
    	local f = ctx.ffc(src, "Fuse", true)
    	if not f and hit and hit.Parent then
    		f = ctx.ffc(hit.Parent, "Fuse", true)
    	end
    	if not (f and f:IsA("ValueBase")) then
    		return nil
    	end
    	local ok, v = pcall(function()
    		return f.Value
    	end)
    	if ok and typeof(v) == "Instance" then
    		return v
    	end
    	return nil
    end
    
    ctx.isFuseBlastPart = function(obj)
    	local ok, isPart = pcall(function()
    		return obj and obj:IsA("Part")
    	end)
    	if not (ok and isPart) then
    		return false
    	end
    	local okProps, shape, size, color, material, brickColor = pcall(function()
    		return obj.Shape, obj.Size, obj.Color, obj.Material, obj.BrickColor
    	end)
    	if not okProps or shape ~= Enum.PartType.Ball then
    		return false
    	end
    	local sz = math.max(size.X, size.Y, size.Z)
    	if sz < 10 then
    		return false
    	end
    	local red = color.R > 0.75 and color.G < 0.2 and color.B < 0.2
    	local neon = material == Enum.Material.Neon
    	local reallyRed = tostring(brickColor) == "Really red"
    	return red and (neon or reallyRed or sz >= 18)
    end
    
    ctx.nearFuseBlast = function(src, hit, map)
    	if not (hit and hit.Parent) then
    		return false, nil
    	end
    	local target = ctx.fuseValueTarget(src, hit)
    	if target and ctx.isFuseBlastPart(target) then
    		return true, target
    	end
    	local root = src
    	if hit and hit.Parent and (not root or root == hit) then
    		root = hit.Parent
    	end
    	local parts = {}
    	if root then
    		for _, obj in ctx.descOf(root) do
    			if obj ~= hit and ctx.isFuseBlastPart(obj) then
    				parts[#parts + 1] = obj
    			end
    		end
    	end
    	local best = nil
    	local bestDist = math.huge
    	for _, part in parts do
    		if part then
    			local okPart, size, pos = pcall(function()
    				return part.Size, part.Position
    			end)
    			if okPart and size and pos then
    				local radius = math.max(size.X, size.Y, size.Z) * 0.5
    				local dist = (hit.Position - pos).Magnitude
    				if dist <= math.max(80, radius + 35) and dist < bestDist then
    					best = part
    					bestDist = dist
    				end
    			end
    		end
    	end
    	return best ~= nil, best
    end
    
    ctx.fuseBlastSizePosition = function(part)
    	local ok, size, pos = pcall(function()
    		return part and part.Size, part and part.Position
    	end)
    	if ok and size and pos then
    		return size, pos
    	end
    	return nil, nil
    end
    
    ctx.markFusePressed = function(src, hit)
    	local untilTime = os.clock() + 2.5
    	if src then
    		fusePressed[src] = untilTime
    	end
    	if hit then
    		fusePressed[hit] = untilTime
    	end
    	if hit and hit.Parent then
    		fusePressed[hit.Parent] = untilTime
    	end
    	ctx.cache.fuseBlastAt = 0
    end
    
    ctx.fusePressedRecently = function(src, hit)
    	local now = os.clock()
    	for _, obj in { src, hit, hit and hit.Parent } do
    		local t = obj and fusePressed[obj]
    		if type(t) == "number" then
    			if now < t then
    				return true
    			end
    			fusePressed[obj] = nil
    		end
    	end
    	return false
    end
    
    ctx.fuseUnsafe = function(src, hit, map)
    	if not ctx.isFuseBtn(src or hit) then
    		return false
    	end
    	if ctx.fusePressedRecently(src, hit) then
    		return true
    	end
    	local near = ctx.nearFuseBlast(src, hit, map)
    	return near == true
    end
    
    ctx.fuseRange = function(src, hit)
    	local best = nil
    	local bestSize = 0
    	local root = src
    	if hit and hit.Parent and (not root or root == hit) then
    		root = hit.Parent
    	end
    	for _, obj in ctx.descOf(root) do
    		if obj ~= hit and ctx.isFuseBlastPart(obj) then
    			local sz = math.max(obj.Size.X, obj.Size.Y, obj.Size.Z)
    			if sz > bestSize then
    				best = obj
    				bestSize = sz
    			end
    		end
    	end
    	if not best then
    		local _, blast = ctx.nearFuseBlast(src, hit)
    		best = blast
    	end
    	return best
    end
    
    ctx.fuseSafePosition = function(src, hit, r)
    	local sp = ctx.fuseRange(src, hit)
    	local spSize, spPos = ctx.fuseBlastSizePosition(sp)
    	if not (spSize and spPos) then
    		if not hit then
    			return nil
    		end
    		local away = Vector3.new(hit.CFrame.LookVector.X, 0, hit.CFrame.LookVector.Z)
    		if away.Magnitude < 0.05 then
    			away = Vector3.new(1, 0, 0)
    		end
    		return hit.Position + away.Unit * 35 + Vector3.new(0, ESY, 0)
    	end
    	local origin = spPos
    	local from = (r and r.Parent and r.Position) or (hit and hit.Position) or (origin + Vector3.new(1, 0, 0))
    	local away = Vector3.new(from.X - origin.X, 0, from.Z - origin.Z)
    	if away.Magnitude < 0.05 and hit then
    		away = Vector3.new(hit.Position.X - origin.X, 0, hit.Position.Z - origin.Z)
    	end
    	if away.Magnitude < 0.05 then
    		away = Vector3.new(1, 0, 0)
    	end
    	local radius = math.max(spSize.X, spSize.Y, spSize.Z) * 0.5
    	return origin + away.Unit * (radius + 12) + Vector3.new(0, ESY, 0)
    end
    
    ctx.waitFuseRange = function(src, hit, keepGoing)
    	if keepGoing and not keepGoing() then
    		return nil
    	end
    	return ctx.fuseRange(src, hit)
    end
    
    ctx.moveFuseSafe = function(src, hit, r, keepGoing)
    	if keepGoing and not keepGoing() then
    		return
    	end
    	if not hit or not hit.Parent then
    		return
    	end
    	if not r or not r.Parent then
    		r = select(1, ctx.rh(false))
    	end
    	if not r or not r.Parent then
    		return
    	end
    	local pos = ctx.fuseSafePosition(src, hit, r)
    	if not pos then
    		return
    	end
    	pcall(function()
    		ctx.pivotRootTo(CFrame.new(pos), r)
    		r.AssemblyLinearVelocity = Vector3.zero
    		r.AssemblyAngularVelocity = Vector3.zero
    		r.Anchored = true
    	end)
    end
    
    ctx.pressMapButton = function(hit)
    	if not hit or not hit.Parent then
    		return false
    	end
    	local now = os.clock()
    	local last = pressTimes[hit]
    	if last and now - last < PCD then
    		return false
    	end
    	if now - pressWin >= pressGap then
    		pressWin = now
    		pressCnt = 0
    	end
    	if pressCnt >= pressMax then
    		return false
    	end
    	pressCnt += 1
    	pressTimes[hit] = now
    	if ctx.isRetroGame() and __exec.firetouchinterest ~= nil then
    		local r = type(ctx.rootPart) == "function" and ctx.rootPart() or nil
    		if r and r.Parent then
    			pcall(__exec.firetouchinterest, r, hit, 0)
    			pcall(__exec.firetouchinterest, hit, r, 0)
    			task.wait(0.03)
    			pcall(__exec.firetouchinterest, r, hit, 1)
    			pcall(__exec.firetouchinterest, hit, r, 1)
    		end
    	end
    	local fired = false
    	for _, rem in PressRemotes do
    		if rem and rem.Parent then
    			local ok = pcall(function()
    				rem:FireServer(hit)
    			end)
    			fired = fired or ok
    		end
    	end
    	if fired and type(ctx.markFusePressed) == "function" and ctx.isFuseBtn(hit.Parent or hit) then
    		ctx.markFusePressed(hit.Parent or hit, hit)
    	end
    	return fired
    end
    
    ctx.startPressLoop = function(hit, runId, keepGoing)
    	if not hit or not hit.Parent then
    		return
    	end
    	ctx.spawnLoop(function()
    		local tries = 0
    		local t0 = os.clock()
    		while ctx.alive() and on and tok == runId and hit and hit.Parent and tries < 80 and os.clock() - t0 < 8 do
    			if type(keepGoing) == "function" and not keepGoing() then
    				break
    			end
    			if ctx.pressMapButton(hit) then
    				tries += 1
    			end
    			task.wait(math.max(BSI, PCD))
    		end
    	end)
    end
    
    ctx.startAutoFarmButtonSpam = function(map, runId, entries)
    	if not map or not map.Parent then
    		return
    	end
    	local spamKey = tostring(runId) .. ":" .. tostring(map)
    	if ctx.cache.buttonSpamKey == spamKey then
    		return
    	end
    	ctx.cache.buttonSpamKey = spamKey
    	entries = type(entries) == "table" and entries or {}
    	ctx.spawnLoop(function()
    		local idx = 1
    		while ctx.activeRun(map, runId) and ctx.inState("InGame") do
    			ctx.mergeLocatorBtns(entries, map)
    			if not ctx.buttonsDone() then
    				local total = #entries
    				local tried = 0
    				local done = 0
    				while total > 0 and tried < total and done < pressBudget do
    					if idx > #entries then
    						idx = 1
    					end
    					local entry = entries[idx]
    					local hit = entry and entry.hit
    					if hit and hit.Parent and hit:IsDescendantOf(map) then
    						if ctx.entryReady(entry, map) then
    							ctx.pressMapButton(hit)
    							done += 1
    						end
    						idx += 1
    					else
    						table.remove(entries, idx)
    						if idx > #entries then
    							idx = 1
    						end
    					end
    					tried += 1
    				end
    			end
    			task.wait(BSI)
    		end
    		if ctx.cache.buttonSpamKey == spamKey then
    			ctx.cache.buttonSpamKey = nil
    		end
    	end)
    end
    
    ctx.retroButtonsDone = function(entries, sent)
    	entries = type(entries) == "table" and entries or {}
    	sent = type(sent) == "table" and sent or {}
    	local hasRetro = false
    	for _, entry in entries do
    		if entry and entry.retro then
    			local hit = entry.hit
    			if hit and hit.Parent then
    				hasRetro = true
    				if not sent[hit] then
    					return false
    				end
    			end
    		end
    	end
    	return hasRetro
    end
    
    ctx.getPassArg = function(force)
    	if force then
    		passKey = nil
    	end
    	if passKey ~= nil then
    		return type(passKey) == "number" and -passKey or passKey
    	end
    	if not (PasskeyRemote and PasskeyRemote.Parent) then
    		return nil
    	end
    	local ok, res = pcall(function()
    		return PasskeyRemote:InvokeServer()
    	end)
    	if not ok or res == nil then
    		return nil
    	end
    	passKey = res
    	return type(res) == "number" and -res or res
    end
    
    
    ctx.dataSig = function(data)
    	local st = data and data.stats
    	if type(st) ~= "table" then
    		return nil
    	end
    	local parts = {}
    	for k, v in st do
    		if type(v) ~= "table" and typeof(v) ~= "Instance" then
    			parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
    		end
    	end
    	table.sort(parts)
    	return table.concat(parts, "|")
    end
    
    ctx.cacheData = function(data)
    	if type(data) == "table" and type(data.stats) == "table" then
    		local sig = ctx.dataSig(data)
    		pdata = data
    		if data.dailyChallenges ~= nil and type(ctx.updateChallengePlan) == "function" then
    			ctx.updateChallengePlan(data)
    		end
    		if sig then
    			if sig ~= statsSig then
    				lastFreshData = os.clock()
    				if pendingSaveSig and sig ~= pendingSaveSig then
    					pendingSaveSig = nil
    				end
    			end
    			statsSig = sig
    		end
    		if type(ctx.paintStats) == "function" then
    			ctx.paintStats()
    		end
    	end
    end
    
    ctx.cacheLocalData = function()
    	if not LP then
    		return
    	end
    	local data = LP:FindFirstChild("Data")
    	if not data then
    		return
    	end
    	local function val(n)
    		local obj = data:FindFirstChild(n)
    		return obj and obj:IsA("ValueBase") and obj.Value or nil
    	end
    	ctx.cacheData({
    		stats = {
    			level = val("Level"),
    			xp = val("Experience"),
    			coins = val("Coins"),
    			gems = val("Amethysts"),
    			rebirth = val("Rebirths"),
    		},
    	})
    end
    
    ctx.needXp = function(lv, rb)
    	lv = tonumber(lv) or 0
    	rb = tonumber(rb) or 0
    	if FE2CalcLevelXP then
    		local ok, xp = pcall(FE2CalcLevelXP, lv, rb)
    		if ok and type(xp) == "number" then
    			return xp
    		end
    	end
    	if lv == 0 then
    		return 1
    	end
    	local base = math.clamp(200 + (lv - 1) * 200, 1, 12000)
    	return base + base * (math.clamp(rb, 0, 30) * 0.05)
    end
    
    ctx.paintStats = function()
    	local st = pdata and pdata.stats
    	if type(st) ~= "table" or not LP then
    		return
    	end
    	local pg = LP:FindFirstChild("PlayerGui")
    	local gg = pg and pg:FindFirstChild("GameGui")
    	local hud = gg and gg:FindFirstChild("HUD")
    	local main = hud and hud:FindFirstChild("Main")
    	local gs = main and main:FindFirstChild("GameStats")
    	local ui = gs and gs:FindFirstChild("Stats")
    	if not ui then
    		return
    	end
    	local lv = tonumber(st.level) or 0
    	local rb = tonumber(st.rebirth) or 0
    	local xp = tonumber(st.xp) or 0
    	local req = ctx.needXp(lv, rb)
    	if req <= 0 then
    		req = 1
    	end
    	local rdy = lv >= 100 and rb < 30 and xp >= req
    	local xs = ui:FindFirstChild("XPStats")
    	if xs then
    		local ic = ctx.ffc(xs, "Icon", false)
    		local inf = ic and ic:FindFirstChild("Info")
    		if inf then
    			inf.Text = tostring(lv)
    		end
    		local xt = xs:FindFirstChild("XP")
    		if xt then
    			xt.Text = tostring(xp) .. "/" .. tostring(req) .. " XP"
    		end
    		local pb = ctx.ffc(xs, "Percentage", true)
    		if pb then
    			pb.Size = UDim2.new(math.clamp(xp / req, 0, 1), 0, 1, 0)
    		end
    		local reb = xs:FindFirstChild("Rebirth")
    		if reb then
    			reb.Visible = rb > 0
    			local ri = reb:FindFirstChild("Info")
    			if ri then
    				ri.Text = "x" .. tostring(rb)
    			end
    		end
    		xs.Visible = not rdy
    	end
    	local rbui = ui:FindFirstChild("Rebirth")
    	if rbui then
    		rbui.Visible = rdy
    	end
    	local ms = ui:FindFirstChild("MapStats")
    	local mb = ms and ms:FindFirstChild("MapBar")
    	if mb then
    		local dm = tonumber(st.dailyMapsCompleted) or 0
    		for i = 1, 10 do
    			local m = mb:FindFirstChild("Map" .. i)
    			if m then
    				m.BackgroundTransparency = i <= dm and 0.2 or 0.7
    			end
    		end
    	end
    	local cur = ui:FindFirstChild("Currency")
    	if cur then
    		local ca = ctx.ffc(cur, "CoinAmt", true)
    		local ga = ctx.ffc(cur, "GemAmt", true)
    		local ct = ca and ctx.ffc(ca, "Amount", true)
    		local gx = ga and ctx.ffc(ga, "Amount", true)
    		if ct then
    			ct.Text = tostring(st.coins or 0)
    		end
    		if gx then
    			gx.Text = tostring(st.gems or 0)
    		end
    	end
    end
    
    ctx.canRebirth = function()
    	local st = pdata and pdata.stats
    	if type(st) ~= "table" then
    		return nil
    	end
    	local lv = tonumber(st.level) or 0
    	local rb = tonumber(st.rebirth) or 0
    	local xp = tonumber(st.xp) or 0
    	local req = ctx.needXp(lv, rb)
    	if rb >= 30 or lv < 100 then
    		return false
    	end
    	return req <= 0 or xp >= req
    end
    
    ctx.fireLoaded = function(key)
    	for _, rem in LoadedMapRemotes do
    		if rem and rem.Parent then
    			pcall(function()
    				if key ~= nil then
    					rem:FireServer(key)
    				else
    					rem:FireServer()
    				end
    			end)
    		end
    	end
    end
    
    ctx.fireSurvived = function(key, tm)
    	tm = tonumber(tm) or 100
    	ctx.tmpHasSurvived = false
    	for _, rem in SurvivedRemotes do
    		if rem and rem.Parent then
    			ctx.tmpHasSurvived = true
    			break
    		end
    	end
    	if not ctx.tmpHasSurvived and os.clock() >= (ctx.cache.surviveFindAt or 0) then
    		ctx.addRemoteOnce(SurvivedRemotes, ctx.findRemoteNamed("Survived"))
    		ctx.cache.surviveFindAt = os.clock() + 3
    	end
    	ctx.tmpSurvivedFired = false
    	for _, rem in SurvivedRemotes do
    		if rem and rem.Parent then
    			if key ~= nil then
    				ctx.tmpOk = pcall(function() rem:FireServer(key, tm) end)
    				ctx.tmpSurvivedFired = ctx.tmpSurvivedFired or ctx.tmpOk
    				ctx.tmpOk = pcall(function() rem:FireServer(key) end)
    				ctx.tmpSurvivedFired = ctx.tmpSurvivedFired or ctx.tmpOk
    			end
    			ctx.tmpOk = pcall(function() rem:FireServer(tm) end)
    			ctx.tmpSurvivedFired = ctx.tmpSurvivedFired or ctx.tmpOk
    			ctx.tmpOk = pcall(function() rem:FireServer() end)
    			ctx.tmpSurvivedFired = ctx.tmpSurvivedFired or ctx.tmpOk
    		end
    	end
    	return ctx.tmpSurvivedFired
    end
    
    ctx.requestRoundStats = function()
    	for _, rem in RoundStatsRemotes do
    		if rem and rem.Parent then
    			pcall(function()
    				rem:FireServer()
    			end)
    		end
    	end
    end
    
    ctx.requestPlayerData = function(force)
    	local now = os.clock()
    	if not force and now - lastData < DRI then
    		return
    	end
    	lastData = now
    	local key = ctx.getPassArg(false)
    	if ItemDataFunction and ItemDataFunction.Parent then
    		local ok, data, items = pcall(function()
    			if key ~= nil then
    				return ItemDataFunction:InvokeServer(key, LP, true)
    			end
    			return ItemDataFunction:InvokeServer(nil, LP, true)
    		end)
    		if ok then
    			ctx.cacheData(data)
    			if type(items) == "table" then
    				ctx.cache.shopItems = items
    			end
    		end
    	end
    	for _, rem in ItemDataRemotes do
    		if rem and rem.Parent then
    			pcall(function()
    				if key ~= nil then
    					rem:FireServer(key, true)
    				else
    					rem:FireServer(nil, true)
    				end
    			end)
    		end
    	end
    	for _, rem in PlayerDataRemotes do
    		if rem and rem.Parent then
    			pcall(function()
    				rem:FireServer()
    			end)
    		end
    	end
    	ctx.cacheLocalData()
    end
    
    ctx.tryRebirth = function(force)
    	if not (RebirthRemote and RebirthRemote.Parent) then
    		return
    	end
    	local now = os.clock()
    	local okRb = ctx.canRebirth()
    	if okRb ~= true then
    		return
    	end
    	local gap = RBI
    	if not force and now - lastRb < gap then
    		return
    	end
    	lastRb = now
    	local key = ctx.getPassArg(false)
    	pcall(function()
    		if key ~= nil then
    			RebirthRemote:FireServer(key)
    		else
    			RebirthRemote:FireServer()
    		end
    	end)
    end
    
    ctx.statPulse = function(force)
    	local now = os.clock()
    	if not force and now - lastStat < SRI then
    		return
    	end
    	lastStat = now
    	ctx.requestRoundStats()
    	ctx.requestPlayerData(true)
    	task.delay(0.5, function()
    		if ctx.alive() and on then
    			ctx.requestPlayerData(true)
    			ctx.tryRebirth(true)
    		end
    	end)
    end
    
    ctx.statBurst = function()
    	local now = os.clock()
    	if now - lastBurst < 0.5 then
    		return
    	end
    	lastBurst = now
    	for _, d in RFD do
    		task.delay(d, function()
    			if ctx.alive() and on then
    				ctx.requestRoundStats()
    				ctx.requestPlayerData(true)
    				ctx.tryRebirth(true)
    			end
    		end)
    	end
    end
    
    ctx.flushStatsAfterSurvival = function()
    	saveFlushTok += 1
    	local id = saveFlushTok
    	pendingSaveSig = statsSig or ""
    	local started = os.clock()
    	ctx.spawnLoop(function()
    		while ctx.alive() and on and saveFlushTok == id and os.clock() - started < SFT do
    			ctx.requestRoundStats()
    			ctx.requestPlayerData(true)
    			ctx.tryRebirth(true)
    			if pendingSaveSig == nil and lastFreshData >= started then
    				break
    			end
    			task.wait(SFI)
    		end
    		if ctx.alive() and on and saveFlushTok == id then
    			ctx.requestRoundStats()
    			ctx.requestPlayerData(true)
    			ctx.tryRebirth(true)
    		end
    	end)
    end
    
    ctx.markSurvived = function(src)
    	if survivedSeen then
    		return
    	end
    	local now = os.clock()
    	survivedSeen = true
    	survivedAt = now
    	roundState = "survived"
    	tok += 1
    	ctx.releaseRoot()
    	ctx.statPulse(true)
    	ctx.statBurst()
    	ctx.flushStatsAfterSurvival()
    	if src then
    		ctx.note("Survived; refreshing stats")
    	end
    end
    
    ctx.burstLoaded = function()
    	local key = ctx.getPassArg(false)
    	for _ = 1, LDB do
    		if not (ctx.alive() and on) then
    			return
    		end
    		ctx.fireLoaded(key)
    		ctx.requestRoundStats()
    		task.wait(LDI)
    	end
    end
    
    ctx.startFarmRemotes = function()
    	farmTok += 1
    	local id = farmTok
    	ctx.spawnLoop(function()
    		local ka = 0
    		local ra = 0
    		while ctx.alive() and on and farmTok == id do
    			local ok, err = xpcall(function()
    				local now = os.clock()
    				if now >= ka then
    					ctx.getPassArg(true)
    					ctx.requestPlayerData(false)
    					ctx.tryRebirth(false)
    					ka = now + 2
    				end
    				if now >= ra then
    					ctx.requestRoundStats()
    					ra = now + RSI
    				end
    			end, __traceback)
    			if not ok then
    				warn(err)
    			end
    			task.wait(FMI)
    		end
    	end)
    end
    
    ctx.startPassiveRemotes = function()
    	ctx.spawnLoop(function()
    		local ra = 0
    		local la = 0
    		local sa = 0
    		local ka = 0
    		local sk = nil
    		while ctx.alive() do
    			if ctx.isFEMGame() then
    				task.wait(0.5)
    				continue
    			end
    			local now = os.clock()
    			local playing = on or autoChallenges
    			local inRound = ctx.isRoundIngame()
    			local doSurvive = ctx.opt.surviveLoopOn and ctx.isFE2Game() and inRound and not survivedSeen
    			if doSurvive and now >= la then
    				if now >= ka then
    					sk = ctx.getPassArg(false)
    					ka = now + 3
    				end
    				ctx.fireLoaded(sk)
    				la = now + PLI
    			end
    			if doSurvive and now >= sa then
    				if now >= ka then
    					sk = ctx.getPassArg(false)
    					ka = now + 3
    				end
    				ctx.fireSurvived(sk, 100)
    				sa = now + PSI
    			end
    			if playing and now >= ra then
    				ctx.requestRoundStats()
    				ra = now + RSI
    			end
    			task.wait(PMW)
    		end
    	end)
    end
    
    for _, rem in LocatorRemotes do
    	if rem then
    		ctx.bind(rem.OnClientEvent:Connect(function(goal, hit, ui, nextHit)
    			ctx.addLocatorBtn(hit or goal, nextHit or ui)
    		end))
    	end
    end
    
    for _, rem in RoundStatsRemotes do
    	if rem then
    		ctx.bind(rem.OnClientEvent:Connect(ctx.updateRoundStats))
    		if rem.Parent then
    			pcall(function()
    				rem:FireServer()
    			end)
    		end
    	end
    end
    
    for _, rem in PlayerDataRemotes do
    	if rem and rem.Parent then
    		ctx.bind(rem.OnClientEvent:Connect(ctx.cacheData))
    	end
    end
    
    for _, rem in ItemDataRemotes do
    	if rem and rem.Parent then
    		ctx.bind(rem.OnClientEvent:Connect(function(data, items)
    			ctx.cacheData(data)
    			if type(items) == "table" then
    				ctx.cache.shopItems = items
    			end
    		end))
    	end
    end
    
    for _, rem in SurvivedRemotes do
    	if rem and rem.Parent then
    		ctx.bind(rem.OnClientEvent:Connect(function(ok)
    			if ok == true or tostring(ok):lower() == "survived" then
    				ctx.markSurvived("remote")
    			end
    		end))
    	end
    end
    
    for _, rem in GameStateRemotes do
    	if rem and rem.Parent then
    		ctx.bind(rem.OnClientEvent:Connect(function(st)
    			local state = tostring(st):lower()
    			if state ~= "" and state ~= "nil" then
    				roundState = state
    			end
    			if state == "ingame" then
    				survivedSeen = false
    			elseif state == "survived" then
    				ctx.markSurvived("state")
    			end
    		end))
    	end
    end
    
    ctx.cache.fe2RemoteBound = ctx.cache.fe2RemoteBound or setmetatable({}, { __mode = "k" })
    ctx.cache.fe2RemoteRoot = nil
    ctx.cache.fe2RemoteRootConn = nil
    
    ctx.resolveFE2Remote = function(name, className)
    	if type(name) ~= "string" or name == "" then
    		return nil
    	end
    	local root = Rsp and Rsp:FindFirstChild("Remote")
    	local found = root and (root:FindFirstChild(name) or root:FindFirstChild(name, true)) or nil
    	if found and (not className or found:IsA(className)) then
    		return found
    	end
    	return nil
    end
    
    ctx.bindLateFE2Remote = function(kind, rem)
    	if not (rem and rem:IsA("RemoteEvent")) or ctx.cache.fe2RemoteBound[rem] then
    		return
    	end
    	ctx.cache.fe2RemoteBound[rem] = true
    
    	if kind == "locator" then
    		ctx.bind(rem.OnClientEvent:Connect(function(goal, hit, ui, nextHit)
    			ctx.addLocatorBtn(hit or goal, nextHit or ui)
    		end))
    	elseif kind == "round" then
    		ctx.bind(rem.OnClientEvent:Connect(ctx.updateRoundStats))
    		pcall(function()
    			rem:FireServer()
    		end)
    	elseif kind == "playerData" then
    		ctx.bind(rem.OnClientEvent:Connect(ctx.cacheData))
    	elseif kind == "itemData" then
    		ctx.bind(rem.OnClientEvent:Connect(function(data, items)
    			ctx.cacheData(data)
    			if type(items) == "table" then
    				ctx.cache.shopItems = items
    			end
    		end))
    	elseif kind == "survived" then
    		ctx.bind(rem.OnClientEvent:Connect(function(ok)
    			if ok == true or tostring(ok):lower() == "survived" then
    				ctx.markSurvived("remote")
    			end
    		end))
    	elseif kind == "gameState" then
    		ctx.bind(rem.OnClientEvent:Connect(function(st)
    			local state = tostring(st):lower()
    			if state ~= "" and state ~= "nil" then
    				roundState = state
    			end
    			if state == "ingame" then
    				survivedSeen = false
    			elseif state == "survived" then
    				ctx.markSurvived("state")
    			end
    		end))
    	end
    end
    
    ctx.refreshFE2RemoteRegistry = function()
    	local function addOne(list, kind, rem)
    		if not (rem and rem:IsA("RemoteEvent")) then
    			return
    		end
    		for _, current in list do
    			if current == rem then
    				return
    			end
    		end
    		list[#list + 1] = rem
    		ctx.bindLateFE2Remote(kind, rem)
    	end
    
    	local function addGroup(list, kind, names)
    		for _, name in names do
    			addOne(list, kind, ctx.resolveFE2Remote(name, "RemoteEvent"))
    		end
    	end
    
    	addGroup(PressRemotes, nil, { "PressedMapButton", "igzyswprgEbMOxwZWHUxvFWNJhDtaODb" })
    	addGroup(LocatorRemotes, "locator", { "UpdGoalLocator", "FiIxfRCqDOTWRKHqFMoRjSaAxXOutMzD", "SetButtonLocator" })
    	addGroup(RoundStatsRemotes, "round", { "UpdIngameStats", "flDEUOrLddFXZVDiezUpxyiHWduVnlEC", "UpdateGameInfo" })
    	addGroup(LoadedMapRemotes, nil, { "LoadedMap" })
    	addGroup(SurvivedRemotes, "survived", { "Survived" })
    	addGroup(PlayerDataRemotes, "playerData", { "UpdPlayerData", "mbTUpXEtICXoMoBrBEoiHpRywCzJjtba" })
    	addGroup(ItemDataRemotes, "itemData", { "ReqItemData", "jBRXdUHKhwduqDelrUCPdolYbvaFGFMi" })
    	addGroup(GameStateRemotes, "gameState", { "UpdateGameState", "FBbJEWQDfbOPQZBNaWtXPmnKTDndEbbK" })
    	addGroup(ChallengeRemotes.GetAirBubble, nil, { "GetAirBubble" })
    	addGroup(ChallengeRemotes.SwimInLava, nil, { "SwimInLava", "fvgxdrskCQyGiyAbJXnVrzFRinSqigYN" })
    	addGroup(ChallengeRemotes.RegeneratedAir, nil, { "RegeneratedAir", "ZdwUWbHbtYFphslKtWDPwBpPOrOQbGPZ" })
    	addGroup(ChallengeRemotes.SlideCheck, nil, { "SlideCheck" })
    	addGroup(ChallengeRemotes.Walljumped, nil, { "Walljumped", "cLtjGlpevadbSJSvVQMCvNicyzbFZMGj" })
    
    	local remoteRoot = Rsp and Rsp:FindFirstChild("Remote")
    	local challengeFolder = remoteRoot and remoteRoot:FindFirstChild("Challenges")
    	local gameplayFolder = remoteRoot and remoteRoot:FindFirstChild("Gameplay")
    	addOne(ChallengeRemotes.RideZipline, nil, challengeFolder and challengeFolder:FindFirstChild("RideZipline"))
    	addOne(ZiplineRemotes.RideZipline, nil, remoteRoot and remoteRoot:FindFirstChild("RideZipline"))
    	addOne(ZiplineRemotes.Zipline, nil, remoteRoot and remoteRoot:FindFirstChild("Zipline"))
    	addOne(ZiplineRemotes.Zipline, nil, gameplayFolder and gameplayFolder:FindFirstChild("Zipline"))
    	addOne(WalljumpRemotes.Walljump, nil, gameplayFolder and gameplayFolder:FindFirstChild("Walljump"))
    
    	Lift = Lift or ctx.resolveFE2Remote("AddedWaiting", "RemoteEvent")
    		or ctx.resolveFE2Remote("sTYfsJjxNdIpKgbXIuymAQiYcmAaORRN", "RemoteEvent")
    		or ctx.resolveFE2Remote("dKgyIXnLdhwvSyEorkEWJJAkgUslGCtR", "RemoteEvent")
    	PasskeyRemote = PasskeyRemote or ctx.resolveFE2Remote("ReqPasskey", "RemoteFunction")
    	RebirthRemote = RebirthRemote or ctx.resolveFE2Remote("ReqRebirth", "RemoteEvent")
    		or ctx.resolveFE2Remote("LxWowhVdggjbxLTozuicVKHltFbUuVUg", "RemoteEvent")
    	ConfirmItemRemote = ConfirmItemRemote or ctx.resolveFE2Remote("ConfirmItem", "RemoteEvent")
    		or ctx.resolveFE2Remote("IBHzeWzRcHyDJcPNXXfEkcXARFJrSvvt", "RemoteEvent")
    
    	local passFolder = Rsp and Rsp:FindFirstChild("Remote")
    	passFolder = passFolder and passFolder:FindFirstChild("Pass")
    	if passFolder then
    		PassReqSeasonData = PassReqSeasonData
    			or passFolder:FindFirstChild("ReqSeasonData")
    			or passFolder:FindFirstChild("wYXTxuCjheiXJfcizJPuPwrfonMOVMVJ")
    		PassReqSeasonList = PassReqSeasonList
    			or passFolder:FindFirstChild("ReqSeasonList")
    			or passFolder:FindFirstChild("eumTfRpsBhpIbMhPbsgBhNWijGPZcWZZ")
    	end
    end
    
    ctx.startFE2RemoteRegistry = function()
    	for _, list in { LocatorRemotes, RoundStatsRemotes, PlayerDataRemotes, ItemDataRemotes, SurvivedRemotes, GameStateRemotes } do
    		for _, rem in list do
    			if rem and rem.Parent then
    				ctx.cache.fe2RemoteBound[rem] = true
    			end
    		end
    	end
    
    	ctx.refreshFE2RemoteRegistry()
    	local function bindRoot(root)
    		if not root or ctx.cache.fe2RemoteRoot == root then
    			return
    		end
    		ctx.cut(ctx.cache.fe2RemoteRootConn)
    		ctx.cache.fe2RemoteRoot = root
    		ctx.cache.fe2RemoteRootConn = root.DescendantAdded:Connect(function(obj)
    			if obj:IsA("RemoteEvent") or obj:IsA("RemoteFunction") then
    				task.defer(ctx.refreshFE2RemoteRegistry)
    			end
    		end)
    		ctx.bind(ctx.cache.fe2RemoteRootConn)
    	end
    
    	bindRoot(Rsp and Rsp:FindFirstChild("Remote"))
    	if Rsp then
    		ctx.bind(Rsp.ChildAdded:Connect(function(child)
    			if child.Name == "Remote" then
    				bindRoot(child)
    				task.defer(ctx.refreshFE2RemoteRegistry)
    			end
    		end))
    	end
    end
    
    ctx.startFE2RemoteRegistry()
    
    if LP then
    	ctx.bind(LP:GetAttributeChangedSignal("SurvivedRound"):Connect(function()
    		if LP:GetAttribute("SurvivedRound") == true then
    			ctx.markSurvived("attribute")
    		elseif LP:GetAttribute("IsPlaying") == true then
    			survivedSeen = false
    			roundState = "ingame"
    		end
    	end))
    	ctx.bind(LP:GetAttributeChangedSignal("IsPlaying"):Connect(function()
    		if LP:GetAttribute("IsPlaying") == true and LP:GetAttribute("SurvivedRound") ~= true then
    			survivedSeen = false
    			roundState = "ingame"
    		end
    	end))
    end
    
    ctx.requestPlayerData(true)
    
    ctx.restoreNc = function()
    	for part, originalCanCollide in cTab do
    		if part and part.Parent and type(originalCanCollide) == "boolean" then
    			pcall(function()
    				if part.CanCollide ~= originalCanCollide then
    					part.CanCollide = originalCanCollide
    				end
    			end)
    		end
    	end
    end
    
    ctx.addNc = function(obj)
    	if obj and obj:IsA("BasePart") and cTab[obj] == nil then
    		local ok, originalCanCollide = pcall(function()
    			return obj.CanCollide
    		end)
    		if ok then
    			cTab[obj] = originalCanCollide
    		end
    	end
    end
    
    ctx.clrNc = function()
    	ctx.cut(nCd1)
    	ctx.cut(nCd2)
    	nCd1 = nil
    	nCd2 = nil
    	ctx.restoreNc()
    	cTab = {}
    end
    
    ctx.bindNc = function(c)
    	ctx.clrNc()
    	if not c then
    		return
    	end
    	ctx.addNc(c)
    	for _, d in ctx.descOf(c) do
    		ctx.addNc(d)
    	end
    	nCd1 = c.DescendantAdded:Connect(function(d)
    		ctx.addNc(d)
    	end)
    	nCd2 = c.DescendantRemoving:Connect(function(d)
    		local originalCanCollide = cTab[d]
    		if d and d:IsA("BasePart") and type(originalCanCollide) == "boolean" then
    			pcall(function()
    				if d.CanCollide ~= originalCanCollide then
    					d.CanCollide = originalCanCollide
    				end
    			end)
    		end
    		cTab[d] = nil
    	end)
    end
    
    ctx.setNc = function(v)
    	ctx.cut(nCc)
    	nCc = nil
    	ctx.clrNc()
    	if not v or not Run or not LP then
    		return
    	end
    	ctx.bindNc(LP.Character)
    	nCc = Run.PreSimulation:Connect(function()
    		if not on then
    			return
    		end
    		for part in cTab do
    			if part and part.Parent then
    				if part.CanCollide ~= false then
    					part.CanCollide = false
    				end
    			else
    				cTab[part] = nil
    			end
    		end
    	end)
    end
    
    ctx.liftTarget = function()
    	local lobby = Wsp and Wsp:FindFirstChild("Lobby")
    	if not lobby then
    		return nil
    	end
    	local play = lobby:FindFirstChild("PlayHere")
    	if play then
    		local best = nil
    		for _, obj in ctx.descOf(play) do
    			if obj:IsA("BasePart") then
    				if obj:FindFirstChild("SurfaceGui") or not best then
    					best = obj
    				end
    			end
    		end
    		if best then
    			return best
    		end
    	end
    	local mw = lobby:FindFirstChild("MapWaiting")
    	local direct = mw and (mw:FindFirstChild("LiftTeleport", true) or mw:FindFirstChild("LiftCollision", true) or mw:FindFirstChild("Plate", true))
    	if direct and direct:IsA("BasePart") then
    		return direct
    	end
    	return nil
    end
    
    ctx.touchLift = function(part, r)
    	if not (part and part.Parent and r and r.Parent) then
    		return
    	end
    	if __exec.firetouchinterest ~= nil then
    		pcall(__exec.firetouchinterest, r, part, 0)
    		pcall(__exec.firetouchinterest, r, part, 1)
    	end
    end
    
    ctx.pushLift = function()
    	local r = select(1, ctx.rh(true))
    	if not r then
    		return
    	end
    	pcall(function()
    		ctx.pivotRootTo(r.CFrame + Vector3.new(0, 5, 0), r)
    	end)
    	while ctx.alive() and on and not ctx.inState("InLift") do
    		task.wait(0.1)
    		local rr = select(1, ctx.rh(false))
    		if not rr then
    			continue
    		end
    		local part = ctx.liftTarget()
    		if part then
    			pcall(function()
    				ctx.pivotRootTo(part.CFrame + Vector3.new(0, 3, 0), rr)
    				rr.AssemblyLinearVelocity = Vector3.zero
    			end)
    			ctx.touchLift(part, rr)
    		else
    			rr.AssemblyLinearVelocity = LFG
    		end
    		ctx.mkPlat(rr)
    	end
    end
    
    ctx.doLift = function()
    	if not on then
    		return
    	end
    	if Lift then
    		pcall(function()
    			Lift:FireServer()
    		end)
    	end
    	ctx.spawnLoop(function()
    		local ok, err = xpcall(ctx.pushLift, __traceback)
    		if not ok then
    			warn(err)
    		end
    	end)
    end
    
    ctx.antiVoid = function(getMap)
    	ctx.cut(aVc)
    	aVc = nil
    	if not Run then
    		return
    	end
    	aVc = Run.Heartbeat:Connect(function()
    		if not on then
    			return
    		end
    		local r = select(1, ctx.rh(false))
    		if not r then
    			return
    		end
    
    		local fy = ctx.voidY()
    		local pos = r.Position
    		local vel = Vector3.zero
    		pcall(function()
    			vel = r.AssemblyLinearVelocity
    		end)
    
    		local nearVoid = pos.Y <= fy + FDM
    		local badFall = vel.Y < -VLM and pos.Y <= fy + FDM * 2
    
    		if not nearVoid and not badFall then
    			ctx.saveSafe(r)
    			return
    		end
    
    		if nearVoid or badFall then
    			ctx.limVel(r, nearVoid)
    		end
    
    		local map = nil
    		local ok, res = pcall(getMap)
    		if ok then
    			map = res
    		end
    
    		local cf = ctx.safeMapCf(map, r)
    		pcall(function()
    			ctx.pivotRootTo(cf, r)
    		end)
    		ctx.limVel(r, true)
    		ctx.mkPlat(r)
    
    		if os.clock() - voidAt > 1 then
    			voidAt = os.clock()
    			ctx.note("Recovered from void")
    		end
    	end)
    end
    
    ctx.uiLabel = function(o, t)
    	if not o then
    		return
    	end
    	if type(o.setLabel) == "function" then
    		pcall(function()
    			o:setLabel(t)
    		end)
    	else
    		pcall(function()
    			o.Text = t
    		end)
    	end
    end
    
    ctx.uiColor = function(o, c)
    	if not o then
    		return
    	end
    	if type(o.modifyTheme) == "function" then
    		pcall(function()
    			o:modifyTheme({
    				{ "IconButton", "BackgroundColor3", c },
    				{ "IconOverlay", "BackgroundColor3", c },
    			})
    		end)
    	else
    		pcall(function()
    			o.BackgroundColor3 = c
    		end)
    	end
    end
    
    ctx.setTopBtn = function(o, t, st, col)
    	ctx.uiLabel(o, t)
    	ctx.uiColor(o, col or (st and Color3.fromRGB(60, 130, 210) or Color3.fromRGB(70, 70, 70)))
    end
    
    ctx.setBtn = function()
    	ctx.setTopBtn(ctx.ui.startBtn or btn, on and "Stop AutoFarm" or "Start AutoFarm", on, on and Color3.fromRGB(180, 60, 60) or Color3.fromRGB(60, 180, 60))
    end
    
    ctx.setAuraBtn = function()
    	ctx.setTopBtn(ctx.ui.auraBtn, auraOn and "Button Aura: ON" or "Button Aura: OFF", auraOn)
    end
    
    ctx.setDistModeBtn = function()
    	ctx.setTopBtn(ctx.ui.distModeBtn, auraUseDistance and "Button Distance: ON" or "Button Distance: OFF", auraUseDistance)
    end
    
    ctx.setDistBtn = function()
    	ctx.setTopBtn(ctx.ui.distBtn, "Aura Dist: " .. tostring(auraDist), false, Color3.fromRGB(55, 55, 55))
    end
    
    ctx.setBonusBtn = function()
    	ctx.setTopBtn(ctx.ui.bonusBtn, autoCollectBonuses and "Collect Bonuses: ON" or "Collect Bonuses: OFF", autoCollectBonuses)
    end
    
    ctx.setChallengeBtn = function()
    	ctx.setTopBtn(ctx.ui.chBtn, autoChallenges and "Challenge Manager: ON" or "Challenge Manager: OFF", autoChallenges)
    end
    
    ctx.setFloodBtn = function()
    	ctx.setTopBtn(ctx.ui.floodBtn, ctx.opt.floodOn and "Custom Flood: ON" or "Custom Flood: OFF", ctx.opt.floodOn)
    end
    
    ctx.setPassBtn = function()
    end
    
    ctx.setPaidBtn = function()
    	ctx.setTopBtn(ctx.ui.paidBtn, ctx.opt.paidOn and "Paid UI Locks: ON" or "Paid UI Locks: OFF", ctx.opt.paidOn)
    end
    
    ctx.setBuyCoinBtn = function()
    	ctx.setTopBtn(ctx.ui.buyCoinBtn, ctx.opt.shopBusy and "Buying Shop Items..." or "Buy Coin Shop Items", ctx.opt.shopBusy, ctx.opt.shopBusy and Color3.fromRGB(155, 89, 182) or Color3.fromRGB(218, 165, 32))
    end
    
    ctx.setBuyGemBtn = function()
    	ctx.setTopBtn(ctx.ui.buyGemBtn, ctx.opt.shopBusy and "Buying Shop Items..." or "Buy Gem Shop Items", ctx.opt.shopBusy, ctx.opt.shopBusy and Color3.fromRGB(155, 89, 182) or Color3.fromRGB(142, 68, 173))
    end
    
    ctx.setClipBtn = function()
    	ctx.setTopBtn(ctx.ui.clipBtn, ctx.opt.clipOn and "Side-Clip Rollback: BLOCKED" or "Side-Clip Rollback: GAME", ctx.opt.clipOn)
    end
    
    ctx.setFpPartBtn = function()
    	ctx.setTopBtn(ctx.ui.fpPartBtn, ctx.opt.fpPartOn and "First-Person FX: VISIBLE" or "First-Person FX: GAME", ctx.opt.fpPartOn)
    end
    
    ctx.setRescueBtn = function()
    	ctx.setTopBtn(ctx.ui.rescueBtn, ctx.opt.rescueOn and "Rescue Visual: HIDDEN" or "Rescue Visual: GAME", ctx.opt.rescueOn)
    end
    
    ctx.setDevBtn = function()
    	ctx.setTopBtn(ctx.ui.devBtn, ctx.opt.devOn and "DevTools: ON" or "DevTools: OFF", ctx.opt.devOn)
    end
    
    ctx.setWallBtn = function()
    end
    
    ctx.setSlidePhysBtn = function()
    end
    
    ctx.setZipBtn = function()
    	local enabled = ctx.opt.zipAutoOn and ctx.opt.zipFastOn
    	local label = ctx.opt.zipFastOn and ("Zip Speed: " .. tostring(ctx.opt.zipSpeed)) or "Zip Speed: OFF"
    	if ctx.opt.zipFastOn and not ctx.opt.zipAutoOn then
    		label ..= " (AUTO OFF)"
    	end
    	ctx.setTopBtn(ctx.ui.zipBtn, label, enabled)
    end
    
    ctx.setZipStopBtn = function()
    	local enabled = ctx.opt.zipAutoOn and ctx.opt.zipStopOn
    	local label = ctx.opt.zipStopOn and "Zip Stop Velocity: ON" or "Zip Stop Velocity: OFF"
    	if ctx.opt.zipStopOn and not ctx.opt.zipAutoOn then
    		label ..= " (AUTO OFF)"
    	end
    	ctx.setTopBtn(ctx.ui.zipStopBtn, label, enabled)
    end
    
    ctx.setZipAutoBtn = function()
    	ctx.setTopBtn(ctx.ui.zipAutoBtn, ctx.opt.zipAutoOn and "Zip Auto Apply: ON" or "Zip Auto Apply: OFF", ctx.opt.zipAutoOn)
    end
    
    ctx.setInfAirBtn = function()
    	ctx.setTopBtn(ctx.ui.infAirBtn, ctx.opt.infAirOn and "Inf Air: ON" or "Inf Air: OFF", ctx.opt.infAirOn)
    end
    
    ctx.setInfJumpBtn = function()
    	ctx.setTopBtn(ctx.ui.infJumpBtn, ctx.opt.infJumpOn and "Inf Jump: ON" or "Inf Jump: OFF", ctx.opt.infJumpOn)
    end
    
    ctx.setClickTpBtn = function()
    	ctx.setTopBtn(ctx.ui.clickTpBtn, ctx.opt.clickTpOn and "Click TP: ON" or "Click TP: OFF", ctx.opt.clickTpOn)
    end
    
    ctx.setFemVoteBtn = function()
    	ctx.setTopBtn(ctx.ui.femVoteBtn, ctx.opt.femVoteOn and "FEM Auto Vote: ON" or "FEM Auto Vote: OFF", ctx.opt.femVoteOn)
    end
    
    ctx.setSurviveBtn = function()
    	ctx.setTopBtn(ctx.ui.surviveBtn, ctx.opt.surviveLoopOn and "Survived Loop: ON" or "Survived Loop: OFF", ctx.opt.surviveLoopOn)
    end
    
    ctx.setOptionsOpen = function(open)
    	optionsOpen = open and true or false
    end
    
    local mouseButtonFixHooks = setmetatable({}, { __mode = "k" })
    
    ctx.tryDisconnect = function(conn)
    	if conn and type(conn.Disconnect) == "function" then
    		pcall(function()
    			conn:Disconnect()
    		end)
    	end
    end
    
    ctx.MouseButtonFix = function(button, clickCallback, pressInput)
    	if not button or type(clickCallback) ~= "function" then
    		return { Connected = false, Disconnect = function() end }
    	end
    
    	local clickTimeThreshold = 0.45
    	local moveThreshold = 10
    	local mouseDownTime = 0
    	local isPointerDown = false
    	local startPosition = nil
    	local maxMoveDistance = 0
    	local connections = {}
    	local disconnected = false
    	local wantedInput = pressInput or Enum.UserInputType.MouseButton1
    	local hookKey = tostring(wantedInput)
    	local hooks = mouseButtonFixHooks[button]
    	if type(hooks) ~= "table" then
    		hooks = {}
    		mouseButtonFixHooks[button] = hooks
    	end
    	local existing = hooks[hookKey]
    	if existing then
    		ctx.tryDisconnect(existing)
    	end
    
    	local state = {
    		Connected = true,
    	}
    
    	local function disconnectAll()
    		if disconnected then
    			return
    		end
    		disconnected = true
    		state.Connected = false
    		for i = 1, #connections do
    			ctx.tryDisconnect(connections[i])
    			connections[i] = nil
    		end
    		if hooks[hookKey] == state then
    			hooks[hookKey] = nil
    		end
    	end
    
    	function state:Disconnect()
    		disconnectAll()
    	end
    
    	hooks[hookKey] = state
    
    	local function getSignal(obj, signalName)
    		local ok, signal = pcall(function()
    			return obj[signalName]
    		end)
    		if ok and signal then
    			return signal
    		end
    		return nil
    	end
    
    	local function connectSignal(signal, fn)
    		if disconnected or not signal then
    			return false
    		end
    		local ok, conn = pcall(function()
    			return signal:Connect(fn)
    		end)
    		if ok and conn then
    			connections[#connections + 1] = conn
    			return true
    		end
    		return false
    	end
    
    	local function isPressInput(inputType)
    		if wantedInput == Enum.UserInputType.MouseButton1 then
    			return inputType == Enum.UserInputType.MouseButton1 or inputType == Enum.UserInputType.Touch
    		end
    		return inputType == wantedInput
    	end
    
    	local function resetState()
    		mouseDownTime = 0
    		isPointerDown = false
    		startPosition = nil
    		maxMoveDistance = 0
    	end
    
    	local function beginPointer(input)
    		if disconnected then
    			return
    		end
    		isPointerDown = true
    		mouseDownTime = tick()
    		maxMoveDistance = 0
    		local pos = input and input.Position
    		startPosition = pos and Vector2.new(pos.X, pos.Y) or nil
    	end
    
    	local function endPointer()
    		if disconnected then
    			return
    		end
    		if not isPointerDown or mouseDownTime == 0 then
    			resetState()
    			return
    		end
    		local holdDuration = tick() - mouseDownTime
    		local isClick = holdDuration < clickTimeThreshold and maxMoveDistance <= moveThreshold
    		resetState()
    		if isClick then
    			clickCallback()
    		end
    	end
    
    	local boundPress = false
    	local isGuiButton = type(button.IsA) == "function" and button:IsA("GuiButton")
    	if isGuiButton then
    		local downName = wantedInput == Enum.UserInputType.MouseButton2 and "MouseButton2Down" or "MouseButton1Down"
    		local upName = wantedInput == Enum.UserInputType.MouseButton2 and "MouseButton2Up" or "MouseButton1Up"
    		local downBound = connectSignal(getSignal(button, downName), function()
    			beginPointer(nil)
    		end)
    		local upBound = connectSignal(getSignal(button, upName), function()
    			endPointer()
    		end)
    		boundPress = downBound and upBound
    	end
    
    	if not boundPress then
    		local beganBound = connectSignal(getSignal(button, "InputBegan"), function(input)
    			if input and isPressInput(input.UserInputType) then
    				beginPointer(input)
    			end
    		end)
    		local endedBound = connectSignal(getSignal(button, "InputEnded"), function(input)
    			if input and isPressInput(input.UserInputType) then
    				endPointer()
    			end
    		end)
    		boundPress = beganBound and endedBound
    	end
    
    	connectSignal(getSignal(button, "InputChanged"), function(input)
    		if not isPointerDown then
    			return
    		end
    		if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
    			return
    		end
    		local pos = input.Position
    		if not pos then
    			return
    		end
    		if not startPosition then
    			startPosition = Vector2.new(pos.X, pos.Y)
    			return
    		end
    		local delta = (Vector2.new(pos.X, pos.Y) - startPosition).Magnitude
    		if delta > maxMoveDistance then
    			maxMoveDistance = delta
    		end
    	end)
    
    	if not boundPress then
    		disconnectAll()
    		return state
    	end
    
    	connectSignal(getSignal(button, "AncestryChanged"), function(_, parent)
    		if not parent then
    			task.defer(disconnectAll)
    		end
    	end)
    	connectSignal(getSignal(button, "Destroying"), disconnectAll)
    
    	return state
    end
    
    local NAgui = {
    	_dragState = {},
    	_draggerCleanups = {},
    }
    
    ctx.NAgui_dragger = function(ui, dragui)
    	if not ui then
    		return { Connected = false, Disconnect = function() end }
    	end
    	dragui = dragui or ui
    
    	local draggerId = tostring((ui.GetDebugId and ui:GetDebugId()) or ui)
    	local oldCleanup = NAgui._draggerCleanups[draggerId]
    	if type(oldCleanup) == "function" then
    		pcall(oldCleanup)
    	end
    
    	local ds = NAgui._dragState
    	local dragging = false
    	local dragStart = nil
    	local startPos = nil
    	local cleaned = false
    	local dragPointer = nil
    	local pendingInput = nil
    	local connections = {}
    	local moveConn = nil
    	local endConn = nil
    	local stepConn = nil
    
    	local state = {
    		Connected = true,
    	}
    
    	local function addConn(conn)
    		if conn then
    			connections[#connections + 1] = conn
    		end
    		return conn
    	end
    
    	local function disconnectLiveInput()
    		ctx.tryDisconnect(moveConn)
    		ctx.tryDisconnect(endConn)
    		ctx.tryDisconnect(stepConn)
    		moveConn = nil
    		endConn = nil
    		stepConn = nil
    		pendingInput = nil
    	end
    
    	local function stopDrag()
    		dragging = false
    		dragPointer = nil
    		pendingInput = nil
    		if ds.owner == ui then
    			ds.owner = nil
    			ds.input = nil
    		end
    		disconnectLiveInput()
    	end
    
    	local function cleanupDragger()
    		if cleaned then
    			return
    		end
    		cleaned = true
    		state.Connected = false
    		stopDrag()
    		for i = 1, #connections do
    			ctx.tryDisconnect(connections[i])
    			connections[i] = nil
    		end
    		if NAgui._draggerCleanups[draggerId] == cleanupDragger then
    			NAgui._draggerCleanups[draggerId] = nil
    		end
    	end
    
    	function state:Disconnect()
    		cleanupDragger()
    	end
    
    	NAgui._draggerCleanups[draggerId] = cleanupDragger
    
    	local function getOrder(g)
    		local z = 0
    		pcall(function()
    			z = g.ZIndex or 0
    		end)
    		local lc = g:FindFirstAncestorWhichIsA("LayerCollector")
    		local d = 0
    		if lc and lc:IsA("ScreenGui") then
    			pcall(function()
    				d = lc.DisplayOrder or 0
    			end)
    		end
    		return d * 10000 + z
    	end
    
    	local function isTopMost(root, input)
    		if not (Guis and input and input.Position) then
    			return true
    		end
    		local pos = input.Position
    		local list = nil
    		local ok = pcall(function()
    			list = Guis:GetGuiObjectsAtPosition(pos.X, pos.Y)
    		end)
    		if not ok or type(list) ~= "table" or #list == 0 then
    			return true
    		end
    		local top = nil
    		local topOrder = nil
    		for _, g in list do
    			if typeof(g) == "Instance" and g:IsA("GuiObject") then
    				local order = getOrder(g)
    				if not top or order > topOrder then
    					top = g
    					topOrder = order
    				end
    			end
    		end
    		if not top then
    			return true
    		end
    		return top == root or top:IsDescendantOf(root)
    	end
    
    	local function getParentSize()
    		local parent = ui.Parent
    		if parent then
    			local ok, size = pcall(function()
    				return parent.AbsoluteSize
    			end)
    			if ok and size and size.X > 0 and size.Y > 0 then
    				return size
    			end
    		end
    		local cam = Wsp and Wsp.CurrentCamera
    		if cam then
    			return cam.ViewportSize
    		end
    		return Vector2.new(1920, 1080)
    	end
    
    	local function update(input)
    		if not ui or not ui.Parent or not input or not dragStart or not startPos then
    			return
    		end
    		local delta = input.Position - dragStart
    		local screenSize = getParentSize()
    		if not screenSize or screenSize.X <= 0 or screenSize.Y <= 0 then
    			return
    		end
    		local newXScale = startPos.X.Scale + (startPos.X.Offset + delta.X) / screenSize.X
    		local newYScale = startPos.Y.Scale + (startPos.Y.Offset + delta.Y) / screenSize.Y
    		ui.Position = UDim2.new(newXScale, 0, newYScale, 0)
    	end
    
    	addConn(dragui.InputBegan:Connect(function(input)
    		if cleaned then
    			return
    		end
    		if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch)
    			and (not ds.owner or ds.owner == ui)
    			and isTopMost(dragui, input) then
    			ds.owner = ui
    			ds.input = input
    			dragging = true
    			dragPointer = input
    			dragStart = input.Position
    			startPos = ui.Position
    			disconnectLiveInput()
    			if Uis then
    				moveConn = Uis.InputChanged:Connect(function(changedInput)
    					if not dragging or ds.owner ~= ui then
    						return
    					end
    					local inputType = changedInput.UserInputType
    					if inputType == Enum.UserInputType.MouseMovement then
    						pendingInput = changedInput
    					elseif inputType == Enum.UserInputType.Touch and changedInput == dragPointer then
    						pendingInput = changedInput
    					end
    				end)
    				endConn = Uis.InputEnded:Connect(function(endedInput)
    					if not dragging then
    						return
    					end
    					local inputType = endedInput.UserInputType
    					if inputType == Enum.UserInputType.MouseButton1 or (inputType == Enum.UserInputType.Touch and endedInput == dragPointer) then
    						stopDrag()
    					end
    				end)
    			end
    			if Run then
    				stepConn = Run.RenderStepped:Connect(function()
    					local frameInput = pendingInput
    					if not frameInput then
    						return
    					end
    					pendingInput = nil
    					if not dragging or ds.owner ~= ui then
    						return
    					end
    					update(frameInput)
    				end)
    			end
    		end
    	end))
    
    	addConn(ui.AncestryChanged:Connect(function(_, parent)
    		if not parent then
    			task.defer(cleanupDragger)
    		end
    	end))
    	if ui.Destroying then
    		addConn(ui.Destroying:Connect(cleanupDragger))
    	end
    	if dragui ~= ui then
    		addConn(dragui.AncestryChanged:Connect(function(_, parent)
    			if not parent then
    				task.defer(cleanupDragger)
    			end
    		end))
    		if dragui.Destroying then
    			addConn(dragui.Destroying:Connect(cleanupDragger))
    		end
    	end
    
    	pcall(function()
    		ui.Active = true
    	end)
    	pcall(function()
    		dragui.Active = true
    	end)
    
    	return state
    end
    
    ctx.toggle = function(v)
    	on = v and true or false
    	tok += 1
    	cur = nil
    	pressWin = 0
    	pressCnt = 0
    	ctx.clearLocators()
    	survivedSeen = false
    	ctx.setBtn()
    	ctx.note(on and "Enabled" or "Disabled")
    	ctx.setNc(on)
    	farmTok += 1
    
    	if not on then
    		saveFlushTok += 1
    		pendingSaveSig = nil
    		ctx.releaseRoot()
    		ctx.killPlat()
    		return
    	end
    
    	ctx.startFarmRemotes()
    	ctx.spawnLoop(ctx.burstLoaded)
    	ctx.requestPlayerData(true)
    
    	if ctx.inState("InGame") then
    		ctx.note("Resuming current map")
    		local m = ctx.curMap()
    		if m and m.Parent then
    			cur = m
    			local id = tok
    			ctx.spawnLoop(function()
    				ctx.onMap(m, id)
    			end)
    		end
    	else
    		ctx.doLift()
    	end
    end
    
    ctx.onChar = function(c)
    	if not ctx.alive() then
    		return
    	end
    	ctx.bindNc(c)
    	ctx.hookZipStop(c)
    	ctx.patchSideClip()
    	ctx.patchFpParts()
    	ctx.patchRescue()
    	if ctx.opt.zipFastOn and ctx.opt.zipAutoOn then
    		task.defer(ctx.reapplyZipSpeed)
    	end
    	if on then
    		ctx.spawnLoop(function()
    			if not Lift then
    				return
    			end
    			for _ = 1, RRP do
    				if not (ctx.alive() and on) then
    					return
    				end
    				pcall(function()
    					Lift:FireServer()
    				end)
    				task.wait(RRG)
    			end
    		end)
    		ctx.spawnLoop(function()
    			local ok, err = xpcall(ctx.pushLift, __traceback)
    			if not ok then
    				warn(err)
    			end
    		end)
    	end
    end
    
    ctx.onMap = function(map, id)
    	local hp
    	local ok, err = xpcall(function()
    		local r, h = ctx.rh(true)
    		if not r or not h or not map or not map.Parent then
    			return
    		end
    		safeCf = r.CFrame
    		safeAt = os.clock()
    
    		ctx.resetMapCache(map)
    		local st = ctx.mapSettings(map)
    		local nm = nil
    		if st then
    			local ok2, v = pcall(function()
    				return st:GetAttribute("MapName")
    			end)
    			if ok2 then
    				nm = v
    			end
    		end
    		if not nm then
    			nm = map.Name
    		end
    
    		survivedSeen = false
    		ctx.note("Map Loaded! " .. tostring(nm))
    		ctx.spawnLoop(ctx.burstLoaded)
    
    		if not ctx.inState("InGame") then
    			ctx.note("Skipping due to InGame == false.")
    			cur = nil
    			return
    		end
    
    		local btns = {}
    		local ok2, res = pcall(ctx.scanBtns, map)
    		if ok2 and type(res) == "table" then
    			btns = res
    		end
    		ctx.mergeLocatorBtns(btns, map)
    		ctx.startAutoFarmButtonSpam(map, id, btns)
    
    		ctx.collectMapBonuses(map, r, true)
    
    		ctx.note("Commencing Auto Farm")
    
    		hp = h:GetPropertyChangedSignal("Health"):Connect(function()
    			pcall(function()
    				if h.Parent and h.Health < 1000 then
    					h.Health = 1000
    				end
    			end)
    		end)
    
    		roundCur = nil
    		roundTotal = nil
    		roundLeft = nil
    		roundState = nil
    		for _, rem in RoundStatsRemotes do
    			if rem and rem.Parent then
    				pcall(function()
    					rem:FireServer()
    				end)
    			end
    		end
    		local tr = 0
    		local sent = {}
    		local lastPress = {}
    		local pressLoops = {}
    		local lastExitPulse = 0
    		local waitLocSeq = nil
    		local waitLocAt = 0
    
    		while ctx.activeRun(map, id) and ctx.inState("InGame") do
    			task.wait(SCI)
    			if not (ctx.activeRun(map, id) and ctx.inState("InGame")) then
    				break
    			end
    
    			r, h = ctx.rh(false)
    			if not r or not h then
    				continue
    			end
    
    			pcall(function()
    				h.Jump = true
    			end)
    
    			local ex = ctx.mapExit(map)
    			ctx.mergeLocatorBtns(btns, map)
    			local exitReady = ex and (ctx.buttonsDone() or (not ctx.isFE2CMGame() and ctx.allButtonsHandled(btns, map, sent)))
    			if ctx.isRetroGame() then
    				exitReady = ex and ctx.retroButtonsDone(btns, sent)
    			end
    
    			if waitLocSeq and locSeq ~= waitLocSeq then
    				waitLocSeq = nil
    			end
    
    			local pressFirst = not exitReady
    			if exitReady then
    				for _, entry in btns do
    					if entry.loc and entry.hit and entry.hit.Parent and locBtns[entry.hit] == entry then
    						pressFirst = true
    						break
    					end
    				end
    			end
    
    			if exitReady and not pressFirst and waitLocSeq and os.clock() - waitLocAt < LHW then
    				ctx.releaseRoot(r)
    				ctx.mkPlat(r)
    				continue
    			end
    
    			if pressFirst then
    				for _, entry in btns do
    					if not ctx.activeRun(map, id) then
    						break
    					end
    
    					local b = entry.src
    					local hit = entry.hit
    					local key = entry.loc and entry or hit
    					local currentLoc = not entry.loc or locBtns[hit] == entry
    					local canPress = entry.loc or ctx.entryReady(entry, map)
    					if currentLoc and canPress and (not exitReady or entry.loc) and hit and hit.Parent then
    						local ti = ctx.ffc(hit, "TouchInterest", true) or ctx.ffc(b, "TouchInterest", true)
    						local gg = nil
    						pcall(function()
    							gg = (b and b:FindFirstChildWhichIsA("BillboardGui", true)) or hit:FindFirstChildWhichIsA("BillboardGui", true)
    						end)
    						if entry.loc or entry.retro or (ti and gg) then
    							r, h = ctx.rh(false)
    							if not r or not h then
    								break
    							end
    							if not ctx.activeRun(map, id) then
    								break
    							end
    							local fuse = ctx.isFuseBtn(b)
    							pcall(function()
    								r.Anchored = false
    								ctx.pivotRootTo(CFrame.new(hit.Position), r)
    								h:ChangeState(Enum.HumanoidStateType.Jumping)
    								r.Velocity = JMP
    							end)
    							task.wait(TPD)
    							if not ctx.activeRun(map, id) then
    								ctx.releaseRoot()
    								break
    							end
    							local now = os.clock()
    							local pressedNow = false
    							if entry.loc then
    								if not lastPress[key] or now - lastPress[key] >= PCD then
    									lastPress[key] = now
    									pressedNow = ctx.pressMapButton(hit) == true
    									waitLocSeq = entry.seq
    									waitLocAt = now
    								end
    							else
    								if not fuse and not pressLoops[key] then
    									pressLoops[key] = true
    									ctx.startPressLoop(hit, id, function()
    										return ctx.activeRun(map, id) and ctx.inState("InGame") and not ctx.buttonsDone() and ctx.entryReady(entry, map)
    									end)
    								end
    								pressedNow = ctx.pressMapButton(hit) == true
    								if pressedNow then
    									sent[key] = true
    								end
    							end
    							if fuse then
    								if pressedNow then
    									ctx.moveFuseSafe(b, hit, r, function()
    										return ctx.activeRun(map, id)
    									end)
    								else
    									ctx.releaseRoot(r)
    								end
    							else
    								pcall(function()
    									ctx.pivotRootTo(CFrame.new(hit.Position + Vector3.new(0, ESY, 0)), r)
    									r.Anchored = true
    								end)
    							end
    							task.wait(BTD)
    							ctx.releaseRoot(r)
    							if not ctx.activeRun(map, id) then
    								ctx.releaseRoot()
    								break
    							end
    						end
    					end
    				end
    			else
    				if not ctx.activeRun(map, id) then
    					break
    				end
    				pcall(function()
    					r.Anchored = false
    				end)
    				if tr < EXM then
    					tr += 1
    					pcall(function()
    						ctx.pivotRootTo(ex.CFrame, r)
    						r.Velocity = EXP
    					end)
    					ctx.mkPlat(r)
    					task.wait(TPD)
    					if not ctx.activeRun(map, id) then
    						ctx.releaseRoot()
    						break
    					end
    					if (r.Position - ex.Position).Magnitude <= 5 then
    						tr += 1
    						ctx.fireSurvived(ctx.getPassArg(false), 100)
    						local now = os.clock()
    						if now - lastExitPulse >= 0.5 then
    							lastExitPulse = now
    							ctx.statPulse(false)
    							ctx.statBurst()
    							if pendingSaveSig == nil then
    								ctx.flushStatsAfterSurvival()
    							end
    						end
    					end
    				else
    					tr = 0
    					ctx.mkPlat(r)
    					task.wait(TPD)
    					if not ctx.activeRun(map, id) then
    						ctx.releaseRoot()
    						break
    					end
    				end
    			end
    		end
    	end, __traceback)
    
    	ctx.cut(hp)
    
    	if not ok then
    		warn(err)
    		ctx.note("Map handler error; continuing")
    	end
    
    	if not ctx.activeRun(map, id) then
    		ctx.clearLocators()
    		ctx.releaseRoot()
    		return
    	end
    
    	local r = select(1, ctx.rh(false))
    	if r then
    		ctx.mkPlat(r)
    	end
    
    	if not (ctx.alive() and on) then
    		return
    	end
    
    	ctx.note("Complete. Waiting for next map..")
    
    	while ctx.alive() and on do
    		task.wait(0.2)
    		local m = ctx.curMap()
    		local rr = select(1, ctx.rh(false))
    		if rr then
    			ctx.mkPlat(rr)
    		end
    		if m and m ~= map then
    			ctx.clearLocators()
    			break
    		end
    	end
    end
    
    ctx.curMap = function()
    	if not MP or not MP.Parent then
    		MP = Wsp and Wsp:FindFirstChild("Multiplayer") or nil
    	end
    	if ctx.liveChildOf(ctx.cache.curMap, MP) and (ctx.cache.curMap.Name == "Map" or ctx.cache.curMap.Name == "NewMap") then
    		return ctx.cache.curMap
    	end
    	local now = os.clock()
    	if now < (ctx.cache.curMapAt or 0) then
    		return nil
    	end
    	ctx.cache.curMapAt = now + 0.1
    	ctx.cache.curMap = MP and (MP:FindFirstChild("Map") or MP:FindFirstChild("NewMap")) or nil
    	if ctx.cache.curMap then
    		ctx.resetMapCache(ctx.cache.curMap)
    	end
    	return ctx.cache.curMap
    end
    
    ctx.rootPart = function()
    	local c = ctx.chr(false)
    	if not c then
    		return nil
    	end
    	return c:FindFirstChild("HumanoidRootPart", true)
    end
    
    ctx.startButtonAura = function()
    	auraTok += 1
    	local id = auraTok
    	ctx.spawnLoop(function()
    		local map = nil
    		local req = 0
    		while ctx.alive() and auraTok == id do
    			if not auraOn then
    				task.wait(0.1)
    				map = nil
    				auraList = {}
    				auraMap = nil
    				continue
    			end
    
    			local m = ctx.curMap()
    			if m ~= map then
    				map = m
    				auraList = {}
    				auraMap = nil
    			end
    
    			local now = os.clock()
    			if not ctx.isFEMGame() and now >= req then
    				ctx.requestRoundStats()
    				req = now + 0.75
    			end
    
    			if ctx.isFEMGame() and type(ctx.pressMapButton) == "function" then
    				ctx.tmpRoot = select(1, ctx.rh(false))
    				ctx.tmpHit = ctx.femLocatorHit()
    				if ctx.tmpRoot and ctx.tmpHit and ctx.tmpHit.Parent then
    					ctx.tmpDist = (ctx.tmpRoot.Position - ctx.tmpHit.Position).Magnitude
    					if not auraUseDistance or ctx.tmpDist <= auraDist then
    						ctx.pressMapButton(ctx.tmpHit)
    					end
    				end
    			elseif map and ctx.isRoundIngame() and type(ctx.pressMapButton) == "function" then
    				local entries, hasLoc = ctx.auraEntries(map)
    				if #entries > 0 then
    					ctx.pressAuraEntries(entries, map, not hasLoc)
    				end
    			end
    
    			task.wait(ASI)
    		end
    	end)
    end
    
    ctx.addRemoteOnce = function(list, obj)
    	if type(list) ~= "table" or not (obj and typeof(obj) == "Instance" and obj:IsA("RemoteEvent")) then
    		return false
    	end
    	for _, old in list do
    		if old == obj then
    			return true
    		end
    	end
    	list[#list + 1] = obj
    	return true
    end
    
    ctx.findRemoteNamed = function(nm)
    	if type(nm) ~= "string" or nm == "" then
    		return nil
    	end
    	ctx.tmpCachedRemote = ctx.cache.remoteByName[nm]
    	if ctx.tmpCachedRemote and ctx.tmpCachedRemote.Parent then
    		return ctx.tmpCachedRemote
    	end
    	ctx.tmpRootRemote = Rsp and Rsp:FindFirstChild("Remote")
    	ctx.tmpTestRemote = ctx.tmpRootRemote and ctx.tmpRootRemote:FindFirstChild("TEST")
    	ctx.tmpFoundRemote = ctx.tmpTestRemote and ctx.tmpTestRemote:FindFirstChild(nm) or nil
    	if not (ctx.tmpFoundRemote and ctx.tmpFoundRemote:IsA("RemoteEvent")) then
    		ctx.tmpFoundRemote = ctx.tmpRootRemote and ctx.tmpRootRemote:FindFirstChild(nm, true) or nil
    	end
    	if not (ctx.tmpFoundRemote and ctx.tmpFoundRemote:IsA("RemoteEvent")) then
    		pcall(function()
    			for _, o in Rsp:QueryDescendants("Instance") do
    				if o.Name == nm and o:IsA("RemoteEvent") then
    					ctx.tmpFoundRemote = o
    					break
    				end
    			end
    		end)
    	end
    	if not (ctx.tmpFoundRemote and ctx.tmpFoundRemote:IsA("RemoteEvent")) then
    		ctx.tmpScanFns = {}
    		if __exec.getnilinstances then
    			ctx.tmpScanFns[#ctx.tmpScanFns + 1] = __exec.getnilinstances
    		end
    		if __exec.getinstances then
    			ctx.tmpScanFns[#ctx.tmpScanFns + 1] = __exec.getinstances
    		end
    		for _, fn in ctx.tmpScanFns do
    			ctx.tmpOk, ctx.tmpList = pcall(fn)
    			if ctx.tmpOk and type(ctx.tmpList) == "table" then
    				for _, o in ctx.tmpList do
    					if typeof(o) == "Instance" and o.Name == nm and o:IsA("RemoteEvent") then
    						ctx.tmpFoundRemote = o
    						break
    					end
    				end
    			end
    			if ctx.tmpFoundRemote then
    				break
    			end
    		end
    	end
    	if ctx.tmpFoundRemote and ctx.tmpFoundRemote:IsA("RemoteEvent") then
    		ctx.cache.remoteByName[nm] = ctx.tmpFoundRemote
    		return ctx.tmpFoundRemote
    	end
    	return nil
    end
    
    ctx.fireChallenge = function(n, ...)
    	local t = ChallengeRemotes[n]
    	if type(t) ~= "table" then
    		return false
    	end
    	local hasRemote = false
    	for _, rem in t do
    		if rem and rem.Parent then
    			hasRemote = true
    			break
    		end
    	end
    	if not hasRemote then
    		ctx.addRemoteOnce(t, ctx.findRemoteNamed(n))
    	end
    	local fired = false
    	for _, rem in t do
    		if rem and rem.Parent then
    			local ok = pcall(function(...)
    				rem:FireServer(...)
    			end, ...)
    			fired = fired or ok
    		end
    	end
    	return fired
    end
    
    ctx.fireZipline = function(part)
    	if not (part and part.Parent) then
    		return false
    	end
    	local fired = ctx.fireChallenge("RideZipline", part)
    	for _, rem in ZiplineRemotes.RideZipline do
    		if rem and rem.Parent then
    			local ok = pcall(function()
    				rem:FireServer(part)
    			end)
    			fired = fired or ok
    		end
    	end
    	for _, rem in ZiplineRemotes.Zipline do
    		if rem and rem.Parent then
    			local ok = pcall(function()
    				rem:FireServer(part)
    			end)
    			fired = fired or ok
    		end
    	end
    	return fired
    end
    
    ctx.wallData = function(wall, r, c)
    	if not (wall and wall.Parent and wall:IsA("BasePart")) then
    		return nil
    	end
    	r = r or select(1, ctx.rh(false))
    	c = c or ctx.chr(false)
    	local rp = r and r.Position or (wall.Position + wall.CFrame.LookVector * 4)
    	local pos = wall.Position
    	local norm = nil
    	local dir = wall.Position - rp
    	if dir.Magnitude > 0.05 and Wsp then
    		local prm = RaycastParams.new()
    		prm.FilterType = Enum.RaycastFilterType.Exclude
    		local ex = {}
    		if c then
    			ex[#ex + 1] = c
    		end
    		if Wsp.CurrentCamera then
    			ex[#ex + 1] = Wsp.CurrentCamera
    		end
    		prm.FilterDescendantsInstances = ex
    		local ok, hit = pcall(function()
    			return Wsp:Raycast(rp, dir.Unit * math.min(dir.Magnitude + 6, 12), prm)
    		end)
    		if ok and hit then
    			local okPos, hitPos = pcall(function()
    				return hit.Position
    			end)
    			local okNorm, hitNorm = pcall(function()
    				return hit.Normal
    			end)
    			if okPos and hitPos then
    				pos = hitPos
    			end
    			if okNorm and hitNorm then
    				norm = hitNorm
    			end
    		end
    	end
    	if not norm then
    		norm = rp - wall.Position
    		norm = Vector3.new(norm.X, 0, norm.Z)
    		if norm.Magnitude < 0.05 then
    			norm = wall.CFrame.LookVector
    		end
    		norm = norm.Unit
    	end
    	local c0 = wall.CFrame:ToObjectSpace(CFrame.new(pos + norm * 0.5, pos + norm))
    	return pos, norm, c0
    end
    
    ctx.fireWalljump = function(wall, c0)
    	if not (wall and wall.Parent) then
    		return false
    	end
    	local fired = false
    	for _, rem in WalljumpRemotes.Walljump do
    		if rem and rem.Parent then
    			local ok = pcall(function()
    				if c0 ~= nil then
    					rem:FireServer(wall, c0)
    				else
    					rem:FireServer(wall)
    				end
    			end)
    			fired = fired or ok
    		end
    	end
    	fired = ctx.fireChallenge("Walljumped", wall) or fired
    	return fired
    end
    
    ctx.releaseWalljump = function()
    	local r, h, c = ctx.rh(false)
    	for _, rem in WalljumpRemotes.Walljump do
    		if rem and rem.Parent then
    			pcall(function()
    				rem:FireServer()
    			end)
    		end
    	end
    	if r and r.Parent then
    		for _, ch in r:GetChildren() do
    			if ch.ClassName == "ManualWeld" and (ch.Name == "WalljumpWeld_Live" or ch.Name == "WalljumpWeld_Server") then
    				pcall(function()
    					ch.Part0 = nil
    					ch.Part1 = nil
    					ch:Destroy()
    				end)
    			end
    		end
    	end
    	if h then
    		pcall(function()
    			h.AutoRotate = true
    			h:SetStateEnabled(Enum.HumanoidStateType.Running, true)
    			h:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    			h:SetStateEnabled(Enum.HumanoidStateType.RunningNoPhysics, true)
    			h:SetStateEnabled(Enum.HumanoidStateType.Climbing, true)
    			h:ChangeState(Enum.HumanoidStateType.Jumping)
    		end)
    	end
    	local ps = LP and LP:FindFirstChild("PlayerScripts")
    	local main = ps and ps:FindFirstChild("CL_MAIN_GameScript")
    	local tv = main and main:FindFirstChild("ToggleVelocity")
    	if tv and tv.Fire then
    		pcall(function()
    			tv:Fire(true)
    		end)
    	end
    end
    
    ctx.jumpOffWall = function(wall, norm)
    	local r, h = ctx.rh(false)
    	if not (r and r.Parent) then
    		return
    	end
    	norm = norm or Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z)
    	if norm.Magnitude < 0.05 then
    		norm = Vector3.new(0, 0, -1)
    	end
    	norm = norm.Unit
    	local cfg = wall and wall:FindFirstChild("_Wall")
    	local ang = 45
    	if cfg then
    		local a = cfg:GetAttribute("JumpAngle")
    		if type(a) == "number" then
    			ang = math.clamp(a, -90, 90)
    		end
    	end
    	local sp = 70.71
    	local cf = CFrame.new(Vector3.new(), norm)
    	local lv = (cf * CFrame.Angles(math.rad(ang), 0, 0)).LookVector
    	ctx.releaseWalljump()
    	pcall(function()
    		r.AssemblyLinearVelocity = Vector3.new(lv.X * sp, math.max(48, lv.Y * sp), lv.Z * sp)
    		r.AssemblyAngularVelocity = Vector3.zero
    		if h then
    			h:ChangeState(Enum.HumanoidStateType.Jumping)
    		end
    	end)
    end
    
    ctx.dumpChallenges = function()
    	return
    end
    
    ctx.addChallengeHit = function(list, obj)
    	if obj and not list[obj] then
    		list[obj] = true
    	end
    end
    
    ctx.remChallengeHit = function(list, obj)
    	if obj then
    		list[obj] = nil
    	end
    end
    
    ctx.clearChallengeIndex = function()
    	chTok += 1
    	for _, c in chCons do
    		ctx.cut(c)
    	end
    	chCons = {}
    	chIndex = { air = {}, wall = {}, zip = {}, slide = {} }
    	chCache = chIndex
    end
    
    ctx.airHitbox = function(obj)
    	if not obj then
    		return nil
    	end
    	if obj.Name == "AirTank" then
    		local hb = obj:FindFirstChild("Hitbox")
    		if hb and hb:IsA("BasePart") then
    			return hb
    		end
    	elseif obj:IsA("BasePart") and obj.Name == "Hitbox" and obj.Parent and obj.Parent.Name == "AirTank" then
    		return obj
    	end
    	return nil
    end
    
    ctx.indexChallengeObj = function(obj)
    	if not obj then
    		return
    	end
    	local hb = ctx.airHitbox(obj)
    	if hb then
    		ctx.addChallengeHit(chIndex.air, hb)
    	end
    	if obj:IsA("BasePart") then
    		if obj:FindFirstChild("_Wall") then
    			ctx.addChallengeHit(chIndex.wall, obj)
    		elseif obj.Name == "RopeStart" then
    			ctx.addChallengeHit(chIndex.zip, obj)
    		elseif obj.Name == "SlideBeam" then
    			ctx.addChallengeHit(chIndex.slide, obj)
    		end
    	end
    end
    
    ctx.unindexChallengeObj = function(obj)
    	if not obj then
    		return
    	end
    	local hb = ctx.airHitbox(obj)
    	if hb then
    		ctx.remChallengeHit(chIndex.air, hb)
    	end
    	ctx.remChallengeHit(chIndex.air, obj)
    	ctx.remChallengeHit(chIndex.wall, obj)
    	ctx.remChallengeHit(chIndex.zip, obj)
    	ctx.remChallengeHit(chIndex.slide, obj)
    end
    
    ctx.seedChallengeRoot = function(root, id)
    	if not (root and root.Parent) then
    		return
    	end
    	ctx.indexChallengeObj(root)
    	local q = { root }
    	local qi = 1
    	local steps = 0
    	while ctx.alive() and chTok == id and qi <= #q do
    		local obj = q[qi]
    		qi += 1
    		if obj and obj.Parent then
    			ctx.indexChallengeObj(obj)
    			local ok, kids = pcall(obj.GetChildren, obj)
    			if ok and type(kids) == "table" then
    				for _, ch in kids do
    					q[#q + 1] = ch
    				end
    			end
    		end
    		steps += 1
    		if steps % 120 == 0 then
    			task.wait()
    		end
    	end
    end
    
    ctx.bindChallengeRoot = function(root, id, seed)
    	if not (root and root.Parent) then
    		return
    	end
    	chCons[#chCons + 1] = root.DescendantAdded:Connect(function(obj)
    		if chTok == id then
    			ctx.indexChallengeObj(obj)
    		end
    	end)
    	chCons[#chCons + 1] = root.DescendantRemoving:Connect(function(obj)
    		if chTok == id then
    			ctx.unindexChallengeObj(obj)
    		end
    	end)
    	if seed ~= false then
    		ctx.spawnLoop(function()
    			ctx.seedChallengeRoot(root, id)
    		end)
    	end
    end
    
    ctx.ensureChallenges = function(map)
    	if not (map and map.Parent) then
    		if chMap ~= nil then
    			chMap = nil
    			ctx.clearChallengeIndex()
    		end
    		return false
    	end
    	if chMap == map then
    		return true
    	end
    	chMap = map
    	ctx.clearChallengeIndex()
    	local id = chTok
    	chSeen = setmetatable({}, { __mode = "k" })
    	chWallSeen = setmetatable({}, { __mode = "k" })
    	chZipSeen = setmetatable({}, { __mode = "k" })
    	chSlideSeen = setmetatable({}, { __mode = "k" })
    	chSlideAt = 0
    	chWallAt = 0
    	chZipAt = 0
    	chAirAt = 0
    	ctx.bindChallengeRoot(map, id, true)
    	local deb = Wsp and Wsp:FindFirstChild("Debris")
    	if deb then
    		ctx.bindChallengeRoot(deb, id, false)
    	end
    	return true
    end
    
    ctx.listFromIndex = function(src, root)
    	local out = {}
    	local deb = Wsp and Wsp:FindFirstChild("Debris")
    	for obj in src do
    		if obj and obj.Parent and ((root and obj:IsDescendantOf(root)) or (deb and obj:IsDescendantOf(deb))) then
    			out[#out + 1] = obj
    		else
    			src[obj] = nil
    		end
    	end
    	return out
    end
    
    ctx.challengeHits = function(map)
    	if not ctx.ensureChallenges(map) then
    		return { air = {}, wall = {}, zip = {}, slide = {} }
    	end
    	return {
    		air = ctx.listFromIndex(chIndex.air, map),
    		wall = ctx.listFromIndex(chIndex.wall, map),
    		zip = ctx.listFromIndex(chIndex.zip, map),
    		slide = ctx.listFromIndex(chIndex.slide, map),
    	}
    end
    
    ctx.feScript = function()
    	local c = ctx.chr(false)
    	if not c then
    		return nil
    	end
    	local fe = c:FindFirstChild("FE2_Character")
    	if fe then
    		return fe
    	end
    	return nil
    end
    
    ctx.envOf = function(scr)
    	if not scr then
    		return nil
    	end
    	if __exec.getsenv then
    		local ok, env = pcall(__exec.getsenv, scr)
    		if ok and type(env) == "table" then
    			return env
    		end
    	end
    	return nil
    end
    
    ctx.gameEnv = function()
    	if ctx.cache.gameEnv then
    		return ctx.cache.gameEnv
    	end
    	local m = ctx.mainScript()
    	ctx.cache.gameEnv = ctx.envOf(m)
    	return ctx.cache.gameEnv
    end
    
    ctx.baseEnv = function()
    	if ctx.cache.baseEnv ~= nil then
    		return ctx.cache.baseEnv ~= false and ctx.cache.baseEnv or nil
    	end
    	if __exec.getfenv then
    		local ok, env = pcall(__exec.getfenv)
    		if ok and type(env) == "table" then
    			ctx.cache.baseEnv = env
    			return env
    		end
    	end
    	ctx.cache.baseEnv = type(_G) == "table" and _G or false
    	return ctx.cache.baseEnv ~= false and ctx.cache.baseEnv or nil
    end
    
    ctx.scriptGlobal = function(env, name)
    	if type(env) == "table" then
    		local v = rawget(env, name)
    		if v ~= nil then
    			return v
    		end
    		local g = rawget(env, "_G")
    		if type(g) == "table" and rawget(g, name) ~= nil then
    			return rawget(g, name)
    		end
    	end
    	local b = ctx.baseEnv()
    	if type(b) == "table" then
    		if rawget(b, name) ~= nil then
    			return rawget(b, name)
    		end
    		local g = rawget(b, "_G")
    		if type(g) == "table" then
    			return rawget(g, name)
    		end
    	end
    	return nil
    end
    
    ctx.callScriptGlobal = function(env, name, ...)
    	local fn = ctx.scriptGlobal(env, name)
    	if type(fn) ~= "function" then
    		return false
    	end
    	return pcall(fn, ...)
    end
    
    ctx.feEnv = function()
    	ctx.tmpFeScript = ctx.feScript()
    	return ctx.envOf(ctx.tmpFeScript)
    end
    
    ctx.feCall = function(name, ...)
    	return ctx.callScriptGlobal(ctx.feEnv(), name, ...)
    end
    
    ctx.slidePts = function(bm, r)
    	if not (bm and bm.Parent and bm:IsA("BasePart")) then
    		return nil
    	end
    	local sx = bm.Size.X
    	local sz = bm.Size.Z
    	local ax = sx >= sz and bm.CFrame.RightVector or bm.CFrame.LookVector
    	ax = Vector3.new(ax.X, 0, ax.Z)
    	if ax.Magnitude < 0.05 then
    		ax = r and Vector3.new(r.CFrame.LookVector.X, 0, r.CFrame.LookVector.Z) or Vector3.new(1, 0, 0)
    	end
    	ax = ax.Unit
    	local len = math.max(sx, sz)
    	local a = bm.Position - ax * math.max(8, len * 0.48)
    	local b = bm.Position + ax * math.max(28, len * 0.48)
    	local y = bm.Position.Y - math.max(2.25, bm.Size.Y * 0.5 + 1.75)
    	return Vector3.new(a.X, y, a.Z), Vector3.new(b.X, y, b.Z), ax
    end
    
    ctx.trySlideChallenge = function(list, remoteOnly)
    	local now = os.clock()
    	if now - chSlideAt < 6 then
    		return false
    	end
    	list = type(list) == "table" and list or {}
    	local r, h, c = ctx.rh(false)
    	if not (r and r.Parent and h and c and c.Parent) then
    		return false
    	end
    	local best = nil
    	local bestDist = math.huge
    	for _, bm in list do
    		if bm and bm.Parent then
    			local t = chSlideSeen[bm]
    			if not t or now - t > 8 then
    				local d = (r.Position - bm.Position).Magnitude
    				if d < bestDist then
    					best = bm
    					bestDist = d
    				end
    			end
    		end
    	end
    	local p1, p2, dir
    	if best then
    		p1, p2, dir = ctx.slidePts(best, r)
    	else
    		return false
    	end
    	if not (p1 and p2 and dir) then
    		return false
    	end
    	chSlideAt = now
    	if best then
    		chSlideSeen[best] = now
    	end
    	if remoteOnly == true then
    		return ctx.fireChallenge("SlideCheck", p1, Vector3.new(p2.X, p1.Y, p2.Z))
    	end
    	local old = r.CFrame
    	local ok = false
    	local env = ctx.feEnv()
    	pcall(function()
    		ctx.pivotRootTo(CFrame.new(p1, p1 + dir), r, c)
    		r.AssemblyLinearVelocity = Vector3.zero
    		r.AssemblyAngularVelocity = Vector3.zero
    	end)
    	task.wait(0.05)
    	local fe = ctx.feScript()
    	local sl = fe and fe:FindFirstChild("Slide")
    	if sl and sl:IsA("BindableEvent") then
    		pcall(function()
    			sl:Fire(nil, Enum.UserInputState.Begin, best ~= nil)
    		end)
    	end
    	if env and type(env.runSlide) == "function" then
    		pcall(env.runSlide, nil, Enum.UserInputState.Begin, best ~= nil)
    	end
    	task.wait(0.12)
    	pcall(function()
    		ctx.pivotRootTo(CFrame.new(p2, p2 + dir), r, c)
    		r.AssemblyLinearVelocity = Vector3.zero
    		r.AssemblyAngularVelocity = Vector3.zero
    	end)
    	task.wait(0.05)
    	if env and type(env.endSlide) == "function" then
    		ok = pcall(env.endSlide, p1) or ok
    	end
    	ok = ctx.fireChallenge("SlideCheck", p1, Vector3.new(p2.X, p1.Y, p2.Z)) or ok
    	if old and r and r.Parent and on then
    		task.delay(0.15, function()
    			if ctx.alive() and on and r and r.Parent then
    				pcall(function()
    					ctx.pivotRootTo(old, r, c)
    					r.AssemblyLinearVelocity = Vector3.zero
    					r.AssemblyAngularVelocity = Vector3.zero
    				end)
    			end
    		end)
    	end
    	return ok
    end
    
    ctx.tryWallChallenge = function(list, remoteOnly)
    	list = type(list) == "table" and list or {}
    	ctx.tmpWallSent = false
    	for _, wall in list do
    		if wall and wall.Parent and not chWallSeen[wall] then
    			chWallSeen[wall] = os.clock()
    			ctx.tmpWallSent = ctx.fireChallenge("Walljumped", wall) or ctx.tmpWallSent
    			task.wait(0.05)
    		end
    	end
    	return ctx.tmpWallSent
    end
    ctx.tryZipChallenge = function(list, remoteOnly)
    	list = type(list) == "table" and list or {}
    	ctx.tmpZipSent = false
    	for _, rope in list do
    		if rope and rope.Parent then
    			ctx.tmpZipLast = chZipSeen[rope]
    			if not ctx.tmpZipLast then
    				chZipSeen[rope] = os.clock()
    				ctx.tmpZipSent = ctx.fireChallenge("RideZipline", rope) or ctx.tmpZipSent
    				task.wait(0.05)
    			end
    		end
    	end
    	return ctx.tmpZipSent
    end
    ctx.getFeHitbox = function()
    	local c = ctx.chr(false)
    	if not c then
    		return nil
    	end
    	local hb = c:FindFirstChild("FE2_Hitbox")
    	if hb and hb:IsA("BasePart") then
    		return hb
    	end
    	return nil
    end
    
    ctx.touchAirTank = function(hb, remoteOnly)
    	if not (hb and hb.Parent and hb:IsA("BasePart")) then
    		return false
    	end
    	local now = os.clock()
    	local last = chSeen[hb]
    	if last and now - last < 2.5 then
    		return false
    	end
    	local r, h = ctx.rh(false)
    	if not (r and r.Parent) or (h and h.Health <= 0) then
    		return false
    	end
    	local dist = (r.Position - hb.Position).Magnitude
    	if remoteOnly == true then
    		chSeen[hb] = now
    		return ctx.fireChallenge("GetAirBubble", hb)
    	end
    	if dist > 10 then
    		return false
    	end
    	chSeen[hb] = now
    	local fe = ctx.getFeHitbox()
    	local ok = false
    	if fe and fe.Parent and __exec.firetouchinterest ~= nil then
    		pcall(__exec.firetouchinterest, fe, hb, 0)
    		pcall(__exec.firetouchinterest, hb, fe, 0)
    		task.wait(0.05)
    		pcall(__exec.firetouchinterest, fe, hb, 1)
    		pcall(__exec.firetouchinterest, hb, fe, 1)
    		ok = true
    	end
    	if hb and hb.Parent then
    		ok = ctx.fireChallenge("GetAirBubble", hb) or ok
    	end
    	return ok
    end
    
    ctx.tryAirChallenges = function(list, remoteOnly)
    	local now = os.clock()
    	if now - chAirAt < 1.5 then
    		return false
    	end
    	chAirAt = now
    	list = type(list) == "table" and list or {}
    	local r = select(1, ctx.rh(false))
    	if not (r and r.Parent) then
    		return false
    	end
    	local best = nil
    	local bestDist = remoteOnly == true and math.huge or 10
    	for _, hb in list do
    		if hb and hb.Parent then
    			local t = chSeen[hb]
    			if not t or now - t > 6 then
    				local d = (r.Position - hb.Position).Magnitude
    				if d <= bestDist then
    					best = hb
    					bestDist = d
    				end
    			end
    		end
    	end
    	return best and ctx.touchAirTank(best, remoteOnly) or false
    end
    
    ctx.cache.challengePlan = ctx.cache.challengePlan or {
    	known = false,
    	active = true,
    	all = true,
    	air = true,
    	lava = true,
    	slide = true,
    	wall = true,
    	zip = true,
    }
    
    ctx.updateChallengePlan = function(data)
    	ctx.tmpDaily = type(data) == "table" and data.dailyChallenges or nil
    	if type(ctx.tmpDaily) ~= "table" then
    		ctx.cache.challengePlan.known = false
    		ctx.cache.challengePlan.active = true
    		ctx.cache.challengePlan.all = true
    		return
    	end
    
    	ctx.tmpTier = "standard"
    	ctx.tmpStandard = ctx.tmpDaily.standard
    	if type(ctx.tmpStandard) == "table" then
    		ctx.tmpAllStandard = true
    		for _, challenge in ctx.tmpStandard do
    			if type(challenge) == "table" and challenge.completed ~= true then
    				ctx.tmpAllStandard = false
    				break
    			end
    		end
    		if ctx.tmpAllStandard then
    			ctx.tmpTier = "master"
    		end
    	end
    
    	ctx.tmpRows = ctx.tmpDaily[ctx.tmpTier]
    	if type(ctx.tmpRows) ~= "table" then
    		ctx.cache.challengePlan.known = false
    		ctx.cache.challengePlan.active = true
    		ctx.cache.challengePlan.all = true
    		return
    	end
    
    	ctx.tmpPlan = {
    		known = true,
    		active = false,
    		all = false,
    		air = false,
    		lava = false,
    		slide = false,
    		wall = false,
    		zip = false,
    		premium = ctx.isLocalPremium(),
    		premiumBlocked = false,
    	}
    
    	for _, challenge in ctx.tmpRows do
    		if type(challenge) == "table" then
    			ctx.tmpRequired = tonumber(challenge.amtRequired) or 1
    			ctx.tmpCurrent = tonumber(challenge.amtCurrent) or 0
    			ctx.tmpPremiumChallenge = challenge.isPremium == true
    			ctx.tmpPremiumAllowed = not ctx.tmpPremiumChallenge or ctx.tmpPlan.premium == true
    			if challenge.completed ~= true and ctx.tmpCurrent < ctx.tmpRequired and ctx.tmpPremiumAllowed then
    				ctx.tmpPlan.active = true
    				ctx.tmpDesc = string.lower(tostring(challenge.desc or challenge.name or ""))
    				ctx.tmpMatched = false
    				if string.find(ctx.tmpDesc, "air", 1, true) or string.find(ctx.tmpDesc, "bubble", 1, true) or string.find(ctx.tmpDesc, "tank", 1, true) or string.find(ctx.tmpDesc, "regenerat", 1, true) then
    					ctx.tmpPlan.air = true
    					ctx.tmpMatched = true
    				end
    				if string.find(ctx.tmpDesc, "lava", 1, true) or string.find(ctx.tmpDesc, "acid", 1, true) then
    					ctx.tmpPlan.lava = true
    					ctx.tmpMatched = true
    				end
    				if string.find(ctx.tmpDesc, "slide", 1, true) then
    					ctx.tmpPlan.slide = true
    					ctx.tmpMatched = true
    				end
    				if string.find(ctx.tmpDesc, "wall", 1, true) then
    					ctx.tmpPlan.wall = true
    					ctx.tmpMatched = true
    				end
    				if string.find(ctx.tmpDesc, "zip", 1, true) then
    					ctx.tmpPlan.zip = true
    					ctx.tmpMatched = true
    				end
    				if not ctx.tmpMatched then
    					ctx.tmpPlan.all = true
    				end
    			elseif challenge.completed ~= true and ctx.tmpCurrent < ctx.tmpRequired and ctx.tmpPremiumChallenge then
    				ctx.tmpPlan.premiumBlocked = true
    			end
    		end
    	end
    
    	ctx.cache.challengePlan = ctx.tmpPlan
    end
    
    ctx.refreshChallengeEligibility = function()
    	if type(ctx.updateChallengePlan) == "function" then
    		ctx.updateChallengePlan(pdata)
    	end
    end
    
    if LP then
    	pcall(function()
    		ctx.bind(LP:GetPropertyChangedSignal("MembershipType"):Connect(ctx.refreshChallengeEligibility))
    	end)
    	pcall(function()
    		ctx.bind(LP:GetPropertyChangedSignal("HasRobloxSubscription"):Connect(ctx.refreshChallengeEligibility))
    	end)
    end
    if Plr and Plr.PlayerMembershipChanged then
    	ctx.bind(Plr.PlayerMembershipChanged:Connect(function(player)
    		if player == LP then
    			ctx.refreshChallengeEligibility()
    		end
    	end))
    end
    
    ctx.challengeNeeded = function(kind)
    	ctx.tmpPlan = ctx.cache.challengePlan
    	if type(ctx.tmpPlan) ~= "table" or ctx.tmpPlan.known ~= true then
    		return true
    	end
    	if ctx.tmpPlan.active ~= true then
    		return false
    	end
    	return ctx.tmpPlan.all == true or ctx.tmpPlan[kind] == true
    end
    
    ctx.doChallenges = function(map, remoteOnly)
    	if not (autoChallenges and ctx.isRoundIngame()) then
    		return
    	end
    	ctx.dumpChallenges()
    	ctx.tmpNow = os.clock()
    	if ctx.challengeNeeded("lava") and ctx.tmpNow - chLavaAt > 5 then
    		chLavaAt = ctx.tmpNow
    		ctx.fireChallenge("SwimInLava")
    	end
    	ctx.tmpHits = ctx.challengeHits(map)
    	if ctx.challengeNeeded("air") then
    		ctx.tryAirChallenges(ctx.tmpHits.air, remoteOnly == true)
    	end
    	if ctx.challengeNeeded("slide") then
    		ctx.trySlideChallenge(ctx.tmpHits.slide, remoteOnly == true)
    	end
    	if ctx.challengeNeeded("wall") then
    		ctx.tryWallChallenge(ctx.tmpHits.wall, remoteOnly == true)
    	end
    	if ctx.challengeNeeded("zip") then
    		ctx.tryZipChallenge(ctx.tmpHits.zip, remoteOnly == true)
    	end
    end
    
    ctx.startChallenges = function()
    	ctx.updateChallengePlan(pdata)
    	ctx.spawnLoop(function()
    		while ctx.alive() do
    			if autoChallenges then
    				ctx.doChallenges(ctx.curMap(), true)
    			end
    			task.wait(CHI)
    		end
    	end)
    	ctx.spawnLoop(function()
    		while ctx.alive() do
    			if ctx.opt.infAirOn or (autoChallenges and ctx.challengeNeeded("air")) then
    				ctx.fireRegenAir()
    			end
    			task.wait(1)
    		end
    	end)
    end
    
    ctx.startBonusCollector = function()
    	ctx.spawnLoop(function()
    		while ctx.alive() do
    			if autoCollectBonuses then
    				local map = ctx.curMap()
    				if map and map.Parent then
    					local r = select(1, ctx.rh(false))
    					ctx.collectMapBonuses(map, r, true)
    				end
    			end
    			task.wait(0.3) -- Bonus collector loop interval
    		end
    	end)
    end
    
    ctx.floodPage = function()
    	local pg = LP and LP:FindFirstChildOfClass("PlayerGui")
    	local mg = pg and pg:FindFirstChild("MenuGui")
    	local op = mg and mg:FindFirstChild("Options")
    	local win = op and op:FindFirstChild("Window")
    	local cont = win and win:FindFirstChild("Content")
    	local pages = cont and cont:FindFirstChild("Pages")
    	return pages and pages:FindFirstChild("CustomFloodColors") or nil
    end
    
    ctx.floodWaterScript = function()
    	local ps = LP and LP:FindFirstChild("PlayerScripts")
    	local misc = ps and ps:FindFirstChild("Misc")
    	return misc and misc:FindFirstChild("CL_WaterColors") or nil
    end
    
    ctx.floodBind = function(obj, ev, fn)
    	if not obj or ctx.cache.floodHooks[obj] then
    		return
    	end
    	local sig = obj[ev]
    	if not sig then
    		return
    	end
    	ctx.cache.floodHooks[obj] = true
    	ctx.bind(sig:Connect(fn))
    end
    
    ctx.floodCols = function()
    	if not ctx.opt.floodRandom then
    		return ctx.flood.floodColors
    	end
    	local cfg = Rsp and Rsp:FindFirstChild("Config")
    	local rnd = cfg and cfg:FindFirstChild("RandomFloodColors")
    	if not rnd then
    		return ctx.flood.floodColors
    	end
    	local out = {}
    	for k, v in ctx.flood.floodColors do
    		local ok, c = pcall(function()
    			return rnd:GetAttribute(k)
    		end)
    		out[k] = ok and typeof(c) == "Color3" and c or v
    	end
    	return out
    end
    
    ctx.floodSetProp = function(obj, prop, col)
    	pcall(function()
    		local old = obj[prop]
    		obj[prop] = typeof(old) == "ColorSequence" and ColorSequence.new(col) or col
    	end)
    end
    
    ctx.floodVisual = function(col, obj)
    	if not obj then
    		return
    	end
    	if obj:IsA("BasePart") then
    		ctx.floodSetProp(obj, "Color", col)
    	elseif obj:IsA("Light") then
    		ctx.floodSetProp(obj, "Color", col)
    	elseif obj.ClassName == "Decal" then
    		ctx.floodSetProp(obj, "Color3", col)
    	elseif obj.ClassName == "Smoke" then
    		ctx.floodSetProp(obj, "Color", col)
    	elseif obj.ClassName == "Trail" or obj.ClassName == "ParticleEmitter" or obj.ClassName == "Beam" then
    		ctx.floodSetProp(obj, "Color", col)
    	elseif obj.ClassName == "Fire" then
    		ctx.floodSetProp(obj, "Color", col)
    		ctx.floodSetProp(obj, "SecondaryColor", col)
    	elseif obj.ClassName == "Sparkles" then
    		ctx.floodSetProp(obj, "SparklesColor", col)
    	elseif obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
    		ctx.floodSetProp(obj, "ImageColor3", col)
    	end
    end
    
    ctx.floodState = function(part)
    	local st = "water"
    	local val = part and part:FindFirstChild("WaterState")
    	pcall(function()
    		if val and type(val.Value) == "string" then
    			st = string.lower(val.Value)
    		end
    	end)
    	if ctx.flood.floodColors[st] then
    		return st
    	end
    	local nm = string.lower(part and part.Name or "")
    	if string.find(nm, "acid") then
    		return "acid"
    	elseif string.find(nm, "lava") then
    		return "lava"
    	end
    	return "water"
    end
    
    ctx.floodApply = function(root)
    	if not (ctx.opt.floodOn and ctx.opt.floodEnabled and root) then
    		return
    	end
    	local cols = ctx.floodCols()
    	local desc = ctx.descOf(root)
    	for _, obj in desc do
    		if obj:IsA("BasePart") and string.find(obj.Name, "_Water") then
    			local col = cols[ctx.floodState(obj)] or cols.water
    			ctx.floodVisual(col, obj)
    		end
    	end
    	for _, obj in desc do
    		if obj:IsA("ObjectValue") and obj.Name == "_LinkColor" and obj.Value and obj.Value:IsA("BasePart") then
    			local p = obj.Parent
    			if p then
    				local col = obj.Value.Color
    				ctx.floodVisual(col, p)
    				for _, ch in ctx.descOf(p) do
    					ctx.floodVisual(col, ch)
    				end
    			end
    		end
    	end
    end
    
    ctx.floodSetHsv = function(key, nm, val)
    	local h, s, v = ctx.flood.floodColors[key]:ToHSV()
    	val = math.clamp(val, 0.01, 0.99)
    	if nm == "Hue" then
    		h = val
    	elseif nm == "Saturation" then
    		s = val
    	elseif nm == "Value" then
    		v = val
    	end
    	ctx.flood.floodColors[key] = Color3.fromHSV(h, s, v)
    	ctx.floodPush()
    end
    
    ctx.floodStep = function(key, nm, dir)
    	local h, s, v = ctx.flood.floodColors[key]:ToHSV()
    	local cur = nm == "Hue" and h or nm == "Saturation" and s or v
    	ctx.floodSetHsv(key, nm, cur + 0.06125 * dir)
    end
    
    ctx.floodUi = function()
    	local page = ctx.floodPage()
    	if not page then
    		return
    	end
    	local buy = page:FindFirstChild("PurchaseGamepass")
    	if buy then
    		buy.Visible = false
    		buy.Active = false
    	end
    	local tog = page:FindFirstChild("CustomToggle")
    	if tog then
    		tog.Text = ctx.opt.floodEnabled and "Enabled" or "Disabled"
    		tog.BackgroundColor3 = ctx.opt.floodEnabled and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(24, 34, 44)
    	end
    	local rnd = page:FindFirstChild("MapRandomizer")
    	if rnd then
    		rnd.BackgroundColor3 = ctx.opt.floodRandom and Color3.fromRGB(46, 204, 113) or Color3.fromRGB(24, 34, 44)
    	end
    	local hsv = page:FindFirstChild("HSV_Container")
    	if not hsv then
    		return
    	end
    	for key, col in ctx.flood.floodColors do
    		local box = hsv:FindFirstChild(key .. "_HSV")
    		if box then
    			pcall(function()
    				local h, ss, vv = col:ToHSV()
    				local dat = {
    					{ n = "Hue", v = h },
    					{ n = "Saturation", v = ss },
    					{ n = "Value", v = vv },
    				}
    				for _, it in dat do
    					local cn = it.n == "Saturation" and "Sat" or it.n == "Value" and "Val" or it.n
    					local obj = box.Config[cn]
    					obj.Info.Text = it.n .. ": " .. tostring(math.floor(it.v * 100 * 1.021) - 1) .. "%"
    					obj.Bar.Graphic.Marker:TweenPosition(UDim2.new(it.v, 0, 0.5, 0), "Out", "Sine", 0.3, true)
    				end
    				box.Input.HexInput.Text = "#" .. col:ToHex()
    				box.Preview.BackgroundColor3 = col
    				box.Config.Val.Bar.Graphic.BackgroundColor3 = Color3.fromHSV(h, ss, 1)
    				box.Config.Sat.Bar.Graphic.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
    				box.Config.Sat.Bar.Graphic.DarknessCover.BackgroundTransparency = vv
    			end)
    		end
    	end
    end
    
    ctx.floodPush = function()
    	local wc = ctx.floodWaterScript()
    	local ev = wc and wc:FindFirstChild("UpdCustomColors")
    	if ev and ev.Fire then
    		pcall(function()
    			ev:Fire(ctx.flood.floodColors, ctx.opt.floodEnabled, ctx.opt.floodRandom, "RGB")
    		end)
    	end
    	ctx.floodUi()
    	ctx.floodApply(ctx.curMap())
    end
    
    ctx.floodHookUi = function()
    	local page = ctx.floodPage()
    	if not page then
    		return
    	end
    	ctx.floodUi()
    	ctx.floodBind(page:FindFirstChild("CustomToggle"), "Activated", function()
    		if not ctx.opt.floodOn then
    			return
    		end
    		ctx.opt.floodEnabled = not ctx.opt.floodEnabled
    		ctx.floodPush()
    	end)
    	ctx.floodBind(page:FindFirstChild("MapRandomizer"), "Activated", function()
    		if not ctx.opt.floodOn then
    			return
    		end
    		ctx.opt.floodRandom = not ctx.opt.floodRandom
    		ctx.floodPush()
    	end)
    	local hsv = page:FindFirstChild("HSV_Container")
    	if not hsv then
    		return
    	end
    	local themes = {
    		Classic = { water = Color3.fromRGB(13, 105, 172), acid = Color3.fromRGB(3, 252, 3), lava = Color3.fromRGB(252, 28, 3) },
    		Realism = { water = Color3.fromRGB(152, 194, 219), acid = Color3.fromRGB(117, 17, 1), lava = Color3.fromRGB(213, 115, 61) },
    		Vapor = { water = Color3.fromRGB(86, 3, 252), acid = Color3.fromRGB(252, 169, 3), lava = Color3.fromRGB(3, 252, 252) },
    		Soda = { water = Color3.fromRGB(252, 169, 3), acid = Color3.fromRGB(252, 84, 126), lava = Color3.fromRGB(84, 84, 252) },
    	}
    	local th = hsv:FindFirstChild("Themes")
    	local tc = th and th:FindFirstChild("ThemeContainer")
    	if tc then
    		for _, b in tc:GetChildren() do
    			if b:IsA("GuiButton") then
    				ctx.floodBind(b, "Activated", function()
    					local dat = themes[b.Text]
    					if not dat then
    						return
    					end
    					for k, v in dat do
    						ctx.flood.floodColors[k] = v
    					end
    					ctx.floodPush()
    				end)
    			end
    		end
    	end
    	for key in ctx.flood.floodColors do
    		local box = hsv:FindFirstChild(key .. "_HSV")
    		if box then
    			local hex = box:FindFirstChild("Input") and box.Input:FindFirstChild("HexInput")
    			ctx.floodBind(hex, "FocusLost", function()
    				local ok, c = pcall(function()
    					return Color3.fromHex(hex.Text)
    				end)
    				if ok and typeof(c) == "Color3" then
    					ctx.flood.floodColors[key] = c
    				end
    				ctx.floodPush()
    			end)
    			for _, sp in {
    				{ n = "Hue" },
    				{ n = "Saturation" },
    				{ n = "Value" },
    			} do
    				local cn = sp.n == "Saturation" and "Sat" or sp.n == "Value" and "Val" or sp.n
    				local row = box.Config and box.Config:FindFirstChild(cn)
    				local bar = row and row:FindFirstChild("Bar")
    				local gr = bar and bar:FindFirstChild("Graphic")
    				ctx.floodBind(bar and bar:FindFirstChild("Less"), "Activated", function()
    					ctx.floodStep(key, sp.n, -1)
    				end)
    				ctx.floodBind(bar and bar:FindFirstChild("More"), "Activated", function()
    					ctx.floodStep(key, sp.n, 1)
    				end)
    				ctx.floodBind(gr, "MouseButton1Down", function(x)
    					if type(x) ~= "number" or gr.AbsoluteSize.X <= 0 then
    						return
    					end
    					ctx.floodSetHsv(key, sp.n, (x - gr.AbsolutePosition.X) / gr.AbsoluteSize.X)
    				end)
    			end
    		end
    	end
    end
    
    ctx.startFloodColors = function()
    	if not ctx.support("flood") then
    		return
    	end
    	ctx.cache.floodTok += 1
    	local id = ctx.cache.floodTok
    	local rmt = Rsp and Rsp:FindFirstChild("Remote")
    	local tw = rmt and rmt:FindFirstChild("TweenWaterColor")
    	if tw and tw:IsA("RemoteEvent") then
    		ctx.bind(tw.OnClientEvent:Connect(function(part)
    			if ctx.opt.floodOn and part then
    				task.defer(function()
    					ctx.floodApply(ctx.curMap() or part.Parent)
    				end)
    			end
    		end))
    	end
    	ctx.spawnLoop(function()
    		local uiAt = 0
    		local lastMap = nil
    		while ctx.alive() and ctx.cache.floodTok == id do
    			if ctx.opt.floodOn then
    				local now = os.clock()
    				if now >= uiAt then
    					ctx.floodHookUi()
    					uiAt = now + 3
    				end
    				local map = ctx.curMap()
    				if map and map ~= lastMap then
    					lastMap = map
    					task.defer(ctx.floodApply, map)
    				end
    			end
    			task.wait(1.5)
    		end
    	end)
    end
    
    ctx.pg = function()
    	return LP and LP:FindFirstChildOfClass("PlayerGui") or nil
    end
    
    ctx.uiSet = function(obj, prop, val)
    	if not obj then
    		return
    	end
    	pcall(function()
    		obj[prop] = val
    	end)
    end
    
    ctx.uiHide = function(obj)
    	ctx.uiSet(obj, "Visible", false)
    	ctx.uiSet(obj, "Active", false)
    end
    
    ctx.uiEach = function(root, fn)
    	if not (root and type(fn) == "function") then
    		return
    	end
    	fn(root)
    	for _, obj in ctx.descOf(root) do
    		fn(obj)
    	end
    end
    
    ctx.uiBind = function(obj, ev, tag, fn)
    	if not (obj and type(fn) == "function") then
    		return
    	end
    	local h = ctx.cache.uiHooks[obj]
    	if type(h) ~= "table" then
    		h = {}
    		ctx.cache.uiHooks[obj] = h
    	end
    	local k = tostring(ev) .. tostring(tag)
    	if h[k] then
    		return
    	end
    	local sig = obj[ev]
    	if not sig then
    		return
    	end
    	h[k] = true
    	ctx.bind(sig:Connect(fn))
    end
    
    ctx.dataLib = function()
    	local mods = Rsp and Rsp:FindFirstChild("Modules")
    	local sh = mods and mods:FindFirstChild("Shared")
    	local m = sh and sh:FindFirstChild("FE2DataLibrary")
    	if m and type(require) == "function" then
    		local ok, lib = pcall(require, m)
    		if ok and type(lib) == "table" then
    			return lib
    		end
    	end
    end
    
    
    ctx.shopItemList = function()
    	local dl = ctx.dataLib()
    	if dl and type(dl.ItemData) == "table" then
    		ctx.cache.shopItems = dl.ItemData
    		return ctx.cache.shopItems, dl
    	end
    	if type(ctx.cache.shopItems) == "table" then
    		return ctx.cache.shopItems, dl
    	end
    	ctx.requestPlayerData(true)
    	local st = os.clock()
    	repeat
    		dl = ctx.dataLib()
    		if dl and type(dl.ItemData) == "table" then
    			ctx.cache.shopItems = dl.ItemData
    			return ctx.cache.shopItems, dl
    		end
    		if type(ctx.cache.shopItems) == "table" then
    			return ctx.cache.shopItems, dl
    		end
    		task.wait(0.05)
    	until os.clock() - st > 3 or not ctx.alive()
    	return ctx.cache.shopItems, dl
    end
    
    ctx.ownedItems = function()
    	local out = {}
    	local inv = type(pdata) == "table" and pdata.inventory or nil
    	if type(inv) == "table" then
    		for _, id in inv do
    			local n = tonumber(id) or id
    			out[n] = true
    		end
    	end
    	return out
    end
    
    ctx.shopBuyIds = function(cur)
    	local list = ctx.shopItemList()
    	local ids = {}
    	local seen = {}
    	local owned = ctx.ownedItems()
    	cur = tonumber(cur)
    	if type(list) ~= "table" then
    		return ids
    	end
    	for _, it in list do
    		if type(it) == "table" then
    			local id = tonumber(it.ID)
    			local cat = tostring(it.catagory or "")
    			local cc = tonumber(it.currency)
    			if id and cc == cur and not seen[id] and not owned[id] and it.notForSale ~= true and cat ~= "Currency" and cat ~= "Gamepasses" and cat ~= "UGC" then
    				seen[id] = true
    				ids[#ids + 1] = id
    			end
    		end
    	end
    	return ids
    end
    
    ctx.buyShopCurrency = function(cur)
    	if ctx.isFEMGame() then
    		return ctx.buyFemShopCurrency(cur)
    	end
    	if ctx.opt.shopBusy then
    		return
    	end
    	ctx.opt.shopBusy = true
    	ctx.setBuyCoinBtn()
    	ctx.setBuyGemBtn()
    	local name = cur == 1 and "gem" or "coin"
    	local function done(msg)
    		ctx.opt.shopBusy = false
    		ctx.setBuyCoinBtn()
    		ctx.setBuyGemBtn()
    		if msg then
    			ctx.note(msg)
    		end
    	end
    
    	if not (ConfirmItemRemote and ConfirmItemRemote.Parent) then
    		done("ConfirmItem remote not found.")
    		return
    	end
    	local key = ctx.getPassArg(false)
    	if key == nil then
    		done("Passkey not ready.")
    		return
    	end
    	ctx.requestPlayerData(true)
    	local ids = ctx.shopBuyIds(cur)
    	if #ids < 1 then
    		done("No " .. name .. " shop items found.")
    		return
    	end
    	for _, id in ids do
    		pcall(function()
    			ConfirmItemRemote:FireServer(key, id)
    		end)
    		task.wait(0.08)
    	end
    	pcall(function()
    		ConfirmItemRemote:FireServer(key, -1)
    	end)
    	ctx.requestPlayerData(true)
    	done(("Sent %d %s shop purchase%s"):format(#ids, name, #ids == 1 and "" or "s"))
    end
    
    
    ctx.isFxObj = function(o)
    	return o and (o:IsA("ParticleEmitter") or o:IsA("Beam") or o:IsA("Trail") or o:IsA("Fire") or o:IsA("Smoke") or o:IsA("Sparkles"))
    end
    
    ctx.feManagers = ctx.feManagers or {}
    ctx.feManagers.sideClip = ctx.feManagers.sideClip or {
    	original = setmetatable({}, { __mode = "k" }),
    	watches = setmetatable({}, { __mode = "k" }),
    }
    ctx.feManagers.firstPersonFx = ctx.feManagers.firstPersonFx or {
    	scriptOriginal = setmetatable({}, { __mode = "k" }),
    	fxOriginal = setmetatable({}, { __mode = "k" }),
    	fxWatches = setmetatable({}, { __mode = "k" }),
    }
    ctx.feManagers.rescue = ctx.feManagers.rescue or {
    	scriptOriginal = setmetatable({}, { __mode = "k" }),
    	original = setmetatable({}, { __mode = "k" }),
    	watches = setmetatable({}, { __mode = "k" }),
    	camera = nil,
    	cameraCons = {},
    }
    ctx.cache.feOptionChar = nil
    ctx.cache.feOptionCharCons = ctx.cache.feOptionCharCons or {}
    ctx.cache.feOptionStarted = ctx.cache.feOptionStarted or false
    
    ctx.feManagerSet = function(obj, prop, value)
    	if not obj then
    		return false
    	end
    	ctx.tmpSetOk = pcall(function()
    		if obj[prop] ~= value then
    			obj[prop] = value
    		end
    	end)
    	return ctx.tmpSetOk
    end
    
    ctx.currentZipState = function()
    	if ctx.cache.zipStateSource == "bindable" and ctx.cache.zipEventKnown then
    		return ctx.opt.zipActive == true
    	end
    	if ctx.cache.zipStateSource == "attribute" and LP then
    		local ok, value = pcall(function()
    			return LP:GetAttribute("Ziplining") == true
    		end)
    		if ok then
    			return value
    		end
    	end
    	ctx.tmpZipState = ctx.opt.zipActive == true
    	if LP then
    		pcall(function()
    			ctx.tmpZipState = ctx.tmpZipState or LP:GetAttribute("Ziplining") == true
    		end)
    	end
    	return ctx.tmpZipState == true
    end
    
    ctx.watchSideClipScript = function(scr)
    	if not (scr and scr:IsA("LocalScript")) or ctx.feManagers.sideClip.watches[scr] then
    		return
    	end
    	ctx.tmpCons = {}
    	ctx.feManagers.sideClip.watches[scr] = ctx.tmpCons
    	ctx.tmpCons[#ctx.tmpCons + 1] = scr:GetPropertyChangedSignal("Disabled"):Connect(function()
    		if ctx.opt.clipOn and scr.Parent and scr.Disabled ~= true then
    			ctx.feManagerSet(scr, "Disabled", true)
    		end
    	end)
    	ctx.tmpCons[#ctx.tmpCons + 1] = scr.ChildAdded:Connect(function(child)
    		if child.Name == "Ziplining" then
    			task.defer(ctx.patchSideClip)
    			task.defer(ctx.hookZipStop, scr.Parent)
    		end
    	end)
    	ctx.tmpCons[#ctx.tmpCons + 1] = scr.Destroying:Once(function()
    		ctx.clearCons(ctx.feManagers.sideClip.watches[scr])
    		ctx.feManagers.sideClip.watches[scr] = nil
    		ctx.feManagers.sideClip.original[scr] = nil
    	end)
    end
    
    ctx.patchSideClip = function()
    	ctx.tmpChar = ctx.chr(false)
    	ctx.tmpScript = ctx.tmpChar and ctx.tmpChar:FindFirstChild("CL_AntiSideClip")
    	if not (ctx.tmpScript and ctx.tmpScript:IsA("LocalScript")) then
    		return false
    	end
    	if ctx.feManagers.sideClip.original[ctx.tmpScript] == nil then
    		ctx.feManagers.sideClip.original[ctx.tmpScript] = ctx.tmpScript.Disabled
    	end
    	ctx.watchSideClipScript(ctx.tmpScript)
    	ctx.tmpBlock = ctx.opt.clipOn == true
    	ctx.feManagerSet(ctx.tmpScript, "Disabled", ctx.tmpBlock and true or ctx.feManagers.sideClip.original[ctx.tmpScript])
    	ctx.tmpZipEvent = ctx.tmpScript:FindFirstChild("Ziplining")
    	if ctx.tmpZipEvent and ctx.tmpZipEvent:IsA("BindableEvent") and not ctx.tmpBlock then
    		pcall(function()
    			ctx.tmpZipEvent:Fire(ctx.currentZipState())
    		end)
    	end
    	return true
    end
    
    ctx.watchFirstPersonFx = function(obj)
    	if not (ctx.isFxObj(obj) and obj.Parent) then
    		return
    	end
    	if ctx.feManagers.firstPersonFx.fxOriginal[obj] == nil then
    		ctx.feManagers.firstPersonFx.fxOriginal[obj] = obj.Enabled
    	end
    	if not ctx.feManagers.firstPersonFx.fxWatches[obj] then
    		ctx.tmpCons = {}
    		ctx.feManagers.firstPersonFx.fxWatches[obj] = ctx.tmpCons
    		ctx.tmpCons[#ctx.tmpCons + 1] = obj:GetPropertyChangedSignal("Enabled"):Connect(function()
    			if ctx.opt.fpPartOn and obj.Parent and obj.Enabled ~= true then
    				ctx.feManagerSet(obj, "Enabled", true)
    			end
    		end)
    		ctx.tmpCons[#ctx.tmpCons + 1] = obj.Destroying:Once(function()
    			ctx.clearCons(ctx.feManagers.firstPersonFx.fxWatches[obj])
    			ctx.feManagers.firstPersonFx.fxWatches[obj] = nil
    			ctx.feManagers.firstPersonFx.fxOriginal[obj] = nil
    		end)
    	end
    	if ctx.opt.fpPartOn then
    		ctx.feManagerSet(obj, "Enabled", true)
    	end
    end
    
    ctx.restoreFirstPersonFx = function()
    	for obj, original in ctx.feManagers.firstPersonFx.fxOriginal do
    		if obj and obj.Parent then
    			ctx.feManagerSet(obj, "Enabled", original)
    		end
    	end
    	for obj, cons in ctx.feManagers.firstPersonFx.fxWatches do
    		ctx.clearCons(cons)
    		ctx.feManagers.firstPersonFx.fxWatches[obj] = nil
    	end
    	ctx.feManagers.firstPersonFx.fxOriginal = setmetatable({}, { __mode = "k" })
    	ctx.feManagers.firstPersonFx.fxWatches = setmetatable({}, { __mode = "k" })
    	for scr, original in ctx.feManagers.firstPersonFx.scriptOriginal do
    		if scr and scr.Parent then
    			ctx.feManagerSet(scr, "Disabled", original)
    		end
    	end
    end
    
    ctx.patchFpParts = function()
    	ctx.tmpChar = ctx.chr(false)
    	if not ctx.tmpChar then
    		return false
    	end
    	ctx.tmpManager = ctx.tmpChar:FindFirstChild("CL_FirstPerson_ParticleManager")
    	if ctx.tmpManager and ctx.tmpManager:IsA("LocalScript") then
    		if ctx.feManagers.firstPersonFx.scriptOriginal[ctx.tmpManager] == nil then
    			ctx.feManagers.firstPersonFx.scriptOriginal[ctx.tmpManager] = ctx.tmpManager.Disabled
    		end
    		ctx.feManagerSet(ctx.tmpManager, "Disabled", ctx.opt.fpPartOn and true or ctx.feManagers.firstPersonFx.scriptOriginal[ctx.tmpManager])
    	end
    	if not ctx.opt.fpPartOn then
    		ctx.restoreFirstPersonFx()
    		return true
    	end
    	for _, obj in ctx.descOf(ctx.tmpChar) do
    		if ctx.isFxObj(obj) then
    			ctx.watchFirstPersonFx(obj)
    		end
    	end
    	return true
    end
    
    ctx.isRescueVisual = function(obj)
    	ctx.tmpCam = Wsp and Wsp.CurrentCamera
    	if not (obj and ctx.tmpCam and obj:IsDescendantOf(ctx.tmpCam)) then
    		return false
    	end
    	ctx.tmpParent = obj
    	while ctx.tmpParent and ctx.tmpParent ~= ctx.tmpCam do
    		if ctx.tmpParent:IsA("Model") and ctx.tmpParent.Name == "NPC" then
    			return true
    		end
    		ctx.tmpParent = ctx.tmpParent.Parent
    	end
    	return false
    end
    
    ctx.watchRescueObject = function(obj)
    	if not (ctx.opt.rescueOn and ctx.isRescueVisual(obj)) then
    		return
    	end
    	ctx.tmpProp = nil
    	ctx.tmpHidden = nil
    	if obj:IsA("BasePart") then
    		ctx.tmpProp = "LocalTransparencyModifier"
    		ctx.tmpHidden = 1
    	elseif ctx.isFxObj(obj) then
    		ctx.tmpProp = "Enabled"
    		ctx.tmpHidden = false
    	end
    	if not ctx.tmpProp then
    		return
    	end
    	if ctx.feManagers.rescue.original[obj] == nil then
    		ctx.feManagers.rescue.original[obj] = {
    			property = ctx.tmpProp,
    			value = obj[ctx.tmpProp],
    		}
    	end
    	if not ctx.feManagers.rescue.watches[obj] then
    		ctx.tmpCons = {}
    		ctx.feManagers.rescue.watches[obj] = ctx.tmpCons
    		local watchProp = ctx.tmpProp
    		local watchValue = ctx.tmpHidden
    		ctx.tmpCons[#ctx.tmpCons + 1] = obj:GetPropertyChangedSignal(watchProp):Connect(function()
    			if ctx.opt.rescueOn and obj.Parent and ctx.isRescueVisual(obj) and obj[watchProp] ~= watchValue then
    				ctx.feManagerSet(obj, watchProp, watchValue)
    			end
    		end)
    		ctx.tmpCons[#ctx.tmpCons + 1] = obj.Destroying:Once(function()
    			ctx.clearCons(ctx.feManagers.rescue.watches[obj])
    			ctx.feManagers.rescue.watches[obj] = nil
    			ctx.feManagers.rescue.original[obj] = nil
    		end)
    	end
    	ctx.feManagerSet(obj, ctx.tmpProp, ctx.tmpHidden)
    end
    
    ctx.restoreRescueVisuals = function()
    	for scr, original in ctx.feManagers.rescue.scriptOriginal do
    		if scr and scr.Parent then
    			ctx.feManagerSet(scr, "Disabled", original)
    		end
    	end
    	for obj, snapshot in ctx.feManagers.rescue.original do
    		if obj and obj.Parent and type(snapshot) == "table" then
    			ctx.feManagerSet(obj, snapshot.property, snapshot.value)
    		end
    	end
    	for obj, cons in ctx.feManagers.rescue.watches do
    		ctx.clearCons(cons)
    		ctx.feManagers.rescue.watches[obj] = nil
    	end
    	ctx.feManagers.rescue.scriptOriginal = setmetatable({}, { __mode = "k" })
    	ctx.feManagers.rescue.original = setmetatable({}, { __mode = "k" })
    	ctx.feManagers.rescue.watches = setmetatable({}, { __mode = "k" })
    end
    
    ctx.patchRescueScript = function()
    	ctx.tmpChar = ctx.chr(false)
    	ctx.tmpScript = ctx.tmpChar and ctx.tmpChar:FindFirstChild("CL_RescueVisual")
    	if not (ctx.tmpScript and ctx.tmpScript:IsA("LocalScript")) then
    		return false
    	end
    	if ctx.feManagers.rescue.scriptOriginal[ctx.tmpScript] == nil then
    		ctx.feManagers.rescue.scriptOriginal[ctx.tmpScript] = ctx.tmpScript.Disabled
    	end
    	ctx.feManagerSet(ctx.tmpScript, "Disabled", ctx.opt.rescueOn and true or ctx.feManagers.rescue.scriptOriginal[ctx.tmpScript])
    	return true
    end
    
    ctx.bindRescueCamera = function()
    	ctx.clearCons(ctx.feManagers.rescue.cameraCons)
    	ctx.feManagers.rescue.camera = Wsp and Wsp.CurrentCamera or nil
    	ctx.tmpCam = ctx.feManagers.rescue.camera
    	if not ctx.tmpCam then
    		return
    	end
    	ctx.feManagers.rescue.cameraCons[#ctx.feManagers.rescue.cameraCons + 1] = ctx.tmpCam.DescendantAdded:Connect(function(obj)
    		if ctx.opt.rescueOn then
    			task.defer(ctx.watchRescueObject, obj)
    		end
    	end)
    	if ctx.opt.rescueOn then
    		for _, obj in ctx.descOf(ctx.tmpCam) do
    			ctx.watchRescueObject(obj)
    		end
    	end
    end
    
    ctx.patchRescue = function()
    	ctx.patchRescueScript()
    	if not ctx.opt.rescueOn then
    		ctx.restoreRescueVisuals()
    		return true
    	end
    	if ctx.feManagers.rescue.camera ~= (Wsp and Wsp.CurrentCamera) then
    		ctx.bindRescueCamera()
    	end
    	ctx.tmpCam = Wsp and Wsp.CurrentCamera
    	if not ctx.tmpCam then
    		return false
    	end
    	for _, obj in ctx.descOf(ctx.tmpCam) do
    		ctx.watchRescueObject(obj)
    	end
    	return true
    end
    
    ctx.bindFeOptionCharacter = function(char)
    	ctx.clearCons(ctx.cache.feOptionCharCons)
    	ctx.cache.feOptionChar = char
    	if not char then
    		return
    	end
    	ctx.cache.feOptionCharCons[#ctx.cache.feOptionCharCons + 1] = char.ChildAdded:Connect(function(child)
    		if child.Name == "CL_AntiSideClip" then
    			task.defer(ctx.patchSideClip)
    		elseif child.Name == "CL_FirstPerson_ParticleManager" then
    			task.defer(ctx.patchFpParts)
    		elseif child.Name == "CL_RescueVisual" then
    			task.defer(ctx.patchRescue)
    		end
    	end)
    	ctx.cache.feOptionCharCons[#ctx.cache.feOptionCharCons + 1] = char.DescendantAdded:Connect(function(obj)
    		if ctx.opt.fpPartOn and ctx.isFxObj(obj) then
    			task.defer(ctx.watchFirstPersonFx, obj)
    		end
    	end)
    	task.defer(ctx.patchSideClip)
    	task.defer(ctx.patchFpParts)
    	task.defer(ctx.patchRescue)
    end
    
    ctx.startFeOptionManagers = function()
    	if ctx.cache.feOptionStarted then
    		return
    	end
    	ctx.cache.feOptionStarted = true
    	if LP then
    		ctx.bind(LP.CharacterAdded:Connect(function(char)
    			task.defer(ctx.bindFeOptionCharacter, char)
    		end))
    	end
    	if Wsp then
    		ctx.bind(Wsp:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
    			task.defer(ctx.bindRescueCamera)
    		end))
    	end
    	ctx.bindFeOptionCharacter(LP and LP.Character or nil)
    	ctx.bindRescueCamera()
    	ctx.patchRescue()
    end
    
    ctx.restoreFeOptionManagers = function()
    	ctx.opt.clipOn = false
    	ctx.opt.fpPartOn = false
    	ctx.opt.rescueOn = false
    	ctx.patchSideClip()
    	for scr, cons in ctx.feManagers.sideClip.watches do
    		ctx.clearCons(cons)
    		ctx.feManagers.sideClip.watches[scr] = nil
    	end
    	ctx.feManagers.sideClip.original = setmetatable({}, { __mode = "k" })
    	ctx.feManagers.sideClip.watches = setmetatable({}, { __mode = "k" })
    	ctx.restoreFirstPersonFx()
    	ctx.feManagers.firstPersonFx.scriptOriginal = setmetatable({}, { __mode = "k" })
    	ctx.restoreRescueVisuals()
    	ctx.clearCons(ctx.cache.feOptionCharCons)
    	ctx.clearCons(ctx.feManagers.rescue.cameraCons)
    end
    
    ctx.setDevTools = function(st)
    	ctx.opt.devOn = st and true or false
    	ctx.opt.infAirOn = ctx.opt.devOn
    	ctx.opt.infJumpOn = ctx.opt.devOn
    	ctx.opt.clickTpOn = ctx.opt.devOn
    	local main = LP and LP:FindFirstChild("PlayerScripts") and LP.PlayerScripts:FindFirstChild("CL_MAIN_GameScript")
    	local god = main and main:FindFirstChild("GodMode")
    	if god and god.Fire then
    		pcall(function()
    			god:Fire(ctx.opt.devOn)
    		end)
    	end
    	if ctx.opt.infAirOn then
    		ctx.keepAirFast()
    	else
    		ctx.unprotectAirHealth()
    	end
    	ctx.setDevBtn()
    	ctx.setInfAirBtn()
    	ctx.setInfJumpBtn()
    	ctx.setClickTpBtn()
    end
    
    
    ctx.patchPaidUi = function()
    	if not ctx.opt.paidOn then
    		return
    	end
    	local pg = ctx.pg()
    	if not pg then
    		return
    	end
    	if ctx.support("flood") then
    		ctx.floodUi()
    	end
    	local roots = {
    		pg:FindFirstChild("MenuGui"),
    		pg:FindFirstChild("GameGui"),
    		pg:FindFirstChild("DailyChallengeGui"),
    	}
    	local lob = Wsp and Wsp:FindFirstChild("Lobby")
    	if lob then
    		roots[#roots + 1] = lob:FindFirstChild("ProductWindows")
    	end
    	for _, root in roots do
    		ctx.uiEach(root, function(o)
    			if o.Name == "PurchaseGamepass" or o.Name == "PremiumOnly" or o.Name == "LockedFrame" then
    				ctx.uiHide(o)
    			elseif o:IsA("GuiButton") then
    				ctx.uiSet(o, "Active", true)
    				ctx.uiSet(o, "AutoButtonColor", true)
    			elseif o:IsA("TextLabel") or o:IsA("TextButton") then
    				local tx = tostring(o.Text or "")
    				if string.find(tx, "Unlock") then
    					ctx.uiSet(o, "Text", (string.gsub(tx, "Unlock & ", "")))
    				elseif string.find(tx, "Premium Only") then
    					ctx.uiSet(o, "Visible", false)
    				end
    			end
    		end)
    	end
    end
    
    
    ctx.mainScript = function()
    	local ps = LP and LP:FindFirstChild("PlayerScripts")
    	return ps and ps:FindFirstChild("CL_MAIN_GameScript") or nil
    end
    
    ctx.partWords = function(p, words)
    	if not p then
    		return false
    	end
    	ctx.tmpName = string.lower((p.Name or "") .. " " .. (p.Parent and p.Parent.Name or ""))
    	for _, w in words do
    		if string.find(ctx.tmpName, w, 1, true) then
    			return true
    		end
    	end
    	return false
    end
    
    ctx.nearNamedPart = function(r, words, dist)
    	if not (Wsp and r) then
    		return false
    	end
    	ctx.tmpParts = nil
    	pcall(function()
    		ctx.tmpParts = Wsp:GetPartBoundsInRadius(r.Position, dist or 8)
    	end)
    	if type(ctx.tmpParts) == "table" then
    		for _, p in ctx.tmpParts do
    			if p and p:IsA("BasePart") then
    				if table.find(words, "truss") and p:IsA("TrussPart") then
    					return true
    				end
    				if ctx.partWords(p, words) then
    					return true
    				end
    			end
    		end
    	end
    	ctx.tmpMap = ctx.curMap() or MP
    	if ctx.tmpMap then
    		for _, p in ctx.descOf(ctx.tmpMap) do
    			if p and p:IsA("BasePart") then
    				if table.find(words, "truss") and p:IsA("TrussPart") and (r.Position - p.Position).Magnitude <= (dist or 8) then
    					return true
    				end
    				if ctx.partWords(p, words) and (r.Position - p.Position).Magnitude <= (dist or 8) then
    					return true
    				end
    			end
    		end
    	end
    	return false
    end
    
    ctx.nearWalljump = function(r)
    	if not r then
    		return nil
    	end
    	ctx.tmpBestWall = nil
    	ctx.tmpBestWallDist = 9
    	ctx.tmpMap = ctx.curMap()
    	if ctx.tmpMap then
    		ctx.ensureChallenges(ctx.tmpMap)
    		ctx.tmpHits = ctx.challengeHits(ctx.tmpMap)
    		for _, wall in ctx.tmpHits.wall do
    			if wall and wall.Parent then
    				ctx.tmpDist = (r.Position - wall.Position).Magnitude
    				if ctx.tmpDist < ctx.tmpBestWallDist then
    					ctx.tmpBestWall = wall
    					ctx.tmpBestWallDist = ctx.tmpDist
    				end
    			end
    		end
    	end
    	ctx.tmpRoots = { ctx.tmpMap, MP }
    	for _, root in ctx.tmpRoots do
    		if root then
    			for _, p in ctx.descOf(root) do
    				if p and p:IsA("BasePart") and ((p:FindFirstChild("_Wall") ~= nil) or ctx.partWords(p, { "walljump", "wall_jump", "_wall" })) then
    					ctx.tmpDist = (r.Position - p.Position).Magnitude
    					if ctx.tmpDist < ctx.tmpBestWallDist then
    						ctx.tmpBestWall = p
    						ctx.tmpBestWallDist = ctx.tmpDist
    					end
    				end
    			end
    		end
    	end
    	if ctx.tmpBestWall then
    		ctx.tmpPos, ctx.tmpNorm = ctx.wallData(ctx.tmpBestWall, r, ctx.chr(false))
    		return ctx.tmpBestWall, ctx.tmpNorm
    	end
    	return nil
    end
    
    ctx.climbJump = function(lvl)
    	ctx.tmpRoot, ctx.tmpHum = ctx.rh(false)
    	if not (ctx.tmpRoot and ctx.tmpHum) then
    		return false
    	end
    	ctx.tmpOldState = ctx.tmpHum:GetState()
    	if ctx.tmpOldState ~= Enum.HumanoidStateType.Climbing then
    		return false
    	end
    	ctx.tmpPow = lvl == 1 and 6 or lvl == 2 and 11 or 16
    	ctx.tmpFwd = lvl == 1 and 4 or lvl == 2 and 7 or 10
    	pcall(function()
    		ctx.tmpHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    		ctx.tmpHum.Jump = true
    		ctx.tmpHum:ChangeState(Enum.HumanoidStateType.Jumping)
    	end)
    	if ctx.feCall("AccurateJump", true) ~= true then
    		ctx.callScriptGlobal(ctx.feEnv(), "AccurateJump", true)
    	end
    	pcall(function()
    		ctx.tmpVel = ctx.tmpRoot.AssemblyLinearVelocity
    		ctx.tmpLoc = ctx.tmpRoot.CFrame:VectorToObjectSpace(ctx.tmpVel)
    		ctx.tmpLoc = Vector3.new(ctx.tmpLoc.X, ctx.tmpLoc.Y + ctx.tmpPow, ctx.tmpLoc.Z + ctx.tmpFwd)
    		ctx.tmpVel = ctx.tmpRoot.CFrame:VectorToWorldSpace(ctx.tmpLoc)
    		ctx.tmpRoot.Velocity = ctx.tmpVel
    		ctx.tmpRoot.AssemblyLinearVelocity = ctx.tmpVel
    	end)
    	return true
    end
    
    ctx.jumpRoot = function(pow, fwd, climb)
    	ctx.tmpRoot, ctx.tmpHum = ctx.rh(false)
    	if not (ctx.tmpRoot and ctx.tmpHum) then
    		return false
    	end
    	if climb then
    		return false
    	end
    	ctx.tmpVel = ctx.tmpRoot.AssemblyLinearVelocity
    	pcall(function()
    		ctx.tmpHum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    		ctx.tmpHum.Jump = true
    		ctx.tmpHum:ChangeState(Enum.HumanoidStateType.Jumping)
    		ctx.tmpRoot.Velocity = Vector3.new(ctx.tmpVel.X, math.max(ctx.tmpVel.Y, pow), ctx.tmpVel.Z)
    		ctx.tmpRoot.AssemblyLinearVelocity = ctx.tmpRoot.Velocity
    	end)
    	return true
    end
    
    ctx.doJumpBoost = function()
    	ctx.tmpRoot, ctx.tmpHum = ctx.rh(false)
    	if not (ctx.tmpHum and ctx.tmpRoot) then
    		return
    	end
    	ctx.tmpState = ctx.tmpHum:GetState()
    	if ctx.opt.infJumpOn then
    		ctx.jumpRoot(52, 0, false)
    	end
    end
    
    ctx.clickTeleportTo = function(pos)
    	if typeof(pos) ~= "Vector3" then
    		return false
    	end
    	ctx.tmpRoot = select(1, ctx.rh(false))
    	if not (ctx.tmpRoot and ctx.tmpRoot.Parent) then
    		return false
    	end
    	ctx.tmpRx, ctx.tmpRy, ctx.tmpRz = ctx.tmpRoot.CFrame:ToEulerAnglesXYZ()
    	pcall(function()
    		ctx.pivotRootTo(CFrame.new(pos + Vector3.new(0, 2.5, 0)) * CFrame.fromEulerAnglesXYZ(ctx.tmpRx, ctx.tmpRy, ctx.tmpRz), ctx.tmpRoot)
    	end)
    	return true
    end
    
    ctx.touchClickTeleport = function(points, processed)
    	if processed or not ctx.opt.clickTpOn then
    		return
    	end
    	ctx.tmpPoint = type(points) == "table" and points[1] or nil
    	if typeof(ctx.tmpPoint) ~= "Vector2" then
    		return
    	end
    	ctx.tmpCam = Wsp and Wsp.CurrentCamera
    	if not ctx.tmpCam then
    		return
    	end
    	ctx.tmpRay = ctx.tmpCam:ViewportPointToRay(ctx.tmpPoint.X, ctx.tmpPoint.Y)
    	ctx.tmpParams = RaycastParams.new()
    	ctx.tmpParams.FilterType = Enum.RaycastFilterType.Exclude
    	ctx.tmpChar = ctx.chr(false)
    	ctx.tmpParams.FilterDescendantsInstances = ctx.tmpChar and { ctx.tmpChar } or {}
    	ctx.tmpHit = Wsp:Raycast(ctx.tmpRay.Origin, ctx.tmpRay.Direction * 1000, ctx.tmpParams)
    	if ctx.tmpHit then
    		ctx.clickTeleportTo(ctx.tmpHit.Position)
    	end
    end
    
    
    ctx.remoteRoot = function()
    	return Rsp and Rsp:FindFirstChild("Remote") or nil
    end
    
    ctx.remotePath = function(...)
    	ctx.tmpNode = ctx.remoteRoot()
    	for _, nm in { ... } do
    		ctx.tmpNode = ctx.tmpNode and ctx.tmpNode:FindFirstChild(nm)
    	end
    	return ctx.tmpNode
    end
    
    ctx.fireRemote = function(rem, ...)
    	if not (rem and rem.FireServer) then
    		return false
    	end
    	return pcall(function(...)
    		rem:FireServer(...)
    	end, ...)
    end
    
    ctx.fireRegenAir = function(force)
    	local now = os.clock()
    	if force ~= true and now < (ctx.cache.airRemoteAt or 0) then
    		return true
    	end
    	ctx.cache.airRemoteAt = now + 1
    	if not (ctx.cache.airRegenRemote and ctx.cache.airRegenRemote.Parent) then
    		local list = ChallengeRemotes.RegeneratedAir
    		if type(list) == "table" then
    			for _, rem in list do
    				if rem and rem.Parent then
    					ctx.cache.airRegenRemote = rem
    					break
    				end
    			end
    		end
    		if not (ctx.cache.airRegenRemote and ctx.cache.airRegenRemote.Parent) then
    			ctx.cache.airRegenRemote = ctx.remotePath("Challenges", "RegeneratedAir") or ctx.findRemoteNamed("RegeneratedAir")
    			ctx.addRemoteOnce(list, ctx.cache.airRegenRemote)
    		end
    	end
    	ctx.tmpRem = ctx.cache.airRegenRemote
    	ctx.tmpOk = ctx.fireRemote(ctx.tmpRem, 9999)
    	ctx.tmpOk = ctx.fireRemote(ctx.tmpRem, 300) or ctx.tmpOk
    	ctx.tmpOk = ctx.fireRemote(ctx.tmpRem) or ctx.tmpOk
    	return ctx.tmpOk
    end
    
    ctx.keepAirLocal = function()
    	ctx.tmpAirEnv = ctx.cache.airEnv or ctx.gameEnv()
    	if ctx.tmpAirEnv then
    		ctx.cache.airEnv = ctx.tmpAirEnv
    	end
    	ctx.callAirFns(ctx.tmpAirEnv)
    	local now = os.clock()
    	if now >= (ctx.cache.airLocalAt or 0) then
    		ctx.cache.airLocalAt = now + 0.75
    		ctx.tmpPg = ctx.pg()
    		ctx.tmpAir = ctx.tmpPg and ctx.tmpPg:FindFirstChild("Air", true)
    		ctx.tmpCnt = ctx.tmpAir and ctx.tmpAir:FindFirstChild("Count", true)
    		if ctx.tmpCnt and (ctx.tmpCnt:IsA("TextLabel") or ctx.tmpCnt:IsA("TextButton")) then
    			pcall(function()
    				ctx.tmpCnt.Text = "∞"
    				ctx.tmpCnt.TextColor3 = Color3.new(1, 1, 1)
    			end)
    		end
    	end
    end
    
    ctx.airHpValue = function(h)
    	ctx.tmpHp = 100
    	if h then
    		pcall(function()
    			ctx.tmpHp = math.max(100, h.MaxHealth)
    		end)
    	end
    	return ctx.tmpHp
    end
    
    ctx.resetAirHealth = function(h)
    	if not h then
    		return
    	end
    	pcall(function()
    		if ctx.live and ctx.opt.infAirOn and h.Health <= math.max(1, h.MaxHealth * 0.2) then
    			h.Health = ctx.airHpValue(h)
    		end
    	end)
    end
    
    ctx.airBlockAlert = function(env)
    	if type(env) ~= "table" then
    		return
    	end
    	if ctx.cache.airAlertEnv ~= env then
    		if ctx.cache.airAlertEnv and ctx.cache.airAlertOld then
    			pcall(function()
    				ctx.cache.airAlertEnv.newAlert = ctx.cache.airAlertOld
    			end)
    		end
    		ctx.cache.airAlertEnv = env
    		ctx.cache.airAlertOld = type(env.newAlert) == "function" and env.newAlert or nil
    	end
    	if type(ctx.cache.airAlertOld) ~= "function" then
    		return
    	end
    	if env.newAlert ~= ctx.cache.airAlertWrap then
    		ctx.cache.airAlertWrap = function(msg, ...)
    			if ctx.live and ctx.opt.infAirOn and type(msg) == "string" and (msg:find("Drowned") or msg:find("drowned") or msg:find("lava") or msg:find("Lava")) then
    				return
    			end
    			return ctx.cache.airAlertOld(msg, ...)
    		end
    		pcall(function()
    			env.newAlert = ctx.cache.airAlertWrap
    		end)
    	end
    end
    
    ctx.unblockAirAlert = function()
    	if ctx.cache.airAlertEnv and ctx.cache.airAlertOld then
    		pcall(function()
    			ctx.cache.airAlertEnv.newAlert = ctx.cache.airAlertOld
    		end)
    	end
    	ctx.cache.airAlertEnv = nil
    	ctx.cache.airAlertOld = nil
    	ctx.cache.airAlertWrap = nil
    end
    
    ctx.protectAirHealth = function()
    	ctx.tmpRoot, ctx.tmpHum = ctx.rh(false)
    	if not ctx.tmpHum then
    		return
    	end
    	ctx.cache.airHum = ctx.tmpHum
    	if ctx.cache.airHealthHum ~= ctx.tmpHum then
    		ctx.cut(ctx.cache.airHealthConn)
    		ctx.cut(ctx.cache.airDiedConn)
    		ctx.cache.airHealthHum = ctx.tmpHum
    		ctx.cache.airHealthConn = ctx.tmpHum:GetPropertyChangedSignal("Health"):Connect(function()
    			ctx.resetAirHealth(ctx.cache.airHealthHum)
    		end)
    		ctx.cache.airDiedConn = ctx.tmpHum.Died:Connect(function()
    			if ctx.live and ctx.opt.infAirOn then
    				ctx.resetAirHealth(ctx.cache.airHealthHum)
    			end
    		end)
    	end
    	pcall(function()
    		ctx.tmpHum.BreakJointsOnDeath = false
    	end)
    	pcall(function()
    		ctx.tmpHum.RequiresNeck = false
    	end)
    	pcall(function()
    		ctx.tmpHum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
    	end)
    	pcall(function()
    		if ctx.tmpHum.Health <= math.max(1, ctx.tmpHum.MaxHealth * 0.2) then
    			ctx.tmpHum.Health = ctx.airHpValue(ctx.tmpHum)
    		end
    	end)
    end
    
    ctx.unprotectAirHealth = function()
    	ctx.tmpRoot, ctx.tmpHum = ctx.rh(false)
    	ctx.cut(ctx.cache.airHealthConn)
    	ctx.cut(ctx.cache.airDiedConn)
    	ctx.cache.airHealthConn = nil
    	ctx.cache.airDiedConn = nil
    	ctx.cache.airHealthHum = nil
    	ctx.cache.airHum = nil
    	if ctx.tmpHum then
    		pcall(function()
    			ctx.tmpHum:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
    		end)
    	end
    	ctx.unblockAirAlert()
    	ctx.cache.airFnEnv = nil
    	ctx.cache.airTakeFn = nil
    	ctx.cache.airSwitchFn = nil
    end
    
    ctx.refreshAirFns = function(env)
    	if ctx.cache.airFnEnv == env then
    		return
    	end
    	ctx.cache.airFnEnv = env
    	ctx.cache.airTakeFn = type(env) == "table" and ctx.scriptGlobal(env, "takeAir") or nil
    	ctx.cache.airSwitchFn = type(env) == "table" and ctx.scriptGlobal(env, "switchAir") or nil
    end
    
    ctx.callAirFns = function(env)
    	ctx.refreshAirFns(env)
    	if type(ctx.cache.airTakeFn) == "function" then
    		pcall(ctx.cache.airTakeFn, -9999)
    	end
    	if type(ctx.cache.airSwitchFn) == "function" then
    		pcall(ctx.cache.airSwitchFn, "tank", true)
    	end
    end
    
    ctx.keepAirFast = function()
    	local now = os.clock()
    	if now >= (ctx.cache.airProtectAt or 0) then
    		ctx.cache.airProtectAt = now + 0.75
    		ctx.protectAirHealth()
    	end
    	ctx.tmpAirEnv = ctx.cache.airEnv or ctx.gameEnv()
    	if ctx.tmpAirEnv then
    		ctx.cache.airEnv = ctx.tmpAirEnv
    		ctx.airBlockAlert(ctx.tmpAirEnv)
    	end
    	ctx.callAirFns(ctx.tmpAirEnv)
    	ctx.fireRegenAir()
    	if now >= (ctx.cache.airLocalAt or 0) then
    		ctx.keepAirLocal()
    	end
    end
    
    ctx.fireGod = function(st)
    	ctx.tmpMain = ctx.mainScript()
    	ctx.tmpGod = ctx.tmpMain and ctx.tmpMain:FindFirstChild("GodMode")
    	if ctx.tmpGod and ctx.tmpGod.Fire then
    		pcall(function()
    			ctx.tmpGod:Fire(st == true)
    		end)
    	end
    	if st == true then
    		ctx.keepAirLocal()
    		ctx.fireRegenAir(true)
    	end
    end
    
    ctx.femLocatorHit = function()
    	ctx.tmpPg = ctx.pg()
    	ctx.tmpLoc = ctx.tmpPg and ctx.tmpPg:FindFirstChild("Locator", true)
    	ctx.tmpView = ctx.tmpLoc and ctx.tmpLoc:FindFirstChild("LocatorViewport", true)
    	ctx.tmpBall = ctx.tmpView and ctx.tmpView:FindFirstChild("Ball")
    	if ctx.tmpBall and ctx.tmpBall:IsA("BasePart") then
    		return ctx.tmpBall
    	end
    	return nil
    end
    
    ctx.fireNextButton = function()
    	ctx.tmpMap = ctx.curMap()
    	ctx.tmpRoot = select(1, ctx.rh(false))
    	if ctx.isFEMGame() then
    		ctx.tmpHit = ctx.femLocatorHit()
    		if ctx.tmpHit and ctx.tmpHit.Parent then
    			if ctx.tmpRoot and ctx.tmpRoot.Parent then
    				pcall(function()
    					ctx.pivotRootTo(ctx.tmpHit.CFrame + Vector3.new(0, 3, 0), ctx.tmpRoot)
    					ctx.tmpRoot.AssemblyLinearVelocity = Vector3.zero
    				end)
    				task.wait(0.08)
    			end
    			ctx.cache.muteNotifyUntil = os.clock() + 1.5
    			ctx.pressMapButton(ctx.tmpHit)
    			return true
    		end
    	end
    	ctx.tmpEntries = {}
    	if ctx.tmpMap then
    		ctx.tmpRawEntries = ctx.auraEntries(ctx.tmpMap) or {}
    		ctx.mergeLocatorBtns(ctx.tmpRawEntries, ctx.tmpMap)
    		if #ctx.tmpRawEntries <= 0 then
    			ctx.tmpOk, ctx.tmpRes = pcall(ctx.scanBtns, ctx.tmpMap)
    			if ctx.tmpOk and type(ctx.tmpRes) == "table" then
    				ctx.tmpRawEntries = ctx.tmpRes
    			end
    		end
    		for _, entry in ctx.tmpRawEntries do
    			if ctx.entryReady(entry, ctx.tmpMap) then
    				ctx.tmpEntries[#ctx.tmpEntries + 1] = entry
    			end
    		end
    		if #ctx.tmpEntries <= 0 then
    			ctx.tmpExit = ctx.mapExit(ctx.tmpMap)
    			if ctx.tmpExit and (ctx.buttonsDone() or (not ctx.isFE2CMGame() and #ctx.tmpRawEntries > 0)) and ctx.tmpRoot and ctx.tmpRoot.Parent then
    				pcall(function()
    					ctx.pivotRootTo(ctx.tmpExit.CFrame, ctx.tmpRoot)
    					ctx.tmpRoot.AssemblyLinearVelocity = Vector3.zero
    				end)
    				return true
    			end
    		end
    	end
    	ctx.tmpEntry = ctx.nearestEntry(ctx.tmpEntries, ctx.tmpRoot and ctx.tmpRoot.Position)
    	ctx.tmpHit = ctx.tmpEntry and ctx.tmpEntry.hit
    	if ctx.tmpHit and ctx.tmpHit.Parent then
    		if ctx.tmpRoot and ctx.tmpRoot.Parent then
    			pcall(function()
    				ctx.pivotRootTo(ctx.tmpHit.CFrame + Vector3.new(0, 3, 0), ctx.tmpRoot)
    				ctx.tmpRoot.AssemblyLinearVelocity = Vector3.zero
    			end)
    			task.wait(0.08)
    			if __exec.firetouchinterest ~= nil then
    				pcall(__exec.firetouchinterest, ctx.tmpRoot, ctx.tmpHit, 0)
    				pcall(__exec.firetouchinterest, ctx.tmpRoot, ctx.tmpHit, 1)
    			end
    		end
    		ctx.cache.muteNotifyUntil = os.clock() + 1.5
    		ctx.pressMapButton(ctx.tmpHit)
    		return true
    	end
    	ctx.note("No map button found")
    	return false
    end
    
    ctx.fireTestRemote = function(nm)
    	if nm == "NextButton" then
    		return ctx.fireNextButton()
    	end
    	ctx.tmpEv = ctx.findRemoteNamed(nm)
    	if not (ctx.tmpEv and ctx.tmpEv.FireServer) then
    		ctx.note(tostring(nm) .. " remote not found")
    		return false
    	end
    	return ctx.fireRemote(ctx.tmpEv)
    end
    
    
    ctx.safeParent = function(o)
    	ctx.tmpOk, ctx.tmpPar = pcall(function()
    		return o and o.Parent
    	end)
    	if ctx.tmpOk then
    		return ctx.tmpPar
    	end
    	return nil
    end
    
    ctx.zipTarget = function(o)
    	if not (o and typeof(o) == "Instance") then
    		return false
    	end
    	ctx.tmpZipPar = ctx.safeParent(o)
    	ctx.tmpZipName = string.lower((o.Name or "") .. " " .. (ctx.tmpZipPar and ctx.tmpZipPar.Name or ""))
    	return string.find(ctx.tmpZipName, "zip", 1, true)
    		or string.find(ctx.tmpZipName, "rope", 1, true)
    		or o:GetAttribute("RopeSpeed") ~= nil
    		or o:GetAttribute("ZiplineSpeed") ~= nil
    		or o:GetAttribute("VelocityInheritance") ~= nil
    end
    
    ctx.zipPatchOne = function(o, st)
    	if not (o and typeof(o) == "Instance") then
    		return
    	end
    	if ctx.cache.zipOld[o] == nil then
    		ctx.cache.zipOld[o] = {
    			o:GetAttribute("RopeSpeed"),
    			o:GetAttribute("ZiplineSpeed"),
    			o:GetAttribute("Speed"),
    			o:GetAttribute("VelocityInheritance"),
    		}
    	end
    	pcall(function()
    		if st and ctx.opt.zipSpeed > 0 then
    			o:SetAttribute("RopeSpeed", ctx.opt.zipSpeed)
    			o:SetAttribute("ZiplineSpeed", ctx.opt.zipSpeed)
    			o:SetAttribute("Speed", ctx.opt.zipSpeed)
    		elseif ctx.cache.zipOld[o] then
    			o:SetAttribute("RopeSpeed", ctx.cache.zipOld[o][1])
    			o:SetAttribute("ZiplineSpeed", ctx.cache.zipOld[o][2])
    			o:SetAttribute("Speed", ctx.cache.zipOld[o][3])
    		end
    	end)
    end
    
    ctx.watchZipRoot = function(root)
    	if not (root and typeof(root) == "Instance") or ctx.cache.zipWatches[root] then
    		return
    	end
    	ctx.cache.zipWatches[root] = true
    	if root.DescendantAdded then
    		ctx.bind(root.DescendantAdded:Connect(function(o)
    			if not (ctx.alive() and ctx.opt.zipFastOn and ctx.opt.zipAutoOn) then
    				return
    			end
    			task.defer(function()
    				if not (ctx.alive() and ctx.opt.zipFastOn and ctx.opt.zipAutoOn) then
    					return
    				end
    				if ctx.zipTarget(o) then
    					ctx.zipPatchOne(o, true)
    				end
    				ctx.tmpZipPar = ctx.safeParent(o)
    				if ctx.tmpZipPar and ctx.zipTarget(ctx.tmpZipPar) then
    					ctx.zipPatchOne(ctx.tmpZipPar, true)
    				end
    			end)
    		end))
    	end
    end
    
    ctx.setZipAttrs = function(st)
    	ctx.tmpMap = ctx.curMap()
    	ctx.tmpZipRoots = {}
    	if ctx.tmpMap then
    		ctx.tmpZipRoots[#ctx.tmpZipRoots + 1] = ctx.tmpMap
    	end
    	if MP then
    		ctx.tmpZipRoots[#ctx.tmpZipRoots + 1] = MP
    	end
    	for _, root in ctx.tmpZipRoots do
    		ctx.watchZipRoot(root)
    		for _, o in ctx.descOf(root) do
    			if ctx.zipTarget(o) then
    				ctx.zipPatchOne(o, st)
    			end
    			ctx.tmpZipPar = ctx.safeParent(o)
    			if ctx.tmpZipPar and ctx.zipTarget(ctx.tmpZipPar) then
    				ctx.zipPatchOne(ctx.tmpZipPar, st)
    			end
    		end
    	end
    end
    
    ctx.reapplyZipSpeed = function()
    	if not (ctx.opt.zipFastOn and ctx.opt.zipAutoOn) then
    		return
    	end
    	ctx.setZipAttrs(true)
    end
    
    ctx.resetZipVelocity = function()
    	ctx.tmpRoot = select(1, ctx.rh(false))
    	if not ctx.tmpRoot then
    		return
    	end
    	pcall(function()
    		local velocity = ctx.tmpRoot.AssemblyLinearVelocity
    		ctx.tmpRoot.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
    	end)
    end
    
    ctx.zipGroundClearance = function(character, root, humanoid)
    	local clearance = math.max(root.Size.Y * 0.5 + humanoid.HipHeight, root.Size.Y * 0.5)
    	if humanoid.RigType == Enum.HumanoidRigType.R6 then
    		local legHeight = 0
    		for _, name in { "Left Leg", "Right Leg" } do
    			local leg = character:FindFirstChild(name)
    			if leg and leg:IsA("BasePart") then
    				legHeight = math.max(legHeight, leg.Size.Y)
    			end
    		end
    		clearance += legHeight
    	end
    	return math.max(clearance, 2.5)
    end
    
    ctx.isZipMover = function(obj)
    	return obj and (obj:IsA("BodyPosition")
    		or obj:IsA("BodyVelocity")
    		or obj:IsA("BodyGyro")
    		or obj:IsA("LinearVelocity")
    		or obj:IsA("AlignPosition")
    		or obj:IsA("AlignOrientation"))
    end
    
    ctx.captureZipMovers = function(root)
    	ctx.cache.zipMoverBaseline = setmetatable({}, { __mode = "k" })
    	if not root then
    		return
    	end
    	for _, obj in root:GetChildren() do
    		if ctx.isZipMover(obj) then
    			ctx.cache.zipMoverBaseline[obj] = true
    		end
    	end
    end
    
    ctx.clearZipMovers = function(root)
    	if not root then
    		return
    	end
    	for _, obj in root:GetChildren() do
    		if ctx.isZipMover(obj) and not ctx.cache.zipMoverBaseline[obj] then
    			pcall(function()
    				obj:Destroy()
    			end)
    		end
    	end
    end
    
    ctx.setMainVelocityEnabled = function(enabled)
    	local main = ctx.mainScript and ctx.mainScript() or nil
    	local toggle = main and main:FindFirstChild("ToggleVelocity")
    	if toggle and toggle:IsA("BindableEvent") then
    		pcall(function()
    			toggle:Fire(enabled == true)
    		end)
    		return true
    	end
    	return false
    end
    
    ctx.zipRootBlocked = function(character, root)
    	if not (workspace.GetPartBoundsInBox and character and root) then
    		return false
    	end
    	local params = OverlapParams.new()
    	params.FilterType = Enum.RaycastFilterType.Exclude
    	params.FilterDescendantsInstances = { character }
    	params.RespectCanCollide = true
    	params.CollisionGroup = root.CollisionGroup
    	local ok, parts = pcall(function()
    		return workspace:GetPartBoundsInBox(root.CFrame, root.Size * 0.88, params)
    	end)
    	if not ok then
    		return false
    	end
    	for _, part in parts do
    		if part:IsA("BasePart") and part.CanCollide then
    			return true
    		end
    	end
    	return false
    end
    
    ctx.raiseZipCharacter = function(character, root, humanoid)
    	local moved = false
    	local clearance = ctx.zipGroundClearance(character, root, humanoid)
    	local params = RaycastParams.new()
    	params.FilterType = Enum.RaycastFilterType.Exclude
    	params.FilterDescendantsInstances = { character }
    	params.RespectCanCollide = true
    	params.IgnoreWater = true
    	params.CollisionGroup = root.CollisionGroup
    
    	local origin = root.Position + Vector3.new(0, math.max(clearance + 8, 12), 0)
    	local result = workspace:Raycast(origin, Vector3.new(0, -math.max(clearance + 22, 30), 0), params)
    	if result and result.Normal.Y > 0.35 then
    		local targetY = result.Position.Y + clearance + 0.12
    		if root.Position.Y < targetY then
    			local delta = Vector3.new(0, targetY - root.Position.Y, 0)
    			pcall(function()
    				character:PivotTo(character:GetPivot() + delta)
    			end)
    			moved = true
    		end
    	end
    
    	for _ = 1, 28 do
    		if not ctx.zipRootBlocked(character, root) then
    			break
    		end
    		pcall(function()
    			character:PivotTo(character:GetPivot() + Vector3.new(0, 0.25, 0))
    		end)
    		moved = true
    	end
    	return moved
    end
    
    ctx.recoverZipDismount = function(token)
    	if not (ctx.opt.zipAutoOn and ctx.opt.zipStopOn) then
    		return false
    	end
    	if not ctx.alive() or token ~= ctx.cache.zipDismountToken or ctx.currentZipState() then
    		return false
    	end
    	local root, humanoid = ctx.rh(false)
    	if not (root and humanoid and humanoid.Health > 0) then
    		return false
    	end
    	pcall(function()
    		local velocity = root.AssemblyLinearVelocity
    		root.AssemblyLinearVelocity = Vector3.new(0, velocity.Y, 0)
    	end)
    	return true
    end
    
    ctx.finishZipDismount = function()
    	if not (ctx.opt.zipAutoOn and ctx.opt.zipStopOn) then
    		return
    	end
    	ctx.cache.zipDismountToken = (ctx.cache.zipDismountToken or 0) + 1
    	local token = ctx.cache.zipDismountToken
    	task.defer(function()
    		ctx.recoverZipDismount(token)
    	end)
    	if Run and Run.Heartbeat then
    		task.spawn(function()
    			Run.Heartbeat:Wait()
    			ctx.recoverZipDismount(token)
    		end)
    	end
    end
    
    ctx.hookZipStop = function(c)
    	if ctx.cache.zipChar == c and ctx.cache.zipConn then
    		return
    	end
    	ctx.cut(ctx.cache.zipConn)
    	ctx.cache.zipConn = nil
    	ctx.cache.zipChar = c
    	ctx.tmpAnti = c and c:FindFirstChild("CL_AntiSideClip")
    	ctx.tmpZipEv = ctx.tmpAnti and ctx.tmpAnti:FindFirstChild("Ziplining")
    	if ctx.tmpZipEv and ctx.tmpZipEv.Event then
    		ctx.cache.zipConn = ctx.tmpZipEv.Event:Connect(function(st)
    			local wasActive = ctx.opt.zipActive == true or ctx.cache.zipWasActive == true
    			ctx.cache.zipStateSource = "bindable"
    			ctx.cache.zipEventKnown = true
    			ctx.opt.zipActive = st and true or false
    			ctx.cache.zipWasActive = ctx.opt.zipActive
    			if st then
    				ctx.cache.zipDismountToken = (ctx.cache.zipDismountToken or 0) + 1
    			elseif wasActive then
    				ctx.finishZipDismount()
    			end
    		end)
    	end
    end
    
    ctx.fireSlideBindable = function()
    	ctx.tmpOk = ctx.feCall("runSlide", "FE2Helper", Enum.UserInputState.Begin, true)
    	if ctx.tmpOk then
    		return true
    	end
    	ctx.tmpChar = ctx.chr(false)
    	ctx.tmpFe = ctx.tmpChar and ctx.tmpChar:FindFirstChild("FE2_Character")
    	ctx.tmpSlide = ctx.tmpFe and ctx.tmpFe:FindFirstChild("Slide")
    	if ctx.tmpSlide and ctx.tmpSlide.Fire then
    		pcall(function()
    			ctx.tmpSlide:Fire("FE2Helper", Enum.UserInputState.Begin, true)
    		end)
    		return true
    	end
    	return false
    end
    
    ctx.isKeyDown = function(key)
    	if not (Uis and key) then
    		return false
    	end
    	local ok, down = pcall(function()
    		return Uis:IsKeyDown(key)
    	end)
    	return ok and down == true
    end
    
    ctx.isGamepadDown = function(key)
    	if not (Uis and key and type(Uis.IsGamepadButtonDown) == "function") then
    		return false
    	end
    	local ok, down = pcall(function()
    		return Uis:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, key)
    	end)
    	return ok and down == true
    end
    
    ctx.isJumpHeld = function()
    	local now = os.clock()
    	return ctx.cache.jumpHeld == true
    		or now < (ctx.cache.jumpHeldUntil or 0)
    		or ctx.isKeyDown(Enum.KeyCode.Space)
    		or ctx.isGamepadDown(Enum.KeyCode.ButtonA)
    end
    
    ctx.isJumpInput = function(inp)
    	if not inp then
    		return false
    	end
    	return inp.KeyCode == Enum.KeyCode.Space or inp.KeyCode == Enum.KeyCode.ButtonA
    end
    
    ctx.pulseJumpIntent = function(held)
    	ctx.cache.jumpHeld = held == true
    	if held == true then
    		ctx.cache.jumpHeldUntil = os.clock() + 0.45
    	else
    		ctx.cache.jumpHeldUntil = 0
    	end
    end
    
    ctx.bumpJumpIntent = function()
    	ctx.cache.jumpHeldUntil = os.clock() + 0.45
    end
    
    ctx.bindMobileJumpButton = function()
    	ctx.tmpPg = LP and LP:FindFirstChildOfClass("PlayerGui")
    	ctx.tmpJumpBtn = ctx.tmpPg and ctx.tmpPg:FindFirstChild("JumpButton", true)
    	if not (ctx.tmpJumpBtn and ctx.tmpJumpBtn ~= ctx.cache.jumpButton) then
    		return
    	end
    	ctx.clearCons(ctx.cache.jumpButtonCons)
    	ctx.cache.jumpButton = ctx.tmpJumpBtn
    	ctx.cache.jumpButtonCons[#ctx.cache.jumpButtonCons + 1] = ctx.tmpJumpBtn.InputBegan:Connect(function(input)
    		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
    			ctx.pulseJumpIntent(true)
    			ctx.doJumpBoost()
    		end
    	end)
    	ctx.cache.jumpButtonCons[#ctx.cache.jumpButtonCons + 1] = ctx.tmpJumpBtn.InputEnded:Connect(function(input)
    		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
    			ctx.pulseJumpIntent(false)
    		end
    	end)
    	ctx.cache.jumpButtonCons[#ctx.cache.jumpButtonCons + 1] = ctx.tmpJumpBtn.AncestryChanged:Connect(function(_, parent)
    		if parent ~= nil then
    			return
    		end
    		ctx.clearCons(ctx.cache.jumpButtonCons)
    		ctx.cache.jumpButton = nil
    		ctx.pulseJumpIntent(false)
    	end)
    end
    
    ctx.applyPhysicsOptions = function()
    	if not (ctx.opt.infJumpOn or (ctx.opt.zipFastOn and ctx.opt.zipAutoOn)) then
    		return
    	end
    	ctx.tmpRoot, ctx.tmpHum, ctx.tmpChar = ctx.rh(false)
    	if not (ctx.tmpChar and ctx.tmpHum and ctx.tmpRoot) then
    		return
    	end
    	ctx.tmpNow = os.clock()
    	ctx.tmpSpace = ctx.isJumpHeld()
    
    	if ctx.opt.infJumpOn and ctx.tmpSpace and ctx.tmpNow - ctx.cache.jumpAt >= 0.16 and ctx.tmpHum:GetState() ~= Enum.HumanoidStateType.Climbing then
    		ctx.cache.jumpAt = ctx.tmpNow
    		ctx.jumpRoot(52, 0, false)
    	end
    end
    
    ctx.startInfAirHeartbeat = function()
    	if not Run or ctx.cache.infAirHb then
    		return
    	end
    	ctx.cache.infAirHb = Run.Heartbeat:Connect(function()
    		if not ctx.alive() then
    			return
    		end
    		if ctx.opt.infAirOn then
    			local now = os.clock()
    			if now < (ctx.cache.airFastAt or 0) then
    				return
    			end
    			ctx.cache.airFastAt = now + 0.25
    			ctx.keepAirFast()
    		elseif ctx.cache.airAlertEnv then
    			ctx.unprotectAirHealth()
    		end
    	end)
    	ctx.bind(ctx.cache.infAirHb)
    end
    
    ctx.cache.feMoveOrig = ctx.cache.feMoveOrig or setmetatable({}, { __mode = "k" })
    ctx.cache.feMoveModOrig = ctx.cache.feMoveModOrig or {}
    ctx.cache.feMoveChar = nil
    ctx.cache.feMoveCharCons = ctx.cache.feMoveCharCons or {}
    ctx.cache.feMoveLoop = nil
    ctx.cache.feVelHb = ctx.cache.feVelHb
    ctx.cache.feVelTask = ctx.cache.feVelTask
    ctx.cache.feVelSeen = ctx.cache.feVelSeen
    ctx.cache.feVelLast = 0
    ctx.cache.feVelLastState = nil
    ctx.cache.feVelTickAt = 0
    ctx.cache.feApplyTok = 0
    ctx.cache.feApplying = false
    ctx.cache.fePatchState = nil
    ctx.cache.feAppliedChar = nil
    
    ctx.feMoveNoop = function()
    end
    
    ctx.patchFeMoveEnv = function(scr, st)
    	if not (__exec.getsenv and scr) then
    		return false
    	end
    	local ok, env = pcall(__exec.getsenv, scr)
    	if not ok or type(env) ~= "table" then
    		return
    	end
    	local save = ctx.cache.feMoveOrig[scr]
    	if type(save) ~= "table" then
    		save = {}
    		ctx.cache.feMoveOrig[scr] = save
    	end
    	for _, n in { "AccurateJump" } do
    		if st == true then
    			if save[n] ~= nil then
    				env[n] = save[n]
    			end
    		else
    			if save[n] == nil and type(env[n]) == "function" and env[n] ~= ctx.feMoveNoop then
    				save[n] = env[n]
    			end
    			if type(env[n]) == "function" then
    				env[n] = ctx.feMoveNoop
    			end
    		end
    	end
    end
    
    ctx.patchFeAntiWallhop = function(st)
    	local mods = Rsp and Rsp:FindFirstChild("Modules")
    	local client = mods and mods:FindFirstChild("Client")
    	local mod = client and client:FindFirstChild("AntiWallhop")
    	if not (mod and type(require) == "function") then
    		return false
    	end
    	local ok, t = pcall(require, mod)
    	if not ok or type(t) ~= "table" then
    		return false
    	end
    	for _, n in { "onPostSimulation" } do
    		if st == true then
    			if ctx.cache.feMoveModOrig[n] ~= nil then
    				t[n] = ctx.cache.feMoveModOrig[n]
    			end
    		else
    			if ctx.cache.feMoveModOrig[n] == nil and type(t[n]) == "function" and t[n] ~= ctx.feMoveNoop then
    				ctx.cache.feMoveModOrig[n] = t[n]
    			end
    			if type(t[n]) == "function" then
    				t[n] = ctx.feMoveNoop
    			end
    		end
    	end
    	return true
    end
    
    ctx.connectionFn = function(c)
    	if type(c) ~= "table" and typeof(c) ~= "RBXScriptConnection" then
    		return nil
    	end
    	for _, k in { "Function", "func", "Callback", "_function" } do
    		local ok, v = pcall(function()
    			return c[k]
    		end)
    		if ok and type(v) == "function" then
    			return v
    		end
    	end
    	return nil
    end
    
    ctx.connectionMethod = function(c, n)
    	if not c then
    		return nil
    	end
    	local ok, v = pcall(function()
    		return c[n]
    	end)
    	if ok and type(v) == "function" then
    		return v
    	end
    	return nil
    end
    
    ctx.fnEnvScript = function(fn)
    	if type(fn) ~= "function" or not __exec.getfenv then
    		return nil
    	end
    	local ok, env = pcall(__exec.getfenv, fn)
    	if ok and type(env) == "table" and typeof(env.script) == "Instance" then
    		return env.script
    	end
    	return nil
    end
    
    ctx.fnBelongsToScript = function(fn, scr)
    	if not (scr and type(fn) == "function") then
    		return false
    	end
    	local envScript = ctx.fnEnvScript(fn)
    	if envScript == scr then
    		return true
    	end
    	local dbg = type(debug) == "table" and debug or nil
    	local info = dbg and dbg.info
    	if type(info) == "function" then
    		local ok, src = pcall(info, fn, "s")
    		if ok and type(src) == "string" and string.find(src, scr.Name, 1, true) then
    			return true
    		end
    	end
    	return false
    end
    
    ctx.setFirstBoolUpvalue = function(fn, v)
    	if type(fn) ~= "function" then
    		return false
    	end
    	local dbg = type(debug) == "table" and debug or nil
    	local setup = (dbg and dbg.setupvalue) or __exec.setupvalue
    	if type(setup) ~= "function" then
    		return false
    	end
    	local getvals = (dbg and dbg.getupvalues) or __exec.getupvalues
    	if type(getvals) == "function" then
    		local ok, vals = pcall(getvals, fn)
    		if ok and type(vals) == "table" then
    			for i, val in vals do
    				if type(i) == "number" and type(val) == "boolean" then
    					local ok2 = pcall(setup, fn, i, v == true)
    					return ok2
    				end
    			end
    		end
    	end
    	local getone = (dbg and dbg.getupvalue) or __exec.getupvalue
    	if type(getone) ~= "function" then
    		return false
    	end
    	for i = 1, 64 do
    		local ok, a, b = pcall(getone, fn, i)
    		if not ok or (a == nil and b == nil) then
    			break
    		end
    		local val = if b ~= nil then b else a
    		if type(val) == "boolean" then
    			local ok2 = pcall(setup, fn, i, v == true)
    			return ok2
    		end
    	end
    	return false
    end
    
    ctx.eachSignalConnection = function(sig, cb)
    	if not (__exec.getconnections and sig) then
    		return false
    	end
    	local ok, list = pcall(__exec.getconnections, sig)
    	if not ok or type(list) ~= "table" then
    		return false
    	end
    	local hit = false
    	for _, con in list do
    		hit = true
    		pcall(cb, con)
    	end
    	return hit
    end
    
    ctx.patchFeSignalConnections = function(sig, scr, key, st)
    	if not sig then
    		return false
    	end
    	ctx.cache[key] = ctx.cache[key] or setmetatable({}, { __mode = "k" })
    	if st == true then
    		for con in ctx.cache[key] do
    			local enable = ctx.connectionMethod(con, "Enable")
    			if enable then
    				pcall(function()
    					enable(con)
    				end)
    			end
    		end
    		ctx.cache[key] = setmetatable({}, { __mode = "k" })
    		return true
    	end
    	local patched = false
    	ctx.eachSignalConnection(sig, function(con)
    		local fn = ctx.connectionFn(con)
    		if not ctx.fnBelongsToScript(fn, scr) then
    			return
    		end
    		local disable = ctx.connectionMethod(con, "Disable")
    		local enable = ctx.connectionMethod(con, "Enable")
    		if disable and enable then
    			pcall(function()
    				disable(con)
    			end)
    			ctx.cache[key][con] = true
    			patched = true
    		end
    	end)
    	return patched
    end
    
    ctx.patchFeHumanoidSignals = function(scr, st)
    	local _, h = ctx.rh(false)
    	if not (scr and h) then
    		return
    	end
    	if __exec.getconnections then
    		ctx.patchFeSignalConnections(h.StateChanged, scr, "feStateCons", st)
    		ctx.patchFeSignalConnections(h.FallingDown, scr, "feFallCons", st)
    	end
    	if st == true then
    		ctx.cut(ctx.cache.feScanConn)
    		ctx.cache.feScanConn = nil
    		return
    	end
    	if ctx.cache.feScanHum == h and ctx.cache.feScanConn then
    		return
    	end
    	ctx.cut(ctx.cache.feScanConn)
    	ctx.cache.feScanHum = h
    	ctx.cache.feScanConn = h.StateChanged:Connect(function(_, newState)
    		if ctx.opt.fePhysicsOn ~= true then
    			return
    		end
    		if newState ~= Enum.HumanoidStateType.Freefall and newState ~= Enum.HumanoidStateType.Jumping then
    			return
    		end
    		local env = ctx.envOf(scr)
    		if env and type(env.scanWalljumps) == "function" then
    			task.defer(function()
    				pcall(env.scanWalljumps)
    			end)
    		elseif ctx.opt.fePhysicsOn then
    			task.defer(function()
    				ctx.patchFeAntiWallhop(false)
    				pcall(function()
    					h:SetStateEnabled(Enum.HumanoidStateType.Landed, true)
    				end)
    			end)
    		end
    	end)
    	ctx.bind(ctx.cache.feScanConn)
    end
    
    ctx.patchFeMainEnv = function(st)
    	local env = ctx.gameEnv()
    	if not env then
    		return
    	end
    	local save = ctx.cache.feMoveOrig.__main
    	if type(save) ~= "table" then
    		save = {}
    		ctx.cache.feMoveOrig.__main = save
    	end
    	for _, n in { "AccurateJump" } do
    		if st == true then
    			if save[n] ~= nil then
    				env[n] = save[n]
    			end
    		else
    			if save[n] == nil and type(env[n]) == "function" and env[n] ~= ctx.feMoveNoop then
    				save[n] = env[n]
    			end
    			if type(env[n]) == "function" then
    				env[n] = ctx.feMoveNoop
    			end
    		end
    	end
    end
    
    ctx.setFePhysicsFallback = function(enabled)
    	if enabled ~= true then
    		ctx.cut(ctx.cache.feCompatPostSimulation)
    		ctx.cache.feCompatPostSimulation = nil
    		ctx.cache.feCompatFallback = false
    		return
    	end
    	ctx.cache.feCompatFallback = true
    	if ctx.cache.feCompatPostSimulation or not (Run and Run.PostSimulation) then
    		return
    	end
    	ctx.cache.feCompatPostSimulation = Run.PostSimulation:Connect(function()
    		if not (ctx.alive() and ctx.opt.fePhysicsOn) then
    			return
    		end
    		local _, humanoid = ctx.rh(false)
    		if humanoid then
    			pcall(function()
    				if humanoid:GetStateEnabled(Enum.HumanoidStateType.Landed) ~= true then
    					humanoid:SetStateEnabled(Enum.HumanoidStateType.Landed, true)
    				end
    			end)
    		end
    	end)
    	ctx.bind(ctx.cache.feCompatPostSimulation)
    end
    
    ctx.canRestoreFePhysics = function(force)
    	if force == true then
    		return true
    	end
    	return ctx.opt.zipActive ~= true
    end
    
    ctx.patchFeMovementState = function(st, force)
    	ctx.tmpSameState = force ~= true and ctx.cache.fePatchState == st
    	if not ctx.tmpSameState then
    		ctx.tmpAntiWallhopPatched = ctx.patchFeAntiWallhop(st)
    		ctx.patchFeMainEnv(st)
    		ctx.setFePhysicsFallback(st == false and ctx.tmpAntiWallhopPatched ~= true)
    		ctx.cache.fePatchState = st
    	end
    	ctx.tmpRoot, ctx.tmpHum = ctx.rh(false)
    	ctx.tmpConfig = Rsp and Rsp:FindFirstChild("Config")
    	ctx.tmpAntiWallhopActive = not ctx.tmpConfig or ctx.tmpConfig:GetAttribute("Unpatched") ~= true
    	if ctx.tmpHum and ctx.tmpAntiWallhopActive then
    		pcall(function()
    			ctx.tmpHum:SetStateEnabled(Enum.HumanoidStateType.Landed, st ~= true)
    		end)
    	end
    	return true
    end
    
    ctx.restoreFeMoveEnv = function(scr)
    	local save = ctx.cache.feMoveOrig[scr]
    	if type(save) ~= "table" then
    		return
    	end
    	local env = ctx.envOf(scr)
    	if not env then
    		return
    	end
    	for n, fn in save do
    		if type(n) == "string" and type(fn) == "function" then
    			env[n] = save[n]
    		end
    	end
    end
    
    ctx.applyFeMovement = function(force)
    	if ctx.cache.feApplying and force ~= true then
    		ctx.cache.fePendingApply = true
    		return false
    	end
    	local st = ctx.opt.fePhysicsOn ~= true
    	if st and ctx.cache.fePatchState == false and not ctx.canRestoreFePhysics(force) then
    		ctx.cache.fePendingRestore = true
    		local now = os.clock()
    		if now >= (ctx.cache.fePendingNoteAt or 0) then
    			ctx.cache.fePendingNoteAt = now + 3
    			ctx.note("Movement guard restore queued until the zipline ends")
    		end
    		return false
    	end
    	ctx.cache.fePendingRestore = false
    	local c = ctx.chr(false)
    	if force ~= true and ctx.cache.feLastApplyState == st and ctx.cache.feAppliedChar == c and not ctx.cache.fePendingApply then
    		return true
    	end
    	ctx.cache.feApplying = true
    	ctx.cache.fePendingApply = false
    	local ok = pcall(function()
    		ctx.patchFeMovementState(st, force)
    		if not c then
    			return
    		end
    		local fe = c:FindFirstChild("FE2_Character")
    		if fe and fe:IsA("LocalScript") then
    			ctx.patchFeMoveEnv(fe, st)
    			ctx.patchFeHumanoidSignals(fe, st)
    		end
    		ctx.patchSideClip()
    		local main = ctx.mainScript()
    		if main then
    			ctx.patchFeMoveEnv(main, st)
    		end
    		ctx.cache.feLastApplyState = st
    		ctx.cache.feAppliedChar = c
    	end)
    	ctx.cache.feApplying = false
    	if not ok then
    		ctx.cache.fePatchState = nil
    		ctx.cache.fePendingApply = true
    		ctx.scheduleFeMovement(0.35)
    		return false
    	end
    	if not c then
    		return false
    	end
    	if ctx.cache.fePendingApply then
    		ctx.scheduleFeMovement(0.15)
    	end
    	return true
    end
    
    ctx.scheduleFeMovement = function(delayTime, force)
    	ctx.cache.feApplyTok = (ctx.cache.feApplyTok or 0) + 1
    	local id = ctx.cache.feApplyTok
    	task.delay(delayTime or 0.12, function()
    		if not ctx.alive() or ctx.cache.feApplyTok ~= id then
    			return
    		end
    		ctx.applyFeMovement(force == true)
    	end)
    end
    
    ctx.bindFeMovementChar = function(c)
    	ctx.clearCons(ctx.cache.feMoveCharCons)
    	ctx.cache.feMoveChar = c
    	if not c then
    		return
    	end
    	ctx.cache.feMoveCharCons[#ctx.cache.feMoveCharCons + 1] = c.ChildAdded:Connect(function(v)
    		if v.Name == "FE2_Character" or v.Name == "CL_AntiSideClip" then
    			ctx.scheduleFeMovement(0.1)
    		end
    	end)
    	ctx.scheduleFeMovement(0.1)
    end
    
    ctx.startFeMovementPatch = function()
    	if ctx.cache.feMoveLoop then
    		return
    	end
    	if LP then
    		ctx.bind(LP.CharacterAdded:Connect(function(c)
    			task.defer(ctx.bindFeMovementChar, c)
    		end))
    	end
    	if LP and LP.Character then
    		ctx.bindFeMovementChar(LP.Character)
    	end
    	ctx.cache.feMoveLoop = true
    	ctx.spawnLoop(function()
    		local appliedCharacter = nil
    		while ctx.alive() do
    			ctx.opt.fePhysicsOn = false
    			if LP and LP.Character ~= ctx.cache.feMoveChar then
    				ctx.bindFeMovementChar(LP.Character)
    			end
    			if appliedCharacter ~= LP.Character or ctx.cache.fePendingRestore or ctx.cache.fePendingApply then
    				ctx.applyFeMovement(true)
    				appliedCharacter = LP.Character
    			end
    			task.wait(0.5)
    		end
    	end)
    end
    
    ctx.startPhysicsOptions = function()
    	ctx.startInfAirHeartbeat()
    	ctx.startFeMovementPatch()
    	if Uis then
    		ctx.bind(Uis.JumpRequest:Connect(function()
    			ctx.bumpJumpIntent()
    			ctx.doJumpBoost()
    		end))
    		ctx.bind(Uis.InputBegan:Connect(function(inp, gp)
    			if not inp then
    				return
    			end
    			if gp and inp.UserInputType == Enum.UserInputType.Keyboard then
    				return
    			end
    			if ctx.isJumpInput(inp) then
    				ctx.pulseJumpIntent(true)
    				ctx.doJumpBoost()
    			elseif gp then
    				return
    			end
    		end))
    		ctx.bind(Uis.InputEnded:Connect(function(inp)
    			if ctx.isJumpInput(inp) then
    				ctx.pulseJumpIntent(false)
    			end
    		end))
    	end
    	ctx.tmpMouse = LP and LP:GetMouse()
    	if ctx.tmpMouse then
    		ctx.bind(ctx.tmpMouse.Button1Up:Connect(function()
    			if not ctx.opt.clickTpOn then
    				return
    			end
    			if ctx.tmpMouse.Hit then
    				ctx.clickTeleportTo(ctx.tmpMouse.Hit.Position)
    			end
    		end))
    	end
    	if Uis and Uis.TouchTap then
    		ctx.bind(Uis.TouchTap:Connect(ctx.touchClickTeleport))
    	end
    	ctx.spawnLoop(function()
    		while ctx.alive() do
    			ctx.bindMobileJumpButton()
    			ctx.applyPhysicsOptions()
    			task.wait(0.18)
    		end
    	end)
    end
    
    ctx.startUiUnlocks = function()
    	ctx.cache.uiTok += 1
    	ctx.tmpUiTok = ctx.cache.uiTok
    	ctx.spawnLoop(function()
    		while ctx.alive() and ctx.cache.uiTok == ctx.tmpUiTok do
    			if ctx.opt.paidOn then
    				ctx.patchPaidUi()
    			end
    			task.wait(3)
    		end
    	end)
    end
    
    if MP then
    	ctx.bind(MP.ChildAdded:Connect(function(ch)
    		if ch.Name == "Map" or ch.Name == "NewMap" then
    			ctx.cache.curMap = ch
    			ctx.cache.curMapAt = 0
    			ctx.resetMapCache(ch)
    			if ctx.opt.floodOn and type(ctx.floodApply) == "function" then
    				task.defer(ctx.floodApply, ch)
    			end
    			if on then
    				ctx.spawnLoop(ctx.burstLoaded)
    			end
    			if ctx.opt.zipFastOn and ctx.opt.zipAutoOn then
    				task.defer(ctx.reapplyZipSpeed)
    				task.delay(0.75, ctx.reapplyZipSpeed)
    				task.delay(2, ctx.reapplyZipSpeed)
    			end
    		end
    	end))
    	ctx.bind(MP.ChildRemoved:Connect(function(ch)
    		if ch == ctx.cache.curMap or ch == ctx.cache.mapRef then
    			ctx.cache.curMap = nil
    			ctx.cache.curMapAt = 0
    			ctx.resetMapCache(nil)
    		end
    	end))
    end
    
    ctx.loadTopbar = function()
    	if ctx.topbar then
    		return ctx.topbar
    	end
    	ctx.tmpLoader = __exec.loader
    	if type(ctx.tmpLoader) ~= "function" then
    		return nil
    	end
    	ctx.tmpSrc = nil
    	pcall(function()
    		ctx.tmpSrc = game:HttpGet("https://raw.githubusercontent.com/ltseverydayyou/uuuuuuu/refs/heads/main/Icon.luau")
    	end)
    	if type(ctx.tmpSrc) ~= "string" or ctx.tmpSrc == "" then
    		return nil
    	end
    	ctx.tmpChunk = ctx.tmpLoader(ctx.tmpSrc, "@lt_topbar_icon.luau")
    	if type(ctx.tmpChunk) ~= "function" then
    		return nil
    	end
    	pcall(function()
    		ctx.topbar = ctx.tmpChunk()
    	end)
    	if type(ctx.topbar) == "table" then
    		pcall(function()
    			ctx.topbar.setDisplayOrder(2147483647)
    		end)
    		return ctx.topbar
    	end
    	return nil
    end
    
    ctx.icon = function(name, label, cb, col)
    	ctx.tmpIcon = ctx.topbar.new()
    	pcall(function()
    		ctx.tmpIcon:setName("FE2_" .. name)
    	end)
    	pcall(function()
    		ctx.tmpIcon:setLabel(label)
    	end)
    	pcall(function()
    		ctx.tmpIcon:oneClick()
    	end)
    	if col then
    		ctx.uiColor(ctx.tmpIcon, col)
    	end
    	if type(cb) == "function" then
    		pcall(function()
    			ctx.tmpIcon:bindEvent("selected", function()
    				if Run then
    					local once
    					once = Run.Heartbeat:Connect(function()
    						if once then
    							once:Disconnect()
    							once = nil
    						end
    						ctx.spawnLoop(cb)
    					end)
    				else
    					ctx.spawnLoop(cb)
    				end
    			end)
    		end)
    	end
    	ctx.ui.menu[#ctx.ui.menu + 1] = ctx.tmpIcon
    	return ctx.tmpIcon
    end
    
    ctx.applyAuraDistText = function(txt)
    	ctx.tmpNum = tonumber(txt)
    	if not ctx.tmpNum then
    		ctx.note("Invalid aura distance")
    		return false
    	end
    	auraDist = math.max(0, math.floor(ctx.tmpNum * 100 + 0.5) / 100)
    	ctx.setDistBtn()
    	ctx.saveSoon()
    	ctx.note("Aura distance set to " .. tostring(auraDist))
    	return true
    end
    
    ctx.releasePromptIcon = function(icon)
    	if not icon then
    		return
    	end
    	pcall(function()
    		if type(icon.deselect) == "function" then
    			icon:deselect()
    		elseif type(icon.setState) == "function" then
    			icon:setState("Deselected")
    		end
    	end)
    end
    
    ctx.deferUiTask = function(fn, ...)
    	if type(fn) ~= "function" then
    		return
    	end
    	local args = table.pack(...)
    	local function run()
    		ctx.spawnLoop(function()
    			fn(table.unpack(args, 1, args.n))
    			args = nil
    		end)
    	end
    	if Run then
    		local once
    		once = Run.Heartbeat:Connect(function()
    			if once then
    				once:Disconnect()
    				once = nil
    			end
    			run()
    		end)
    	else
    		task.defer(run)
    	end
    end
    
    ctx.hideDestroyPrompt = function(prompt)
    	if not prompt then
    		return
    	end
    	pcall(function()
    		if prompt:IsA("ScreenGui") then
    			prompt.Enabled = false
    		end
    	end)
    	pcall(function()
    		for _, obj in prompt:GetDescendants() do
    			if obj:IsA("GuiObject") then
    				obj.Visible = false
    			end
    		end
    	end)
    	pcall(function()
    		prompt.Parent = nil
    	end)
    	task.defer(function()
    		pcall(function()
    			prompt:Destroy()
    		end)
    	end)
    end
    
    ctx.cleanupPromptByName = function(name)
    	if type(name) ~= "string" or name == "" then
    		return
    	end
    	local roots = {}
    	local function add(root)
    		if root then
    			roots[#roots + 1] = root
    		end
    	end
    	local okHui, hui = pcall(ctx.gethui)
    	if okHui then
    		add(hui)
    	end
    	add(Cgui)
    	add(LP and LP:FindFirstChildOfClass("PlayerGui"))
    	local seen = {}
    	for _, root in roots do
    		if root and not seen[root] then
    			seen[root] = true
    			local okKids, kids = pcall(root.GetChildren, root)
    			if okKids and type(kids) == "table" then
    				for _, child in kids do
    					if child and child.Name == name then
    						ctx.hideDestroyPrompt(child)
    					end
    				end
    			end
    			local okDesc, desc = pcall(root.GetDescendants, root)
    			if okDesc and type(desc) == "table" then
    				for _, obj in desc do
    					if obj and obj.Name == name then
    						ctx.hideDestroyPrompt(obj)
    					end
    				end
    			end
    		end
    	end
    end
    
    ctx.disposableScreen = function(name)
    	ctx.cleanupPromptByName(name)
    	local gui = Instance.new("ScreenGui")
    	gui.Name = name
    	gui.IgnoreGuiInset = true
    	gui.ResetOnSpawn = false
    	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    	gui.DisplayOrder = 2147483647
    
    	local protected = ctx.__NAProtectUI(gui, {
    		name = name,
    		keepName = true,
    		harden = false,
    		deep = false,
    		watch = false,
    		rename = false,
    	})
    	if typeof(protected) == "Instance" then
    		gui = protected
    	end
    
    	if not gui.Parent then
    		local parent = nil
    		if __NAUIProtector and type(__NAUIProtector.parent) == "function" then
    			local ok, result = pcall(__NAUIProtector.parent)
    			if ok and typeof(result) == "Instance" then
    				parent = result
    			end
    		end
    		if not parent then
    			local ok, result = pcall(ctx.gethui)
    			if ok and typeof(result) == "Instance" then
    				parent = result
    			end
    		end
    		if not parent and type(ctx.gt) == "function" then
    			parent = ctx.gt("CoreGui")
    		end
    		if not parent then
    			gui:Destroy()
    			return nil
    		end
    		gui.Parent = parent
    	end
    
    	return gui
    end
    
    ctx.cleanupPromptByName("FE2AuraDistancePrompt")
    ctx.cleanupPromptByName("FE2ZipSpeedPrompt")
    
    ctx.closeAuraPrompt = function()
    	local prompt = ctx.ui.auraPrompt
    	ctx.ui.auraPrompt = nil
    	ctx.clearCons(ctx.cache.auraPromptCons)
    	if prompt then
    		ctx.hideDestroyPrompt(prompt)
    	end
    	ctx.releasePromptIcon(ctx.ui.distBtn)
    end
    
    ctx.openAuraPrompt = function()
    	if ctx.ui.auraPrompt then
    		ctx.closeAuraPrompt()
    		return
    	end
    	if ctx.ui.zipPrompt then
    		ctx.closeZipPrompt()
    	end
    
    	local prompt = ctx.disposableScreen("FE2AuraDistancePrompt")
    	ctx.ui.auraPrompt = prompt
    	if not prompt then
    		ctx.note("No usable UI parent")
    		ctx.releasePromptIcon(ctx.ui.distBtn)
    		return
    	end
    
    	local frame = Instance.new("Frame")
    	frame.Name = "Box"
    	frame.AnchorPoint = Vector2.new(0.5, 0)
    	frame.Position = UDim2.new(0.5, 0, 0, 72)
    	frame.Size = UDim2.fromOffset(260, 112)
    	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    	frame.BorderSizePixel = 0
    	frame.Parent = prompt
    
    	local corner = Instance.new("UICorner")
    	corner.CornerRadius = UDim.new(0, 10)
    	corner.Parent = frame
    
    	local title = Instance.new("TextLabel")
    	title.BackgroundTransparency = 1
    	title.Size = UDim2.new(1, -16, 0, 28)
    	title.Position = UDim2.fromOffset(8, 6)
    	title.Font = Enum.Font.GothamBold
    	title.TextScaled = true
    	title.TextColor3 = Color3.new(1, 1, 1)
    	title.Text = "Aura Distance"
    	title.Parent = frame
    
    	local box = Instance.new("TextBox")
    	box.Name = "Input"
    	box.Size = UDim2.new(1, -24, 0, 34)
    	box.Position = UDim2.fromOffset(12, 42)
    	box.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
    	box.BorderSizePixel = 0
    	box.ClearTextOnFocus = false
    	box.Text = tostring(auraDist)
    	box.PlaceholderText = "number, e.g. 2 or 8"
    	box.Font = Enum.Font.Gotham
    	box.TextScaled = true
    	box.TextColor3 = Color3.new(1, 1, 1)
    	box.Parent = frame
    
    	local boxCorner = Instance.new("UICorner")
    	boxCorner.CornerRadius = UDim.new(0, 8)
    	boxCorner.Parent = box
    
    	local apply = Instance.new("TextButton")
    	apply.Name = "Apply"
    	apply.Size = UDim2.new(0.5, -18, 0, 26)
    	apply.Position = UDim2.fromOffset(12, 82)
    	apply.BackgroundColor3 = Color3.fromRGB(60, 160, 75)
    	apply.BorderSizePixel = 0
    	apply.Font = Enum.Font.GothamBold
    	apply.TextScaled = true
    	apply.TextColor3 = Color3.new(1, 1, 1)
    	apply.Text = "Apply"
    	apply.Parent = frame
    
    	local applyCorner = Instance.new("UICorner")
    	applyCorner.CornerRadius = UDim.new(0, 8)
    	applyCorner.Parent = apply
    
    	local cancel = Instance.new("TextButton")
    	cancel.Name = "Cancel"
    	cancel.Size = UDim2.new(0.5, -18, 0, 26)
    	cancel.Position = UDim2.new(0.5, 6, 0, 82)
    	cancel.BackgroundColor3 = Color3.fromRGB(150, 55, 55)
    	cancel.BorderSizePixel = 0
    	cancel.Font = Enum.Font.GothamBold
    	cancel.TextScaled = true
    	cancel.TextColor3 = Color3.new(1, 1, 1)
    	cancel.Text = "Cancel"
    	cancel.Parent = frame
    
    	local cancelCorner = Instance.new("UICorner")
    	cancelCorner.CornerRadius = UDim.new(0, 8)
    	cancelCorner.Parent = cancel
    
    	ctx.cache.auraPromptCons[#ctx.cache.auraPromptCons + 1] = apply.Activated:Connect(function()
    		if ctx.applyAuraDistText(box.Text) then
    			ctx.deferUiTask(ctx.closeAuraPrompt)
    		end
    	end)
    	ctx.cache.auraPromptCons[#ctx.cache.auraPromptCons + 1] = cancel.Activated:Connect(function()
    		ctx.deferUiTask(ctx.closeAuraPrompt)
    	end)
    	ctx.cache.auraPromptCons[#ctx.cache.auraPromptCons + 1] = box.FocusLost:Connect(function(enterPressed)
    		if enterPressed and ctx.applyAuraDistText(box.Text) then
    			ctx.deferUiTask(ctx.closeAuraPrompt)
    		end
    	end)
    end
    
    ctx.applyZipSpeedText = function(txt)
    	ctx.tmpNum = tonumber(txt)
    	if not ctx.tmpNum then
    		ctx.note("Invalid zipline speed")
    		return false
    	end
    	ctx.tmpNum = math.max(0, math.floor(ctx.tmpNum * 100 + 0.5) / 100)
    	ctx.opt.zipSpeed = ctx.tmpNum
    	ctx.opt.zipFastOn = ctx.tmpNum > 0
    	ctx.setZipBtn()
    	ctx.setZipAttrs(ctx.opt.zipAutoOn and ctx.opt.zipFastOn)
    	ctx.saveSoon()
    	ctx.note(ctx.opt.zipFastOn and ("Zipline speed set to " .. tostring(ctx.opt.zipSpeed)) or "Zipline speed disabled")
    	return true
    end
    
    ctx.closeZipPrompt = function()
    	local prompt = ctx.ui.zipPrompt
    	ctx.ui.zipPrompt = nil
    	ctx.clearCons(ctx.cache.zipPromptCons)
    	if prompt then
    		ctx.hideDestroyPrompt(prompt)
    	end
    	ctx.releasePromptIcon(ctx.ui.zipBtn)
    end
    
    ctx.openZipPrompt = function()
    	if ctx.ui.zipPrompt then
    		ctx.closeZipPrompt()
    		return
    	end
    	if ctx.ui.auraPrompt then
    		ctx.closeAuraPrompt()
    	end
    
    	local prompt = ctx.disposableScreen("FE2ZipSpeedPrompt")
    	ctx.ui.zipPrompt = prompt
    	if not prompt then
    		ctx.note("No usable UI parent")
    		ctx.releasePromptIcon(ctx.ui.zipBtn)
    		return
    	end
    
    	local frame = Instance.new("Frame")
    	frame.Name = "Box"
    	frame.AnchorPoint = Vector2.new(0.5, 0)
    	frame.Position = UDim2.new(0.5, 0, 0, 72)
    	frame.Size = UDim2.fromOffset(270, 116)
    	frame.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
    	frame.BorderSizePixel = 0
    	frame.Parent = prompt
    
    	local corner = Instance.new("UICorner")
    	corner.CornerRadius = UDim.new(0, 10)
    	corner.Parent = frame
    
    	local title = Instance.new("TextLabel")
    	title.BackgroundTransparency = 1
    	title.Size = UDim2.new(1, -16, 0, 28)
    	title.Position = UDim2.fromOffset(8, 6)
    	title.Font = Enum.Font.GothamBold
    	title.TextScaled = true
    	title.TextColor3 = Color3.new(1, 1, 1)
    	title.Text = "Zipline Speed"
    	title.Parent = frame
    
    	local box = Instance.new("TextBox")
    	box.Name = "Input"
    	box.Size = UDim2.new(1, -24, 0, 34)
    	box.Position = UDim2.fromOffset(12, 42)
    	box.BackgroundColor3 = Color3.fromRGB(45, 45, 52)
    	box.BorderSizePixel = 0
    	box.ClearTextOnFocus = false
    	box.Text = tostring(ctx.opt.zipSpeed)
    	box.PlaceholderText = "0 disables, e.g. 60 or 90"
    	box.Font = Enum.Font.Gotham
    	box.TextScaled = true
    	box.TextColor3 = Color3.new(1, 1, 1)
    	box.Parent = frame
    
    	local boxCorner = Instance.new("UICorner")
    	boxCorner.CornerRadius = UDim.new(0, 8)
    	boxCorner.Parent = box
    
    	local apply = Instance.new("TextButton")
    	apply.Name = "Apply"
    	apply.Size = UDim2.new(0.5, -18, 0, 26)
    	apply.Position = UDim2.fromOffset(12, 86)
    	apply.BackgroundColor3 = Color3.fromRGB(60, 160, 75)
    	apply.BorderSizePixel = 0
    	apply.Font = Enum.Font.GothamBold
    	apply.TextScaled = true
    	apply.TextColor3 = Color3.new(1, 1, 1)
    	apply.Text = "Apply"
    	apply.Parent = frame
    
    	local applyCorner = Instance.new("UICorner")
    	applyCorner.CornerRadius = UDim.new(0, 8)
    	applyCorner.Parent = apply
    
    	local cancel = Instance.new("TextButton")
    	cancel.Name = "Cancel"
    	cancel.Size = UDim2.new(0.5, -18, 0, 26)
    	cancel.Position = UDim2.new(0.5, 6, 0, 86)
    	cancel.BackgroundColor3 = Color3.fromRGB(150, 55, 55)
    	cancel.BorderSizePixel = 0
    	cancel.Font = Enum.Font.GothamBold
    	cancel.TextScaled = true
    	cancel.TextColor3 = Color3.new(1, 1, 1)
    	cancel.Text = "Cancel"
    	cancel.Parent = frame
    
    	local cancelCorner = Instance.new("UICorner")
    	cancelCorner.CornerRadius = UDim.new(0, 8)
    	cancelCorner.Parent = cancel
    
    	ctx.cache.zipPromptCons[#ctx.cache.zipPromptCons + 1] = apply.Activated:Connect(function()
    		if ctx.applyZipSpeedText(box.Text) then
    			ctx.deferUiTask(ctx.closeZipPrompt)
    		end
    	end)
    	ctx.cache.zipPromptCons[#ctx.cache.zipPromptCons + 1] = cancel.Activated:Connect(function()
    		ctx.deferUiTask(ctx.closeZipPrompt)
    	end)
    	ctx.cache.zipPromptCons[#ctx.cache.zipPromptCons + 1] = box.FocusLost:Connect(function(enterPressed)
    		if enterPressed and ctx.applyZipSpeedText(box.Text) then
    			ctx.deferUiTask(ctx.closeZipPrompt)
    		end
    	end)
    end
    
    ctx.femEventsRoot = function()
    	return Rsp and Rsp:FindFirstChild("Events") or nil
    end
    
    ctx.femGetEventsTable = function()
    	if ctx.cache.femEventsTable ~= nil then
    		return ctx.cache.femEventsTable
    	end
    	ctx.cache.femEventsTable = false
    	ctx.tmpPs = LP and LP:FindFirstChild("PlayerScripts")
    	ctx.tmpLh = ctx.tmpPs and ctx.tmpPs:FindFirstChild("LocalHandler")
    	ctx.tmpGe = ctx.tmpLh and ctx.tmpLh:FindFirstChild("GetEvents")
    	if ctx.tmpGe and type(require) == "function" then
    		ctx.tmpOk, ctx.tmpRes = pcall(function()
    			return require(ctx.tmpGe)()
    		end)
    		if ctx.tmpOk and type(ctx.tmpRes) == "table" then
    			ctx.cache.femEventsTable = ctx.tmpRes
    			return ctx.tmpRes
    		end
    	end
    	return nil
    end
    
    ctx.femEvent = function(n, cls)
    	ctx.tmpEvs = ctx.femEventsRoot()
    	ctx.tmpEv = ctx.tmpEvs and ctx.tmpEvs:FindFirstChild(n)
    	if ctx.tmpEv and (not cls or ctx.tmpEv:IsA(cls)) then
    		return ctx.tmpEv
    	end
    	ctx.tmpTbl = ctx.femGetEventsTable()
    	ctx.tmpEv = type(ctx.tmpTbl) == "table" and ctx.tmpTbl[n] or nil
    	if ctx.tmpEv and (not cls or ctx.tmpEv:IsA(cls)) then
    		return ctx.tmpEv
    	end
    	if __exec.getnilinstances or __exec.getinstances then
    		for _, fn in { __exec.getnilinstances, __exec.getinstances } do
    			if type(fn) == "function" then
    				ctx.tmpOk, ctx.tmpList = pcall(fn)
    				if ctx.tmpOk and type(ctx.tmpList) == "table" then
    					for _, obj in ctx.tmpList do
    						if typeof(obj) == "Instance" and obj.Name == n and (not cls or obj:IsA(cls)) then
    							return obj
    						end
    					end
    				end
    			end
    		end
    	end
    	return nil
    end
    
    ctx.isFEM = function()
    	if ctx.cache.isFEM == true then
    		return true
    	end
    	if ctx.cache.isFEM == false and os.clock() < (ctx.cache.femRetry or 0) then
    		return false
    	end
    	ctx.tmpGameId = nil
    	pcall(function()
    		ctx.tmpGameId = game.GameId
    	end)
    	ctx.cache.isFEM = ctx.tmpGameId == 761462079 and ctx.femEvent("StartMapVote", "RemoteEvent") ~= nil and ctx.femEvent("UpdMapVote", "RemoteEvent") ~= nil
    	if ctx.cache.isFEM ~= true then
    		ctx.cache.femRetry = os.clock() + 2
    	end
    	return ctx.cache.isFEM == true
    end
    
    ctx.femFreeMap = function(data)
    	if type(data) ~= "table" or type(data.MapData) ~= "table" then
    		return nil
    	end
    	ctx.tmpBest = nil
    	for _, map in data.MapData do
    		if type(map) == "table" and map.ID ~= nil and map.ShowMap ~= false and map.Cooldown ~= true and map.Locked ~= true then
    			ctx.tmpBest = map
    			break
    		end
    	end
    	return ctx.tmpBest
    end
    
    ctx.femVoteData = function(data)
    	if not ctx.opt.femVoteOn or not ctx.isFEMGame() then
    		return false
    	end
    	ctx.tmpMap = ctx.femFreeMap(data)
    	if not ctx.tmpMap then
    		return false
    	end
    	ctx.tmpId = ctx.tmpMap.ID
    	ctx.tmpNow = os.clock()
    	if ctx.cache.femLastVoteId == ctx.tmpId and ctx.tmpNow - (ctx.cache.femVoteAt or 0) < 1.25 then
    		return false
    	end
    	ctx.tmpVote = ctx.femEvent("UpdMapVote", "RemoteEvent")
    	if not ctx.tmpVote then
    		return false
    	end
    	ctx.cache.femLastVoteId = ctx.tmpId
    	ctx.cache.femVoteAt = ctx.tmpNow
    	return ctx.fireRemote(ctx.tmpVote, ctx.tmpId, 0)
    end
    
    ctx.startFemAutoVote = function()
    	if ctx.cache.femStarted then
    		return
    	end
    	ctx.cache.femStarted = true
    	ctx.tmpStartVote = ctx.femEvent("StartMapVote", "RemoteEvent")
    	if ctx.tmpStartVote then
    		ctx.bind(ctx.tmpStartVote.OnClientEvent:Connect(function(data)
    			if ctx.opt.femVoteOn then
    				task.defer(ctx.femVoteData, data)
    			end
    		end))
    	end
    	ctx.tmpUpdVote = ctx.femEvent("UpdMapVote", "RemoteEvent")
    	if ctx.tmpUpdVote then
    		ctx.bind(ctx.tmpUpdVote.OnClientEvent:Connect(function(data)
    			if ctx.opt.femVoteOn then
    				task.defer(ctx.femVoteData, data)
    			end
    		end))
    	end
    end
    
    ctx.femItemData = function()
    	if type(ctx.cache.femItems) == "table" then
    		return ctx.cache.femItems
    	end
    	ctx.cache.femItems = false
    	ctx.tmpMods = Rsp and Rsp:FindFirstChild("Modules")
    	ctx.tmpItemData = ctx.tmpMods and ctx.tmpMods:FindFirstChild("ItemData")
    	if ctx.tmpItemData and type(require) == "function" then
    		ctx.tmpOk, ctx.tmpMod = pcall(require, ctx.tmpItemData)
    		if ctx.tmpOk and type(ctx.tmpMod) == "table" and type(ctx.tmpMod.GetItemData) == "function" then
    			ctx.tmpOk2, ctx.tmpItems = pcall(ctx.tmpMod.GetItemData)
    			if ctx.tmpOk2 and type(ctx.tmpItems) == "table" then
    				ctx.cache.femItems = ctx.tmpItems
    				return ctx.tmpItems
    			end
    		end
    	end
    	return nil
    end
    
    ctx.femOwnedItems = function()
    	ctx.tmpOwned = {}
    	ctx.tmpData = LP and LP:FindFirstChild("Data")
    	ctx.tmpShop = ctx.tmpData and ctx.tmpData:FindFirstChild("Shop")
    	ctx.tmpItems = ctx.tmpShop and ctx.tmpShop:FindFirstChild("Items")
    	if ctx.tmpItems then
    		for _, obj in ctx.tmpItems:GetChildren() do
    			ctx.tmpId = tonumber(obj.Name) or obj.Name
    			ctx.tmpOwned[ctx.tmpId] = true
    		end
    	end
    	return ctx.tmpOwned
    end
    
    ctx.femFunds = function(cur)
    	ctx.tmpData = LP and LP:FindFirstChild("Data")
    	ctx.tmpVal = ctx.tmpData and ctx.tmpData:FindFirstChild(cur == 1 and "Amethysts" or "Coins")
    	return ctx.tmpVal and tonumber(ctx.tmpVal.Value) or 0
    end
    
    ctx.femShopBuyIds = function(cur)
    	ctx.tmpItems = ctx.femItemData()
    	ctx.tmpIds = {}
    	ctx.tmpSeen = {}
    	ctx.tmpOwned = ctx.femOwnedItems()
    	ctx.tmpBudget = ctx.femFunds(cur)
    	ctx.tmpSpent = 0
    	if type(ctx.tmpItems) ~= "table" then
    		return ctx.tmpIds
    	end
    	for _, it in ctx.tmpItems do
    		if type(it) == "table" then
    			ctx.tmpId = tonumber(it.ID)
    			ctx.tmpCat = tostring(it.Catagory or it.catagory or "")
    			ctx.tmpPrice = tonumber(cur == 1 and it.Price_Amethysts or it.Price_Coins)
    			if ctx.tmpId and ctx.tmpPrice and ctx.tmpPrice > 0 and not ctx.tmpSeen[ctx.tmpId] and not ctx.tmpOwned[ctx.tmpId] and it.NotForSale ~= true and it.notForSale ~= true and ctx.tmpCat ~= "Currency" and ctx.tmpCat ~= "Gamepasses" and ctx.tmpSpent + ctx.tmpPrice <= ctx.tmpBudget then
    				ctx.tmpSeen[ctx.tmpId] = true
    				ctx.tmpSpent += ctx.tmpPrice
    				ctx.tmpIds[#ctx.tmpIds + 1] = { id = ctx.tmpId, cat = ctx.tmpCat }
    			end
    		end
    	end
    	return ctx.tmpIds
    end
    
    ctx.buyFemShopCurrency = function(cur)
    	if ctx.opt.shopBusy then
    		return
    	end
    	ctx.opt.shopBusy = true
    	ctx.setBuyCoinBtn()
    	ctx.setBuyGemBtn()
    	ctx.tmpName = cur == 1 and "amethyst" or "coin"
    	local function done(msg)
    		ctx.opt.shopBusy = false
    		ctx.setBuyCoinBtn()
    		ctx.setBuyGemBtn()
    		if msg then
    			ctx.note(msg)
    		end
    	end
    	ctx.tmpPurchase = ctx.femEvent("PurchaseItem", "RemoteFunction")
    	if not ctx.tmpPurchase then
    		done("FEM PurchaseItem remote not found.")
    		return
    	end
    	ctx.tmpIds = ctx.femShopBuyIds(cur)
    	if #ctx.tmpIds < 1 then
    		done("No affordable FEM " .. ctx.tmpName .. " shop items found.")
    		return
    	end
    	ctx.tmpBought = 0
    	for _, it in ctx.tmpIds do
    		ctx.tmpOk, ctx.tmpRes = pcall(function()
    			return ctx.tmpPurchase:InvokeServer(it.id, cur == 1 and 2 or 1, nil, it.cat)
    		end)
    		if ctx.tmpOk and ctx.tmpRes == true then
    			ctx.tmpBought += 1
    		end
    		task.wait(0.08)
    	end
    	done(("Sent %d FEM %s purchase%s"):format(ctx.tmpBought, ctx.tmpName, ctx.tmpBought == 1 and "" or "s"))
    end
    
    ctx.patchFemRopeData = function(data)
    	if type(data) ~= "table" then
    		return false
    	end
    	ctx.cache.femRopeData = data
    	ctx.tmpTarget = tonumber(ctx.opt.zipSpeed) or 0
    	for _, rope in data do
    		if type(rope) == "table" and type(rope[2]) == "table" then
    			if ctx.cache.femRopeOld[rope] == nil then
    				ctx.cache.femRopeOld[rope] = tonumber(rope[3]) or 40
    			end
    			if ctx.opt.zipAutoOn and ctx.opt.zipFastOn and ctx.tmpTarget > 0 then
    				ctx.tmpBase = ctx.cache.femRopeOld[rope] or tonumber(rope[3]) or 40
    				rope[3] = math.clamp(ctx.tmpBase * 40 / math.max(ctx.tmpTarget, 1), 1, 200)
    			else
    				rope[3] = ctx.cache.femRopeOld[rope] or rope[3]
    			end
    		end
    	end
    	return true
    end
    
    ctx.startFemZipPatch = function()
    	if ctx.cache.femZipStarted then
    		return
    	end
    	ctx.cache.femZipStarted = true
    	ctx.tmpRope = ctx.femEvent("UpdRopeData", "RemoteEvent")
    	if ctx.tmpRope then
    		ctx.bind(ctx.tmpRope.OnClientEvent:Connect(function(data)
    			task.defer(ctx.patchFemRopeData, data)
    		end))
    	end
    end
    
    ctx.femSetZip = function(st)
    	ctx.startFemZipPatch()
    	if ctx.cache.femRopeData then
    		ctx.patchFemRopeData(ctx.cache.femRopeData)
    	end
    end
    
    ctx.startFemZipStop = function()
    	if ctx.cache.femZipStopStarted or not LP then
    		return
    	end
    	ctx.cache.femZipStopStarted = true
    	ctx.cache.zipStateSource = "attribute"
    	ctx.cache.femZipLast = LP:GetAttribute("Ziplining") == true
    	ctx.opt.zipActive = ctx.cache.femZipLast
    	ctx.bind(LP:GetAttributeChangedSignal("Ziplining"):Connect(function()
    		ctx.tmpZipState = LP:GetAttribute("Ziplining") == true
    		ctx.cache.zipStateSource = "attribute"
    		ctx.opt.zipActive = ctx.tmpZipState
    		if ctx.tmpZipState then
    			ctx.cache.zipDismountToken = (ctx.cache.zipDismountToken or 0) + 1
    		elseif ctx.cache.femZipLast then
    			ctx.finishZipDismount()
    		end
    		ctx.cache.femZipLast = ctx.tmpZipState
    	end))
    end
    
    ctx.startFemButtonCache = function()
    	if ctx.cache.femBtnStarted then
    		return
    	end
    	ctx.cache.femBtnStarted = true
    	ctx.tmpSet = ctx.femEvent("SetButtonLocator", "RemoteEvent")
    	if ctx.tmpSet then
    		ctx.bind(ctx.tmpSet.OnClientEvent:Connect(function(goal, hit, ui)
    			if hit and typeof(hit) == "Instance" and hit:IsA("BasePart") and ctx.buttonHitAllowed(hit, ctx.curMap()) then
    				ctx.cache.femButtonPart = hit
    			elseif hit and typeof(hit) == "Instance" and hit:IsA("BasePart") and (tostring(hit.Name) == "AirTank" or (hit.Parent and tostring(hit.Parent.Name) == "AirTank")) then
    				ctx.cache.femButtonPart = nil
    			end
    		end))
    	end
    end
    
    ctx.hideIcon = function(field)
    	ctx.tmpIcon = ctx.ui[field]
    	if not ctx.tmpIcon then
    		return
    	end
    	for i = #ctx.ui.menu, 1, -1 do
    		if ctx.ui.menu[i] == ctx.tmpIcon then
    			table.remove(ctx.ui.menu, i)
    		end
    	end
    	pcall(function()
    		if type(ctx.tmpIcon.destroy) == "function" then
    			ctx.tmpIcon:destroy()
    		elseif type(ctx.tmpIcon.Destroy) == "function" then
    			ctx.tmpIcon:Destroy()
    		end
    	end)
    	ctx.ui[field] = nil
    end
    
    ctx.applyProfileUi = function()
    	if ctx.isRetroGame() then
    		for _, field in { "bonusBtn", "chBtn", "floodBtn", "fpPartBtn", "rescueBtn", "devBtn", "zipBtn", "zipStopBtn", "zipAutoBtn", "femVoteBtn" } do
    			ctx.hideIcon(field)
    		end
    	elseif ctx.isFEMGame() then
    		for _, field in { "bonusBtn", "chBtn", "floodBtn", "clipBtn", "fpPartBtn", "rescueBtn", "devBtn", "surviveBtn" } do
    			ctx.hideIcon(field)
    		end
    	elseif ctx.isFE2Game() then
    		ctx.hideIcon("femVoteBtn")
    	end
    end
    
    do
    	local oldSetZipAttrs = ctx.setZipAttrs
    	ctx.setZipAttrs = function(st)
    		if ctx.isFEMGame() then
    			return ctx.femSetZip(st)
    		end
    		return oldSetZipAttrs(st)
    	end
    	local oldHookZipStop = ctx.hookZipStop
    	ctx.hookZipStop = function(c)
    		oldHookZipStop(c)
    		if ctx.isFEMGame() then
    			ctx.startFemZipStop()
    		end
    	end
    	local oldFemLocatorHit = ctx.femLocatorHit
    	ctx.femLocatorHit = function()
    		ctx.startFemButtonCache()
    		ctx.tmpBtn = ctx.cache.femButtonPart
    		if ctx.tmpBtn and ctx.tmpBtn.Parent and ctx.buttonHitAllowed(ctx.tmpBtn, ctx.curMap()) then
    			return ctx.tmpBtn
    		end
    		return nil
    	end
    end
    
    ctx.mkUi = function()
    	ctx.topbar = ctx.loadTopbar()
    	if type(ctx.topbar) ~= "table" or type(ctx.topbar.new) ~= "function" then
    		ctx.note("Topbar loader failed")
    		return
    	end
    	ctx.ui.menu = {}
    	ctx.ui.rootIcon = ctx.topbar.new()
    	ctx.ui.rootIcon:setName(ctx.helperIconName())
    	ctx.ui.rootIcon:setLabel(ctx.helperTitle())
    	ctx.ui.rootIcon:setImage(6031280882)
    	ctx.ui.rootIcon:align("Center")
    	ctx.ui.rootIcon:setOrder(50)
    	ctx.ui.startBtn = ctx.icon("Start", "Start AutoFarm", function()
    		ctx.toggle(not on)
    	end, Color3.fromRGB(60, 180, 60))
    	ctx.ui.auraBtn = ctx.icon("Aura", "Button Aura: OFF", function()
    		auraOn = not auraOn
    		ctx.setAuraBtn()
    		ctx.saveSoon()
    	end)
    	ctx.ui.distModeBtn = ctx.icon("AuraDistance", "Button Distance: ON", function()
    		auraUseDistance = not auraUseDistance
    		ctx.setDistModeBtn()
    		ctx.saveSoon()
    	end, Color3.fromRGB(60, 130, 210))
    	ctx.ui.distBtn = ctx.icon("AuraDist", "Aura Dist: 7", ctx.openAuraPrompt, Color3.fromRGB(55, 55, 55))
    	ctx.ui.bonusBtn = ctx.icon("Bonuses", "Collect Bonuses: ON", function()
    		autoCollectBonuses = not autoCollectBonuses
    		ctx.setBonusBtn()
    		ctx.saveSoon()
    	end, Color3.fromRGB(60, 130, 210))
    	ctx.ui.chBtn = ctx.icon("Challenges", "Challenge Manager: OFF", function()
    		autoChallenges = not autoChallenges
    		ctx.setChallengeBtn()
    		ctx.saveSoon()
    	end)
    	ctx.ui.floodBtn = ctx.icon("CustomFlood", "Custom Flood: ON", function()
    		ctx.opt.floodOn = not ctx.opt.floodOn
    		ctx.setFloodBtn()
    		ctx.saveSoon()
    		ctx.floodPush()
    	end, Color3.fromRGB(60, 130, 210))
    	ctx.ui.paidBtn = ctx.icon("PaidLocks", "Paid UI Locks: ON", function()
    		ctx.opt.paidOn = not ctx.opt.paidOn
    		ctx.setPaidBtn()
    		ctx.saveSoon()
    		if ctx.opt.paidOn then
    			ctx.patchPaidUi()
    		end
    	end, Color3.fromRGB(60, 130, 210))
    	ctx.ui.buyCoinBtn = ctx.icon("BuyCoin", "Buy Coin Shop Items", function()
    		ctx.spawnLoop(ctx.buyShopCurrency, 0)
    	end, Color3.fromRGB(218, 165, 32))
    	ctx.ui.buyGemBtn = ctx.icon("BuyGem", "Buy Gem Shop Items", function()
    		ctx.spawnLoop(ctx.buyShopCurrency, 1)
    	end, Color3.fromRGB(142, 68, 173))
    	ctx.ui.clipBtn = ctx.icon("NoSideClip", "Side-Clip Rollback: GAME", function()
    		ctx.opt.clipOn = not ctx.opt.clipOn
    		ctx.setClipBtn()
    		ctx.saveSoon()
    		ctx.patchSideClip()
    	end)
    	ctx.ui.fpPartBtn = ctx.icon("FirstPersonFx", "First-Person FX: GAME", function()
    		ctx.opt.fpPartOn = not ctx.opt.fpPartOn
    		ctx.setFpPartBtn()
    		ctx.saveSoon()
    		ctx.patchFpParts()
    	end, Color3.fromRGB(110, 85, 170))
    	ctx.ui.rescueBtn = ctx.icon("HideRescue", "Rescue Visual: GAME", function()
    		ctx.opt.rescueOn = not ctx.opt.rescueOn
    		ctx.setRescueBtn()
    		ctx.saveSoon()
    		ctx.patchRescue()
    	end)
    	ctx.ui.zipBtn = ctx.icon("ZiplineSpeed", "Zip Speed: OFF", ctx.openZipPrompt)
    	ctx.ui.zipStopBtn = ctx.icon("ZipStopVelocity", "Zip Stop Velocity: ON", function()
    		ctx.opt.zipStopOn = not ctx.opt.zipStopOn
    		ctx.setZipStopBtn()
    		ctx.saveSoon()
    	end)
    	ctx.ui.zipAutoBtn = ctx.icon("ZipAutoApply", "Zip Auto Apply: ON", function()
    		ctx.opt.zipAutoOn = not ctx.opt.zipAutoOn
    		ctx.cache.zipDismountToken = (ctx.cache.zipDismountToken or 0) + 1
    		ctx.setZipAutoBtn()
    		ctx.setZipBtn()
    		ctx.setZipStopBtn()
    		ctx.setZipAttrs(ctx.opt.zipAutoOn and ctx.opt.zipFastOn)
    		ctx.saveSoon()
    	end)
    	ctx.ui.devBtn = ctx.icon("DevTools", "DevTools: OFF", function()
    		ctx.setDevTools(not ctx.opt.devOn)
    		ctx.saveSoon()
    	end)
    	ctx.ui.infAirBtn = ctx.icon("InfAir", "Inf Air: OFF", function()
    		ctx.opt.infAirOn = not ctx.opt.infAirOn
    		ctx.setInfAirBtn()
    		ctx.saveSoon()
    		if ctx.opt.infAirOn then
    			ctx.keepAirFast()
    		else
    			ctx.unprotectAirHealth()
    		end
    		ctx.fireGod(ctx.opt.infAirOn)
    	end)
    	ctx.ui.infJumpBtn = ctx.icon("InfJump", "Inf Jump: OFF", function()
    		ctx.opt.infJumpOn = not ctx.opt.infJumpOn
    		ctx.setInfJumpBtn()
    		ctx.saveSoon()
    	end)
    	ctx.ui.clickTpBtn = ctx.icon("ClickTP", "Click TP: OFF", function()
    		ctx.opt.clickTpOn = not ctx.opt.clickTpOn
    		ctx.setClickTpBtn()
    		ctx.saveSoon()
    	end)
    	ctx.ui.femVoteBtn = ctx.icon("FemAutoVote", "FEM Auto Vote: OFF", function()
    		ctx.opt.femVoteOn = not ctx.opt.femVoteOn
    		ctx.setFemVoteBtn()
    		ctx.saveSoon()
    		if ctx.opt.femVoteOn then
    			ctx.startFemAutoVote()
    		end
    	end, Color3.fromRGB(44, 160, 110))
    	ctx.ui.surviveBtn = ctx.icon("SurvivedLoop", "Survived Loop: ON", function()
    		ctx.opt.surviveLoopOn = not ctx.opt.surviveLoopOn
    		ctx.setSurviveBtn()
    		ctx.saveSoon()
    	end, Color3.fromRGB(80, 150, 220))
    	ctx.ui.nextBtn = ctx.icon("NextButton", "Next Button", function()
    		ctx.fireNextButton()
    	end, Color3.fromRGB(55, 90, 150))
    	ctx.applyProfileUi()
    	ctx.ui.rootIcon:setDropdown(ctx.ui.menu)
    	if ctx.compatibility.degraded and not ctx.cache.compatibilityNoticeShown then
    		ctx.cache.compatibilityNoticeShown = true
    		task.defer(ctx.note, (ctx.isFE2CMGame() and "FE2CM compatibility mode active: using module, BindableEvent, property, and semantic remote fallbacks" or "Compatibility mode active: advanced executor hooks are unavailable; FE2 module, event, property, and remote fallbacks are being used"))
    	end
    	ctx.setBtn()
    	ctx.setAuraBtn()
    	ctx.setDistModeBtn()
    	ctx.setDistBtn()
    	ctx.setBonusBtn()
    	ctx.setChallengeBtn()
    	ctx.setFloodBtn()
    	ctx.setPaidBtn()
    	ctx.setBuyCoinBtn()
    	ctx.setBuyGemBtn()
    	ctx.setClipBtn()
    	ctx.setFpPartBtn()
    	ctx.setRescueBtn()
    	ctx.setDevBtn()
    	ctx.setZipBtn()
    	ctx.setZipStopBtn()
    	ctx.setZipAutoBtn()
    	ctx.setInfAirBtn()
    	ctx.setInfJumpBtn()
    	ctx.setClickTpBtn()
    	ctx.setFemVoteBtn()
    	ctx.setSurviveBtn()
    end
    
    -- Embedded in Flood GUI: the main GUI owns the UI.
    -- ctx.mkUi() intentionally suppressed to avoid a second standalone menu.
    ctx.startPassiveRemotes()
    ctx.startButtonAura()
    if ctx.support("bonus") then
    	ctx.startBonusCollector()
    end
    if ctx.support("challenges") then
    	ctx.startChallenges()
    end
    if ctx.support("flood") then
    	ctx.startFloodColors()
    end
    ctx.startUiUnlocks()
    ctx.startFeOptionManagers()
    ctx.startPhysicsOptions()
    if ctx.support("femVote") then
    	ctx.startFemAutoVote()
    end
    if ctx.isFEMGame() then
    	ctx.startFemButtonCache()
    	ctx.startFemZipPatch()
    	ctx.startFemZipStop()
    end
    if LP and LP.Character then
    	ctx.hookZipStop(LP.Character)
    end
    if ctx.opt.zipFastOn and ctx.opt.zipAutoOn then
    	task.defer(ctx.reapplyZipSpeed)
    end
    
    if LP then
    	chC = LP.CharacterAdded:Connect(ctx.onChar)
    	if LP.Character then
    		ctx.spawnLoop(ctx.onChar, LP.Character)
    	end
    end
    
    ctx.antiVoid(ctx.curMap)
    ctx.note("Ready [" .. ctx.profileName() .. "]")
    
    ctx.spawnLoop(function()
    	while ctx.alive() do
    		local ok, err = xpcall(function()
    			task.wait(SCI)
    			if not on then
    				return
    			end
    			local m = ctx.curMap()
    			local ig = ctx.inState("InGame")
    			if m and ig and m ~= cur then
    				cur = m
    				tok += 1
    				local id = tok
    				ctx.note("New Map")
    				ctx.onMap(m, id)
    			elseif not m or not ig then
    				cur = nil
    			end
    		end, __traceback)
    
    		if not ok then
    			warn(err)
    			ctx.note("Loop error; continuing")
    			task.wait(0.25)
    		end
    	end
    end)
    
    -- Flood GUI integration bridge: expose backend controls without creating a second UI.
    ctx._embedded = true
    ctx.setFloodGuiFeature = function(name, value)
        value = value == true
        if name == "autofarm" then
            ctx.toggle(value)
        elseif name == "auraOn" then
            auraOn = value
            ctx.setAuraBtn()
        elseif name == "auraUseDistance" then
            auraUseDistance = value
            ctx.setDistModeBtn()
        elseif name == "autoCollectBonuses" then
            autoCollectBonuses = value
            ctx.setBonusBtn()
        elseif name == "autoChallenges" then
            autoChallenges = value
            ctx.setChallengeBtn()
        elseif name == "floodOn" then
            ctx.opt.floodOn = value
            ctx.setFloodBtn()
            ctx.floodPush()
        elseif name == "paidOn" then
            ctx.opt.paidOn = value
            ctx.setPaidBtn()
            if value then ctx.patchPaidUi() end
        elseif name == "clipOn" then
            ctx.opt.clipOn = value
            ctx.setClipBtn()
            ctx.patchSideClip()
        elseif name == "fpPartOn" then
            ctx.opt.fpPartOn = value
            ctx.setFpPartBtn()
            ctx.patchFpParts()
        elseif name == "rescueOn" then
            ctx.opt.rescueOn = value
            ctx.setRescueBtn()
            ctx.patchRescue()
        elseif name == "devOn" then
            ctx.setDevTools(value)
        elseif name == "zipAutoOn" then
            ctx.opt.zipAutoOn = value
            ctx.cache.zipDismountToken = (ctx.cache.zipDismountToken or 0) + 1
            ctx.setZipAutoBtn(); ctx.setZipBtn(); ctx.setZipStopBtn()
            ctx.setZipAttrs(ctx.opt.zipAutoOn and ctx.opt.zipFastOn)
        elseif name == "zipStopOn" then
            ctx.opt.zipStopOn = value
            ctx.setZipStopBtn()
        elseif name == "zipFastOn" then
            ctx.opt.zipFastOn = value
            ctx.setZipBtn()
            ctx.setZipAttrs(ctx.opt.zipAutoOn and ctx.opt.zipFastOn)
            if value then task.defer(ctx.reapplyZipSpeed) end
        elseif name == "infAirOn" then
            ctx.opt.infAirOn = value
            ctx.setInfAirBtn()
            if value then ctx.keepAirFast() else ctx.unprotectAirHealth() end
            ctx.fireGod(value)
        elseif name == "infJumpOn" then
            ctx.opt.infJumpOn = value
            ctx.setInfJumpBtn()
        elseif name == "clickTpOn" then
            ctx.opt.clickTpOn = value
            ctx.setClickTpBtn()
        elseif name == "femVoteOn" then
            ctx.opt.femVoteOn = value
            ctx.setFemVoteBtn()
            if value then ctx.startFemAutoVote() end
        elseif name == "surviveLoopOn" then
            ctx.opt.surviveLoopOn = value
            ctx.setSurviveBtn()
        elseif name == "fePhysicsOn" then
            ctx.opt.fePhysicsOn = value
        elseif name == "floodEnabled" or name == "floodRandom" then
            ctx.opt[name] = value
            ctx.floodPush()
        end
        ctx.saveSoon()
    end
    ctx.getFloodGuiSetting = function(name)
        return ctx.getSetting(name)
    end
    ctx.floodGuiBuyCoins = function() ctx.spawnLoop(ctx.buyShopCurrency, 0) end
    ctx.floodGuiBuyGems = function() ctx.spawnLoop(ctx.buyShopCurrency, 1) end
    ctx.floodGuiNextButton = function() return ctx.fireNextButton() end
    ctx.floodGuiSetAuraDist = function(v)
        auraDist = math.max(0, tonumber(v) or auraDist)
        ctx.setDistBtn()
        ctx.saveSoon()
    end
    ctx.floodGuiSetZipSpeed = function(v)
        local n = tonumber(v)
        if n then
            ctx.opt.zipSpeed = math.max(0, n)
            ctx.setZipBtn()
            if ctx.opt.zipFastOn then task.defer(ctx.reapplyZipSpeed) end
            ctx.saveSoon()
        end
    end
    ctx.floodGuiStatus = function()
        return {
            farm = on,
            aura = auraOn,
            auraUseDistance = auraUseDistance,
            auraDist = auraDist,
            bonuses = autoCollectBonuses,
            challenges = autoChallenges,
            flood = ctx.opt.floodOn,
            paid = ctx.opt.paidOn,
            clip = ctx.opt.clipOn,
            fp = ctx.opt.fpPartOn,
            rescue = ctx.opt.rescueOn,
            dev = ctx.opt.devOn,
            zipFast = ctx.opt.zipFastOn,
            zipSpeed = ctx.opt.zipSpeed,
            zipStop = ctx.opt.zipStopOn,
            zipAuto = ctx.opt.zipAutoOn,
            infAir = ctx.opt.infAirOn,
            infJump = ctx.opt.infJumpOn,
            clickTp = ctx.opt.clickTpOn,
            femVote = ctx.opt.femVoteOn,
            survive = ctx.opt.surviveLoopOn,
            floodEnabled = ctx.opt.floodEnabled,
            floodRandom = ctx.opt.floodRandom,
            fePhysics = ctx.opt.fePhysicsOn,
        }
    end
    
    getgenv().FloodGUI_Fe2Ctx = ctx
    
    end)
    getgenv().FloodGUI_Fe2BackendOk = __backendOk
    getgenv().FloodGUI_Fe2BackendError = __backendErr
    if not __backendOk then
        warn("[Flood GUI] FE2 backend failed to initialize:", __backendErr)
    end
end

-- ==============================================================================
-- [9] USER INTERFACE (KAVO)
-- ==============================================================================
local function InitializeUI()
    local source = game:HttpGet(CONFIG.UI_LIBRARY)
    local Kavo = loadstring(source)()
    local Window = Kavo.CreateLib("Flood GUI v4", KAVO_THEME)


    -- FE2 backend bridge: one GUI, distributed controls.
    local function Fe2Ctx()
        return getgenv().FloodGUI_Fe2Ctx
    end
    local function Fe2Set(name, value)
        local c = Fe2Ctx()
        if not c or type(c.setFloodGuiFeature) ~= "function" then
            Alert("FE2 backend unavailable: " .. tostring(getgenv().FloodGUI_Fe2BackendError or "unknown error"), "Error")
            return false
        end
        local ok, err = pcall(c.setFloodGuiFeature, name, value)
        if not ok then
            Alert("FE2 feature error: " .. tostring(err), "Error")
            return false
        end
        return true
    end
    local function Fe2Action(fn, unavailableMsg)
        local c = Fe2Ctx()
        if not c or type(fn) ~= "function" then
            Alert(unavailableMsg or "FE2 backend unavailable.", "Error")
            return false
        end
        local ok, err = pcall(fn, c)
        if not ok then
            Alert("FE2 feature error: " .. tostring(err), "Error")
            return false
        end
        return true
    end

    Config.HookWindow(Window)
    
    local tasTab = Window:NewTab("TAS")
    
    local stealthSec = tasTab:NewSection("Auto-Play (Stealth Farm)")
    stealthSec:NewToggle("Enable Auto-Play", "Automatically downloads & plays TAS files.", function(state)
        State.AutoPlay = state
        if state then getgenv().TAS_ManualStop = false end
        Alert("Auto-Play (Stealth) " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)
    
    stealthSec:NewToggle("Fallback to Blatant Farm", "[NOT RECOMMENDED] Farm manually if TAS is missing.", function(state)
        State.FallbackToFarm = state
        Alert("TAS Fallback " .. (state and "Enabled" or "Disabled"), "Warning")
    end)

    stealthSec:NewTextBox("TAS Speed", "1 = Normal | 0.5 = 2x Faster | 0.25 = 4x Faster | 2 = Slower", function(txt)
        local num = tonumber(txt)
        if num and num > 0 then
            State.TASSpeed = num
            Alert("TAS Speed set to: " .. num, "Info")
        else
            Alert("Invalid number! Use e.g. 1, 0.5, 0.25, 2", "Error")
        end
    end)

    local tasSec = tasTab:NewSection("TAS Manager & Sniping")
    tasSec:NewDropdown("Operation Mode", "What to do on target maps.", {"Farm", "Play", "Record"}, function(current)
        State.Mode = current
        Alert("Mode set to: " .. current, "Info")
    end)

    tasSec:NewTextBox("Target Map Snipe", "Exact Name (e.g. Sandswept Ruins)", function(txt)
        State.TargetMapName = txt
        Alert("Target map set to: " .. txt, "System")
    end)

    tasSec:NewKeybind("Toggle Swim Mode [TAS]", "Simulate water state for TAS.", Enum.KeyCode.Y, function()
        State.SwimEnabled = not State.SwimEnabled
        Alert("TAS Swim Mode " .. (State.SwimEnabled and "Enabled" or "Disabled"), "Info")
    end)

    tasSec:NewButton("Force Load TAS Player", "Manually inject TAS Player (If joined late).", function()
        getgenv().TAS_ManualStop = false
        StartBuiltInTASPlayer()
    end)

    tasSec:NewButton("STOP TAS (mid-run)", "Fully stops the TAS and gives control back.", function()
        if getgenv().TAS_Stop then
            pcall(getgenv().TAS_Stop)
        elseif getgenv().IsTASPlaying then
            getgenv().IsTASPlaying = false
            getgenv().TASPaused = false
            getgenv().TAS_ManualStop = true
            if getgenv().TAS_RestoreAnim then
                pcall(getgenv().TAS_RestoreAnim)
                getgenv().TAS_RestoreAnim = nil
            end
            if getgenv().TASConnections then
                for _, c in pairs(getgenv().TASConnections) do
                    if c then pcall(function() c:Disconnect() end) end
                end
                getgenv().TASConnections = {}
            end
            DestroyPauseButton()
            Alert("TAS stopped.", "Success")
        else
            Alert("No TAS is running.", "Warning")
        end
    end)

    tasSec:NewButton("Create TAS", "Launch TAS Creator script immediately.", function()
        LoadExternalScript(CONFIG.TAS_CREATOR_URL)
    end)

    tasSec:NewButton("Toggle Pause (or press P)", "Pause/Resume the current TAS run.", function()
        TogglePauseManual()
    end)

    tasSec:NewButton("Load Infinite Yield", "Loads Infinite Yield Admin Script", function()
        LoadExternalScript("https://raw.githubusercontent.com/edgeiy/infiniteyield/master/source")
        Alert("Infinite Yield Loaded.", "Info")
    end)

    local tasLibSec = tasTab:NewSection("TAS Library")
    local tasCountLabel = tasLibSec:NewLabel("TAS files: not loaded yet")
    local tasMapLabel = tasLibSec:NewLabel("Current map: waiting for a round...")
    local tasMapDropdown = tasLibSec:NewDropdown("Available TAS Maps", "Pick a map to set it as the snipe target.", {"(press Refresh)"}, function(current)
        if type(current) == "string" and current:sub(1, 1) ~= "(" then
            State.TargetMapName = current
            Alert("Target map set to: " .. current, "System")
        end
    end)

    local function RefreshTasLibrary()
        local ok, result = TasLibrary.Refresh()
        if ok then
            pcall(function() tasCountLabel:UpdateLabel("TAS files: " .. tostring(result) .. " maps") end)
            pcall(function() tasMapDropdown:Refresh(TasLibrary.Maps) end)
            Alert("TAS library loaded: " .. tostring(result) .. " maps.", "Success")
        else
            pcall(function() tasCountLabel:UpdateLabel("TAS files: load failed") end)
            Alert("TAS list failed: " .. tostring(result), "Error")
        end
    end

    tasLibSec:NewButton("Refresh TAS List", "Fetches the available TAS files from GitHub.", function()
        task.spawn(RefreshTasLibrary)
    end)

    TasLibrary.OnMapChanged = function(mapName, has, benched)
        pcall(function()
            tasMapLabel:UpdateLabel("Current map: " .. mapName .. " | TAS: " .. (benched and "BENCHED" or (has and "YES" or "NO")))
        end)
    end

    task.spawn(RefreshTasLibrary)

    local runSec = tasTab:NewSection("Run Tracking")

    runSec:NewTextBox("Skip TAS After N Fails", "In a row, per map. 0 = never skip. Default 3. Retried after 60 min.", function(txt)
        local num = tonumber(txt)
        if num and num >= 0 then
            State.MaxTasFails = math.floor(num)
            Alert(State.MaxTasFails == 0 and "TAS skipping disabled." or ("TAS skipped after " .. State.MaxTasFails .. " fails in a row."), "Info")
        else
            Alert("Enter 0 or a positive whole number.", "Error")
        end
    end)

    runSec:NewButton("Show Failing Maps", "Lists maps whose TAS has failed.", function()
        local list = RunStats.FailingSummary()
        if #list == 0 then
            Alert("No TAS failures recorded.", "Success")
            return
        end
        for i = 1, math.min(#list, 5) do
            local item = list[i]
            Alert(string.format("%s: %d fails / %d ok (streak %d, last: %s)", item.name, item.rec.fail, item.rec.ok, item.rec.streak, item.rec.lastReason), "Warning")
        end
    end)

    runSec:NewButton("Reset Run Stats", "Clears all recorded TAS successes and failures.", function()
        RunStats.Reset()
    end)

    local autoTab = Window:NewTab("Auto Farm")
    local mainSec = autoTab:NewSection("Blatant Auto Farm Options")
    
    mainSec:NewToggle("Enable Auto-Farm", "Quick farm: presses buttons through remotes and escapes instantly.", function(state)
        State.AutoFarm = state
        getgenv().TomatoAutoFarm = state
        Alert("Blatant Auto Farm " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)
    
    mainSec:NewToggle("Auto Collect (Page-Escapee)", "V3 Touch — works anytime on map.", function(state)
        State.AutoCollect = state
        Alert("Auto Collect " .. (state and "Enabled (anytime)" or "Disabled"), "Info")
    end)
    
    mainSec:NewToggle("Auto Rebirth", "Rebirths as soon as you qualify (Lv 100+ with enough XP). If your data can't be read, tries every 60s.", function(state)
        State.AutoRebirth = state
        Alert("Auto Rebirth " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)
    
    mainSec:NewDropdown("Max Difficulty Level", "Skip maps harder than this.", {"None", "Crazy+", "Crazy", "Insane", "Hard", "Normal", "Easy"}, function(current)
        State.TargetDifficulty = current
        Alert("Max Difficulty set to: " .. current, "System")
    end)

    mainSec:NewToggle("Enforce Difficulty Limiter", "Suicides to skip if map is too hard.", function(state)
        State.EnforceDifficulty = state
        Alert("Difficulty Limiter " .. (state and "Enabled" or "Disabled"), "Info")
    end)

    local fe2AutoSec = autoTab:NewSection("FE2 Extra Automation")

    fe2AutoSec:NewButton("Next Button", "Trigger the FE2 backend's next-button action.", function()
        Fe2Action(function(c) c.floodGuiNextButton() end)
    end)

    fe2AutoSec:NewToggle("Collect Bonuses", "Collect map bonuses using the FE2 backend.", function(state)
        Fe2Set("autoCollectBonuses", state)
    end)

    fe2AutoSec:NewToggle("Survived Loop", "Enable the FE2 survived-event loop.", function(state)
        Fe2Set("surviveLoopOn", state)
    end)

    local qfSec = autoTab:NewSection("Quick Farm Options")

    qfSec:NewToggle("Fast Load", "Skips the map loading delay and screens.", function(state)
        State.FastLoad = state
        getgenv().FloodGUI_FastLoad = state
        Alert("Fast Load " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    qfSec:NewToggle("Enable God Mode", "Uses the FE2 Infinite Air script as God Mode.", function(state)
        State.GodMode = state
        Fe2Set("infAirOn", state)
        Alert("God Mode " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    qfSec:NewToggle("Play after Buttons (No Escape)", "Presses every button, then returns you to spawn without escaping.", function(state)
        State.PlayAfterButtons = state
        Alert("Play after Buttons " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    qfSec:NewToggle("Reset after Escape", "Resets your character after escaping.", function(state)
        State.ResetAfterEscape = state
        Alert("Reset after Escape " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    qfSec:NewSlider("Autofarm Start Delay", "Seconds to wait after the map loads.", 30, 0, function(value)
        State.StartDelay = value
    end)

    qfSec:NewSlider("Reset Delay", "Seconds to wait before resetting after an escape.", 10, 0, function(value)
        State.ResetDelay = value
    end)

    qfSec:NewToggle("Cycle Challenges (10 Min Blind)", "Cycles your daily challenges every 10 minutes.", function(state)
        State.CycleChallenges = state
        Alert("Cycle Challenges " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    local lobbyTab = Window:NewTab("Lobby")
    local boostSec = lobbyTab:NewSection("Boosts & Events")

    boostSec:NewToggle("Auto Boost (20 Gems)", "Automatically sends full boosts at round start.", function(state)
        State.AutoBoost = state
        Alert("Auto Boost " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    boostSec:NewButton("Manual Full Boost (20 Gems)", "Sends one-time manual boost requests.", function()
        Lobby.FullBoost()
    end)

    boostSec:NewToggle("Auto Double Map Event (15 Gems)", "Automatically adds two events during voting.", function(state)
        State.AutoEvent = state
        Alert("Auto Double Map Event " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    boostSec:NewButton("Manual Double Map Event (15 Gems)", "Instantly adds 2 events.", function()
        Lobby.DoubleMapEvent()
    end)

    local fe2LobbySec = lobbyTab:NewSection("FE2 Flood / Shop")

    fe2LobbySec:NewToggle("Custom Flood", "Enable the FE2 backend custom-flood feature.", function(state)
        Fe2Set("floodOn", state)
    end)

    fe2LobbySec:NewToggle("Flood Enabled", "Enable or disable the custom flood color system.", function(state)
        Fe2Set("floodEnabled", state)
    end)

    fe2LobbySec:NewToggle("Random Flood", "Use the backend random flood-color mode.", function(state)
        Fe2Set("floodRandom", state)
    end)

    fe2LobbySec:NewToggle("Paid UI Locks", "Enable the backend paid-UI lock patch.", function(state)
        Fe2Set("paidOn", state)
    end)

    fe2LobbySec:NewButton("Buy Coin Shop Items", "Run the backend coin-shop purchase routine.", function()
        Fe2Action(function(c) c.floodGuiBuyCoins() end)
    end)

    fe2LobbySec:NewButton("Buy Gem Shop Items", "Run the backend gem-shop purchase routine.", function()
        Fe2Action(function(c) c.floodGuiBuyGems() end)
    end)

    local tpSec = lobbyTab:NewSection("Teleports")

    tpSec:NewToggle("Auto TP to Secret Room", "Teleports your character to the safe room on spawn.", function(state)
        State.AutoTeleport = state
        Alert("Auto TP to Secret Room " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
        if state and LocalPlayer.Character then
            task.spawn(Lobby.TeleportToSecretRoom, LocalPlayer.Character)
        end
    end)

    tpSec:NewButton("Manual TP to Secret Room", "Teleports to the safe area once.", function()
        local char = GetChar()
        local rootpart = char and char:FindFirstChild("HumanoidRootPart")
        if rootpart then
            rootpart.CFrame = SAFE_ROOM_CFRAME
        end
    end)

    local automationTab = Window:NewTab("Automation")
    local votingSec = automationTab:NewSection("Voting")

    votingSec:NewToggle("Auto Open Voting", "Opens the voting screen remotely.", function(state)
        State.AutoVoting = state
        if state then
            Alert("Auto Voting Enabled.", "Success")
        else
            Alert("Auto Voting Disabled.", "Info")
            local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
            local gameGui = playerGui and playerGui:FindFirstChild("GameGui")
            local waiting = gameGui and gameGui:FindFirstChild("Waiting")
            local clWaiting = waiting and waiting:FindFirstChild("CL_Waiting")
            local isVotingEvent = clWaiting and clWaiting:FindFirstChild("IsVoting")
            if isVotingEvent then
                isVotingEvent:Fire(false)
            end
        end
    end)

    local fe2AutomationSec = automationTab:NewSection("FE2 Automation")

    fe2AutomationSec:NewToggle("Challenge Manager", "Enable automatic challenge handling from the FE2 backend.", function(state)
        Fe2Set("autoChallenges", state)
    end)

    fe2AutomationSec:NewToggle("FEM Auto Vote", "Enable automatic voting in Flood Escape Maps where supported.", function(state)
        Fe2Set("femVoteOn", state)
    end)

    local voteAutoSec = automationTab:NewSection("Vote Automator")
    local CoinCostLabel = voteAutoSec:NewLabel("Estimated Coin Cost: " .. tostring(Lobby.CalculateCoinCost(State.CustomVoteTarget)) .. " Coins (" .. tostring(State.CustomVoteTarget) .. " votes)")

    voteAutoSec:NewTextBox("Target Vote Amount", "Enter desired vote count", function(text)
        local num = tonumber(text)
        if num and num > 0 then
            State.CustomVoteTarget = num
            local cost = Lobby.CalculateCoinCost(num)
            CoinCostLabel:UpdateLabel("Estimated Coin Cost: " .. tostring(cost) .. " Coins (" .. tostring(num) .. " votes)")
            Alert("Vote amount set to: " .. tostring(num) .. " (Cost: " .. tostring(cost) .. " coins)", "Success")
        else
            State.CustomVoteTarget = 4
            local cost = Lobby.CalculateCoinCost(4)
            CoinCostLabel:UpdateLabel("Estimated Coin Cost: " .. tostring(cost) .. " Coins (4 votes)")
            Alert("Invalid number. Reset vote target to 4.", "Warning")
        end
    end)

    voteAutoSec:NewToggle("Custom Vote Amount", "Auto votes the target vote amount.", function(state)
        State.AutoFullVote = state
        if state then
            Alert("Custom Vote Amount Enabled (" .. tostring(State.CustomVoteTarget) .. " votes).", "Success")
        else
            Alert("Custom Vote Amount Disabled.", "Info")
        end
    end)

    local autoJoinSec = automationTab:NewSection("Auto-Join")

    autoJoinSec:NewTextBox("Target Username", "Enter target player username and press Enter", function(text)
        Lobby.UpdateTargetUserId(text)
    end)

    autoJoinSec:NewDropdown("Server Type", "Select Pro or Normal servers (Default = Pro)", {"Pro", "Normal"}, function(selected)
        State.SelectedPlaceType = selected
        Alert("Server type set to: " .. selected, "Info")
    end)

    autoJoinSec:NewToggle("Auto Teleport Request", "Fires a teleport request every four seconds.", function(state)
        State.AutoReqTele = state
        if state then
            if State.TargetUserId then
                Alert("Auto Teleport Request Enabled.", "Success")
            else
                Alert("Auto Teleport Request Enabled, but no target username is set!", "Warning")
            end
        else
            Alert("Auto Teleport Request Disabled.", "Info")
        end
    end)

    local charTab = Window:NewTab("Local Player")
    local moveSec = charTab:NewSection("Movement Settings")
    
    moveSec:NewSlider("WalkSpeed", "Changes player speed.", 100, 20, function(s)
        State.WalkSpeed = math.max(1, s)
    end)
    
    moveSec:NewSlider("JumpPower", "Changes jump height.", 200, 50, function(s)
        State.JumpPower = math.max(0, s)
    end)

    local fe2ZipSec = charTab:NewSection("FE2 Zipline")

    fe2ZipSec:NewToggle("Zipline Speed", "Enable the FE2 backend zipline speed feature.", function(state)
        Fe2Set("zipFastOn", state)
    end)

    fe2ZipSec:NewTextBox("Zipline Speed", "Speed value used by the backend. No artificial upper limit.", function(txt)
        local c = Fe2Ctx()
        local n = tonumber(txt)
        if c and c.floodGuiSetZipSpeed and n then
            pcall(c.floodGuiSetZipSpeed, n)
        else
            Alert("Enter a valid zipline speed.", "Error")
        end
    end)

    fe2ZipSec:NewToggle("Zipline Auto Apply", "Automatically apply zipline settings when entering a zipline.", function(state)
        Fe2Set("zipAutoOn", state)
    end)

    fe2ZipSec:NewToggle("Zipline Stop Velocity", "Enable the backend zipline stop-velocity behavior.", function(state)
        Fe2Set("zipStopOn", state)
    end)
    
    local blatantTab = Window:NewTab("Blatant")
    local exploitSec = blatantTab:NewSection("Exploits")
    
    exploitSec:NewKeybind("Noclip", "Allows walking through walls.", Enum.KeyCode.G, function()
        State.Noclip = not State.Noclip
        Noclip(State.Noclip)
        Alert("Noclip " .. (State.Noclip and "Enabled" or "Disabled"), State.Noclip and "Success" or "Error")
    end)
    
    exploitSec:NewKeybind("Air Jump", "Allows jumping while mid-air.", Enum.KeyCode.M, function()
        State.AirJump = not State.AirJump
        Alert("Air Jump " .. (State.AirJump and "Enabled" or "Disabled"), State.AirJump and "Success" or "Error")
    end)

    local fe2BlatantSec = blatantTab:NewSection("FE2 Extras")

    fe2BlatantSec:NewToggle("Side-Clip Rollback", "Enable the FE2 side-clip rollback patch.", function(state)
        Fe2Set("clipOn", state)
    end)

    fe2BlatantSec:NewToggle("First-Person FX", "Enable the FE2 first-person effects patch.", function(state)
        Fe2Set("fpPartOn", state)
    end)

    fe2BlatantSec:NewToggle("Rescue Visual", "Enable the FE2 rescue-visual patch.", function(state)
        Fe2Set("rescueOn", state)
    end)

    fe2BlatantSec:NewToggle("DevTools", "Enable the FE2 developer tools.", function(state)
        Fe2Set("devOn", state)
    end)

    local assistSec = blatantTab:NewSection("Assist")

    assistSec:NewToggle("Button Aura", "Presses buttons near you (or the one the game points to) while you play.", function(state)
        State.ButtonAura = state
        if state and not PressedMapButton then
            Alert("Button Aura needs the PressedMapButton remote, which wasn't found yet.", "Warning")
        end
        Alert("Button Aura " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    assistSec:NewToggle("Aura: Use Distance", "On = only press buttons within range. Off = press the game's current target from anywhere.", function(state)
        State.AuraUseDistance = state
    end)

    assistSec:NewTextBox("Aura Distance", "Range in studs. No artificial upper limit.", function(txt)
        local n = tonumber(txt)
        if n and n >= 0 then
            State.AuraDist = n
            local c = Fe2Ctx()
            if c and c.floodGuiSetAuraDist then
                pcall(c.floodGuiSetAuraDist, n)
            end
        else
            Alert("Enter a valid non-negative range.", "Error")
        end
    end)

    assistSec:NewToggle("Anti-Void", "Pulls you back to your last safe spot if you fall into the void.", function(state)
        State.AntiVoid = state
        Alert("Anti-Void " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    assistSec:NewToggle("Click TP", "Ctrl + click (PC) or tap the world (mobile) to teleport there.", function(state)
        State.ClickTP = state
        Alert("Click TP " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    local miscTab = Window:NewTab("Other")
    local utilSec = miscTab:NewSection("Utilities")
    local fe2StatusLabel = utilSec:NewLabel("FE2 backend: checking...")
    task.spawn(function()
        while fe2StatusLabel do
            local ok = getgenv().FloodGUI_Fe2BackendOk
            local c = Fe2Ctx()
            local textValue = ok and "FE2 backend: ready" or ("FE2 backend: failed — " .. tostring(getgenv().FloodGUI_Fe2BackendError or "unknown error"))
            if ok and c and c.floodGuiStatus then
                local st = c.floodGuiStatus()
                textValue = string.format("FE2 backend: ready | Farm %s | Aura %s | Bonuses %s | Challenges %s", st.farm and "ON" or "OFF", st.aura and "ON" or "OFF", st.bonuses and "ON" or "OFF", st.challenges and "ON" or "OFF")
            end
            pcall(function() fe2StatusLabel:UpdateLabel(textValue) end)
            task.wait(3)
        end
    end)

    
    utilSec:NewKeybind("Toggle UI", "Toggles the GUI visibility.", Enum.KeyCode.J, function()
        State.UIEnabled = not State.UIEnabled
        Kavo:ToggleUI()
        Alert("UI " .. (State.UIEnabled and "Enabled" or "Disabled"), "Info")
    end)

    local afkSec = miscTab:NewSection("AFK Mode")

    afkSec:NewToggle("AFK Mode (3D off + low FPS)", "Turns 3D rendering off, caps FPS and shows a stats screen.", function(state)
        if state then Afk.Enable() else Afk.Disable() end
    end)

    afkSec:NewTextBox("AFK FPS Cap", "Frames per second while AFK. Default 15.", function(txt)
        local num = tonumber(txt)
        if num and num >= 1 and num <= 144 then
            State.AfkFps = math.floor(num)
            Alert("AFK FPS cap set to " .. State.AfkFps .. ".", "Info")
            if Afk.Active and type(setfpscap) == "function" then pcall(setfpscap, State.AfkFps) end
        else
            Alert("Enter a number from 1 to 144.", "Error")
        end
    end)

    -- Floating button: tap to hide/show the menu, drag to move it (handy on mobile)
    local floatConns = {}

    local function DestroyFloatingButton()
        for _, c in ipairs(floatConns) do
            pcall(function() c:Disconnect() end)
        end
        floatConns = {}
        if getgenv().FloodGUI_FloatingBtn then
            pcall(function() getgenv().FloodGUI_FloatingBtn:Destroy() end)
            getgenv().FloodGUI_FloatingBtn = nil
        end
    end

    local function CreateFloatingButton()
        DestroyFloatingButton()

        local gui = Instance.new("ScreenGui")
        gui.Name = "FloodGUI_FloatingButton"
        gui.ResetOnSpawn = false
        gui.DisplayOrder = 999
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

        local btn = Instance.new("TextButton")
        btn.Name = "Toggle"
        btn.Size = UDim2.new(0, 46, 0, 46)
        btn.Position = UDim2.new(0, 12, 0.5, -23)
        btn.BackgroundColor3 = Color3.fromRGB(8, 8, 8)
        btn.BackgroundTransparency = 0.15
        btn.Text = "F"
        btn.TextColor3 = Color3.fromRGB(245, 245, 245)
        btn.Font = Enum.Font.GothamBold
        btn.TextSize = 20
        btn.AutoButtonColor = true
        btn.Parent = gui
        Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
        local stroke = Instance.new("UIStroke")
        stroke.Color = Color3.fromRGB(180, 20, 30)
        stroke.Thickness = 2
        stroke.Parent = btn

        local dragging, moved = false, false
        local dragStart, startPos = nil, nil

        btn.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging, moved = true, false
                dragStart, startPos = input.Position, btn.Position
            end
        end)

        floatConns[#floatConns + 1] = TrackConnection(UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseMovement) then
                local delta = input.Position - dragStart
                if delta.Magnitude > 8 then moved = true end
                if moved then
                    btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
                end
            end
        end))

        floatConns[#floatConns + 1] = TrackConnection(UserInputService.InputEnded:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1) then
                dragging = false
                if not moved then
                    State.UIEnabled = not State.UIEnabled
                    pcall(function() Kavo:ToggleUI() end)
                end
            end
        end))

        local parent = (type(gethui) == "function" and gethui()) or CoreGui
        local ok = pcall(function() gui.Parent = parent end)
        if not ok or not gui.Parent then
            pcall(function() gui.Parent = LocalPlayer:WaitForChild("PlayerGui") end)
        end
        getgenv().FloodGUI_FloatingBtn = gui
    end

    utilSec:NewToggle("Floating UI Button", "Shows a draggable button that hides/shows this menu.", function(state)
        State.FloatingButton = state
        if state then CreateFloatingButton() else DestroyFloatingButton() end
    end)

    utilSec:NewToggle("Auto-Leave", "Automatically leaves if another player joins.", function(state)
        State.AutoLeave = state
        Alert("Auto-Leave " .. (state and "Enabled" or "Disabled"), "Info")
    end)

    utilSec:NewButton("Rejoin Server", "Teleports you to a new server of the same game.", function()
        Alert("Attempting to rejoin...", "Info")
        pcall(TeleportService.Teleport, TeleportService, game.PlaceId, LocalPlayer)
    end)

    local cfgTab = Window:NewTab("Config & Safety")
    local cfgSec = cfgTab:NewSection("Config")

    cfgSec:NewButton("Save Config", "Saves your settings to " .. CONFIG_FILE, function()
        Config.Save(false)
    end)

    cfgSec:NewButton("Load Config", "Loads saved settings and syncs the toggles.", function()
        if Config.Load(false) then Config.SyncUI() end
    end)

    cfgSec:NewButton("Delete Config", "Deletes the saved config file.", function()
        Config.Delete()
    end)

    cfgSec:NewToggle("Auto-Save Config", "Saves every 15s whenever something changed.", function(state)
        State.AutoSaveConfig = state
        Alert("Auto-Save Config " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    local rejoinSec = cfgTab:NewSection("Auto-Rejoin Watchdog")

    rejoinSec:NewToggle("Auto-Rejoin on Disconnect", "Waits out FE2's ~10s anti-rejoin cooldown, then rejoins after a kick or disconnect.", function(state)
        State.AutoRejoinDisconnect = state
        Alert("Auto-Rejoin (Disconnect) " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    rejoinSec:NewToggle("Auto-Rejoin on Stall", "Rejoins if Auto-Play/Auto-Farm stops making progress.", function(state)
        State.AutoRejoinStall = state
        Alert("Auto-Rejoin (Stall) " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    rejoinSec:NewTextBox("Stall Timeout (minutes)", "Minutes without a new map or escape. Default 8.", function(txt)
        local num = tonumber(txt)
        if num and num >= 1 then
            State.StallMinutes = num
            Alert("Stall timeout set to " .. tostring(num) .. " min.", "Info")
        else
            Alert("Enter a number of 1 or more.", "Error")
        end
    end)

    rejoinSec:NewTextBox("Reload Source", "Workspace file name OR https link to this script.", function(txt)
        txt = tostring(txt or ""):gsub("^%s*(.-)%s*$", "%1")
        if txt:find("]=]", 1, true) then
            Alert("That path contains unsupported characters.", "Error")
            return
        end
        State.ReloadSource = txt
        Alert(txt == "" and "Reload Source cleared." or ("Reload Source set: " .. txt), "Info")
    end)

    rejoinSec:NewTextBox("Rejoin Delay (seconds)", "Wait after a kick or disconnect before rejoining. Default 11.", function(txt)
        local num = tonumber(txt)
        if num and num >= 0 and num <= 120 then
            State.RejoinDelay = num
            Alert("Rejoin delay set to " .. tostring(num) .. "s.", "Info")
        else
            Alert("Enter a number from 0 to 120.", "Error")
        end
    end)

    rejoinSec:NewButton("Rejoin Now", "Saves config, queues the reload and teleports (good for testing).", function()
        Safety.Rejoin("Manual")
    end)

    local notifySec = cfgTab:NewSection("Discord Notifications")

    notifySec:NewTextBox("Webhook URL", "Your own Discord webhook. It is saved in your config file.", function(txt)
        txt = tostring(txt or ""):gsub("^%s*(.-)%s*$", "%1")
        if txt == "" then
            State.WebhookURL = ""
            Alert("Webhook cleared.", "Warning")
        elseif Notify.IsValidUrl(txt) then
            State.WebhookURL = txt
            Alert("Webhook set.", "Success")
        else
            Alert("That doesn't look like a Discord webhook URL.", "Error")
        end
    end)

    notifySec:NewToggle("Send Webhook Notifications", "Pings your webhook on TAS failures, benching and rejoins.", function(state)
        State.WebhookEnabled = state
        Alert("Webhook Notifications " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    notifySec:NewButton("Send Stats Summary", "Sends uptime, maps, escapes, TAS results and currency gains.", function()
        if Notify.Send(Currency.Summary(), true) then
            Alert("Stats summary sent.", "Info")
        else
            Alert("Set a valid webhook URL first.", "Error")
        end
    end)

    notifySec:NewButton("Test Webhook", "Sends a test message.", function()
        if Notify.Send("Test message from Flood GUI.", true) then
            Alert("Test message sent. Check Discord.", "Info")
        else
            Alert("Set a valid webhook URL first (or your executor has no request function).", "Error")
        end
    end)

    local statsSec = cfgTab:NewSection("Session Stats")
    local uptimeLabel = statsSec:NewLabel("Uptime: 0h 00m")
    local mapsLabel = statsSec:NewLabel("Maps: 0 | Escapes: 0 (0.0/hr)")
    local tasStatsLabel = statsSec:NewLabel("TAS runs: 0 ok / 0 failed")
    local coinsLabel = statsSec:NewLabel("Coins: n/a")
    local gemsLabel = statsSec:NewLabel("Gems: n/a")
    local levelLabel = statsSec:NewLabel("Level: n/a")

    local statsSession = {}
    getgenv().FloodGUI_StatsSession = statsSession
    task.spawn(function()
        while getgenv().FloodGUI_StatsSession == statsSession do
            local elapsed = os.clock() - RunStats.StartedAt
            local hours = math.max(elapsed / 3600, 1 / 60)
            local h = math.floor(elapsed / 3600)
            local m = math.floor((elapsed % 3600) / 60)
            pcall(function()
                uptimeLabel:UpdateLabel(string.format("Uptime: %dh %02dm", h, m))
                mapsLabel:UpdateLabel(string.format("Maps: %d | Escapes: %d (%.1f/hr)", RunStats.MapsSeen, RunStats.Escapes, RunStats.Escapes / hours))
                tasStatsLabel:UpdateLabel(string.format("TAS runs: %d ok / %d failed", RunStats.SessionOk, RunStats.SessionFail))
                local cl = Currency.Lines()
                coinsLabel:UpdateLabel(cl[1])
                gemsLabel:UpdateLabel(cl[2])
                levelLabel:UpdateLabel(cl[3])
            end)
            task.wait(5)
        end
    end)

    local mapTab = Window:NewTab("Map Tools")
    local mapSec = mapTab:NewSection("Teleport Spam")

    for _, spec in ipairs(MapTools.Specs) do
        mapSec:NewToggle(spec.label, spec.desc, function(state)
            MapTools.Enabled[spec.id] = state or nil
            Alert(spec.id .. " spam " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
        end)
    end

    mapSec:NewToggle("Float (no fall)", "Holds you in the air while a spam is running.", function(state)
        State.MapTPFloat = state
        if not state then MapTools.ReleaseFloat() end
    end)

    mapSec:NewTextBox("Spam Interval (seconds)", "e.g. 0.05 | 0 = fastest (max 5)", function(txt)
        local num = tonumber(txt)
        if num then
            State.MapTPInterval = math.clamp(num, 0, 5)
            Alert("Spam interval set to " .. tostring(State.MapTPInterval) .. "s.", "Info")
        else
            Alert("Enter a number from 0 to 5.", "Error")
        end
    end)

    local mapStatusLabel = mapSec:NewLabel("Status: idle")
    MapTools.OnStatus = function(spec)
        pcall(function()
            mapStatusLabel:UpdateLabel(spec and ("Status: spamming " .. spec.id) or "Status: idle")
        end)
    end

    mapSec:NewButton("TP Once (Current Map)", "Hits every target of this map one time.", function()
        task.spawn(MapTools.TpOnce)
    end)

    mapSec:NewButton("Debug Paths", "Prints the resolved parts to the console.", function()
        MapTools.Debug()
    end)

    local mapInfoSec = mapTab:NewSection("Supported Maps")
    for _, spec in ipairs(MapTools.Specs) do
        mapInfoSec:NewLabel(spec.info)
    end

    local credTab = Window:NewTab("Credits")
    local credSec = credTab:NewSection("Credits & Info")
    credSec:NewLabel("TAS System: Tomato (Base by Voiz#5668)")
    credSec:NewLabel("Reverse Engineering/Base GUI: Tomato")
    credSec:NewLabel("UI Library: xHeptc (Kavo)")
    credSec:NewLabel("TAS Auto-Sync: wo0psie")
    credSec:NewLabel("Lobby Tools: rokfx (github.com/4phi)")
    credSec:NewLabel("Quick Farm: tomato.txt (Flood-GUI quickfarm)")
    credSec:NewLabel("Fe2AutoFarm backend: embedded in the FE2 AutoFarm tab (single GUI mode)")
    credSec:NewLabel("Map Tools: from Map TP Spam (SCW + MOM)")
    credSec:NewLabel("Aura / Smart Rebirth ideas: ltseverydayyou (Fe2AutoFarm)")
    
    credSec:NewButton("Copy Support Server Invite", "Copies Discord invite.", function()
        if setclipboard then
            pcall(setclipboard, CONFIG.DISCORD_INVITE)
            Alert("Discord invite copied to clipboard!", "Success")
        else
            Alert("Clipboard access not supported by your exploit.", "Warning")
        end
    end)

    if State.FloatingButton then pcall(CreateFloatingButton) end
    pcall(function() Config.SyncUI() end)
end

do
    local okUI, errUI = pcall(InitializeUI)
    if not okUI then
        warn("[Flood GUI]: UI failed:", errUI)
        pcall(function()
            Alert("UI error — check console. Partial load.", "Error")
        end)
    else
        pcall(function()
            Alert("Flood GUI v4 loaded" .. (IS_FE2CM and " (FE2CM mode)" or "") .. "!", "Success")
        end)
    end
end
