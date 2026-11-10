## Code Signing

Always use Apple identity signing. Never use ad-hoc signing. All builds must be signed with a valid Apple Developer certificate.

## Releases

- Version is defined in `project.yml` (`MARKETING_VERSION`); bump `CURRENT_PROJECT_VERSION` with it to `major*10000 + minor*100 + patch` (e.g. `1.8.1` → `10801`) — the release workflow checks they match
- Release artifacts go in `dist/{version}/` — DMG and ZIP
- GitHub releases at https://github.com/nickshatilo/snapper/releases
- Tag format: `v{major}.{minor}.{patch}` (e.g. `v1.5.0`)
- DMG naming: `Snapper-{version}.dmg` (e.g. `Snapper-1.1.0.dmg`)
- **Website**: `downloadUrl` in `website/src/pages/index.astro` uses the stable `Snapper-latest.dmg` release asset; every release must publish that alias alongside the versioned DMG

## Website

- Astro static site in `website/`
- Domain: snapper.tools
- Docker build (from the repo root, where the `Dockerfile` lives): `docker build -t snapper-site .`
