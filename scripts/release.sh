#!/usr/bin/env bash
# Cut a fork release of rift and publish the formula to nicks/homebrew-tap.
#
# Tags follow  v<upstream-version>-nicks.<n>  -- see FORK.md for the scheme.
set -euo pipefail

UPSTREAM_URL="https://github.com/acsandmann/rift"
UPSTREAM_BOOKMARK="main@upstream"
FORK_SUFFIX="nicks"

cd "$(jj workspace root)"

# jj has no dirty tree -- the working copy is always a commit -- so release the
# newest non-empty commit at or below @. That way an empty @ sitting on top of
# the real work is fine.
rev="$(jj log --no-graph -r 'heads(::@ & ~empty())' -T 'commit_id ++ "\n"' | head -1)"
if [[ -z "$rev" ]]; then
  echo "error: no non-empty commit at or below @" >&2
  exit 1
fi

# The formula's URLs point at a GitHub tag, so the commit has to be on the
# remote already.
if [[ -z "$(jj log --no-graph -r "${rev} & ::remote_bookmarks()" -T 'commit_id')" ]]; then
  echo "error: ${rev:0:12} is not reachable from any remote bookmark." >&2
  echo "       push it with 'jj git push' first." >&2
  exit 1
fi

# Our version numbers are named after upstream's, so make sure we have its tags.
if ! jj git remote list | grep -q "^upstream "; then
  jj git remote add upstream "$UPSTREAM_URL"
fi
jj git fetch --remote upstream

base_commit="$(jj log --no-graph \
  -r "heads(::${rev} & ::${UPSTREAM_BOOKMARK})" -T 'commit_id ++ "\n"' | head -1)"
if [[ -z "$base_commit" ]]; then
  echo "error: no common ancestor with ${UPSTREAM_BOOKMARK}" >&2
  exit 1
fi

# Newest upstream release tag this build descends from. Fork tags are filtered
# out so a fork release can't be picked as its own base.
base_tag="$(jj log --no-graph -r "::${base_commit} & tags()" -T 'tags ++ "\n"' \
  | tr ' ' '\n' \
  | grep -E '^v[0-9]' \
  | grep -v -- "-${FORK_SUFFIX}\." \
  | head -1)"
if [[ -z "$base_tag" ]]; then
  echo "error: no upstream release tag in the ancestry of ${rev:0:12}" >&2
  exit 1
fi
base_version="${base_tag#v}"

# Next fork revision on this base.
n="$(jj tag list -T 'name ++ "\n"' "glob:v${base_version}-${FORK_SUFFIX}.*" \
  | sed "s/.*-${FORK_SUFFIX}\.//" | sort -n | tail -1)"
n=$(( ${n:-0} + 1 ))
tag="v${base_version}-${FORK_SUFFIX}.${n}"

fork_commits="$(jj log --no-graph -r "${base_commit}..${rev}" -T '"x\n"' | wc -l | tr -d ' ')"

# goreleaser reads git, not jj. In a colocated repo git HEAD tracks @'s *parent*,
# so if the release commit is @ itself, HEAD still points one commit back and
# goreleaser would build the wrong tree. 'jj new' puts an empty commit on top,
# which moves HEAD onto the release commit.
needs_new=""
[[ "$(git rev-parse HEAD)" != "$rev" ]] && needs_new=1

echo "release rev   : ${rev:0:12}"
echo "upstream base : ${base_tag} (${base_commit:0:12})"
echo "fork commits  : ${fork_commits}"
echo "release tag   : ${tag}"
[[ -n "$needs_new" ]] && echo "note          : will run 'jj new' to move git HEAD onto ${rev:0:12}"
echo

read -r -p "create and push ${tag}, then run goreleaser? [y/N] " reply
[[ "$reply" == [yY] ]] || { echo "aborted"; exit 1; }

# jj tags are lightweight (no annotation), so the upstream base is recorded in
# the GitHub release notes footer instead of a tag message.
jj tag set "$tag" -r "$rev"

if [[ -n "$needs_new" ]]; then
  jj new "$rev"
fi

if [[ "$(git rev-parse HEAD)" != "$rev" ]]; then
  echo "error: git HEAD is $(git rev-parse --short HEAD), expected ${rev:0:12}" >&2
  echo "       goreleaser would build the wrong commit; aborting before publish." >&2
  exit 1
fi

jj git push --remote origin --tag "$tag"

RIFT_UPSTREAM_BASE="$base_tag" \
RIFT_UPSTREAM_COMMIT="$base_commit" \
  goreleaser release --clean
