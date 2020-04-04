local NetworkManager = {}
NetworkManager.__index = NetworkManager

function NetworkManager.new(worker, profile)
	local self = setmetatable(NetworkManager, {})

	self.worker = worker
	self.serverId = profile.serverId

	local isModemFound = false
	for i,v in pairs(peripheral.getNames()) do
		if peripheral.getType(v) == "modem" then
			rednet.open(v)
			isModemFound = true
		end
	end

	if not isModemFound then
		error("No modem found")
		return false
	end

	return self
end

function NetworkManager:receive(wait)
	local waitTimer = os.startTimer(wait)

	while true do
		local e, id, msg = os.pullEvent()

		if e == "timer" and waitTimer == id then
			return nil, nil
		elseif e == "rednet_message" and id == self.serverId then
			return id, msg
		end
	end
end

function NetworkManager:listen()
	local id, msg = self:receive(2)
	if msg == nil then
		return
	end

	self:setPolling(true)
	local data = textutils.unserialise(msg)

	if data.command == "batch-message" then
		for i,v in pairs(data.messages) do
			NetworkManager:processMessage(v)
		end
	else
		self:processMessage(data)
	end

	self:setPolling(false)
end

function NetworkManager:processMessage(data)
	if data.command == "pickup" then
		local order = data.order
		local output = data.output

		self.worker:pickupItems(order, output)
	elseif data.command == "do-index" then
		self.worker:sendIndexUpdate()
	end
end

function NetworkManager:setPolling(value)
	local msg = {
		command = "set-polling",
		value = value
	}

	rednet.send(self.serverId, textutils.serialise(msg))
end

return NetworkManager
