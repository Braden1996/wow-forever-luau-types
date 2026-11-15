local WidgetAPI = {
	FrameScriptObject = {
		inherits = {},
		methods = {
			"GetName",
		},
	},
	Object = {
		inherits = {"FrameScriptObject"},
		methods = {
			"GetParent",
		},
	},
	ScriptObject = {
		inherits = {},
		methods = {
			"GetScript",
			"HasScript",
			"HookScript",
			"SetScript",
		},
	},
	ScriptRegion = {
		inherits = {"Object", "ScriptObject"},
		handlers = {
			"OnHide",
			"OnShow",
		},
		methods = {
			"SetPoint",
			"Show",
		},
	},
	Region = {
		inherits = {"Region"},
		methods = {
			"SetDrawLayer",
		},
	},
	Frame = {
		inherits = {"ScriptRegion"},
		handlers = {
			"OnEvent",
		},
		methods = {
			"RegisterEvent",
			"Undocumented",
		},
	},
	Button = {
		inherits = {"Frame"},
		handlers = {
			"OnClick",
		},
		methods = {
			"SetText",
		},
	},
}

return WidgetAPI
