# Legacy TypeScript interoperability fixtures

These private fixtures exercise the initialization-era MCP SDK and published
filesystem server. They are test inputs, not dependencies of the published
Dart SDK or CLI. Keep their versions separate from the modern TypeScript
fixtures in `../ts_2026_07_28/`.

## Security overrides

The manifest pins these transitive security fixes:

- `@hono/node-server 2.1.8` addresses
  [GHSA-rmxm-3fg6-px4f](https://github.com/advisories/GHSA-rmxm-3fg6-px4f).
- `glob 14.0.2` addresses
  [GHSA-3g3m-2fjr-6pw4](https://github.com/advisories/GHSA-3g3m-2fjr-6pw4).
- `minimatch 11.0.1` addresses
  [GHSA-g3hv-75wg-m249](https://github.com/advisories/GHSA-g3hv-75wg-m249).

The lockfile also resolves `hono 4.13.18` within the SDK's existing range for
Hono security fixes, including the mount-prefix middleware bypass described in
[GHSA-4m76-xfj5-7975](https://github.com/honojs/hono/security/advisories/GHSA-4m76-xfj5-7975).

The glob and minimatch overrides cross their parents' declared major ranges.
They were selected explicitly for this Node 24 fixture; the matching behavior,
filesystem tool calls, and lint file selection must remain covered by tests.
The minimatch upgrade adds the BlueOak-1.0.0-licensed transitive package
`@isaacs/nonrecursive-glob-match`.

Remove an override only after all affected parents resolve a fixed version
without it and the same compatibility checks pass. Do not silence audit
findings or weaken interoperability expectations to accommodate an update.

## Verification

From this directory:

```bash
npm ci
npm run build
npm run lint
npm run format:check
npm run test:dependency-compat
npm audit
```

From `packages/mcp_dart_cli/`, run the public CLI filesystem regressions with
missing fixtures treated as failures:

```bash
CI=true dart test test/e2e/cli_interop_e2e_test.dart --name filesystem
```

Also run the root Dart tests and the tagged legacy interoperability suites.
`npm audit` covers the resolved dependency graph; it is not proof that bundled
upstream source contains no vulnerable third-party code.
