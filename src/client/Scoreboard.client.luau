--!strict
-- Табло на стадионе (детали с тегом Scoreboard, экран — грань Front).
-- Рисует клиент через SurfaceGui в PlayerGui (Adornee = экран) по данным, которые сервер
-- и так рассылает: состояние гонки, таблица позиций, финиши, итоги. Новых remote'ов нет.
--  * лобби — «Следующая гонка», таймер и кто на сервере;
--  * гонка — живые позиции и время гонки;
--  * итоги — места и время;
--  * бегущая строка внизу: финиши, «📸 Фотофиниш!», в паузах — спонсоры.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local Types = require(Shared:WaitForChild("Types"))

local TAG = "Scoreboard"
local PIXELS_PER_STUD = 24
local BIG_BOARD_HEIGHT = 14 -- выше — 6 строк, ниже — 4
local EVENT_SECONDS = 5
local REFRESH = 0.2
local SPONSORS = { "ZOOM COLA", "SPRINTEX", "BULLSEYE", "PULSE+", "TURBO SOCKS", "MEGA MUESLI", "ROBO BIKES" }

local GOLD = Color3.fromRGB(255, 205, 60)
local WHITE = Color3.new(1, 1, 1)
local DIM = Color3.fromRGB(150, 160, 190)
local ACCENT = Color3.fromRGB(255, 120, 60)
local PHOTO = Color3.fromRGB(255, 110, 200)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

---------------------------------------------------------------- данные

local current: Types.RaceStatePayload = { state = "Lobby", endsAt = 0, raceStartedAt = 0 }
local standings: { Types.StandingEntry } = {}
local results: { Types.ResultEntry } = {}
local eventText: string? = nil
local eventColor = WHITE
local eventUntil = 0

local function formatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	return string.format("%d:%05.2f", m, seconds - m * 60)
end

local function phaseText(entry: Types.StandingEntry): (string, Color3)
	if entry.phase == "Finished" then
		return formatTime(entry.time or 0), GOLD
	elseif entry.phase == "Shooting" then
		return "🎯 стрельба", ACCENT
	elseif entry.phase == "Penalty" then
		return string.format("штраф %d", entry.penaltyLeft), Color3.fromRGB(255, 90, 90)
	end
	return "🏃 трасса", DIM
end

local function showEvent(text: string, color: Color3)
	eventText = text
	eventColor = color
	eventUntil = os.clock() + EVENT_SECONDS
end

---------------------------------------------------------------- вёрстка одного табло

type Row = { frame: Frame, place: TextLabel, name: TextLabel, status: TextLabel }
type Board = {
	gui: SurfaceGui,
	title: TextLabel,
	timer: TextLabel,
	rows: { Row },
	ticker: TextLabel,
}

local boards: { [Instance]: Board } = {}

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.FredokaOne
	t.TextScaled = true
	t.TextColor3 = WHITE
	t.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in props do
		(t :: any)[k] = v
	end
	t.Parent = parent
	return t
end

local function buildBoard(screen: BasePart): Board
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Scoreboard_" .. screen:GetFullName()
	gui.Adornee = screen
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = PIXELS_PER_STUD
	gui.LightInfluence = 0
	gui.Brightness = 1.5
	gui.ResetOnSpawn = false

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(15, 18, 30)
	root.BorderSizePixel = 0
	root.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.02, 0)
	pad.PaddingRight = UDim.new(0.02, 0)
	pad.PaddingTop = UDim.new(0.03, 0)
	pad.PaddingBottom = UDim.new(0.03, 0)
	pad.Parent = root

	-- шапка
	local header = Instance.new("Frame")
	header.Size = UDim2.fromScale(1, 0.16)
	header.BackgroundColor3 = Color3.fromRGB(235, 70, 70)
	header.BorderSizePixel = 0
	header.Parent = root
	Instance.new("UICorner", header).CornerRadius = UDim.new(0.25, 0)
	local title = label(header, { Position = UDim2.fromScale(0.03, 0.1), Size = UDim2.fromScale(0.65, 0.8) })
	local timer = label(header, {
		Position = UDim2.fromScale(0.68, 0.1),
		Size = UDim2.fromScale(0.29, 0.8),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

	-- строки
	local rowCount = if screen.Size.Y >= BIG_BOARD_HEIGHT then 6 else 4
	local rowsTop, rowsHeight = 0.19, 0.64
	local rows: { Row } = {}
	for i = 1, rowCount do
		local frame = Instance.new("Frame")
		frame.Position = UDim2.fromScale(0, rowsTop + (i - 1) * rowsHeight / rowCount)
		frame.Size = UDim2.fromScale(1, rowsHeight / rowCount * 0.88)
		frame.BackgroundColor3 = Color3.fromRGB(35, 40, 65)
		frame.BackgroundTransparency = if i % 2 == 0 then 0.4 else 0.15
		frame.BorderSizePixel = 0
		frame.Parent = root
		Instance.new("UICorner", frame).CornerRadius = UDim.new(0.2, 0)
		rows[i] = {
			frame = frame,
			place = label(frame, { Position = UDim2.fromScale(0.02, 0.1), Size = UDim2.fromScale(0.08, 0.8), TextXAlignment = Enum.TextXAlignment.Center }),
			name = label(frame, { Position = UDim2.fromScale(0.12, 0.1), Size = UDim2.fromScale(0.5, 0.8) }),
			status = label(frame, { Position = UDim2.fromScale(0.62, 0.1), Size = UDim2.fromScale(0.36, 0.8), TextXAlignment = Enum.TextXAlignment.Right }),
		}
	end

	-- бегущая строка
	local tickerBar = Instance.new("Frame")
	tickerBar.Position = UDim2.fromScale(0, 0.86)
	tickerBar.Size = UDim2.fromScale(1, 0.14)
	tickerBar.BackgroundColor3 = Color3.fromRGB(40, 110, 230)
	tickerBar.BorderSizePixel = 0
	tickerBar.Parent = root
	Instance.new("UICorner", tickerBar).CornerRadius = UDim.new(0.25, 0)
	local ticker = label(tickerBar, {
		Position = UDim2.fromScale(0.02, 0.1),
		Size = UDim2.fromScale(0.96, 0.8),
		TextXAlignment = Enum.TextXAlignment.Center,
	})

	gui.Parent = playerGui
	return { gui = gui, title = title, timer = timer, rows = rows, ticker = ticker }
end

local function setRow(row: Row, place: string, name: string, status: string, statusColor: Color3, highlight: boolean)
	row.frame.Visible = true
	row.place.Text = place
	row.place.TextColor3 = if highlight then GOLD else WHITE
	row.name.Text = name
	row.name.TextColor3 = if highlight then GOLD else WHITE
	row.status.Text = status
	row.status.TextColor3 = statusColor
end

---------------------------------------------------------------- отрисовка

local function remaining(): number
	return if current.endsAt > 0 then math.max(0, current.endsAt - workspace:GetServerTimeNow()) else 0
end

local function renderBoard(board: Board)
	local s = current.state
	for _, row in board.rows do
		row.frame.Visible = false
	end

	if s == "Racing" then
		board.title.Text = "🏁 LIVE • ГОНКА"
		board.timer.Text = formatTime(workspace:GetServerTimeNow() - current.raceStartedAt)
		for i, entry in standings do
			local row = board.rows[i]
			if not row then
				break
			end
			local status, color = phaseText(entry)
			setRow(row, tostring(entry.place), entry.name, status, color, entry.place == 1)
		end
	elseif s == "Results" then
		board.title.Text = "🏆 ИТОГИ"
		board.timer.Text = ""
		for i, entry in results do
			local row = board.rows[i]
			if not row then
				break
			end
			if entry.dnf then
				setRow(row, "—", entry.name, "DNF", DIM, false)
			else
				local photo = if entry.photoFinish then "📸 " else ""
				setRow(row, tostring(entry.place), entry.name, photo .. formatTime(entry.time or 0), GOLD, entry.place == 1)
			end
		end
	else
		board.title.Text = if s == "Countdown" then "СТАРТ!" else "СЛЕДУЮЩАЯ ГОНКА"
		board.timer.Text = if current.endsAt > 0 then string.format("%d", math.ceil(remaining())) else "…"
		for i, p in Players:GetPlayers() do
			local row = board.rows[i]
			if not row then
				break
			end
			setRow(row, "•", p.DisplayName, "на старте", DIM, false)
		end
	end

	if eventText and os.clock() < eventUntil then
		board.ticker.Text = eventText
		board.ticker.TextColor3 = eventColor
	else
		local i = math.floor(os.clock() / 4) % #SPONSORS + 1
		board.ticker.Text = "★ " .. SPONSORS[i] .. " ★"
		board.ticker.TextColor3 = WHITE
	end
end

---------------------------------------------------------------- события

Remotes.get(Remotes.Names.RaceState).OnClientEvent:Connect(function(payload: Types.RaceStatePayload)
	if payload.state == "Racing" and current.state ~= "Racing" then
		showEvent("🔫 СТАРТ ДАН!", GOLD)
	end
	current = payload
	if payload.state ~= "Racing" then
		standings = {}
	end
end)

Remotes.get(Remotes.Names.Standings).OnClientEvent:Connect(function(list: { Types.StandingEntry })
	standings = list
end)

Remotes.get(Remotes.Names.PlayerFinished).OnClientEvent:Connect(function(entry: Types.ResultEntry)
	if entry.photoFinish then
		showEvent("📸 ФОТОФИНИШ!", PHOTO)
	else
		showEvent(string.format("🏁 %s — %d место • %s", entry.name, entry.place or 0, formatTime(entry.time or 0)), GOLD)
	end
end)

Remotes.get(Remotes.Names.RaceResults).OnClientEvent:Connect(function(list: { Types.ResultEntry })
	results = list
	local winner = list[1]
	if winner and not winner.dnf then
		showEvent("🏆 ПОБЕДИТЕЛЬ: " .. winner.name, GOLD)
	end
end)

---------------------------------------------------------------- табло в мире (с учётом стриминга)

local function addScreen(screen: Instance)
	if boards[screen] or not screen:IsA("BasePart") then
		return
	end
	boards[screen] = buildBoard(screen)
end

local function removeScreen(screen: Instance)
	local board = boards[screen]
	if board then
		board.gui:Destroy()
		boards[screen] = nil
	end
end

for _, screen in CollectionService:GetTagged(TAG) do
	addScreen(screen)
end
CollectionService:GetInstanceAddedSignal(TAG):Connect(addScreen)
CollectionService:GetInstanceRemovedSignal(TAG):Connect(removeScreen)

while true do
	for _, board in boards do
		renderBoard(board)
	end
	task.wait(REFRESH)
end
