---
name: security-review
description: Review code, configuration or a system for security weaknesses using a threat model and the OWASP Top 10 / ASVS categories, check dependencies and secrets, and report verified findings with severity and fix. Use for changes touching authentication, authorization, input handling, cryptography, secrets, file or network access, dependencies or personal data, before exposing a legacy system to new networks or APIs, and when asked for a security check. Do not use for general code quality review (use code-review), for attacking systems you are not authorized to test, or as a replacement for a formal penetration test or the company's security team.
---

# Security Review

Scope: static review of code and configuration you are authorized to work on. No scanning or
exploitation of systems outside a written authorization. Findings about customer systems are
CONFIDENTIAL; handle them per `data-guard` and report through the agreed channel only.

## Before you start

- Clarify scope: repository and commit, components, deployment context (internet-facing,
  internal network, batch only), what data the system holds, and what changed.
- Collect what exists: architecture notes, earlier findings
  (`brain search "<system> security" --project <slug>` if `brain` is installed), the
  company's security requirements if IT has provided them.
- Check available tools: `gitleaks` (installed with the kit's data-guard module), the
  ecosystem's dependency audit (`npm audit`, `pip-audit`, `dotnet list package --vulnerable`,
  `mvn org.owasp:dependency-check-maven:check`, `cargo audit`), a static analyzer if the
  project uses one. If a tool is missing, do the step manually and state that in the report.
  Many audit tools need network access to a vulnerability database; if you are offline, say
  that the dependency check was not run.

## Procedure

1. **Threat model (short).** Draw or list: actors, entry points (UI, API, files, queues,
   scheduled jobs, admin tools), trust boundaries, sensitive assets (credentials, personal
   data, financial data, customer data). For each entry point ask the STRIDE questions:
   spoofing, tampering, repudiation, information disclosure, denial of service, elevation
   of privilege. Keep it to one page.
2. **Secrets.** Run `gitleaks git --redact .` (full history) or
   `gitleaks git --pre-commit --staged --redact .` (staged changes); gitleaks older than
   8.19 uses `detect` and `protect --staged` instead. Without gitleaks, search with
   `rg -i "(password|passwd|secret|api[_-]?key|token|connectionstring)\s*[:=]"` and review
   config files by hand. Never print secret values in the report; give file and line.
3. **Walk the checklist** in references/checklist.md, ordered by the threat model. The
   categories follow the OWASP Top 10:2025. Prioritize access control, injection, and
   authentication on every entry point you found.
4. **Dependencies and supply chain.** List direct dependencies with versions, flag known
   vulnerabilities (audit tool output), end-of-life components, unpinned versions, and
   downloads from unverified sources in build scripts.
5. **Configuration.** Debug modes, default credentials, verbose error pages, permissive CORS,
   missing TLS, weak cipher settings, overly broad file or database permissions.
6. **Legacy specifics.** Hand-built SQL strings, homegrown crypto or password hashing,
   shared service accounts, credentials in config files or stored procedures, protocols
   without encryption (FTP, plain SMTP, unencrypted database links), file shares as
   interfaces, missing audit logs.
7. **Verify each finding.** Point to the vulnerable code path and describe the input that
   reaches it. Do not run exploits against shared or customer environments. If proof would
   require that, mark the finding "plausible" and say what test would confirm it.
8. **Rate and report** (format below). Severity: *critical* (remote, no auth, data or
   system compromise), *high*, *medium*, *low*, *info*. Consider exposure and data class.

## Report format

```
Scope: <repo@sha, components>, context: <exposure>, tools run: <list, or "not run: reason">
Threat model summary: <entry points, assets, boundaries>

[critical|high|medium|low|info] <category, e.g. A01 Broken Access Control> (confirmed|plausible)
  Location: path/file.ext:123
  Issue: <what>   Attack scenario: <who, how, impact>
  Fix: <concrete change>   Reference: <OWASP/CWE id>
Not covered: <areas, reasons>
```

## Done when

- A threat model names the entry points, assets and trust boundaries in scope.
- Secrets scan, dependency check and checklist ran, or the report says why not.
- Every finding has a location, scenario, severity, fix and reference, without secret values.
- Not-covered areas are listed. Critical and high findings are reported to the responsible
  person immediately, not only in the final document.

## Pitfalls

- Relying on scanner output alone; access-control and logic flaws need reading the code.
- Reporting scanner noise unverified, which buries real issues.
- Copying secrets, personal data or exploit payloads into chat, tickets or AI tools.
- Testing live systems without written authorization.
- Assuming an internal network is a trust boundary. Legacy systems are often reachable
  from more places than the documentation says.

## Related skills

`code-review`, `dependency-upgrade`, `data-guard`, `modernization-assessment`.
Sources: references/sources.md.
