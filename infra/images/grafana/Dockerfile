FROM grafana/grafana:13.2.4@sha256:dbbc38ea21103cefb50396340cd88afec779c7e070b0a7bf5a75b4ce46651d3f

USER root

RUN apk upgrade --no-cache

COPY infra/local/grafana/provisioning/ /etc/grafana/provisioning/
COPY infra/local/grafana/dashboards/ /etc/grafana/dashboards/gridguard/

USER 472
