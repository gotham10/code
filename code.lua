local function log(category, message)
    print(string.format("[%s | BLOCK-FINDER | %s] %s", os.date("%X"), category, message))
end

log("Core", "Script execution started.")

if _G.BlockFinderRunning then
    log("FATAL", "Another instance is already running. Aborting execution.")
    return
end
_G.BlockFinderRunning = true
log("Core", "Global flag 'BlockFinderRunning' set to true.")

local Config = {
    ScriptUrl = "https://raw.githubusercontent.com/gotham10/code/main/code.lua"
}

local HttpService = game:GetService("HttpService")
local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
    log("FATAL", "Could not get LocalPlayer. Aborting script.")
    _G.BlockFinderRunning = false
    return
end

local PlaceId = game.PlaceId
local JobId = game.JobId

log("Info", string.format("Player: %s | PlaceId: %d", LocalPlayer.Name, PlaceId))

if not (request and queue_on_teleport) then
    log("FATAL", "'request' or 'queue_on_teleport' are not available. Aborting.")
    _G.BlockFinderRunning = false
    return
end
log("Deps", "'request' and 'queue_on_teleport' are available.")

local function checkForLuckyBlocks()
    local plots = workspace:FindFirstChild("Plots")
    if not plots then
        log("WARN", "Could not find 'Plots' folder in workspace.")
        return false
    end

    local luckyBlockNames = {"Admin Lucky Block", "Brainrot God Lucky Block", "Secret Lucky Block", "Taco Lucky Block"}
    local found = false

    for _, plot in ipairs(plots:GetChildren()) do
        if plot:IsA("Model") then
            for _, blockName in ipairs(luckyBlockNames) do
                local luckyBlock = plot:FindFirstChild(blockName)
                if luckyBlock and luckyBlock:IsA("Model") then
                    if not luckyBlock:FindFirstChildOfClass("Highlight") then
                        found = true
                        log("FOUND", string.format("Found '%s' in plot: %s", blockName, plot.Name))
                        local highlight = Instance.new("Highlight")
                        highlight.FillColor = Color3.fromRGB(0, 255, 0)
                        highlight.OutlineColor = Color3.fromRGB(0, 80, 0)
                        highlight.FillTransparency = 0.5
                        highlight.Adornee = luckyBlock
                        highlight.Parent = luckyBlock
                    end
                end
            end
        end
    end
    return found
end

if checkForLuckyBlocks() then
    log("Core", "Target lucky block(s) found on this server. Halting execution.")
    _G.BlockFinderRunning = false
else
    log("Core", "No target blocks found. Initializing server hop sequence.")

    _G.VisitedServers = _G.VisitedServers or {}
    _G.VisitedServers[JobId] = true
    log("State", "Current server marked as visited.")

    local teleportFailedConn
    
    local function getBestServer(ignoreList)
        local requestUrl = "https://games.roblox.com/v1/games/" .. PlaceId .. "/servers/Public?sortOrder=Asc&limit=100"
        local responseBody
        
        while not responseBody do
            local success, response = pcall(function()
                return request({Url = requestUrl, Method = "GET"})
            end)
            if success and response and response.StatusCode == 200 then
                responseBody = response.Body
                log("API", "Successfully fetched server list.")
            else
                local reason = "pcall failed"
                if success and response then reason = "Status Code: " .. response.StatusCode end
                log("WARN", string.format("API fetch failed. Reason: %s. Retrying in 15 seconds...", reason))
                task.wait(15)
            end
        end

        local success, body = pcall(function() return HttpService:JSONDecode(responseBody) end)
        if not (success and body and body.data) then
            log("ERROR", "Failed to decode server list JSON. Retrying...")
            task.wait(5)
            return nil
        end
        
        local lowestPlayerCount = math.huge
        local bestServerId = nil

        for _, server in ipairs(body.data) do
            if not ignoreList[server.id] and server.id ~= JobId and server.playing < server.maxPlayers then
                if server.playing < lowestPlayerCount then
                    lowestPlayerCount = server.playing
                    bestServerId = server.id
                end
            end
        end
        
        if bestServerId then
            log("ServerHop", "Found best available server: " .. bestServerId)
        else
            log("ServerHop", "No new unvisited servers found in the list.")
        end
        return bestServerId
    end

    local function attemptHop()
        local targetServer
        while not targetServer do
            targetServer = getBestServer(_G.VisitedServers)
            if not targetServer then
                log("State", "All available servers have been visited. Resetting list and retrying.")
                _G.VisitedServers = {[JobId] = true}
                task.wait(5)
            end
        end
        
        log("Teleport", string.format("Attempting to teleport to server: %s", targetServer))
        
        local scriptToQueue = string.format('loadstring(game:HttpGet("%s"))()', Config.ScriptUrl)
        queue_on_teleport(scriptToQueue)
        log("Persistence", "Successfully queued script for re-execution after teleport.")

        TeleportService:TeleportToPlaceInstance(PlaceId, targetServer, LocalPlayer)
    end

    teleportFailedConn = TeleportService.TeleportInitFailed:Connect(function(player, result, errorMessage)
        if player == LocalPlayer then
            log("Teleport", string.format("TELEPORT FAILED! Result: %s, Message: %s", tostring(result), errorMessage))
            log("RetryLogic", "Encountered a teleport error. Finding another server immediately...")
            task.wait(2)
            attemptHop()
        end
    end)
    
    attemptHop()
end
