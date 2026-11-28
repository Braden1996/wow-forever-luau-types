// Base-less site paths for every API symbol. Pages add the deploy base (import.meta.env.BASE_URL) when rendering.

export function globalLetter(name: string): string {
  const first = name.charAt(0).toLowerCase();
  return /[a-z]/.test(first) ? first : "_";
}

export const apiPaths = {
  root: "/api/",
  namespaces: "/api/namespaces/",
  namespace: (name: string): string => `/api/namespaces/${name}/`,
  globals: "/api/globals/",
  globalLetter: (letter: string): string => `/api/globals/${letter}/`,
  global: (name: string): string => `/api/globals/${globalLetter(name)}/#${name}`,
  widgets: "/api/widgets/",
  widget: (name: string): string => `/api/widgets/${name}/`,
  events: "/api/events/",
  event: (name: string): string => `/api/events/${name}/`,
  enums: "/api/enums/",
  enumPage: (name: string): string => `/api/enums/${name}/`,
  structures: "/api/structures/",
  structure: (name: string): string => `/api/structures/${name}/`,
  aliases: "/api/aliases/",
  alias: (name: string): string => `/api/aliases/#${name}`,
} as const;
