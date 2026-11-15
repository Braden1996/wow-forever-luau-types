---@meta _
---@alias DrawLayer
---|"BACKGROUND"
---|"ARTWORK"

---@alias CVar string
---|"autoLootDefault"
---|"Sound_EnableAllSound"

---@alias ItemInfo number|string

---@class BaseInfo
---@field id number
---@field name string

---@class RichInfo : BaseInfo
---@field level number
---@field tags string[]
---@field byKey table<string, boolean>
---@field private secret number
---@field [string] any

---@param callback fun(id: number, ...: string): boolean
---@param ... number
---@return string first
---@return number ...
function DemoVarargs(callback, ...) end

---@generic T
---@param list T[]
---@return T? first
function DemoFirst(list) end

---@param layer DrawLayer
---@param cvar CVar
---@param item ItemInfo
---@param flag true|"yes"|nil
---@param anything any
---@return table|nil result
function DemoUnions(layer, cvar, item, flag, anything) end

---@param info RichInfo
---@param missing UndefinedType
function DemoClasses(info, missing) end

---@param end string
---@param async async fun(): integer
function DemoReserved(end, async) end
