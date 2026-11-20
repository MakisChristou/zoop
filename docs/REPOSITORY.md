# Repository layout

Zoop's iPhone app remains at the root so existing Xcode, signing and package paths
continue to work. The API is in `server/` and the web dashboard is in `web/`.

The API and web histories were imported as unsquashed Git subtrees. Their original
commits and parent relationships remain reachable; no source history was rewritten.
The import points are API `4af5cdf` and web `9017749`.

To follow a component before the import, inspect its original history directly:

```sh
git log 4af5cdf -- crates/
git log 9017749 -- src/
```

New work belongs in this repository. The former repositories remain intact and
existing deployments remain pinned to their previous sources until an operator
explicitly chooses to migrate them. No deployments or release tags are created by
this repository move. Repository privacy and the pending history review are unchanged.

## Working directories

Run XcodeGen and Swift checks from the root, Cargo and `just` from `server/`,
and npm from `web/`. CI workflows and Dependabot configuration live in root
`.github/`; component-specific agent instructions remain beside their code.

The API Dockerfile takes `server/` as its build context, preserving its existing
allowlist so app files, local configuration and Git history are not sent to Docker:

```sh
docker build -f server/crates/zoop/Dockerfile -t zoop-api server
```

Metrics, database migrations and dependency versions are unchanged. Build validation
also corrected case-ambiguous web module names and a redundant Swift nil fallback.
Existing Nix packaging files are retained without changes; they are not a new
monorepo deployment interface.
