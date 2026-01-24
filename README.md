# GradPath

Monorepo for the GradPath project. This top-level `gradpath` repository will contain multiple folders:

- `gradpath_frontend/` — Flutter (web/mobile/desktop) app.
- `gradpath_backend/` — (future) server-side application and APIs.

## Frontend

See `gradpath_frontend/` for the Flutter project. It targets Chrome and other platforms.

### Development

```bash
cd gradpath_frontend
flutter pub get
flutter run -d chrome
```

### Common Tasks
- Hot restart: press `R` in the Flutter run terminal.
- Clean build caches: `flutter clean`.

## Repository Structure and Git

This repository is initialized at the root, so both frontend and backend live under a single Git history. The `.gitignore` in the root excludes Flutter build outputs and platform-specific ephemeral files.

## Next Steps
- Add `gradpath_backend/` when ready.
- Set up CI (e.g., GitHub Actions) for formatting/build checks.
