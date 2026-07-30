/// Native deprecation message for the legacy HTTP+SSE transport surface.
///
/// SEP-2596 reached Final on 2026-05-18. Its transition rule gives HTTP+SSE a
/// three-month grace period, making 2026-08-18 the earliest eligibility date.
const legacySseDeprecationMessage =
    'HTTP+SSE is deprecated by MCP SEP-2596; earliest removal eligibility is '
    '2026-08-18. Use Streamable HTTP instead. See '
    'https://modelcontextprotocol.io/seps/2596-spec-feature-lifecycle-and-deprecation';
