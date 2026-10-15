getgenv().TAS_Active = true 

local UI_API_URL = "https://raw.githubusercontent.com/tomatotxt/Flood-GUI/refs/heads/v4beta/TAS/CREATOR/uiapi.luau"

print("TAS Creator: Ultimate Edition Loaded")

-- // NEW CONFIGURATIONS //
getgenv().ExtremeSmoothing = false
getgenv().TargetSmoothingFPS = 24
getgenv().ShowTASPathDuringPlayback = false
getgenv().PlaybackCamera = false
getgenv().ShowVelocityPredictor = false
getgenv().EnableAutoSwim = true -- Added default configuration
getgenv().PreloadTASFile = getgenv().PreloadTASFile or "" -- Optional: exact JSON filename to preload automatically

local Keybinds = {
    AddSavestate = "One",
    RemoveSavestate = "Two",
    BackSavestate = "Three",
    GoFrameBack = "Four", 
    GoFrameForward = "Five", 
    SaveRun = "Six",
    UserPause = "CapsLock",
    CollisionToggler = "C",
    ResetToNormal = "Delete",
    ViewTAS = "Zero",
    Resync = "F8",
    EnvPause = "Equals",
    DebugToggler = "V",
    AutoSwimToggler = "T" -- added Auto-Swim toggle keybind (T)
}

-- // SERVICES //
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

-- // ALERT SYSTEM //
local NewAlert = nil
local function SetupAlerts()
    local GameScript = LocalPlayer.PlayerScripts:WaitForChild("CL_MAIN_GameScript", 5)
    if GameScript then
        local success, env = pcall(getsenv, GameScript)
        if success and env.newAlert then NewAlert = env.newAlert end
    end
end
SetupAlerts()

local function SendAlert(msg, color)
    if NewAlert then
        pcall(function() NewAlert(msg, color, 1.5, nil) end)
    else
        local GameScript = LocalPlayer.PlayerScripts:FindFirstChild("CL_MAIN_GameScript")
        if GameScript then
            local s, e = pcall(getsenv, GameScript)
            if s and e and e.newAlert then
                NewAlert = e.newAlert
                pcall(function() NewAlert(msg, color, 1.5, nil) end)
            end
        end
    end
end

SendAlert("Ultimate TAS Creator Initialized", Color3.fromRGB(183, 0, 255))

-- // BYPASSES //
local OldIndex
OldIndex = hookmetamethod(game, "__index", function(self, key)
    if not checkcaller() then
        if key == "Archivable" then return false end
        -- Updated: Position spoofing will now respect getgenv().TAS_Active, getgenv().EnableAutoSwim, and getgenv().PauseSpoofing
        if getgenv().TAS_Active and getgenv().EnableAutoSwim and getgenv().IsSwimming and not getgenv().PauseSpoofing and key == "Position" and self.Name == "HumanoidRootPart" then
            return Vector3.new(-23, -153, 0)
        end
    end
    return OldIndex(self, key)
end)

pcall(function() ReplicatedStorage.Remote.ReqPasskey:InvokeServer() end)

-- // VARIABLES //
local CurrentAnim = {}
local Savestates = {}
local Frames = {} 
local TimeOffset = 0
local PreviewOffset = 0
local IsPaused = true
local EnvPaused = false
local PauseStart
local OriginalPlayAnim
local AnimEnv
local RunStart
local SavedVelocity = Vector3.new(0, 0, 0)
local Connections = {} 

-- Flags
local IsPreviewingForward = false
local IsPreviewingBackward = false
local IsAdvancingFrame = false 
local IsRewinding = false
local IsViewingTAS = false
local AutoSaved = false

-- Recorder & Map
local MapEvents = {} 
local PlaybackIndex = 1
local MapRecorderCache = {}
local ClonedMap
local RopeTable
local MapOffset, MapPos, MapX, MapY, MapZ
local MapUUIDs = {} 

-- Button Order Tracking
local RecordedButtonSequence = {} 
local OrderedButtonRegistry = {}  

-- Lighting Storage
local SavedLighting = {Props = {}, Children = {}}
local LightingCaptured = false

-- Recording Cap
local RecordAccumulator = 0
local TARGET_FPS = 60
local RECORD_INTERVAL = 1 / TARGET_FPS

-- Auto-Swim
getgenv().IsSwimming = false
getgenv().PauseSpoofing = false -- Track zipline contact to pause position spoofing
local WaterParts = {}

-- Button Tracking
local TotalButtons = {}
local ButtonRegistry = {}

-- // NEW VISUALIZER VARIABLES //
local OriginalVisuals = setmetatable({}, { __mode = "k" })
local DebugActive = false
local TrajectoryFolder = Instance.new("Folder", workspace)
TrajectoryFolder.Name = "TAS_Trajectory"
local TrajectoryLines = {}
local PathLines = {}
local SelectedFileToLoad = ""

-- // FILE PLAYBACK STATE //
-- ok so how it work s its used by the original 0-key TAS preview so file editing/loading is handled
-- separately below so loading a saved TAS never requires playing it through, yay
local PlaybackState = {
    Active = false,
    Paused = false,
    Time = 0,
    PlayStart = 0,
    Data = nil,
    OldFrame = 1,
    Offset = nil
}
local ActivateTASAnimation

-- // PRELOADED FILE EDITOR //
-- a selected json file is decoded into memory immediately, so load selected run
-- never has to play through the TAS first so timestamp seeking is non-destructive or wtv
-- until the user resumes recording, then everything after the seek point is cut
local PreloadedTASData = nil
local PreloadedTASFilename = ""
local LoadedFileMode = false
local PendingEditCut = false
local PendingEditTime = 0
local FileTimestampBox = nil
local FileTimestampStatus = nil

-- // UI Variables //
local TAS_UI = loadstring(game:HttpGet(UI_API_URL))()
local UI_Elements = nil
local MobileGui = nil
local TimeText, FrameCountLabel, StatusLabel, MapEventLabel

-- // DATA PACKING (OPTIMIZATION) //
local PACK_FORMAT = "d" .. string.rep("f", 28) .. "s"

local function PackFrame(Time, Vel, CF, CamCF, Anim)
    local animName = Anim[1] or "idle"
    local animSpeed = Anim[2] or 0
    local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = CF:GetComponents()
    local cx, cy, cz, cR00, cR01, cR02, cR10, cR11, cR12, cR20, cR21, cR22 = CamCF:GetComponents()
    return string.pack(PACK_FORMAT, Time, Vel.X, Vel.Y, Vel.Z, x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22, cx, cy, cz, cR00, cR01, cR02, cR10, cR11, cR12, cR20, cR21, cR22, animSpeed, animName)
end

local function UnpackFrame(data)
    local t, vx, vy, vz, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12, cm1, cm2, cm3, cm4, cm5, cm6, cm7, cm8, cm9, cm10, cm11, cm12, asp, anm = string.unpack(PACK_FORMAT, data)
    return {
        Time = t, Velocity = Vector3.new(vx, vy, vz),
        CFrame = CFrame.new(c1, c2, c3, c4, c5, c6, c7, c8, c9, c10, c11, c12),
        CameraCFrame = CFrame.new(cm1, cm2, cm3, cm4, cm5, cm6, cm7, cm8, cm9, cm10, cm11, cm12),
        Animation = {anm, asp}
    }
end

-- // HELPER FUNCTIONS //
local function AddConnection(con) table.insert(Connections, con); return con end

local function isRandomString(str)
    if #str == 0 then return false end
    for i = 1, #str do
        local ltr = str:sub(i, i)
        if ltr:lower() == ltr then return false end
    end
    return true
end

local function GetUUID(part)
    if not part then return nil end
    local id = part:GetAttribute("TAS_UUID")
    if not id then
        id = HttpService:GenerateGUID(false)
        part:SetAttribute("TAS_UUID", id)
    end
    return id
end

local function DeepCopy(orig)
    local copy = {}
    if type(orig) == 'table' then
        for k, v in pairs(orig) do copy[k] = v end
    else
        copy = orig
    end
    return copy
end

local function ToggleCollision()
    local mouse = LocalPlayer:GetMouse()
    if mouse and mouse.Target then
        local target = mouse.Target
        target.CanCollide = not target.CanCollide
        SendAlert("Collision " .. (target.CanCollide and "Enabled" or "Disabled"), Color3.fromRGB(255, 255, 0))
    end
end

local function IsPointInPart(part, point)
    local rel = part.CFrame:PointToObjectSpace(point)
    local halfSize = part.Size / 2
    return math.abs(rel.X) <= halfSize.X and math.abs(rel.Y) <= halfSize.Y and math.abs(rel.Z) <= halfSize.Z
end

-- [[ ENTIRE BOUNDING BOX WATER DETECTION ]]
local function IsPartEntirelyInPart(containerPart, targetPart)
    local tCF = targetPart.CFrame
    local tSize = targetPart.Size / 2
    local cCFInv = containerPart.CFrame:Inverse()
    local cSize = containerPart.Size / 2

    local corners = {
        tCF * Vector3.new( tSize.X,  tSize.Y,  tSize.Z),
        tCF * Vector3.new( tSize.X,  tSize.Y, -tSize.Z),
        tCF * Vector3.new( tSize.X, -tSize.Y,  tSize.Z),
        tCF * Vector3.new( tSize.X, -tSize.Y, -tSize.Z),
        tCF * Vector3.new(-tSize.X,  tSize.Y,  tSize.Z),
        tCF * Vector3.new(-tSize.X,  tSize.Y, -tSize.Z),
        tCF * Vector3.new(-tSize.X, -tSize.Y,  tSize.Z),
        tCF * Vector3.new(-tSize.X, -tSize.Y, -tSize.Z)
    }

    for _, corner in ipairs(corners) do
        local rel = cCFInv * corner
        if math.abs(rel.X) > cSize.X or math.abs(rel.Y) > cSize.Y or math.abs(rel.Z) > cSize.Z then
            return false
        end
    end
    return true
end

local function GetPlayerCFrame()
    local Root = LocalPlayer.Character.HumanoidRootPart
    local x, y, z, R00, R01, R02, R10, R11, R12, R20, R21, R22 = Root.CFrame:GetComponents()
    return CFrame.new(x - MapX, y - MapY + 1000, z - MapZ, R00, R01, R02, R10, R11, R12, R20, R21, R22)
end

local function CaptureFrameData()
    return PackFrame(
        tick() - RunStart - TimeOffset,
        LocalPlayer.Character.HumanoidRootPart.Velocity,
        GetPlayerCFrame(),
        workspace.CurrentCamera.CFrame,
        CurrentAnim
    )
end

-- [[ COMPILER & FILE LOGIC ]] --
local function CompileTASData()
    local Data = {}
    local function AddList(list)
         for j = 1, #list do
            local FramePacked = list[j]
            if type(FramePacked) == "string" then
                local F = UnpackFrame(FramePacked)
                local rx, ry, rz = F.CFrame:ToEulerAnglesXYZ()
                local crx, cry, crz = F.CameraCFrame:ToEulerAnglesXYZ()
                table.insert(Data, {
                    AAnimationChanged = F.Animation[2],
                    CCameraCFrame = {F.CameraCFrame.X - MapX, F.CameraCFrame.Y - (MapY - 1000), F.CameraCFrame.Z - MapZ, crx, cry, crz},
                    CCFrame = {F.CFrame.X, F.CFrame.Y, F.CFrame.Z, rx, ry, rz},
                    VVelocity = {F.Velocity.X, F.Velocity.Y, F.Velocity.Z},
                    AAnimation = F.Animation or {"walk", 0.1},
                    time = F.Time
                })
            end
         end
    end
    for i = 1, #Savestates do AddList(Savestates[i]) end
    AddList(Frames)
    return Data
end

local PreloadTASFile

local function RefreshFileList()
    if not UI_Elements or not UI_Elements.FileList then return end
    for _, child in ipairs(UI_Elements.FileList:GetChildren()) do
        if child:IsA("TextButton") then child:Destroy() end
    end
    if not listfiles or not isfolder then return end

    pcall(function()
        if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
        local files = {}
        for _, file in ipairs(listfiles("Flood-GUI/TAS FILES")) do
            if file:match("%.json$") then files[#files + 1] = file:match("([^/\\]+)$") end
        end

        for _, filename in ipairs(files) do
            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, -10, 0, 30)
            btn.BackgroundColor3 = Color3.fromRGB(40,40,45)
            btn.Text = filename
            btn.TextColor3 = Color3.new(1,1,1)
            btn.Font = Enum.Font.Gotham
            btn.Parent = UI_Elements.FileList
            btn.Activated:Connect(function()
                SelectedFileToLoad = filename
                if UI_Elements.SelectedLabel then UI_Elements.SelectedLabel.Text = "Selected: " .. filename end
                -- Decode immediately on selection. This is the important part:
                -- selecting a file no longer means waiting for its full playback.
                PreloadTASFile(filename)
            end)
        end

        -- Optional fixed preload. Set getgenv().PreloadTASFile to a filename if
        -- you want one particular TAS ready every time the creator starts.
        local wanted = tostring(getgenv().PreloadTASFile or "")
        if wanted ~= "" then
            for _, filename in ipairs(files) do
                if filename == wanted then
                    SelectedFileToLoad = filename
                    if UI_Elements.SelectedLabel then UI_Elements.SelectedLabel.Text = "Selected: " .. filename end
                    PreloadTASFile(filename, true)
                    break
                end
            end
        elseif #files == 1 then
            SelectedFileToLoad = files[1]
            if UI_Elements.SelectedLabel then UI_Elements.SelectedLabel.Text = "Selected: " .. files[1] end
            PreloadTASFile(files[1], true)
        end
    end)
end

-- // CORE LOGIC / FORWARD DECLARATIONS //
local TogglePause, AddSavestate, RemoveSavestate, LoadLastSavestate, RewindFrame, StepForward, PlaybackTAS, ResetToNormal, RewindLoop

-- // FILE TIMESTAMP / INSTANT LOAD //
local UpdateMapState, SyncButtonState, UpdateTimeDisplay
local function ParsePlaybackTimestamp(text)
    text = tostring(text or ""):gsub("%s+", "")
    if text == "" then return nil end

    local plain = tonumber(text)
    if plain then return math.max(0, plain) end

    local parts = {}
    for part in text:gmatch("[^:]+") do table.insert(parts, part) end
    if #parts == 2 or #parts == 3 then
        local n = {}
        for i, part in ipairs(parts) do n[i] = tonumber(part) end
        for i = 1, #n do if not n[i] then return nil end end
        if #n == 2 then
            return math.max(0, n[1] * 60 + n[2])
        end
        return math.max(0, n[1] * 3600 + n[2] * 60 + n[3])
    end
    return nil
end

local function FormatPlaybackTimestamp(t)
    t = math.max(0, tonumber(t) or 0)
    local h = math.floor(t / 3600)
    local m = math.floor((t % 3600) / 60)
    local sec = t % 60
    if h > 0 then
        return string.format("%d:%02d:%06.3f", h, m, sec)
    end
    return string.format("%d:%06.3f", m, sec)
end

local function DecodeTASFile(filename)
    if not filename or filename == "" then return nil, "No filename" end
    if not isfile or not readfile then return nil, "File API unavailable" end
    local path = "Flood-GUI/TAS FILES/" .. filename
    if isfile and not isfile(path) then return nil, "File not found" end
    local ok, raw = pcall(readfile, path)
    if not ok then return nil, raw end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, raw)
    if not ok2 or type(data) ~= "table" or #data == 0 then
        return nil, "Invalid/empty TAS JSON"
    end
    return data
end

PreloadTASFile = function(filename, quiet)
    local data, err = DecodeTASFile(filename)
    if not data then
        PreloadedTASData = nil
        PreloadedTASFilename = ""
        if not quiet then SendAlert("Could not preload " .. tostring(filename) .. ": " .. tostring(err), Color3.fromRGB(255, 0, 0)) end
        return false
    end
    PreloadedTASData = data
    PreloadedTASFilename = filename
    if not quiet then
        SendAlert("Preloaded " .. filename .. " (" .. #data .. " frames)", Color3.fromRGB(0, 255, 255))
    end
    if FileTimestampStatus then
        FileTimestampStatus.Text = "READY • " .. FormatPlaybackTimestamp(data[#data].time or 0)
    end
    return true
end

local function JsonFrameToPacked(entry)
    if type(entry) ~= "table" then return nil end
    if type(entry.CCFrame) ~= "table" or type(entry.CCameraCFrame) ~= "table" then return nil end
    if type(entry.VVelocity) ~= "table" then return nil end

    local c = entry.CCFrame
    local cam = entry.CCameraCFrame
    local vel = entry.VVelocity
    if #c < 6 or #cam < 6 or #vel < 3 then return nil end

    local cf = CFrame.new(c[1], c[2], c[3]) * CFrame.fromEulerAnglesXYZ(c[4], c[5], c[6])
    local camcf = CFrame.new(cam[1], cam[2], cam[3]) * CFrame.fromEulerAnglesXYZ(cam[4], cam[5], cam[6])
    local anim = type(entry.AAnimation) == "table" and entry.AAnimation or {"walk", 0.1}
    return PackFrame(tonumber(entry.time) or 0, Vector3.new(vel[1] or 0, vel[2] or 0, vel[3] or 0), cf, camcf, anim)
end

local function ConvertTASDataToFrames(data)
    local packed = {}
    for i = 1, #data do
        local frame = JsonFrameToPacked(data[i])
        if frame then packed[#packed + 1] = frame end
    end
    return packed
end

local function ApplyPackedFrameAtTime(packed, targetTime)
    if type(packed) ~= "table" or #packed == 0 then return nil end
    targetTime = math.max(0, tonumber(targetTime) or 0)

    local first = UnpackFrame(packed[1])
    local last = UnpackFrame(packed[#packed])
    targetTime = math.clamp(targetTime, first.Time, last.Time)

    local lo, hi = 1, #packed
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        local f = UnpackFrame(packed[mid])
        if f.Time <= targetTime then lo = mid else hi = mid - 1 end
    end

    local a = UnpackFrame(packed[lo])
    local b = UnpackFrame(packed[math.min(lo + 1, #packed)])
    local span = b.Time - a.Time
    local alpha = span > 0 and math.clamp((targetTime - a.Time) / span, 0, 1) or 0

    local cf = a.CFrame:Lerp(b.CFrame, alpha)
    local vel = a.Velocity:Lerp(b.Velocity, alpha)
    local cam = a.CameraCFrame:Lerp(b.CameraCFrame, alpha)
    local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if Root then
        Root.Anchored = true
        Root.CFrame = cf + Vector3.new(MapX, MapY - 1000, MapZ)
        Root.Velocity = vel
        SavedVelocity = vel
    end
    workspace.CurrentCamera.CFrame = cam + Vector3.new(MapX, MapY - 1000, MapZ)

    local anim = a.Animation or {"walk", 0.1}
    if OriginalPlayAnim and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        pcall(function() OriginalPlayAnim(anim[1], anim[2], LocalPlayer.Character.Humanoid) end)
    end
    if anim[1] == "walk" and AnimEnv then pcall(function() AnimEnv.setAnimationSpeed(0.76) end) end

    SyncButtonState(targetTime, targetTime)
    UpdateMapState(targetTime)
    UpdateTimeDisplay(targetTime)
    return targetTime
end

local function LoadPreloadedRunIntoEditor()
    if type(PreloadedTASData) ~= "table" or #PreloadedTASData == 0 then
        SendAlert("Select/preload a TAS file first", Color3.fromRGB(255, 170, 0))
        return false
    end

    local packed = ConvertTASDataToFrames(PreloadedTASData)
    if #packed == 0 then
        SendAlert("TAS file contains no usable frames", Color3.fromRGB(255, 0, 0))
        return false
    end

    PlaybackState.Active = false
    PlaybackState.Paused = false
    PlaybackState.Data = nil
    IsViewingTAS = false
    LoadedFileMode = true
    PendingEditCut = false
    PendingEditTime = UnpackFrame(packed[1]).Time
    Frames = packed
    Savestates = {}
    PreviewOffset = 0
    TimeOffset = 0
    local first = UnpackFrame(Frames[1])
    RunStart = tick() - first.Time
    PauseStart = tick()
    IsPaused = true

    local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if Root then Root.Anchored = true end
    ApplyPackedFrameAtTime(Frames, first.Time)

    if UI_Elements and UI_Elements.SaveBox and PreloadedTASFilename ~= "" then
        UI_Elements.SaveBox.Text = PreloadedTASFilename:gsub("%.json$", "")
    end
    if FileTimestampBox then FileTimestampBox.Text = FormatPlaybackTimestamp(first.Time) end
    if FileTimestampStatus then FileTimestampStatus.Text = "LOADED • " .. FormatPlaybackTimestamp(UnpackFrame(Frames[#Frames]).Time) end
    SendAlert("Loaded " .. PreloadedTASFilename .. " instantly — ready to edit", Color3.fromRGB(0, 255, 100))
    return true
end

local function SeekLoadedTAS(targetTime)
    if not LoadedFileMode or #Frames == 0 then
        SendAlert("Load a TAS file first", Color3.fromRGB(255, 170, 0))
        return
    end
    local lastTime = UnpackFrame(Frames[#Frames]).Time
    targetTime = math.clamp(tonumber(targetTime) or 0, 0, lastTime)
    PendingEditTime = targetTime
    PendingEditCut = true
    RunStart = tick() - targetTime
    PauseStart = tick()
    TimeOffset = 0
    IsPaused = true
    ApplyPackedFrameAtTime(Frames, targetTime)
    if FileTimestampBox then FileTimestampBox.Text = FormatPlaybackTimestamp(targetTime) end
    if FileTimestampStatus then FileTimestampStatus.Text = "EDIT POINT • " .. FormatPlaybackTimestamp(targetTime) .. " • resume to cut" end
    SendAlert("Edit point: " .. FormatPlaybackTimestamp(targetTime) .. " — resume to cut the future", Color3.fromRGB(0, 255, 255))
end

local function CutFramesAfterTime(targetTime)
    if #Frames == 0 then return end
    targetTime = math.max(0, tonumber(targetTime) or 0)
    local kept = {}
    for i = 1, #Frames do
        local f = UnpackFrame(Frames[i])
        if f.Time <= targetTime then
            kept[#kept + 1] = Frames[i]
        else
            break
        end
    end
    if #kept == 0 then kept[1] = Frames[1] end
    Frames = kept
    local last = UnpackFrame(Frames[#Frames])
    if math.abs(last.Time - targetTime) > 0.0005 then
        -- Capture the exact current state as the branch boundary.
        local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if Root then Frames[#Frames + 1] = PackFrame(targetTime, Root.Velocity, GetPlayerCFrame(), workspace.CurrentCamera.CFrame, CurrentAnim) end
    end
end

local function BuildFileTimestampControl(anchor)
    if FileTimestampBox or not UI_Elements then return end
    anchor = anchor or (UI_Elements.Buttons and UI_Elements.Buttons.LoadRun)
    local host = anchor and anchor.Parent or (UI_Elements.FileList and UI_Elements.FileList.Parent)
    if not host then return end

    local panel = Instance.new("Frame")
    panel.Name = "FileTimestampControl"
    panel.Size = anchor and anchor.Size or UDim2.new(1, -10, 0, 34)
    panel.Position = anchor and UDim2.new(anchor.Position.X.Scale, anchor.Position.X.Offset, anchor.Position.Y.Scale, anchor.Position.Y.Offset - 39) or UDim2.new(0, 5, 1, -39)
    panel.BackgroundColor3 = Color3.fromRGB(28, 28, 35)
    panel.BackgroundTransparency = 0.05
    panel.BorderSizePixel = 0
    panel.ZIndex = 30
    panel.Parent = host
    Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 6)

    local box = Instance.new("TextBox")
    box.Name = "Timestamp"
    box.Size = UDim2.new(0.72, -5, 1, -8)
    box.Position = UDim2.new(0, 4, 0, 4)
    box.BackgroundColor3 = Color3.fromRGB(40, 40, 48)
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.Font = Enum.Font.Gotham
    box.Text = "0:00.000"
    box.TextColor3 = Color3.new(1, 1, 1)
    box.TextSize = 11
    box.PlaceholderText = "Timestamp"
    box.ZIndex = 31
    box.Parent = panel
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 5)

    local go = Instance.new("TextButton")
    go.Name = "Go"
    go.Size = UDim2.new(0.28, -5, 1, -8)
    go.Position = UDim2.new(0.72, 0, 0, 4)
    go.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
    go.BorderSizePixel = 0
    go.Font = Enum.Font.GothamBold
    go.Text = "GO"
    go.TextColor3 = Color3.new(1, 1, 1)
    go.TextSize = 11
    go.ZIndex = 31
    go.Parent = panel
    Instance.new("UICorner", go).CornerRadius = UDim.new(0, 5)

    FileTimestampBox = box

    local function goToTimestamp()
        local t = ParsePlaybackTimestamp(box.Text)
        if not t then
            SendAlert("Invalid timestamp — use 12.345 or 0:12.345", Color3.fromRGB(255, 0, 0))
            return
        end
        SeekLoadedTAS(t)
    end
    go.Activated:Connect(goToTimestamp)
    box.FocusLost:Connect(function(enterPressed) if enterPressed then goToTimestamp() end end)
end

-- [[ UI API LOADING & BINDING ]] --
local function BindUI()
    if not UI_Elements or not UI_Elements.Buttons then return end
    local btns = UI_Elements.Buttons
    
    -- Controls
    btns.Pause.Activated:Connect(TogglePause)
    btns.AddState.Activated:Connect(AddSavestate)
    btns.RemState.Activated:Connect(RemoveSavestate)
    btns.LoadState.Activated:Connect(function() task.spawn(LoadLastSavestate) end)
    btns.StepBack.Activated:Connect(RewindFrame)
    btns.StepFwd.Activated:Connect(StepForward)
    btns.Resync.Activated:Connect(function() IsPreviewingForward = false; IsPreviewingBackward = false; PreviewOffset = 0; SendAlert("Visuals Resynced", Color3.fromRGB(0, 255, 255)) end)
    btns.PlayTAS.Activated:Connect(function() if not IsViewingTAS then PlaybackTAS(CompileTASData()) end end)
    btns.Collision.Activated:Connect(ToggleCollision)
    btns.Stop.Activated:Connect(function() task.spawn(ResetToNormal) end)
    
    -- Configs / Vis
    btns.DebugView.Activated:Connect(function()
        DebugActive = not DebugActive
        if DebugActive then
            if ClonedMap then
                for _, v in pairs(ClonedMap:GetDescendants()) do
                    if v:IsA("BasePart") then
                        OriginalVisuals[v] = {Color = v.Color, Transparency = v.Transparency}
                        if v.Name == "Hitbox" or v.Name:find("_Water") then
                            v.Color = Color3.fromHSV(math.random(), 1, 1); v.Transparency = 0.2
                        else
                            v.Color = Color3.new(0.4, 0.4, 0.4); if v.Transparency == 1 then v.Transparency = 0.8 end
                        end
                    end
                end
            end
            btns.DebugView.Text = "Debug Hitboxes: ON"; btns.DebugView.BackgroundColor3 = Color3.fromRGB(0, 150, 100)
        else
            for part, props in pairs(OriginalVisuals) do if part and part.Parent then part.Color = props.Color; part.Transparency = props.Transparency end end
            OriginalVisuals = setmetatable({}, { __mode = "k" })
            btns.DebugView.Text = "Debug Hitboxes: OFF"; btns.DebugView.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        end
    end)
    btns.SmoothMode.Activated:Connect(function()
        getgenv().ExtremeSmoothing = not getgenv().ExtremeSmoothing
        btns.SmoothMode.Text = "Extreme Smoothing: " .. (getgenv().ExtremeSmoothing and "ON" or "OFF")
        btns.SmoothMode.BackgroundColor3 = getgenv().ExtremeSmoothing and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
    end)
    btns.PathTracing.Activated:Connect(function()
        getgenv().ShowTASPathDuringPlayback = not getgenv().ShowTASPathDuringPlayback
        btns.PathTracing.Text = "TAS Path Tracing: " .. (getgenv().ShowTASPathDuringPlayback and "ON" or "OFF")
        btns.PathTracing.BackgroundColor3 = getgenv().ShowTASPathDuringPlayback and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
    end)
    btns.Trajectory.Activated:Connect(function()
        getgenv().ShowVelocityPredictor = not getgenv().ShowVelocityPredictor
        btns.Trajectory.Text = "Predictive Velocity: " .. (getgenv().ShowVelocityPredictor and "ON" or "OFF")
        btns.Trajectory.BackgroundColor3 = getgenv().ShowVelocityPredictor and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
    end)
    btns.CamMode.Activated:Connect(function()
        getgenv().PlaybackCamera = not getgenv().PlaybackCamera
        btns.CamMode.Text = "Camera Follow: " .. (getgenv().PlaybackCamera and "ON" or "OFF")
        btns.CamMode.BackgroundColor3 = getgenv().PlaybackCamera and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
    end)
    
    -- Added: Backwards compatible registration for AutoSwim button logic
    if btns.AutoSwim then
        btns.AutoSwim.Activated:Connect(function()
            getgenv().EnableAutoSwim = not getgenv().EnableAutoSwim
            btns.AutoSwim.Text = "Auto-Swim: " .. (getgenv().EnableAutoSwim and "ON" or "OFF")
            btns.AutoSwim.BackgroundColor3 = getgenv().EnableAutoSwim and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
            SendAlert("Auto-Swim " .. (getgenv().EnableAutoSwim and "Enabled" or "Disabled"), getgenv().EnableAutoSwim and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0))
        end)
    end

    -- Files
    btns.SaveRun.Activated:Connect(function()
        local name = (UI_Elements.SaveBox and UI_Elements.SaveBox.Text ~= "") and UI_Elements.SaveBox.Text or (ClonedMap and ClonedMap.Settings:GetAttribute("MapName") or "MyRun")
        if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
        writefile("Flood-GUI/TAS FILES/" .. name .. ".json", HttpService:JSONEncode(CompileTASData()))
        SendAlert("Saved as " .. name, Color3.fromRGB(0, 255, 0))
        RefreshFileList()
    end)
    btns.RefreshList.Activated:Connect(RefreshFileList)
    btns.LoadRun.Activated:Connect(function()
        if SelectedFileToLoad == "" then SendAlert("No file selected!", Color3.fromRGB(255,0,0)); return end
        if PreloadedTASFilename ~= SelectedFileToLoad or not PreloadedTASData then
            if not PreloadTASFile(SelectedFileToLoad) then return end
        end
        LoadPreloadedRunIntoEditor()
    end)

    BuildFileTimestampControl(btns.LoadRun)
    RefreshFileList()
end

local function LoadUI(MapName)
    if UI_Elements and UI_Elements.ScreenGui and UI_Elements.ScreenGui.Parent then return end
    UI_Elements = TAS_UI.Create()

    -- Compact the main UI only. The mobile numpad is a separate ScreenGui.
    if UI_Elements.ScreenGui then
        local MainScale = UI_Elements.ScreenGui:FindFirstChild("TAS_MainUIScale")
        if not MainScale then
            MainScale = Instance.new("UIScale")
            MainScale.Name = "TAS_MainUIScale"
            MainScale.Parent = UI_Elements.ScreenGui
        end
        MainScale.Scale = 0.60
    end

    TimeText = UI_Elements.TimeText
    FrameCountLabel = UI_Elements.FrameCount
    StatusLabel = UI_Elements.StatusText
    MapEventLabel = UI_Elements.MapEventInfo
    
    if MapName and MapEventLabel then MapEventLabel.Text = MapName end
    BindUI()
end

UpdateTimeDisplay = function(DisplayTime)
    if not TimeText then return end
    local m = math.floor(DisplayTime / 60)
    local s = math.floor(DisplayTime % 60)
    local ms = math.floor(DisplayTime * 1000 % 1000)
    TimeText.Text = string.format("%d:%02d.%03d", m, s, ms)
end

-- // LIGHTING MANAGER //
local function CaptureLighting()
    SavedLighting.Props = {
        Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness,
        ClockTime = Lighting.ClockTime, FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd,
        FogStart = Lighting.FogStart, GlobalShadows = Lighting.GlobalShadows,
        ExposureCompensation = Lighting.ExposureCompensation, TimeOfDay = Lighting.TimeOfDay
    }
    SavedLighting.Children = {}
    for _, child in ipairs(Lighting:GetChildren()) do table.insert(SavedLighting.Children, child:Clone()) end
    LightingCaptured = true
end

local function EnforceLighting()
    if not LightingCaptured then return end
    for prop, val in pairs(SavedLighting.Props) do if Lighting[prop] ~= val then Lighting[prop] = val end end
    local CurrentChildren = Lighting:GetChildren()
    if #CurrentChildren ~= #SavedLighting.Children then
        Lighting:ClearAllChildren()
        for _, c in ipairs(SavedLighting.Children) do c:Clone().Parent = Lighting end
    end
end

-- // MAP MONITOR //
local MonitorCon = workspace.Multiplayer.ChildAdded:Connect(function(child)
    if not getgenv().TAS_Active then return end
    if ClonedMap and (child.Name == "Map" or child.Name == "NewMap") then task.wait(); child:Destroy() end
end)
AddConnection(MonitorCon)

-- // MAP PLAYBACK ENGINE //
UpdateMapState = function(TargetTime)
    if EnvPaused then return end
    
    while PlaybackIndex <= #MapEvents and MapEvents[PlaybackIndex].Time <= TargetTime do
        local Event = MapEvents[PlaybackIndex]
        if Event.Instance then
            if Event.Prop == "Destroyed" then
                Event.Instance.Transparency = 1
                if Event.Instance:IsA("BasePart") then
                    Event.Instance.CanCollide = false
                    Event.Instance.Anchored = true
                    if Event.ChildrenUUIDs then
                        for _, childUUID in ipairs(Event.ChildrenUUIDs) do
                            local child = MapUUIDs[childUUID]
                            if child then child.Transparency = 1 end
                        end
                    end
                end
            elseif Event.Prop == "Anchored" then
                if Event.NewVal == false and Event.Instance:IsA("BasePart") and Event.Instance.CanCollide == false then
                    Event.Instance.Anchored = true
                    Event.Instance.Transparency = 1
                else
                    Event.Instance.Anchored = Event.NewVal
                end
            else
                Event.Instance[Event.Prop] = Event.NewVal
            end
        end
        PlaybackIndex = PlaybackIndex + 1
    end
    
    while PlaybackIndex > 1 and MapEvents[PlaybackIndex - 1].Time > TargetTime do
        PlaybackIndex = PlaybackIndex - 1
        local Event = MapEvents[PlaybackIndex]
        if Event.Instance then
            if Event.Prop == "Destroyed" then
                if type(Event.OldVal) == "table" then
                    local s = Event.OldVal
                    Event.Instance.Transparency = s.Transparency
                    if Event.Instance:IsA("BasePart") then
                        Event.Instance.CanCollide = s.CanCollide; Event.Instance.CFrame = s.CFrame
                        Event.Instance.Anchored = s.Anchored; Event.Instance.Color = s.Color
                        Event.Instance.Size = s.Size; Event.Instance.Material = s.Material
                        Event.Instance.Reflectance = s.Reflectance
                    end
                    if Event.Instance:IsA("Decal") or Event.Instance:IsA("Texture") then
                         Event.Instance.Color3 = s.Color3; Event.Instance.Texture = s.Texture
                    end
                    if Event.Children and Event.ChildrenUUIDs then
                        for _, childUUID in ipairs(Event.ChildrenUUIDs) do
                            local child = MapUUIDs[childUUID]
                            local childState = Event.Children[childUUID]
                            if child and childState then
                                child.Transparency = childState.Transparency; child.Color3 = childState.Color3
                            end
                        end
                    end
                else
                    Event.Instance.Transparency = 0
                    if Event.Instance:IsA("BasePart") then Event.Instance.CanCollide = true end
                end
            elseif Event.Prop == "Anchored" then
                Event.Instance.Anchored = Event.OldVal
                if Event.OldVal == true and Event.StoredCFrame then
                    Event.Instance.CFrame = Event.StoredCFrame; Event.Instance.CanCollide = Event.StoredCanCollide
                    Event.Instance.Transparency = 0; Event.Instance.Velocity = Vector3.new(0,0,0)
                    Event.Instance.RotVelocity = Vector3.new(0,0,0)
                end
            else
                Event.Instance[Event.Prop] = Event.OldVal
            end
        end
    end
end

-- // BUTTON AUTO-SYNC //
-- The autofarm records expected button times with network-ping compensation.
-- When a recorded button is reached, shift PreviewOffset so the visual/map
-- timeline catches up with the recorded TAS timing.

-- // BUTTON SYNC LOGIC //
SyncButtonState = function(VisualTime, RealTime)
    for part, data in pairs(ButtonRegistry) do
        if data.IsPressed and data.TruePressTime > RealTime then
            data.IsPressed = false; data.PressTime = nil
        end
    end
    
    local NextIndex = 1
    for i = 1, #RecordedButtonSequence do
        local btnData = OrderedButtonRegistry[i]
        if btnData and not btnData.IsPressed then NextIndex = i; break end
        if i == #RecordedButtonSequence then NextIndex = i + 1 end
    end
    
    for part, data in pairs(ButtonRegistry) do
        local isVisuallyPressed = (data.TruePressTime and data.TruePressTime <= VisualTime)
        if isVisuallyPressed then data.SelectionBox.Color3 = Color3.fromRGB(0, 255, 0)
        elseif data.Order ~= 999 then
            if data.Order == NextIndex then data.SelectionBox.Color3 = Color3.fromRGB(255, 255, 0)
            elseif data.Order > NextIndex then data.SelectionBox.Color3 = Color3.fromRGB(255, 0, 0)
            else data.SelectionBox.Color3 = Color3.fromRGB(0, 255, 0) end
        else
            data.SelectionBox.Color3 = Color3.fromRGB(255, 140, 0)
        end
    end
end

local function HookAnimations()
    repeat
        local script = LocalPlayer.Character:WaitForChild("Animate")
        AnimEnv = getsenv(script)
        task.wait()
    until AnimEnv.playAnimation ~= nil
    OriginalPlayAnim = AnimEnv.playAnimation
    AnimEnv.playAnimation = function(anim, speed)
        if not IsPaused then
            CurrentAnim = {anim, speed}
            OriginalPlayAnim(CurrentAnim[1], CurrentAnim[2], LocalPlayer.Character.Humanoid)
        end
    end
end

-- // CLEANUP //
function ResetToNormal()
    PlaybackState.Active = false
    PlaybackState.Paused = false
    PlaybackState.Data = nil
    IsViewingTAS = false
    LoadedFileMode = false
    PendingEditCut = false
    PendingEditTime = 0
    getgenv().TAS_Active = false
    getgenv().IsSwimming = false
    getgenv().PauseSpoofing = false
    getgenv().EnableAutoSwim = false
    
    -- Disconnect all event listeners safely
    for _, con in pairs(Connections) do 
        pcall(function() con:Disconnect() end) 
    end
    Connections = {}
    
    -- Restore original animation engine
    if AnimEnv and OriginalPlayAnim then
        pcall(function()
            AnimEnv.playAnimation = OriginalPlayAnim
        end)
    end
    
    -- Restore native ambient lighting properties
    if LightingCaptured and SavedLighting.Props then
        pcall(function()
            for prop, val in pairs(SavedLighting.Props) do
                Lighting[prop] = val
            end
            Lighting:ClearAllChildren()
            for _, c in ipairs(SavedLighting.Children) do
                c:Clone().Parent = Lighting
            end
        end)
    end
    
    -- Clean up path & trajectory rendering elements
    for _, line in ipairs(TrajectoryLines) do pcall(function() line:Destroy() end) end
    TrajectoryLines = {}
    for _, line in ipairs(PathLines) do pcall(function() line:Destroy() end) end
    PathLines = {}
    if TrajectoryFolder then pcall(function() TrajectoryFolder:Destroy() end) end
    
    -- Reset noclip, speed, and positioning systems
    pcall(function() Noclip(false) end)
    pcall(function()
        local Root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if Root then Root.Anchored = false end
        local Hum = LocalPlayer.Character:FindFirstChild("Humanoid")
        if Hum then
            Hum.WalkSpeed = 16 -- Roblox standard WalkSpeed
            Hum.JumpPower = 50 -- Roblox standard JumpPower
        end
    end)
    
    TotalButtons = {}; ButtonRegistry = {}; OrderedButtonRegistry = {}; RecordedButtonSequence = {}
    MapEvents = {}; MapUUIDs = {}; SavedLighting = {Props = {}, Children = {}}; LightingCaptured = false; AutoSaved = false
    
    if ClonedMap then pcall(function() ClonedMap:Destroy() end); ClonedMap = nil end
    if UI_Elements and UI_Elements.ScreenGui then pcall(function() UI_Elements.ScreenGui:Destroy() end) end
    UI_Elements = nil

    if MobileGui then
        pcall(function() MobileGui:Destroy() end)
        MobileGui = nil
    end
    
    -- Clear physical character state variables through standard reset
    pcall(function() LocalPlayer.Character:BreakJoints() end)
    SendAlert("TAS Creator Stopped", Color3.fromRGB(255, 0, 0))
end

-- // CORE LOGIC IMPLEMENTATIONS //
function TogglePause()
    local pause = task.spawn(function()
        IsPaused = not IsPaused
        local Root = LocalPlayer.Character.HumanoidRootPart
        if IsPaused then
            SavedVelocity = Root.Velocity; Root.Anchored = true; PauseStart = tick()
            if StatusLabel then StatusLabel.Text = "PAUSED"; StatusLabel.TextColor3 = Color3.fromRGB(255, 200, 80) end
            SendAlert("Paused", Color3.fromRGB(255, 255, 0))
        else
            -- If a loaded file was seeked with the timestamp box, the first
            -- resume is the edit operation: discard the old future and keep
            -- the timeline starting exactly at the chosen timestamp.
            if LoadedFileMode and PendingEditCut then
                CutFramesAfterTime(PendingEditTime)
                RunStart = tick() - PendingEditTime
                TimeOffset = 0
                PauseStart = tick()
                PendingEditCut = false
                if FileTimestampStatus then FileTimestampStatus.Text = "EDITING • " .. FormatPlaybackTimestamp(PendingEditTime) end
                SendAlert("Future frames cut — recording from " .. FormatPlaybackTimestamp(PendingEditTime), Color3.fromRGB(0, 255, 255))
            end
            Root.Anchored = false; Root.Velocity = SavedVelocity; TimeOffset = TimeOffset + tick() - PauseStart
            if StatusLabel then StatusLabel.Text = "PLAYING"; StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255) end
            RecordAccumulator = 0
            SendAlert("Unpaused", Color3.fromRGB(0, 255, 0))
        end
    end)
end

function LoadLastSavestate()
    local LastState = Savestates[#Savestates]
    if LastState then
        local FramePacked = LastState[#LastState]
        if not FramePacked then return end
        local Frame = UnpackFrame(FramePacked)
        
        Frames = {}; IsPaused = true; PreviewOffset = 0
        local Root = LocalPlayer.Character.HumanoidRootPart
        Root.Anchored = true; Root.CFrame = Frame.CFrame + Vector3.new(MapX, MapY - 1000, MapZ)
        Root.Velocity = Frame.Velocity; SavedVelocity = Frame.Velocity
        
        workspace.CurrentCamera.CFrame = Frame.CameraCFrame
        PauseStart = tick(); RunStart = tick() - Frame.Time; TimeOffset = 0
        
        SyncButtonState(Frame.Time, Frame.Time); UpdateMapState(Frame.Time)
        
        OriginalPlayAnim(Frame.Animation[1], Frame.Animation[2], LocalPlayer.Character.Humanoid)
        if Frame.Animation[1] == "walk" then AnimEnv.setAnimationSpeed(0.76) end
        
        task.spawn(function() UpdateTimeDisplay(Frame.Time) end)
        SendAlert("Savestate Loaded", Color3.fromRGB(0, 255, 255))
    end
end

function AddSavestate()
    table.insert(Savestates, Frames); Frames = {}
    SendAlert("Savestate Added (" .. #Savestates .. ")", Color3.fromRGB(0, 255, 0))
end

local RemoveConfirm = false; local RemoveConfirmTime = 0
function RemoveSavestate()
    if not RemoveConfirm or (tick() - RemoveConfirmTime > 2) then
        RemoveConfirm = true; RemoveConfirmTime = tick()
        SendAlert("Press again to remove last state", Color3.fromRGB(255, 170, 0))
        return
    end
    RemoveConfirm = false
    if #Savestates > 1 then
        table.remove(Savestates); task.spawn(LoadLastSavestate)
        SendAlert("Savestate Removed", Color3.fromRGB(255, 0, 0))
    else
        SendAlert("Cannot remove initial state", Color3.fromRGB(255, 0, 0))
    end
end

local function Noclip(Toggle)
    local char = LocalPlayer.Character
    if char then
        for i, v in char:GetChildren() do if v:IsA("BasePart") then v.CanCollide = not Toggle end end
    end
end

-- // ADVANCED MAP RECORDER //
local function SetupMap()
    local MP = game.Workspace.Multiplayer
    local LiveMap = MP:WaitForChild("Map", 9e9)
    local Settings = LiveMap:FindFirstChild("Settings")
    local MapName = Settings and Settings:GetAttribute("MapName") or "Unknown Map"
    
    SendAlert("Map Detected: " .. MapName, Color3.fromRGB(0, 255, 255))
    
    local Spawn = LiveMap:FindFirstChild("Spawn", true)
    
    if not Spawn then
        local target = nil; local connections = {}
        for _, child in ipairs(LiveMap:GetChildren()) do
            if child.Name == "Part" and child.Size.Y < 5 then
                table.insert(connections, child:GetPropertyChangedSignal("Rotation"):Connect(function()
                    target = child
                    for _, con in ipairs(connections) do con:Disconnect() end
                end))
            end
        end
        repeat task.wait() until target; LiveMap.PrimaryPart = target
    else
        LiveMap.PrimaryPart = Spawn
    end
    
    CaptureLighting()
    
    for _, desc in ipairs(LiveMap:GetDescendants()) do
        if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then GetUUID(desc) end
    end
    
    LiveMap.Archivable = true
    for _, d in pairs(LiveMap:GetDescendants()) do d.Archivable = true end
    ClonedMap = LiveMap:Clone(); ClonedMap.Parent = nil 
    
    local Char = LocalPlayer.Character
    local Root = Char:WaitForChild("HumanoidRootPart")
    local Hum = Char:WaitForChild("Humanoid")
    
    local Recording = true; local StartTime = os.clock(); local Recorders = {}
    
    -- [[ SMART WHITELIST FOR .CHANGED ]] --
    local PropWhitelist = {
        BasePart = {["CFrame"] = true, ["Transparency"] = true, ["CanCollide"] = true, ["Color"] = true, ["Size"] = true, ["Anchored"] = true, ["Material"] = true, ["Reflectance"] = true},
        Decal = {["Transparency"] = true, ["Color3"] = true, ["Texture"] = true},
        Texture = {["Transparency"] = true, ["Color3"] = true, ["Texture"] = true, ["OffsetStudsU"] = true, ["OffsetStudsV"] = true, ["StudsPerTileU"] = true, ["StudsPerTileV"] = true}
    }
    
    local function TrackPart(Part)
        local id = GetUUID(Part); if not id then return end
        
        local MyWhitelist = nil
        if Part:IsA("BasePart") then MyWhitelist = PropWhitelist.BasePart elseif Part:IsA("Decal") then MyWhitelist = PropWhitelist.Decal elseif Part:IsA("Texture") then MyWhitelist = PropWhitelist.Texture end
        if not MyWhitelist then return end
        
        MapRecorderCache[Part] = {}
        for prop, _ in pairs(MyWhitelist) do
            local s, val = pcall(function() return Part[prop] end)
            if s then MapRecorderCache[Part][prop] = val end
        end
        
        local function OnChange(Prop)
            if not Recording then return end; if not MyWhitelist[Prop] then return end
            local NewVal = Part[Prop]; local OldVal = MapRecorderCache[Part][Prop]
            
            if NewVal ~= OldVal then
                local EventData = {Time = os.clock() - StartTime, UUID = id, Prop = Prop, OldVal = OldVal, NewVal = NewVal}
                if Prop == "Anchored" and Part:IsA("BasePart") then EventData.StoredCFrame = Part.CFrame; EventData.StoredCanCollide = Part.CanCollide end
                table.insert(MapEvents, EventData); MapRecorderCache[Part][Prop] = NewVal
            end
        end
        
        table.insert(Recorders, Part.Changed:Connect(OnChange))
        
        table.insert(Recorders, Part.Destroying:Connect(function()
            if not Recording then return end
            local State = DeepCopy(MapRecorderCache[Part])
            local ChildrenUUIDs = {}; local ChildrenStates = {}
            if Part:IsA("BasePart") then
                for _, child in ipairs(Part:GetChildren()) do
                    if (child:IsA("Decal") or child:IsA("Texture")) and MapRecorderCache[child] then
                        local childID = GetUUID(child)
                        table.insert(ChildrenUUIDs, childID); ChildrenStates[childID] = DeepCopy(MapRecorderCache[child])
                    end
                end
            end
            table.insert(MapEvents, {Time = os.clock() - StartTime, UUID = id, Prop = "Destroyed", OldVal = State, Children = ChildrenStates, ChildrenUUIDs = ChildrenUUIDs, NewVal = true})
        end))
    end

    for _, Object in ipairs(LiveMap:GetDescendants()) do if Object:IsA("BasePart") or Object:IsA("Decal") or Object:IsA("Texture") then TrackPart(Object) end end
    table.insert(Recorders, LiveMap.DescendantAdded:Connect(function(d) if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then TrackPart(d) end end))

    SendAlert("Scanning for Buttons...", Color3.fromRGB(255, 170, 0))
    
    local Buttons = {}
    for i, MapObject in pairs(LiveMap:GetDescendants()) do
        if isRandomString(MapObject.Name) and MapObject:IsA("Model") then
            local Hitbox
            for i, Candidate in pairs(MapObject:GetChildren()) do
                if Candidate:IsA("BasePart") and tostring(Candidate.BrickColor) ~= "Medium stone grey" then Hitbox = Candidate; break end
            end
            if Hitbox and isRandomString(Hitbox.Name) then Hitbox.Name = "Hitbox"; table.insert(Buttons, MapObject) end
        end
    end
    
    SendAlert("Autofarm: Found " .. #Buttons .. " Buttons", Color3.fromRGB(0, 255, 0))
    SendAlert("Commencing Auto Farm", Color3.fromRGB(255, 170, 0))

    Noclip(true)
    local GodModeCon = RunService.RenderStepped:Connect(function() if Hum then Hum.Health = 99999 end end)
    
    local LastSafePos = CFrame.new(0, 1000, 0)
    local LiveExitRegion = nil 
    local LastTargetButton = nil
    RecordedButtonSequence = {}
    task.delay(60, function()
        pcall(function()
            GodModeCon:Disconnect()
            SendAlert("God Mode Disabled! You can reset now.", Color3.fromRGB(255, 140, 0))
        end)
    end)
    while Recording and LiveMap.Parent and Hum.Health > 0 do
        Hum.Jump = true
        if not LiveExitRegion then LiveExitRegion = LiveMap:FindFirstChild("ExitRegion", true) end
        
        local FailedScan = true; Root.Anchored = true
        
        for i, Button in pairs(Buttons) do
            local ButtonHitbox = Button:FindFirstChild("Hitbox")
            if ButtonHitbox then
                local TouchFound = Button:FindFirstChild("TouchInterest", true)
                local GuiFound = Button:FindFirstChildWhichIsA("BillboardGui", true)
                
                if (TouchFound and GuiFound) then
                    FailedScan = false; Root.Anchored = false
                    
                    if Button ~= LastTargetButton then
                        local uuid = GetUUID(ButtonHitbox)
                        if uuid and not table.find(RecordedButtonSequence, uuid) then
                            table.insert(RecordedButtonSequence, uuid)
                        end
                        if LastTargetButton ~= nil then task.wait(0.1) end
                        LastTargetButton = Button
                    else
                        local uuid = GetUUID(ButtonHitbox)
                        if uuid and not table.find(RecordedButtonSequence, uuid) then
                            table.insert(RecordedButtonSequence, uuid)
                        end
                    end
                    Root.CFrame = CFrame.new(ButtonHitbox.Position)
                    Root.Velocity = Vector3.new(0, 0, 0)
                    Hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    task.wait(0.255/15)
                end
            end
        end
        
        if FailedScan then
            -- Ensure player isn't anchored to prevent hanging on last button serverside.
            Root.Anchored = false
            Hum:ChangeState(Enum.HumanoidStateType.Running)
            if LiveExitRegion then
                Root.CFrame = LiveExitRegion.CFrame + Vector3.new(0, 100, 0); Root.Velocity = Vector3.new(0,0,0)
            else
                Root.CFrame = LastSafePos + Vector3.new(0, 10, 0); Root.Velocity = Vector3.new(0,0,0)
            end
        else
            LastSafePos = Root.CFrame
        end
        RunService.Heartbeat:Wait()
    end
    
    Recording = false
    if GodModeCon then GodModeCon:Disconnect() end
    SendAlert("Recording Finished", Color3.fromRGB(255, 0, 0))
    Noclip(false)
    for _, r in ipairs(Recorders) do r:Disconnect() end
    
    CaptureLighting(); SendAlert("Processing Map...", Color3.fromRGB(0, 200, 255))
    if LiveMap then LiveMap.Archivable = true; LiveMap:Destroy() end
    
    ClonedMap.Parent = workspace
    MapUUIDs = {}
    for _, desc in ipairs(ClonedMap:GetDescendants()) do
        local id = desc:GetAttribute("TAS_UUID")
        if id then MapUUIDs[id] = desc end
    end
    
    for _, Event in ipairs(MapEvents) do Event.Instance = MapUUIDs[Event.UUID] end
    for i = #MapEvents, 1, -1 do
        local Event = MapEvents[i]
        if Event.Instance then if Event.Prop ~= "Destroyed" then Event.Instance[Event.Prop] = Event.OldVal end end
    end
    
    if not ClonedMap.PrimaryPart then
         local LiveName = LiveMap.PrimaryPart.Name
         ClonedMap.PrimaryPart = ClonedMap:FindFirstChild(LiveName, true)
    end
    
    MapPos = ClonedMap.PrimaryPart.Position
    MapX, MapY, MapZ = MapPos.X, MapPos.Y, MapPos.Z
    MapOffset = CFrame.new(MapX, MapY, MapZ)
    
    Char.Humanoid.Health = 0
    SendAlert("Respawning...", Color3.fromRGB(255, 255, 0))
    LocalPlayer.CharacterAdded:Wait(); Char = LocalPlayer.Character; task.wait(1)
    -- FE2CM method
    Char:BreakJoints();
    SendAlert("Double Respawning...", Color3.fromRGB(255, 255, 0))
    LocalPlayer.CharacterAdded:Wait(); Char = LocalPlayer.Character; task.wait(5)
    
    local FE2Env = getsenv(Char:WaitForChild("FE2_Character"))
    local startZipline = FE2Env.startZipline
    if RopeTable and #RopeTable >= 1 then
        SendAlert("Zipline Data Restored", Color3.fromRGB(0, 255, 255))
        task.spawn(function()
            while Char and Char.Humanoid.Health >= 1 do setupvalue(startZipline, 2, RopeTable); task.wait() end
        end)
    end
    
    Root = Char:WaitForChild("HumanoidRootPart"); Hum = Char:WaitForChild("Humanoid")
    Hum.WalkSpeed = 0; Hum.JumpPower = 0; task.wait(0.5); Hum.WalkSpeed = 0; Hum.JumpPower = 0
    
    Root.CFrame = CFrame.new(ClonedMap.PrimaryPart.Position) + Vector3.new(0, ClonedMap.PrimaryPart.Size.Y/2, 0) + Vector3.new(0, Root.Size.Y/2, 0) + Vector3.new(0, Char["Left Leg"].Size.Y, 0)
    task.wait(0.5); Root.Anchored = true; Hum.WalkSpeed = 20; Hum.JumpPower = 50
    
    table.insert(Savestates, {PackFrame(0, Vector3.new(0,0,0), GetPlayerCFrame(), workspace.CurrentCamera.CFrame, {"idle", 0})})
    PauseStart = tick(); RunStart = tick(); HookAnimations()
    
    AddConnection(LocalPlayer.CharacterAdded:Connect(function(c)
        local anim = c:WaitForChild("Animate")
        if anim.Enabled then HookAnimations() end
    end))
    
    LoadUI(MapName)
    
    WaterParts = {}; TotalButtons = {}; ButtonRegistry = {}; OrderedButtonRegistry = {}
    local CheckedButtonParts = {}

    for _, obj in ipairs(ClonedMap:GetDescendants()) do
        if obj:IsA("BasePart") then
             if obj.Name:find("_Water") then table.insert(WaterParts, obj) end
             
             -- Dynamic Zipline / Rope Touch Listener
             if obj.Name == "RopeStart" then
                 AddConnection(obj.Touched:Connect(function(hit)
                     if hit.Parent == LocalPlayer.Character and not getgenv().PauseSpoofing then
                         getgenv().PauseSpoofing = true
                         -- Pause spoofing temporarily to let the engine register the zipline touch and attach the player
                         task.wait(0.5) 
                         getgenv().PauseSpoofing = false
                     end
                 end))
             end
        end
        if obj.Name == "ButtonIcon" then
            local ButtonPart = nil
            if obj.Parent and obj.Parent.Parent and obj.Parent.Parent:IsA("BasePart") then ButtonPart = obj.Parent.Parent
            elseif obj.Parent and obj.Parent.Parent and obj.Parent.Parent:IsA("Model") then ButtonPart = obj.Parent.Parent:FindFirstChildOfClass("BasePart") end
            if ButtonPart and not CheckedButtonParts[ButtonPart] then
                CheckedButtonParts[ButtonPart] = true
                table.insert(TotalButtons, ButtonPart)
                
                local sel = Instance.new("SelectionBox", ButtonPart)
                sel.Adornee = ButtonPart; sel.Color3 = Color3.fromRGB(255, 140, 0); sel.SurfaceTransparency = 0.8
                ButtonPart.CanTouch = true
                
                local uuid = GetUUID(ButtonPart)
                local order = table.find(RecordedButtonSequence, uuid) or 999
                local bData = {IsPressed = false, PressTime = nil, SelectionBox = sel, Order = order}
                ButtonRegistry[ButtonPart] = bData; OrderedButtonRegistry[order] = bData
                
                AddConnection(ButtonPart.Touched:Connect(function(hit)
                    if hit.Parent == LocalPlayer.Character and not bData.IsPressed then
                        if not RunStart then return end
                        if bData.Order and bData.Order > 1 then
                            local prevBtn = OrderedButtonRegistry[bData.Order - 1]
                            if prevBtn and not prevBtn.IsPressed then SendAlert("WRONG ORDER! Press Button #" .. (bData.Order - 1) .. " first!", Color3.fromRGB(255, 0, 0)); return end
                        end
                        
                        local RealTime = tick() - RunStart - TimeOffset
                        
                        bData.IsPressed = true; bData.PressTime = RealTime; bData.TruePressTime = RealTime 
                        sel.Color3 = Color3.fromRGB(0, 255, 0)
                        SendAlert("Button " .. (order ~= 999 and "#"..order or "") .. " Pressed!", Color3.fromRGB(0, 255, 0))
                    end
                end))
            end
        end
        
        if isRandomString(obj.Name) and obj:IsA("Model") then
            if obj.Name == "NPC" or obj:FindFirstAncestor("_Rescue") then
            else
                local hp = obj:FindFirstChild("Hitbox") 
                if not hp then
                    for _, c in ipairs(obj:GetChildren()) do
                        if c:IsA("BasePart") and tostring(c.BrickColor) ~= "Medium stone grey" then hp = c; break end
                    end
                end
                if hp and not CheckedButtonParts[hp] then
                    CheckedButtonParts[hp] = true
                    table.insert(TotalButtons, hp)
                    
                    local sel = Instance.new("SelectionBox", hp)
                    sel.Adornee = hp; sel.Color3 = Color3.fromRGB(255, 140, 0); sel.SurfaceTransparency = 0.8
                    hp.CanTouch = true
                    
                    local uuid = GetUUID(hp)
                    local order = table.find(RecordedButtonSequence, uuid) or 999
                    local bData = {IsPressed = false, PressTime = nil, SelectionBox = sel, Order = order}
                    ButtonRegistry[hp] = bData; OrderedButtonRegistry[order] = bData
                    
                    AddConnection(hp.Touched:Connect(function(hit)
                        if hit.Parent == LocalPlayer.Character and not bData.IsPressed then
                            if not RunStart then return end
                            if bData.Order and bData.Order > 1 then
                                local prevBtn = OrderedButtonRegistry[bData.Order - 1]
                                if prevBtn and not prevBtn.IsPressed then SendAlert("WRONG ORDER! Press Button #" .. (bData.Order - 1) .. " first!", Color3.fromRGB(255, 0, 0)); return end
                            end
                            
                            local RealTime = tick() - RunStart - TimeOffset
                            
                            bData.IsPressed = true; bData.PressTime = RealTime; bData.TruePressTime = RealTime 
                            sel.Color3 = Color3.fromRGB(0, 255, 0)
                            SendAlert("Button " .. (order ~= 999 and "#"..order or "") .. " Pressed!", Color3.fromRGB(0, 255, 0))
                        end
                    end))
                end
            end
        end
    end
    SendAlert("Map Ready & Linked", Color3.fromRGB(0, 255, 0))
end

-- // FAST FORWARD / REWIND PLAYER //
function StepForward()
    if not IsPaused then return end 
    local InitialFrames = #Frames; TogglePause(); RecordAccumulator = RECORD_INTERVAL + 0.1 
    repeat RunService.Heartbeat:Wait(); if IsRewinding then break end until #Frames > InitialFrames
    if not IsPaused then TogglePause() end
end

local function FrameAdvanceLoop()
    if IsRewinding then return end
    if IsAdvancingFrame then return end
    IsAdvancingFrame = true; SendAlert("Step Forward", Color3.fromRGB(0, 255, 0))
    while IsAdvancingFrame do if IsRewinding then IsAdvancingFrame = false; break end; StepForward() end
end

function RewindFrame()
    if LocalPlayer.Character then
        local FramePacked = Frames[#Frames - 1]
        if not FramePacked and #Savestates > 0 then local PrevState = Savestates[#Savestates]; FramePacked = PrevState[#PrevState - 1] end
        if FramePacked then
            local Frame = UnpackFrame(FramePacked)
            if not IsPaused then TogglePause() end
            local Root = LocalPlayer.Character.HumanoidRootPart
            Root.CFrame = Frame.CFrame + Vector3.new(MapX, MapY - 1000, MapZ)
            Root.Velocity = Frame.Velocity; SavedVelocity = Frame.Velocity
            workspace.CurrentCamera.CFrame = Frame.CameraCFrame
            PauseStart = tick(); RunStart = tick() - Frame.Time; TimeOffset = 0
            
            local VisualTime = Frame.Time + PreviewOffset
            SyncButtonState(VisualTime, Frame.Time); UpdateMapState(VisualTime)
            
            if Frame.Animation[1] then OriginalPlayAnim(Frame.Animation[1], Frame.Animation[2], LocalPlayer.Character.Humanoid) end
            if Frame.Animation[1] == "walk" then AnimEnv.setAnimationSpeed(0.76) end
            
            task.spawn(function() UpdateTimeDisplay(VisualTime) end)
            Frames[#Frames] = nil
        end
    end
end

function RewindLoop()
    if IsAdvancingFrame then return end
    IsRewinding = true; SendAlert("Rewinding...", Color3.fromRGB(255, 0, 0))
    RewindFrame(); while task.wait(0.05) and IsRewinding do RewindFrame() end
end

-- // VIEW TAS (IMPROVED PLAYER LOGIC) //
local IsTASSliding = false
local function ToggleTASSlide(val)
    if not LocalPlayer.Character then return end
    if val then
        if LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then LocalPlayer.Character.HumanoidRootPart.Size = Vector3.new(2, 1, 1) end
        if LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.HipHeight = -1.5 end
    else
        if LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then LocalPlayer.Character.HumanoidRootPart.Size = Vector3.new(2, 2, 1) end
        if LocalPlayer.Character:FindFirstChild("Humanoid") then LocalPlayer.Character.Humanoid.HipHeight = 0 end
    end
end

local LastTASAnim = nil
function ActivateTASAnimation(AnimData)
    if not AnimData then OriginalPlayAnim("idle", 0.1, LocalPlayer.Character.Humanoid); return end
    if not LocalPlayer.Character then return end
    local n = AnimData[1]; local animTime = AnimData[2] or 0.1
    if LocalPlayer.Character.Humanoid:GetState() == Enum.HumanoidStateType.Physics then n = "swing" end
    if n == "idle" then
        local vel = LocalPlayer.Character.HumanoidRootPart.Velocity
        if vel.Magnitude > 1 then
            if LocalPlayer.Character.Humanoid.FloorMaterial ~= Enum.Material.Air then n = "walk"; animTime = 0.1 else n = "fall"; animTime = 0.3 end
        end
    end
    if n == "fall" and LocalPlayer.Character.HumanoidRootPart.Velocity.Magnitude < 0.1 then n = "swing" end
    if n == "slide" then if not IsTASSliding then ToggleTASSlide(true); IsTASSliding = true end else if IsTASSliding then ToggleTASSlide(false); IsTASSliding = false end end
    if n and (n == "swing" or n == "zipline" or n ~= LastTASAnim) then
        if OriginalPlayAnim then
            pcall(function() OriginalPlayAnim(n, animTime, LocalPlayer.Character.Humanoid) end)
        end
        if n == "walk" and AnimEnv and AnimEnv.setAnimationSpeed then
            pcall(function() AnimEnv.setAnimationSpeed(0.76) end)
        end
        LastTASAnim = n
    end
end

-- Apply a JSON TAS sample at an arbitrary playback timestamp.
-- PlaybackTAS calls this both on startup and every Heartbeat; keeping it
-- separate from the editor's packed-frame seeker avoids mixing the two paths.
local function ApplyPlaybackFrameAtTime(Data, targetTime)
    if type(Data) ~= "table" or #Data == 0 then return end

    targetTime = math.max(0, tonumber(targetTime) or 0)
    local firstTime = tonumber(Data[1].time) or 0
    local lastTime = tonumber(Data[#Data].time) or firstTime
    targetTime = math.clamp(targetTime, firstTime, lastTime)

    local lo, hi = 1, #Data
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if (tonumber(Data[mid].time) or 0) <= targetTime then
            lo = mid
        else
            hi = mid - 1
        end
    end

    local A = Data[lo]
    local B = Data[math.min(lo + 1, #Data)] or A
    local ta = tonumber(A.time) or 0
    local tb = tonumber(B.time) or ta
    local span = tb - ta
    local alpha = span > 0 and math.clamp((targetTime - ta) / span, 0, 1) or 0

    local function MakeCFrame(values)
        if type(values) ~= "table" or #values < 6 then return nil end
        return CFrame.new(values[1], values[2], values[3]) * CFrame.fromEulerAnglesXYZ(values[4], values[5], values[6])
    end

    local cfA = MakeCFrame(A.CCFrame)
    local cfB = MakeCFrame(B.CCFrame) or cfA
    if not cfA then return end

    local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local Cam = workspace.CurrentCamera
    local Offset = ClonedMap and ClonedMap.PrimaryPart and (ClonedMap.PrimaryPart.Position - Vector3.new(0, 1000, 0)) or Vector3.zero

    if Root then
        Root.Anchored = true
        Root.CFrame = cfA:Lerp(cfB, alpha) + Offset

        local va = A.VVelocity
        local vb = B.VVelocity or va
        if type(va) == "table" and #va >= 3 then
            local vA = Vector3.new(va[1] or 0, va[2] or 0, va[3] or 0)
            local vB = Vector3.new(vb and vb[1] or vA.X, vb and vb[2] or vA.Y, vb and vb[3] or vA.Z)
            Root.Velocity = vA:Lerp(vB, alpha)
            SavedVelocity = Root.Velocity
        end
    end

    if getgenv().PlaybackCamera and Cam then
        local camA = MakeCFrame(A.CCameraCFrame)
        local camB = MakeCFrame(B.CCameraCFrame) or camA
        if camA then Cam.CFrame = camA:Lerp(camB, alpha) + Offset end
    end

    ActivateTASAnimation(A.AAnimation or {"walk", 0.1})
    UpdateMapState(targetTime)
    SyncButtonState(targetTime, targetTime)
    UpdateTimeDisplay(targetTime)
end

function PlaybackTAS(Data)
    if type(Data) ~= "table" or #Data == 0 then
        SendAlert("TAS file is empty or invalid", Color3.fromRGB(255, 0, 0))
        return
    end

    LoadedFileMode = false
    PendingEditCut = false
    IsViewingTAS = true
    PlaybackState.Active = true
    PlaybackState.Paused = false
    PlaybackState.Time = 0
    PlaybackState.Data = Data
    PlaybackState.OldFrame = 1
    SendAlert("Viewing TAS Preview", Color3.fromRGB(183, 0, 255))

    if getgenv().ExtremeSmoothing then
        local smoothed = {}
        local interval = 1 / getgenv().TargetSmoothingFPS
        local nextT = 0
        for i, frame in ipairs(Data) do
            if frame.time >= nextT or i == 1 or i == #Data then
                table.insert(smoothed, frame)
                nextT = frame.time + interval
            end
        end
        Data = smoothed
        PlaybackState.Data = Data
    end

    local Root = LocalPlayer.Character.HumanoidRootPart
    local Offset = ClonedMap.PrimaryPart.Position - Vector3.new(0, 1000, 0)
    PlaybackState.Offset = Offset
    PlaybackState.PlayStart = tick()
    Root.Anchored = true
    IsTASSliding = false
    LastTASAnim = nil

    if getgenv().ShowTASPathDuringPlayback then
        for _, line in ipairs(PathLines) do line:Destroy() end; PathLines = {}
        local NewV = Vector3.new
        for i = 1, #Data - 1, (getgenv().ExtremeSmoothing and 1 or 4) do
            local p1 = NewV(Data[i].CCFrame[1], Data[i].CCFrame[2], Data[i].CCFrame[3]) + Offset
            local p2 = NewV(Data[i+1].CCFrame[1], Data[i+1].CCFrame[2], Data[i+1].CCFrame[3]) + Offset
            local dist = (p2 - p1).Magnitude
            if dist > 0.05 then
                local line = Instance.new("CylinderHandleAdornment")
                line.Radius = 0.15; line.Color3 = Color3.fromRGB(0, 255, 255); line.Transparency = 0.3
                line.Height = dist; line.CFrame = CFrame.lookAt(p1 + (p2 - p1)/2, p2)
                line.Adornee = workspace.Terrain; line.Parent = TrajectoryFolder
                table.insert(PathLines, line)
            end
        end
    end

    -- Start exactly at the first sample instead of waiting for the first heartbeat.
    PlaybackState.Time = Data[1].time or 0
    PlaybackState.PlayStart = tick() - PlaybackState.Time
    PlaybackState.OldFrame = 1
    ApplyPlaybackFrameAtTime(Data, PlaybackState.Time)

    local Con
    Con = RunService.Heartbeat:Connect(function()
        if not IsViewingTAS or not PlaybackState.Active then
            Con:Disconnect(); Root.Anchored = true; ToggleTASSlide(false)
            for _, line in ipairs(PathLines) do line:Destroy() end; PathLines = {}
            return
        end

        Root.Anchored = true
        if not PlaybackState.Paused then
            PlaybackState.Time = math.max(0, tick() - PlaybackState.PlayStart)
        end

        local elapsed = PlaybackState.Time
        ApplyPlaybackFrameAtTime(Data, elapsed)

        if elapsed >= (Data[#Data].time or 0) then
            PlaybackState.Time = Data[#Data].time or elapsed
            ApplyPlaybackFrameAtTime(Data, PlaybackState.Time)
            PlaybackState.Active = false
            IsViewingTAS = false
            Con:Disconnect(); Root.Anchored = true; ToggleTASSlide(false)
            for _, line in ipairs(PathLines) do line:Destroy() end; PathLines = {}
            SendAlert("TAS Preview Finished", Color3.fromRGB(0, 255, 0))
            return
        end
    end)
    AddConnection(Con)
end

-- // PREDICTIVE TRAJECTORY VISUALIZER //
local LastTrajectoryUpdate = 0
AddConnection(RunService.RenderStepped:Connect(function()
    if not getgenv().TAS_Active or not getgenv().ShowVelocityPredictor or IsViewingTAS then
        for _, l in ipairs(TrajectoryLines) do l.Visible = false end; return 
    end
    
    local now = os.clock()
    if now - LastTrajectoryUpdate < 1/15 then return end
    LastTrajectoryUpdate = now

    local char = LocalPlayer.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if root and root.Velocity.Magnitude > 0.5 then
        local p = root.Position; local v = root.Velocity; local dt = 1/60
        local grav = getgenv().IsSwimming and Vector3.new(0, -20, 0) or Vector3.new(0, -workspace.Gravity, 0)
        local rayParams = RaycastParams.new(); rayParams.FilterDescendantsInstances = {char}
        
        local points, vels = {p}, {v}
        for frame = 1, 90 do
            if getgenv().IsSwimming then v = v * 0.95 end
            v = v + (grav * dt); local stepVec = v * dt
            
            local hit = workspace:Raycast(p, stepVec, rayParams)
            if hit then p = hit.Position; table.insert(points, p); table.insert(vels, v); break end
            p = p + stepVec; table.insert(points, p); table.insert(vels, v)
        end
        
        for i = 1, #points - 1 do
            local line = TrajectoryLines[i]
            if not line then
                line = Instance.new("CylinderHandleAdornment"); line.Radius = 0.15; line.Adornee = workspace.Terrain; line.Parent = TrajectoryFolder; TrajectoryLines[i] = line
            end
            local p1, p2 = points[i], points[i+1]
            line.Height = (p2 - p1).Magnitude; line.CFrame = CFrame.lookAt(p1 + (p2 - p1)/2, p2)
            local speed = vels[i].Magnitude; line.Color3 = speed > 30 and Color3.new(1,0,0) or Color3.new(0,1,0)
            line.Visible = true
        end
        for i = #points, #TrajectoryLines do TrajectoryLines[i].Visible = false end
    else
        for _, l in ipairs(TrajectoryLines) do l.Visible = false end
    end
end))

-- // MAIN EXECUTION //
task.spawn(function()
    local Remote = game:GetService("ReplicatedStorage"):WaitForChild("Remote")
    local UpdRopeData = Remote:FindFirstChild("UpdRopeData")
    if not UpdRopeData then
        --Hardcoded obfuscated name highly volatile.
        UpdRopeData = Remote:FindFirstChild("oBoPcLGDkNQjGAPHvlWujHyuqmatLeGx")
    end
    if UpdRopeData then
        UpdRopeData.OnClientEvent:Connect(function(val) if type(val) == "table" and not ClonedMap then RopeTable = val end end)
    else
        SendAlert("Warning: Rope Data Remote Not Found!", Color3.fromRGB(255, 0, 0))
    end
end)

game.Workspace.Multiplayer:WaitForChild("NewMap", 9e99)
game.Workspace.Multiplayer:WaitForChild("Map", 9e99)
repeat task.wait() until LocalPlayer.Character.HumanoidRootPart.Anchored == false
SetupMap()

-- // MOBILE TOUCH CONTROLS (Numpad) //
-- Separate ScreenGui so the main UI can be scaled independently.
do
    if MobileGui then pcall(function() MobileGui:Destroy() end) end

    MobileGui = Instance.new("ScreenGui")
    MobileGui.Name = "TAS_Mobile"
    MobileGui.Parent = game:GetService("CoreGui")
    MobileGui.ResetOnSpawn = false
    MobileGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    MobileGui.DisplayOrder = 100

    local Pad = Instance.new("Frame", MobileGui)
    Pad.Name = "Numpad"
    Pad.AnchorPoint = Vector2.new(1, 0.5)
    Pad.Position = UDim2.new(1, -10, 0.35, 0)
    Pad.Size = UDim2.new(0, 175, 0, 244)
    Pad.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
    Pad.BackgroundTransparency = 0.2
    Pad.BorderSizePixel = 0
    Pad.ZIndex = 10

    Instance.new("UICorner", Pad).CornerRadius = UDim.new(0, 8)
    local pStroke = Instance.new("UIStroke", Pad)
    pStroke.Color = Color3.fromRGB(60, 60, 70)
    pStroke.Thickness = 1

    local pPad = Instance.new("UIPadding", Pad)
    pPad.PaddingTop = UDim.new(0, 5)
    pPad.PaddingBottom = UDim.new(0, 5)
    pPad.PaddingLeft = UDim.new(0, 5)
    pPad.PaddingRight = UDim.new(0, 5)

    local pLayout = Instance.new("UIListLayout", Pad)
    pLayout.SortOrder = Enum.SortOrder.LayoutOrder
    pLayout.Padding = UDim.new(0, 3)
    pLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

    local function MkRow(order)
        local r = Instance.new("Frame", Pad)
        r.BackgroundTransparency = 1
        r.Size = UDim2.new(1, 0, 0, 34)
        r.LayoutOrder = order

        local l = Instance.new("UIListLayout", r)
        l.FillDirection = Enum.FillDirection.Horizontal
        l.Padding = UDim.new(0, 3)
        l.SortOrder = Enum.SortOrder.LayoutOrder
        l.HorizontalAlignment = Enum.HorizontalAlignment.Center
        l.VerticalAlignment = Enum.VerticalAlignment.Center
        return r
    end

    local function MkBtn(parent, text, ord, w, col)
        local b = Instance.new("TextButton", parent)
        b.Size = UDim2.new(0, w or 38, 1, 0)
        b.BackgroundColor3 = col or Color3.fromRGB(45, 45, 55)
        b.BorderSizePixel = 0
        b.Font = Enum.Font.GothamBold
        b.Text = text
        b.TextColor3 = Color3.fromRGB(240, 240, 240)
        b.TextSize = 13
        b.AutoButtonColor = true
        b.LayoutOrder = ord or 0
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
        return b
    end

    local r0 = MkRow(0)
    local bCaps = MkBtn(r0, "CAPS", 0, 161, Color3.fromRGB(160, 120, 10))

    local r1 = MkRow(1)
    local b1 = MkBtn(r1, "1", 1)
    local b2 = MkBtn(r1, "2", 2)
    local b3 = MkBtn(r1, "3", 3)

    local r2 = MkRow(2)
    local b4 = MkBtn(r2, "4", 1)
    local b5 = MkBtn(r2, "5", 2)
    local b6 = MkBtn(r2, "6", 3)
    local b0 = MkBtn(r2, "0", 4)

    local r3 = MkRow(3)
    local bC = MkBtn(r3, "C", 1)
    local bEq = MkBtn(r3, "=", 2)
    local bSwim = MkBtn(r3, "S", 3)

    local r4 = MkRow(4)
    local bUp = MkBtn(r4, "▲", 1)
    local bDn = MkBtn(r4, "▼", 2)
    local bF8 = MkBtn(r4, "F8", 3)

    local r5 = MkRow(5)
    local bDel = MkBtn(r5, "DEL", 0, 161, Color3.fromRGB(160, 35, 35))

    bCaps.Activated:Connect(TogglePause)
    b1.Activated:Connect(AddSavestate)
    b2.Activated:Connect(RemoveSavestate)
    b3.Activated:Connect(function() task.spawn(LoadLastSavestate) end)

    b6.Activated:Connect(function()
        local name = (UI_Elements and UI_Elements.SaveBox and UI_Elements.SaveBox.Text ~= "")
            and UI_Elements.SaveBox.Text
            or (ClonedMap and ClonedMap.Settings:GetAttribute("MapName") or "MyRun")

        if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
        writefile("Flood-GUI/TAS FILES/" .. name .. ".json", HttpService:JSONEncode(CompileTASData()))
        SendAlert("Saved as " .. name, Color3.fromRGB(0, 255, 0))
        RefreshFileList()
    end)

    bC.Activated:Connect(ToggleCollision)

    bEq.Activated:Connect(function()
        EnvPaused = not EnvPaused
        SendAlert("Map Updates " .. (EnvPaused and "Paused" or "Active"), Color3.fromRGB(255, 255, 0))
    end)

    bSwim.Activated:Connect(function()
        getgenv().EnableAutoSwim = not getgenv().EnableAutoSwim
        SendAlert(
            "Auto-Swim " .. (getgenv().EnableAutoSwim and "ON" or "OFF"),
            getgenv().EnableAutoSwim and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0)
        )
    end)

    bF8.Activated:Connect(function()
        IsPreviewingForward = false
        IsPreviewingBackward = false
        PreviewOffset = 0
        SendAlert("Visuals Resynced", Color3.fromRGB(0, 255, 255))
    end)

    bDel.Activated:Connect(function() task.spawn(ResetToNormal) end)

    b0.Activated:Connect(function()
        if not IsViewingTAS then PlaybackTAS(CompileTASData()) end
    end)

    local function HookHold(btn, onPress, onRelease)
        btn.MouseButton1Down:Connect(onPress)
        btn.MouseButton1Up:Connect(onRelease)
        btn.InputEnded:Connect(function(inp)
            if inp.UserInputType == Enum.UserInputType.Touch then onRelease() end
        end)
    end

    HookHold(b4, function()
        if IsAdvancingFrame then IsAdvancingFrame = false; task.wait() end
        task.spawn(RewindLoop)
    end, function() IsRewinding = false end)

    HookHold(b5, function()
        if IsRewinding then return end
        if not IsAdvancingFrame then task.spawn(FrameAdvanceLoop) end
    end, function() IsAdvancingFrame = false end)

    HookHold(bUp, function() IsPreviewingForward = true end, function() IsPreviewingForward = false end)
    HookHold(bDn, function() IsPreviewingBackward = true end, function() IsPreviewingBackward = false end)

    -- Draggable with mouse or touch.
    do
        local dragging, dragInput, dragStart, startPos

        Pad.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1
                or input.UserInputType == Enum.UserInputType.Touch then
                dragging = true
                dragStart = input.Position
                startPos = Pad.Position
                input.Changed:Connect(function()
                    if input.UserInputState == Enum.UserInputState.End then dragging = false end
                end)
            end
        end)

        Pad.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement
                or input.UserInputType == Enum.UserInputType.Touch then
                dragInput = input
            end
        end)

        AddConnection(UserInputService.InputChanged:Connect(function(input)
            if input == dragInput and dragging then
                local delta = input.Position - dragStart
                Pad.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + delta.X,
                    startPos.Y.Scale, startPos.Y.Offset + delta.Y
                )
            end
        end))
    end

    SendAlert("Mobile Controls Ready", Color3.fromRGB(0, 255, 100))
end

-- // HEARTBEAT LOOP //
local LastHeartbeat = tick()
local HBCon = RunService.Heartbeat:Connect(function(dt)
    if not getgenv().TAS_Active then return end
    if not UI_Elements or not UI_Elements.ScreenGui or not UI_Elements.ScreenGui.Parent then return end
    EnforceLighting()

    if not RunStart then return end
    if IsViewingTAS or IsRewinding or IsAdvancingFrame then return end

    if IsPreviewingForward then PreviewOffset = PreviewOffset + (dt * 5) end
    if IsPreviewingBackward then PreviewOffset = PreviewOffset - (dt * 5) end

    local RealTime = 0
    if not IsPaused then RealTime = tick() - RunStart - TimeOffset else RealTime = (PauseStart or tick()) - RunStart - TimeOffset end
    
    local VisualTime = RealTime + PreviewOffset; if VisualTime < 0 then VisualTime = 0 end
    
    UpdateMapState(VisualTime); SyncButtonState(VisualTime, RealTime); UpdateTimeDisplay(VisualTime)
    
    if UI_Elements.SavestatesCount then UI_Elements.SavestatesCount.Text = "States: " .. tostring(#Savestates) end
    if UI_Elements.FrameCount then UI_Elements.FrameCount.Text = "Frames: " .. tostring(#Frames) end
    
    if PreviewOffset > 0.1 then TimeText.TextColor3 = Color3.fromRGB(0, 255, 0)
    elseif PreviewOffset < -0.1 then TimeText.TextColor3 = Color3.fromRGB(255, 0, 0)
    else 
        if IsPaused then TimeText.TextColor3 = Color3.fromRGB(255, 255, 0) else TimeText.TextColor3 = Color3.fromRGB(255, 255, 255) end
    end

    if not IsPaused then
        RecordAccumulator = RecordAccumulator + dt
        if RecordAccumulator >= RECORD_INTERVAL then
            RecordAccumulator = RecordAccumulator - RECORD_INTERVAL
            if RecordAccumulator > RECORD_INTERVAL then RecordAccumulator = 0 end
            table.insert(Frames, CaptureFrameData())
        end
        if tick() - LastHeartbeat >= 2 then LastHeartbeat = tick() end
        
        if ClonedMap then
            local ExitRegion = ClonedMap:FindFirstChild("ExitRegion", true)
            if ExitRegion and not AutoSaved then
                if IsPointInPart(ExitRegion, LocalPlayer.Character.HumanoidRootPart.CFrame.Position) then
                    AutoSaved = true; SendAlert("Reached Exit - Auto Saving...", Color3.fromRGB(0, 255, 0))
                    
                    local Export = CompileTASData()
                    local name = ClonedMap.Settings:GetAttribute("MapName") or "AutoSaveRun"
                    if UI_Elements.SaveBox and UI_Elements.SaveBox.Text ~= "" then name = UI_Elements.SaveBox.Text end
                    if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
                    writefile("Flood-GUI/TAS FILES/" .. name .. ".json", HttpService:JSONEncode(Export))
                    RefreshFileList()
                end
            end
        end
    else 
        LastHeartbeat = tick() 
    end
    
    local Character = LocalPlayer.Character
local RootPart = Character and Character:FindFirstChild("HumanoidRootPart")
local Head = Character and Character:FindFirstChild("Head")

local InWater = false
local IsSliding = (CurrentAnim and CurrentAnim[1] == "slide")

if getgenv().EnableAutoSwim and not IsSliding and RootPart and Head then
    local headPosition = Head.Position

    for _, waterPart in ipairs(WaterParts) do
        if IsPointInPart(waterPart, headPosition) then
            InWater = true
            break
        end
    end
end

getgenv().IsSwimming = InWater
end)
AddConnection(HBCon)

-- // INPUTS //
local InputCon = UserInputService.InputBegan:Connect(function(input, gpe)
    if not gpe then
        local k = input.KeyCode.Name
        if k == Keybinds.UserPause then TogglePause()
        elseif k == Keybinds.AddSavestate then AddSavestate()
        elseif k == Keybinds.RemoveSavestate then RemoveSavestate()
        elseif k == Keybinds.BackSavestate then task.spawn(LoadLastSavestate)
        elseif k == Keybinds.CollisionToggler then ToggleCollision()
        elseif k == Keybinds.SaveRun then 
            local Export = CompileTASData()
            local name = (UI_Elements.SaveBox and UI_Elements.SaveBox.Text ~= "") and UI_Elements.SaveBox.Text or (ClonedMap and ClonedMap.Settings:GetAttribute("MapName") or "MyRun")
            if not isfolder("Flood-GUI/TAS FILES") then makefolder("Flood-GUI/TAS FILES") end
            writefile("Flood-GUI/TAS FILES/" .. name .. ".json", HttpService:JSONEncode(CompileTASData()))
            SendAlert("Run Saved!", Color3.fromRGB(0, 255, 0)); RefreshFileList()
        elseif k == Keybinds.GoFrameForward then
            if IsRewinding then return end
            if not IsAdvancingFrame then task.spawn(FrameAdvanceLoop) end
        elseif k == Keybinds.GoFrameBack then 
            if IsAdvancingFrame then IsAdvancingFrame = false; task.wait() end
            task.spawn(RewindLoop)
        elseif k == "Up" then IsPreviewingForward = true
        elseif k == "Down" then IsPreviewingBackward = true
        elseif k == Keybinds.ResetToNormal then task.spawn(ResetToNormal)
        elseif k == Keybinds.EnvPause then 
            EnvPaused = not EnvPaused
            SendAlert("Map Updates " .. (EnvPaused and "Paused" or "Active"), Color3.fromRGB(255, 255, 0))
        elseif k == Keybinds.Resync then
            IsPreviewingForward = false; IsPreviewingBackward = false; PreviewOffset = 0
            SendAlert("Visuals Resynced", Color3.fromRGB(0, 255, 255))
        elseif k == Keybinds.ViewTAS then
            if not IsViewingTAS then PlaybackTAS(CompileTASData()) end
        elseif k == Keybinds.LoadRun then
            if SelectedFileToLoad ~= "" then
                if PreloadedTASFilename ~= SelectedFileToLoad or not PreloadedTASData then PreloadTASFile(SelectedFileToLoad) end
                LoadPreloadedRunIntoEditor()
            end
        elseif k == Keybinds.AutoSwimToggler then -- Added Keybind Handler (T)
            getgenv().EnableAutoSwim = not getgenv().EnableAutoSwim
            if UI_Elements and UI_Elements.Buttons and UI_Elements.Buttons.AutoSwim then
                UI_Elements.Buttons.AutoSwim.Text = "Auto-Swim: " .. (getgenv().EnableAutoSwim and "ON" or "OFF")
                UI_Elements.Buttons.AutoSwim.BackgroundColor3 = getgenv().EnableAutoSwim and Color3.fromRGB(0, 150, 100) or Color3.fromRGB(45, 45, 55)
            end
            SendAlert("Auto-Swim " .. (getgenv().EnableAutoSwim and "Enabled" or "Disabled"), getgenv().EnableAutoSwim and Color3.fromRGB(0, 255, 0) or Color3.fromRGB(255, 0, 0))
        elseif k == Keybinds.DebugToggler then
            DebugActive = not DebugActive
            if DebugActive then
                if ClonedMap then
                    for _, v in pairs(ClonedMap:GetDescendants()) do
                        if v:IsA("BasePart") then
                            OriginalVisuals[v] = {Color = v.Color, Transparency = v.Transparency}
                            if v.Name == "Hitbox" or v.Name:find("_Water") then v.Color = Color3.fromHSV(math.random(), 1, 1); v.Transparency = 0.2
                            else v.Color = Color3.new(0.4, 0.4, 0.4); if v.Transparency == 1 then v.Transparency = 0.8 end end
                        end
                    end
                end
                if UI_Elements and UI_Elements.Buttons then UI_Elements.Buttons.DebugView.Text = "Debug Hitboxes: ON"; UI_Elements.Buttons.DebugView.BackgroundColor3 = Color3.fromRGB(0, 150, 100) end
                SendAlert("Debug View Enabled", Color3.fromRGB(0, 255, 0))
            else
                for part, props in pairs(OriginalVisuals) do if part and part.Parent then part.Color = props.Color; part.Transparency = props.Transparency end end
                OriginalVisuals = setmetatable({}, { __mode = "k" })
                if UI_Elements and UI_Elements.Buttons then UI_Elements.Buttons.DebugView.Text = "Debug Hitboxes: OFF"; UI_Elements.Buttons.DebugView.BackgroundColor3 = Color3.fromRGB(45, 45, 55) end
                SendAlert("Debug View Disabled", Color3.fromRGB(255, 0, 0))
            end
        end
    end
end)
AddConnection(InputCon)

local InputEndCon = UserInputService.InputEnded:Connect(function(input, gpe)
    if not gpe then
        if input.KeyCode.Name == Keybinds.GoFrameBack then IsRewinding = false end
        if input.KeyCode.Name == Keybinds.GoFrameForward then IsAdvancingFrame = false end
        if input.KeyCode.Name == "Up" then IsPreviewingForward = false end
        if input.KeyCode.Name == "Down" then IsPreviewingBackward = false end
    end
end)
AddConnection(InputEndCon)

local DiedCon = LocalPlayer.Character.Humanoid.Died:Connect(function()
    task.wait(0.1); if not IsPaused then TogglePause() end
    LocalPlayer.CharacterAdded:Wait(); task.wait(0.1)
    if ClonedMap and ClonedMap.Parent then LoadLastSavestate() end
end)
AddConnection(DiedCon)
