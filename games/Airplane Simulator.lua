local gitToken = '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'
local function import(path: string)

    local formatPath = table.concat(path:split(' '), '%20')

    local httpRequest = syn.request({
        Url = 'https://api.github.com/repos/Voutastic/mountain-hub/contents/' .. formatPath,
        Method = 'GET',
        Headers = {
            ["Authorization"] = 'token ' .. gitToken,
            ['Accept'] = 'application/vnd.github.v4.raw'
        }
    })
    
    return loadstring(httpRequest.Body)()
end

local httpHook
httpHook = hookfunction(game.HttpGet, function(self,...)
   local Args = {...}
   if Args[1] and type(Args[1]) == "string" then
       if Args[1]:match("checkPremium.php") then
           return "true"
       end
   end
   return httpHook(self,...)
end)

local Promise = import('modules/promise.lua')
local Maid = import('modules/maid.lua')
local orionLib = import('modules/orionLibrary.lua')

local game = game
local getService = game.GetService
local workspace = workspace
local players = getService(game, 'Players')
local runService = getService(game, 'RunService')
local replicatedStorage = getService(game, 'ReplicatedStorage')
local httpService = getService(game, 'HttpService')

local client = players.LocalPlayer

local spawnedVehicles: Folder = workspace.SpawnedVehicles
local clientTasks: Folder = client.Tasks
local unloadDestinations: Folder = workspace.UnloadDestinations
local vacationDestinations: Folder = workspace.Destinations
local airportDestinations: Folder = workspace.AirportDestinations
local clientContracts: Folder = client.Contracts
local vehicles: Folder = replicatedStorage.Vehicles

local selectContract: RemoteEvent = replicatedStorage.SelectContract
local resetContracts: RemoteEvent = replicatedStorage.ResetContracts

local heartbeatQueue = {}
local registeredPlanes = {}

type planeSettings = {
	MaxBankY: number,
	MaxBankZ: number,
	TurnSpeed: number,
	MaxVelocity: number,
	Acceleration: number,
	SpeedDifferential: number,
	StallSpeed: number,
	StallRecoverReq: number,
	ButterHeight: number,
	MaxButterAngle: number,
	MaxAltitude: number,
	Offset: Vector3,
	ShakeEffectStrength: number,
	WindEffectStrength: number,
	CameraDelayEffect: number,
	AdvancedXSpeed: number,
	AdvancedZSpeed: number,
	AdvancedRotSpeed: number,
	ForwardCamOffset: number,
	FlightSoundPitchIncrease: number,
	FlightSoundVolumeIncrease: number,
	WindPitchIncrease: number,
	NoStuntMode: boolean
}

local customizableSettings = {
    MaxBankY = "Number",
	MaxBankZ = "Number",
	TurnSpeed = "Number",
	MaxVelocity = "Number",
	Acceleration = "Number",
	SpeedDifferential = "Number",
	StallSpeed = "Number",
	StallRecoverReq = "Number",
	ButterHeight = "Number",
	MaxButterAngle = "Number",
	MaxAltitude = "Number",
	ShakeEffectStrength = "Number",
	WindEffectStrength = "Number",
	CameraDelayEffect = "Number",
	AdvancedXSpeed = "Number",
	AdvancedZSpeed = "Number",
	AdvancedRotSpeed = "Number",
	ForwardCamOffset = "Number",
	FlightSoundPitchIncrease = "Number",
	FlightSoundVolumeIncrease = "Number",
	WindPitchIncrease = "Number",
	NoStuntMode = "Boolean"
}

local function checkPlane(plane: Model)
    return plane:GetAttribute('Owner') == client.Name
end

local function getPlane()
    return Promise.new(function(Resolve, Reject)
        for _, value in pairs(spawnedVehicles:GetChildren()) do
            if checkPlane(value) then
                Resolve(value)
            end
        end
    end)
end

local function getPlaneSettings(planeModel: Model, yield: boolean)
    return Promise.new(function(Resolve, Reject)
        repeat
            task.wait()
            for _, v in pairs(getgc(true)) do
                if typeof(v) == 'table' then
                    local maxVelocity, maxAltitude, acceleration = rawget(v, 'MaxVelocity'), rawget(v, 'MaxAltitude'), rawget(v, 'Acceleration')
                    if maxVelocity and typeof(maxVelocity) == 'number' and maxAltitude and typeof(maxAltitude) == 'number' and acceleration and typeof(acceleration) == 'number' and not rawget(v, 'isExploitTable') and not rawget(v, 'PlaneDeleted') then

                        if not planeModel:GetAttribute('PlaneId') then
                            local planeId = httpService:GenerateGUID(false)
                            planeModel:SetAttribute('PlaneId', planeId)
                            registeredPlanes[planeId] = v
                        end

                        yield = false
                        Resolve(v)
                        break
                    end
                end
            end
        until not yield
    end)
end

local function addToQueue(callback, name)
    table.insert(heartbeatQueue, {callback = callback, name = name})
end

local wantedPlaneSettings = {isExploitTable = true}

local function setSettings(yield: boolean)
    getPlane():andThen(function(planeModel: Model)
        getPlaneSettings(planeModel, yield):andThen(function(planeSettings: planeSettings)
            for setting, value in pairs(wantedPlaneSettings) do
                local hasSetting = rawget(planeSettings, setting)
                if customizableSettings[setting] and (hasSetting ~= value or setting == 'NoStuntMode') then
                    if typeof(value) == customizableSettings[setting]:lower() then
                        rawset(planeSettings, setting, value)
                        rawset(planeSettings, 'PlaneModel', planeModel)
                        print('Set setting of ' .. tostring(setting) .. ' to ' .. tostring(value))
                    else
                        orionLib:MakeNotification({
                            Name = "Alert",
                            Content = "Make sure you actually input a number. | Setting: " .. setting,
                            Image = "rbxassetid://4483345998",
                            Time = 3
                        })
                    end
                end
            end
        end):catch(warn)
    end):catch(warn)
end

spawnedVehicles.ChildAdded:Connect(function(child)
    if checkPlane(child) then
        print('New plane spawned. Waiting for plane settings')
        child:WaitForChild('PlaneSettings')
        print('Plane settings found. Setting modifications')
        setSettings(true)
    end
end)

spawnedVehicles.ChildRemoved:Connect(function(child)
    local planeId = child:GetAttribute('PlaneId')

    if planeId then
        -- // Plane is owned by client.
        rawset(registeredPlanes[planeId], 'PlaneDeleted', true)
    end
end)

local doTask = false
local teleportMaid = Maid.new()
local isTeleporting = false

local uncollideableObjects = {}

local function makeObjectUncollidable(model: Model)
    local modifiedParts = {}
    for _, v in pairs(model:GetDescendants()) do
        if v:IsA('BasePart') and not v:IsA('Seat') then
            v.CanCollide = false
            table.insert(modifiedParts, v)
        end
    end

    uncollideableObjects[model] = modifiedParts
end

local function reverseUncollidable(model: Model)
    local isUncollidable: table = uncollideableObjects[model]
    if isUncollidable and typeof(isUncollidable) == 'table' then
        for _, v in pairs(isUncollidable) do
            v.CanCollide = true
        end
    end

    uncollideableObjects[model] = nil
end

local function teleportPlane(wantedPosition: Vector3)
    if not isTeleporting then
        isTeleporting = true
        getPlane():andThen(function(planeModel: Model)
            makeObjectUncollidable(planeModel)

            local planeMain = planeModel.PrimaryPart
            local bodyPosition = Instance.new('BodyPosition', planeMain)
            teleportMaid:GiveTask(bodyPosition)
    
            bodyPosition.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            bodyPosition.Position = Vector3.new(planeMain.Position.X, 5000, planeMain.Position.Z)
            
            task.wait(1)

            bodyPosition.Position = wantedPosition
    
            task.wait(5)
            teleportMaid:DoCleaning()
            reverseUncollidable(planeModel)
            isTeleporting = false
        end):catch(function()
            isTeleporting = false
        end)
    end
end

local function resetTasks()
    local contracts = clientContracts:GetChildren()

    selectContract:FireServer(contracts[1])
    task.wait(0.25)
    resetContracts:FireServer()
end

addToQueue(function()
    if doTask then

        local tasks = clientTasks:GetChildren()
        local hasTasks = false

        for _, v in pairs(tasks) do
            if v.Type.Value == 'Takeoff/land' then
                local airportName: string = v.Airport.Value
                local airportDestination: BasePart = unloadDestinations:FindFirstChild(airportName) or airportDestinations:FindFirstChild(airportName)

                if not airportDestination then
                    warn('Couldn\'t find airport for: ' .. airportName)
                    return
                end

                hasTasks = true
                teleportPlane(airportDestination.Position)
            elseif v.Type.Value == 'Travel to' then
                local destinationName: string = v.Destination.Value
                local vacationDestination: BasePart = vacationDestinations:FindFirstChild(destinationName)

                if not vacationDestination then
                    warn('Couldn\'t find airport for: ' .. destinationName)
                    return
                end

                hasTasks = true
                teleportPlane(vacationDestination.Position)
            end
        end

        if not hasTasks then
            print('Probably no more tasks. Resettings tasks.')
            resetTasks()
        end
    end
end, 'AutoTask')

local function resetPlaneSettings()
    print('Reset settings called!')
    getPlane():andThen(function(planeModel: Model)
        print('Found plane!')
        local storedPlane = vehicles:FindFirstChild(planeModel)
        
        if storedPlane then
            print('Found stored plane!')
            local storedPlaneSettings = require(storedPlane.PlaneSettings)
            for settingName, defaultValue in pairs(storedPlaneSettings) do
                wantedPlaneSettings[settingName] = defaultValue
            end
            setSettings()
            wantedPlaneSettings = {isExploitTable = true}
            print('Settings should be resetted!')
        end
    end):catch(warn)
end

-- // UI Library.

local mainWindow = orionLib:MakeWindow({Name = 'Airplane Simulator'})

local planeTab = mainWindow:MakeTab({
    Name = 'Plane',
    Icon = 'rbxassetid://9486014527',
    PremiumOnly = false
})

planeTab:AddButton({
	Name = "Default Settings",
	Callback = function()
      	resetPlaneSettings()
  	end    
})

for propertyName, propertyType in pairs(customizableSettings) do
    if propertyType == 'Number' then
        planeTab:AddTextbox({
            Name = "Set " .. propertyName,
            TextDisappear = false,
            Callback = function(Value)
                wantedPlaneSettings[propertyName] = tonumber(Value)
                setSettings()
            end
        })
    elseif propertyType == 'Boolean' then
        planeTab:AddToggle({
            Name = "Toggle " .. propertyName,
            Callback = function(Value)
                wantedPlaneSettings[propertyName] = Value
                setSettings()
            end    
        })
    end
end

local autoTab = mainWindow:MakeTab({
    Name = 'Automation',
    Icon = 'rbxassetid://311226872',
    PremiumOnly = false
})

autoTab:AddToggle({
    Name = 'Complete Tasks',
    Callback = function(Value)
        doTask = Value
        if not doTask then
            teleportMaid:DoCleaning()
            isTeleporting = false
        end
    end
})

-- // Background activity

runService.Heartbeat:Connect(function()
    for _, v in pairs(heartbeatQueue) do
        task.spawn(v.callback)
    end
end)

orionLib:Init()