FROM grafana/grafana:13.3.0@sha256:488984b716c0862639f91a698adbe2862677a5a07bad42da5f03f3030883b205

USER root

RUN apk upgrade --no-cache

COPY infra/local/grafana/provisioning/ /etc/grafana/provisioning/
COPY infra/local/grafana/dashboards/ /etc/grafana/dashboards/gridguard/

USER 472
