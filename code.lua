local function log(category, message)
    print(string.format("[%s | AUTO-HOP | %s] %s", os.date("%X"), category, message))
end

log("Core", "Script execution started.")

if _G.AutoHopRunning then
    log("FATAL", "Another instance is already running. Aborting execution.")
    return
end
_G.AutoHopRunning = true
log("Core", "Global flag 'AutoHopRunning' set to true.")

local Config = {
    MaxHops = 5,
    HopToLowest = true,
    ScriptUrl = "https://raw.githubusercontent.com/gotham10/code/main/code.lua"
}

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    log("FATAL", "Could not get LocalPlayer. Aborting script.")
    _G.AutoHopRunning = false
    return
end

local PlaceId = game.PlaceId
local JobId = game.JobId

log("Info", string.format("Player: %s | PlaceId: %d", LocalPlayer.Name, PlaceId))
log("Config", string.format("MaxHops: %d | HopToLowest: %s", Config.MaxHops, tostring(Config.HopToLowest)))

if not request then
    log("FATAL", "'request' function is not available. Aborting.")
    _G.AutoHopRunning = false
    return
end
log("Deps", "'request' is available.")

local queue_on_teleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
if not queue_on_teleport then
    log("FATAL", "'queue_on_teleport' function is not available. Aborting.")
    _G.AutoHopRunning = false
    return
end
log("Deps", "'queue_on_teleport' is available.")

_G.AutoHopCount = _G.AutoHopCount or 0
log("State", "Initialized hop count from _G.AutoHopCount: " .. _G.AutoHopCount)

if _G.AutoHopCount < Config.MaxHops then
    log("HopLogic", string.format("Current hop count (%d) is less than MaxHops (%d). Proceeding.", _G.AutoHopCount, Config.MaxHops))
    
    _G.AutoHopCount = _G.AutoHopCount + 1
    log("State", "Incremented hop count to: " .. _G.AutoHopCount)

    local teleportFailedConn
    local triedServers = {}

    local function getBestServer(ignoreList)
        log("ServerHop", "Fetching server list...")
        local requestUrl = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local responseBody
        
        for attempt = 1, 3 do
            local success, response = pcall(function()
                return request({Url = requestUrl, Method = "GET"})
            end)
            if success and response and response.StatusCode == 200 then
                responseBody = response.Body
                break
            else
                local reason = "pcall failed"
                if success and response then reason = "Status Code: " .. response.StatusCode end
                log("WARN", string.format("API fetch attempt %d/3 failed. Reason: %s", attempt, reason))
                if attempt < 3 then
                    log("API", "Retrying in 5 seconds...")
                    task.wait(5)
                end
            end
        end

        if not responseBody then
            log("ERROR", "All API fetch attempts failed.")
            return nil
        end

        local success, body = pcall(function() return HttpService:JSONDecode(responseBody) end)
        if not (success and body and body.data) then
            log("ERROR", "Failed to decode server list JSON.")
            return nil
        end
        
        local servers = {}
        local lowestPlayerCount = math.huge
        local bestServerId = nil

        for _, server in ipairs(body.data) do
            local isTried = false
            for _, triedId in ipairs(ignoreList) do
                if server.id == triedId then
                    isTried = true
                    break
                end
            end
            if not isTried and server.id ~= JobId and server.playing < server.maxPlayers then
                if Config.HopToLowest then
                    if server.playing < lowestPlayerCount then
                        lowestPlayerCount = server.playing
                        bestServerId = server.id
                    end
                else
                    table.insert(servers, server.id)
                end
            end
        end
        
        if not Config.HopToLowest and #servers > 0 then
            bestServerId = servers[math.random(1, #servers)]
        end

        if bestServerId then
            log("ServerHop", "Found best available server: " .. bestServerId)
        else
            log("ServerHop", "Could not find any suitable servers to join.")
        end
        return bestServerId
    end

    local function attemptHop()
        local bestServer = getBestServer(triedServers)
        if bestServer then
            log("Teleport", string.format("Attempting to teleport to server: %s", bestServer))
            table.insert(triedServers, bestServer)
            
            local scriptToQueue = string.format('loadstring(game:HttpGet("%s"))()', Config.ScriptUrl)
            queue_on_teleport(scriptToQueue)
            log("Persistence", "Successfully queued script for re-execution after teleport.")

            TeleportService:TeleportToPlaceInstance(PlaceId, bestServer, LocalPlayer)
        else
            log("FATAL", "No available servers found to hop to after all attempts. Aborting sequence.")
            if teleportFailedConn then teleportFailedConn:Disconnect() end
            _G.AutoHopCount = nil 
            _G.AutoHopRunning = false
            log("Core", "Global flags reset. Auto-hop aborted.")
        end
    end

    teleportFailedConn = TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
        if player == LocalPlayer then
            log("Teleport", string.format("TELEPORT FAILED! Result: %s, Message: %s", tostring(result), errorMessage))
            
            local recoverableErrors = {
                [Enum.TeleportResult.GameFull] = true,
                [Enum.TeleportResult.Flooded] = true,
                [Enum.TeleportResult.Unauthorized] = true
            }

            if recoverableErrors[result] then
                log("RetryLogic", "Encountered a recoverable teleport error. Finding another server...")
                task.wait(2)
                attemptHop()
            else
                log("FATAL", "Teleport failed for a non-recoverable reason. Aborting sequence.")
                if teleportFailedConn then teleportFailedConn:Disconnect() end
                _G.AutoHopCount = nil
                _G.AutoHopRunning = false
                log("Core", "Global flags reset. Auto-hop aborted.")
            end
        end
    end)
    
    attemptHop()

else
    log("HopLogic", string.format("Hop count (%d) has reached MaxHops (%d).", _G.AutoHopCount, Config.MaxHops))
    print("-------------------------------------------------")
    print("Auto-Hop sequence finished. Hop count is reset.")
    print("-------------------------------------------------")
    _G.AutoHopCount = nil
    _G.AutoHopRunning = false
    log("Core", "Global flags reset. Sequence complete.")
    log("Core", "Script execution finished normally.")
end
