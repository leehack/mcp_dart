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
- `minimatch 11.0.9` retains the fix for
  [GHSA-g3hv-75wg-m249](https://github.com/advisories/GHSA-g3hv-75wg-m249)
  and includes the fixes released in 11.0.8 for
  [GHSA-c859-jr93-m5j4](https://github.com/isaacs/minimatch/security/advisories/GHSA-c859-jr93-m5j4)
  and
  [GHSA-hqmv-qgp3-jx75](https://github.com/isaacs/minimatch/security/advisories/GHSA-hqmv-qgp3-jx75).

The lockfile also resolves `hono 4.13.18` within the SDK's existing range for
Hono security fixes, including the mount-prefix middleware bypass described in
[GHSA-4m76-xfj5-7975](https://github.com/honojs/hono/security/advisories/GHSA-4m76-xfj5-7975).

The minimatch pin satisfies ESLint 10.15.0's declared range (`^11.0.5`),
but some legacy parents still declare minimatch 10.x ranges. The glob override
also crosses a parent's declared major range. These overrides are specific to
this Node 24 fixture; tests cover matching behavior, filesystem tool calls,
and lint file selection. Minimatch depends on the BlueOak-1.0.0-licensed
transitive package `@isaacs/nonrecursive-glob-match`.

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
