local say = ...

local function outOfFuel()
	say("Turtle has run out of fuel... exiting setup with error code")
	return false, "Out of fuel"
end

say("Compiling profile data")

term.write("What is the server id: ")
local serverId = tonumber(read())

local ySize = 1
while not turtle.detect() and turtle.forward() do
	ySize = ySize + 1
end

turtle.turnRight()
local xSize = 1
while not turtle.detect() and turtle.forward() do
	xSize = xSize + 1
end

local zSize = 1
while not turtle.detectUp() and turtle.up() do
	zSize = zSize + 1
end

local roomSize = {
	x = xSize,
	y = ySize,
	z = zSize,
}

local curZ = roomSize.z
while curZ ~= 1 and turtle.down() do
	curZ = curZ - 1
end

turtle.turnLeft()
turtle.turnLeft()

local curX = roomSize.x
while curX ~= 1 and turtle.forward() do
	curX = curX - 1
end

turtle.turnLeft()

local curY = roomSize.y
while curY ~= 1 and turtle.forward() do
	curY = curY - 1
end

turtle.turnRight()
turtle.turnRight()

-- Step two: Save the data
local data = {
	roomSize = roomSize,
	curPos = {
		x = 1,
		y = 1,
		z = 1
	},
	serverId = serverId,
	index = {},
	direction = "n"
}

local file = fs.open("profile.data", "w")
file.write(textutils.serialise(data))
file.close()

rednet.send(serverId, textutils.serialise({ command = "register", roomSize = roomSize }))

say("Set up is complete")
