FROM python:3.14-slim-trixie@sha256:cad9a2c871761c413caa6fdd6441c783451e740a48aaeba60ae62a8b53525ef6

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app/src
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_ROOT_USER_ACTION=ignore

WORKDIR /app

RUN apt-get update \
    && apt-get upgrade --yes \
    && rm -rf /var/lib/apt/lists/*

RUN groupadd --system gridguard \
    && useradd --system --gid gridguard --home-dir /nonexistent --shell /usr/sbin/nologin gridguard

COPY power-sim/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --requirement requirements.txt

COPY power-sim/src/ ./src/
COPY infra/contracts/register-maps/ieee13-demo.json /etc/gridguard/register-map.json

USER gridguard

ENTRYPOINT ["python", "-m", "power_sim"]
