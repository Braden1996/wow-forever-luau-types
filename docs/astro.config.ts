import react from "@astrojs/react";
import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";
import starlightWarcraft from "starlight-warcraft";

import { BASE } from "./src/lib/base.ts";

const repository = "https://github.com/Braden1996/wow-forever-luau-types";

// https://astro.build/config: fully static output for GitHub Pages (project site under /wow-forever-luau-types/).
// Expressive Code's options (themes and the Luau checking plugin) are in ec.config.mjs.
export default defineConfig({
  site: "https://braden1996.github.io",
  base: BASE,
  trailingSlash: "always",
  output: "static",
  compressHTML: true,
  integrations: [
    starlight({
      title: "wow-forever-luau-types",
      description:
        "Strict Luau type definitions for the World of Warcraft: Forever addon API, with a searchable, cross-linked API reference.",
      logo: { src: "./src/assets/logo.svg", alt: "" },
      favicon: "/favicon.svg",
      social: [{ icon: "github", label: "GitHub", href: repository }],
      editLink: { baseUrl: `${repository}/edit/main/docs/` },
      lastUpdated: true,
      credits: false,
      customCss: ["./src/styles/global.css"],
      plugins: [starlightWarcraft()],
      components: {
        Footer: "./src/components/starlight/footer.astro",
        Search: "./src/components/starlight/search.astro",
      },
      head: [{ tag: "meta", attrs: { name: "color-scheme", content: "dark light" } }],
      sidebar: [
        {
          label: "Start here",
          items: [
            { label: "Introduction", link: "/" },
            { slug: "start/getting-started" },
            { slug: "start/first-addon" },
            { slug: "start/addon-template" },
            { slug: "start/editor-setup" },
          ],
        },
        {
          label: "Guides",
          items: [
            { slug: "guides/strict-patterns" },
            { slug: "guides/events" },
            { slug: "guides/widgets" },
            { slug: "guides/saved-variables" },
            { slug: "guides/untyped-apis" },
          ],
        },
        {
          label: "API reference",
          items: [
            { label: "Overview", link: "/api/" },
            { label: "Namespaces", link: "/api/namespaces/" },
            { label: "Global functions and values", link: "/api/globals/" },
            { label: "Widgets and script objects", link: "/api/widgets/" },
            { label: "Events", link: "/api/events/" },
            { label: "Enums", link: "/api/enums/" },
            { label: "Structures and mixins", link: "/api/structures/" },
            { label: "Type aliases", link: "/api/aliases/" },
            { label: "Coverage", link: "/coverage/" },
          ],
        },
        {
          label: "Project",
          items: [
            { slug: "project/how-it-works" },
            { slug: "project/checked-examples" },
            { slug: "project/contributing" },
            { slug: "project/credits" },
          ],
        },
      ],
    }),
    react(),
  ],
});
