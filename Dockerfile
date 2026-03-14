FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
      shellinabox \
      curl \
      ca-certificates \
      bash \
      htop \
      vim \
      net-tools \
      procps \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Set root password
RUN echo "root:root" | chpasswd

# Pre-install sshx at build time
RUN curl -sSf https://sshx.io/get | sh

WORKDIR /app
COPY start.sh .
RUN chmod +x start.sh

EXPOSE 4200

CMD ["./start.sh"]
