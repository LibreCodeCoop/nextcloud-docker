#!/usr/bin/env bash
# Reviewable Nextcloud stable-version inventory. Requires curl, awk and jq.
set -euo pipefail

source_url=https://github.com/nextcloud/server/wiki/Maintenance-and-Release-Schedule
wiki_url=https://raw.githubusercontent.com/wiki/nextcloud/server/Maintenance-and-Release-Schedule.md
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$repo_root/.github/nextcloud-supported.json"
command_name=${1:?Usage: nextcloud-versions.sh discover|matrix [options]}
shift
wiki_file=''
github_output=''
skip_upstream=false
today=$(date -u +%F)

error() {
  local message=$1
  printf '::error title=Nextcloud version discovery failed::%s\n' "$message" >&2
  if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
    printf '**Nextcloud version discovery FAILED:** %s. Existing manifest was preserved.\n' "$message" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 1
}
trap 'error "Unexpected failure at line $LINENO (exit $?)"' ERR

while (( $# )); do
  case "$1" in
    --file|--wiki-file|--github-output|--today)
      (( $# >= 2 )) || error "Missing argument for $1"
      case "$1" in
        --file) manifest=$2 ;;
        --wiki-file) wiki_file=$2 ;;
        --github-output) github_output=$2 ;;
        --today) today=$2 ;;
      esac
      shift 2
      ;;
    --skip-upstream-check) skip_upstream=true; shift ;;
    *) error "Unknown option: $1" ;;
  esac
done

[[ $today =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || error "Invalid date: $today"

# Validate the committed JSON before it can reach the build matrix or tag promotion.
validate_manifest() {
  local path=$1
  jq -e --arg source "$source_url" --arg month "${today:0:7}" '
    . as $root |
    ($root | type == "object") and
    (($root | keys) == ["schema_version","source","versions"]) and
    ($root.schema_version == 1) and ($root.source == $source) and
    ($root.versions | type == "array" and length >= 1 and length <= 5) and
    ($root.versions | all(.[];
      type == "object" and
      (keys == ["eol","image","major"]) and
      (.major | type == "number" and . >= 20 and . <= 99 and . == floor) and
      (.image | type == "string" and test("^nextcloud:[0-9]{2,3}[.][0-9]+[.][0-9]+-fpm@sha256:[a-f0-9]{64}$")) and
      ((.image | capture("^nextcloud:(?<major>[0-9]{2,3})[.]").major | tonumber) == .major) and
      (.eol | type == "string" and test("^20[0-9]{2}-(0[1-9]|1[0-2])$") and . >= $month)
    )) and
    ([$root.versions[].major] as $majors |
      ($majors == ($majors | unique | sort)) and
      all(range(1; ($majors | length)); . as $i | $majors[$i] == ($majors[$i-1] + 1)))
  ' "$path" > /dev/null || error "Invalid or EOL approved manifest: $path"
}

request() {
  curl --fail --silent --show-error --location --retry 2 --max-time 30 \
    -H 'User-Agent: librecode-nextcloud-version-discovery' "$@"
}

verify_release() {
  local release=$1 github_tag docker_tag headers=()
  if [[ -n ${GITHUB_TOKEN:-} ]]; then
    headers=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  github_tag=$(request "${headers[@]}" \
    "https://api.github.com/repos/nextcloud-releases/server/releases/tags/v${release}")
  jq -e --arg release "v$release" '
    .tag_name == $release and .prerelease == false and .draft == false
  ' <<< "$github_tag" > /dev/null || error "No official stable GitHub release v$release"

  docker_tag=$(request "https://hub.docker.com/v2/repositories/library/nextcloud/tags/${release}-fpm")
  jq -e --arg tag "${release}-fpm" '
    .name == $tag and
    (.images | any(.[]; .os == "linux" and .architecture == "amd64")) and
    (.images | any(.[]; .os == "linux" and .architecture == "arm64"))
  ' <<< "$docker_tag" > /dev/null || error "Official image nextcloud:${release}-fpm lacks amd64 or arm64"
  jq -er '.digest | select(test("^sha256:[a-f0-9]{64}$"))' <<< "$docker_tag"     || error "No valid digest for nextcloud:${release}-fpm"
}

case "$command_name" in
  matrix)
    validate_manifest "$manifest"
    matrix=$(jq -c '{include: [.versions[] | {major, tag: ((.major | tostring) + "-fpm"), image, release: (.image | split(":")[1] | split("-fpm@")[0])}]}' "$manifest")
    if [[ -n $github_output ]]; then
      printf 'matrix=%s\n' "$matrix" >> "$github_output"
    else
      printf '%s\n' "$matrix"
    fi
    printf 'Approved Nextcloud versions: %s\n' "$(jq -r '[.versions[].major | tostring] | join(", ")' "$manifest")" >&2
    ;;
  discover)
    tmpdir=$(mktemp -d)
    trap 'rm -rf "$tmpdir"' EXIT
    if [[ -n $wiki_file ]]; then
      cp -- "$wiki_file" "$tmpdir/wiki.md"
    else
      request "$wiki_url" > "$tmpdir/wiki.md"
    fi

    awk -f "$repo_root/scripts/parse-nextcloud-wiki.awk" "$tmpdir/wiki.md" > "$tmpdir/releases.tsv"
    while IFS=$'\t' read -r major release eol released; do
      [[ $eol =~ ^20[0-9]{2}-(0[1-9]|1[0-2])$ && $eol > "${today:0:7}" || $eol == "${today:0:7}" ]] \
        || error "Nextcloud $major is EOL or has invalid EOL month: $eol"
      [[ $released =~ ^20[0-9]{2}-[0-9]{2}-[0-9]{2}$ && $released < $today || $released == "$today" ]] \
        || error "Nextcloud $major release date is invalid or in the future: $released"
      [[ $(date -u -d "$released" +%F 2>/dev/null) == "$released" ]] || error "Invalid release date: $released"
      digest="sha256:$(printf "%064d" 0)"
      if [[ $skip_upstream == false ]]; then digest=$(verify_release "$release"); fi
      image=''
      if [[ -f $manifest ]]; then
        image=$(jq -r --argjson major "$major" '.versions[]? | select(.major == $major) | .image // empty' "$manifest")
      fi
      if [[ -z $image ]]; then image="nextcloud:${release}-fpm@${digest}"; fi
      printf '%s\t%s\t%s\n' "$major" "$image" "$eol" >> "$tmpdir/images.tsv"
    done < "$tmpdir/releases.tsv"

    jq -Rn --arg source "$source_url" '
      {schema_version: 1, source: $source,
       versions: ([inputs | split("\t") |
         {major: (.[0] | tonumber), image: .[1], eol: .[2]}] | sort_by(.major))}
    ' < "$tmpdir/images.tsv" > "$tmpdir/manifest.json"

    validate_manifest "$tmpdir/manifest.json"
    if [[ ! -f $manifest ]] || ! cmp -s "$tmpdir/manifest.json" "$manifest"; then
      cp -- "$tmpdir/manifest.json" "$manifest"
      status=updated
    else
      status=unchanged
    fi
    printf 'Nextcloud discovery: %s; manifest %s\n' \
      "$(jq -r '[.versions[].major | tostring] | join(", ")' "$manifest")" "$status"
    if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
      printf 'Nextcloud discovery: **%s**, manifest **%s**. Source: %s\n' \
        "$(jq -r '[.versions[].major | tostring] | join(", ")' "$manifest")" "$status" "$source_url" >> "$GITHUB_STEP_SUMMARY"
    fi
    ;;
  *) error "Expected discover or matrix, received $command_name" ;;
esac
