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
		RespawnHeight = 3, -- на сколько выше пола чекпоинта ставим игрока	},
}

return Config
