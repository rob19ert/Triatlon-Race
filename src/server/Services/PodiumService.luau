--!strict
-- Подиум после гонки: топ-3 ставятся на ступени (Spot1..Spot3 в модели Track/Podium),
-- замирают лицом к камере. Камеру на подиум у клиентов включает клиент по RaceResults.
-- Персонажи пересоздаются при возврате в лобби, поэтому снимать заморозку не нужно.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local Types = require(ReplicatedStorage.Shared.Types)

local PODIUM_PLACES = 3
local STAND_HEIGHT = 3 -- HumanoidRootPart над верхом ступени

local PodiumService = {}

local podium: Model?

function PodiumService.show(results: { Types.ResultEntry })
	if not podium then
		return
	end
	local camera = podium:FindFirstChild("Camera") :: BasePart?
	for _, entry in results do
		local place = entry.place
		if entry.dnf or not place or place > PODIUM_PLACES then
			continue
		end
		local spot = podium:FindFirstChild("Spot" .. place) :: BasePart?
		local player = Players:GetPlayerByUserId(entry.userId)
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not spot or not character or not root then
			continue
		end
		local pos = spot.Position + Vector3.new(0, spot.Size.Y / 2 + STAND_HEIGHT, 0)
		local look = if camera then Vector3.new(camera.Position.X, pos.Y, camera.Position.Z) else pos + Vector3.new(0, 0, 1)
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
		character:PivotTo(CFrame.lookAt(pos, look))
	end
end

function PodiumService.start()
	local track = workspace:WaitForChild(Config.Track.FolderName)
	podium = track:FindFirstChild(Config.Track.PodiumName) :: Model?
	if not podium then
		warn("[PodiumService] no Track/" .. Config.Track.PodiumName .. " model — podium disabled")
	end
end

return PodiumService
