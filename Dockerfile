# ──────────────────────────────────────────────────────────────────────────────
# Builder Stage: Compile the latest stable guacd with RDP plugin only
# ──────────────────────────────────────────────────────────────────────────────
FROM ubuntu:24.04 AS builder

# Set Guacamole version as a build argument
ARG GUAC_VERSION=1.5.5
ARG DEBIAN_FRONTEND=noninteractive

# Install build dependencies for Guacamole server
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libcairo2-dev \
    libjpeg-turbo8-dev \
    libpng-dev \
    libossp-uuid-dev \
    libpango1.0-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libwebp-dev \
    libssl-dev \
    libfreerdp-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone, configure, and build Guacamole server
RUN git clone --depth 1 --branch ${GUAC_VERSION} https://github.com/apache/guacamole-server.git /tmp/guacamole-server \
    && cd /tmp/guacamole-server \
    && autoreconf -fi \
    && ./configure --with-systemd-dir=/etc/systemd/system --enable-rdp --disable-ssh --disable-vnc \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig \
    && rm -rf /tmp/guacamole-server

# ──────────────────────────────────────────────────────────────────────────────
# Final Stage: Runtime image (guacd + Tomcat + guacamole.war + XFCE & xrdp)
# ──────────────────────────────────────────────────────────────────────────────
FROM ubuntu:24.04

ARG GUAC_VERSION=1.5.5
ARG DEBIAN_FRONTEND=noninteractive

LABEL maintainer="you@example.com"
LABEL description="Guacamole RDP-only with XFCE desktop & xrdp, exposing only 8080"

ENV LANG=en_US.UTF-8

# 1) Copy guacd and its libraries from the builder stage
COPY --from=builder /usr/local/sbin/guacd /usr/local/sbin/guacd
COPY --from=builder /usr/local/lib/libguac* /usr/local/lib/
COPY --from=builder /usr/local/include/guacamole /usr/local/include/guacamole
RUN ldconfig

# 2) Install runtime packages (XFCE desktop, xrdp, Tomcat prerequisites, etc.)
RUN apt-get update && apt-get install -y --no-install-recommends \
    # XFCE desktop environment
    xfce4 \
    xfce4-goodies \
    xorgxrdp \
    # xrdp RDP server
    xrdp \
    # Runtime libraries for guacd
    freerdp2-x11 \
    libcairo2 \
    libjpeg-turbo8 \
    libpng16-16 \
    libossp-uuid16 \
    libpango-1.0-0 \
    libavcodec60 \
    libavformat60 \
    libswscale7 \
    libwebp7 \
    libssl3 \
    # Java 17 runtime for Tomcat
    openjdk-17-jre-headless \
    # Utilities
    curl \
    wget \
    sudo \
    netcat-openbsd \
    locales \
    vim \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/* \
    && locale-gen en_US.UTF-8

# 3) Configure /etc/guacamole
RUN mkdir -p /etc/guacamole
COPY guacamole.properties user-mapping.xml logback.xml /etc/guacamole/
RUN chown -R root:root /etc/guacamole \
    && find /etc/guacamole -type d -exec chmod 755 {} \; \
    && find /etc/guacamole -type f -exec chmod 644 {} \;

# 4) Configure xrdp to start an XFCE session
COPY startwm.sh /etc/xrdp/startwm.sh
RUN chmod 755 /etc/xrdp/startwm.sh \
    && sed -i 's/^;*ListenAddress=.*/ListenAddress=127.0.0.1/' /etc/xrdp/xrdp.ini \
    && sed -i 's/^;*autorun=.*//' /etc/xrdp/sesman.ini \
    && echo "autorun=xrdp-sesman" >> /etc/xrdp/sesman.ini

# 5) Install Apache Tomcat (barebones)
RUN mkdir /opt/tomcat \
    && wget -q https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.89/bin/apache-tomcat-9.0.89.tar.gz -O /tmp/tomcat.tar.gz \
    && tar xzf /tmp/tomcat.tar.gz -C /opt/tomcat --strip-components=1 \
    && rm /tmp/tomcat.tar.gz

# 6) Download Guacamole client .war into Tomcat
RUN mkdir -p /config \
    && wget -q -O /config/guacamole.war \
       https://downloads.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war \
    && ln -s /config/guacamole.war /opt/tomcat/webapps/

# 7) Set Guacamole home directory
ENV GUACAMOLE_HOME=/etc/guacamole

# 8) Create a non-root user and grant passwordless sudo
RUN useradd -m -u 10001 -s /bin/bash guacuser \
    && echo "guacuser:o4Zt2TtRh8GmD3gxv" | chpasswd \
    && usermod -aG sudo,video guacuser \
    && echo "guacuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && mkdir -p /home/guacuser/Desktop \
    && chown -R guacuser:guacuser /opt/tomcat /config /home/guacuser

# 9) Expose Tomcat's port. guacd (4822) & xrdp (3389) remain internal.
EXPOSE 8080

# 10) Copy and set up the entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 11) Switch to non-root user and define the entrypoint
USER 10001
ENTRYPOINT ["/entrypoint.sh"]
