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

local raceStateRemote: RemoteEvent
local raceResultsRemote: RemoteEvent
local playerFinishedRemote: RemoteEvent
local standingsRemote: RemoteEvent

-- в Studio — тестовые значения лобби
local MIN_PLAYERS = if RunService:IsStudio() then Config.Race.StudioMinPlayers else Config.Race.MinPlayers
local LOBBY_WAIT = if RunService:IsStudio() then Config.Race.StudioLobbyWaitTime else Config.Race.LobbyWaitTime

local state: RaceState = "Lobby"
local stateEndsAt = 0 -- workspace:GetServerTimeNow()
local raceStartedAt = 0 -- workspace:GetServerTimeNow() для клиентского таймера
local raceStartClock = 0 -- os.clock() для точного серверного времени

local participants: { [Player]: boolean } = {}
local finishers: { ResultEntry } = {}
local winnerFinishClock: number? = nil

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

-- Расставить игроков на стартовой решётке и заморозить (Anchored) до старта.
local function placeOnGrid(players: { Player })
	local track = workspace:WaitForChild(Config.Track.FolderName)
	local grid = track:WaitForChild(Config.Track.StartGridName) :: BasePart
	local spacing = Config.Track.GridSpacing
	local rowSize = Config.Track.GridRowSize

	for i, player in players do
		local root = getRoot(player)
		if root then
			local col = (i - 1) % rowSize
			local row = (i - 1) // rowSize
			local x = (col - (rowSize - 1) / 2) * spacing
			local z = row * spacing
			-- сетка смотрит вдоль -Z (к финишу)
			local pos = grid.Position + Vector3.new(x, 3, z)
			root.Anchored = true
			root.CFrame = CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1))
		end
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

local function onPlayerFinished(player: Player)
	if state ~= "Racing" or not participants[player] then
		return
	end
	local elapsed = os.clock() - raceStartClock
	local entry: ResultEntry = {
		userId = player.UserId,
		name = player.Name,
		place = #finishers + 1,
		time = elapsed,
		dnf = false,
	}
	table.insert(finishers, entry)
	log("%s finished #%d in %.2fs", player.Name, entry.place :: number, elapsed)
	playerFinishedRemote:FireAllClients(entry)

	if not winnerFinishClock then
		winnerFinishClock = os.clock()
		-- клиентам показываем таймер до DNF
		stateEndsAt = now() + Config.Race.DnfAfterWinner
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
				entry = { userId = player.UserId, name = player.Name, place = 0, phase = "Finished", penaltyLeft = 0, time = fin.time },
				finishPlace = fin.place,
				score = 0,
			})
		else
			local phase, score, penaltyLeft = ProgressTracker.getProgress(player)
			table.insert(rows, {
				entry = { userId = player.UserId, name = player.Name, place = 0, phase = phase, penaltyLeft = penaltyLeft },
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
	releaseAll()
	setState("Racing", Config.Race.MaxRaceTime)
	log("GO! %d participant(s)", #list)

	local nextStandingsAt = 0
	while true do
		task.wait(0.1)
		local t = os.clock()
		if t >= nextStandingsAt then
			nextStandingsAt = t + Config.Race.StandingsInterval
			publishStandings()
		end
		if #finishers >= countParticipants() then
			log("All participants finished")
			break
		end
		if winnerFinishClock and t - winnerFinishClock >= Config.Race.DnfAfterWinner then
			log("DNF timeout after winner")
			break
		end
		if t - raceStartClock >= Config.Race.MaxRaceTime then
			log("Max race time reached")
			break
		end
	end
	publishStandings() -- финальный порядок
	ProgressTracker.reset()
	StaminaService.endRace()
end

-- Итоги считаются до сброса стрельбы и штрафов: нужна точность стрельбы.
local function buildResults(): { ResultEntry }
	local results = table.clone(finishers)
	for player in participants do
		if not isFinished(player) then
			table.insert(results, { userId = player.UserId, name = player.Name, dnf = true })
		end
	end
	for _, entry in results do
		local player = Players:GetPlayerByUserId(entry.userId)
		if player then
			entry.hits, entry.shots = ShootingService.getTotals(player)
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
			log("  #%d  %s  %.2fs  shooting %s", entry.place :: number, entry.name, entry.time :: number, accuracy)
		end
	end
	raceResultsRemote:FireAllClients(results)
	setState("Results", Config.Race.ResultsTime)
	task.wait(Config.Race.ResultsTime)

	-- вернуть всех в лобби
	raceStartedAt = 0
	table.clear(participants)
	for _, player in Players:GetPlayers() do
		player:LoadCharacter()
	end
end

local function raceLoop()
	while true do
		runLobby()
		if runCountdown() then
			runRacing()
			runResults()
		end
	end
end

---------------------------------------------------------------- жизненный цикл сервиса

function RaceManager.getState(): RaceState
	return state
end

function RaceManager.isParticipant(player: Player): boolean
	return participants[player] == true
end

function RaceManager.init(services: { [string]: any })
	ProgressTracker = services.ProgressTracker
	StaminaService = services.StaminaService
	ShootingService = services.ShootingService
	PenaltyService = services.PenaltyService
	raceStateRemote = Remotes.get(Remotes.Names.RaceState)
	raceResultsRemote = Remotes.get(Remotes.Names.RaceResults)
	playerFinishedRemote = Remotes.get(Remotes.Names.PlayerFinished)
	standingsRemote = Remotes.get(Remotes.Names.Standings)
end

function RaceManager.start()
	ProgressTracker.Finished:Connect(onPlayerFinished)

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
