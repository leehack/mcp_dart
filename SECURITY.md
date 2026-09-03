# Security policy

## Supported releases

Security fixes target the current stable SDK and CLI release lines:

| Package | Supported stable line |
| --- | --- |
| `mcp_dart` | `2.5.x` |
| `mcp_dart_cli` | `0.2.x` |

Older lines receive best-effort fixes only. A vulnerability may require
upgrading to the latest stable line when a safe backport would break protocol
correctness or public API compatibility.

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability. Use
[GitHub private vulnerability reporting](https://github.com/leehack/mcp_dart/security/advisories/new)
and include:

- affected versions and platforms;
- transport and negotiated MCP version;
- reproduction steps or a proof of concept;
- expected impact and any known mitigation.

Maintainers commit to acknowledging a complete report within two business days.
Please allow time to coordinate a fix and disclosure before publishing details.

## Response commitments

A vulnerability with CVSS 7.0 or higher is `P0` under the MCP SDK tiering
policy. Maintainers commit to resolving it within seven calendar days after
validation. Resolution means a released fix or a documented safe mitigation
that removes user exposure. If a final upstream fix remains outstanding, the
advisory will track that follow-up separately.

Security fixes receive focused regression tests and the affected analyzer,
unit, transport, conformance, interoperability, and release checks. Public
advisories credit reporters who want attribution and are published after a
fixed version or mitigation is available.

## Scope

Reports are especially useful for:

- JSON-RPC or MCP message validation bypasses;
- authentication, OAuth, redirect, issuer, token, Origin, or Host validation;
- cross-request data leakage or request-ID confusion;
- unsafe URI, header, schema-reference, file, or process handling;
- dependency vulnerabilities reachable through supported SDK behavior.

Application-specific authorization policy, insecure deployment configuration,
and plaintext storage copied from explicitly local learning examples are
outside the SDK vulnerability boundary unless the SDK makes the safe behavior
impossible.
