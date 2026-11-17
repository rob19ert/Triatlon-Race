--!strict
-- Защита от сбивания (бонусы из боксов), одна для всех источников: маятники, поезда, овцы, бочки, толчки.
--  * 👻 Призрак (атрибут GhostUntil) — всё проходит сквозь, ничего не тратится;
--  * 🛡 Щит (атрибут ShieldUntil) — гасит одно попадание и пропадает.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Attributes = require(ReplicatedStorage.Shared.Attributes)

local Protection = {}

local function active(player: Player, name: string): boolean
	local v = player:GetAttribute(name)
	return typeof(v) == "number" and v > workspace:GetServerTimeNow()
end

function Protection.isGhost(player: Player): boolean
	return active(player, Attributes.GhostUntil)
end

-- Попадание по игроку: true — защита сработала, не сбивать.
function Protection.absorb(player: Player): boolean
	if Protection.isGhost(player) then
		return true
	end
	if active(player, Attributes.ShieldUntil) then
		player:SetAttribute(Attributes.ShieldUntil, nil) -- клиенты видят пропажу щита и рисуют вспышку
		print(string.format("[Protection] %s shield absorbed a hit", player.Name))
		return true
	end
	return false
end

return Protection
