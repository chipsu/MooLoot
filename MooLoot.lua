--[[
	A simple master looter addon, inspired by XLootMaster but doesn't require XLoot.
	
	NOTE: This is just an early demo of the MooLoot addon, I'm not really used to WoW/Ace3 API or LUA yet so expect some weird bugs ;)
	
	-- Configuration --
	Click Interace > Addons > MooLoot or by typing /mooloot in the console.
		
	-- Looting --
	Right click an item to show the MooLoot menu. If the menu closes you can just right click the item again.
	The default (blizzard) menu will show if you hold down CONTROL.
	
	TODO: -- critical ---
			ON_PARTY_CHAT:
				if self.rollActive and self.db.allowClientPause then
					if chat == "wait"  or chat == "pause" then
						self:PauseRoll(sender)
					end
				end
		  
		  -- high prio ---
		  Automatically set loot threshold when becoming a LM or creating a new raid and warn if ML isn't set.
		  No confirm for low quality items
		  Better error handling/reporting
		  Slash commands
		  Dont announce badges?
		  Detect guild runs and pugs so they can have individual profiles?
		  
		  -- medium prio --
		  "Fair" randomness
		  History, + easy copy & paste for forums etc (as a separate addon maybe)
		  Better boss name detection? chests and stuff...
		  Support for other loot addons. MooLoot does detect XLoot's frames, but maybe ask the user before overriding XLoots events.
		  Standby when not master looter
		  Extend roll by X seconds
		  Alert looters if they are changing item during a roll (starting roll for item #1, then opening them menu for #2)? It's just during a roll this may cause confusion.
		  
		  -- low prio --
		  User pausing and other commands (by typing wait, pass, passall, offspec etc.), allowing rolls to end early if everyone responds.
		  Route only some messages to RW
		  Custom rolls (extend the main/offspec thing)
		  Custom client frame (with need for main/ offspec/pass buttons)
		  Localizations
		  Roll range other than 1,100 (supported, but not configurable from the UI, and roll range isn't announced)
		  Loot announcing when not ML, useful for trash epics.
		  Roll tracker (triggered by someone doing a /roll, then announcing the result silently or to the party)
		  Master looter raid roll (and maybe announce raid ids first, to prevent drama, this could also be used for ties, optional ofc)
		  
		  -- implemented, but needs to be verified --
		  Pausing -- working
		  Stopping -- working
		  Database reset & saving -- working
		  Disenchant -- working
		  Remember loot rolls when if the lootwindow is closed & reopened -- working
		  Auto loot announce (only once) -- working, but stuff like badges are announced too
		  Check if players are in the group/raid -- should work, untested
		  Party looting -- untested
		  Loot handout -- working
]]

MooLoot = LibStub("AceAddon-3.0"):NewAddon("MooLoot", "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0", "AceTimer-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local L = LibStub("AceLocale-3.0"):GetLocale("MooLoot")
local Dewdrop = AceLibrary("Dewdrop-2.0")
local currentVersion = 0.51
local leastCompatible = 0.46
local updateInterval = 1.0

StaticPopupDialogs["MooLoot_Confirm"] = {
	-- TODO: Remove this warning once we consider MooLoot stable enough
	text = "\n" .. L["Give %s to %s?"] .. "\n\nWarning! Check that the item and playername is correct!",
	button1 = "Yes",
	button2 = "No",
	OnAccept = function(self, data)
		local _,name = GetLootSlotInfo(data.item.index)
		assert(name == data.item.name)
		assert(GetMasterLootCandidate(data.candidateIndex) == data.player)
		assert(GetLootSlotLink(data.item.index) == data.item.link)
		GiveMasterLoot(data.item.index, data.candidateIndex)
		MooLoot:FormatToChat(data.message or "awarded", { player = data.player, item = data.item.link })
	end,
	timeout = 0,
	whileDead = 1,
	hideOnEscape = 1
};

local options = { 
	name = L["MooLoot"],
	type = "group",
	args = {
		start = {
			name = "Start",
			type = "group",
			args = {
				description = {
					type = "description",
					name = L["m00! Select a submenu for more options"],
					width = "full",
				},
				reset = {
					type = "execute",
					name = L["Reset configuration"],
					desc = L["Resets all MooLoot options"],
					order = 1000,
					width = "full",
					func = function() MooLoot:LoadDefaultOptions() end,
				},
				enableDebug = {
					type = "toggle",
					name = L["Enabled debug output"],
					desc = L["Should probably be disabled"],
					order = -1,
					width = "full",
					get = function(info) return MooLoot.db.enableDebug end,
					set = function(info, value) MooLoot.db.enableDebug = not MooLoot.db.enableDebug end,
				},
			},
		},
		general = {
			name = "General",
			type = "group",
			args = {
				enableRaidWarning = {
					type = "toggle",
					name = L["Announce in RW"],
					desc = L["Send all messages to raid warning"],
					order = 10,
					get = function(info) return MooLoot.db.enableRaidWarning end,
					set = function(info, value) MooLoot.db.enableRaidWarning = not MooLoot.db.enableRaidWarning end,
				},
				enableOffspecRoll = {
					type = "toggle",
					name = L["Auto offspec roll"],
					desc = L["Enable this to automatically do an offspec roll if no main rolls are found"],
					order = 20,
					get = function(info) return MooLoot.db.enableOffspecRoll end,
					set = function(info, value) MooLoot.db.enableOffspecRoll = not MooLoot.db.enableOffspecRoll end,
				},
				autoAnnounce = {
					type = "toggle",
					name = L["Auto announce loot"],
					desc = L["Enable this to automatically announce the loot"],
					order = 30,
					get = function(info) return MooLoot.db.autoAnnounce end,
					set = function(info, value) MooLoot.db.autoAnnounce = not MooLoot.db.autoAnnounce end,
				},
				boeWarning = {
					type = "toggle",
					name = L["Bind on equip warning"],
					desc = L["Warn when a BoE item is detected"],
					order = 31,
					get = function(info) return MooLoot.db.boeWarning end,
					set = function(info, value) MooLoot.db.boeWarning = not MooLoot.db.boeWarning end,
				},
				allowClientPause = {
					type = "toggle",
					name = L["Allow user pause"],
					desc = L["Allow users to pause the roll by typing wait or pause in the chat"],
					order = 32,
					get = function(info) return MooLoot.db.allowClientPause end,
					set = function(info, value) MooLoot.db.allowClientPause = not MooLoot.db.allowClientPause end,
				},
				enchanters = {
					type = "input",
					name = L["Enchanters"],
					desc = L["A comma separated list of known enchanters on your current realm"],
					order = 40,
					width = "full",
					get = function(info) return table.concat(MooLoot:GetEnchanters(), ", ") end,
					set = function(info, value)
						local enchanters = { strsplit(" ", string.gsub(value, ",", " ")) }
						MooLoot:SetEnchanters(enchanters)
					end,
				},		
				rollTime1 = {
					type = "range",
					name = L["Roll timeout"],
					desc = L["Time in seconds before the roll ends"],
					order = 50,
					min = 10,
					max = 60,
					step = 1,
					width = "full",
					get = function(info) return MooLoot.db.rollTime1 end,
					set = function(info, value) MooLoot.db.rollTime1 = value end,
				},
				rollTime2 = {
					type = "range",
					name = L["Offspec roll timeout"],
					desc = L["Time in seconds before the offspec roll ends"],
					order = 60,
					min = 10,
					max = 60,
					step = 1,
					width = "full",
					get = function(info) return MooLoot.db.rollTime2 end,
					set = function(info, value) MooLoot.db.rollTime2 = value end,
				},
				endingThreshold = {
					type = "range",
					name = L["Announce end threshold"],
					desc = L["Should be lower than roll and offspec roll timeout"],
					order = 70,
					min = 5,
					max = 30,
					step = 1,
					width = "full",
					get = function(info) return MooLoot.db.endingThreshold end,
					set = function(info, value) MooLoot.db.endingThreshold = value end,
				},
			},
		},
		messages = {
			type = "group",
			name = "Messages",
			args = {
				announce = {
					type = "input",
					name = L["Announce"],
					desc = L["This message is sent when the loot is announced"],
					order = 10,
					width = "full",
					get = function(info) return MooLoot.db.msg.announce end,
					set = function(info, value) MooLoot.db.msg.announce = value end,
				},
				roll = {
					type = "input",
					name = L["Roll for item"],
					desc = L["Sent when a new roll starts"],
					order = 20,
					width = "full",
					get = function(info) return MooLoot.db.msg.roll1 end,
					set = function(info, value) MooLoot.db.msg.roll1 = value end,
				},
				offspec = {
					type = "input",
					name = L["Roll for offspec"],
					desc = L["Sent when an offspec roll starts"],
					order = 30,
					width = "full",
					get = function(info) return MooLoot.db.msg.roll2 end,
					set = function(info, value) MooLoot.db.msg.roll2 = value end,
				},
				all = {
					type = "input",
					name = L["All roll for"],
					desc = L["Sent when a roll for an item that anyone can use starts"],
					order = 35,
					width = "full",
					get = function(info) return MooLoot.db.msg.all end,
					set = function(info, value) MooLoot.db.msg.all = value end,
				},
				ending = {
					type = "input",
					name = L["Roll ending"],
					desc = L["Sent when a roll is about to end"],
					order = 40,
					width = "full",
					get = function(info) return MooLoot.db.msg.ending end,
					set = function(info, value) MooLoot.db.msg.ending = value end,
				},
				won = {
					type = "input",
					name = L["Won"],
					desc = L["Sent when a roll is won"],
					order = 50,
					width = "full",
					get = function(info) return MooLoot.db.msg.won end,
					set = function(info, value) MooLoot.db.msg.won = value end,
				},
				tie = {
					type = "input",
					name = L["Tied"],
					desc = L["Sent when a roll tied"],
					order = 60,
					width = "full",
					get = function(info) return MooLoot.db.msg.tie end,
					set = function(info, value) MooLoot.db.msg.tie = value end,
				},
				ended = {
					type = "input",
					name = L["Ended"],
					desc = L["Sent when a roll ended without anyone rolled"],
					order = 70,
					width = "full",
					get = function(info) return MooLoot.db.msg.ended end,
					set = function(info, value) MooLoot.db.msg.ended = value end,
				},
				stopped = {
					type = "input",
					name = L["Stopped"],
					desc = L["Sent when a roll is stopped"],
					order = 80,
					width = "full",
					get = function(info) return MooLoot.db.msg.stopped end,
					set = function(info, value) MooLoot.db.msg.stopped = value end,
				},
				awarded = {
					type = "input",
					name = L["Awarded"],
					desc = L["Sent when the loot master gives an item to someone"],
					order = 90,
					width = "full",
					get = function(info) return MooLoot.db.msg.awarded end,
					set = function(info, value) MooLoot.db.msg.awarded = value end,
				},
				disenchant = {
					type = "input",
					name = L["Disenchant"],
					desc = L["Sent when the loot master gives an item for disenchanting"],
					order = 100,
					width = "full",
					get = function(info) return MooLoot.db.msg.disenchant end,
					set = function(info, value) MooLoot.db.msg.disenchant = value end,
				},
				random = {
					type = "input",
					name = L["Random"],
					desc = L["Sent when the loot master gives an item to a random player"],
					order = 100,
					width = "full",
					get = function(info) return MooLoot.db.msg.disenchant end,
					set = function(info, value) MooLoot.db.msg.disenchant = value end,
				},
			},
		},
	},
}

local defaults = {
	profile =  {
		lastVersion = 0,
		enableDebug = false,
		enableRaidWarning = false,
		enableOffspecRoll = true,
		rollTime1 = 30,
		rollTime2 = 20,
		endingThreshold = 10,
		autoAnnounce = true,
		boeWarning = true,
		allowClientPause = true,
		rememberLootFor = 300,
		rollLow = 1,
		rollHigh = 100,
		msg = {
			announce = "$boss dropped $items",
			roll1 = "Roll for $item if you need for MAIN spec! Ending in $time.",
			roll2 = "Roll for $item if you need for OFF spec! Ending in $time.",
			all = "All roll for $item if you can use it, Ending in $time.",
			ending = "Roll for $item will end in $time.",
			won = "$player won $item ($roll)!",
			tie = "$players tied for $item ($roll), please reroll now! Ending in $time.",
			tie2 = "$players tied for $item ($roll).",
			ended = "Roll for $item ended, no one rolled.",
			stopped = "Roll for $item ended by $player",
			awarded = "$player was awared $item",
			disenchant = "$item was given to $player for disenchanting",
			random = "$item was randomly given to $player",
			paused = "Roll for $item paused by $player, you can still continue to roll",
			resumed = "Roll for $item resumed by $player. Ending in $time.",
			notEligible = "Sorry, $player you cannot receive $item",
			boe = "$item binds on equip!",
		},
		enchanters = {
		},
	},
}

function MooLoot:OnInitialize()
	self.database = LibStub("AceDB-3.0"):New("MooLootDB")
	self.database:RegisterDefaults(defaults)
	LibStub("AceConfig-3.0"):RegisterOptionsTable("MooLoot", options)
	AceConfigRegistry:RegisterOptionsTable("MooLoot Start", options.args.start)
	AceConfigRegistry:RegisterOptionsTable("MooLoot General", options.args.general)
	AceConfigRegistry:RegisterOptionsTable("MooLoot Messages", options.args.messages)
	
	self.optionsFrame = AceConfigDialog:AddToBlizOptions("MooLoot Start", "MooLoot")
	AceConfigDialog:AddToBlizOptions("MooLoot General", "General", "MooLoot")
	AceConfigDialog:AddToBlizOptions("MooLoot Messages", "Messages", "MooLoot")
	
	self:RegisterChatCommand("mooloot", "ChatCommand")
	
	local lastVersion = self.database.profile.lastVersion or 0
	if lastVersion < leastCompatible then
		self:Print("Incompatible database (" .. lastVersion .. " < " .. leastCompatible .. "), loading defaults")
		self.database:ResetDB()
	elseif lastVersion < currentVersion then
		self:Trace("Database from previous version (" .. lastVersion .. ") should work fine though...")
	end
	
	self:Trace("|cFF00FF00MooLoot|r version |cFF00FF00" .. currentVersion .. "|r")
	self:Trace("|cFFFF0000Warning:|r Debug mode enabled, non valid rolls might be captured!")
	self:Trace("Type |cFF00FF00/mooloot|r to disable debug logging")
	
	self.db = self.database.profile
	self.db.lastVersion = currentVersion
	self.lastUpdate = 0
	self.rolls = {}
	self.items = {}
	self.realm = GetRealmName()
	self.rollActive = false
	self.rollPauseCounter = 0
end

function MooLoot:ChatCommand(input)
	if not input or input:trim() == "" then
		InterfaceOptionsFrame_OpenToCategory(self.optionsFrame)
	else
		LibStub("AceConfigCmd-3.0").HandleCommand(MooLoot, "mooloot", "MooLoot", input)
	end
end
function MooLoot:OnEnable()
	self:RegisterEvent("LOOT_OPENED")
	self:RegisterEvent("LOOT_CLOSED")
	self:RegisterEvent("CHAT_MSG_SYSTEM")
	self:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
end

function MooLoot:OnDisable()
	self:HideFrame()
end

function MooLoot:StartRoll(item, counter, message, options)
	if self.rollActive then
		self:Trace("Already rolling for " .. self.rollItem.name .. ", wait for the roll to end")
		return false
	end
	counter = counter or 1
	message = message or "roll" .. counter
	local rollTime = options and options.rollTime or self.db["rollTime" ..  counter] or 30
	self:Trace("Starting roll #" .. counter)
	self.rolls = {}
	self.rollers = {}
	self.players = options and options.players or {}
	self.rollItem = item
	self.rollStart = time()
	self.rollEndAnnounced = false
	self.rollCounter = counter
	self.rollEnd = time() + rollTime
	self.rollTimer = self:ScheduleRepeatingTimer("UpdateActiveRoll", 1)
	self.rollActive = true
	self.rollPauseCounter = 0
	self:FormatToChat(message, { item = item.link,
		time = self:FormatTimeLeft(),
		players = self.players,
		roll = options and options.roll
	})
end

function MooLoot:IsRollPaused()
	return self.rollPauseCounter > 0
end

function MooLoot:PauseRoll(player)
	self.rollPauseCounter = self.rollPauseCounter + 1
	if self.rollPauseCounter == 1 then
		self.rollPauseTime = self:GetTimeLeft()
		self:FormatToChat("paused", { player = player or UnitName("player"), item = self.rollItem.link })
		Dewdrop:Refresh(1)
	end
end

function MooLoot:ResumeRoll(player, reset)
	if self.rollPauseCounter > 0 then
		self.rollPauseCounter = self.rollPauseCounter - 1
		if reset or self.rollPauseCounter == 0 then
			self.rollPauseCounter = 0
			self.rollEnd = time() + self.rollPauseTime
			self:FormatToChat("resumed", { player = player or UnitName("player"), item = self.rollItem.link, time = self:FormatTimeLeft() })
			Dewdrop:Refresh(1)
		end
	end
end

function MooLoot:EndRoll(player)
	if self.rollActive then
		self:FormatToChat("stopped", { player = player or UnitName("player"), item = self.rollItem.link })
		self:RollEnded(true)
	else
		self:Trace("No active roll")
	end
end

function MooLoot:UpdateActiveRoll()
	if not self:IsRollPaused() then
		local seconds = self:GetTimeLeft()
		if not self.rollEndAnnounced and seconds <= self.db.endingThreshold then
			self.rollEndAnnounced = true
			self:FormatToChat("ending", { item = self.rollItem.link, time = self:FormatTimeLeft() })
		end
		if seconds < 1 then
			self:RollEnded()
			return
		else
			--self:GetLootFrame():SetStatusText("Rolling for " .. self.rollItem.name .. ", ending in " .. self:FormatTimeLeft())
		end
	end
	Dewdrop:Refresh(1)
end

function MooLoot:IsValidRoll(player, roll, low, high)
	if player and roll and low == self.db.rollLow and high == self.db.rollHigh then
		if #(self.players) > 0 then
			local found = false
			for _,v in ipairs(self.players) do
				if v == player then
					found = true
					break
				end
			end
			if not found then return
				false
			end
		end
		if self:CanHaveLoot(player) then
			return true
		end
		self:FormatToChat("notEligible", { player = player, self.rollItem.link })
		self:Trace(player .. " rolled, but cannot receive the current item from the master looter")
	end
	return false
end

function MooLoot:CHAT_MSG_SYSTEM()
	if self.rollActive then
		local pattern = string.gsub(RANDOM_ROLL_RESULT, "[%(%)-]", "%%%1")
		pattern = string.gsub(pattern, "%%s", "(.+)")
		pattern = string.gsub(pattern, "%%d", "%(%%d+%)")
		for player, roll, low, high in string.gmatch(arg1, pattern) do
			roll = tonumber(roll)
			low = tonumber(low)
			high = tonumber(high)
			--self:Trace(player .. " rolled " .. roll .. " - " .. low .. "," .. high)
			if self:IsValidRoll(player, roll, low, high) and self.rollers[player] == nil then
				self:Trace(player .. " rolled " .. roll)
				self.rollers[player] = true
				table.insert(self.rolls, { player = player, roll = roll })
				table.insert(self.rolls, { player = player, roll = roll })
			end
		end
	end
end

function MooLoot:RollEnded(noReroll)
	self.rollActive = false
	self.rollPauseCounter = 0
	self:Trace("Roll ended")
	self:CancelTimer(self.rollTimer)
	if #(self.rolls) < 1 then
		if not noReroll and self.rollCounter == 1 and self.db.enableOffspecRoll then
			self:Trace("No rolls detected, starting offspec roll")
			self:StartRoll(self.rollItem, self.rollCounter + 1)
		else
			self:Trace("No one rolled for item")
			self:FormatToChat("ended", { item = self.rollItem.link })
		end
	else
		local tied = {}
		table.sort(self.rolls, function(a, b) return a.roll > b.roll end)
		for _,v in ipairs(self.rolls) do
			if tied[v.roll] == nil then
				tied[v.roll] = {}
			end
			table.insert(tied[v.roll], v.player)
		end
		local roll = self.rolls[1].roll
		if #(tied[roll]) > 1 then
			if noReroll then
				self:Trace("Tie detected")
				self:FormatToChat("tie2", { item = self.rollItem.link, players = tied[roll], roll = roll })
			else
				self:Trace("Tie detected, rerolling")
				self:StartRoll(self.rollItem, self.rollCounter + 1, "tie", { item = self.rollItem.link, players = tied[roll], roll = roll })
			end
		else
			local player = self.rolls[1].player
			self:FormatToChat("won", { item = self.rollItem.link, player = player, roll = roll })
		end
		self.rollItem.rolls = self.rolls
		self.rolls = {}
	end
	Dewdrop:Refresh(1)
end

function MooLoot:GetTimeLeft()
	return self.rollEnd - time()
end

function MooLoot:FormatTimeLeft()
	local seconds = self:GetTimeLeft()
	return seconds .. " " .. L["seconds"]
end

function MooLoot:Trace(obj)
	if self.database.profile.enableDebug then
		self:Print(obj)
	end
end

function MooLoot:FormatMessage(message, params)
	local result = self.db.msg[message] or message
	for _,v in ipairs(params) do
		if type(v) == "table" then
			v = table.concat(v, ", ")
			if type(v) == "table" then
				v = "<table>"
			end
		elseif type(v) ~= "string" then
			v = tostring(v)
		end
	end
	return string.gsub(result, "%$(%w+)", params)
end

-- TODO: I really don't know if this works with all kind of links, it's just a quick hack.
-- TODO: We should prefer to split words instead (find spaces) (tho, not needed if the message format is blablabla $items).
function MooLoot:SplitText(text, length)
	length = length or 255
	if string.len(text) < length then
		return { text }
	end
	local parts = {}
	local start = 1
	--local fail = 1
	while start <= string.len(text) do
		local linkStart = string.find(text, "\124c", start)
		local pos = start + length - 1
		if linkStart and linkStart - start < length then
			pos = linkStart - 1
			local linkEnd = string.find(text, "\124r", pos)
			while linkEnd and (pos == linkStart - 1 or pos + linkEnd - start < length) do
				pos = linkEnd + 1
				linkEnd = string.find(text, "\124r", pos)
			end
		end
		self:Trace("SPLIT: [" .. string.sub(text, start, pos) .. "]")
		table.insert(parts, string.sub(text, start, pos))
		start = pos + 1
		--[[fail = fail + 1
		if fail > 20 then
			self:Trace("FAILFAILFAIL!")
			return parts
		end--]]
	end
	return parts
end

function MooLoot:SendToChannel(text, channel, target)
	local parts = self:SplitText(text)
	for _,v in ipairs(parts) do
		SendChatMessage(v, channel, nil, target)
	end
end

function MooLoot:SendToChat(text)
	self:Trace("CHAT: " .. text)
	if self.db.enableRaidWarning then
		if IsRaidLeader("player") or IsRaidOfficer("player") or UnitIsPartyLeader("player") then
			self:SendToChannel(text, "RAID_WARNING")
			return
		end
	end
	if UnitInRaid("player") then
		self:SendToChannel(text, "RAID")
	elseif GetNumPartyMembers() > 0 then
		self:SendToChannel(text, "PARTY")
	else
		self:SendToChannel(text, "WHISPER", UnitName("player"))
		--self:Print("(you're not in a group): " .. text)
	end
end

function MooLoot:FormatToChat(message, params)
	local text = self:FormatMessage(message, params)
	self:SendToChat(text)
	return text
end

function MooLoot:IsMasterLooter()
	local method, partyId, raidId = GetLootMethod()
	if raidId ~= nil then
		local name = GetRaidRosterInfo(raidId)
		return name == UnitName("player")
	end
	if partyId ~= nil and partyId == 0 then
		return true
	end
	return false
end

-- TODO: Not sure about this
--       Track random rolls so the same player doesn't get an item in a row?
function MooLoot:GetRandomCandidate()
	local max = GetNumRaidMembers() and 40 or MAX_PARTY_MEMBERS
	for attempt = 1,40 do
		local rand = math.random(1, max + 1)
		local player = GetMasterLootCandidate(rand)
		if player then
			return rand, player
		end
	end
	return nil
end

function MooLoot:GetLootCandidate(player)	
	if GetNumRaidMembers() > 0 then
		for index = 1, 40 do
			if GetMasterLootCandidate(index) == player then
				return index
			end
		end
	elseif GetNumPartyMembers() > 0 then
		for index = 1, MAX_PARTY_MEMBERS + 1 do
			if GetMasterLootCandidate(index) == player then
				return index
			end
		end
	end
	return nil
end

function MooLoot:GiveRandom(item)
	local id, player = self:GetRandomCandidate()
	if id ~= nil then
		self:GiveLootToCandidate(id, player, item, "random")
	else
		self:Print("Random lookup failed, try again")
	end
end

function MooLoot:GiveLoot(player, item, message)
	if self.rollActive then
		self:Print("Wait for current roll to end first")
	else
		local id = self:GetLootCandidate(player)
		if id ~= nil then
			self:GiveLootToCandidate(id, player, item, message)
		else
			self:Print("Player " .. player .. " cannot receive that item")
		end
	end
end

function MooLoot:GiveLootToCandidate(candidateIndex, player, item, message)
	assert(item)
	assert(player)
	local dialog = StaticPopup_Show("MooLoot_Confirm", item.link, player)
	if dialog then
		dialog.data = { player = player, item = item, candidateIndex = candidateIndex, message = message or nil }
	end
end

function MooLoot:CanHaveLoot(unitId)
	assert(unitId)
	local player = UnitName(unitId)
	if self.db.enableDebug and (UnitName("player") == player or UnitInRaid(player) or UnitInParty(player)) then
		if self.canHaveLootSpammed == nil then
			self:Trace("CanHaveLoot will return true because debug is enabled and the player is in the group")
			self.canHaveLootSpammed = true
		end
		return true
	end
	return self:GetLootCandidate(player) ~= nil
end

function MooLoot:GetClassColor(class)
	local colors = {
		DEATHKNIGHT = { 0.77, 0.12, 0.23 },
		DRUID = { 1.00, 0.49, 0.04 },
		HUNTER = { 0.67, 0.83, .45 },	
		MAGE = { 0.41, 0.80, 0.94 },
		PALADIN = { 0.96, 0.55, 0.73 },
		PRIEST = { 1.00, 1.00, 1.00 },
		ROGUE = { 1.00, 0.96, 0.41 },
		SHAMAN = { 0.14, 0.35, 1.00  },
		WARLOCK = { 0.58, 0.51, 0.79 },
		WARRIOR = { 0.78, 0.61, 0.43 },
	}
	return colors[class] or nil
end

function MooLoot:BuildPlayerMenu(level, value, item, player, func, append)
	local eligible = self:CanHaveLoot(player)
	local _,class = UnitClass(player)
	local color = eligible and self:GetClassColor(class) or { nil, nil, nil }
	local warn = false
	if not UnitIsConnected(player) then
		warn = L["Offline?"]
	elseif not UnitInRange(player) then
		warn = L["Out of range?"]
	end
	local text = "[" .. (UnitLevel(player) or "??") .. "] " .. player .. (append or "") .. (warn and " (" .. warn .. ")" or "")
	func = func or function() self:GiveLoot(player, item) end
	Dewdrop:AddLine(
		"text", text,
		"func", func,
		"value", player,
		"textR", color[1] or nil,
		"textG", color[2] or nil,
		"textB", color[3] or nil,
		"disabled", not eligible
	)
end

function MooLoot:BuildClassMenus(level, value, item)
	local classes = {}
	if GetNumRaidMembers() > 0 then
		for index = 1, GetNumRaidMembers() do
			local player, rank, subgroup, plevel, rclass, fileName, zone, online, isDead, role, isML = GetRaidRosterInfo(index);
			local lclass,class = UnitClass("raid" .. index)
			if classes[class] == nil then
				classes[class] = {}
			end
			table.insert(classes[class], { class = class, lclass = lclass, player = player })
		end
	else
		local targets = { "player", "party1", "party2", "party3", "party4" }
		for _,target in ipairs(targets) do
			if UnitExists(target) then
				local lclass,class = UnitClass(target)
				if classes[class] == nil then
					classes[class] = {}
				end
				table.insert(classes[class], { class = class, lclass = lclass, player = UnitName(target) })
			end
		end
	end
	if level == 1 then
		for class,v in pairs(classes) do
			local color = self:GetClassColor(class)
			Dewdrop:AddLine(
				"text", v[1].lclass or class,
				"textR", color[1],
				"textG", color[2],
				"textB", color[3],
				"value", class,
				"hasArrow", true
			)			
		end
	elseif level == 2 then
		for _,v in ipairs(classes[value] or {}) do
			self:BuildPlayerMenu(level, value, item, v.player)
		end
	end
	self.classes = classes
end

function MooLoot:BuildRollsMenu(level, value, item)
	if level == 2 then
		for _,v in ipairs(item.rolls) do
			self:BuildPlayerMenu(level, value, item, v.player, nil, " (" .. v.roll .. ")")	
		end
	end
end

function MooLoot:SetEnchanters(value)
	assert(type(value) == "table")
	self.db.enchanters[self.realm] = value
end

function MooLoot:GetEnchanters()
	if type(self.db.enchanters[self.realm]) == "table" then
		return self.db.enchanters[self.realm]
	end
	return {}
end

function MooLoot:GetAvailableEnchanters()
	local enchanters = {}
	for _,v in ipairs(self:GetEnchanters()) do
		if self:CanHaveLoot(v) then
			table.insert(enchanters, v)
		end
	end
	return enchanters
end

function MooLoot:ScanBoE(item)
	GameTooltip:SetHyperlink(item.link)
	local boe = self:ScanToolTip(ITEM_BIND_ON_EQUIP, 2, 4)
	GameTooltip:Hide()
	return boe
end

function MooLoot:ScanToolTip(find, a, b)
	for i = a or 1, b or GameTooltip:NumLines() do
		local text = _G["GameTooltipTextLeft" .. i]:GetText()
		if text ~= nil then
			self:Trace("SCAN=" .. text)
			if string.find(text, find) ~= nil then
				return true
			end
		end
	end
	return false
end

function MooLoot:ShowLootMenu(frame, index)
	Dewdrop:Open(frame, "children", function(level, value)		
		for _,item in ipairs(self.items) do
			--self:Print("LVL = " .. level .. ", VAL=" .. (value == nil and value or "NIL"))
			if item.index == index then
				if level == 1 then
					Dewdrop:AddLine(
						"text", L["MooLoot"] .. " " .. currentVersion,
						"isTitle", true
					)
					if self.db.enableDebug then
						Dewdrop:AddLine(
							"text", "Warning: Debug enabled!",
							"textR", 1,
							"textG", 0,
							"textB", 0						
						)
					end
					Dewdrop:AddSeparator()
					local r, g, b, hex = GetItemQualityColor(item.quality)
					if item.link then
						Dewdrop:AddLine(
							"text", item.name,
							"tooltipFunc", GameTooltip.SetHyperlink,
							"tooltipArg1", GameTooltip,
							"tooltipArg2", item.link,
							"icon", item.icon,
							"iconWidth", 16,
							"iconHeight", 16,
							"textR", r,
							"textG", g,
							"textB", b,
							"isTitle", true
						)
					else
						Dewdrop:AddLine(
							"text", item.name,
							"textR", r,
							"textG", g,
							"textB", b,
							"isTitle", true
						)
					end
					Dewdrop:AddSeparator()
					Dewdrop:AddLine(
						"text", self:IsRollPaused() and L["Roll paused"] or self.rollActive and L["Roll ending in "] .. self:FormatTimeLeft() or L["Start new roll"],
						"icon", "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
						"func", function() self:StartRoll(item) end,
						"disabled", self.rollActive
					)
					Dewdrop:AddLine(
						"text", self:IsRollPaused() and L["Resume"] or L["Pause"],
						"func", function()
									if self:IsRollPaused() then
										self:ResumeRoll(nil, true)
									else
										self:PauseRoll()
									end
								end,
						"disabled", not self.rollActive
					)
					Dewdrop:AddLine(
						"text", L["End current roll now"],
						"func", function() self:EndRoll() end,
					--	"icon", "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
						"disabled", not self.rollActive
					)
					Dewdrop:AddSeparator()
					if #(item.rolls) > 0 then
						self:BuildPlayerMenu(level, value, item, item.rolls[1].player, nil, " (" .. item.rolls[1].roll .. ")")
					else
						Dewdrop:AddLine(
							"text", L["No roll data found"],
							"func", function() self:StartRoll(item) end,
							"disabled", true
						)
					end
					Dewdrop:AddSeparator()
					Dewdrop:AddLine(
						"text", L["Rolls"],
						"value", "rolls",
						"disabled", #(item.rolls) < 1,
						"hasArrow", true
					)	
					Dewdrop:AddSeparator()
					Dewdrop:AddLine(
						"text", L["Disenchant"],
						"value", "disenchant",
						"hasArrow", true
					)
					Dewdrop:AddLine(
						"text", L["More"],
						"value", "more",
						"hasArrow", true
					)
					Dewdrop:AddSeparator()
					self:BuildClassMenus(level, value, item)
					Dewdrop:AddSeparator()
					Dewdrop:AddLine(
						"text", L["Close"],
						"func", function() Dewdrop:Close() end
					)
				elseif level == 2 then
					if value == "disenchant" then
						Dewdrop:AddLine(
							"text", L["Give to any enchanter"],
							"func", function()
								local enchanters = self:GetAvailableEnchanters()
								if #(enchanters) > 0 then
									self:GiveLoot(enchanters[1], item, "disenchant")
								else
									self:Print(L["No enchanters found!"])
								end
							end
						)
						--[[ this doesn't work too well as the lootframe will close when you target someone
						     maybe make another raid menu here?
						Dewdrop:AddLine(
							"text", "My target is an enchanter",
							"func", function()
								if self:CanHaveLoot("target") then
									if self.db.enchanters[self.realm] == nil then
										self.db.enchanters[self.realm] = {}
									end
									table.insert(self.db.enchanters[self.realm], (UnitName("target")) )
								else
									self:Print("You have no valid target!")
								end
							end
						)]]
						local enchanters = self:GetAvailableEnchanters()
						if #(enchanters) > 0 then
							Dewdrop:AddSeparator()
							for _,v in ipairs(enchanters) do
								self:BuildPlayerMenu(level, value, item,v)
							end
						else	
							Dewdrop:AddLine("text", L["No known enchanters in this group"], "disabled", true)
							Dewdrop:AddLine("text", L["You can add enchanters from the MooLoot options dialog"], "disabled", true)
						end
					elseif value == "more" then
						Dewdrop:AddLine(
							"text", L["Give to random"],
							"func", function() self:GiveRandom(item) end,
							"disabled", self.rollActive
						)
						Dewdrop:AddLine(
							"text", L["Give to self"],
							"func", function() self:GiveLoot(UnitName("player"), item) end,
							"disabled", self.rollActive or not self:CanHaveLoot("player")
						)
						Dewdrop:AddLine(
							"text", L["Give to target"],
							"func", function() self:GiveLoot(UnitName("target"), item) end,
							"disabled", self.rollActive or not self:CanHaveLoot("target")
						)
						Dewdrop:AddSeparator()
						Dewdrop:AddLine(
							"text", L["Announce all loot"],		
							"func", function()
								self:FormatToChat("announce", { items = self:ItemsToString(self.items), boss = UnitName("target") or "Unknown" })
							end
						)
						Dewdrop:AddSeparator()
						Dewdrop:AddLine(
							"text", L["Start offspec roll"],
							"func", function() self:StartRoll(item, 2) end,
							"disabled", self.rollActive
						)
						Dewdrop:AddLine(
							"text", L["Start free for all roll"],
							"func", function() self:StartRoll(item, 2, "all") end,
							"disabled", self.rollActive
						)
					elseif value == "rolls" then
						self:BuildRollsMenu(level, value, item)
					elseif self.classes[value] ~= nil then
						self:BuildClassMenus(level, value, item)
					end
				end
				return
			end
		end
		-- Shouldn't get here...
		Dewdrop:AddLine("text", L["Item not found"] .. " (probably a bug)")
	end)
end

function MooLoot:ItemsToString(items)
	local result = {}
	for _,v in ipairs(items) do
		table.insert(result, v.link or v.name)
	end
	return table.concat(result, " ")
end

function MooLoot:HookLootButton(index)
	local button = _G["XLootButton" .. index] or _G["LootButton" .. index]
	if button ~= nil then
		local onClick = button:GetScript("OnClick")
		button:SetScript("OnClick", function(frame, button, down)
			if button == "RightButton" and not IsControlKeyDown() then
				self:ShowLootMenu(frame, index)
			elseif onClick then
				onClick(frame, button, down)
			end
		end)
	else
		self:Trace("Hook button #" .. index .." failed")
	end
end

function MooLoot:AnnounceLoot(items)
	local items = items or self.items
	if #(items) > 0 then
		self:FormatToChat("announce", { items = self:ItemsToString(items), boss = self.lootSource })
		if self.db.boeWarning then
			for _,item in ipairs(items) do
				if self:ScanBoE(item) then
					self:FormatToChat("boe", { item = item.link })
				end
			end
		end
	end
end

function MooLoot:LOOT_OPENED()
	self:Trace("LOOT_OPENED")
	if not self:IsMasterLooter() and not self.db.enableDebug then
		return
	end
	local old = {}
	local items = {}
	local announce = self.db.autoAnnounce
	local threshold = GetLootThreshold()
	for _,item in ipairs(self.items) do
		if item.time + self.db.rememberLootFor > time() then
			table.insert(old, item)
		end
	end
	for index = 1, GetNumLootItems() do
		local icon, name, quantity, quality, locked = GetLootSlotInfo(index)
		local link = GetLootSlotLink(index)
		if (quality >= threshold or self.db.enableDebug) and link and not locked then
			self:Trace("Loot found: " .. name .. " - " .. link .. " - " .. icon .. ", index = " .. index)
			local item = {
				time = time(),
				index = index,
				icon = icon,
				name = name,
				quantity = quantity,
				quality = quality,
				locked =  locked,
				link = link,
				rolls = {}
			}
			for i,v in ipairs(old) do
				if v.link == link then
					item.rolls = v.rolls
					table.remove(old, i)
					announce = false
				end
			end
			table.insert(items, item)
			self:HookLootButton(index)
		else
			--self:Trace("Loot below threshold: " .. name .. " - " .. link .. ", th = " .. threshold)
		end
	end
	self.items = items
	self.lootSource = UnitName("target") or "Unknown"
	if announce then
		self:AnnounceLoot()
	end
end

function MooLoot:LOOT_CLOSED()
	self:Trace("LOOT_CLOSED")
end

function MooLoot:PARTY_LOOT_METHOD_CHANGED()
	self:Trace("PARTY_LOOT_METHOD_CHANGED")
end
