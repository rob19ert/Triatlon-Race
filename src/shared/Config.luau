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
		EyeAboveRoot = 1.5, -- глаза стрелка выше HumanoidRootPart
		FinishDelay = 1, -- с после последнего выстрела до выхода с рубежа

		-- по стойке (атрибут Stance у стрельбища)
		TargetDiameter = { Prone = 1.2, Standing = 0.72 }, -- стоя на 40% меньше
		StanceSpeedMultiplier = { Prone = 1, Standing = 1.2 }, -- маятник стоя быстрее
		TremorMultiplier = { Prone = 1, Standing = 1.5 }, -- и трясёт сильнее

		-- Мушка-маятник: сама ходит слева направо через все мишени, игрок только жмёт «Огонь» вовремя.
		-- Скорость фиксируется по пульсу в момент выхода на рубеж (прибежал уставшим — быстрый маятник).
		PendulumWidth = 2.6, -- размах в шагах между мишенями от центра (мишени — на ±2)
		PendulumCalmPulse = 30, -- при этом пульсе и ниже — самый медленный маятник
		PendulumTiredPulse = 90, -- при этом и выше — самый быстрый
		PendulumPeriodCalm = 3.2, -- с, полный цикл туда-обратно
		PendulumPeriodTired = 1.8,
		-- вертикальная дрожь: по текущему пульсу (стоишь — пульс падает — дрожь стихает)
		TremorBaseDeg = 0.08,
		TremorDegPerPulse = 0.008, -- на единицу пульса выше PendulumCalmPulse
		TremorFrequency = 1.3, -- Гц

		-- задержка дыхания
		HoldBreathDuration = 2,
		HoldBreathCooldown = 4, -- с после окончания задержки
		HoldBreathPulseCost = 10, -- пульс после задержки
		HoldBreathSpeedMultiplier = 0.35, -- маятник во время задержки медленнее
		HoldBreathTremorMultiplier = 0.15, -- и почти не дрожит

		TargetOpenColor = Color3.fromRGB(20, 20, 20),
		TargetClosedColor = Color3.fromRGB(255, 255, 255),

		-- клиент: отклик выстрела (только визуал, на попадание не влияет)
		RecoilDeg = 1.6, -- рывок камеры вверх при выстреле
		RecoilReturnTime = 0.25, -- с, возврат после отдачи
		RecoilFovKick = 2, -- градусов FOV на мгновение шире
		MissShakeDeg = 0.35, -- встряска камеры при промахе
		MissShakeTime = 0.22,
		ShutterTime = 0.08, -- с, шторка падает на мишень (резкий старт)
		StreakShowTime = 1.3, -- с, сколько висит надпись серии

		-- клиент
		ImpactMarkSeconds = 4, -- сколько виден след пули на щите
		ImpactMarkSize = 0.3,
		ScopeFov = 15,
	},

	-- Толчок соперника (пати-хаос). Пульс не тратит.
	Push = {
		Range = 8, -- стад, дальность до соперника
		ConeAngleDeg = 100, -- полуугол: вперёд и в стороны (бегущий рядом тоже), но не назад
		Cooldown = 3, -- с, после удачного толчка
		MissCooldown = 1, -- с, если рядом никого не оказалось
		Speed = 45, -- стад/с, скорость отлёта соперника по горизонтали
		UpSpeed = 18, -- стад/с вверх
		Duration = 0.2, -- с, сколько держится импульс (LinearVelocity)
		KnockdownTime = 0.6, -- с, соперник падает и встаёт
		TargetImmunity = 1.5, -- с после толчка, когда этого игрока толкнуть нельзя (против спама толпой)
		AnimTime = 0.35, -- с, руки вперёд у толкающего (клиент)
		AnimArmDeg = 85, -- на сколько градусов руки уходят вперёд
	},

	-- Усталость на экране (клиент, только картинка): чем выше пульс, тем сильнее
	Fatigue = {
		StartPulse = 70, -- с этого пульса начинаются эффекты
		BreathPeriodSlow = 1.6, -- с, вдох-выдох при StartPulse
		BreathPeriodFast = 0.75, -- с, при пульсе 100
		CameraBobDeg = 0.9, -- «дыхание» камеры по вертикали при пульсе 100
		CameraRollDeg = 0.5, -- покачивание
		VignetteMaxAlpha = 0.55, -- насколько темнеют края при пульсе 100 (0 — нет, 1 — чёрные)
		RedZoneBlur = 3, -- размытие в красной зоне
		RedZoneSaturation = -0.25, -- выцветание в красной зоне
	},

	-- Подвижные препятствия (маятники, мельницы). Движение — формула от серверного времени,
	-- клиент рисует, сервер по той же формуле ловит попадания.
	Hazards = {
		PendulumTag = "Pendulum", -- модель: Pivot (ось, не двигается) + качающиеся части
		WindmillTag = "Windmill", -- модель: Pivot (ступица) + лопасти
		TrainTag = "Train", -- поезд-челнок по расписанию (атрибуты Period, Delay, Distance, Speed)
		MoverTag = "Mover", -- то же для бочек, овец и прочих «живых помех» (+ RollRadius — катится)
		GateTag = "RailGate", -- шлагбаум (атрибуты Period, ClosedFrom, ClosedTo)
		BarrierTag = "RailBarrier", -- невидимая стенка у шлагбаума: твёрдая, пока закрыто (сервер)
		RailLightTag = "RailLight", -- мигающий фонарь переезда (клиент; те же атрибуты расписания)
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
	-- Модификатор заезда: в лобби — голосование за один из Options случайных, действует одну гонку.
	-- Атмосфера (Fog, Night) переопределяет поля Atmosphere поверх сезона; после гонки сезон возвращается.
	Modifiers = {
		Options = 3, -- сколько карточек в лобби
		Pool = { "Fog", "Night", "LowGravity" }, -- из кого выбирать (вид карты; игровые эффекты — в боксах, Config.Boxes)
		BannerTime = 2.5, -- с, крупная надпись на отсчёте
		Defs = {
			Fog = {
				icon = "🌫",
				title = "Туман",
				desc = "Видно на пару шагов",
				atmosphere = { density = 0.82, offset = 0.1, haze = 6, glare = 0, color = Color3.fromRGB(205, 210, 216), decay = Color3.fromRGB(185, 190, 198) },
			},
			Night = {
				icon = "🌙",
				title = "Ночь",
				desc = "Темно, у всех фары",
				lighting = {
					clockTime = 0.5,
					brightness = 1,
					ambient = Color3.fromRGB(45, 50, 80),
					outdoorAmbient = Color3.fromRGB(70, 75, 110),
				},
				atmosphere = { density = 0.35, offset = 0, haze = 0.5, glare = 0, color = Color3.fromRGB(40, 45, 80), decay = Color3.fromRGB(20, 22, 45) },
				headlamp = { range = 60, brightness = 4, angle = 70, glowRange = 14, glowBrightness = 1.2, color = Color3.fromRGB(255, 240, 200) },
			},
			LowGravity = {
				icon = "🎈",
				title = "Низкая гравитация",
				desc = "Прыжки до небес",
				gravity = 80, -- обычная 196.2; полёты с трамплинов и толчков дольше
				jumpMultiplier = 2, -- высоту прыжка (в стадах) движок держит при любой гравитации — поднимаем сами
			},
		},
	},

	-- Секретные боксы «?» на трассе: проехал сквозь — случайный бонус только тебе; бокс пропадает у всех
	-- и через RespawnTime появляется в другой свободной точке (детали с тегом SpotTag).
	-- Лёд на поворотах велокруга (детали с тегом IcePatch, атрибут SlideDir — наружу из поворота).
	-- На льду скорость падает и сносит наружу; каждый клик/тап — сцепление (сервер, IceService).
	Ice = {
		Tag = "IcePatch",
		HeightAbove = 8, -- стад над льдом, где ещё «на льду» (корень персонажа на велосипеде ~3–4)
		MinSpeed = 0.4, -- скорость × при нулевом сцеплении (с полным — ×1)
		StartGrip = 0.5, -- сцепление при въезде на лёд (0..1)
		GripPerClick = 0.2,
		GripDecayPerSec = 0.6, -- уходит само: от ~4 кликов/с сцепление растёт, без кликов — ноль меньше чем за секунду
		MaxClicksPerSec = 10, -- чаще не засчитываем (автокликер не помогает)
		SlideStrength = 0.6, -- снос наружу при нулевом сцеплении (доля к направлению движения)
		Hint = "ЖМИ!",
	},

	Boxes = {
		SpotTag = "BoxSpot", -- невидимые точки, где может появиться бокс
		BoxTag = "PowerBox", -- сам бокс (клиент крутит и покачивает)
		Active = 5, -- сколько боксов одновременно на трассе
		RespawnTime = 8, -- с, через сколько взятый бокс появляется снова (в другом месте)
		PickupRadius = 4.5, -- стад от центра бокса до корня персонажа
		Size = 3,
		Color = Color3.fromRGB(255, 190, 40),
		Effects = { "Turbo", "MegaPush", "BigTargets", "Shield", "Ghost", "SecondWind", "TimeBonus", "Snail", "Invert", "Spring", "Roulette" },
		-- шанс подвоха (kind = "bad") по месту в гонке: лидеру чаще, последнему редко; одному в гонке — Solo
		BadChance = { Leader = 0.4, Last = 0.05, Solo = 0.2 },
		Defs = {
			Turbo = { icon = "⚡", title = "Турбо", hint = "быстрее 5 с", seconds = 5 }, -- то же турбо, что за 5/5 (Config.Reward)
			MegaPush = {
				icon = "💥",
				title = "Мега-толчок",
				hint = "толкни соперника (F)",
				seconds = 5,
				rivalRadius = 80, -- стад: выдаём, только если соперник ближе (иначе толкать некого)
				force = 1.5, -- отлёт соперника ×
				up = 1.2, -- вверх ×
				cooldown = 1.5, -- с вместо Push.Cooldown
			},
			BigTargets = {
				icon = "🎯",
				title = "Большие мишени",
				hint = "на следующей стрельбе",
				scale = 1.6, -- диаметр мишени × на следующую стрельбу
				maxDiameter = 1.33, -- но не больше (мишени стоят через 1,4 стад — не слипаться)
				pendulumSpeed = 1.3, -- маятник мушки быстрее
			},
			Shield = { icon = "🛡", title = "Щит", hint = "погасит один удар", seconds = 30 }, -- гасит одно попадание (маятник, поезд, толчок…); пропадает через seconds
			Ghost = { icon = "👻", title = "Призрак", hint = "сквозь препятствия 4 с", seconds = 4, transparency = 0.65 }, -- сквозь препятствия и толчки
			SecondWind = { icon = "💚", title = "Второе дыхание", hint = "пульс вниз", pulse = 30, uselessBelow = 45 }, -- пульс сразу до pulse; ниже uselessBelow — не выдаём
			TimeBonus = { icon = "⏱", title = "−2 секунды", hint = "к итоговому времени", seconds = 2 }, -- к итоговому времени
			-- подвохи (щит или призрак их гасят)
			Snail = { icon = "🐌", title = "Улитка", hint = "медленнее 3 с", kind = "bad", seconds = 3, speed = 0.5 },
			Invert = { icon = "🔄", title = "Наоборот", hint = "лево и право перепутаны 6 с", kind = "bad", seconds = 6 },
			-- разное
			Spring = { icon = "🦘", title = "Пружина", hint = "3 прыжка выше", jumps = 3, multiplier = 2.2, seconds = 20 }, -- JumpHeight ×; неистраченные прыжки сгорают через seconds
			Roulette = { icon = "🎲", title = "Рулетка", hint = "что выпадет?", kind = "any" }, -- случайный бонус: подвох или польза 50/50
		},
	},

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
		CleanShootingRadius = 100, -- стад: болельщики вокруг стрелка ликуют после его 5/5
		UpdateInterval = 0.1, -- с, как часто пересчитывать, кто ликует
		IdleBob = 0.12, -- стад, лёгкое покачивание
		IdleSpeed = 2.2, -- рад/с
		CheerJump = 1.3, -- стад, высота прыжка
		CheerSpeed = 9, -- рад/с
	},

	-- Звуки: id из бесплатной библиотеки Roblox (Creator Store). Пока только удар маятника —
	-- остальные звуки (выстрел, попадание, сердце, финиш) убраны: не понравились, подберём позже.
	Sounds = {
		Bonk = { id = 3765689841, volume = 0.8 }, -- сбил маятник
	},

	-- Частицы (клиент): числа ограничены ради телефонов
	Effects = {
		ConfettiCount = 40, -- попадание в мишень
		DustCount = 18, -- падение после удара
		FireworkCount = 60, -- салют, на каждый залп
		FireworkVolleys = 3,
		FireworkHeight = 18, -- стад над финишной аркой
	},

	-- Только Studio: помощники для тестов на нескольких клиентах
	Dev = {
		ToFinishKey = Enum.KeyCode.G, -- перенести к финишу, минуя стрельбы
		ToFinishDistance = 10, -- стад до финишной линии
		ToFinishSpacing = 4, -- стад между игроками по ширине
		ToBikeKey = Enum.KeyCode.B, -- засчитать первую стрельбу и перенести в зону посадки на велосипед
	},

	-- Велопетля (фаза 2): трамплины, ускорители, возврат на дорогу
	Bike = {
		-- велосипед (аркадный: персонаж с повышенной скоростью и прикреплённой моделью)
		MountTag = "BikeMount", -- зона посадки в велопарке (север)
		DismountTag = "BikeDismount", -- зона высадки (юг)
		GateTag = "BikeGate", -- невидимые ворота круга (атрибут Order 1..N, LookVector = по ходу); Order 0 — начало круга
		SkipNotice = "Сначала проедь круг!", -- въехал в высадку, не пройдя все ворота
		RideSpeed = 36, -- стад/с, обычная езда (пульс держится ~RunPulse)
		PedalSpeed = 46, -- стад/с, педали (кнопка спринта; пульс +SprintGainPerSec)
		CoastRecoveryPerSec = 5, -- спуск без педалей: пульс −5/с
		CoastMinDropSpeed = 3, -- стад/с вниз: быстрее — считаем, что катится под горку
		ShoulderSpeedMultiplier = 0.6, -- за краем дороги (обочина, до OffRoadMargin): −40%
		-- модель и поза (шаблон ServerStorage/BikeTemplate: Root у земли между колёсами, вперёд = −Z;
		-- моторы FrontWheelMotor / RearWheelMotor / CrankMotor; детали с атрибутом Paint красятся в цвет игрока)
		TemplateName = "BikeTemplate",
		ModelName = "Bike", -- имя клона внутри персонажа
		Colors = { -- цвет рамы: по UserId игрока
			Color3.fromRGB(235, 60, 60),
			Color3.fromRGB(40, 140, 255),
			Color3.fromRGB(60, 200, 90),
			Color3.fromRGB(255, 170, 30),
			Color3.fromRGB(170, 80, 230),
			Color3.fromRGB(255, 95, 180),
			Color3.fromRGB(30, 200, 200),
			Color3.fromRGB(250, 220, 40),
		},
		WheelRadius = 1.3, -- стад, для скорости вращения колёс
		CrankTurnsPerStud = 0.12, -- оборотов педалей на стад пути
		PoseLeanDeg = 18, -- наклон корпуса вперёд
		PoseArmsDeg = 62, -- руки вперёд к рулю
		PoseHipDeg = 38, -- бедро вперёд (средняя точка)
		PoseHipSwingDeg = 22, -- размах бедра при педалировании
		PoseKneeDeg = 55, -- сгиб колена (средняя точка)
		PoseKneeSwingDeg = 30,
		RoadTag = "BikeRoad", -- куски дороги петли (отрезки Seg — по центральной линии, атрибут Width)
		LaunchTag = "LaunchPad", -- зона на верхнем крае трамплина
		BoostTag = "BoostPad", -- светящаяся полоса-ускоритель
		LaunchForwardSpeed = 46, -- стад/с вперёд при броске с трамплина
		LaunchUpSpeed = 30, -- стад/с вверх
		LaunchTime = 0.25, -- с, сколько держится импульс
		LaunchMinSpeed = 8, -- медленнее — трамплин не бросает (просто заехал шагом)
		LaunchCooldown = 0.8,
		BoostMultiplier = 1.3, -- ускоритель: +30% скорости
		BoostSeconds = 2,
		OffRoadMargin = 3, -- стад за краем дороги — ещё можно (обочина)
		OffRoadGrace = 0.15, -- с вне дороги на земле — потом возврат на центр
		StadiumEdgeX = -92, -- восточнее (стадион, велопарк) проверки нет
		-- мост с падающими плитами
		PlateTag = "FallingPlate",
		PlateWarnTime = 0.35, -- с: наехал — плита мигает, потом падает (на полной скорости успеваешь проскочить)
		PlateFallTime = 0.6, -- с, полёт вниз
		PlateFallDepth = 14,
		PlateRespawnTime = 4, -- с, через сколько плита возвращается
		PlateWarnColor = Color3.fromRGB(255, 140, 30),
	},

	-- Награда за риск на рубеже
	Reward = {
		TurboSpeedMultiplier = 1.2, -- 5/5 → турбо: +20% скорости
		TurboSeconds = 6, -- с, после ухода с рубежа
		TurboFov = 6, -- градусов шире поле зрения в турбо (клиент)
		GoldenChance = 0.4, -- шанс, что на рубеже будет золотая мишень
		GoldenSizeMultiplier = 0.6, -- золотая мишень меньше
		GoldenColor = Color3.fromRGB(255, 200, 30),
		GoldenBonusSeconds = 3, -- попал в золотую → −3 с к времени (может уйти в минус)
	},

	-- Штрафное время вместо штрафных кругов: каждый промах сразу прибавляет секунды
	-- к индивидуальному времени игрока; над ним всплывает «+3 с».
	Penalty = {
		SecondsPerMiss = 3,
		PopupOffsetY = 3.5, -- стад над головой, откуда всплывает «+3 с»
		PopupRise = 3, -- на сколько стад поднимается
		PopupTime = 1.4, -- с, сколько видно
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
		ZoneColumnHeight = 60, -- стад над чекпоинтом/воротами/зоной велопарка, где ещё засчитываем (перепрыгнул — всё равно прошёл)
		RespawnHeight = 3, -- на сколько выше пола чекпоинта ставим игрока
	},
}

return Config
