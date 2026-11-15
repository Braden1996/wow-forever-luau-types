# warcraftcn (fork)

A subset of [warcraftcn/ui](https://github.com/TheOrcDev/warcraftcn-ui) by TheOrcDev, forked at commit
`67dfa8e30442ae042b3d63030c17cb00590542ff` under the MIT licence ([LICENSE.md](LICENSE.md)).

| File                     | Upstream (`components/ui/warcraftcn/`) | Changes                                                       |
| ------------------------ | -------------------------------------- | ------------------------------------------------------------- |
| `button.tsx`             | `button.tsx`                           | strict TypeScript props, relative imports                     |
| `card.tsx`               | `card.tsx`                             | strict TypeScript props, smaller header padding               |
| `badge.tsx`              | `badge.tsx`                            | no faction variant; renders a `span`                          |
| `input.tsx`              | `input.tsx`                            | strict TypeScript props                                       |
| `skeleton.tsx`           | `skeleton.tsx`                         | default look only                                             |
| `spinner.tsx`            | `spinner.tsx`                          | strict TypeScript props                                       |
| `warcraft.css`           | `styles/warcraft.css`                  | used classes only, local textures, self-hosted Cinzel         |
| `assets/*.webp`          | `assets/`                              | unchanged (frame textures drawn for warcraftcn, not game art) |
| `assets/spinner-path.ts` | `assets/`                              | unchanged                                                     |

The site's other components (`../api`, `../playground`, `../search`, `../starlight`) are this project's own. To update
the fork, copy the files from a newer upstream commit and re-apply the changes listed above.
