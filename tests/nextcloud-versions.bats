#!/usr/bin/env bats
# Offline regression tests for the official wiki and reviewed JSON format.
setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TEST_ROOT=$(mktemp -d)
  export TEST_ROOT
  mkdir -p "$TEST_ROOT/bin"
  export PATH="$TEST_ROOT/bin:$PATH"
  script=scripts/nextcloud-versions.sh
  inventory="$TEST_ROOT/versions.json"
}
teardown() {
  rm -rf "$TEST_ROOT"
}
discover_fixture() {
  bash "$script" discover --wiki-file "tests/fixtures/$1.md" \
    --today "$2" --skip-upstream-check --file "$inventory"
}
@test "historical 2023 maintained section parses three majors" {
  run discover_fixture 2023-maintained 2023-07-01
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.versions[].major] | join(",")' "$inventory")" = 25,26,27 ]
}
@test "historical 2024 maintained section parses two majors" {
  run discover_fixture 2024-maintained 2024-07-01
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.versions[].major] | join(",")' "$inventory")" = 28,29 ]
}
@test "historical 2025 supported section parses two majors" {
  run discover_fixture 2025-supported 2025-07-01
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.versions[].major] | join(",")' "$inventory")" = 30,31 ]
}
@test "current supported section extracts 33, 34 and 35, without 32" {
  run discover_fixture 2026-supported 2026-10-20
  [ "$status" -eq 0 ]
  [ "$(jq -r '[.versions[].major] | join(",")' "$inventory")" = 33,34,35 ]
  [ "$(jq -r '.versions[-1].release' "$inventory")" = 35.0.2 ]
}
@test "malformed wiki preserves the last approved manifest" {
  echo '{"untouched":true}' > "$inventory"
  run discover_fixture 2024-malformed 2024-10-24
  [ "$status" -ne 0 ]
  [[ "$output" == *'::error title=Nextcloud version discovery failed::'* ]]
  [ "$(cat "$inventory")" = '{"untouched":true}' ]
}
@test "upstream EOL overlap and unreleased versions fail closed" {
  run discover_fixture 2025-eol-overlap 2025-04-15
  [ "$status" -ne 0 ]
  [[ "$output" == *'both supported and EOL'* ]]
  run discover_fixture 2026-unreleased 2026-02-12
  [ "$status" -ne 0 ]
  [[ "$output" == *'invalid current release'* ]]
}
@test "renamed wiki heading fails instead of guessing" {
  sed 's/Currently supported versions/Upcoming releases/' \
    tests/fixtures/2026-supported.md > "$TEST_ROOT/broken.md"
  run bash "$script" discover --wiki-file "$TEST_ROOT/broken.md" \
    --skip-upstream-check --today 2026-10-20 --file "$inventory"
  [ "$status" -ne 0 ]
  [ ! -f "$inventory" ]
}
@test "EOL date and future release date prevent a proposal" {
  run discover_fixture 2026-supported 2027-10-01
  [ "$status" -ne 0 ]
  [[ "$output" == *EOL* ]]
  run discover_fixture 2026-supported 2026-02-01
  [ "$status" -ne 0 ]
  [[ "$output" == *EOL* || "$output" == *'in the future'* ]]
}
@test "matrix contains only approved and ordered releases" {
  discover_fixture 2026-supported 2026-10-20
  run bash "$script" matrix --file "$inventory" --today 2026-10-20 \
    --github-output "$TEST_ROOT/output"
  [ "$status" -eq 0 ]
  jq -e '.include | map(.tag) == ["33-fpm","34-fpm","35-fpm"]' \
    <(sed 's/^matrix=//' "$TEST_ROOT/output")
  jq -e '.include[-1].release == "35.0.2"' \
    <(sed 's/^matrix=//' "$TEST_ROOT/output")
}
@test "out-of-order and expired JSON is rejected" {
  discover_fixture 2026-supported 2026-10-20
  jq '.versions |= reverse' "$inventory" > "$TEST_ROOT/reversed.json"
  run bash "$script" matrix --file "$TEST_ROOT/reversed.json" --today 2026-10-20
  [ "$status" -ne 0 ]
  jq '.versions[0].eol = "2026-09"' "$inventory" > "$TEST_ROOT/expired.json"
  run bash "$script" matrix --file "$TEST_ROOT/expired.json" --today 2026-10-20
  [ "$status" -ne 0 ]
}
@test "upstream confirmation verifies release and both FPM architectures" {
  cat > "$TEST_ROOT/bin/curl" <<'MOCK'
#!/usr/bin/env bash
url="${*: -1}"
case "$url" in
  *api.github.com*)
    tag="${url##*/}"
    printf '{"tag_name":"%s","prerelease":false,"draft":false}\n' "$tag"
    ;;
  *hub.docker.com*)
    tag="${url##*/}"
    printf '{"name":"%s","images":[{"os":"linux","architecture":"amd64"},{"os":"linux","architecture":"arm64"}]}\n' "$tag"
    ;;
  *) exit 1 ;;
esac
MOCK
  chmod +x "$TEST_ROOT/bin/curl"
  run bash "$script" discover --wiki-file tests/fixtures/2026-supported.md \
    --today 2026-10-20 --file "$inventory"
  [ "$status" -eq 0 ]
}
@test "missing upstream arm64 architecture rejects proposed manifest" {
  cat > "$TEST_ROOT/bin/curl" <<'MOCK'
#!/usr/bin/env bash
url="${*: -1}"
case "$url" in
  *api.github.com*) printf '{"tag_name":"%s","prerelease":false,"draft":false}\n' "${url##*/}" ;;
  *hub.docker.com*)
    printf '{"name":"%s","images":[{"os":"linux","architecture":"amd64"}]}\n' "${url##*/}"
    ;;
  *) exit 1 ;;
esac
MOCK
  chmod +x "$TEST_ROOT/bin/curl"
  run bash "$script" discover --wiki-file tests/fixtures/2026-supported.md \
    --today 2026-10-20 --file "$inventory"
  [ "$status" -ne 0 ]
  [[ "$output" == *'lacks amd64 or arm64'* ]]
  [ ! -f "$inventory" ]
}
