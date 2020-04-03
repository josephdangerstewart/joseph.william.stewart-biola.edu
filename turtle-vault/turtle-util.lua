local TurtleUtil = {}

function TurtleUtil.new(profile, updatePos)
	local self = setmetatable(TurtleUtil, {})

	self.pos = {
		x = profile.curPos.x,
		y = profile.curPos.y,
		z = profile.curPos.z,
	}

	self.direction = profile.direction
	self.updatePos = updatePos

	return self
end

function TurtleUtil:selectItem(itemName)
	for i = 1, 16 do
		local details = turtle.getItemDetail(i) or {}
		if details.name == itemName then
			turtle.select(i)
			return true
		end
	end
	return false
end

function TurtleUtil:countOf(itemName)
	local total = 0
	for i = 1, 16 do
		local details = turtle.getItemDetail(i) or {}
		if details.name == itemName then
			total = total + details.count
		end
	end
	return total
end

function TurtleUtil:up()
	while not turtle.up() do
		os.sleep(0.2)
	end
	
	self.pos.z = self.pos.z + 1
	self.updatePos(self.pos, self.direction)
end

function TurtleUtil:down()
	while not turtle.down() do
		os.sleep(0.2)
	end

	self.pos.z = self.pos.z - 1
	self.updatePos(self.pos, self.direction)
end

function TurtleUtil:forward()
	while not turtle.forward() do
		os.sleep(0.2)
	end

	if self.direction == "n" then
		self.pos.y = self.pos.y + 1
	elseif self.direction == "s" then
		self.pos.y = self.pos.y - 1
	elseif self.direction == "e" then
		self.pos.x = self.pos.x + 1
	elseif self.direction == "w" then
		self.pos.x = self.pos.x - 1
	else
		error("Bad direction")
		return false
	end

	self.updatePos(self.pos, self.direction)
end

function TurtleUtil:turnLeft()
	turtle.turnLeft()

	if self.direction == "n" then
		self.direction = "w"
	elseif self.direction == "w" then
		self.direction = "s"
	elseif self.direction == "s" then
		self.direction = "e"
	elseif self.direction == "e" then
		self.direction = "n"
	else
		error("Bad direction")
		return false
	end

	self.updatePos(self.pos, self.direction)
end

function TurtleUtil:turnRight()
	turtle.turnRight()

	if self.direction == "n" then
		self.direction = "e"
	elseif self.direction == "w" then
		self.direction = "n"
	elseif self.direction == "s" then
		self.direction = "w"
	elseif self.direction == "e" then
		self.direction = "s"
	else
		error("Bad direction")
		return false
	end

	self.updatePos(self.pos, self.direction)
end

function TurtleUtil:face(direction)
	if self.direction == direction then
		return
	end

	if direction ~= "n" and direction ~= "e" and direction ~= "s" and direction ~= "w" then
		error("Bad direction")
		return false
	end

	local function turnFunc()
		self:turnLeft()
	end

	if (self.direction == "n" and direction == "e") or (self.direction == "e" and direction == "s") or (self.direction == "s" and direction == "w") or (self.direction == "w" and direction == "n") then
		turnFunc = function()
			self:turnRight()
		end
	end

	while self.direction ~= direction do
		turnFunc()
	end
end

function TurtleUtil:getCurPos()
	return self.pos
end

function TurtleUtil:goToStart()
	self:goTo({ x = 1, y = 1, z = 1 })
	self:face("n")
end

function TurtleUtil:selectFreeSlot()
	for i = 1, 16 do
		if turtle.getItemCount(i) == 0 then
			turtle.select(i)
			return true, i
		end
	end
	return false
end

function TurtleUtil:organize()
	local inventoryByItem = {}
	for i = 1, 16 do
		if turtle.getItemCount(i) > 0 then
			local details = turtle.getItemDetail(i)

			if inventoryByItem[details.name] == nil then
				inventoryByItem[details.name] = {}
			end

			table.insert(inventoryByItem[details.name], { slot = i, count = details.count })
		end
	end

	local compare = function(a, b) return a.count < b.count end

	for i,v in pairs(inventoryByItem) do
		table.sort(v, compare)

		for cur = 1, #v - 1 do
			for target = #v, #v, -1 do
				turtle.select(v[cur].slot)
				
				if turtle.transferTo(v[target].slot) and turtle.getItemCount() > 0 then
					break
				end
			end
		end
	end
end

function TurtleUtil:goTo(coords)
	if self.pos.z ~= coords.z then
		local moveFunc
		if self.pos.z > coords.z then
			moveFunc = function()
				self:down()
			end
		else
			moveFunc = function()
				self:up()
			end
		end

		while self.pos.z ~= coords.z do
			moveFunc()
		end
	end

	if self.pos.y ~= coords.y then
		-- Zero out x first
		self:face("w")
		while self.pos.x ~= 1 do
			self:forward()
		end

		if self.pos.y > coords.y then
			self:turnLeft()
		else
			self:turnRight()
		end

		while self.pos.y ~= coords.y do
			self:forward()
		end
	end

	if self.pos.x ~= coords.x then
		if self.pos.x > coords.x then
			self:face("w")
		else
			self:face("e")
		end

		while self.pos.x ~= coords.x do
			self:forward()
		end
	end
end

return TurtleUtil
