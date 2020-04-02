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
	local lastChest = {
		x = 2,
		y = 2,
		z = 1,
	}
	local roomSize = self.roomSize

	if table.count(self.index) == 0 then
		return lastChest
	end
	
	for i,v in pairs(self.index) do
		if v.chest.y > lastChest.y then
			lastChest.x = v.chest.x
			lastChest.z = v.chest.z
			lastChest.y = v.chest.y
		end

		if v.chest.z > lastChest.z and v.chest.y == lastChest.y then
			lastChest.x = v.chest.x
			lastChest.z = v.chest.z
		end

		if v.chest.x > lastChest.x and v.chest.z == lastChest.z and v.chest.y == lastChest.y then
			lastChest.x = v.chest.x
		end
	end

	if lastChest.x + 3 < roomSize.x then
		-- Try and increase x first
		return {
			x = lastChest.x + 3,
			z = lastChest.z,
			y = lastChest.y
		}
	elseif lastChest.z + 2 < roomSize.z then
		-- Try and increase z next
		return {
			x = 2,
			z = lastChest.z + 2,
			y = lastChest.y,
		}
	elseif lastChest.y + 2 < roomSize.y then
		-- Try and increase y next
		return {
			x = 2,
			z = 1,
			y = lastChest.y + 2,
		}
	else
		return nil
	end
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

	self.updateIndex(self.index)
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
		self:putAwayItems()
	end
end

function Worker:pickupItems(order, output)
	local chests = {}
	for i,v in pairs(order) do
		local indexEntry = self.index[v.item]

		if indexEntry ~= nil then
			local itemCount = self.turtleUtil:countOf(v.item)

			if itemCount < v.count then
				table.insert(chests, { count = v.count - itemCount, chest = indexEntry.chest, item = v.item })
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

			if not turtle.suck(batchSize) then
				if not self.turtleUtil:selectFreeSlot() then
					table.insert(nextOrder, { item = v.item, count = remaining })
				end
				break
			end

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
				turtle.drop()
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

	self.turtleUtil:goToStart()
	self:updateInventory()
end

return Worker
