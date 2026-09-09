---
description: Refactor
---



## Process

1. Identify the target module, feature, or code path.
2. Read the surrounding code before changing anything.
3. Trace dependencies, data flow, state changes, and public interfaces.
4. Identify:
   - duplicated logic
   - unnecessary abstractions
   - excessive complexity
   - inefficient algorithms
   - unnecessary allocations
   - non-idiomatic language patterns
   - functionality already available in the standard library
   - unnecessary dependencies
   - poor error handling
5. Check current official documentation with Context7 where language/framework/library behavior matters.
6. Propose the refactoring approach before making large structural changes.
7. Preserve externally observable behavior unless explicitly instructed otherwise.
8. Implement the refactor.
9. Run the relevant test suite.
10. Run Semgrep when applicable.
11. Check dependency changes with Sonatype if dependencies were modified.
12. Review the final diff.
13. Explain the important improvements and any remaining technical debt.

## Do not

- Rewrite code merely to make it look different.
- Optimize without identifying an actual inefficiency.
- Introduce abstractions without a concrete reason.
- Change public APIs unnecessarily.
- Remove behavior simply because it looks unused without verifying its usage.