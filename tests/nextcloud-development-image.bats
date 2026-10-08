#!/usr/bin/env bats

setup() {
  TEST_ROOT="$(mktemp -d)"
  BIN_DIR="$TEST_ROOT/bin"
  mkdir -p "$BIN_DIR"
  export PATH="$BIN_DIR:$PATH"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

@test "resolve upstream emits validated metadata" {
  cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
if [[ "$args" == *"auth.docker.io/token"* ]]; then
  printf '{"token":"test-token"}'
elif [[ "$args" == *"registry-1.docker.io"* ]]; then
  headers=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-D" ]; then
      headers=$2
      shift 2
    else
      shift
    fi
  done
  printf 'docker-content-digest: sha256:%064d\r\n' 0 > "$headers"
elif [[ "$args" == *".sha512"* ]]; then
  output=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
      output=$2
      shift 2
    else
      shift
    fi
  done
  printf '%0128d  latest-master.tar.bz2\n' 0 > "$output"
else
  exit 1
fi
EOF
  chmod +x "$BIN_DIR/curl"

  run scripts/resolve-nextcloud-upstream.sh stable-fpm https://download.nextcloud.com/server/daily/latest-master.tar.bz2

  [ "$status" -eq 0 ]
  [[ "$output" == *"base_image=nextcloud@sha256:"* ]]
  [[ "$output" == *"source_sha512="* ]]
  [[ "$output" == *"created="* ]]
}

@test "resolve upstream rejects an invalid base digest" {
  cat > "$BIN_DIR/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
if [[ "$args" == *"auth.docker.io/token"* ]]; then
  printf '{"token":"test-token"}'
elif [[ "$args" == *"registry-1.docker.io"* ]]; then
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-D" ]; then
      printf 'docker-content-digest: invalid\r\n' > "$2"
      exit 0
    fi
    shift
  done
fi
EOF
  chmod +x "$BIN_DIR/curl"

  run scripts/resolve-nextcloud-upstream.sh stable-fpm https://download.nextcloud.com/server/daily/latest-master.tar.bz2

  [ "$status" -ne 0 ]
  [[ "$output" == *"Could not resolve nextcloud:stable-fpm digest"* ]]
}

@test "architecture publication uses only the requested staging tag" {
  cat > "$BIN_DIR/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_ROOT/docker.log"
EOF
  chmod +x "$BIN_DIR/docker"

  run scripts/push-master-architecture.sh ghcr.io/example/app scan/master:amd64 abc123 amd64

  [ "$status" -eq 0 ]
  grep -Fx "tag scan/master:amd64 ghcr.io/example/app:master-fpm-abc123-amd64" "$TEST_ROOT/docker.log"
  grep -Fx "push ghcr.io/example/app:master-fpm-abc123-amd64" "$TEST_ROOT/docker.log"
}

@test "architecture publication rejects unsupported architectures" {
  run scripts/push-master-architecture.sh ghcr.io/example/app scan/master:s390x abc123 s390x

  [ "$status" -eq 2 ]
  [[ "$output" == *"Unsupported architecture: s390x"* ]]
}

@test "manifest publication combines exactly amd64 and arm64" {
  cat > "$BIN_DIR/docker" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$TEST_ROOT/docker.log"
EOF
  chmod +x "$BIN_DIR/docker"

  run scripts/publish-master-manifest.sh ghcr.io/example/app abc123

  [ "$status" -eq 0 ]
  grep -Fx "buildx imagetools create --tag ghcr.io/example/app:master-fpm ghcr.io/example/app:master-fpm-abc123-amd64 ghcr.io/example/app:master-fpm-abc123-arm64" "$TEST_ROOT/docker.log"
  grep -Fx "buildx imagetools inspect ghcr.io/example/app:master-fpm" "$TEST_ROOT/docker.log"
}
