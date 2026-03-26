#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

export TF_VAR_postgres_admin_password=''
export TF_VAR_cloudflare_api_token=''

tofu init -upgrade
tofu destroy -var-file=terraform.tfvars -auto-approve
