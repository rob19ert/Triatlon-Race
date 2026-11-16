--!strict
-- Модификатор заезда: общее чтение состояния для сервера и клиентов.
-- Сервер (ModifierService) пишет атрибуты workspace, все остальные только читают.
--   ModifierOptions — "Fog,Night,LowGravity": карточки открытого голосования ("" / nil — голосования нет)
--   ModifierVotes   — "2,0,1": голоса по карточкам
--   Modifier        — id активного модификатора (nil — обычная гонка)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local Modifier = {}

Modifier.OptionsAttr = "ModifierOptions"
Modifier.VotesAttr = "ModifierVotes"
Modifier.ActiveAttr = "Modifier"

local function split(s: unknown): { string }
	local list = {}
	if typeof(s) == "string" and s ~= "" then
		for part in string.gmatch(s, "[^,]+") do
			table.insert(list, part)
		end
	end
	return list
end

-- Карточки открытого голосования (пусто — голосования нет).
function Modifier.options(): { string }
	return split(workspace:GetAttribute(Modifier.OptionsAttr))
end

function Modifier.votes(): { number }
	local list = {}
	for _, v in split(workspace:GetAttribute(Modifier.VotesAttr)) do
		table.insert(list, tonumber(v) or 0)
	end
	return list
end

-- id активного модификатора или nil.
function Modifier.active(): string?
	local id = workspace:GetAttribute(Modifier.ActiveAttr)
	return if typeof(id) == "string" and id ~= "" then id else nil
end

function Modifier.def(id: string?): any
	return if id then (Config.Modifiers.Defs :: any)[id] else nil
end

return Modifier
