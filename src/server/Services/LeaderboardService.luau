--!strict
-- Рекорды недели: лучшее итоговое время каждого игрока за неделю (пн–вс, UTC) — OrderedDataStore
-- с номером недели в имени (новая неделя — новое хранилище, табло само обнуляется).
-- Топ — на табло Workspace/<Leaderboard.BoardName>/Screen (SurfaceGui собирает сервер), обновление раз в RefreshSeconds
-- и сразу после нового рекорда. Боты в рекорды не попадают.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

local L = Config.Leaderboard
local WEEK = 7 * 86400
local MONDAY_OFFSET = 4 * 86400 -- 1 января 1970 — четверг; недели считаем с понедельника

local LeaderboardService = {}

local names: { [number]: string } = {}
local rows: { TextLabel } = {}
local refreshQueued = false

local function weekNumber(): number
	return (os.time() - MONDAY_OFFSET) // WEEK
end

local function storeForWeek(): OrderedDataStore?
	local studio = RunService:IsStudio()
	if studio and not Config.Profile.UseStudioDataStore then
		return nil
	end
	local name = string.format("%s_w%d%s", L.StoreName, weekNumber(), if studio then "_Studio" else "")
	local ok, store = pcall(DataStoreService.GetOrderedDataStore, DataStoreService, name)
	return if ok then store else nil
end

local function nameOf(userId: number): string
	local cached = names[userId]
	if cached then
		return cached
	end
	local online = Players:GetPlayerByUserId(userId)
	if online then
		names[userId] = online.DisplayName
		return online.DisplayName
	end
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	names[userId] = if ok and typeof(name) == "string" then name else "Player"
	return names[userId]
end

local function formatTime(seconds: number): string
	local m = math.floor(seconds / 60)
	return string.format("%d:%05.2f", m, seconds - m * 60)
end

-- Табло: SurfaceGui на Screen (строим один раз на сервере — реплицируется всем).
local function buildBoard()
	local board = workspace:FindFirstChild(L.BoardName)
	local screen = board and board:FindFirstChild("Screen")
	if not screen or not screen:IsA("BasePart") then
		warn("[LeaderboardService] no Workspace/" .. L.BoardName .. "/Screen — board disabled")
		return
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Board"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, 16)
	pad.Parent = gui
	local head = Instance.new("TextLabel")
	head.Name = "Title"
	head.LayoutOrder = 0
	head.Size = UDim2.new(0.94, 0, 0, 56)
	head.BackgroundTransparency = 1
	head.Font = Enum.Font.GothamBlack
	head.TextScaled = true
	head.TextColor3 = Color3.fromRGB(255, 205, 70)
	head.Text = L.Title
	head.Parent = gui
	for i = 1, L.Size do
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(0.9, 0, 0, 30)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.GothamBold
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i == 1
			then Color3.fromRGB(255, 215, 80)
			elseif i == 2 then Color3.fromRGB(215, 225, 240)
			elseif i == 3 then Color3.fromRGB(235, 165, 110)
			else Color3.fromRGB(235, 240, 250)
		row.Text = ""
		row.Parent = gui
		rows[i] = row
	end
	gui.Parent = screen
end

local function refresh()
	if #rows == 0 then
		return
	end
	local store = storeForWeek()
	if not store then
		rows[1].Text = L.Empty
		return
	end
	local ok, pages = pcall(store.GetSortedAsync, store, true, L.Size)
	if not ok then
		warn("[LeaderboardService] read failed", pages)
		return
	end
	local entries = (pages :: DataStorePages):GetCurrentPage()
	for i = 1, L.Size do
		local entry = entries[i]
		if entry then
			local userId = tonumber(entry.key) or 0
			rows[i].Text = string.format("%d.  %s   %s", i, nameOf(userId), formatTime(entry.value / 1000))
		else
			rows[i].Text = if i == 1 then L.Empty else ""
		end
	end
end

local function queueRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	task.delay(2, function()
		refreshQueued = false
		refresh()
	end)
end

-- Финиш игрока: если это его лучшее время за неделю — записать (в мс; меньше — лучше).
function LeaderboardService.record(player: Player, seconds: number)
	local store = storeForWeek()
	if not store then
		return
	end
	local ms = math.max(1, math.floor(seconds * 1000 + 0.5))
	task.spawn(function()
		local improved = false
		local ok, err = pcall(store.UpdateAsync, store, tostring(player.UserId), function(old: number?)
			if old and old <= ms then
				improved = false
				return nil
			end
			improved = true
			return ms
		end)
		if not ok then
			warn("[LeaderboardService] write failed", err)
		elseif improved then
			print(string.format("[LeaderboardService] %s weekly best %s", player.Name, formatTime(seconds)))
			queueRefresh()
		end
	end)
end

function LeaderboardService.start()
	buildBoard()
	task.spawn(function()
		while true do
			refresh()
			task.wait(L.RefreshSeconds)
		end
	end)
end

return LeaderboardService
