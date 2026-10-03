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
local Multiplayer = Workspace:WaitForChild("Multiplayer")

local RemoteFolder = ReplicatedStorage:WaitForChild("Remote")
local ReqPasskey = RemoteFolder:WaitForChild("ReqPasskey")
local ReqRebirth = RemoteFolder:WaitForChild("ReqRebirth")
local NewMapVote = RemoteFolder:WaitForChild("NewMapVote")
local UpdMapVote = RemoteFolder:WaitForChild("UpdMapVote")
local AddedWaiting = RemoteFolder:WaitForChild("AddedWaiting")
local AlertRemote = RemoteFolder:WaitForChild("Alert")
local AddMapEventRemote = RemoteFolder:FindFirstChild("AddMapEvent")
local BoostIntensity = RemoteFolder:FindFirstChild("BoostIntensity")
local ReqTele = RemoteFolder:FindFirstChild("ReqTele")
local RemoveWaiting = RemoteFolder:FindFirstChild("RemoveWaiting")
local PressedMapButton = RemoteFolder:FindFirstChild("PressedMapButton") or RemoteFolder:WaitForChild("PressedMapButton")
local UpdGoalLocator = RemoteFolder:FindFirstChild("UpdGoalLocator") or RemoteFolder:WaitForChild("UpdGoalLocator")
local SurvivedRemote = RemoteFolder:FindFirstChild("Survived") or RemoteFolder:WaitForChild("Survived")
local LoadedMapRemote = RemoteFolder:FindFirstChild("LoadedMap")

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
    Normal = 738339342
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
    RejoinPendingAt = 0
}

local PauseButtonGui = nil

local RunStats = {
    Maps = {}, SessionOk = 0, SessionFail = 0,
    Escapes = 0, MapsSeen = 0, LastEscape = 0, StartedAt = os.clock()
}
local Notify = {}
local TasPrefetch = {}
local QF = {
    Goal = nil, Button = nil, Next = nil, Passkey = nil,
    ExitPhase = false, Escaped = false, DelayOverride = false, ResettingCharacter = false,
    UpdTarget = nil, LockIndices = {}, OrigUpd = nil, OrigNewAlert = nil, NoclipConn = nil
}

-- ==============================================================================
-- [4] UTILITIES & ALERT SYSTEM
-- ==============================================================================
local CLMAIN = LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("CL_MAIN_GameScript")
local CLMAINenv = nil
pcall(function() CLMAINenv = getsenv(CLMAIN) end)

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
        
        local liveWeld = RootPart:FindFirstChild("WalljumpWeld_Live")
        if liveWeld then liveWeld:Destroy() end
        local serverWeld = RootPart:FindFirstChild("WalljumpWeld_Server")
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

QF.InstallHooks()

TrackConnection(UpdGoalLocator.OnClientEvent:Connect(function(p1, p2, p3, p4)
    QF.Goal, QF.Button, QF.Next = p1, p2, p4
end))

TrackConnection(AlertRemote.OnClientEvent:Connect(function(msg)
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

-- God Mode: keep health pinned at 1000 (reset paths set ResettingCharacter to bypass it)
TrackConnection(RunService.Heartbeat:Connect(function()
    if not State.GodMode or QF.ResettingCharacter or State.ResettingForDifficulty then return end
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    if hum and hum.Health > 0 then
        if hum.MaxHealth ~= 1000 then hum.MaxHealth = 1000 end
        if hum.Health < 1000 then hum.Health = 1000 end
    end
end))

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

        if State.AutoRebirth then
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
TrackConnection(NewMapVote.OnClientEvent:Connect(function(dataPacket)
    if State.Mode ~= "Record" then return end
    if not State.AutoFarm and not State.AutoPlay then return end
    -- Record mode still works, just no automatic voting
end))

TrackConnection(Multiplayer.ChildAdded:Connect(function(NewMap)
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

TrackConnection(AlertRemote.OnClientEvent:Connect(function(msg)
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
            if not Check("InLift") and not Check("InGame") then
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
            if now - lastRebirthAttempt >= 60 then
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
        AddedWaiting:FireServer()
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

    TrackConnection(NewMapVote.OnClientEvent:Connect(function()
        fullVoteInProgress = false
    end))

    TrackConnection(UpdMapVote.OnClientEvent:Connect(function(voteData)
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

    TrackConnection(Multiplayer.ChildAdded:Connect(function(NewMap)
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
}

local PERSIST_KEYS = {
    "AutoPlay", "FallbackToFarm", "AutoFarm", "AutoCollect", "AutoRebirth", "AutoLeave",
    "EnforceDifficulty", "AutoBoost", "AutoEvent", "AutoVoting", "AutoFullVote",
    "AutoTeleport", "AutoReqTele", "AutoRejoinDisconnect", "AutoRejoinStall", "AutoSaveConfig",
    "Mode", "TargetDifficulty", "TargetMapName", "WalkSpeed", "JumpPower", "TASSpeed",
    "CustomVoteTarget", "TargetUsername", "SelectedPlaceType", "StallMinutes", "ReloadSource",
    "MaxTasFails", "WebhookURL", "WebhookEnabled", "FloatingButton",
    "FastLoad", "GodMode", "PlayAfterButtons", "ResetAfterEscape", "StartDelay", "ResetDelay",
    "CycleChallenges", "RejoinDelay", "RejoinPendingAt",
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
    TrackConnection(AlertRemote.OnClientEvent:Connect(function(msg)
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
    TrackConnection(Multiplayer.ChildAdded:Connect(function(NewMap)
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
    TrackConnection(AlertRemote.OnClientEvent:Connect(function(msg)
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

    TrackConnection(NewMapVote.OnClientEvent:Connect(TasPrefetch.FromVoteData))
    TrackConnection(UpdMapVote.OnClientEvent:Connect(TasPrefetch.FromVoteData))
end

RunStats.Load()

-- Restore saved settings before the UI is built
Config.Load(true)

-- ==============================================================================
-- [9] USER INTERFACE (KAVO)
-- ==============================================================================
local function InitializeUI()
    local source = game:HttpGet(CONFIG.UI_LIBRARY)
    local Kavo = loadstring(source)()
    local Window = Kavo.CreateLib("Flood GUI v4", KAVO_THEME)
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
    
    mainSec:NewToggle("Auto Rebirth", "Automatically attempts to rebirth every 60 seconds.", function(state)
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

    local qfSec = autoTab:NewSection("Quick Farm Options")

    qfSec:NewToggle("Fast Load", "Skips the map loading delay and screens.", function(state)
        State.FastLoad = state
        getgenv().FloodGUI_FastLoad = state
        Alert("Fast Load " .. (state and "Enabled" or "Disabled"), state and "Success" or "Error")
    end)

    qfSec:NewToggle("Enable God Mode", "Keeps your health at 1000.", function(state)
        State.GodMode = state
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

    local miscTab = Window:NewTab("Other")
    local utilSec = miscTab:NewSection("Utilities")
    
    utilSec:NewKeybind("Toggle UI", "Toggles the GUI visibility.", Enum.KeyCode.J, function()
        State.UIEnabled = not State.UIEnabled
        Kavo:ToggleUI()
        Alert("UI " .. (State.UIEnabled and "Enabled" or "Disabled"), "Info")
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
            end)
            task.wait(5)
        end
    end)

    local credTab = Window:NewTab("Credits")
    local credSec = credTab:NewSection("Credits & Info")
    credSec:NewLabel("TAS System: Tomato (Base by Voiz#5668)")
    credSec:NewLabel("Reverse Engineering/Base GUI: Tomato")
    credSec:NewLabel("UI Library: xHeptc (Kavo)")
    credSec:NewLabel("TAS Auto-Sync: wo0psie")
    credSec:NewLabel("Lobby Tools: rokfx (github.com/4phi)")
    credSec:NewLabel("Quick Farm: tomato.txt (Flood-GUI quickfarm)")
    
    credSec:NewButton("Copy Support Server Invite", "Copies Discord invite.", function()
        if setclipboard then
            pcall(setclipboard, CONFIG.DISCORD_INVITE)
            Alert("Discord invite copied to clipboard!", "Success")
        else
            Alert("Clipboard access not supported by your exploit.", "Warning")
        end
    end)

    if State.FloatingButton then CreateFloatingButton() end
    Config.SyncUI()
end

InitializeUI()
Alert("Flood GUI v4 (TAS Player + Lobby + Config/Safety) Loaded Successfully!", "Success")
