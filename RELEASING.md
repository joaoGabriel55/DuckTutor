# Releasing DuckTutor

DuckTutor uses Changesets to propose and apply release versions. `package.json` is the canonical
version; `scripts/sync-plugin-version.mjs` copies it into the Claude marketplace, Claude plugin, and
Codex plugin manifests.

## Add release intent

Every pull request with a user-facing change should include a changeset:

```bash
pnpm changeset
```

Select `duck-tutor`, choose the SemVer bump, and describe the change for the generated changelog.
Commit the new Markdown file under `.changeset/` with the implementation.

## Create the version pull request

After changesets reach `main`, `.github/workflows/changesets.yml` runs `pnpm run version`. The
Changesets action opens or updates a release pull request containing:

- the new `package.json` version;
- the synchronized `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, and
  `.codex-plugin/plugin.json` versions;
- the generated `CHANGELOG.md` entries;
- removal of the consumed changeset files.

The repository settings must allow GitHub Actions to create pull requests. The workflow grants only
the `contents: write` and `pull-requests: write` permissions needed for that release PR.

Review the manifest diff and CI results, then merge the release pull request. The workflow does not
publish an npm package or create a Git tag or GitHub release.

## Publish the plugin release

From the updated default branch, tag and publish the reviewed version manually:

```bash
git switch main
git pull --ff-only origin main
git tag v0.15.0
git push origin v0.15.0
gh release create v0.15.0 --generate-notes
```

Replace `0.15.0` with the version from the merged release pull request.

For recovery only, `scripts/bump-version.sh <major.minor.patch>` updates `package.json` and all three
plugin manifests together while retaining the existing validation against drift and downgrades.
