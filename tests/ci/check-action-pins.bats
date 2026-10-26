#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/../.."
}

check_pins() {
  local file line ref count=0
  local use_ref='^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*([^[:space:]]+)'
  local release='^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*[a-zA-Z0-9_.-]+(/[a-zA-Z0-9_.-]+)+@[a-f0-9]{40}[[:space:]]+#[[:space:]]+v?[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$'
  local template='^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*LibreCodeCoop/nextcloud-docker/\.github/workflows/[a-zA-Z0-9_.-]+@[a-f0-9]{40}[[:space:]]+#[[:space:]]+main[[:space:]]*$'

  for file in "$@"; do
    while IFS= read -r line || [[ -n $line ]]; do
      [[ $line =~ $use_ref ]] || continue
      ref="${BASH_REMATCH[2]}"
      [[ $ref == ./* ]] && continue
      ((count += 1))
      if [[ ! $line =~ $release && ! $line =~ $template ]]; then
        echo "$file: $line" >&2
        return 1
      fi
    done < "$file"
  done

  (( count > 0 ))
}

@test "all external Actions and reusable workflows are pinned to full SHAs" {
  local file
  local -a files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find .github templates/workflows -type f \( -name '*.yml' -o -name '*.yaml' \) -print0)

  check_pins "${files[@]}"
}

@test "mutable tags and missing version comments are rejected" {
  local fixture="$BATS_TEST_TMPDIR/unpinned.yml"
  printf '    - uses: actions/checkout@v7\n' > "$fixture"
  run check_pins "$fixture"
  [ "$status" -ne 0 ]
  [[ $output == *'actions/checkout@v7'* ]]

  printf '    - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1\n' > "$fixture"
  run check_pins "$fixture"
  [ "$status" -ne 0 ]
}
