# EKS + Vault com Openterraform

Esta stack provisiona:

1. VPC e EKS com add-ons basicos
2. IRSA e IAM para o Vault
3. KMS para auto-unseal do Vault
4. Bucket S3 para snapshots do Vault
5. cert-manager com ACME DNS-01 usando Cloudflare
6. Cloudflare Tunnel para publicar Vault e Grafana sem LoadBalancer publico
7. Certificados TLS para Vault e Grafana
8. Prometheus, Grafana, Loki e Promtail
9. Vault HA com Raft e telemetria integrada
10. PostgreSQL no cluster para uso com secrets dinamicos

## Uso

No PowerShell:

```powershell
$env:TF_VAR_postgres_admin_password = "sua-senha-postgres"
$env:TF_VAR_cloudflare_api_token = "seu-token-cloudflare"
```

```bash
cp terraform.tfvars.example terraform.tfvars
# ajuste valores em terraform.tfvars
# inclua em `vault_snapshot_bucket_admin_principal_arns` os ARNs IAM que podem operar o bucket S3 de snapshots

export TF_VAR_postgres_admin_password='sua-senha-postgres'
export TF_VAR_cloudflare_api_token='seu-token-cloudflare'

terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars -auto-approve
```

## Acesso

- Vault: `https://vault.lab-internal.com.br`
- Grafana: `https://grafana.lab-internal.com.br`
- Usuario padrao do Grafana: `admin`
- Senha padrao do Grafana:

```bash
kubectl -n monitoring get secret kube-prometheus-stack-grafana \
  -o jsonpath="{.data.admin-password}" | base64 -d; echo
```

Comandos uteis tambem via outputs do Terraform:

```bash
terraform output vault_url
terraform output grafana_url
terraform output grafana_admin_username
terraform output -raw grafana_admin_password_command
terraform output -raw vault_status_command
terraform output -raw vault_raft_peers_command
```

## O Que O Bootstrap Configura

O script `scripts/bootstrap_vault.py` configura automaticamente no Vault:

- inicializacao e persistencia do `root_token` em `bootstrap/vault-init.json`
- secret engine `kv-v2` em `kv/`
- auth method `kubernetes/`
- audit device `file/` com `file_path=stdout` e `format=json`
- client counters com `enabled=enable` e `retention_months=12`
- secret engine `database/`
- connection `postgres`
- role dinamica `postgres-dynamic` com `default_ttl=10m` e `max_ttl=1h`

## Validacoes

Certificados emitidos:

```bash
kubectl get certificates -A
```

Pods principais:

```bash
kubectl get pods -n monitoring
kubectl get pods -n vault
kubectl get pods -n cloudflare
```

Status do Vault:

```bash
kubectl exec -n vault vault-0 -- sh -lc 'VAULT_ADDR=https://vault-0.vault-internal.vault.svc.cluster.local:8200 VAULT_CACERT=/vault/userconfig/ca/ca.crt vault status'
```

Peers do Raft:

```bash
ROOT_TOKEN=$(jq -r .root_token bootstrap/vault-init.json)
kubectl exec -n vault vault-0 -- sh -lc "VAULT_ADDR=https://vault-0.vault-internal.vault.svc.cluster.local:8200 VAULT_CACERT=/vault/userconfig/ca/ca.crt VAULT_TOKEN=$ROOT_TOKEN vault operator raft list-peers"
```

Audit, counters e database engine:

```bash
ROOT_TOKEN=$(jq -r .root_token bootstrap/vault-init.json)

kubectl exec -n vault vault-0 -- sh -lc "VAULT_ADDR=https://vault-0.vault-internal.vault.svc.cluster.local:8200 VAULT_CACERT=/vault/userconfig/ca/ca.crt VAULT_TOKEN=$ROOT_TOKEN vault audit list"
kubectl exec -n vault vault-0 -- sh -lc "VAULT_ADDR=https://vault-0.vault-internal.vault.svc.cluster.local:8200 VAULT_CACERT=/vault/userconfig/ca/ca.crt VAULT_TOKEN=$ROOT_TOKEN vault read sys/internal/counters/config"
kubectl exec -n vault vault-0 -- sh -lc "VAULT_ADDR=https://vault-0.vault-internal.vault.svc.cluster.local:8200 VAULT_CACERT=/vault/userconfig/ca/ca.crt VAULT_TOKEN=$ROOT_TOKEN vault read database/config/postgres"
kubectl exec -n vault vault-0 -- sh -lc "VAULT_ADDR=https://vault-0.vault-internal.vault.svc.cluster.local:8200 VAULT_CACERT=/vault/userconfig/ca/ca.crt VAULT_TOKEN=$ROOT_TOKEN vault read database/roles/postgres-dynamic"
```

Logs do tunnel em caso de erro externo:

```bash
kubectl logs -n cloudflare deploy/cloudflared --since=5m
```

## Observacoes

- Zona DNS esperada na Cloudflare: `lab-internal.com.br`.
- O token da Cloudflare precisa permitir ao menos `Zone DNS Edit` e `Account Cloudflare Tunnel Edit`.
- O cert-manager usa DNS-01 na Cloudflare para emitir o certificado publico do Grafana.
- O Vault usa uma CA interna dedicada para trafego entre pods e para a origem validada pelo `cloudflared`.
- O `cloudflared` publica Vault e Grafana pelos services internos do cluster.
- O Vault publica metricas de telemetria e cria `ServiceMonitor` para coleta pelo Prometheus Operator.
- O Grafana provisiona automaticamente os dashboards `Vault Telemetry` e `Vault Audit Logs` a partir dos JSONs em `grafana-dashboard/`.
- Os logs de auditoria do Vault enviados para `stdout` ficam consultaveis no Loki logo apos o `apply`.
- O bucket S3 de snapshots libera somente a role do Vault, o `root` da conta e os ARNs definidos em `vault_snapshot_bucket_admin_principal_arns`.
