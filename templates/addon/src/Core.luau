--!strict
-- The first file in MyAddon.toc: fills in the shared namespace.

local ADDON: string, ns: MyAddonNamespace = ...

ns.version = C_AddOns.GetAddOnMetadata(ADDON, "Version")

function ns.print(message: string)
	DEFAULT_CHAT_FRAME:AddMessage(format("|cff33ff99%s|r: %s", ADDON, message))
end

function ns.load()
	local db = MyAddonDB or { enabled = true, logins = 0 }
	db.logins += 1
	_G.MyAddonDB = db
	ns.db = db
	ns.print(format("v%s loaded (login %d)", ns.version, db.logins))
end
