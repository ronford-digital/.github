#!/usr/bin/env bash
# CalVer (YYYY.M.D, no zero-padding, matching RonfordDigital.SharedKernel's own
# scheme) for a given git tag prefix. A same-day second release gets a .N suffix.
# Promoted from ronford-signal/scripts/next-calver.sh -- the org-wide standard is
# IMAGE-TAGGING-AND-PROMOTION-STANDARD.md (devops-knpdts-argocd-manifests).
#
# Usage: next-calver.sh <tag-prefix> [legacy-prefix ...]
#   e.g. next-calver.sh "momo/v"            -> 2026.10.23 (or 2026.10.23.1, ...)
#        next-calver.sh "notify/v" "v"      -> also treats v2026.10.23 as taken
#
# Same-day releases use ".N" (dot), never "-N" (hyphen): SemVer2 reads a hyphen
# as a PRERELEASE label, so 2026.10.23-1 would sort BELOW bare 2026.10.23 and a
# floor-based (">=") consumer would keep resolving back to the superseded build.
#
# Legacy prefixes exist only for the cut-over from an older tag series: the image
# tag is the bare version, so a version already released under the old prefix
# must not be reused or the image tag would be overwritten.
#
# Set PRERELEASE=rc to get the next release candidate of the next stable version
# (2026.10.23-rc.1, -rc.2, ...). Here the hyphen IS intentional: an rc must sort
# below the final release.

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <tag-prefix> [legacy-prefix ...]" >&2
    exit 1
fi

prefixes=("$@")
prerelease="${PRERELEASE:-}"

if [[ -n "$prerelease" && ! "$prerelease" =~ ^[a-z]+$ ]]; then
    echo "PRERELEASE must be a lowercase word such as 'rc', got '$prerelease'" >&2
    exit 1
fi

# 10#$var forces base-10 interpretation so a leading zero (e.g. "08") isn't
# misread as octal -- and stripping via arithmetic context works identically
# on GNU date (Linux CI runners) and BSD date (local macOS runs), unlike the
# `date +%-m`/`%-d` no-padding flag, which BSD date doesn't support at all.
year=$(date -u +%Y)
month=$((10#$(date -u +%m)))
day=$((10#$(date -u +%d)))
today_version="${year}.${month}.${day}"

# A version is taken if a stable tag exists for it under ANY of the prefixes.
version_taken() {
    local p
    for p in "${prefixes[@]}"; do
        [[ -n "$(git tag -l "${p}$1")" ]] && return 0
    done
    return 1
}

version="$today_version"
if version_taken "$version"; then
    n=1
    while version_taken "${today_version}.${n}"; do
        n=$((n + 1))
    done
    version="${today_version}.${n}"
fi

if [[ -z "$prerelease" ]]; then
    echo "$version"
    exit 0
fi

n=1
while [[ -n "$(git tag -l "${prefixes[0]}${version}-${prerelease}.${n}")" ]]; do
    n=$((n + 1))
done

echo "${version}-${prerelease}.${n}"
