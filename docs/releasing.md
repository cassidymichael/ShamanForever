# Branches and releasing

`main` holds only work that has been tested in game, so anything tagged from it is safe to release.

- Work that changes the addon goes on a short-lived branch named for it (`shield-split`), one commit
  per change, each saying what it does. The branch is pushed as a backup, and CI lints it.
- It is tested in game from the branch, then merged into `main` keeping its commits
  (`git merge --ff-only`, or `--no-ff` for a larger piece of work). The branch is then deleted.
- A branch that adds, removes or changes something players can do (not just a setting) updates the
  README's Features section before it is merged. Experimental features are listed as experimental.
- Changes that don't touch what players get (docs, CI, repo files) can go straight to `main`.
- A pull request only when a written record of a larger change helps; not for every change.

## Releasing

1. Merge the tested work into `main` as above.
2. In `CHANGELOG.md`, rename the `## Unreleased` section at the top to `## X.Y.Z (YYYY-MM-DD)`, or
   add that section if there is none, and make sure it lists what players will notice. Commit it on
   its own as `Release X.Y.Z`.
   Anything new in it should already be in the README's Features section. On a 0.x.0 release, also
   read the whole list against the options window and drop anything that has gone.
3. Tag and push: `git tag -a vX.Y.Z -m "ShamanForever X.Y.Z" && git push origin main vX.Y.Z`
4. If the Features section changed since the last release (`git diff vPREV vX.Y.Z -- README.md`),
   paste it into the CurseForge and Wago project descriptions. The release doesn't update those.

## Changelog

`CHANGELOG.md` lists what players will notice in each version, newest first; not every commit.
Changes that are merged or in a test build but not yet released go under `## Unreleased` at the top.
Each branch adds its own lines there, so they reach `main` with the work. Right after a release
there is no such section; the next change to list starts it.

## Test builds (betas)

A beta is a test build of the next version, for players who chose to receive beta versions. Only
beta tags are used, never alpha.

1. The work is on a pushed branch: a work branch, or a `next` branch that is `main` plus the branches
   in the test. It has been tested in game from there, as for anything bound for `main`.
2. The branch's `## Unreleased` section lists everything the build changes for players since the
   last release. It is the beta's release notes.
3. Tag the branch's tip `vX.Y.Z-beta.N`, where X.Y.Z is the next release and N counts up from 1:
   `git tag -a vX.Y.Z-beta.N -m "ShamanForever X.Y.Z-beta.N" && git push origin vX.Y.Z-beta.N`

A beta tag runs the same workflow as a release. CurseForge and Wago get a beta file, which reaches
only players who opted in to betas in their addon app, and GitHub marks the release a pre-release.
There is no Discord post. The word "alpha" or "beta" anywhere in a tag sets the file type, so tags
are only ever `vX.Y.Z` or `vX.Y.Z-beta.N`; the workflow stops on any other.

## The release workflow

A tag push runs `.github/workflows/release.yml`:

- It writes `RELEASE_NOTES.md`, the release notes on GitHub, CurseForge and Wago, from
  `CHANGELOG.md`: for a release, that version's section; for a beta, the `## Unreleased` section
  under a line saying it's a test build and how to go back to releases. It stops if the section is
  missing (or, for a beta, has no entries), or if the tag is neither kind.
- The BigWigs packager builds the zip (files listed under `ignore` in `.pkgmeta`, and dotfiles, are
  left out), creates the GitHub release and uploads to CurseForge (project 1706929) and Wago (project
  rN4rkrKD), using the `CF_API_KEY` and `WAGO_API_TOKEN` repo secrets. CurseForge's own "Automatic
  Packaging" must stay disabled on the project, or each tag produces two files. The version in the
  TOC comes from the tag.
- For a release only, it posts the notes to the Discord server's #announcements through the webhook
  in the `DISCORD_WEBHOOK_URL` secret; betas are not announced. A failed post only warns: post it by
  hand.

`.github/workflows/lint.yml` runs luacheck on every push, on any branch; a release comes from a
commit where it passes.
