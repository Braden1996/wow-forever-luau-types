// Expressive Code options, kept out of astro.config.ts because a plugin is not serializable and the API pages'
// <Code> component needs this file (https://expressive-code.com/key-features/code-component/).
import { defineEcConfig } from "@astrojs/starlight/expressive-code";

import { BASE } from "./src/lib/base.ts";
import { pluginLuauTypesForSite } from "./src/lib/luau/ec-plugin.ts";

export default defineEcConfig({
  themes: ["github-dark-default", "github-light-default"],
  styleOverrides: { borderRadius: "0.25rem" },
  // Every ```luau block is type-checked at build time, with hover types (src/lib/luau/ec-plugin.ts).
  plugins: [pluginLuauTypesForSite(BASE.slice(0, -1))],
});
