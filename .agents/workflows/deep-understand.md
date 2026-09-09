---
description: Deep Understand
---



Do not modify code.

## Investigation

1. Identify the target module and its role in the application.
2. Find all entry points into the module.
3. Trace the call graph through relevant layers.
4. Identify dependencies and dependents.
5. Trace important data flows.
6. Identify state changes and side effects.
7. Identify database interactions.
8. Identify external APIs/services.
9. Identify authentication and authorization boundaries.
10. Identify error handling and failure paths.
11. Identify concurrency/asynchronous behavior where applicable.
12. Inspect relevant tests.
13. Identify configuration and environment dependencies.

## Explanation

After investigation, explain:

- What the module does.
- Why it exists.
- How execution enters it.
- How data moves through it.
- What other modules it depends on.
- What depends on it.
- Important side effects.
- Failure modes.
- Security boundaries.
- Important assumptions.
- Current technical debt.

Use concrete file names, classes, functions, and symbols from the repository.

Do not invent behavior that cannot be established from the code or documentation.

Do not modify anything.