--!strict
-- Режим «Кино» для промо-роликов (только Studio): K — следующий план камеры, J — предыдущий,
-- после последнего — выключено. В режиме: весь интерфейс скрыт (и верхняя панель Roblox),
-- освещение — дневное (только у себя: модификаторы «Ночь»/«Туман» на картинку не влияют).
-- Планы — Config.Dev.CinemaShots: плавный проезд камеры from→to или погоня за ближайшим гонщиком.
-- Записывать — записью экрана Mac (Cmd+Shift+5), окно Studio в фокусе.

local RunService = game:GetService("RunService")
if not RunService:IsStudio() then
	return
end

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local D = Config.Dev
local SHOTS = D.CinemaShots
local player = Players.LocalPlayer

local index = 0 -- 0 — выключено
local startedAt = 0
local hiddenGuis: { [ScreenGui]: boolean } = {}
local savedFov = 70

-- дневной свет: снимок при запуске (лобби — сезон без модификатора)
type LightSnap = { clock: number, brightness: number, ambient: Color3, outdoor: Color3, fogEnd: number, density: number?, haze: number? }
local day: LightSnap? = nil
local function snapLight()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	day = {
		clock = Lighting.ClockTime,
		brightness = Lighting.Brightness,
		ambient = Lighting.Ambient,
		outdoor = Lighting.OutdoorAmbient,
		fogEnd = Lighting.FogEnd,
		density = atmosphere and atmosphere.Density,
		haze = atmosphere and atmosphere.Haze,
	}
end
task.delay(3, snapLight)

local function applyDay()
	local d = day
	if not d then
		return
	end
	Lighting.ClockTime = d.clock
	Lighting.Brightness = d.brightness
	Lighting.Ambient = d.ambient
	Lighting.OutdoorAmbient = d.outdoor
	Lighting.FogEnd = d.fogEnd
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere and d.density then
		atmosphere.Density = d.density
		atmosphere.Haze = d.haze or atmosphere.Haze
	end
end

local function nearestRacer(from: Vector3): BasePart?
	local best: BasePart? = nil
	local bestD = math.huge
	local function consider(model: Instance?)
		local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = (root.Position - from).Magnitude
			if d < bestD then
				best, bestD = root, d
			end
		end
	end
	for _, model in CollectionService:GetTagged(Config.Bots.Tag) do
		consider(model)
	end
	for _, p in Players:GetPlayers() do
		consider(p.Character)
	end
	return best
end

local chaseTarget: BasePart? = nil

local function setActive(on: boolean)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, not on)
	end)
	local camera = workspace.CurrentCamera
	if on then
		savedFov = camera.FieldOfView
	else
		local playerGui = player:FindFirstChild("PlayerGui")
		for gui in hiddenGuis do
			gui.Parent = playerGui
		end
		table.clear(hiddenGuis)
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = savedFov
	end
end

local function select(step: number)
	local was = index
	index = (index + step) % (#SHOTS + 1)
	startedAt = os.clock()
	chaseTarget = nil
	if was == 0 and index ~= 0 then
		setActive(true)
	elseif index == 0 then
		setActive(false)
	end
	print(string.format("[Cinema] %s", if index == 0 then "off" else SHOTS[index].name))
end

local function smooth(u: number): number
	return u * u * (3 - 2 * u)
end

RunService:BindToRenderStep("CinemaCam", Enum.RenderPriority.Last.Value, function()
	if index == 0 then
		return
	end
	-- интерфейс отцепляем от экрана (некоторые HUD сами включают себя каждый кадр — Enabled не помогает);
	-- скрипты держат ссылки и работают дальше, при выходе вернём на место
	for _, gui in player.PlayerGui:GetChildren() do
		if gui:IsA("ScreenGui") then
			hiddenGuis[gui] = true
			gui.Parent = nil
		end
	end
	applyDay()
	local shot = SHOTS[index]
	local camera = workspace.CurrentCamera
	camera.CameraType = Enum.CameraType.Scriptable
	camera.FieldOfView = shot.fov
	if shot.follow then
		-- погоня: держимся за ближайшим гонщиком, сбоку-сзади, плавно
		local focus = camera.CFrame.Position
		if not chaseTarget or not chaseTarget.Parent then
			chaseTarget = nearestRacer(focus)
		end
		local target = chaseTarget
		if target then
			local flat = Vector3.new(target.CFrame.LookVector.X, 0, target.CFrame.LookVector.Z)
			local fwd = if flat.Magnitude > 0.1 then flat.Unit else Vector3.new(0, 0, -1)
			local right = fwd:Cross(Vector3.yAxis)
			local o = shot.offset
			local want = target.Position + right * o.X + Vector3.yAxis * o.Y - fwd * o.Z
			local pos = camera.CFrame.Position:Lerp(want, 0.08)
			camera.CFrame = CFrame.lookAt(pos, target.Position + fwd * 4)
		end
		return
	end
	local u = smooth(math.clamp((os.clock() - startedAt) / shot.seconds, 0, 1))
	camera.CFrame = CFrame.lookAt(shot.from:Lerp(shot.to, u), shot.lookFrom:Lerp(shot.lookTo, u))
end)

ContextActionService:BindAction("CinemaNext", function(_, state)
	if state == Enum.UserInputState.Begin then
		select(1)
	end
	return Enum.ContextActionResult.Pass
end, false, D.CinemaNextKey)
ContextActionService:BindAction("CinemaPrev", function(_, state)
	if state == Enum.UserInputState.Begin then
		select(-1)
	end
	return Enum.ContextActionResult.Pass
end, false, D.CinemaPrevKey)
