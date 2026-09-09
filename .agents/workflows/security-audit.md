---
description: Security Audit
---



1. Inspect the target feature/module and its trust boundaries.
2. Identify authentication and authorization paths.
3. Identify all external/untrusted inputs.
4. Inspect data validation and sanitization.
5. Inspect database and API interactions.
6. Inspect secrets and credential handling.
7. Inspect sensitive data storage and transmission.
8. Run Semgrep against the relevant code.
9. Review dependency risks with Sonatype.
10. Investigate every meaningful security finding.
11. Fix confirmed issues.
12. Re-run Semgrep.
13. Run relevant tests.
14. Report:
   - findings
   - fixes
   - remaining risks
   - checks that could not be performed.