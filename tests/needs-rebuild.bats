#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
  TEST_DIR="$(mktemp -d)"
  export PATH="$TEST_DIR:$PATH"
  export CHECK_MODE=matching
  SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  cat > "$TEST_DIR/docker" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
image="$4"
if [[ "$6" == '{{.Manifest.Digest}}' ]]; then
  [[ "${CHECK_MODE:-}" == registry-failure ]] && exit 1
  printf 'sha256:%064d\n' 1
  exit 0
fi
[[ "${CHECK_MODE:-}" == missing && "$image" == *35-fpm ]] && exit 1
digest="sha256:$(printf '%064d' 1)"
revision="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
if [[ "${CHECK_MODE:-}" == outdated && "$image" == *34-fpm ]]; then
  digest="sha256:$(printf '%064d' 2)"
fi
if [[ "${CHECK_MODE:-}" == old-revision ]]; then
  revision="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
fi
if [[ "${CHECK_MODE:-}" == missing-arm64 ]]; then
  platforms='["linux/amd64"]'
else
  platforms='["linux/amd64","linux/arm64"]'
fi
jq -cn --arg d "$digest" --arg r "$revision" --argjson p "$platforms" '
  reduce $p[] as $platform ({}; .[$platform] = {
    config: {Labels: {"org.opencontainers.image.base.digest": $d,
                      "org.opencontainers.image.revision": $r}}
  })'
MOCK
  chmod +x "$TEST_DIR/docker"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "unchanged bases and published architectures skip the build" {
  run bash scripts/needs-rebuild.sh ghcr.io/example/app ghcr.io/example/web "$SHA"
  [ "$status" -eq 0 ]
  [ "$output" = false ]
}

@test "updated base digest requests a rebuild" {
  CHECK_MODE=outdated run bash scripts/needs-rebuild.sh ghcr.io/example/app ghcr.io/example/web "$SHA"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "missing or incomplete GHCR images request a rebuild" {
  CHECK_MODE=missing run bash scripts/needs-rebuild.sh ghcr.io/example/app ghcr.io/example/web "$SHA"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
  CHECK_MODE=missing-arm64 run bash scripts/needs-rebuild.sh ghcr.io/example/app ghcr.io/example/web "$SHA"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "unpublished Git revision requests a rebuild" {
  CHECK_MODE=old-revision run bash scripts/needs-rebuild.sh ghcr.io/example/app ghcr.io/example/web "$SHA"
  [ "$status" -eq 0 ]
  [ "$output" = true ]
}

@test "upstream inspection errors do not report an unchanged image" {
  CHECK_MODE=registry-failure run bash scripts/needs-rebuild.sh ghcr.io/example/app ghcr.io/example/web "$SHA"
  [ "$status" -ne 0 ]
}
