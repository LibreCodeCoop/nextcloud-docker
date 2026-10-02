#!/usr/bin/env bash
set -uo pipefail

if [[ $# -eq 0 ]]; then
  printf 'Usage: %s label@linux/amd64=image [label@linux/arm64=image ...]\n' "$0" >&2
  exit 2
fi

trivy_bin="${TRIVY_BIN:-trivy}"
if ! command -v "$trivy_bin" >/dev/null 2>&1; then
  if [[ "$trivy_bin" == "trivy" ]] && command -v trivy.exe >/dev/null 2>&1; then
    trivy_bin=trivy.exe
  else
    printf 'Trivy is required. Install the version documented in README.md.\n' >&2
    exit 127
  fi
fi

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "${script_dir}/.." && pwd)"
config="${repo_root}/trivy.yaml"
report_dir="${TRIVY_REPORT_DIR:-${repo_root}/trivy-results}"

if ! mkdir -p "$report_dir"; then
  printf 'Could not create SARIF output directory: %s\n' "$report_dir" >&2
  exit 1
fi

trivy_config="$config"
if [[ "$trivy_bin" == "trivy.exe" ]] && command -v wslpath >/dev/null 2>&1; then
  trivy_config="$(wslpath -w "$config")"
fi

scan_status=0
scanned=0
failed=()
for image_spec in "$@"; do
  if [[ "$image_spec" != *=* ]]; then
    printf 'Expected label=image, received: %s\n' "$image_spec" >&2
    exit 2
  fi

  label_platform="${image_spec%%=*}"
  label="${label_platform%%@*}"
  platform="${label_platform#*@}"
  image="${image_spec#*=}"

  if [[ "$label_platform" != *@* || ! "$label" =~ ^[A-Za-z0-9_-]+$ || -z "$image" ]]; then
    printf 'Invalid image specification: %s\n' "$image_spec" >&2
    exit 2
  fi
  if [[ "$platform" != linux/amd64 && "$platform" != linux/arm64 ]]; then
    printf 'Unsupported platform in image specification: %s\n' "$image_spec" >&2
    exit 2
  fi

  printf '\nScanning %s for %s (%s), table output\n' "$label" "$platform" "$image"
  scanned=$((scanned + 1))
  if ! "$trivy_bin" image --config "$trivy_config" --platform "$platform" --format table "$image"; then
    scan_status=1
    failed+=("${label} (${platform})")
  fi

  printf '\nScanning %s for %s (%s), SARIF output\n' "$label" "$platform" "$image"
  platform_suffix="${platform//\//-}"
  sarif_output="${report_dir}/${label}-${platform_suffix}.sarif"
  if [[ "$trivy_bin" == "trivy.exe" ]] && command -v wslpath >/dev/null 2>&1; then
    sarif_output="$(wslpath -w "$sarif_output")"
  fi
  if ! "$trivy_bin" image --config "$trivy_config" --platform "$platform" --format sarif --output "$sarif_output" "$image"; then
    scan_status=1
  fi
done

if [[ ${#failed[@]} -gt 0 ]]; then
  {
    printf '\n==============================================================\n'
    printf 'SCAN POLICY FAILED for %d of %d image(s):\n' "${#failed[@]}" "$scanned"
    for entry in "${failed[@]}"; do
      printf '  - %s\n' "$entry"
    done
    printf '\nPolicy: %s\n' "$trivy_config"
    printf 'This means HIGH/CRITICAL vulnerabilities with a published fix,\n'
    printf 'or an end-of-life base image. See the table output above for\n'
    printf 'the exact findings. Fix the image; do not weaken the policy.\n'
    printf '==============================================================\n'
  } >&2
elif [[ "$scan_status" -eq 0 ]]; then
  printf '\nScan policy passed for %d image(s).\n' "$scanned"
fi

exit "$scan_status"
