--!strict
-- «Ощущение выстрела» на рубеже — чисто визуальный отклик, на попадание не влияет
-- (попадание по-прежнему считает сервер):
--  * отдача: камера дёргается вверх и плавно возвращается, FOV на миг шире;
--  * попадание: на мишень сверху падает белая шторка;
--  * промах: короткая встряска камеры;
--  * серии крупно над прицелом: «2 подряд!», «🔥 3 подряд!», «ЧИСТО 5/5!»; промах — красное «+3 с».

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local C = Config.Shooting

local ShotFeedback = {}

local recoilAt = -math.huge
local shakeAt = -math.huge
local streak = 0
local hits = 0
local streakLabel: TextLabel? = nil
local streakScale: UIScale? = nil
local streakToken = 0

local GOLD = Color3.fromRGB(255, 205, 60)
local ORANGE = Color3.fromRGB(255, 140, 40)
local RED = Color3.fromRGB(255, 80, 80)

-- Надпись серии в HUD прицела (вызвать один раз).
function ShotFeedback.attach(gui: ScreenGui)
	local label = Instance.new("TextLabel")
	label.Name = "Streak"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.32)
	label.Size = UDim2.fromOffset(420, 64)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = GOLD
	label.TextStrokeTransparency = 0.2
	label.Visible = false
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = label
	streakLabel = label
	streakScale = scale
end

local function showStreak(text: string, color: Color3, big: boolean)
	local label, scale = streakLabel, streakScale
	if not label or not scale then
		return
	end
	streakToken += 1
	local token = streakToken
	label.Text = text
	label.TextColor3 = color
	label.Visible = true
	-- «подпрыгивание»: из маленького в большой с отскоком
	scale.Scale = 0.4
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = if big then 1.25 else 1,
	}):Play()
	task.delay(C.StreakShowTime, function()
		if token == streakToken then
			label.Visible = false
		end
	end)
end

-- Новый заход на рубеж.
function ShotFeedback.reset()
	streak = 0
	hits = 0
	recoilAt = -math.huge
	shakeAt = -math.huge
	streakToken += 1
	if streakLabel then
		streakLabel.Visible = false
	end
end

function ShotFeedback.onFire()
	recoilAt = os.clock()
end

-- Белая шторка падает на мишень (локальная копия, сервер и так красит мишень в белый).
local function dropShutter(target: BasePart, eyePos: Vector3)
	local shutter = Instance.new("Part")
	shutter.Name = "Shutter"
	shutter.Shape = Enum.PartType.Cylinder
	shutter.Size = target.Size + Vector3.new(0.02, 0.06, 0.06)
	shutter.Anchored = true
	shutter.CanCollide = false
	shutter.CanQuery = false
	shutter.CanTouch = false
	shutter.CastShadow = false
	shutter.Material = Enum.Material.SmoothPlastic
	shutter.Color = Color3.new(1, 1, 1)
	local toShooter = (eyePos - target.Position).Unit * 0.08
	local finalCf = target.CFrame + toShooter
	shutter.CFrame = finalCf + Vector3.new(0, target.Size.Y * 1.3, 0)
	shutter.Parent = workspace
	TweenService:Create(shutter, TweenInfo.new(C.ShutterTime, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = finalCf }):Play()
	Debris:AddItem(shutter, 2) -- к этому времени сервер уже покрасил мишень
end

-- Мишень с номером index, ближайшая к точке попадания.
local function findTarget(index: number, near: Vector3): BasePart?
	local name = "Target" .. index
	local track = workspace:FindFirstChild(Config.Track.FolderName)
	if not track then
		return nil
	end
	local best: BasePart?, bestDist = nil, 4
	for _, d in track:GetDescendants() do
		if d.Name == name and d:IsA("BasePart") then
			local dist = (d.Position - near).Magnitude
			if dist < bestDist then
				best, bestDist = d, dist
			end
		end
	end
	return best
end

function ShotFeedback.onResult(hit: boolean, targetIndex: number?, impact: Vector3?, eyePos: Vector3, shotsFired: number, totalShots: number, golden: boolean?)
	if hit then
		streak += 1
		hits += 1
		if targetIndex and impact then
			local target = findTarget(targetIndex, impact)
			if target then
				dropShutter(target, eyePos)
			end
		end
	else
		streak = 0
		shakeAt = os.clock()
	end

	local last = shotsFired >= totalShots
	if last and hits == totalShots then
		showStreak(string.format("ЧИСТО %d/%d! 🔥 ТУРБО", hits, totalShots), GOLD, true)
	elseif golden then
		showStreak(string.format("⭐ ЗОЛОТО! −%d с", Config.Reward.GoldenBonusSeconds), GOLD, true)
	elseif not hit then
		showStreak(string.format("+%d с", Config.Penalty.SecondsPerMiss), RED, true) -- штраф за промах
	elseif streak >= 4 then
		showStreak(string.format("🔥🔥 %d подряд!", streak), ORANGE, true)
	elseif streak == 3 then
		showStreak("🔥 3 подряд!", ORANGE, false)
	elseif streak == 2 then
		showStreak("2 подряд!", GOLD, false)
	end
end

-- Смещение камеры прицела сейчас: (рысканье°, тангаж°, +FOV°). Добавляется только к картинке.
function ShotFeedback.cameraOffset(): (number, number, number)
	local t = os.clock()
	local yaw, pitch, fov = 0, 0, 0

	local sinceRecoil = t - recoilAt
	if sinceRecoil < C.RecoilReturnTime then
		local k = 1 - sinceRecoil / C.RecoilReturnTime
		k = k * k -- быстрый рывок, плавный возврат
		pitch += C.RecoilDeg * k
		fov += C.RecoilFovKick * k
	end

	local sinceShake = t - shakeAt
	if sinceShake < C.MissShakeTime then
		local k = 1 - sinceShake / C.MissShakeTime
		yaw += math.sin(sinceShake * 90) * C.MissShakeDeg * k
		pitch += math.cos(sinceShake * 70) * C.MissShakeDeg * 0.6 * k
	end
	return yaw, pitch, fov
end

return ShotFeedback
