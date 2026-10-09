# Agents

The Apple apps of [Assistant Link](https://github.com/assistant-link/assistant-link). The Xcode project is generated
from `project.yml` with XcodeGen; never edit `AssistantLink.xcodeproj`.

## Rules

- Comment only what the code cannot show: never restate what the code does.
- Run `make lint` and `make test` when you are done and fix everything they report.
- Never commit signing identifiers (team IDs, provisioning profiles, certificates). They go in the git-ignored
  `Local.mk`.
