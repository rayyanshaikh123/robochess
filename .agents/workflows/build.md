---
description: Build Feature
---

# Build Feature

## Process

1. Understand the requested behavior and acceptance criteria.
2. Inspect the existing repository and identify the relevant architecture, modules, components, APIs, state, and tests.
3. Do not modify code during the investigation phase.
4. Identify existing functionality that can be reused instead of creating duplicate implementations.
5. Inspect the provided design and map it to the existing component structure.
6. When framework/library behavior is relevant, consult current official documentation using Context7.
7. Implement the smallest maintainable solution.
8. Follow the language and framework's idioms.
9. Prefer standard-library functionality where appropriate.
10. Avoid unnecessary dependencies.
11. Run relevant tests.
12. If the change affects an API, verify the affected endpoints using Postman when appropriate.
13. Inspect the final git diff.
14. Report what changed, what was tested, and any checks that could not be performed.

## Rules

- Do not rewrite unrelated code.
- Do not invent APIs.
- Do not claim tests passed unless they actually passed.
- Preserve existing behavior outside the requested change.