local Demo =
{
	Name = "Demo",
	Type = "System",
	Namespace = "C_Demo",
	Environment = "All",

	Functions =
	{
		{
			Name = "GetInfo",
			Type = "Function",

			Arguments =
			{
				{ Name = "demoID", Type = "number", Nilable = false },
				{ Name = "kind", Type = "DemoKind", Nilable = false, Default = 0 },
			},

			Returns =
			{
				{ Name = "info", Type = "DemoInfoExtended", Nilable = true },
			},
		},
		{
			Name = "ListIDs",
			Type = "Function",

			Returns =
			{
				{ Name = "count", Type = "number", Nilable = false },
				{ Name = "ids", Type = "number", Nilable = false, StrideIndex = 1 },
			},
		},
		{
			Name = "GetNames",
			Type = "Function",

			Returns =
			{
				{ Name = "names", Type = "table", InnerType = "cstring", Nilable = false },
				{ Name = "byID", Type = "table", InnerType = "DemoInfo", KeyType = "number", Nilable = false },
			},
		},
	},

	Events =
	{
		{
			Name = "DemoUpdated",
			Type = "Event",
			LiteralName = "DEMO_UPDATED",
			Payload =
			{
				{ Name = "demoID", Type = "number", Nilable = false },
				{ Name = "name", Type = "cstring", Nilable = true },
			},
		},
		{
			Name = "DemoRetired",
			Type = "Event",
			LiteralName = "DEMO_RETIRED",
		},
	},

	Tables =
	{
		{
			Name = "DemoKind",
			Type = "Enumeration",
			NumValues = 2,
			MinValue = 0,
			MaxValue = 1,
			Fields =
			{
				{ Name = "Small", Type = "DemoKind", EnumValue = 0 },
				{ Name = "Large", Type = "DemoKind", EnumValue = 1 },
			},
		},
		{
			Name = "DemoInfo",
			Type = "Structure",
			Fields =
			{
				{ Name = "demoID", Type = "number", Nilable = false },
				{ Name = "name", Type = "cstring", Nilable = false },
				{ Name = "kind", Type = "DemoKind", Nilable = false },
			},
		},
		{
			Name = "DemoInfoExtended",
			Type = "Structure",
			Fields =
			{
				{ Name = "demoID", Type = "number", Nilable = false },
				{ Name = "name", Type = "cstring", Nilable = false },
				{ Name = "kind", Type = "DemoKind", Nilable = false },
				{ Name = "owner", Type = "WOWGUID", Nilable = true },
			},
		},
		{
			Name = "DemoConstants",
			Type = "Constants",
			Values =
			{
				{ Name = "MAX_DEMOS", Type = "number", Value = Constants.DemoConstants.BASE + 1 },
			},
		},
	},
};

APIDocumentation:AddDocumentationTable(Demo);
