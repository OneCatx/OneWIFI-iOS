# UI Glass Polish Implementation Plan

**Goal:** Make the shared OneWIFI shell calmer in light and dark themes, reduce the floating Dock height, and move the remote OTP disconnect action to the card header without changing behavior.

**Architecture:** Reuse the existing `Glass` token layer and `GlassDock` implementation. Keep the current black, white, gray palette and replace only the Dock's rainbow travel rim with a neutral monochrome highlight. Keep the OTP pairing state and callback unchanged; only change its layout and add a widget regression assertion.

**Tech Stack:** Flutter/Dart, Material 3, existing widget tests.

## Global Constraints

- Product UI only; do not change APNs, Live Activity, server, pairing, or version configuration.
- Preserve `remote?.disconnect`, existing semantics, and at least 44 px interactive targets.
- Keep light/dark token symmetry and reserve color for existing semantic error states.
- Work only in `C:\Users\Administrator\.codex\worktrees\ui-glass-polish\IOS`.

## File map

- Modify `test/features/sms/presentation/remote_otp_pairing_tile_test.dart`: add a failing paired-state layout test.
- Modify `test/design/one_design_test.dart`: pin the compact Dock token values.
- Modify `lib/features/sms/presentation/widgets/remote_otp_pairing_tile.dart`: move the disconnect action into the header row.
- Modify `lib/design/one/glass.dart`: lower Dock and indicator tokens.
- Modify `lib/design/one/ultra_glass_dock.dart`: use neutral glass edge highlights instead of rainbow chroma.

## Execution

1. Add the paired-state and compact-Dock assertions and run the two focused test files. Expected: tests fail because the current layout has no header disconnect key and the Dock token is still 64 px.
2. Move the existing disconnect callback into the header, lower the shared Dock tokens, and replace the rainbow rim with a neutral light/dark highlight. Run the focused tests. Expected: all focused tests pass.
3. Run `dart format` on changed Dart files, `flutter analyze`, the focused tests again, `git diff --check`, and inspect `git status --short`.
4. Commit only the UI work after fresh verification.
