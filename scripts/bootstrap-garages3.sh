#!/usr/bin/env bash
set -euo pipefail

compose_file=${GARAGES3_COMPOSE_FILE:-docker-compose-garages3.yml}
garage_service=${GARAGES3_SERVICE:-garage}
garage_toml=${GARAGES3_GARAGE_TOML:-garage/garage.toml}
bucket_name=${GARAGES3_BUCKET:-nextcloud}
key_name=${GARAGES3_KEY_NAME:-nextcloud-app}
env_file=${GARAGES3_ENV_FILE:-.env}
skip_garage_up=${GARAGES3_SKIP_GARAGE_UP:-0}
auto_layout=${GARAGES3_AUTO_LAYOUT:-false}
layout_zone=${GARAGES3_LAYOUT_ZONE:-local}
layout_capacity=${GARAGES3_LAYOUT_CAPACITY:-1TB}

compose() {
  docker compose -f "$compose_file" "$@"
}

garage_exec() {
  compose exec -T "$garage_service" /garage "$@"
}

env_value() {
  local file=$1
  local key=$2

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  awk -F= -v key="$key" '
    $1 == key {
      print substr($0, length(key) + 2)
      exit
    }
  ' "$file"
}

ensure_rpc_secret() {
  if grep -q 'rpc_secret = "CHANGE_ME_WITH_OPENSSL_RAND_HEX_32"' "$garage_toml"; then
    local rpc_secret
    rpc_secret=${GARAGES3_RPC_SECRET:-}

    if [[ -z "$rpc_secret" ]]; then
      if command -v openssl >/dev/null 2>&1; then
        rpc_secret=$(openssl rand -hex 32)
      else
        echo "openssl is required when GARAGES3_RPC_SECRET is not set" >&2
        exit 1
      fi
    fi

    perl -0pi -e 's/^rpc_secret = ".*"$/rpc_secret = "'"$rpc_secret"'"/m' "$garage_toml"
    echo "Updated $garage_toml with a rpc_secret value"
  fi
}

ensure_rpc_secret

if [[ ! -f "$env_file" ]]; then
  if [[ -f .env.example ]]; then
    cp .env.example "$env_file"
  else
    : > "$env_file"
  fi
fi

if [[ "$skip_garage_up" != 1 ]]; then
  compose up -d --force-recreate "$garage_service"
fi

until garage_exec status >/dev/null 2>&1; do
  sleep 2
done

if [[ "$auto_layout" == 1 || "${auto_layout,,}" == "true" ]]; then
  if garage_exec layout show | grep -q "No nodes currently have a role in the cluster."; then
    node_id=$(garage_exec node id | awk -F'@' 'NR == 1 {print $1; exit}')
    if [[ -z "$node_id" ]]; then
      echo "Could not determine Garage node id for automatic layout setup" >&2
      exit 1
    fi

    garage_exec layout assign "$node_id" -z "$layout_zone" -c "$layout_capacity" >/dev/null
    layout_show_output=$(garage_exec layout show)
    layout_version=$(printf '%s\n' "$layout_show_output" | awk '/garage layout apply --version/ {print $5; exit}')
    if [[ -z "$layout_version" ]]; then
      echo "$layout_show_output" >&2
      echo "Could not determine the new Garage layout version" >&2
      exit 1
    fi

    garage_exec layout apply --version "$layout_version" >/dev/null
    echo "Applied automatic Garage layout for node $node_id (version $layout_version)"

    until garage_exec status | grep -q "HEALTHY NODES"; do
      sleep 2
    done
  fi
fi

garage_exec bucket create "$bucket_name" >/dev/null 2>&1 || true

secret_key=$(env_value "$env_file" GARAGES3_SECRET)
existing_key_id=$(env_value "$env_file" GARAGES3_KEY_ID)
legacy_key=$(env_value "$env_file" GARAGES3_KEY)

if [[ -n "$existing_key_id" && -n "$secret_key" ]]; then
  key_id="$existing_key_id"
  echo "Reusing Garage key credentials from $env_file"
elif [[ -n "$legacy_key" && -n "$secret_key" ]]; then
  key_id=$(garage_exec key list | awk -v name="$key_name" '$2 == name {print $1; exit}')

  if [[ -n "$key_id" ]]; then
    echo "Reusing Garage key credentials from $env_file"
  else
    matching_key_ids=$(garage_exec key list | awk -v name="$key_name" '$2 == name {print $1}')

    if [[ -n "$matching_key_ids" ]]; then
      while read -r stale_key_id; do
        [[ -n "$stale_key_id" ]] || continue
        garage_exec key delete --yes "$stale_key_id" >/dev/null
      done <<< "$matching_key_ids"
      echo "Removed stale Garage keys named $key_name"
    fi

    key_output=$(garage_exec key create "$key_name" 2>&1 || true)
    if [[ "$key_output" != *"Secret key:"* ]]; then
      echo "$key_output" >&2
      echo "Failed to create Garage key $key_name" >&2
      exit 1
    fi

    key_id=$(printf '%s\n' "$key_output" | awk -F': ' '/^Key ID:/ {print $2; exit}')
    secret_key=$(printf '%s\n' "$key_output" | awk -F': ' '/^Secret key:/ {print $2; exit}')
    if [[ -z "$key_id" ]]; then
      key_id=$(printf '%s\n' "$key_output" | awk '/^GK[0-9a-f]+/ {print $1; exit}')
    fi
    if [[ -z "$secret_key" ]]; then
      echo "$key_output" >&2
      echo "Could not extract the secret key from Garage output" >&2
      exit 1
    fi
    if [[ -z "$key_id" ]]; then
      echo "$key_output" >&2
      echo "Could not extract the Garage access key ID from output" >&2
      exit 1
    fi
  fi
else
  key_output=$(garage_exec key create "$key_name" 2>&1 || true)
  if [[ "$key_output" != *"Secret key:"* ]]; then
    echo "$key_output" >&2
    echo "Failed to create Garage key $key_name" >&2
    exit 1
  fi

  key_id=$(printf '%s\n' "$key_output" | awk -F': ' '/^Key ID:/ {print $2; exit}')
  secret_key=$(printf '%s\n' "$key_output" | awk -F': ' '/^Secret key:/ {print $2; exit}')
  if [[ -z "$key_id" ]]; then
    key_id=$(printf '%s\n' "$key_output" | awk '/^GK[0-9a-f]+/ {print $1; exit}')
  fi
  if [[ -z "$secret_key" ]]; then
    echo "$key_output" >&2
    echo "Could not extract the secret key from Garage output" >&2
    exit 1
  fi
  if [[ -z "$key_id" ]]; then
    echo "$key_output" >&2
    echo "Could not extract the Garage access key ID from output" >&2
    exit 1
  fi
fi

garage_exec bucket allow --read --write --key "$key_id" "$bucket_name"

write_env() {
  local file=$1
  local key=$2
  local value=$3
  local tmp

  tmp=$(mktemp)
  awk -v key="$key" -v value="$value" '
    BEGIN { found = 0 }
    $0 ~ "^" key "=" {
      print key "=" value
      found = 1
      next
    }
    { print }
    END {
      if (!found) {
        print key "=" value
      }
    }
  ' "$file" > "$tmp"
  mv "$tmp" "$file"
}

write_env "$env_file" GARAGES3_BUCKET "$bucket_name"
write_env "$env_file" GARAGES3_KEY "$key_name"
write_env "$env_file" GARAGES3_KEY_ID "$key_id"
write_env "$env_file" GARAGES3_SECRET "$secret_key"
write_env "$env_file" GARAGES3_HOSTNAME "${GARAGES3_HOSTNAME:-host.docker.internal}"
write_env "$env_file" GARAGES3_PORT "${GARAGES3_PORT:-3900}"
write_env "$env_file" GARAGES3_REGION "${GARAGES3_REGION:-garage}"
write_env "$env_file" GARAGES3_USE_SSL "${GARAGES3_USE_SSL:-false}"
write_env "$env_file" GARAGES3_USE_PATH_STYLE "${GARAGES3_USE_PATH_STYLE:-true}"
write_env "$env_file" GARAGES3_AUTOCREATE "${GARAGES3_AUTOCREATE:-true}"
write_env "$env_file" GARAGES3_VERIFY_BUCKET_EXISTS "${GARAGES3_VERIFY_BUCKET_EXISTS:-true}"

echo "Wrote Garage credentials to $env_file"
echo "Bucket: $bucket_name"
echo "Key: $key_name"
