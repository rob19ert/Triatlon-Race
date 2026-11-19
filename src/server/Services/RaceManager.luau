--!strict
-- Состояния гонки: Lobby -> Countdown -> Racing -> Results -> Lobby.
-- Время гонки считает только сервер (os.clock от момента старта).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

type RaceState = Types.RaceState
type ResultEntry = Types.ResultEntry

local RaceManager = {}

-- задаются в init
local ProgressTracker: any
local StaminaService: any
local ShootingService: any
local PenaltyService: any
local PushService: any
local PodiumService: any
local SpectatorService: any
local ModifierService: any
local DataService: any
local AnalyticsTracker: any
local BotService: any

local raceStateRemote: RemoteEvent
local raceResultsRemote: RemoteEvent
local playerFinishedRemote: RemoteEvent
local standingsRemote: RemoteEvent
local noticeRemote: RemoteEvent

-- в Studio — тестовые значения лобби
local MIN_PLAYERS = Config.Race.MinPlayers
local LOBBY_WAIT = if RunService:IsStudio() then Config.Race.StudioLobbyWaitTime else Config.Race.LobbyWaitTime
local DNF_AFTER_WINNER = if RunService:IsStudio() then Config.Race.StudioDnfAfterWinner else Config.Race.DnfAfterWinner

local state: RaceState = "Lobby"
local stateEndsAt = 0 -- workspace:GetServerTimeNow()
local raceStartedAt = 0 -- workspace:GetServerTimeNow() для клиентского таймера
local raceStartClock = 0 -- os.clock() для точного серверного времени

local participants: { [Player]: boolean } = {}
local finishers: { ResultEntry } = {}
local winnerFinishClock: number? = nil
local places: { [Player]: number } = {} -- место в последней таблице (для шансов в боксах)
local placeCount = 0

local function log(fmt: string, ...: any)
	print("[RaceManager] " .. string.format(fmt, ...))
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function statePayload(): Types.RaceStatePayload
	return { state = state, endsAt = stateEndsAt, raceStartedAt = raceStartedAt }
end

local function setState(newState: RaceState, duration: number?)
	state = newState
	stateEndsAt = if duration then now() + duration else 0
	log("State -> %s%s", newState, if duration then string.format(" (%ds)", duration) else "")
	raceStateRemote:FireAllClients(statePayload())
end

local function countParticipants(): number
	local n = 0
	for _ in participants do
		n += 1
	end
	return n
end

local function getRoot(player: Player): BasePart?
	local character = player.Character
	return if character then character:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

-- Место i на стартовой решётке (сетка смотрит вдоль -Z, к финишу).
local function gridCFrame(i: number): CFrame
	local track = workspace:WaitForChild(Config.Track.FolderName)
	local grid = track:WaitForChild(Config.Track.StartGridName) :: BasePart
	local spacing = Config.Track.GridSpacing
	local rowSize = Config.Track.GridRowSize
	local col = (i - 1) % rowSize
	local row = (i - 1) // rowSize
	local x = (col - (rowSize - 1) / 2) * spacing
	local z = row * spacing
	local pos = grid.Position + Vector3.new(x, 3, z)
	return CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
end

-- Расставить игроков на стартовой решётке и заморозить (Anchored) до старта.
local function placeOnGrid(players: { Player })
	for i, player in players do
		local root = getRoot(player)
		if root then
			root.Anchored = true
			root.CFrame = gridCFrame(i)
		end
	end
end

-- Мало людей — добиваем ботами до Bots.FillTo (места на решётке — после людей).
local function spawnBots(humans: number)
	local B = Config.Bots
	if not B.Enabled then
		return
	end
	local count = math.min(B.FillTo, Config.Race.MaxPlayers) - humans
	if count <= 0 then
		return
	end
	local lineup = table.clone(B.Lineup)
	local rng = Random.new()
	for i = #lineup, 2, -1 do
		local j = rng:NextInteger(1, i)
		lineup[i], lineup[j] = lineup[j], lineup[i]
	end
	for k = 1, count do
		local slot = humans + k
		BotService.spawn(slot, lineup[(k - 1) % #lineup + 1], gridCFrame(slot))
	end
end

local function releaseAll()
	for player in participants do
		local root = getRoot(player)
		if root then
			root.Anchored = false
		end
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Config.Movement.WalkSpeed
		end
	end
end

-- Вставить финишера по точному времени (двое в одном кадре встанут в правильном порядке),
-- пересчитать места и отметить фотофиниш с соседями.
local function insertFinisher(entry: ResultEntry): boolean
	local index = #finishers + 1
	for i, other in finishers do
		if (entry.time :: number) < (other.time :: number) then
			index = i
			break
		end
	end
	table.insert(finishers, index, entry)
	for i, e in finishers do
		e.place = i
	end
	local photo = false
	for _, neighbor in { finishers[index - 1], finishers[index + 1] } do
		if neighbor and math.abs((neighbor.time :: number) - (entry.time :: number)) < Config.Race.PhotoFinishGap then
			neighbor.photoFinish = true
			entry.photoFinish = true
			photo = true
		end
	end
	return photo
end

local function onPlayerFinished(player: Player, finishClock: number)
	if state ~= "Racing" or not participants[player] then
		return
	end
	-- итоговое время = время до финишной линии + штраф за промахи
	local penalty = PenaltyService.getSeconds(player)
	local elapsed = finishClock - raceStartClock + penalty
	local entry: ResultEntry = {
		userId = player.UserId,
		name = player.Name,
		place = 0,
		time = elapsed,
		penalty = penalty,
		dnf = false,
	}
	local photo = insertFinisher(entry)
	local hits, shots = ShootingService.getTotals(player)
	DataService.recordFinish(player, elapsed, hits, shots)
	AnalyticsTracker.finished(player, entry.place :: number, elapsed)
	log("%s finished #%d in %.3fs (penalty %ds)%s", player.Name, entry.place :: number, elapsed, penalty, if photo then " (PHOTO FINISH)" else "")
	playerFinishedRemote:FireAllClients(entry)
	if photo then
		noticeRemote:FireAllClients("📸 Фотофиниш!")
	end

	if not winnerFinishClock then
		winnerFinishClock = os.clock()
		-- клиентам показываем таймер до DNF
		stateEndsAt = now() + DNF_AFTER_WINNER
		raceStateRemote:FireAllClients(statePayload())
	end
end

local function onBotFinished(bot: any, finishClock: number)
	if state ~= "Racing" then
		return
	end
	local elapsed = finishClock - raceStartClock + bot.penalty
	local entry: ResultEntry = {
		userId = bot.id,
		name = bot.name,
		place = 0,
		time = elapsed,
		penalty = bot.penalty,
		dnf = false,
	}
	local photo = insertFinisher(entry)
	log("%s (bot) finished #%d in %.3fs (penalty %ds)%s", bot.name, entry.place :: number, elapsed, bot.penalty, if photo then " (PHOTO FINISH)" else "")
	playerFinishedRemote:FireAllClients(entry)
	if photo then
		noticeRemote:FireAllClients("📸 Фотофиниш!")
	end
	if not winnerFinishClock then
		winnerFinishClock = os.clock()
		stateEndsAt = now() + DNF_AFTER_WINNER
		raceStateRemote:FireAllClients(statePayload())
	end
end

local function isFinished(player: Player): boolean
	for _, entry in finishers do
		if entry.userId == player.UserId then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- таблица позиций

local function finishEntry(player: Player): ResultEntry?
	for _, entry in finishers do
		if entry.userId == player.UserId then
			return entry
		end
	end
	return nil
end

-- Порядок: финишировавшие по месту, потом остальные по прогрессу на трассе.
local function computeStandings(): { Types.StandingEntry }
	type Row = { entry: Types.StandingEntry, finishPlace: number?, score: number }
	local rows: { Row } = {}
	for player in participants do
		local fin = finishEntry(player)
		if fin then
			table.insert(rows, {
				entry = { userId = player.UserId, name = player.Name, place = 0, phase = "Finished", penalty = fin.penalty or 0, time = fin.time },
				finishPlace = fin.place,
				score = 0,
			})
		else
			local phase, score = ProgressTracker.getProgress(player)
			table.insert(rows, {
				entry = { userId = player.UserId, name = player.Name, place = 0, phase = phase, penalty = PenaltyService.getSeconds(player) },
				finishPlace = nil,
				score = score,
			})
		end
	end
	for _, bot in BotService.getBots() do
		local fin: ResultEntry? = nil
		for _, entry in finishers do
			if entry.userId == bot.id then
				fin = entry
			end
		end
		if fin then
			table.insert(rows, {
				entry = { userId = bot.id, name = bot.name, place = 0, phase = "Finished", penalty = fin.penalty or 0, time = fin.time },
				finishPlace = fin.place,
				score = 0,
			})
		else
			local phase, score = BotService.getProgress(bot)
			table.insert(rows, {
				entry = { userId = bot.id, name = bot.name, place = 0, phase = phase, penalty = bot.penalty },
				finishPlace = nil,
				score = score,
			})
		end
	end
	table.sort(rows, function(a, b)
		if a.finishPlace and b.finishPlace then
			return a.finishPlace < b.finishPlace
		elseif a.finishPlace or b.finishPlace then
			return a.finishPlace ~= nil
		end
		return a.score > b.score
	end)
	local standings: { Types.StandingEntry } = {}
	for i, row in rows do
		row.entry.place = i
		standings[i] = row.entry
	end
	return standings
end

local function publishStandings()
	local standings = computeStandings()
	standingsRemote:FireAllClients(standings)

	-- догонялка: последняя треть ещё бегущих
	local n = #standings
	table.clear(places)
	placeCount = n
	for _, entry in standings do
		local player = Players:GetPlayerByUserId(entry.userId)
		if player then
			places[player] = entry.place
		end
	end
	local slowFrom = n - math.ceil(n * Config.Stamina.CatchUpShare) + 1
	for _, entry in standings do
		local player = Players:GetPlayerByUserId(entry.userId)
		if player then
			local catchUp = n >= Config.Stamina.CatchUpMinRacers and entry.place >= slowFrom and entry.phase ~= "Finished"
			StaminaService.setCatchUp(player, catchUp)
		end
	end
end

---------------------------------------------------------------- этапы

-- Игроки, у которых уже загружен персонаж (только их можно поставить на старт).
-- Персонаж может грузиться дольше таймера лобби (медленная выдача ассетов), поэтому
-- считаем готовых, а не всех подключившихся.
local function countReady(): number
	local n = 0
	for _, player in Players:GetPlayers() do
		if getRoot(player) then
			n += 1
		end
	end
	return n
end

local function runLobby()
	while true do
		setState("Lobby")
		while countReady() < MIN_PLAYERS do
			task.wait(0.5)
		end

		setState("Lobby", LOBBY_WAIT)
		ModifierService.openVote()
		local deadline = os.clock() + LOBBY_WAIT
		local enough = true
		while os.clock() < deadline do
			task.wait(0.25)
			-- тут считаем подключённых: респаун одного игрока не должен сбрасывать таймер всем
			local count = #Players:GetPlayers()
			if count < MIN_PLAYERS then
				enough = false
				break
			end
			if count >= Config.Race.MaxPlayers then
				log("Lobby full — starting now")
				break
			end
		end
		if enough then
			return
		end
		ModifierService.clear() -- лобби сорвалось: голосование заново
	end
end

-- Возвращает false, если некого запускать.
local function runCountdown(): boolean
	table.clear(participants)
	table.clear(finishers)
	winnerFinishClock = nil

	local list: { Player } = {}
	for _, player in Players:GetPlayers() do
		if #list >= Config.Race.MaxPlayers then
			break
		end
		if getRoot(player) then
			participants[player] = true
			table.insert(list, player)
		end
	end
	if #list == 0 then
		log("No loaded characters at start — back to lobby")
		return false
	end

	placeOnGrid(list)
	spawnBots(#list)
	setState("Countdown", Config.Race.CountdownTime)
	for i = Config.Race.CountdownTime, 1, -1 do
		log("%d...", i)
		task.wait(1)
	end
	return true
end

local function runRacing()
	raceStartClock = os.clock()
	raceStartedAt = now()

	local list: { Player } = {}
	for player in participants do
		table.insert(list, player)
	end
	ProgressTracker.beginTracking(list)
	StaminaService.beginRace(list)
	ShootingService.beginRace(list)
	PenaltyService.beginRace(list)
	PushService.beginRace(list)
	releaseAll()
	BotService.go(raceStartClock)
	setState("Racing", Config.Race.MaxRaceTime)
	log("GO! %d participant(s)", #list)
	AnalyticsTracker.raceStarted(list)

	local nextStandingsAt = 0
	local humansDoneAt: number? = nil
	while true do
		task.wait(0.1)
		local t = os.clock()
		if t >= nextStandingsAt then
			nextStandingsAt = t + Config.Race.StandingsInterval
			publishStandings()
		end
		-- конец: все финишировали; люди финишировали — ботов ждём не дольше Bots.WaitAfterHumans
		local humansLeft = 0
		for player in participants do
			if not isFinished(player) then
				humansLeft += 1
			end
		end
		local botsLeft = 0
		for _, bot in BotService.getBots() do
			if bot.state ~= "Finished" then
				botsLeft += 1
			end
		end
		if humansLeft == 0 and botsLeft == 0 then
			log("All participants finished")
			break
		end
		if humansLeft == 0 then
			if countParticipants() == 0 then
				log("No players left")
				break
			end
			humansDoneAt = humansDoneAt or t
			if t - (humansDoneAt :: number) >= Config.Bots.WaitAfterHumans then
				log("All players finished — bots out of time")
				break
			end
		end
		if winnerFinishClock and t - winnerFinishClock >= DNF_AFTER_WINNER then
			log("DNF timeout after winner")
			break
		end
		if t - raceStartClock >= Config.Race.MaxRaceTime then
			log("Max race time reached")
			break
		end
	end
	publishStandings() -- финальный порядок
	BotService.stopAll()
	PushService.endRace()
	SpectatorService.reset()
	ProgressTracker.reset()
	StaminaService.endRace()
end

-- Итоги считаются до сброса стрельбы и штрафов: нужна точность стрельбы.
local function buildResults(): { ResultEntry }
	local results = table.clone(finishers)
	for player in participants do
		if not isFinished(player) then
			table.insert(results, { userId = player.UserId, name = player.Name, dnf = true, penalty = PenaltyService.getSeconds(player) })
			AnalyticsTracker.dnf(player)
		end
	end
	for _, bot in BotService.getBots() do
		local finished = false
		for _, entry in finishers do
			if entry.userId == bot.id then
				finished = true
			end
		end
		if not finished then
			table.insert(results, { userId = bot.id, name = bot.name, dnf = true, penalty = bot.penalty })
		end
	end
	for _, entry in results do
		local player = Players:GetPlayerByUserId(entry.userId)
		local bot = if player then nil else BotService.getById(entry.userId)
		if player then
			entry.hits, entry.shots = ShootingService.getTotals(player)
		elseif bot then
			entry.hits, entry.shots = bot.hits, bot.shots
		end
	end
	ShootingService.endRace()
	PenaltyService.endRace()
	return results
end

local function runResults()
	local results = buildResults()
	log("===== RESULTS =====")
	for _, entry in results do
		local accuracy = string.format("%d/%d", entry.hits or 0, entry.shots or 0)
		if entry.dnf then
			log("  DNF  %s  shooting %s", entry.name, accuracy)
		else
			log("  #%d  %s  %.3fs  shooting %s%s", entry.place :: number, entry.name, entry.time :: number, accuracy, if entry.photoFinish then "  PHOTO" else "")
		end
	end
	PodiumService.show(results)
	raceResultsRemote:FireAllClients(results)
	local duration = Config.Race.PodiumTime + Config.Race.ResultsTime
	setState("Results", duration)
	task.wait(duration)

	-- вернуть всех в лобби
	ModifierService.clear()
	BotService.clear()
	raceStartedAt = 0
	table.clear(participants)
	for _, player in Players:GetPlayers() do
		player:LoadCharacter()
	end
end

local function raceLoop()
	while true do
		runLobby()
		ModifierService.decide()
		if runCountdown() then
			runRacing()
			runResults()
		else
			ModifierService.clear()
			BotService.clear()
		end
	end
end

---------------------------------------------------------------- жизненный цикл сервиса

function RaceManager.getState(): RaceState
	return state
end

-- Место игрока в гонке и сколько всего в таблице (nil — нет в таблице).
function RaceManager.getPlace(player: Player): (number?, number)
	return places[player], placeCount
end

function RaceManager.isParticipant(player: Player): boolean
	return participants[player] == true
end

function RaceManager.init(services: { [string]: any })
	ProgressTracker = services.ProgressTracker
	StaminaService = services.StaminaService
	ShootingService = services.ShootingService
	PenaltyService = services.PenaltyService
	PushService = services.PushService
	PodiumService = services.PodiumService
	SpectatorService = services.SpectatorService
	ModifierService = services.ModifierService
	DataService = services.DataService
	AnalyticsTracker = services.AnalyticsTracker
	BotService = services.BotService
	raceStateRemote = Remotes.get(Remotes.Names.RaceState)
	raceResultsRemote = Remotes.get(Remotes.Names.RaceResults)
	playerFinishedRemote = Remotes.get(Remotes.Names.PlayerFinished)
	standingsRemote = Remotes.get(Remotes.Names.Standings)
	noticeRemote = Remotes.get(Remotes.Names.Notice)
end

function RaceManager.start()
	ProgressTracker.Finished:Connect(onPlayerFinished)
	BotService.Finished:Connect(onBotFinished)

	-- зашедшим позже сразу шлём текущее состояние
	Players.PlayerAdded:Connect(function(player)
		raceStateRemote:FireClient(player, statePayload())
	end)
	Players.PlayerRemoving:Connect(function(player)
		participants[player] = nil
		ProgressTracker.stopTracking(player)
	end)

	task.spawn(raceLoop)
end

return RaceManager
