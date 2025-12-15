---
description: Protocol for committing and pushing changes to GitHub
---

# Commit and Push Protocol

This workflow MUST be followed whenever checking code into version control.

1.  **Update Product Requirements Document (PRD)**
    -   Review `artifacts/prd-fletcher-ios-app.md`.
    -   Ensure all new features, UI changes, and configuration updates are reflected.
    -   Update the "Status" or "Date" if necessary.

2.  **Verify Artifacts**
    -   Ensure new assets (icons, etc.) are in the `artifacts/` folder if they are not part of the build bundle but are deliverables.

3.  **Git Operations**
    -   Stage changes: `git add .`
    -   Commit with descriptive message: `git commit -m "Type: Description"`
    -   Push to remote: `git push`
