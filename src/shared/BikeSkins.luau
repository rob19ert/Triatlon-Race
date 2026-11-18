--!strict
-- Who may ride which bike: shared by the shop, the selection remote and the bike mount.
local Attributes = require(script.Parent.Attributes)
local Config = require(script.Parent.Config).Cosmetics

local BikeSkins = {}
BikeSkins.Default = Config.BikeSkins[1].id

function BikeSkins.find(id: unknown): any?
	for _, skin in Config.BikeSkins do
		if skin.id == id then
			return skin
		end
	end
	return nil
end

function BikeSkins.owns(player: Player, id: string): boolean
	local owned = player:GetAttribute(Attributes.OwnedBikeSkins)
	return typeof(owned) == "string" and table.find(string.split(owned, ","), id) ~= nil
end

-- Robux-only bikes open by purchase alone; the rest also open by level.
function BikeSkins.unlocked(player: Player, skin: any): boolean
	local level = player:GetAttribute(Attributes.ProfileLevel)
	return (not skin.robuxOnly and typeof(level) == "number" and level >= skin.level) or BikeSkins.owns(player, skin.id)
end

-- The bike the player actually rides: a saved choice that is no longer allowed falls back to the default.
function BikeSkins.effective(player: Player): string
	local skin = BikeSkins.find(player:GetAttribute(Attributes.BikeSkin))
	if skin and (skin.id == BikeSkins.Default or BikeSkins.unlocked(player, skin)) then
		return skin.id
	end
	return BikeSkins.Default
end

return BikeSkins
