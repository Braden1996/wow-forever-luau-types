---@meta _
---[Documentation](https://warcraft.wiki.gg/wiki/API_DemoPrint)
---@param text string
---@param r? number
---@param g? number
---@param b? number
---@overload fun(text: string, color: DemoColor)
function DemoPrint(text, r, g, b) end

---@param seconds number
---@param callback fun()
---@return DemoTimerHandle handle
function NewDemoTimer(seconds, callback) end

---@param id number
---@return string? name
function AnnotatedOnly(id) end

---@return boolean
function RetailOnly() end

---@class DemoColor
---@field r number
---@field g number
---@field b number

---@class DemoTimerHandle
local DemoTimerHandle = {}

---@return boolean cancelled
function DemoTimerHandle:Cancel() end
