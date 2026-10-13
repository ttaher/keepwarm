---
name: troubleshoot
description: 'Diagnose why the KeepWarm site or API will not run. Use for startup failures, connection problems, occupied ports, Node.js or npm issues, missing dependencies, and SQLite access problems.'
user-invocable: true
disable-model-invocation: false
---

# Troubleshoot KeepWarm

Run the bundled read-only diagnostic script from the workspace root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .github/skills/troubleshoot/scripts/diagnose.ps1
```

The script writes one JSON object to standard output. Parse that object and present its `checks` in a compact list:

- `pass`: ✅
- `fail`: ❌
- `warn`: ⚠️
- `info`: ℹ️

Show each check's name and message. State the overall status. Do not attempt to fix any reported issue: do not install packages, edit configuration, start or stop servers, or change the database. End by asking: **Would you like me to fix any of the reported issues?**

If the script cannot run, report that directly and ask whether the user wants help resolving that blocker. Do not invent diagnostic results.