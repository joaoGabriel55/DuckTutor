# Releasing DuckTutor

DuckTutor keeps its release version in three manifests. Bump them together with:

```bash
scripts/bump-version.sh 0.13.0
```

The command accepts only a stable `major.minor.patch` version greater than the current release. It
validates that the existing manifests agree before writing and updates:

- `.claude-plugin/plugin.json`
- `.claude-plugin/marketplace.json`
- `.codex-plugin/plugin.json`

Review and publish the bump explicitly:

```bash
git diff --check
for test_script in scripts/test-*.sh; do "$test_script" || exit 1; done
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json .codex-plugin/plugin.json
git commit -m "release: v0.13.0"
git push -u origin HEAD
```

Merge the reviewed version-bump commit into `main`, then publish from the updated default branch:

```bash
git switch main
git pull --ff-only origin main
git tag v0.13.0
git push origin v0.13.0
gh release create v0.13.0 --generate-notes
```

Replace `0.13.0` consistently. Creating the commit, tag, push, and GitHub release remains manual so
the manifest diff and validation results can be reviewed before publication.
