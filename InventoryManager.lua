--!strict

local InventoryManager = {}
InventoryManager.__index = InventoryManager

local Players = game:GetService("Players")

--//CONSTRUCTOR

function InventoryManager.new(userId: number)
	if typeof(userId) ~= "number" then
		return
	end

	local self = setmetatable({}, InventoryManager)

	self.UserId = userId
	self.Inventory = {} :: InventoryItems
	
	self.AUTO_SAVING = false
	self.Dirty = false
		
	self:LoadData()
	
	return self
end

--//TYPES

export type InventoryItems = {
	[string]: {
		Amount: number
	}
}

export type InventoryData = {
	Inventory: InventoryItems,
}

--//HELPERS

local function deepCopy(original)
	local copy = {}
	
	for key, value in pairs(original) do
		if typeof(key) == "string" and typeof(value) == "table" then
			copy[key] = deepCopy(value)
		end
	end
	
	return copy
end

local function RightAmount(amount : number)
	amount = (typeof(amount) == "number" and amount > 0) and math.floor(amount) or 1
	amount = math.clamp(amount, 1, 99)
	
	return amount
end

--//DATASTORE

local DataStoreService = game:GetService("DataStoreService")
local DataStore = DataStoreService:GetDataStore("InventoryDataStoreV.001")

local AUTO_SAVE_INTERVAL = 60

function InventoryManager:LoadData()
	local success, data = pcall(function()
		return DataStore:GetAsync(self.UserId)
	end)

	if not success then
		warn("[InventoryManager] Error while loading data")
		return
	end

	self.Inventory = (data and data.Inventory) or {}
	
	print("[InventoryManager] Data loaded successfully")
end

function InventoryManager:SaveData()
	
	local success, err = pcall(function()
		DataStore:UpdateAsync(self.UserId, function(oldData)
			self:ValidateInventory()
			
			local newData = oldData or {} :: InventoryData
			newData.Inventory = self.Inventory
			return newData
		end)
	end)

	if not success then
		warn("[InventoryManager] Error while saving data:", tostring(err))
		return false
	end
	
	print("[InventoryManager] Data saved successfully]")
	
	return true
end

function InventoryManager:AutoSave()
	local Player = Players:GetPlayerByUserId(self.UserId)
	if not Player then return end
		
	task.spawn(function()
		while Player and Player.Parent do
			task.wait(AUTO_SAVE_INTERVAL)
			if self.Dirty then
				
				if self.AUTO_SAVING then continue end
				self.AUTO_SAVING = true

				local succes, err = self:SaveData()
				
				if succes then self.Dirty = false end
				
				self.AUTO_SAVING = false
			end
		end
	end)
end

function InventoryManager:ValidateInventory()
	local Inventory = self.Inventory :: InventoryItems
	
	for itemName, item in pairs(Inventory) do
		
		if not item or typeof(item) ~= "table" then
			warn("[InventoryManager] Invalid item data:", itemName)
			Inventory[itemName] = nil
			
			continue
		end
		
		if not item.Amount or typeof(item.Amount) ~= "number" then
			warn("[InventoryManager] Invalid item amount:", itemName)
			Inventory[itemName] = nil
			
			continue
		end
		
		if item.Amount <= 0 then
			warn("[InventoryManager] Invalid item amount:", itemName)
			Inventory[itemName] = nil
			
			continue
		end
	end
end

--//EVENTS

local RS = game:GetService("ReplicatedStorage")
local InventoryEvents = RS:FindFirstChild("InventoryEvents")

local InventoryUpdated = InventoryEvents:FindFirstChild("InventoryUpdated")
local NotificationEvent = InventoryEvents:FindFirstChild("NotificationEvent")

--//INIT

function InventoryManager:Init()	
	--//REMOTE EVENTS
	local InventoryUpdated = InventoryEvents:FindFirstChild("InventoryUpdated")

	if not InventoryUpdated then
		InventoryUpdated = Instance.new("RemoteEvent")
		InventoryUpdated.Name = "InventoryUpdated"
		InventoryUpdated.Parent = InventoryEvents
	end
	
	local NotificationEvent = InventoryEvents:FindFirstChild("NotificationEvent")
	
	if not NotificationEvent then
		NotificationEvent = Instance.new("RemoteEvent")
		NotificationEvent.Name = "NotificationEvent"
		NotificationEvent.Parent = InventoryEvents
	end
	
	--//AUTO SAVE
	
	self:AutoSave()

end

--//ITEMS

function InventoryManager:HasItem(itemName : string)
	if not itemName or typeof(itemName) ~= "string" then
		return
	end
	
	local Inventory = self.Inventory
	
	local Item = Inventory[itemName]
	if not Item then return end
	
	return Item ~= nil and Item.Amount > 0
end

function InventoryManager:CanAddItem(itemName: string, amount: number)
	if not itemName or typeof(itemName) ~= "string" then
		return
	end
	
	if not amount or typeof(amount) ~= "number" then
		return
	end
	
	amount = RightAmount(amount)
	
	local Inventory = self.Inventory
	local MAX_STACK = 99

	local Item = Inventory[itemName]
	if not Item then return end
	
	if Item.Amount >= MAX_STACK then
		NotificationEvent:FireClient(player, "Max stack reached", "Error")
		return false
	end
	
	if Item.Amount + amount > MAX_STACK then
		NotificationEvent:FireClient(player, "Max stack reached", "Error")
		return false
	end
	
	return true
end

function InventoryManager:AddItem(itemName: string, amount: number)
	if typeof(itemName) ~= "string" then
		warn("[InventoryManager] Invalid item name")
		return
	end

	amount = RightAmount(amount)
	if not self:CanAddItem(itemName, amount) then return end

	local Inventory = self.Inventory
	local item = Inventory[itemName]

	if item then
		item.Amount += amount
	else
		item = {
			Amount = amount
		}
		Inventory[itemName] = item
	end

	local player = Players:GetPlayerByUserId(self.UserId)
	if not player then return end
	
	if not InventoryUpdated or not InventoryUpdated:IsA("RemoteEvent") then return end
	InventoryUpdated:FireClient(player, itemName, item.Amount)
	
	self.Dirty = true
end

function InventoryManager:RemoveItem(itemName: string, amount: number)
	if typeof(itemName) ~= "string" then
		warn("[InventoryManager] Invalid item name")
		return
	end

	amount = RightAmount(amount)

	local Inventory = self.Inventory
	local item = Inventory[itemName]

	if not item then
		return
	end

	item.Amount -= amount

	if item.Amount <= 0 then
		Inventory[itemName] = nil
	end

	local player = Players:GetPlayerByUserId(self.UserId)
	if not player then return end

	if not InventoryUpdated or not InventoryUpdated:IsA("RemoteEvent") then return end
	InventoryUpdated:FireClient(player, itemName, item and item.Amount or 0)
	
	self.Dirty = true
end

--//RETURN

function InventoryManager:ReturnInventory()
	--//COPY INVENTORY

	local Inventory = self.Inventory

	return deepCopy(Inventory)
end

return InventoryManager