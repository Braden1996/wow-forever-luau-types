// Site-wide helpers safe to use from both pages and browser islands.

/** Prefixes a site path (`/api/`) with the deploy base (`/wow-forever-luau-types/`). */
export function withBase(path: string): string {
  const base = import.meta.env.BASE_URL.replace(/\/$/, "");
  return `${base}${path.startsWith("/") ? path : `/${path}`}`;
}

export const REPOSITORY = "https://github.com/Braden1996/wow-forever-luau-types";
