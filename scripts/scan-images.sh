#!/usr/bin/env bash
set -uo pipefail

if [[ $# -eq 0 ]]; then
  printf 'Usage: %s label=image [label=image ...]\n' "$0" >&2
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
for image_spec in "$@"; do
  if [[ "$image_spec" != *=* ]]; then
    printf 'Expected label=image, received: %s\n' "$image_spec" >&2
    exit 2
  fi

  label="${image_spec%%=*}"
  image="${image_spec#*=}"
  if [[ ! "$label" =~ ^[A-Za-z0-9_-]+$ || -z "$image" ]]; then
    printf 'Invalid image specification: %s\n' "$image_spec" >&2
    exit 2
  fi

  printf '\nScanning %s (%s), table output\n' "$label" "$image"
  if ! "$trivy_bin" image --config "$trivy_config" --format table "$image"; then
    scan_status=1
  fi

  printf '\nScanning %s (%s), SARIF output\n' "$label" "$image"
  sarif_output="${report_dir}/${label}.sarif"
  if [[ "$trivy_bin" == "trivy.exe" ]] && command -v wslpath >/dev/null 2>&1; then
    sarif_output="$(wslpath -w "$sarif_output")"
  fi
  if ! "$trivy_bin" image --config "$trivy_config" --format sarif --output "$sarif_output" "$image"; then
    scan_status=1
  fi
done

exit "$scan_status"
