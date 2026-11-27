--!strict
-- Draws .github/banner.svg: the emblem, the wordmark, a typed line of addon code and live coverage
-- numbers. Regenerated with the definitions, so the numbers always match the release.

local Build = require("./build")

local Banner = {}

type Attrs = { [string]: string | number }

-- Escapes text for XML: attribute values and element text both go through it.
local function escapeXml(text: string): string
	return (string.gsub(text, '[&<>"]', { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

local function attrs(t: Attrs): string
	local keys = {}
	for k in t do
		table.insert(keys, k)
	end
	table.sort(keys)
	local parts = {}
	for _, k in keys do
		table.insert(parts, string.format('%s="%s"', k, escapeXml(tostring(t[k]))))
	end
	return table.concat(parts, " ")
end

-- An element with escaped text content, or empty (`<name .../>`) without `text`.
local function el(name: string, a: Attrs, text: string?): string
	if text then
		return "<" .. name .. " " .. attrs(a) .. ">" .. escapeXml(text) .. "</" .. name .. ">"
	end
	return "<" .. name .. " " .. attrs(a) .. "/>"
end

-- An element whose content is already markup (child elements).
local function parent(name: string, a: Attrs, children: string): string
	return "<" .. name .. " " .. attrs(a) .. ">" .. children .. "</" .. name .. ">"
end

type Stop = { offset: number, color: string, opacity: number? }

local function gradient(id: string, kind: string, stops: { Stop }, extra: Attrs): string
	local body = {}
	for _, s in stops do
		local stop: Attrs = { offset = s.offset, ["stop-color"] = s.color }
		if s.opacity then
			stop["stop-opacity"] = s.opacity
		end
		table.insert(body, "      " .. el("stop", stop))
	end
	local a = table.clone(extra)
	a.id = id
	return "    <" .. kind .. " " .. attrs(a) .. ">\n" .. table.concat(body, "\n") .. "\n    </" .. kind .. ">"
end

local function thousands(n: number): string
	local s = tostring(math.floor(n))
	local out = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	return (string.gsub(out, "^,", ""))
end

local MONO = "'JetBrains Mono','Cascadia Code',Consolas,monospace"
local SANS = "'Segoe UI','Inter','Helvetica Neue',Arial,sans-serif"

-- summary: report.summary (category -> { typed, untyped, excluded }).
function Banner.svg(summary: { [Build.Category]: Build.StatusCounts }): string
	local lines = {
		'<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="400" viewBox="0 0 1280 400" role="img" aria-labelledby="title desc">',
		'  <title id="title">wow-forever-luau-types</title>',
		'  <desc id="desc">Strict Luau type definitions for the World of Warcraft: Forever API</desc>',
		"  <defs>",
		gradient("bg", "linearGradient", {
			{ offset = 0, color = "#0b1022" },
			{ offset = 0.55, color = "#121a3a" },
			{ offset = 1, color = "#1d1440" },
		}, { x1 = 0, y1 = 0, x2 = 1, y2 = 1 }),
		gradient(
			"glow",
			"radialGradient",
			{ { offset = 0, color = "#00a2ff", opacity = 0.55 }, { offset = 1, color = "#00a2ff", opacity = 0 } },
			{ cx = 0.5, cy = 0.5, r = 0.5 }
		),
		gradient(
			"gold",
			"linearGradient",
			{ { offset = 0, color = "#ffe7a3" }, { offset = 1, color = "#d9a441" } },
			{ x1 = 0, y1 = 0, x2 = 0, y2 = 1 }
		),
		gradient(
			"blue",
			"linearGradient",
			{ { offset = 0, color = "#5ec8ff" }, { offset = 1, color = "#2f6bff" } },
			{ x1 = 0, y1 = 0, x2 = 1, y2 = 1 }
		),
		'    <pattern id="grid" width="32" height="32" patternUnits="userSpaceOnUse">',
		"      " .. el("path", { d = "M32 0H0V32", fill = "none", stroke = "#ffffff", ["stroke-opacity"] = 0.04 }),
		"    </pattern>",
		"  </defs>",
		"  " .. el("rect", { width = 1280, height = 400, fill = "url(#bg)" }),
		"  " .. el("rect", { width = 1280, height = 400, fill = "url(#grid)" }),
		"  " .. el("circle", { cx = 250, cy = 200, r = 230, fill = "url(#glow)" }),
	}

	-- Emblem: a Luau-style tilted square inside a ring with four rune points.
	table.insert(lines, '  <g transform="translate(250 200)">')
	table.insert(
		lines,
		"    "
			.. el(
				"circle",
				{ r = 132, fill = "none", stroke = "url(#gold)", ["stroke-width"] = 3, ["stroke-opacity"] = 0.85 }
			)
	)
	table.insert(lines, "    " .. el("circle", {
		r = 118,
		fill = "none",
		stroke = "url(#gold)",
		["stroke-width"] = 1,
		["stroke-opacity"] = 0.5,
		["stroke-dasharray"] = "2 10",
	}))
	for _, angle in { 0, 90, 180, 270 } do
		table.insert(lines, "    " .. el("path", {
			d = "M0 -150 L7 -136 L0 -122 L-7 -136 Z",
			fill = "url(#gold)",
			["fill-opacity"] = 0.9,
			transform = "rotate(" .. angle .. ")",
		}))
	end
	table.insert(lines, '    <g transform="rotate(-15)">')
	table.insert(
		lines,
		"      " .. el("rect", { x = -70, y = -70, width = 140, height = 140, rx = 10, fill = "url(#blue)" })
	)
	table.insert(lines, "      " .. el("rect", { x = 22, y = -58, width = 36, height = 36, rx = 4, fill = "#0b1022" }))
	table.insert(lines, "    </g>")
	table.insert(lines, "    " .. el("text", {
		x = -6,
		y = 30,
		["font-family"] = MONO,
		["font-size"] = 54,
		["font-weight"] = 700,
		fill = "#0b1022",
		["text-anchor"] = "middle",
	}, ": T"))
	table.insert(lines, "  </g>")

	-- Wordmark.
	table.insert(lines, "  " .. el("text", {
		x = 470,
		y = 150,
		["font-family"] = SANS,
		["font-size"] = 64,
		["font-weight"] = 700,
		fill = "#ffffff",
		["letter-spacing"] = -1,
	}, "wow-forever-luau-types"))
	table.insert(
		lines,
		"  "
			.. el(
				"text",
				{ x = 472, y = 198, ["font-family"] = SANS, ["font-size"] = 25, fill = "#c7d2fe" },
				"Strict Luau type definitions for the World of Warcraft: Forever API"
			)
	)

	-- A typed line of addon code, syntax-coloured.
	local tokens = {
		{ "local", "#c678dd" },
		{ " frame", "#e5e7eb" },
		{ ": ", "#9ca3af" },
		{ "Button", "#5ec8ff" },
		{ " = ", "#9ca3af" },
		{ "CreateFrame", "#ffe7a3" },
		{ "(", "#e5e7eb" },
		{ '"Button"', "#98c379" },
		{ ")", "#e5e7eb" },
	}
	local spans = {}
	for _, t in tokens do
		table.insert(spans, el("tspan", { fill = t[2] }, t[1]))
	end
	table.insert(lines, "  " .. el("rect", {
		x = 470,
		y = 228,
		width = 580,
		height = 60,
		rx = 10,
		fill = "#0b1022",
		["fill-opacity"] = 0.75,
		stroke = "#2f6bff",
		["stroke-opacity"] = 0.5,
	}))
	table.insert(
		lines,
		"  " .. parent("text", { x = 494, y = 266, ["font-family"] = MONO, ["font-size"] = 22 }, table.concat(spans))
	)

	-- Live numbers.
	local f = summary.functions
	local m = summary.widgetMethods
	local e = summary.events
	local stats = string.format(
		"%s typed functions  ·  %s typed widget methods  ·  %s events with payload types",
		thousands(f.typed),
		thousands(m.typed),
		thousands(e.typed)
	)
	table.insert(
		lines,
		"  " .. el("text", { x = 472, y = 340, ["font-family"] = SANS, ["font-size"] = 20, fill = "#ffe7a3" }, stats)
	)
	table.insert(lines, "</svg>")
	return table.concat(lines, "\n") .. "\n"
end

return Banner
