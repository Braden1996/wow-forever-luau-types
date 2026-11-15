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
			Name = "GetDemoSlot",
			Type = "Function",
			RequiresDemoSlot = true,

			Arguments =
			{
				{ Name = "slot", Type = "number", Nilable = false },
			},

			Returns =
			{
				{ Name = "name", Type = "cstring", Nilable = false },
				{ Name = "count", Type = "number", Nilable = false },
			},
		},
		{
			Name = "CheckDemoSlot",
			Type = "Function",
			RequiresDemoArguments = true,

			Arguments =
			{
				{ Name = "slot", Type = "number", Nilable = false },
			},

			Returns =
			{
				{ Name = "valid", Type = "bool", Nilable = false },
			},
		},
		{
			Name = "FindDemo",
			Type = "Function",
			MayReturnNothing = true,

			Arguments =
			{
				{ Name = "name", Type = "cstring", Nilable = false },
			},

			Returns =
			{
				{ Name = "demoID", Type = "number", Nilable = false },
				{ Name = "owner", Type = "cstring", Nilable = true },
			},
		},
		{
			Name = "NotInClient",
			Type = "Function",
		},
	},

	Predicates =
	{
		{
			Name = "RequiresDemoSlot",
			Type = "Precondition",
			FailureMode = "ReturnNothing",
		},
		{
			Name = "RequiresDemoArguments",
			Type = "Precondition",
			FailureMode = "Error",
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
