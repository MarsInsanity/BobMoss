#!/bin/bash
# archive-release.sh TAG PREFIX
#
# Moves the release tagged TAG to the tag PREFIX-YYYYMMDD, the day (UTC) the
# release was created, i.e. the day its build started publishing. A second
# archive on the same day becomes PREFIX-YYYYMMDD-2, and so on. The new tag
# points at the same commit as the old one; the old tag is then deleted, so
# TAG is free for the next build. No release tagged TAG: nothing to do.
#
# Used by build-all for device branches (the "rg351p" release always being
# the newest RG351P build, so an installer can fetch that one tag).
set -euo pipefail

tag="$1"
prefix="$2"
repo="${GITHUB_REPOSITORY:?}"

created="$(gh release view "$tag" --repo "$repo" --json createdAt -q .createdAt 2>/dev/null)" || {
    echo "No release tagged ${tag}: nothing to archive"
    exit 0
}
day="$(date -u -d "$created" +%Y%m%d)"

# The tag's commit; gh release create makes lightweight tags, but follow an
# annotated one too.
read -r type sha < <(gh api "repos/${repo}/git/ref/tags/${tag}" -q '.object.type + " " + .object.sha')
if [ "$type" = tag ]; then
    sha="$(gh api "repos/${repo}/git/tags/${sha}" -q .object.sha)"
fi

new="${prefix}-${day}"
n=2
while gh api "repos/${repo}/git/ref/tags/${new}" >/dev/null 2>&1; do
    new="${prefix}-${day}-${n}"
    n=$((n + 1))
done

gh api -X POST "repos/${repo}/git/refs" -f ref="refs/tags/${new}" -f sha="$sha" >/dev/null
gh release edit "$tag" --repo "$repo" --tag "$new"
gh api -X DELETE "repos/${repo}/git/refs/tags/${tag}"
echo "Archived release ${tag} (${sha}) as ${new}"
