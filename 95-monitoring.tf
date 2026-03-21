resource "kubernetes_namespace" "monitoring" {
  depends_on = [time_sleep.eks_access_ready]

  metadata {
    name = local.monitoring_namespace
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false
  timeout          = 600

  values = [
    yamlencode({
      grafana = {
        enabled = true
        additionalDataSources = [
          {
            name      = "Loki"
            type      = "loki"
            uid       = "loki"
            access    = "proxy"
            url       = "http://loki-gateway.monitoring.svc.cluster.local"
            isDefault = false
          }
        ]
        ingress = {
          enabled = false
        }
        sidecar = {
          dashboards = {
            enabled          = true
            label            = "grafana_dashboard"
            labelValue       = "1"
            searchNamespace  = kubernetes_namespace.monitoring.metadata[0].name
            folderAnnotation = "grafana_folder"
          }
        }
        extraSecretMounts = [
          {
            name       = "grafana-tls"
            secretName = "grafana-tls"
            mountPath  = "/etc/grafana/certs"
            readOnly   = true
          }
        ]
        readinessProbe = {
          httpGet = {
            path   = "/api/health"
            port   = "grafana"
            scheme = "HTTPS"
          }
        }
        livenessProbe = {
          failureThreshold = 10
          httpGet = {
            path   = "/api/health"
            port   = "grafana"
            scheme = "HTTPS"
          }
          initialDelaySeconds = 60
          timeoutSeconds      = 30
        }
        "grafana.ini" = {
          server = {
            protocol  = "https"
            domain    = var.grafana_hostname
            root_url  = "https://${var.grafana_hostname}"
            cert_file = "/etc/grafana/certs/tls.crt"
            cert_key  = "/etc/grafana/certs/tls.key"
          }
        }
      }
      prometheus = {
        prometheusSpec = {
          retention                               = "10d"
          serviceMonitorSelectorNilUsesHelmValues = false
          serviceMonitorSelector                  = {}
          serviceMonitorNamespaceSelector         = {}
          podMonitorSelectorNilUsesHelmValues     = false
          podMonitorSelector                      = {}
          podMonitorNamespaceSelector             = {}
        }
      }
      alertmanager = {
        enabled = true
      }
    })
  ]

  depends_on = [
    helm_release.cert_manager,
    kubectl_manifest.grafana_certificate
  ]
}

resource "kubernetes_config_map_v1" "vault_grafana_dashboards" {
  metadata {
    name      = "vault-grafana-dashboards"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
    annotations = {
      grafana_folder = "Vault"
    }
  }

  data = {
    "vault-telemetry-dashboard.json"  = file("${path.module}/grafana-dashboard/vault-telemetry-dashboard.json")
    "vault-audit-loki-dashboard.json" = file("${path.module}/grafana-dashboard/vault-audit-loki-dashboard.json")
  }
}
