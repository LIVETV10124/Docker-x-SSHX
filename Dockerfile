FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install essentials
RUN apt-get update && apt-get install -y \
    curl \
    bash \
    ca-certificates \
    git \
    wget \
    htop \
    vim \
    net-tools \
    procps \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY start.sh .
RUN chmod +x start.sh

# Render requires a listening port (even if unused)
EXPOSE 10000

CMD ["./start.sh"]
