variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "lab"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "vault-eks-lab"
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.30"
}

variable "vault_hostname" {
  description = "Vault FQDN"
  type        = string
  default     = "vault.lab-internal.com.br"
}

variable "vault_image_tag" {
  description = "Vault container image tag"
  type        = string
  default     = "1.21.4"
}

variable "domain_name" {
  description = "Primary DNS zone domain name"
  type        = string
  default     = "lab-internal.com.br"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare DNS zone ID"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare account ID used by the tunnel"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions"
  type        = string
  sensitive   = true
}

variable "acme_email" {
  description = "Email used by cert-manager for the ACME account"
  type        = string
  default     = null
}

variable "cloudflare_tunnel_name" {
  description = "Name of the Cloudflare Tunnel resource"
  type        = string
  default     = "vault-eks-lab"
}

variable "cloudflare_tunnel_replicas" {
  description = "Number of cloudflared replicas to run in the cluster"
  type        = number
  default     = 2
}

variable "cloudflare_tunnel_image" {
  description = "cloudflared container image"
  type        = string
  default     = "cloudflare/cloudflared:2025.2.1"
}

variable "vault_snapshot_bucket_name" {
  description = "Bucket used by Vault snapshots"
  type        = string
  default     = "vault-lab-snapshots-unique"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.42.0.0/16"
}

variable "private_subnets" {
  description = "Private subnet CIDRs"
  type        = list(string)
  default     = ["10.42.1.0/24", "10.42.2.0/24", "10.42.3.0/24"]
}

variable "public_subnets" {
  description = "Public subnet CIDRs"
  type        = list(string)
  default     = ["10.42.101.0/24", "10.42.102.0/24", "10.42.103.0/24"]
}

variable "node_instance_type" {
  description = "EKS node instance type"
  type        = string
  default     = "t3.large"
}

variable "vault_storage_class_name" {
  description = "StorageClass used by Vault data PVCs"
  type        = string
  default     = "ebs-gp3"
}

variable "grafana_hostname" {
  description = "Grafana FQDN"
  type        = string
  default     = "grafana.lab-internal.com.br"
}

variable "postgres_allowed_cidrs" {
  description = "Allowed source CIDRs for external PostgreSQL LoadBalancer access"
  type        = list(string)
  default     = []
}

variable "postgres_database_name" {
  description = "PostgreSQL database name"
  type        = string
}

variable "postgres_admin_username" {
  description = "PostgreSQL admin username"
  type        = string
}

variable "postgres_admin_password" {
  description = "PostgreSQL admin password"
  type        = string
  sensitive   = true
}
