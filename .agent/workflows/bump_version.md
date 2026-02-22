---
description: Steps to bump the application version
---

# Bumping Application Version

When you need to release a new version of the app, follow this checklist to ensure consistency across the codebase.

1.  **Determine New Version**: Decide on the next semantic version (e.g., `v0.1.2` -> `v0.1.3`).
2.  **Update Source Code**:
    - [ ] `ios/Fletcher/Fletcher.xcodeproj/project.pbxproj`: Update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
3.  **Update Documentation**:
    - [ ] `artifacts/changelog.md`: Create a new section for the new version and move Unreleased items under it.
4.  **Verification**:
    - [ ] Run the app (checklist: Splash Screen shows new version).
    - [ ] Check Settings (checklist: Footer shows new version).
5.  **Commit**:
    - [ ] `git commit -m "chore: bump version to vX.Y.Z"`
