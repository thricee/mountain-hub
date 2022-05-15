local function import(path)
    local formatPath = table.concat(path:split(' '), '%20')
    local httpRequest = syn.request({
        Url = 'https://western-reinvented-forgery.glitch.me/exports/' .. formatPath,
        Method = 'GET',
        Headers = {
            isExploit = 'true'
        }
    })
    
    return loadstring(httpRequest.Body)()
end

local Promise = import('modules/promise.lua')
local Maid = import('modules/maid.lua')
local venyxLibrary = import('modules/venyx.lua').new('bordr')

local game = game
local getService = game.GetService
local workspace = workspace
local players = getService(game, 'Players')
local runService = getService(game, 'RunService')
local replicatedStorage = getService(game, 'ReplicatedStorage')
local httpService = getService(game, 'HttpService')

local client = players.LocalPlayer
local clientScripts = client.PlayerScripts

local bowClient = clientScripts.BowClient
local bowClientEnv = getsenv(bowClient)

local rayParams = RaycastParams.new()
local silentAim, wallBang
local currentCamera = workspace.CurrentCamera

local clientMouse = client:GetMouse()

local function nearestPlayer(toMouse: boolean): Player
    local target, maxDistance = nil, math.huge
    for _, v in pairs(players:GetPlayers()) do
        local character = v.Character
        if v ~= client and character then
            local hum = character:FindFirstChildOfClass('Humanoid')
            if character and hum and hum.Health > 0 then
                local distance = (character.PrimaryPart.Position - client.Character.PrimaryPart.Position).Magnitude
                if toMouse then
                    local vector, onScreen = currentCamera:WorldToScreenPoint(character.PrimaryPart.Position)
                    if not onScreen then
                        continue
                    end

                    distance = (Vector2.new(clientMouse.X, clientMouse.Y) - Vector2.new(vector.X, vector.Y)).Magnitude
                end
                if distance <= maxDistance then
                    target = v
                    maxDistance = distance
                end
            end
        end
    end

    return target
end

local currentNearest

local oldGetFinalAim = bowClientEnv.GetFinalAim
bowClientEnv.GetFinalAim = function(bow: Tool)
    local oldResult = oldGetFinalAim(bow)
    if not silentAim then
        return oldResult
    end

    local target = nearestPlayer(true)
    
    if target then
        currentNearest = target
        return target.Character.PrimaryPart.Position
    else
        return oldResult
    end
end

local oldCreateRay = bowClientEnv.CreateRay
bowClientEnv.CreateRay = function(character: Model, head: BasePart, bow: Tool , finalAim: Vector3)
    local oldResult = oldCreateRay(character, head, bow, finalAim)
    if not wallBang then
        return oldResult
    end
    local hitPart, hitPoint
    local targetCharacter = nearestPlayer(true).Character or currentNearest

    if not targetCharacter then
        return oldResult
    end

    rayParams.FilterDescendantsInstances = {targetCharacter}
    rayParams.FilterType = Enum.RaycastFilterType.Whitelist

    local rayResult = workspace:Raycast(head.Position, (finalAim - head.Position).Unit * 999, rayParams)
    hitPart = rayResult.Instance
    hitPoint = rayResult.Position

    return hitPart, hitPoint, (hitPoint - bow.Arrow.Position).Magnitude
end

local planeTab = venyxLibrary:addPage('Combat')
local bowSection = planeTab:addSection('Bow')

bowSection:addToggle('Silent Aim', false, function(value)
    silentAim = value
end)

bowSection:addToggle('Wallbang', false, function(value)
    wallBang = value
end)

local settingsPage = venyxLibrary:addPage('Settings')
local bindsSection = settingsPage:addSection('Binds')

bindsSection:addKeybind('Toggle UI', Enum.KeyCode.H, function()
    venyxLibrary:toggle()
end)

venyxLibrary:SelectPage(venyxLibrary.pages[1], true)