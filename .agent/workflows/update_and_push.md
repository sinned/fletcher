---
description: Protocol for committing and pushing changes to GitHub
---

# Update and Push Protocol

Use this checklist **EVERY TIME** you are preparing to push changes to the repository.

1.  **Documentation Review**:
    - [ ] **Critical**: Have you updated [changelog.md](file:///Users/dennisyang/Antigravity/fletcher/artifacts/changelog.md) with your recent changes? **Include the Time!**
    - [ ] Updated `README.md` if new features were added?
    - [ ] Updated `walkthrough.md` if visual changes/features were verified?

2.  **Code Check**:
    - [ ] Removed temporary debug print statements?
    - [ ] Verified build passes?

3.  **Git Operations**:
    - [ ] `git add .`
    - [ ] `git commit -m "feat(scope): description"` (Use Conventional Commits)
    - [ ] `git push`

> [!IMPORTANT]
> Never skip the Changelog update. Users rely on it to know what changed.
