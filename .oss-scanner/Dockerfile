# Anthropic OSS Scanner environment for the public PostgreSQL reference runtime.
# Never point tests at a deployed database. Use only disposable local clusters.
FROM postgres:16-bookworm

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       ca-certificates git bash python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*

ENV PATH="/usr/lib/postgresql/16/bin:${PATH}"
WORKDIR /src
COPY . /src

# Keep PostgreSQL binaries and all public SQL/tests available for offline audits.
RUN psql --version \
    && python3 -m compileall -q scripts \
    && test -s sql/01_core.sql \
    && test -s sql/11_perimeter_evaluability.sql \
    && test -d tests

# The scanner may initialize a disposable cluster under /tmp as user postgres.
# A database is intentionally not started or initialized during image build.
