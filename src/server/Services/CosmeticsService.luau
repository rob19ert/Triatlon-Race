--!strict
local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Config = require(Shared.Config).Cosmetics
local Attributes = require(Shared.Attributes)
local Remotes = require(Shared.Remotes)
local BikeSkins = require(Shared.BikeSkins)
local CosmeticsService = {}
local DataService: any
local RaceManager: any
local AnalyticsTracker: any
local readyAt: { [Player]: number } = {}
local selecting: { [Player]: boolean } = {}

function CosmeticsService.init(services: { [string]: any })
	DataService = services.DataService
	RaceManager = services.RaceManager
	AnalyticsTracker = services.AnalyticsTracker
end

function CosmeticsService.start()
	Remotes.get(Remotes.Names.SelectBikeSkin).OnServerEvent:Connect(function(player: Player, id: unknown)
		if typeof(id) ~= "string" or RaceManager.getState() ~= "Lobby" then
			return
		end
		local now = os.clock()
		if selecting[player] or (readyAt[player] or 0) > now then
			return
		end
		readyAt[player] = now + Config.SelectionCooldown
		local level = player:GetAttribute(Attributes.ProfileLevel)
		if typeof(level) ~= "number" or BikeSkins.effective(player) == id then
			return
		end
		for _, skin in Config.BikeSkins do
			if skin.id == id then
				local owned = player:GetAttribute(Attributes.OwnedBikeSkins)
				local purchased = typeof(owned) == "string" and table.find(string.split(owned, ","), id) ~= nil
				local requiredLevel = if skin.robuxOnly then math.huge else skin.level
				if level < requiredLevel and not purchased then
					return
				end
				selecting[player] = true
				local success = DataService.selectBikeSkin(player, id, requiredLevel)
				selecting[player] = nil
				if success then
					AnalyticsTracker.bikeSelected(player, id)
				end
				if not success and player.Parent == Players then
					Remotes.get(Remotes.Names.Notice):FireClient(player, "Couldn't save your bike choice")
				end
				return
			end
		end
	end)
	MarketplaceService.ProcessReceipt = function(receipt)
		local player = Players:GetPlayerByUserId(receipt.PlayerId)
		if player then
			for _, skin in Config.BikeSkins do
				if skin.productId > 0 and skin.productId == receipt.ProductId then
					if DataService.grantBikeSkin(player, skin.id) then
						AnalyticsTracker.bikePurchased(player, skin.id, receipt.CurrencySpent)
						return Enum.ProductPurchaseDecision.PurchaseGranted
					end
					break
				end
			end
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	Players.PlayerRemoving:Connect(function(player)
		readyAt[player] = nil
		selecting[player] = nil
	end)
end

return CosmeticsService
