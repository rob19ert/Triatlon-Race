--!strict
-- После гонки камера PodiumTime секунд смотрит на подиум (деталь Camera в модели Track/Podium),
-- потом возвращается к игроку — и RaceHud показывает таблицу результатов.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local token = 0

local function restore()
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Custom
end

Remotes.get(Remotes.Names.RaceResults).OnClientEvent:Connect(function()
	local track = workspace:FindFirstChild(Config.Track.FolderName)
	local podium = track and track:FindFirstChild(Config.Track.PodiumName)
	local viewPoint = podium and podium:FindFirstChild("Camera")
	if not viewPoint or not viewPoint:IsA("BasePart") then
		return
	end
	token += 1
	local myToken = token
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = viewPoint.CFrame
	task.delay(Config.Race.PodiumTime, function()
		if myToken == token then
			restore()
		end
	end)
end)

-- новая гонка (или возврат в лобби) — камера точно обычная
Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: { state: string })
	if payload.state ~= "Results" then
		token += 1
		restore()
	end
end)
