resource "kubernetes_namespace" "cert_manager" {
  depends_on = [time_sleep.eks_access_ready]

  metadata {
    name = local.cert_manager_namespace
  }
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.20.0"
  namespace        = kubernetes_namespace.cert_manager.metadata[0].name
  create_namespace = false
  wait             = true
  timeout          = 600

  values = [
    yamlencode({
      crds = {
        enabled = true
      }
      prometheus = {
        enabled = false
        servicemonitor = {
          enabled = false
        }
      }
    })
  ]
}

resource "kubernetes_secret_v1" "cert_manager_cloudflare_api_token" {
  metadata {
    name      = "cloudflare-api-token"
    namespace = kubernetes_namespace.cert_manager.metadata[0].name
  }

  data = {
    "api-token" = var.cloudflare_api_token
  }

  type = "Opaque"
}

resource "kubectl_manifest" "letsencrypt_cloudflare_cluster_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-cloudflare"
    }
    spec = {
      acme = {
        email  = local.acme_email
        server = "https://acme-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-cloudflare-account-key"
        }
        solvers = [
          {
            dns01 = {
              cloudflare = {
                apiTokenSecretRef = {
                  name = kubernetes_secret_v1.cert_manager_cloudflare_api_token.metadata[0].name
                  key  = "api-token"
                }
              }
            }
          }
        ]
      }
    }
  })

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret_v1.cert_manager_cloudflare_api_token,
  ]
}

resource "kubectl_manifest" "vault_internal_ca_issuer" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Issuer"
    metadata = {
      name      = "vault-internal-ca"
      namespace = local.vault_namespace
    }
    spec = {
      ca = {
        secretName = kubernetes_secret_v1.vault_internal_ca.metadata[0].name
      }
    }
  })

  depends_on = [
    helm_release.cert_manager,
    kubernetes_namespace.vault,
    kubernetes_secret_v1.vault_internal_ca,
  ]
}

resource "kubectl_manifest" "vault_server_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "vault-server-tls"
      namespace = local.vault_namespace
    }
    spec = {
      secretName  = "vault-server-tls"
      duration    = "2160h"
      renewBefore = "360h"
      issuerRef = {
        name = "vault-internal-ca"
        kind = "Issuer"
      }
      commonName = var.vault_hostname
      dnsNames = [
        var.vault_hostname,
        "vault",
        "vault.${local.vault_namespace}",
        "vault.${local.vault_namespace}.svc",
        "vault.${local.vault_namespace}.svc.cluster.local",
        "vault-active.${local.vault_namespace}.svc",
        "vault-active.${local.vault_namespace}.svc.cluster.local",
        "vault-internal.${local.vault_namespace}.svc",
        "vault-internal.${local.vault_namespace}.svc.cluster.local",
        "*.vault-internal.${local.vault_namespace}.svc.cluster.local",
        "localhost",
      ]
      ipAddresses = [
        "127.0.0.1",
      ]
      usages = [
        "server auth",
        "client auth",
        "digital signature",
        "key encipherment",
      ]
    }
  })

  depends_on = [
    kubectl_manifest.vault_internal_ca_issuer,
  ]
}

resource "kubectl_manifest" "grafana_certificate" {
  yaml_body = yamlencode({
    apiVersion = "cert-manager.io/v1"
    kind       = "Certificate"
    metadata = {
      name      = "grafana-tls"
      namespace = local.monitoring_namespace
    }
    spec = {
      secretName  = "grafana-tls"
      duration    = "2160h"
      renewBefore = "360h"
      issuerRef = {
        name = "letsencrypt-cloudflare"
        kind = "ClusterIssuer"
      }
      commonName = var.grafana_hostname
      dnsNames = [
        var.grafana_hostname,
      ]
      usages = [
        "server auth",
        "digital signature",
        "key encipherment",
      ]
    }
  })

  depends_on = [
    kubectl_manifest.letsencrypt_cloudflare_cluster_issuer,
    kubernetes_namespace.monitoring,
  ]
}
