# Terrain GN mobile app

Flutter client (Android, iOS, web) in French and English. Setup, run and test instructions are in the [root README](../README.md).

- `lib/theme.dart`: design tokens (colors, spacing, radius). Swap these for the Figma values.
- `lib/l10n/app_fr.arb`, `app_en.arb`: all user-facing strings.
- `lib/api.dart`: API client with timeouts, retries only for requests that are safe to repeat, and a shared token refresh.
