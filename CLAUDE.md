# Project: Tesla Powerwall Tidbyt Dashboard

## Workflow Rules
- Always include the PR link after committing and pushing changes.
- Commit and push after completing each logical chunk of work.
- Run syntax/render checks before committing when possible.

## Project Structure
- `powerwall_tidbyt.star` — Starlark rendering app for Tidbyt (64x32 pixel LED display), rendered via `pixlet` CLI
- `powerwall_push.py` — Python orchestrator that fetches data from Home Assistant / Tesla APIs and pushes renders to Tidbyt

## Technical Notes
- Starlark has no `%02x`, no `sin()`/`cos()`, no floating-point hex formatting
- All pixel coordinates are integers
- Display is 64x32 pixels: col1 (20px), col2 (22px), col3 (22px)
- Use named constants instead of magic numbers
- Keep code DRY — extract repeated patterns into constants or helpers
