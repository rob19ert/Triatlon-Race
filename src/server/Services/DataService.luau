--!strict
-- Профиль игрока. Каждый финиш сохраняется атомарно; повтор запроса не начисляет опыт заново.

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Attributes = require(ReplicatedStorage.Shared.Attributes)
local C = require(ReplicatedStorage.Shared.Config).Profile

type Profile = {
	finishes: number,
	xp: number,
	best: number?,
	hits: number,
	shots: number,
	firstFinish: boolean,
	veteran: boolean,
	recent: { string },
}

local studio = RunService:IsStudio()
local store = if studio and not C.UseStudioDataStore
	then nil
	else DataStoreService:GetDataStore(if studio then C.StoreName .. "_Studio" else C.StoreName)
local memory: { [number]: Profile } = {}
local pending = 0
local DataService = {}

local function normalize(raw: any): Profile
	local data = if typeof(raw) == "table" then raw else {}
	return {
		finishes = data.finishes or 0,
		xp = data.xp or 0,
		best = data.best,
		hits = data.hits or 0,
		shots = data.shots or 0,
		firstFinish = data.firstFinish == true,
		veteran = data.veteran == true,
		recent = if typeof(data.recent) == "table" then table.clone(data.recent) else {},
	}
end

local function publish(player: Player, profile: Profile)
	if player.Parent ~= Players then
		return
	end
	local shown = player:GetAttribute(Attributes.ProfileFinishes)
	if typeof(shown) == "number" and shown > profile.finishes then
		return -- чтение профиля могло завершиться после записи финиша
	end
	player:SetAttribute(Attributes.ProfileBest, profile.best)
	player:SetAttribute(Attributes.ProfileXP, profile.xp)
	player:SetAttribute(Attributes.ProfileLevel, math.floor(profile.xp / C.XPPerLevel) + 1)
	player:SetAttribute(Attributes.ProfileAchievement, if profile.veteran then "Ветеран трассы" elseif profile.firstFinish then "Первый финиш" else nil)
	player:SetAttribute(Attributes.ProfileFinishes, profile.finishes)
	player:SetAttribute(Attributes.ProfileLoadFailed, nil)
end

local function request(operation: () -> any): (boolean, any)
	for attempt = 1, C.SaveAttempts do
		local ok, value = pcall(operation)
		if ok then
			return true, value
		end
		if attempt == C.SaveAttempts then
			return false, value
		end
		task.wait(C.RetryDelay * 2 ^ (attempt - 1))
	end
	return false, "no attempts configured"
end

local function load(player: Player)
	local dataStore = store
	if not dataStore then
		publish(player, normalize(memory[player.UserId]))
		return
	end
	local ok, value = request(function()
		return dataStore:GetAsync(tostring(player.UserId))
	end)
	if ok then
		publish(player, normalize(value))
	else
		if player.Parent == Players and player:GetAttribute(Attributes.ProfileFinishes) == nil then
			player:SetAttribute(Attributes.ProfileLoadFailed, true)
		end
		warn("[DataService] Load failed for", player.UserId, value)
	end
end

function DataService.recordFinish(player: Player, seconds: number, hits: number, shots: number)
	local id = HttpService:GenerateGUID(false)
	local userId = player.UserId
	local function apply(raw: any): Profile
		local profile = normalize(raw)
		if table.find(profile.recent, id) then
			return profile
		end
		profile.finishes += 1
		profile.xp += C.FinishXP
		profile.best = math.min(profile.best or seconds, seconds)
		profile.hits += hits
		profile.shots += shots
		profile.firstFinish = true
		profile.veteran = profile.finishes >= C.VeteranFinishes
		table.insert(profile.recent, id)
		if #profile.recent > C.RecentResultLimit then
			table.remove(profile.recent, 1)
		end
		return profile
	end

	local dataStore = store
	if not dataStore then
		local profile = apply(memory[userId])
		memory[userId] = profile
		publish(player, profile)
		return
	end

	pending += 1
	task.spawn(function()
		local ok, value = request(function()
			return dataStore:UpdateAsync(tostring(userId), apply)
		end)
		pending -= 1
		if ok then
			publish(Players:GetPlayerByUserId(userId) or player, normalize(value))
		else
			warn("[DataService] Finish save failed for", userId, value)
		end
	end)
end

function DataService.start()
	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		task.spawn(load, player)
	end
	game:BindToClose(function()
		local deadline = os.clock() + C.ShutdownWait
		while pending > 0 and os.clock() < deadline do
			task.wait()
		end
	end)
end

return DataService
