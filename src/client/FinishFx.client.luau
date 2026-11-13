--!strict
-- Салют над финишной аркой при чьём-то финише (только частицы, без звука).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local Fx = require(script.Parent:WaitForChild("Fx"))

local E = Config.Effects

local function finishPoint(): Vector3?
	local track = workspace:FindFirstChild(Config.Track.FolderName)
	local line = track and track:FindFirstChild(Config.Track.FinishLineName)
	return if line and line:IsA("BasePart") then line.Position else nil
end

Remotes.get(Remotes.Names.PlayerFinished).OnClientEvent:Connect(function()
	local base = finishPoint()
	if not base then
		return
	end
	task.spawn(function()
		for i = 1, E.FireworkVolleys do
			local x = (i - (E.FireworkVolleys + 1) / 2) * 10
			Fx.burst("Firework", base + Vector3.new(x, E.FireworkHeight + math.random() * 4, 0))
			task.wait(0.35)
		end
	end)
end)
