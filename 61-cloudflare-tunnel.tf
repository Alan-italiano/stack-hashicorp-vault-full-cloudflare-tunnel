resource "random_id" "cloudflare_tunnel_secret" {
  byte_length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "cluster" {
  account_id = var.cloudflare_account_id
  name       = var.cloudflare_tunnel_name
  config_src = "local"
  secret     = random_id.cloudflare_tunnel_secret.b64_std
}

resource "cloudflare_record" "vault" {
  zone_id         = var.cloudflare_zone_id
  allow_overwrite = true
  name            = replace(var.vault_hostname, ".${var.domain_name}", "")
  type            = "CNAME"
  content         = "${cloudflare_zero_trust_tunnel_cloudflared.cluster.id}.cfargotunnel.com"
  proxied         = true
  ttl             = 1
}

resource "cloudflare_record" "grafana" {
  zone_id         = var.cloudflare_zone_id
  allow_overwrite = true
  name            = replace(var.grafana_hostname, ".${var.domain_name}", "")
  type            = "CNAME"
  content         = "${cloudflare_zero_trust_tunnel_cloudflared.cluster.id}.cfargotunnel.com"
  proxied         = true
  ttl             = 1
}

resource "kubernetes_namespace" "cloudflare" {
  metadata {
    name = local.cloudflare_namespace
  }
}

resource "kubernetes_secret_v1" "cloudflare_tunnel_credentials" {
  metadata {
    name      = "cloudflared-credentials"
    namespace = kubernetes_namespace.cloudflare.metadata[0].name
  }

  data = {
    "credentials.json" = jsonencode({
      AccountTag   = var.cloudflare_account_id
      TunnelID     = cloudflare_zero_trust_tunnel_cloudflared.cluster.id
      TunnelSecret = random_id.cloudflare_tunnel_secret.b64_std
    })
  }

  type = "Opaque"
}

resource "kubernetes_config_map_v1" "cloudflare_tunnel" {
  metadata {
    name      = "cloudflared-config"
    namespace = kubernetes_namespace.cloudflare.metadata[0].name
  }

  data = {
    "config.yaml" = yamlencode({
      tunnel              = cloudflare_zero_trust_tunnel_cloudflared.cluster.id
      "credentials-file" = "/etc/cloudflared/creds/credentials.json"
      metrics             = "0.0.0.0:2000"
      ingress = [
        {
          hostname = var.vault_hostname
          service  = "https://vault-active.${kubernetes_namespace.vault.metadata[0].name}.svc.cluster.local:8200"
          originRequest = {
            httpHostHeader   = var.vault_hostname
            originServerName = "vault-internal.${kubernetes_namespace.vault.metadata[0].name}.svc.cluster.local"
            caPool           = "/etc/cloudflared/ca/vault/ca.crt"
          }
        },
        {
          hostname = var.grafana_hostname
          service  = "https://kube-prometheus-stack-grafana.${kubernetes_namespace.monitoring.metadata[0].name}.svc.cluster.local:80"
          originRequest = {
            httpHostHeader   = var.grafana_hostname
            originServerName = var.grafana_hostname
          }
        },
        {
          service = "http_status:404"
        }
      ]
    })
  }
}

resource "kubernetes_deployment_v1" "cloudflared" {
  metadata {
    name      = "cloudflared"
    namespace = kubernetes_namespace.cloudflare.metadata[0].name
    labels = {
      app = "cloudflared"
    }
  }

  spec {
    replicas = var.cloudflare_tunnel_replicas

    selector {
      match_labels = {
        app = "cloudflared"
      }
    }

    template {
      metadata {
        labels = {
          app = "cloudflared"
        }
        annotations = {
          "checksum/config"      = sha1(kubernetes_config_map_v1.cloudflare_tunnel.data["config.yaml"])
          "checksum/credentials" = sha1(kubernetes_secret_v1.cloudflare_tunnel_credentials.data["credentials.json"])
          "checksum/vault-ca"    = sha1(kubernetes_secret_v1.vault_internal_ca_cloudflared.data["ca.crt"])
        }
      }

      spec {
        container {
          name  = "cloudflared"
          image = var.cloudflare_tunnel_image
          args  = ["tunnel", "--config", "/etc/cloudflared/config/config.yaml", "run"]

          port {
            container_port = 2000
            name           = "metrics"
          }

          readiness_probe {
            http_get {
              path = "/ready"
              port = "metrics"
            }

            initial_delay_seconds = 10
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/ready"
              port = "metrics"
            }

            initial_delay_seconds = 10
            period_seconds        = 10
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "250m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/cloudflared/config"
            read_only  = true
          }

          volume_mount {
            name       = "credentials"
            mount_path = "/etc/cloudflared/creds"
            read_only  = true
          }

          volume_mount {
            name       = "vault-ca"
            mount_path = "/etc/cloudflared/ca/vault"
            read_only  = true
          }
        }

        volume {
          name = "config"

          config_map {
            name = kubernetes_config_map_v1.cloudflare_tunnel.metadata[0].name
          }
        }

        volume {
          name = "credentials"

          secret {
            secret_name = kubernetes_secret_v1.cloudflare_tunnel_credentials.metadata[0].name
          }
        }

        volume {
          name = "vault-ca"

          secret {
            secret_name = kubernetes_secret_v1.vault_internal_ca_cloudflared.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    helm_release.vault,
    helm_release.kube_prometheus_stack,
    kubernetes_secret_v1.vault_internal_ca_cloudflared
  ]
}
