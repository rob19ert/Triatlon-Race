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
