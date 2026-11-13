--!strict
-- Имена всех RemoteEvent'ов в одном месте.
-- Сервер создаёт их при старте (Remotes.createAll), клиент берёт через Remotes.get.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FOLDER_NAME = "Remotes"

local Remotes = {
	Names = {
		-- сервер -> клиент
		RaceState = "RaceState", -- Types.RaceStatePayload
		RaceResults = "RaceResults", -- {Types.ResultEntry}
		PlayerFinished = "PlayerFinished", -- Types.ResultEntry
		ShootingStarted = "ShootingStarted", -- Types.ShootingStartPayload (только стрелку)
		ShotResult = "ShotResult", -- Types.ShotResultPayload (только стрелку)
		ShootingFinished = "ShootingFinished", -- Types.ShootingSummary (всем, лента событий)
		Notice = "Notice", -- (text: string) короткое сообщение игроку в ленту событий
		Standings = "Standings", -- {Types.StandingEntry} таблица позиций во время гонки
		KnockedDown = "KnockedDown", -- (duration: number) сбили препятствием — упасть и встать (только сбитому)

		-- клиент -> сервер (намерения, сервер проверяет)
		SprintIntent = "SprintIntent", -- (wantsSprint: boolean)
		FireShot = "FireShot", -- (aimYawDeg: number, aimPitchDeg: number, shotTime: number)
		HoldBreath = "HoldBreath", -- ()
		PushIntent = "PushIntent", -- () толкнуть соперника впереди
	},
}

-- Только сервер: создать папку и все события.
function Remotes.createAll()
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = FOLDER_NAME
		folder.Parent = ReplicatedStorage
	end
	for _, name in Remotes.Names do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
end

function Remotes.get(name: string): RemoteEvent
	local folder = ReplicatedStorage:WaitForChild(FOLDER_NAME)
	return folder:WaitForChild(name) :: RemoteEvent
end

return Remotes
