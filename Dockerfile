FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2
ENV DEBIAN_FRONTEND=noninteractive
COPY build/artifacts/ /opt/artifacts/
RUN cd /opt/artifacts && sha256sum --check SHA256SUMS && apt-get --yes --no-install-recommends install /opt/artifacts/debs/*.deb
ENV HOME=/tmp USER=rpw PYTHONDONTWRITEBYTECODE=1 RPW_ARTIFACTS=/opt/artifacts
WORKDIR /work
USER 1000:1000
CMD ["/bin/sh", "scripts/test-offline.sh"]
