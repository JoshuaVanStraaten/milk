Run the bug fixer workflow:

1. Read CLAUDE.md and .claude/skills/milk-bug-patterns/SKILL.md
2. Run `flutter analyze` and list all issues
3. Fix each issue one at a time, starting with errors, then warnings
4. After all fixes, run `flutter analyze` again to confirm zero warnings
5. List all files changed and suggest manual tests to run on-device
