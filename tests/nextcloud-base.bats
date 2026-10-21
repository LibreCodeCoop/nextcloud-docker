#!/usr/bin/env bats

setup() {
  cd "$BATS_TEST_DIRNAME/.."
}

@test "each reviewed Nextcloud release has a pinned, readable base" {
  while IFS=$'\t' read -r major release; do
    run bash scripts/select-nextcloud-base.sh "${release}-fpm"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^nextcloud:${release}-fpm@sha256:[a-f0-9]{64}$ ]]
    [ -f ".docker/nextcloud-bases/$major/Dockerfile" ]
    [ "$(head -n1 ".docker/nextcloud-bases/$major/Dockerfile")" = "FROM $output" ]
  done < <(jq -r '.versions[] | [.major,.release] | @tsv' .github/nextcloud-supported.json)
}

@test "invalid release tags and unsupported majors are rejected" {
  run bash scripts/select-nextcloud-base.sh '35.0.2-fpm;echo INJECTED'
  [ "$status" -ne 0 ]
  run bash scripts/select-nextcloud-base.sh 36.0.0-fpm
  [ "$status" -ne 0 ]
}

@test "a different patch release cannot silently reuse the previous digest" {
  run bash scripts/select-nextcloud-base.sh 35.0.99-fpm
  [ "$status" -ne 0 ]
  [[ "$output" == *'does not match reviewed release'* ]]
}
