--!strict
-- Только Studio: G — перенестись к финишной линии, B — режим велосипеда (см. DevService).

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local remote = Remotes.get(Remotes.Names.DevToFinish)

ContextActionService:BindAction("DevToFinish", function(_, state)
	if state == Enum.UserInputState.Begin then
		remote:FireServer()
	end
	return Enum.ContextActionResult.Pass
end, false, Config.Dev.ToFinishKey)

local bikeRemote = Remotes.get(Remotes.Names.DevBikeMode)
ContextActionService:BindAction("DevBikeMode", function(_, state)
	if state == Enum.UserInputState.Begin then
		bikeRemote:FireServer()
	end
	return Enum.ContextActionResult.Pass
end, false, Config.Dev.BikeModeKey)
