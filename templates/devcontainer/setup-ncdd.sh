#!/usr/bin/env bash
set -euo pipefail

install_root="${HOME}/.local/share/ncdd"
bin_dir="${HOME}/.local/bin"

mkdir -p "${HOME}/.local/share" "${bin_dir}"

if [ -d "${install_root}/.git" ]; then
  git -C "${install_root}" fetch --depth=1 origin main
  git -C "${install_root}" reset --hard origin/main
else
  rm -rf "${install_root}"
  git clone --depth=1 https://github.com/LibreCodeCoop/nextcloud-docker.git "${install_root}"
fi

chmod +x "${install_root}/bin/ncdd"
ln -sfn "${install_root}/bin/ncdd" "${bin_dir}/ncdd"

if [ ! -f .ncdd.yml ]; then
  app_id=$(basename "${PWD}")
  cat > .ncdd.yml <<EOF
nextcloud:
  default: stable35
app:
  id: ${app_id}
  source: .
  path: /var/www/html/apps-extra/${app_id}
  runtime_user: www-data
EOF
fi

ncdd help ai
