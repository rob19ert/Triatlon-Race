--!strict
-- Все игровые числа в одном месте. Это стартовые значения — крутим здесь, не в коде.

local Config = {
	Race = {
		MinPlayers = 1, -- гонка стартует по таймеру лобби с любым числом игроков
		MaxPlayers = 12, -- при полном составе старт сразу, без ожидания
		LobbyWaitTime = 30, -- с, ожидание в лобби после набора MinPlayers
		StudioLobbyWaitTime = 10, -- в Studio (плейтест) ждём меньше
		StandingsInterval = 0.5, -- с, как часто пересчитывать и рассылать таблицу позиций
		CountdownTime = 3, -- с, отсчёт перед стартом
		DnfAfterWinner = 60, -- с после финиша победителя, потом DNF
		StudioDnfAfterWinner = 300, -- в Studio (тест на нескольких клиентах) ждём дольше
		MaxRaceTime = 7 * 60, -- с, страховка от бесконечной гонки
		PodiumTime = 5, -- с, камера на подиуме перед таблицей
		ResultsTime = 10, -- с, показ таблицы результатов (после подиума)
		PhotoFinishGap = 0.1, -- с, разница с соседом меньше — «Фотофиниш!»
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

		-- мягкая догонялка: последняя треть таблицы восстанавливает пульс быстрее
		CatchUpShare = 1 / 3,
		CatchUpRecoveryBonus = 0.15,
		CatchUpMinRacers = 3, -- при меньшем числе участников не включается

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

	-- Толчок соперника (пати-хаос). Пульс не тратит.
	Push = {
		Range = 6, -- стад, дальность до соперника
		ConeAngleDeg = 50, -- полуугол конуса впереди толкающего
		Cooldown = 5, -- с, после удачного толчка
		MissCooldown = 1, -- с, если рядом никого не оказалось
		Speed = 32, -- стад/с, скорость отлёта соперника по горизонтали
		UpSpeed = 14, -- стад/с вверх
		Duration = 0.2, -- с, сколько держится импульс (LinearVelocity)
	},

	-- Подвижные препятствия (маятники, мельницы). Движение — формула от серверного времени,
	-- клиент рисует, сервер по той же формуле ловит попадания.
	Hazards = {
		PendulumTag = "Pendulum", -- модель: Pivot (ось, не двигается) + качающиеся части
		WindmillTag = "Windmill", -- модель: Pivot (ступица) + лопасти
		HitsAttribute = "Hits", -- true у частей, которые сбивают (груз, лопасти)
		PivotName = "Pivot",

		-- значения по умолчанию, модель может переопределить атрибутами
		PendulumPeriod = 3, -- с, полный цикл туда-обратно (атрибут Period)
		PendulumAmplitudeDeg = 60, -- (атрибут AmplitudeDeg)
		WindmillRpm = 10, -- оборотов в минуту, знак = направление (атрибут Rpm)
		-- атрибут Phase (0–1) — сдвиг по времени, чтобы соседние не шли в такт

		HitPadding = 1.5, -- стад, «толщина» персонажа при проверке попадания
		HitTimeLag = 0.1, -- с, сервер проверяет препятствие чуть в прошлом (позиция персонажа приходит с задержкой)
		HitImmunity = 1.5, -- с после сбивания, когда то же игрока не бьёт снова

		KnockSpeed = 40, -- стад/с, отлёт по горизонтали
		KnockUpSpeed = 22, -- стад/с вверх
		KnockImpulseTime = 0.2, -- с, сколько держится импульс
		KnockdownTime = 1, -- с, лежит, потом встаёт
		TumbleSpin = 8, -- рад/с, кувырок при падении (клиент)
	},

	-- Режим зрителя (финишировал или зашёл посреди гонки)
	Spectator = {
		PrevKey = Enum.KeyCode.Left,
		NextKey = Enum.KeyCode.Right,
	},

	-- Сезоны: детали окружения с тегом Themed и атрибутом Role красятся по палитре сезона,
	-- папки Decor/<Сезон> показываются только для текущего сезона. Применяет ThemeService.
	Theme = {
		Tag = "Themed",
		RoleAttribute = "Role",
		DecorFolder = "Decor", -- workspace.Decor/<Сезон>
		Current = "Summer", -- сезон по умолчанию (потом — ротация/голосование)
	},

	-- Болельщики на трибунах: создаёт и анимирует только клиент (не реплицируются, сервер не нагружают)
	Crowd = {
		RowTag = "StandRow", -- ряд сидений (атрибут Facing: +1 смотрят в +X, -1 в -X)
		SeatSpacing = 2.6, -- стад между местами в ряду
		FillChance = 0.65, -- доля занятых мест
		PropChance = 0.25, -- доля болельщиков с флажком
		AnimateRadius = 160, -- стад от камеры: дальше болельщики замирают (экономим кадр)
		CheerRadius = 30, -- стад: гонщик ближе — болельщик прыгает и машет
		CheerOnFinishTime = 3, -- с, ликуют все после чьего-то финиша
		UpdateInterval = 0.1, -- с, как часто пересчитывать, кто ликует
		IdleBob = 0.12, -- стад, лёгкое покачивание
		IdleSpeed = 2.2, -- рад/с
		CheerJump = 1.3, -- стад, высота прыжка
		CheerSpeed = 9, -- рад/с
	},

	-- Только Studio: помощники для тестов на нескольких клиентах
	Dev = {
		ToFinishKey = Enum.KeyCode.G, -- перенести к финишу, минуя стрельбы
		ToFinishDistance = 10, -- стад до финишной линии
		ToFinishSpacing = 4, -- стад между игроками по ширине
	},

	Penalty = {
		LoopName = "PenaltyLoop", -- модели в Track с этим префиксом (атрибут Order = стрельбище): Near, Far (зоны круга), Check (проверка на трассе), Return (точка возврата)
		LapsPerMiss = 1,
		CounterOffsetY = 3, -- высота счётчика «Штраф: 1/3» над головой
	},

	Track = {
		FolderName = "Track",
		StartGridName = "StartGrid",
		FinishZoneName = "FinishZone",
		FinishLineName = "FinishLine", -- финиш = пересечение плоскости этой детали (время интерполируется между кадрами)
		PodiumName = "Podium", -- модель: Spot1..Spot3 (куда ставить призёров), Camera (откуда смотреть)
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
