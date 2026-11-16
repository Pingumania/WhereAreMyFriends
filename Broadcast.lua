local _, ns = ...

local AceComm = LibStub("AceComm-3.0")
local HBD = LibStub("HereBeDragons-2.0")

local PREFIX = "WAMF"
local TICK_INTERVAL = 2
local HEARTBEAT_TICKS = 15
local HELLO = "hello"
local ACK = "ack"
local GONE = "gone"
local HIDE = "hide"

local peers = {}
local ticker
local restricted
local ticks = 0
local lastMessage

local function Serialize(instanceId, x, y)
	if not (instanceId and x and y) then
		return HIDE
	end

	return string.format("%d:%.4f:%.4f", instanceId, x, y)
end

local function Deserialize(message)
	local instanceId, x, y = string.match(message, "^(%d+):(-?[%d%.]+):(-?[%d%.]+)$")
	if not instanceId then
		return nil
	end

	return tonumber(instanceId), tonumber(x), tonumber(y)
end

local function Send(message, name)
	if restricted then
		return
	end

	AceComm:SendCommMessage(PREFIX, message, "WHISPER", name)
end

local function AddPeer(name)
	peers[name] = true

	if lastMessage then
		Send(lastMessage, name)
	end

	ns:StartBroadcasting()
end

function ns:IsPeer(name)
	return peers[name] ~= nil
end

function ns:RemovePeer(name)
	peers[name] = nil

	ns:RemovePin(name)
end

function ns:Ping(name)
	Send(HELLO, name)
end

function ns:SendGone(name)
	Send(GONE, name)
end

function ns:Broadcast()
	local x, y, instanceId = HBD:GetPlayerWorldPosition()
	local message = Serialize(instanceId, x, y)
	ticks = ticks + 1
	local heartbeat = ticks >= HEARTBEAT_TICKS

	if message == lastMessage and not heartbeat then
		return
	end

	lastMessage = message

	for name in next, peers do
		Send(message, name)
	end

	if heartbeat then
		ticks = 0
		ns:PingFriends()
	end
end

function ns:StartBroadcasting()
	if ticker or restricted then
		return
	end

	ticker = C_Timer.NewTicker(TICK_INTERVAL, function() ns:Broadcast() end)
end

function ns:StopBroadcasting()
	if not ticker then
		return
	end

	ticker:Cancel()
	ticker = nil
	lastMessage = nil
end

function ns:PauseBroadcasting()
	for name in next, peers do
		Send(GONE, name)
	end

	ns:StopBroadcasting()
end

function ns:SetRestricted(value)
	if value then
		ns:PauseBroadcasting()
		ns:RemoveAllPins()
	end

	restricted = value

	if not value then
		ns:StartBroadcasting()
		ns:PingFriends()
	end
end

function ns:OnCommReceived(prefix, message, distribution, sender)
	if prefix ~= PREFIX or distribution ~= "WHISPER" then
		return
	end

	sender = Ambiguate(sender, "none")

	if restricted or not ns:IsFriend(sender) then
		return
	end

	if message == HELLO then
		Send(ACK, sender)
		AddPeer(sender)
	elseif message == ACK then
		AddPeer(sender)
	elseif message == GONE then
		ns:RemovePeer(sender)
	else
		if not ns:IsPeer(sender) then
			AddPeer(sender)
		end

		if message == HIDE then
			ns:RemovePin(sender)
		else
			local instanceId, x, y = Deserialize(message)

			if instanceId then
				ns:UpdatePin(sender, instanceId, x, y)
			end
		end
	end
end

AceComm:RegisterComm(PREFIX, function(...) ns:OnCommReceived(...) end)
