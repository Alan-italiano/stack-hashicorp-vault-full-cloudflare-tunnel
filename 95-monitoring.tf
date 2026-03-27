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
  version          = "67.9.0"
  namespace        = kubernetes_namespace.monitoring.metadata[0].name
  create_namespace = false
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 1200

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
        "grafana.ini" = {
          server = {
            protocol  = "http"
            domain    = var.grafana_hostname
            root_url  = "https://${var.grafana_hostname}"
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
    helm_release.cert_manager
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
