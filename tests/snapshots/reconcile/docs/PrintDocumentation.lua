local Print =
{
	Name = "Print",
	Type = "System",
	Environment = "All",

	Functions =
	{
		{
			Name = "DemoPrint",
			Type = "Function",

			Arguments =
			{
				{ Name = "text", Type = "cstring", Nilable = false },
				{ Name = "r", Type = "number", Nilable = false },
				{ Name = "g", Type = "number", Nilable = false },
				{ Name = "b", Type = "number", Nilable = false },
			},
		},
		{
			Name = "NewDemoTimer",
			Type = "Function",

			Arguments =
			{
				{ Name = "seconds", Type = "number", Nilable = false },
				{ Name = "callback", Type = "DemoTimerCallback", Nilable = false },
			},

			Returns =
			{
				{ Name = "handle", Type = "DemoTimerCallback", Nilable = false },
			},
		},
		{
			Name = "DocumentedOnly",
			Type = "Function",

			Returns =
			{
				{ Name = "ready", Type = "bool", Nilable = false },
			},
		},
		{
			Name = "NotInClient",
			Type = "Function",
		},
	},

	Events =
	{
	},

	Tables =
	{
		{
			Name = "DemoTimerCallback",
			Type = "CallbackType",

			Arguments =
			{
				{ Name = "handle", Type = "DemoTimerHandle", Nilable = false },
			},
		},
	},
};

APIDocumentation:AddDocumentationTable(Print);
