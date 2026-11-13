--!strict
-- Все игровые числа в одном месте. Это стартовые значения — крутим здесь, не в коде.

local Config = {
	Race = {
		MinPlayers = 1, -- для теста в Studio; для боя поставить 4
		MaxPlayers = 12,
		LobbyWaitTime = 10, -- с, ожидание в лобби после набора MinPlayers
		CountdownTime = 3, -- с, отсчёт перед стартом
		DnfAfterWinner = 60, -- с после финиша победителя, потом DNF
		MaxRaceTime = 7 * 60, -- с, страховка от бесконечной гонки
		ResultsTime = 10, -- с, показ таблицы результатов
	},

	Movement = {
		WalkSpeed = 16,
		SprintSpeed = 24,
	},

	-- Пульс 0–100, общий на всю гонку
	Stamina = {
		StartPulse = 50, -- пульс на старте
		RunPulse = 50, -- обычный бег держит пульс около этого значения
		MinPulse = 20, -- ниже не опускается (пульс покоя)
		MaxPulse = 100,

		SprintGainPerSec = 8, -- спринт
		RunDriftPerSec = 4, -- скорость, с которой обычный бег тянет пульс к RunPulse
		RestRecoveryPerSec = 15, -- стоять на месте
		JumpCost = 3, -- за прыжок

		RedZoneEnter = 90, -- красная зона: спринт недоступен, скорость ниже
		RedZoneExit = 70, -- выход из красной зоны
		RedZoneSpeedMultiplier = 0.9,

		MovingSpeedThreshold = 2, -- стад/с: медленнее — считаем, что игрок стоит
		JumpVelocityThreshold = 30, -- стад/с вверх: рост скорости через порог = прыжок
		PublishInterval = 0.1, -- с, как часто обновлять атрибуты для клиентов

		-- для HUD: «удары в минуту» = линейно от пульса
		BpmAtMin = 60,
		BpmAtMax = 200,
	},

	Shooting = {
		RangeTag = "ShootingRange", -- CollectionService-тег модели стрельбища (атрибуты Order, Stance)
		ShotsPerStage = 5,
		MinShotInterval = 0.6, -- с, перезарядка затвора
		ShotTimeTolerance = 0.35, -- с, насколько метка выстрела с клиента может отставать от сервера
		AimLimitDeg = 12, -- насколько далеко от центра мишеней можно увести прицел
		EyeAboveRoot = 1.5, -- глаза стрелка выше HumanoidRootPart
		FinishDelay = 1, -- с после последнего выстрела до выхода с рубежа

		-- по стойке (атрибут Stance у стрельбища)
		TargetDiameter = { Prone = 1.2, Standing = 0.72 }, -- стоя на 40% меньше
		SwayMultiplier = { Prone = 1, Standing = 1.5 },

		-- качание «восьмёркой»: амплитуда растёт с пульсом
		SwayBaseDeg = 0.05, -- минимальное качание
		SwayPulseOffset = 30, -- ниже этого пульса качание не растёт
		SwayDegPerPulse = 0.02, -- градусов амплитуды на единицу пульса выше SwayPulseOffset
		SwayFrequency = 0.35, -- Гц

		-- задержка дыхания
		HoldBreathDuration = 2,
		HoldBreathCooldown = 4, -- с после окончания задержки
		HoldBreathPulseCost = 10, -- пульс после задержки
		HoldBreathSwayMultiplier = 0.1,

		-- ветер: уровень 0–3, направление влево/вправо, на всю гонку для каждого стрельбища
		WindMaxLevel = 3,
		WindDegPerLevel = 0.6, -- смещение пули в градусах на уровень

		TargetOpenColor = Color3.fromRGB(20, 20, 20),
		TargetClosedColor = Color3.fromRGB(255, 255, 255),

		-- клиент
		ImpactMarkSeconds = 4, -- сколько виден след пули на щите
		ImpactMarkSize = 0.3,
		ScopeFov = 15,
		MouseSensitivity = 0.012, -- градусов на пиксель
		TouchSensitivity = 0.02,
	},

	Penalty = {
		LoopName = "PenaltyLoop", -- модель в Track: Near, Far (зоны круга), Check (проверка на трассе), Return (точка возврата)
		LapsPerMiss = 1,
		CounterOffsetY = 3, -- высота счётчика «Штраф: 1/3» над головой
	},

	Track = {
		FolderName = "Track",
		StartGridName = "StartGrid",
		FinishZoneName = "FinishZone",
		GridSpacing = 4, -- стадов между игроками на старте
		GridRowSize = 6, -- игроков в ряду

		-- препятствия
		CheckpointTag = "Checkpoint", -- CollectionService-тег зоны начала препятствия (атрибут Order)
		FallZoneTag = "FallZone", -- тег зоны падения (вода и т.п.)
		KillY = -20, -- ниже этой высоты — тоже падение
		RespawnHeight = 3, -- на сколько выше пола чекпоинта ставим игрока
	},
}

return Config
