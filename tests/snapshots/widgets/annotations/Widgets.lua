---@meta _
---@alias FramePoint
---|"CENTER"
---|"TOP"

---@alias FrameType
---|"Frame"
---|"Button"
---|"NotAClientWidget"

---@class ScriptRegionResizing : Object
local ScriptRegionResizing = {}

---@param point FramePoint
---@param relativeTo? any
---@param relativePoint? FramePoint
---@param offsetX? number
---@param offsetY? number
---@overload fun(self, point: FramePoint, ofsx?: number, ofsy?: number)
function ScriptRegionResizing:SetPoint(point, relativeTo, relativePoint, offsetX, offsetY) end

---@class Region : ScriptRegion, ScriptRegionResizing
local Region = {}

---@param layer string
function Region:SetDrawLayer(layer) end

---@class Button : Frame
local Button = {}

---@param text string?
function Button:SetText(text) end

---@generic T
---@param frameType `T` | FrameType
---@param name? string
---@return T frame
function CreateFrame(frameType, name) end
