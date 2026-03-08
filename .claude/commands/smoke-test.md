Generate a smoke test checklist for the current changes:

1. Run `git diff --name-only` to see what files changed
2. Map each changed file to the user flows it affects
3. Output a numbered checklist with specific steps to test on-device
4. Include dark mode check if any UI files changed
5. Always end with: flutter analyze, no crash on launch, physical device test
