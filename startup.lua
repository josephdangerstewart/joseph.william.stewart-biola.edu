table.count = function(t)
	local n = 0
	for i,v in pairs(t) do
		n = n + 1
	end
	return n
end

local NetworkManager = dofile("turtle-vault/network-manager.lua")
local Worker = dofile("turtle-vault/worker.lua")
local TurtleUtil = dofile("turtle-vault/turtle-util.lua")

if not fs.exists("profile.data") then
	local setup, err = loadfile("turtle-vault/setup.lua")

	if not setup then
		error(err)
		return
	end

	setup(print)
end

local file = fs.open("profile.data", "r")
local profile = textutils.unserialise(file.readAll())
file.close() 

local function updatePos(coords, direction)
	profile.curPos = coords
	profile.direction = direction

	local profileFile = fs.open("profile.data", "w")
	profileFile.write(textutils.serialise(profile))
	profileFile.close()
end

local function updateIndex(index)
	profile.index = index

	local profileFile = fs.open("profile.data", "w")
	profileFile.write(textutils.serialise(profile))
	profileFile.close()
end

local turtleUtil = TurtleUtil.new(profile, updatePos)
local worker = Worker.new(profile, turtleUtil, updateIndex)
local networkManager = NetworkManager.new(worker, profile)

turtleUtil:goToStart()

while true do
	networkManager:listen()
	networkManager:setPolling(true)
	worker:poll()
	networkManager:setPolling(false)
end
