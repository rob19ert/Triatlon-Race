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
	revision: number,
	bikeSkin: string,
	ownedBikeSkins: { [string]: boolean },
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
local revisionShown: { [Player]: number } = {}

local function normalize(raw: any): Profile
	local data = if typeof(raw) == "table" then raw else {}
	return {
		revision = data.revision or data.finishes or 0,
		bikeSkin = if typeof(data.bikeSkin) == "string" then data.bikeSkin else "auto",
		ownedBikeSkins = if typeof(data.ownedBikeSkins) == "table" then table.clone(data.ownedBikeSkins) else {},
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
	if profile.revision < (revisionShown[player] or 0) then
		return
	end
	revisionShown[player] = profile.revision
	local owned = {}
	for id, granted in profile.ownedBikeSkins do
		if granted then
			table.insert(owned, id)
		end
	end
	table.sort(owned)
	player:SetAttribute(Attributes.BikeSkin, profile.bikeSkin)
	player:SetAttribute(Attributes.OwnedBikeSkins, table.concat(owned, ","))
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

local function update(player: Player, apply: (any) -> Profile?): boolean
	local userId = player.UserId
	local dataStore = store
	if not dataStore then
		local profile = apply(memory[userId])
		if not profile then
			return false
		end
		memory[userId] = profile
		publish(player, profile)
		return true
	end

	pending += 1
	local ok, value = request(function()
		return dataStore:UpdateAsync(tostring(userId), apply)
	end)
	pending -= 1
	if not ok then
		warn("[DataService] Profile update failed for", userId, value)
	elseif value then
		publish(Players:GetPlayerByUserId(userId) or player, normalize(value))
		return true
	end
	return false
end

function DataService.selectBikeSkin(player: Player, id: string, requiredLevel: number): boolean
	return update(player, function(raw)
		local profile = normalize(raw)
		local level = math.floor(profile.xp / C.XPPerLevel) + 1
		if level < requiredLevel and not profile.ownedBikeSkins[id] then
			return nil
		end
		profile.bikeSkin = id
		profile.revision += 1
		return profile
	end)
end

function DataService.grantBikeSkin(player: Player, id: string): boolean
	return update(player, function(raw)
		local profile = normalize(raw)
		if not profile.ownedBikeSkins[id] then
			profile.ownedBikeSkins[id] = true
			profile.revision += 1
		end
		return profile
	end)
end

function DataService.recordFinish(player: Player, seconds: number, hits: number, shots: number)
	local id = HttpService:GenerateGUID(false)
	local function apply(raw: any): Profile
		local profile = normalize(raw)
		if table.find(profile.recent, id) then
			return profile
		end
		profile.revision += 1
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

	task.spawn(update, player, apply)
end

function DataService.start()
	Players.PlayerAdded:Connect(load)
	Players.PlayerRemoving:Connect(function(player)
		revisionShown[player] = nil
	end)
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
