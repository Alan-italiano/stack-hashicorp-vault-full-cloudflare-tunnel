#!/usr/bin/env bash
# Executa tofu apply localmente.
#
# Variáveis sensíveis devem ser exportadas antes de rodar:
#   export TF_VAR_cloudflare_api_token="..."
#   export TF_VAR_postgres_admin_password="..."
#   export TF_VAR_vault_oidc_client_secret="..."   # opcional
#
# Para usar backend S3 local passe o arquivo de config:
#   tofu init -backend-config=backend.local.hcl
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

: "${TF_VAR_cloudflare_api_token:?Variável TF_VAR_cloudflare_api_token não definida}"
: "${TF_VAR_postgres_admin_password:?Variável TF_VAR_postgres_admin_password não definida}"

tofu init -upgrade
tofu apply -var-file=terraform.tfvars -auto-approve
