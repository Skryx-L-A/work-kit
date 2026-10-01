# Security checklist (OWASP Top 10:2025 order)

Use as prompts, not as a complete standard. For systematic verification requirements see
OWASP ASVS 5.0 (link in sources.md).

## A01 Broken Access Control (includes SSRF since 2025)
- Every endpoint, page, job and report checks authorization on the server side.
- Object-level checks: can user A read or change user B's record by changing an ID?
- Admin functions separated and protected; no "hidden URL" security.
- Outgoing requests built from user input are restricted to allowed destinations (SSRF).
- File paths from input cannot escape the intended directory (path traversal).

## A02 Security Misconfiguration
- No debug mode, default accounts, sample apps or directory listing in deployable config.
- Error pages do not reveal stack traces, versions or SQL.
- Security headers, CORS and cookie flags (Secure, HttpOnly, SameSite) set deliberately.
- XML parsers have external entities disabled (XXE).

## A03 Software Supply Chain Failures
- Dependencies pinned, from trusted registries, with known vulnerabilities addressed.
- Build scripts do not download and execute unverified code.
- End-of-life frameworks and runtimes identified with an upgrade path.

## A04 Insecure Design
- Business rules enforced on the server (limits, workflows, state transitions).
- Rate limits or lockouts where abuse is plausible.

## A05 Cryptographic Failures
- Sensitive data encrypted in transit (TLS) and at rest where required.
- No homegrown crypto, no MD5/SHA-1 for security, no ECB mode, no hard-coded keys.
- Passwords hashed with a slow, salted algorithm (Argon2id, scrypt, bcrypt, PBKDF2).

## A06 Injection
- SQL built only with parameters or a safe query builder; check stored procedures with
  dynamic SQL too.
- No shell commands, LDAP queries, XPath or template strings built from input.
- Output encoding for HTML, JavaScript and URLs (XSS).

## A07 Identification and Authentication Failures (Authentication Failures)
- Session IDs regenerated at login, invalidated at logout, with timeouts.
- Credentials never in URLs or logs; password reset flows cannot be enumerated or guessed.
- Service accounts not shared between systems and not given admin rights by default.

## A08 Software and Data Integrity Failures
- No insecure deserialization of untrusted data (Java serialization, BinaryFormatter,
  pickle, PHP unserialize).
- Updates, plugins and imported files verified before use.

## A09 Security Logging and Alerting Failures
- Security-relevant events (login, failed access, admin actions) logged with user and time.
- Logs contain no secrets or unnecessary personal data; log injection prevented.

## A10 Mishandling of Exceptional Conditions
- Errors fail closed (deny), not open.
- Exceptions are not swallowed; resources are released on error paths.
- Unexpected input sizes and formats are rejected cleanly.
