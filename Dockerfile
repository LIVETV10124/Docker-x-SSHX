FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
      curl \
      ca-certificates \
      bash \
      python3 \
      htop \
      vim \
      net-tools \
      procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Verify python3 exists
RUN which python3 && python3 --version


# Set root password
RUN echo "root:root" | chpasswd

# Pre-install sshx
RUN curl -sSf https://sshx.io/get | sh

WORKDIR /app
COPY start.sh .
RUN chmod +x start.sh

EXPOSE 10000

CMD ["./start.sh"]
