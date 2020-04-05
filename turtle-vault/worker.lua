local Worker = {}

function Worker.new(profile, turtleUtil, updateIndex)
	local self = setmetatable(Worker, {})

	self.serverId = profile.serverId
	self.inventory = {}
	self.turtleUtil = turtleUtil
	self.index = {}
	self.updateIndex = updateIndex
	self.roomSize = profile.roomSize

	for i,v in pairs(profile.index) do
		self.index[i] = v
	end

	self:updateInventory()

	return self
end

function Worker:compare(a, b)
	local curY = self.turtleUtil:getCurPos().y + 1
	if a.chest.y == curY and b.chest.y ~= curY then
		return true
	elseif a.chest.y ~= curY and b.chest.y == curY then
		return false
	end

	if a.chest.y == b.chest.y and a.chest.x == b.chest.x then
		return a.chest.z < b.chest.z
	elseif a.chest.y == b.chest.y then
		return a.chest.x < b.chest.x
	end

	return a.chest.y < b.chest.y
end

function Worker:allocateNewChest()
	local potentials = {}
	local roomSize = self.roomSize
	for x = 2, roomSize.x - 1, 3 do
		potentials[x] = {}
		for y = 2, roomSize.y - 1, 2 do
			potentials[x][y] = {}
			for z = 1, roomSize.z - 1, 2 do
				potentials[x][y][z] = true
			end
		end
	end

	for i,v in pairs(self.index) do
		potentials[v.chest.x][v.chest.y][v.chest.z] = false

		if v.pastChests ~= nil then
			for n, pastChest in pairs(v.pastChests) do
				potentials[pastChest.chest.x][pastChest.chest.y][pastChest.chest.z] = false
			end
		end
	end

	for x = 2, roomSize.x - 1, 3 do
		for y = 2, roomSize.y - 1, 2 do
			for z = 1, roomSize.z - 1, 2 do
				if potentials[x][y][z] then
					return {
						x = x,
						y = y,
						z = z,
					}
				end
			end
		end
	end

	return nil
end

function Worker:doIndex(items)
	for i,v in pairs(items) do
		if self.index[i] == nil then
			local chest = self:allocateNewChest()
			if chest ~= nil then
				self.index[i] = {
					chest = chest,
					count = 0,
					isChestFull = false,
				}
			end
		end

		if self.index[i] ~= nil then
			self.index[i].count = self.index[i].count + v.diff
		end
	end

	-- Check for any entries with a count of 0 or below and free up those chests
	local indexEntriesToRemove = {}
	for i,v in pairs(self.index) do
		if v.count <= 0 then
			table.insert(indexEntriesToRemove, i)
		elseif (v.currentChestCount or v.count) <= 0 then
			if v.pastChests ~= nil and #v.pastChests > 0 then
				nextChest = v.pastChests[#v.pastChests]
				table.remove(v.pastChests, #v.pastChests)

				v.chest = nextChest.chest
				v.currentChestCount = nextChest.count
			else
				table.insert(indexEntriesToRemove, i)
			end
		end
	end

	for i,v in pairs(indexEntriesToRemove) do
		self.index[v] = nil
	end

	self.updateIndex(self.index)
	self:sendIndexUpdate()
end

function Worker:sendIndexUpdate()
	local msg = {
		command = "index",
		index = self.index
	}

	rednet.send(self.serverId, textutils.serialise(msg))
end

function Worker:updateInventory()
	local oldInventoryCopy = {}
	for i = 1, 16 do
		oldInventoryCopy[i] = self.inventory[i] or { count = 0, name = "", damage = 0 }
	end

	local inventory = {}

	for i = 1, 16 do
		inventory[i] = turtle.getItemDetail(i) or { count = 0, name = "", damage = 0 }
	end
	
	self.inventory = inventory
	return oldInventoryCopy, self.inventory
end

function Worker:getInventoryChange()
	local old, new = self:updateInventory()
	local count = 0

	local changes = {}
	local oldCounts = {}
	for i = 1, 16 do
		if old[i].count ~= new[i].count or old[i].name ~= new[i].name then
			local itemName = new[i].name
			if itemName == "" then
				itemName = old[i].name
			end

			if changes[itemName] == nil then
				changes[itemName] = {
					count = 0,
				}
			end

			if oldCounts[itemName] == nil then
				oldCounts[itemName] = 0
			end

			count = count + 1
			changes[itemName].count = changes[itemName].count + new[i].count
			oldCounts[itemName] = oldCounts[itemName] + old[i].count
		end
	end

	for i, v in pairs(changes) do
		v.diff = v.count - oldCounts[i]
	end

	return changes, count
end

function Worker:poll()
	while turtle.suckDown() do
		os.sleep(0.1)
	end

	local changesToIndex, count = self:getInventoryChange()
	if count > 0 then
		self:doIndex(changesToIndex)
	end

	if not self.turtleUtil:selectFreeSlot() then
		self.turtleUtil:organize()
		if not self.turtleUtil:selectFreeSlot() then
			self:putAwayItems()
		end
	end
end

function Worker:pickupItems(order, output)
	local chests = {}
	for i,v in pairs(order) do
		local indexEntry = self.index[v.item]

		if indexEntry ~= nil then
			local itemCount = self.turtleUtil:countOf(v.item)

			if itemCount < v.count then
				-- Try and get everything we need from the current chest
				local availableInChest = indexEntry.currentChestCount or indexEntry.count
				local itemCountInChest = math.min(v.count, availableInChest)
				table.insert(chests, {
					count = itemCountInChest,
					chest = indexEntry.chest,
					item = v.item,
					decreaseCount = function(ammount)
						indexEntry.currentChestCount = indexEntry.currentChestCount - ammount
						self.updateIndex(self.index)
					end
				})

				if itemCountInChest ~= v.count and indexEntry.pastChests ~= nil then
					local remaining = v.count - itemCountInChest

					for n = #indexEntry.pastChests, 1, -1 do
						local nextChest = indexEntry.pastChests[n]
						itemCountInChest = math.min(remaining, itemCountInChest)

						table.insert(chests, {
							count = itemCountInChest,
							chest = nextChest.chest,
							item = v.item,
							decreaseCount = function(ammount)
								nextChest.count = nextChest.count - ammount
								self.updateIndex(self.index)
							end
						})

						remaining = remaining - itemCountInChest
						if remaining <= 0 then
							break
						end
					end
				end
			end
		end
	end

	table.sort(chests, function(a,b) return self:compare(a, b) end)
	local nextOrder = {}

	for i,v in pairs(chests) do
		self.turtleUtil:goTo({
			x = v.chest.x,
			y = v.chest.y - 1,
			z = v.chest.z
		})

		self.turtleUtil:face("n")

		local remaining = v.count

		while remaining > 0 do
			local batchSize = remaining
			if remaining > 64 then
				batchSize = 64
			end

			local countBefore = self.turtleUtil:countOf(v.item)
			local gotItem = turtle.suck(batchSize)
			local countAfter = self.turtleUtil:countOf(v.item)
			if not gotItem or (countAfter - countBefore) ~= batchSize then
				if not self.turtleUtil:selectFreeSlot() then
					local orderItem = nil
					for n, order in pairs(nextOrder) do
						if order.item == v.item then
							orderItem = order
							break
						end
					end

					if orderItem == nil then
						table.insert(nextOrder, { item = v.item, count = remaining })
					else
						orderItem.count = orderItem.count + remaining
					end
				end
				break
			end

			v.decreaseCount(countAfter - countBefore)
			remaining = remaining - batchSize
		end
	end

	self.turtleUtil:goTo({
		x = output.x,
		y = output.y,
		z = 1
	})

	self:updateInventory()

	for i,v in pairs(order) do
		local remaining = v.count

		while remaining > 0 do
			if not self.turtleUtil:selectItem(v.item) then
				break
			end

			local batchSize = turtle.getItemDetail().count
			if batchSize > remaining then
				batchSize = remaining
			end
			if not turtle.dropDown(batchSize) then
				break
			end

			remaining = remaining - batchSize
		end
	end

	local changesToIndex = self:getInventoryChange()
	self:doIndex(changesToIndex)

	if #nextOrder > 0 then
		self:pickupItems(nextOrder, output)
	end

	self.turtleUtil:goToStart()
end

function Worker:putAwayItems()
	self:updateInventory()
	local itemToChestMap = {}

	for i,v in pairs(self.inventory) do
		if self.index[v.name] ~= nil then
			itemToChestMap[v.name] = self.index[v.name].chest
		end
	end

	if table.count(itemToChestMap) ~= 0 then
		-- First get the coordinates of all of the chests and sort them by
		-- Y, X, Z
		local chests = {}
		for i,v in pairs(itemToChestMap) do
			table.insert(chests, { item = i, chest = v })
		end

		table.sort(chests, function(a, b) return self:compare(a, b) end)

		-- Then go to each chest and put its item away
		for i,v in pairs(chests) do
			self.turtleUtil:goTo({
				x = v.chest.x,
				y = v.chest.y - 1,
				z = v.chest.z
			})

			self.turtleUtil:face("n")

			while self.turtleUtil:selectItem(v.item) do
				local itemStackCount = turtle.getItemCount()
				if not turtle.drop() or turtle.getItemCount() > 0 then
					-- Try to dynamically allocate a new chest if the current chest
					-- is full
					local nextChest = self:allocateNewChest()

					if nextChest == nil then
						break
					end

					if self.index[v.item].pastChests == nil then
						self.index[v.item].pastChests = {}
					end

					local totalPutIn = itemStackCount - turtle.getItemCount()
					local countInChest
					if self.index[v.item].currentChestCount ~= nil then
						countInChest = self.index[v.item].currentChestCount + totalPutIn
					else
						countInChest = self.index[v.item].count - self.turtleUtil:countOf(v.item)
					end

					local chestHistoryEntry = {
						chest = self.index[v.item].chest,
						isFull = true,
						count = countInChest
					}

					table.insert(self.index[v.item].pastChests, chestHistoryEntry)

					self.index[v.item].currentChestCount = 0
					self.index[v.item].chest = nextChest

					self.turtleUtil:goTo({
						x = nextChest.x,
						y = nextChest.y - 1,
						z = nextChest.z
					})

					self.turtleUtil:face("n")
				else
					if self.index[v.item].currentChestCount == nil then
						self.index[v.item].currentChestCount = self.index[v.item].count - self.turtleUtil:countOf(v.item)
					else
						self.index[v.item].currentChestCount = self.index[v.item].currentChestCount + itemStackCount
					end
				end
				self.updateIndex(self.index)
			end
		end
	end

	-- Dump everything that couldn't be found in the index
	self:updateInventory()
	local needToDump = false
	for i = 1, 16 do
		if turtle.getItemCount(i) > 0 then
			needToDump = true
		end
	end

	if needToDump then
		self.turtleUtil:goTo({
			x = self.roomSize.x,
			y = 1,
			z = 1,
		})

		for i,v in pairs(self.inventory) do
			turtle.select(i)
			turtle.dropDown()
		end
	end

	local changesToIndex = self:getInventoryChange()
	self:doIndex(changesToIndex)

	self.turtleUtil:goToStart()
end

return Worker
