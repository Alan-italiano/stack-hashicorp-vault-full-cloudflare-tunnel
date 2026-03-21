locals {
  tags = {
    Project     = "vault-eks"
    Environment = var.environment
    ManagedBy   = "Openterraform"
  }

  postgres_allowed_cidrs = distinct(concat(var.postgres_allowed_cidrs, [var.vpc_cidr]))

  vault_namespace        = "vault"
  vault_service_account  = "vault"
  monitoring_namespace   = "monitoring"
  postgres_namespace     = "postgres"
  cloudflare_namespace   = "cloudflare"
  cert_manager_namespace = "cert-manager"
  acme_email             = coalesce(var.acme_email, "admin@${var.domain_name}")
}
