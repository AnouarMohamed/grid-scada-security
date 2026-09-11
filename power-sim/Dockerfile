FROM python:3.14-slim-bookworm@sha256:9ab8d9c8514b44f90cf0029dd42fdd7e9e211e639c8b995304cc04568dee900f

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/app/src
ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_ROOT_USER_ACTION=ignore

WORKDIR /app

RUN groupadd --system gridguard \
    && useradd --system --gid gridguard --home-dir /nonexistent --shell /usr/sbin/nologin gridguard

COPY power-sim/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir --requirement requirements.txt

COPY power-sim/src/ ./src/
COPY infra/contracts/register-maps/ieee13-demo.json /etc/gridguard/register-map.json

USER gridguard

ENTRYPOINT ["python", "-m", "power_sim"]
