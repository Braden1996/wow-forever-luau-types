--!strict
-- Container, item and quest APIs, plus the Lua 5.1 globals WoW adds (strsplit, wipe, tinsert).

local _, ns = ...

local function countFreeSlots(): number
	local free = 0
	for bag = 0, 4 do
		local slots = C_Container.GetContainerNumSlots(bag)
		for slot = 1, slots do
			if C_Container.GetContainerItemInfo(bag, slot) == nil then
				free += 1
			end
		end
	end
	return free
end

local function describeItem(link: string): string
	-- WoW: Forever runs the modern client: item and quest APIs live in C_ namespaces.
	local name, _, quality, itemLevel = C_Item.GetItemInfo(link)
	if name == nil then
		return "(not cached)"
	end
	return format("%s (quality %d, item level %d)", name, quality, itemLevel)
end

local function questTitles(): { string }
	local titles: { string } = {}
	local entries = C_QuestLog.GetNumQuestLogEntries()
	for index = 1, entries do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader then
			tinsert(titles, format("[%d] %s", info.level, info.title))
		end
	end
	return titles
end

local function bindingFor(action: string): string?
	-- GetBindingKeyForAction is a real client function with no type source yet, so it is declared
	-- `(...unknown) -> ...unknown`: its result must be cast before use.
	local key = GetBindingKeyForAction(action) :: string?
	return key
end

local recent: { string } = {}

local function remember(text: string)
	local first, rest = strsplit(" ", strtrim(text), 2)
	tinsert(recent, first)
	if rest then
		tinsert(recent, rest)
	end
	if #recent > 20 then
		wipe(recent)
	end
end

ns.bags = {
	countFreeSlots = countFreeSlots,
	describeItem = describeItem,
	questTitles = questTitles,
	remember = remember,
	bindingFor = bindingFor,
}
