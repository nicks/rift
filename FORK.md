# Fork notes

This is a fork of [acsandmann/rift](https://github.com/acsandmann/rift), published
as a Homebrew formula from [nicks/homebrew-tap](https://github.com/nicks/homebrew-tap).

```sh
brew install nicks/tap/rift
brew services start nicks/tap/rift
```

## Tagging scheme

Release tags are:

```
v<upstream-version>-nicks.<n>
```

- **`<upstream-version>`** is the most recent upstream release tag this build
  descends from, so the version always says which upstream release it is based on.
- **`<n>`** is the fork revision on that base, starting at 1 and resetting
  whenever the base moves.

| Tag                | Meaning                                            |
| ------------------ | -------------------------------------------------- |
| `v0.5.3-nicks.1`   | first fork build on top of upstream `v0.5.3`        |
| `v0.5.3-nicks.2`   | another fork change, still based on `v0.5.3`        |
| `v0.5.4-nicks.1`   | rebased onto upstream `v0.5.4`                      |

The suffix is semver prerelease syntax, so tags sort correctly against each other
(`0.5.3-nicks.1` < `0.5.3-nicks.2` < `0.5.4-nicks.1`) and `brew upgrade` sees fork
releases in the right order. Semver does rank `0.5.3-nicks.1` *below* a plain
`0.5.3`, but nothing ever compares the two: this tap only carries fork builds, and
upstream's own formula lives in a different tap under a conflicting name.

Because the base version alone doesn't say how far past that tag the fork sits,
each release also records the exact upstream base commit in its GitHub release
notes footer.

## Cutting a release

```sh
./scripts/release.sh
```

The script drives `jj`, not `git`. It:

1. picks the release commit: the newest non-empty commit at or below `@`, so an
   empty working copy sitting on top of the real work is fine
2. refuses to continue if that commit isn't reachable from a remote bookmark,
   since the formula's URLs point at a tag on GitHub
3. fetches upstream tags and derives the base tag from the common ancestor with
   `main@upstream`
4. computes the next `-nicks.<n>` revision from existing tags
5. shows the tag and how many fork commits it contains, and asks before doing anything
6. creates the tag with `jj tag set` and pushes it with `jj git push --tag`
7. runs `goreleaser release`, which builds, publishes the GitHub release, and
   pushes the regenerated `Formula/rift.rb` to the tap

Two jj-specific wrinkles it handles for you:

- **git HEAD lags `@`.** goreleaser reads git, and in a colocated repo git HEAD
  tracks `@`'s *parent*. If the release commit is `@` itself, goreleaser would
  build the previous commit. The script runs `jj new` to move HEAD onto the
  release commit, and hard-fails before publishing if HEAD still doesn't match.
- **jj tags are lightweight.** `jj tag set` has no annotation message, so the
  upstream base tag and commit are recorded in the GitHub release notes footer
  (via `RIFT_UPSTREAM_BASE` / `RIFT_UPSTREAM_COMMIT`) instead.

`goreleaser` needs a `GITHUB_TOKEN` with `repo` scope on both `nicks/rift` and
`nicks/homebrew-tap`.

## Release layout

Each release ships one tarball per architecture — `rift_<version>_darwin_amd64.tar.gz`
and `rift_<version>_darwin_arm64.tar.gz` — each containing `rift`, `rift-cli`,
`rift.default.toml`, `README.md`, and `LICENSE`. The generated formula selects
between them with `on_intel` / `on_arm`.

This differs from upstream, which ships a single `lipo`-merged universal tarball.

## Differences from upstream packaging

- **Formula, not cask.** Homebrew casks have no `service` stanza, so a formula is
  what keeps `brew services start rift` working.
- **The formula is generated.** `goreleaser` regenerates `Formula/rift.rb` from
  `.goreleaser.yaml` on every release, so edit the packaging there, not in the tap.
  `brews` is deprecated in goreleaser (it is steering users to casks, which cannot
  express the service block) — it still works, but it will need revisiting if
  goreleaser removes it.
- **`rift.default.toml` is actually installed.** Upstream's caveats tell users to
  copy it out of `pkgshare`, but nothing puts it there; here it ships in the
  tarball and is installed.
- **No `-C target-cpu=native`.** Upstream's release workflow sets it, which tunes
  distributed binaries to whichever machine built them.
