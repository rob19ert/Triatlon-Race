--!strict
-- Помощники для тестов, работают ТОЛЬКО в Studio (на живых серверах игнорируются).
-- G — перенести игрока к финишной линии, минуя стрельбы: удобно в тесте на нескольких клиентах.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local D = Config.Dev

local DevService = {}

local RaceManager: any
local StaminaService: any
local ProgressTracker: any
local ShootingService: any
local slot = 0 -- раскладываем по ширине, чтобы не стояли друг в друге

local function onToFinish(player: Player)
	if not RunService:IsStudio() then
		return
	end
	if RaceManager.getState() ~= "Racing" or not ProgressTracker.isTracked(player) or ShootingService.isShooting(player) then
		return
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not character or not root then
		return
	end
	local track = workspace:WaitForChild(Config.Track.FolderName)
	local line = track:WaitForChild(Config.Track.FinishLineName) :: BasePart
	-- трасса идёт вдоль -Z: встаём перед линией, лицом к ней
	local x = ((slot % 5) - 2) * D.ToFinishSpacing
	slot += 1
	local pos = line.Position + Vector3.new(x, 3, D.ToFinishDistance)
	root.AssemblyLinearVelocity = Vector3.zero
	character:PivotTo(CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)))
	print(string.format("[DevService] %s -> finish line", player.Name))
end

function DevService.init(services: { [string]: any })
	RaceManager = services.RaceManager
	ProgressTracker = services.ProgressTracker
	ShootingService = services.ShootingService
	StaminaService = services.StaminaService
end

local function onBikeMode(player: Player)
	if not RunService:IsStudio() then
		return
	end
	local on = StaminaService.getSpeedOverride(player) == nil
	StaminaService.setSpeedOverride(player, if on then D.BikeModeSpeed else nil)
	print(string.format("[DevService] %s bike mode %s", player.Name, if on then "ON" else "OFF"))
end

function DevService.start()
	if RunService:IsStudio() then
		Remotes.get(Remotes.Names.DevToFinish).OnServerEvent:Connect(onToFinish)
		Remotes.get(Remotes.Names.DevBikeMode).OnServerEvent:Connect(onBikeMode)
	end
end

return DevService
