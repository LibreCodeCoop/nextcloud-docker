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

export TRIVY_BIN="$bin_dir/trivy"
export TRIVY_TEST_LOG="$log_file"
export TRIVY_REPORT_DIR="$report_dir"
export TRIVY_EXPECTED_PLATFORM=linux/amd64

bash "$repo_root/scripts/scan-images.sh" \
  'app@linux/amd64=example/app:amd64'
test -f "$report_dir/app-linux-amd64.sarif"
grep -Fqx 'linux/amd64|table|example/app:amd64' "$log_file"
grep -Fqx 'linux/amd64|sarif|example/app:amd64' "$log_file"

export TRIVY_EXPECTED_PLATFORM=linux/arm64
bash "$repo_root/scripts/scan-images.sh" \
  'app@linux/arm64=example/app:arm64'
test -f "$report_dir/app-linux-arm64.sarif"
grep -Fqx 'linux/arm64|table|example/app:arm64' "$log_file"
grep -Fqx 'linux/arm64|sarif|example/app:arm64' "$log_file"

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

echo 'scan-images tests passed'
