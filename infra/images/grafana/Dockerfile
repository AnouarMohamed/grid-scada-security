FROM grafana/grafana:12.4.10@sha256:c132a683b2430fff9115a29b2a79c8ab97540cdcc90846e3c81878c778ca3596

COPY infra/local/grafana/provisioning/ /etc/grafana/provisioning/
COPY infra/local/grafana/dashboards/ /etc/grafana/dashboards/gridguard/

USER 472
