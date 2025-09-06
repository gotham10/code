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
    ScriptFileName = "auto_hop.lua",
    CountFileName = "hop_count.txt",
    HopToLowest = true 
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
log("Config", string.format("MaxHops: %d | ScriptFile: '%s' | CountFile: '%s' | HopToLowest: %s", Config.MaxHops, Config.ScriptFileName, Config.CountFileName, tostring(Config.HopToLowest)))

if not (readfile and writefile and request) then
    log("FATAL", "'readfile', 'writefile', or 'request' functions are not available. Aborting.")
    _G.AutoHopRunning = false
    return
end
log("Deps", "'readfile', 'writefile', and 'request' are available.")

local queue_on_teleport = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport)
if not queue_on_teleport then
    log("FATAL", "'queue_on_teleport' function is not available. Aborting.")
    _G.AutoHopRunning = false
    return
end
log("Deps", "'queue_on_teleport' is available.")

local function getBestServer()
    log("ServerHop", "Fetching server list...")
    local servers = {}
    local lowestPlayerCount = math.huge
    local bestServerId = nil
    local requestUrl = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"

    local success, response = pcall(function()
        return request({Url = requestUrl, Method = "GET"})
    end)

    if success and response and response.StatusCode == 200 then
        local body = HttpService:JSONDecode(response.Body)
        if body and body.data then
            for _, server in ipairs(body.data) do
                if server.id ~= JobId and server.playing < server.maxPlayers then
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
            log("ServerHop", "Found best server: " .. (bestServerId or "None"))
            return bestServerId
        end
    else
        log("ERROR", "Failed to fetch server list.")
    end
    return nil
end

local hopCount = 0
log("HopFS", string.format("Reading hop count from '%s'.", Config.CountFileName))
local success, countData = pcall(function() return readfile(Config.CountFileName) end)
if success and countData and countData ~= "" then
    hopCount = tonumber(countData) or 0
    log("HopFS", string.format("Successfully read hop count: %d.", hopCount))
else
    log("HopFS", string.format("Failed to read from '%s' or file is empty/invalid. Defaulting hop count to 0.", Config.CountFileName))
end

if hopCount < Config.MaxHops then
    log("HopLogic", string.format("Current hop count (%d) is less than MaxHops (%d). Proceeding with hop.", hopCount, Config.MaxHops))

    local newHopCount = hopCount + 1
    log("HopFS", string.format("Writing new hop count (%d) to '%s'.", newHopCount, Config.CountFileName))
    local writeSuccess, writeError = pcall(writefile, Config.CountFileName, tostring(newHopCount))
    if not writeSuccess then
        log("ERROR", string.format("Failed to write new hop count. Reason: %s", tostring(writeError)))
    else
        log("HopFS", "Successfully wrote new hop count.")
    end
    
    log("Persistence", "Attempting to retrieve current script source.")
    local scriptSource
    local sourceSuccess = pcall(function()
        scriptSource = script.Source
    end)

    if not sourceSuccess or not scriptSource or scriptSource == "" then
        log("Persistence", string.format("'script.Source' method failed. Falling back to readfile('%s')...", Config.ScriptFileName))
        sourceSuccess, scriptSource = pcall(function() return readfile(Config.ScriptFileName) end)
    end
    
    if sourceSuccess and scriptSource and scriptSource ~= "" then
        log("Persistence", string.format("Successfully retrieved script source. Length: %d bytes.", #scriptSource))
        log("Persistence", "Queueing script for re-execution after teleport.")
        queue_on_teleport(scriptSource)
        
        local character = LocalPlayer.Character
        local rootPart = character and character:FindFirstChild("HumanoidRootPart")
        
        if rootPart then
            log("Teleport", "Found HumanoidRootPart. Anchoring and zeroing velocity before teleport.")
            rootPart.Anchored = true
            rootPart.Velocity = Vector3.new(0, 0, 0)
            rootPart.RotVelocity = Vector3.new(0, 0, 0)
        else
            log("Teleport", "WARNING: Could not find HumanoidRootPart. Character may move during teleport initiation.")
        end

        local teleportFailedConn
        teleportFailedConn = TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
            if player == LocalPlayer then
                log("Teleport", string.format("TELEPORT FAILED! Result: %s, Message: %s", tostring(result), errorMessage))
                if rootPart then
                    log("Teleport", "Un-anchoring HumanoidRootPart due to teleport failure.")
                    rootPart.Anchored = false
                end
                log("HopFS", "Resetting hop count to 0 due to teleport failure.")
                pcall(writefile, Config.CountFileName, "0") 
                _G.AutoHopRunning = false
                log("Core", "Global flag 'AutoHopRunning' set to false.")
                teleportFailedConn:Disconnect()
            end
        end)

        local bestServer = getBestServer()
        if bestServer then
            log("Teleport", string.format("Initiating teleport to server: %s", bestServer))
            TeleportService:TeleportToPlaceInstance(PlaceId, bestServer, LocalPlayer)
        else
            log("FATAL", "Could not find a suitable server to hop to. Aborting.")
            pcall(writefile, Config.CountFileName, "0")
            _G.AutoHopRunning = false
        end

    else
        log("FATAL", string.format("Could not get script source via 'script.Source' or readfile('%s').", Config.ScriptFileName))
        log("FATAL", string.format("Ensure '%s' is in your executor's workspace folder or that your executor supports 'script.Source'.", Config.ScriptFileName))
        log("HopFS", "Resetting hop count to 0 and aborting auto-hop sequence.")
        pcall(writefile, Config.CountFileName, "0")
        _G.AutoHopRunning = false
        log("Core", "Global flag 'AutoHopRunning' set to false.")
    end
else
    log("HopLogic", string.format("Hop count (%d) has reached MaxHops (%d).", hopCount, Config.MaxHops))
    log("HopFS", string.format("Resetting hop count to 0 in '%s'.", Config.CountFileName))
    pcall(writefile, Config.CountFileName, "0")
    print("-------------------------------------------------")
    print("Auto-Hop sequence finished. Hop count is reset.")
    print("-------------------------------------------------")
    _G.AutoHopRunning = false
    log("Core", "Global flag 'AutoHopRunning' set to false.")
    log("Core", "Script execution finished normally.")
end
