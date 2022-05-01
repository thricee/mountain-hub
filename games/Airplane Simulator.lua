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

local Promise = import('modules/promise.lua')
local Maid = import('modules/maid.lua')
local venyxLibrary = import('modules/venyx.lua').new('Airplane Simulator')

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

local function getPlaneSettings(planeModel: Model, doYield: boolean)
    return Promise.new(function(Resolve, Reject)
        repeat
            task.wait()
            for _, v in pairs(getgc(true)) do
                if typeof(v) == 'table' then

                    if rawget(v, 'PlaneDeleted') then
                        v = {}
                        continue
                    elseif rawget(v, 'isExploitTable') then
                        continue
                    end

                    local maxVelocity, maxAltitude, acceleration = rawget(v, 'MaxVelocity'), rawget(v, 'MaxAltitude'), rawget(v, 'Acceleration')
                    if maxVelocity and typeof(maxVelocity) == 'number' and maxAltitude and typeof(maxAltitude) == 'number' and acceleration and typeof(acceleration) == 'number' then

                        if not planeModel:GetAttribute('PlaneId') then
                            local planeId = httpService:GenerateGUID(false)
                            planeModel:SetAttribute('PlaneId', planeId)
                            registeredPlanes[planeId] = v
                        end

                        doYield = false
                        Resolve(v)
                        break
                    end
                end
            end
        until not doYield
    end)
end

local function addToQueue(callback, name)
    table.insert(heartbeatQueue, {callback = callback, name = name})
end

local wantedPlaneSettings = {isExploitTable = true}

local function setSettings(doYield: boolean)
    return Promise.new(function(Resolve, Reject)
        getPlane():andThen(function(planeModel: Model)
            getPlaneSettings(planeModel, doYield):andThen(function(planeSettings)
                rawset(planeSettings, 'PlaneModel', planeModel)
                for setting, value in pairs(wantedPlaneSettings) do
                    local hasSetting = rawget(planeSettings, setting)
                    if customizableSettings[setting] and (hasSetting ~= value or setting == 'NoStuntMode') then
                        if typeof(value) == customizableSettings[setting]:lower() then
                            rawset(planeSettings, setting, value)
                            print('Set setting of ' .. tostring(setting) .. ' to ' .. tostring(value))
                        else
                            venyxLibrary:Notify('Alert', 'Make sure you actually input a ' ..  customizableSettings[setting]:lower() .. ' value for ' .. setting)
                        end
                    end
                end

                Resolve()
            end):catch(warn)
        end):catch(warn)
    end)
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

local venyxTextboxes = {}
local venyxToggles = {}

local planeTab = venyxLibrary:addPage('Plane')
local defaultSection = planeTab:addSection('Default')
local settingsSection = planeTab:addSection('Settings')

local function resetPlaneSettings()
    getPlane():andThen(function(planeModel: Model)
        local storedPlane = vehicles:FindFirstChild(planeModel.Name)
        
        if storedPlane then
            local storedPlaneSettings = require(storedPlane.PlaneSettings)
            for settingName, defaultValue in pairs(storedPlaneSettings) do
                print('Set: ' .. settingName .. ' to: ' .. tostring(defaultValue))
                wantedPlaneSettings[settingName] = defaultValue

                local textbox, toggle = venyxTextboxes[settingName], venyxToggles[settingName]
                if textbox then
                    settingsSection:updateTextbox(textbox, 'Set ' .. settingName, defaultValue)
                elseif toggle then
                    settingsSection:updateToggle(toggle, 'Toggle ' .. settingName, defaultValue)
                end

            end

            storedPlaneSettings['isExploitTable'] = true
            setSettings():awaitStatus()
            storedPlaneSettings['isExploitTable'] = nil

            wantedPlaneSettings = {isExploitTable = true}
        end
    end):catch(warn)
end

-- // UI Library.

defaultSection:addButton('Default Settings', function()
    resetPlaneSettings()
end)

for propertyName, propertyType in pairs(customizableSettings) do
    if propertyType == 'Number' then
        local textbox = settingsSection:addTextbox('Set ' .. propertyName, '', function(Value, FocusLost)
            if FocusLost then
                wantedPlaneSettings[propertyName] = tonumber(Value)
                setSettings()
            end
        end)

        venyxTextboxes[propertyName] = textbox
    elseif propertyType == 'Boolean' then
        local toggle = settingsSection:addToggle('Toggle ' .. propertyName, false, function(Value)
            wantedPlaneSettings[propertyName] = Value
            setSettings()
        end)

        venyxToggles[propertyName] = toggle
    end
end

local autoTab = venyxLibrary:addPage('Automation')
local tasksSection = autoTab:addSection('Tasks')

tasksSection:addToggle('Complete Tasks', false, function(Value)
    doTask = Value
        if not doTask then
            teleportMaid:DoCleaning()
            isTeleporting = false
        end
end)

local settingsPage = venyxLibrary:addPage('Settings')
local bindsSection = settingsPage:addSection('Binds')

bindsSection:addKeybind('Toggle UI', Enum.KeyCode.H, function()
    venyxLibrary:toggle()
end)

-- // Background activity

runService.Heartbeat:Connect(function()
    for _, v in pairs(heartbeatQueue) do
        task.spawn(v.callback)
    end
end)

venyxLibrary:SelectPage(venyxLibrary.pages[1], true)