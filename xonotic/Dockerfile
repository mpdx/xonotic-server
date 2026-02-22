FROM debian:stable-slim

RUN apt-get update && apt-get install -y \
    wget \
    unzip \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt
RUN wget https://dl.xonotic.org/xonotic-0.8.6.zip && \
    unzip xonotic-0.8.6.zip && \
    mv Xonotic xonotic && \
    rm xonotic-0.8.6.zip

WORKDIR /opt/xonotic

EXPOSE 26000/udp

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
