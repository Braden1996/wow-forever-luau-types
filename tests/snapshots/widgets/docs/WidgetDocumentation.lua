local SimpleFrameScriptObjectAPI =
{
	Name = "SimpleFrameScriptObjectAPI",
	Type = "ScriptObject",
	Environment = "All",

	Functions =
	{
		{
			Name = "GetName",
			Type = "Function",

			Returns =
			{
				{ Name = "name", Type = "cstring", Nilable = true },
			},
		},
		{
			Name = "SetScript",
			Type = "Function",

			Arguments =
			{
				{ Name = "scriptTypeName", Type = "cstring", Nilable = false },
				{ Name = "script", Type = "luaFunction", Nilable = true },
			},
		},
	},

	Events =
	{
	},

	Tables =
	{
	},
};

local SimpleScriptRegionResizingAPI =
{
	Name = "SimpleScriptRegionResizingAPI",
	Type = "ScriptObject",
	Environment = "All",

	Functions =
	{
		{
			Name = "SetPoint",
			Type = "Function",

			Arguments =
			{
				{ Name = "point", Type = "FramePoint", Nilable = false },
				{ Name = "relativeTo", Type = "ScriptRegion", Nilable = false },
				{ Name = "relativePoint", Type = "FramePoint", Nilable = false },
				{ Name = "offsetX", Type = "uiUnit", Nilable = false },
				{ Name = "offsetY", Type = "uiUnit", Nilable = false },
			},
		},
	},

	Events =
	{
	},

	Tables =
	{
	},
};

local SimpleFrameAPI =
{
	Name = "SimpleFrameAPI",
	Type = "ScriptObject",
	Environment = "All",

	Functions =
	{
		{
			Name = "RegisterEvent",
			Type = "Function",

			Arguments =
			{
				{ Name = "eventName", Type = "cstring", Nilable = false },
			},

			Returns =
			{
				{ Name = "registered", Type = "bool", Nilable = false },
			},
		},
	},

	Events =
	{
	},

	Tables =
	{
	},
};

APIDocumentation:AddDocumentationTable(SimpleFrameScriptObjectAPI);
APIDocumentation:AddDocumentationTable(SimpleScriptRegionResizingAPI);
APIDocumentation:AddDocumentationTable(SimpleFrameAPI);
