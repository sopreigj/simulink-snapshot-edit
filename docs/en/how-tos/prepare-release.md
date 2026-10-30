# How-To: Pre-Release Cleanup and Export

**Problem it solves**: you want to export the repository as an open-source release others can use, without shipping machine-local artifacts, private state, or git history.

**Bottom line**: use `git archive`; do not copy the whole directory tree.

## Why not "copy the whole tree"

The working tree holds a number of gitignored machine-local artifacts (`test/scratch/` verification intermediates, `test/scripts/multiver/` multi-version archives, `config_local.m` local configuration, `test/sfun_probe/` runtime fixture directories). Copying the whole tree brings all of them along; `git archive` packages only git-tracked files, so none of them are included.

## Steps

1. Confirm the working tree is clean: `git status --short` produces no output (or the only changes are ones you intentionally want in the release, already committed).
2. Export (from the repository root):

   ```bash
   git archive --format=tar --prefix=simulink-snapshot-edit/ HEAD \
     | tar -x -C <目标目录>
   ```

3. Spot-check the exported tree:
   - No `private/` (the state boundary, untracked)
   - No `test/scratch/`, `config_local.m`, `test/sfun_probe/`, `*.slxc`, `slprj/`
   - `LICENSE`, `README.md`, `CHANGELOG.md`, `config_example.m`, `src/`, `test/`, `docs/` all present

## An important property of git archive

`git archive` packages the file tree as of HEAD, **without git history**. If the release takes the form of "a source tarball without history", that is exactly what you get; if the release is a push to a public repository, the history goes public with it — that is a separate decision (whether to strip history first) and out of scope for this guide.

## Re-verification before export

Run the verification suite (`test/scripts/`) before releasing, at minimum:

- `verify_rebuild_all` (rebuild fidelity: 1 library + 4 models)
- `verify_snapshots_fresh` (snapshot freshness)
- `verify_special_blocks` (special block types)

```matlab
run('test/scripts/verify_rebuild_all.m');
```
