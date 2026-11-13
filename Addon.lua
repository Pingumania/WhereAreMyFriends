local _, ns = ...

local RESTRICTED_TYPES = {
	[Enum.AddOnRestrictionType.Chat] = true,
	[Enum.AddOnRestrictionType.Map] = true,
}

local MAX_RACE_ID = 100

local friends = {}
local previous = {}
local raceFactions = {}
local playerFaction

local function CacheRaceFactions()
	local race, faction

	for raceID = 1, MAX_RACE_ID do
		race = C_CreatureInfo.GetRaceInfo(raceID)
		faction = race and C_CreatureInfo.GetFactionInfo(raceID)

		if faction then
			raceFactions[race.clientFileString] = faction.groupTag
		end
	end
end

local function IsRestricted()
	for restrictionType in next, RESTRICTED_TYPES do
		if C_RestrictedActions.GetAddOnRestrictionState(restrictionType) ~= Enum.AddOnRestrictionState.Inactive then
			return true
		end
	end

	return false
end

local function IsOtherFaction(englishRace)
	local faction = raceFactions[englishRace]

	return faction ~= nil and faction ~= "Neutral" and faction ~= playerFaction
end

local function IsCandidate(info)
	if not info or FriendMapDB.blocked[info.name] then
		return false
	end

	local _, englishClass, _, englishRace = GetPlayerInfoByGUID(info.guid)

	return not IsOtherFaction(englishRace), englishClass
end

local function SetFriend(list, name, classFile, className, level)
	local friend = previous[name] or {}

	friend.classFile = classFile
	friend.className = className
	friend.level = level
	list[name] = friend
end

local function RefreshCharacterFriends()
	local info, candidate, englishClass

	for index = 1, C_FriendList.GetNumFriends() or 0 do
		info = C_FriendList.GetFriendInfoByIndex(index)

		if info and info.connected then
			candidate, englishClass = IsCandidate(info)

			if candidate then
				SetFriend(friends, info.name, englishClass, info.className, info.level)
			end
		end
	end
end

local function GetGameAccountName(game)
	if RegionalUniqueNamesEnabled() or not game.realmName then
		return game.characterName
	end

	return Ambiguate(game.characterName .. "-" .. game.realmName:gsub("%s", ""), "none")
end

local function AddBattleNetFriends(list)
	local game, name

	for index = 1, BNGetNumFriends() or 0 do
		for gameIndex = 1, C_BattleNet.GetFriendNumGameAccounts(index) or 0 do
			game = C_BattleNet.GetFriendGameAccountInfo(index, gameIndex)

			if game and game.isOnline and game.characterName and game.clientProgram == BNET_CLIENT_WOW and game.wowProjectID == WOW_PROJECT_ID and game.factionName == playerFaction then
				name = GetGameAccountName(game)

				if not FriendMapDB.blocked[name] then
					SetFriend(list, name, game.classFilename, game.className, game.characterLevel)
				end
			end
		end
	end
end

function ns:RefreshFriends()
	if not playerFaction then
		return
	end

	friends, previous = previous, friends
	wipe(friends)

	RefreshCharacterFriends()
	AddBattleNetFriends(friends)

	for name in next, friends do
		if not previous[name] then
			ns:Ping(name)
		end
	end

	for name in next, previous do
		if not friends[name] then
			ns:RemovePeer(name)
		end
	end
end

function ns:PingFriends()
	for name in next, friends do
		if not ns:IsPeer(name) then
			ns:Ping(name)
		end
	end
end

function ns:GetBlockCandidates()
	local names = {}
	local candidates = {}
	local info

	AddBattleNetFriends(names)

	for index = 1, C_FriendList.GetNumFriends() or 0 do
		info = C_FriendList.GetFriendInfoByIndex(index)

		if IsCandidate(info) then
			names[info.name] = true
		end
	end

	for name in next, names do
		candidates[#candidates + 1] = {value = name, label = name}
	end

	table.sort(candidates, function(a, b) return a.value < b.value end)

	return candidates
end

function ns:GetFriend(name)
	return friends[Ambiguate(name, "none")]
end

function ns:IsFriend(name)
	return ns:GetFriend(name) ~= nil
end

function ns:BlockFriend(name)
	if ns:IsPeer(name) then
		ns:SendGone(name)
	end

	FriendMapDB.blocked[name] = true
	ns:RefreshFriends()
end

function ns:UnblockFriend(name)
	FriendMapDB.blocked[name] = nil
	ns:RefreshFriends()
end

function ns:OnLoad()
	if not FriendMapDB then
		_G.FriendMapDB = {}
	end

	FriendMapDB.channel = nil
	FriendMapDB.password = nil
	FriendMapDB.blocked = FriendMapDB.blocked or {}
end

function ns:OnLogin()
	playerFaction = UnitFactionGroup("player")

	CacheRaceFactions()

	if IsRestricted() then
		ns:PauseBroadcasting()
	end

	ns:RefreshFriends()
end

function ns:FRIENDLIST_UPDATE()
	ns:RefreshFriends()
end

function ns:BN_FRIEND_INFO_CHANGED()
	ns:RefreshFriends()
end

function ns:BN_FRIEND_ACCOUNT_ONLINE()
	ns:RefreshFriends()
end

function ns:BN_FRIEND_ACCOUNT_OFFLINE()
	ns:RefreshFriends()
end

function ns:ADDON_RESTRICTION_STATE_CHANGED(restrictionType, state)
	if not RESTRICTED_TYPES[restrictionType] then
		return
	end

	if state == Enum.AddOnRestrictionState.Activating then
		ns:PauseBroadcasting()
		ns:RemoveAllPins()
	elseif state == Enum.AddOnRestrictionState.Inactive and not IsRestricted() then
		ns:ResumeBroadcasting()
		ns:PingFriends()
	end
end
