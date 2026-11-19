#!/bin/bash
# archive-release.sh TAG PREFIX
#
# Moves the release tagged TAG to the tag PREFIX-YYYYMMDD, the day (UTC) the
# release was created, i.e. the day its build started publishing. A second
# archive on the same day becomes PREFIX-YYYYMMDD-2, and so on. The new tag
# points at the same commit as the old one; the old tag is then deleted, so
# TAG is free for the next build. No release tagged TAG: nothing to archive,
# but a leftover TAG tag (from an earlier run whose tag delete failed) is
# deleted, so the next release cannot pick up its stale commit. Any GitHub
# error other than "not found" stops the publish (exit 1).
#
# Used by build-all for device branches (the "rg351p" release always being
# the newest RG351P build, so an installer can fetch that one tag).
set -euo pipefail

tag="$1"
prefix="$2"
repo="${GITHUB_REPOSITORY:?}"

err="$(mktemp)"
trap 'rm -f "$err"' EXIT

# gh_get ENDPOINT JQ: prints the result; exit 0 found, 4 not found (HTTP 404),
# 1 any other error (printed).
gh_get() {
    if gh api "$1" -q "$2" 2>"$err"; then
        return 0
    fi
    if grep -q 'HTTP 404' "$err"; then
        return 4
    fi
    cat "$err" >&2
    return 1
}

rc=0
created="$(gh_get "repos/${repo}/releases/tags/${tag}" .created_at)" || rc=$?
if [ "$rc" = 4 ]; then
    echo "No release tagged ${tag}: nothing to archive"
    rc=0
    gh_get "repos/${repo}/git/ref/tags/${tag}" .object.sha >/dev/null || rc=$?
    case "$rc" in
        4) exit 0 ;;
        0)
            echo "Deleting the leftover tag ${tag}, which no release uses"
            gh api -X DELETE "repos/${repo}/git/refs/tags/${tag}" \
                || { echo "::error::the leftover tag ${tag} could not be deleted; delete it, then re-run the publish"; exit 1; }
            exit 0
            ;;
        *) echo "::error::could not look up the tag ${tag}"; exit 1 ;;
    esac
elif [ "$rc" != 0 ] || [ -z "$created" ]; then
    echo "::error::could not look up the release ${tag}"
    exit 1
fi
day="$(date -u -d "$created" +%Y%m%d)"

# The tag's commit; gh release create makes lightweight tags, but follow an
# annotated one too.
ref="$(gh_get "repos/${repo}/git/ref/tags/${tag}" '.object.type + " " + .object.sha')" \
    || { echo "::error::release ${tag} exists, but its tag could not be read"; exit 1; }
read -r type sha <<<"$ref"
if [ "$type" = tag ]; then
    sha="$(gh api "repos/${repo}/git/tags/${sha}" -q .object.sha)"
fi
[ -n "$sha" ] || { echo "::error::no commit found for the tag ${tag}"; exit 1; }

new="${prefix}-${day}"
n=2
while :; do
    rc=0
    gh_get "repos/${repo}/git/ref/tags/${new}" .object.sha >/dev/null || rc=$?
    [ "$rc" = 4 ] && break
    [ "$rc" = 0 ] || { echo "::error::could not check whether the tag ${new} exists"; exit 1; }
    new="${prefix}-${day}-${n}"
    n=$((n + 1))
done

# The release edit creates the new tag at --target. It is used because creating
# the tag through the git refs API is refused to the run token (403) for a
# commit that carries workflow changes the default branch lacks, as the rg351p
# branch's commits do. On some repos the edit is refused to the run token too,
# hence build-all's recommended RELEASE_TOKEN.
gh release edit "$tag" --repo "$repo" --tag "$new" --target "$sha"
[ "$(gh release view "$new" --repo "$repo" --json tagName -q .tagName)" = "$new" ] \
    || { echo "::error::release ${tag} did not move to ${new}"; exit 1; }
# A tag left behind would be reused by the next gh release create, at its old
# commit, so stop here; a re-run deletes it (see the top).
gh api -X DELETE "repos/${repo}/git/refs/tags/${tag}" \
    || { echo "::error::release moved to ${new}, but the old tag ${tag} could not be deleted; delete it, then re-run the publish"; exit 1; }
echo "Archived release ${tag} (${sha}) as ${new}"
