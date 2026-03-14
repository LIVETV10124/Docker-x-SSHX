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
      wget \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Set root password
RUN echo "root:root" | chpasswd

# Pre-install sshx
RUN curl -sSf https://sshx.io/get | sh

WORKDIR /
COPY start.sh .
COPY server.py .
RUN chmod +x start.sh

EXPOSE 10000

CMD ["./start.sh"]












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

WORKDIR /
COPY start.sh .
RUN chmod +x start.sh

EXPOSE 4200

CMD ["./start.sh"]
