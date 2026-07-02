## Code Signing

Always use Apple identity signing. Never use ad-hoc signing. All builds must be signed with a valid Apple Developer certificate.

## Releases

- Version is defined in `project.yml`
- Release artifacts go in `dist/{version}/` — DMG and ZIP
- GitHub releases at https://github.com/nickshatilo/snapper/releases
- Tag format: `v{major}.{minor}` (e.g. `v1.1`)
- DMG naming: `Snapper-{version}.dmg` (e.g. `Snapper-1.1.0.dmg`)
- **Website**: After a release, update `downloadUrl` in `website/src/pages/index.astro` to point to the new DMG

## Website

- Astro static site in `website/`
- Domain: snapper.tools
- Docker build: `cd website && docker build -t snapper-site .`
