FROM python:3.11-slim

ARG PIXLET_VERSION=0.34.0
ARG TARGETARCH=amd64

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    curl -LO "https://github.com/tidbyt/pixlet/releases/download/v${PIXLET_VERSION}/pixlet_${PIXLET_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    tar -xzf "pixlet_${PIXLET_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    mv pixlet /usr/local/bin/pixlet && \
    chmod +x /usr/local/bin/pixlet && \
    rm "pixlet_${PIXLET_VERSION}_linux_${TARGETARCH}.tar.gz" && \
    apt-get remove -y curl && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY powerwall_push.py .
COPY powerwall_tidbyt.star .

CMD ["python", "powerwall_push.py"]
