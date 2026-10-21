#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

bin_dir="$tmp_root/bin"
report_dir="$tmp_root/reports"
log_file="$tmp_root/trivy.log"
mkdir -p "$bin_dir" "$report_dir"

cat > "$bin_dir/trivy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

args=("$@")
platform=''
image=''
output=''
format=''
for ((i = 0; i < ${#args[@]}; i++)); do
  case "${args[$i]}" in
    --platform)
      ((i + 1 < ${#args[@]})) || exit 90
      platform="${args[$((i + 1))]}"
      ;;
    --format)
      ((i + 1 < ${#args[@]})) || exit 91
      format="${args[$((i + 1))]}"
      ;;
    --output)
      ((i + 1 < ${#args[@]})) || exit 92
      output="${args[$((i + 1))]}"
      ;;
  esac
done
image="${args[-1]}"

printf '%s|%s|%s\n' "$platform" "$format" "$image" >> "$TRIVY_TEST_LOG"

if [[ "$platform" != "$TRIVY_EXPECTED_PLATFORM" ]]; then
  printf 'unexpected platform: %s\n' "$platform" >&2
  exit 93
fi

if [[ "$format" == sarif ]]; then
  [[ -n "$output" ]] || exit 94
  printf '{"version":"2.1.0"}\n' > "$output"
fi

if [[ -n "${TRIVY_FAIL_IMAGE:-}" && "$image" == "$TRIVY_FAIL_IMAGE" ]]; then
  exit 1
fi
EOF
chmod +x "$bin_dir/trivy"

cat > "$bin_dir/php-runtime-check" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
image=''
platform=''
while (( $# )); do
  case "$1" in
    --image) image=$2; shift 2 ;;
    --platform) platform=$2; shift 2 ;;
    *) printf 'Unexpected PHP checker argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
printf '%s|%s\n' "$platform" "$image" >> "$PHP_RUNTIME_TEST_LOG"
if [[ -n "${PHP_RUNTIME_FAIL_IMAGE:-}" && "$image" == "$PHP_RUNTIME_FAIL_IMAGE" ]]; then
  exit 1
fi
EOF
chmod +x "$bin_dir/php-runtime-check"

export PHP_RUNTIME_CHECK_BIN="$bin_dir/php-runtime-check"
export PHP_RUNTIME_TEST_LOG="$tmp_root/php-runtime.log"

export TRIVY_BIN="$bin_dir/trivy"
export TRIVY_TEST_LOG="$log_file"
export TRIVY_REPORT_DIR="$report_dir"
export TRIVY_EXPECTED_PLATFORM=linux/amd64

bash "$repo_root/scripts/scan-images.sh" \
  'app@linux/amd64=example/app:amd64'
test -f "$report_dir/app-linux-amd64.sarif"
grep -Fqx 'linux/amd64|table|example/app:amd64' "$log_file"
grep -Fqx 'linux/amd64|sarif|example/app:amd64' "$log_file"
grep -Fqx 'linux/amd64|example/app:amd64' "$PHP_RUNTIME_TEST_LOG"

export TRIVY_EXPECTED_PLATFORM=linux/arm64
bash "$repo_root/scripts/scan-images.sh" \
  'app@linux/arm64=example/app:arm64'
test -f "$report_dir/app-linux-arm64.sarif"
grep -Fqx 'linux/arm64|table|example/app:arm64' "$log_file"
grep -Fqx 'linux/arm64|sarif|example/app:arm64' "$log_file"
grep -Fqx 'linux/arm64|example/app:arm64' "$PHP_RUNTIME_TEST_LOG"

if TRIVY_EXPECTED_PLATFORM=linux/arm64 TRIVY_FAIL_IMAGE=example/app:arm64 \
  bash "$repo_root/scripts/scan-images.sh" \
    'app-failure@linux/arm64=example/app:arm64'; then
  printf 'expected a Trivy failure to make the helper fail\n' >&2
  exit 1
fi

if TRIVY_EXPECTED_PLATFORM=linux/amd64 \
  bash "$repo_root/scripts/scan-images.sh" \
    'app@linux/s390x=example/app:amd64'; then
  printf 'expected an unsupported architecture to be rejected\n' >&2
  exit 1
fi

# The PHP release policy must block publication even when Trivy succeeds.
if PHP_RUNTIME_FAIL_IMAGE=example/app:arm64 TRIVY_EXPECTED_PLATFORM=linux/arm64 \
  bash "$repo_root/scripts/scan-images.sh" \
    'app@linux/arm64=example/app:arm64'; then
  printf 'expected the runtime policy failure to reject the image\n' >&2
  exit 1
fi

# Nginx web images contain no PHP runtime.
before=$(wc -l < "$PHP_RUNTIME_TEST_LOG")
TRIVY_EXPECTED_PLATFORM=linux/amd64 bash "$repo_root/scripts/scan-images.sh" \
  'web@linux/amd64=example/web:amd64'
after=$(wc -l < "$PHP_RUNTIME_TEST_LOG")
test "$before" -eq "$after"

echo 'scan-images tests passed'
