// Starter snippets for the playground. Each one type-checks against the definitions as the comments say.

export interface Example {
  readonly id: string;
  readonly label: string;
  readonly code: string;
}

export const EXAMPLES: readonly Example[] = [
  {
    id: "quests",
    label: "Quest log",
    code: `--!strict
-- C_QuestLog.GetInfo returns QuestInfo? : narrow it before use.
for index = 1, C_QuestLog.GetNumQuestLogEntries() do
\tlocal info = C_QuestLog.GetInfo(index)
\tif info and not info.isHeader then
\t\tprint(info.title, info.level)
\tend
end

-- Hover a name to see its type. Try deleting the \`if info\` check.
`,
  },
  {
    id: "events",
    label: "Typed events",
    code: `--!strict
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LEVEL_UP")

-- EventHandler<"NAME"> is the handler type for one event.
local onLevelUp: EventHandler<"PLAYER_LEVEL_UP"> = function(level: number, healthDelta: number)
\tprint("Reached level", level, "gained", healthDelta, "health")
end

frame:SetScript("OnEvent", function(_self, event: string, ...: any)
\tif event == "PLAYER_LEVEL_UP" then
\t\tonLevelUp(...)
\tend
end)
`,
  },
  {
    id: "widgets",
    label: "Widgets",
    code: `--!strict
-- CreateFrame is generic: "Button" gives a Button.
local button = CreateFrame("Button", nil, UIParent)
button:SetSize(120, 24)
button:SetPoint("CENTER")
button:SetText("Hello")
button:SetScript("OnClick", function()
\tprint("clicked")
end)

local texture = button:CreateTexture(nil, "ARTWORK")
texture:SetAllPoints()
`,
  },
  {
    id: "errors",
    label: "Caught mistakes",
    code: `--!strict
-- Each line below is an error the definitions catch.
GetQuestLogTitle(1) -- not in WoW: Forever: use C_QuestLog.GetInfo

local frame = CreateFrame("Frame")
frame:SetScript("OnClick", function() end) -- a Frame has no OnClick handler

frame:RegisterEvent("NOT_AN_EVENT") -- not a FrameEvent

local count: string = C_QuestLog.GetNumQuestLogEntries() -- returns a number
`,
  },
  {
    id: "untyped",
    label: "Untyped APIs",
    code: `--!strict
-- FrameXML functions with no type source return unknown: cast what you know.
local key = GetBindingKeyForAction("JUMP") :: string?
if key then
\tprint("Jump is bound to", key)
end
`,
  },
];

export const DEFAULT_EXAMPLE = EXAMPLES[0]?.code ?? "--!strict\n";
