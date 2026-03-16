resource "kubernetes_namespace" "cert_manager" {
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

resource "null_resource" "cert_manager_resources" {
  triggers = {
    clusterissuer_name     = "letsencrypt-cloudflare"
    grafana_hostname       = var.grafana_hostname
    vault_hostname         = var.vault_hostname
    vault_namespace        = local.vault_namespace
    monitoring_namespace   = local.monitoring_namespace
    acme_email             = local.acme_email
    internal_ca_cert_hash  = sha1(tls_self_signed_cert.vault_internal_ca.cert_pem)
    cloudflare_secret_name = kubernetes_secret_v1.cert_manager_cloudflare_api_token.metadata[0].name
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat <<EOF | kubectl apply -f -
      apiVersion: cert-manager.io/v1
      kind: ClusterIssuer
      metadata:
        name: letsencrypt-cloudflare
      spec:
        acme:
          email: ${local.acme_email}
          server: https://acme-v02.api.letsencrypt.org/directory
          privateKeySecretRef:
            name: letsencrypt-cloudflare-account-key
          solvers:
            - dns01:
                cloudflare:
                  apiTokenSecretRef:
                    name: ${kubernetes_secret_v1.cert_manager_cloudflare_api_token.metadata[0].name}
                    key: api-token
      ---
      apiVersion: cert-manager.io/v1
      kind: Issuer
      metadata:
        name: vault-internal-ca
        namespace: ${local.vault_namespace}
      spec:
        ca:
          secretName: ${kubernetes_secret_v1.vault_internal_ca.metadata[0].name}
      ---
      apiVersion: cert-manager.io/v1
      kind: Certificate
      metadata:
        name: vault-server-tls
        namespace: ${local.vault_namespace}
      spec:
        secretName: vault-server-tls
        duration: 2160h
        renewBefore: 360h
        issuerRef:
          name: vault-internal-ca
          kind: Issuer
        commonName: ${var.vault_hostname}
        dnsNames:
          - ${var.vault_hostname}
          - vault
          - vault.${local.vault_namespace}
          - vault.${local.vault_namespace}.svc
          - vault.${local.vault_namespace}.svc.cluster.local
          - vault-active.${local.vault_namespace}.svc
          - vault-active.${local.vault_namespace}.svc.cluster.local
          - vault-internal.${local.vault_namespace}.svc
          - vault-internal.${local.vault_namespace}.svc.cluster.local
          - '*.vault-internal.${local.vault_namespace}.svc.cluster.local'
          - localhost
        ipAddresses:
          - 127.0.0.1
        usages:
          - server auth
          - client auth
          - digital signature
          - key encipherment
      ---
      apiVersion: cert-manager.io/v1
      kind: Certificate
      metadata:
        name: grafana-tls
        namespace: ${local.monitoring_namespace}
      spec:
        secretName: grafana-tls
        duration: 2160h
        renewBefore: 360h
        issuerRef:
          name: letsencrypt-cloudflare
          kind: ClusterIssuer
        commonName: ${var.grafana_hostname}
        dnsNames:
          - ${var.grafana_hostname}
        usages:
          - server auth
          - digital signature
          - key encipherment
      EOF
    EOT
  }

  depends_on = [
    helm_release.cert_manager,
    kubernetes_secret_v1.cert_manager_cloudflare_api_token,
    kubernetes_secret_v1.vault_internal_ca
  ]
}

resource "null_resource" "wait_for_certificates" {
  triggers = {
    certs_hash = sha1(null_resource.cert_manager_resources.id)
  }

  provisioner "local-exec" {
    command = <<-EOT
      kubectl wait --namespace ${local.vault_namespace} --for=condition=Ready certificate/vault-server-tls --timeout=10m
      kubectl wait --namespace ${local.monitoring_namespace} --for=condition=Ready certificate/grafana-tls --timeout=10m
    EOT
  }

  depends_on = [
    null_resource.cert_manager_resources
  ]
}
