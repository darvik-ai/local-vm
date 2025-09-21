# ──────────────────────────────────────────────────────────────────────────────
# Builder Stage: Compile guacd with VNC on a slim base
# ──────────────────────────────────────────────────────────────────────────────
FROM debian:12-slim AS builder

ARG GUAC_VERSION=1.5.5
ARG DEBIAN_FRONTEND=noninteractive

# Install build dependencies for Guacamole server
# Using Debian packages; libjpeg62-turbo-dev is the equivalent of libjpeg-turbo8-dev
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libcairo2-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libossp-uuid-dev \
    libpango1.0-dev \
    libavcodec-dev \
    libavformat-dev \
    libswscale-dev \
    libwebp-dev \
    libssl-dev \
    libvncserver-dev \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone, configure, and build Guacamole server
RUN git clone --depth 1 --branch ${GUAC_VERSION} https://github.com/apache/guacamole-server.git /tmp/guacamole-server \
    && cd /tmp/guacamole-server \
    && autoreconf -fi \
    && ./configure --enable-vnc --disable-rdp \
    && make -j"$(nproc)" \
    && make install \
    && ldconfig \
    && rm -rf /tmp/guacamole-server

# ──────────────────────────────────────────────────────────────────────────────
# Final Stage: Optimized runtime image
# ──────────────────────────────────────────────────────────────────────────────
FROM debian:12-slim

ARG GUAC_VERSION=1.5.5
ARG DEBIAN_FRONTEND=noninteractive

LABEL maintainer="you@example.com"
LABEL description="Lightweight Guacamole VNC with minimal XFCE desktop & TightVNC"

# 1) Copy guacd and its libraries from the builder stage
COPY --from=builder /usr/local/sbin/guacd /usr/local/sbin/guacd
COPY --from=builder /usr/local/lib/libguac* /usr/local/lib/
COPY --from=builder /usr/local/include/guacamole /usr/local/include/guacamole
RUN ldconfig

# 2) Consolidated RUN command for installation, setup, and cleanup
# This single layer installs dependencies, downloads assets, and cleans up after itself.
RUN set -x \
    # Install build-time dependencies and runtime dependencies
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        wget \
        ca-certificates \
        # Minimal XFCE Core
        xfce4-session \
        xfce4-panel \
        xfwm4 \
        xfdesktop4 \
        thunar \
        xfce4-terminal \
        # VNC Server and Fonts
        tightvncserver \
        xfonts-base \
        # Runtime libraries - CORRECTED FFMPEG VERSIONS FOR DEBIAN 12
        libvncserver1 \
        libcairo2 \
        libjpeg62-turbo \
        libpng16-16 \
        libossp-uuid16 \
        libpango-1.0-0 \
        libavcodec59 \
        libavformat59 \
        libswscale6 \
        libwebp7 \
        libssl3 \
        # Java 17 for Tomcat
        openjdk-17-jre-headless \
        # Utilities
        sudo \
        netcat-openbsd \
        locales \
    # Generate locale
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen \
    # Create non-root user
    && useradd -m -u 10001 -s /bin/bash guacuser \
    && echo "guacuser:o4Zt2TtRh8GmD3gxv" | chpasswd \
    && usermod -aG sudo,video guacuser \
    && echo "guacuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && mkdir -p /home/guacuser/Desktop \
    # Install Tomcat
    && mkdir /opt/tomcat \
    && wget -q https://archive.apache.org/dist/tomcat/tomcat-9/v9.0.89/bin/apache-tomcat-9.0.89.tar.gz -O /tmp/tomcat.tar.gz \
    && tar xzf /tmp/tomcat.tar.gz -C /opt/tomcat --strip-components=1 \
    # Install Guacamole client
    && mkdir -p /config \
    && wget -q -O /config/guacamole.war https://downloads.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war \
    && ln -s /config/guacamole.war /opt/tomcat/webapps/ \
    # Clean up build-time dependencies and caches to reduce image size
    && apt-get purge -y --auto-remove wget ca-certificates \
    && rm -rf /tmp/* /var/lib/apt/lists/*

# 3) Configure /etc/guacamole
COPY guacamole.properties user-mapping.xml logback.xml /etc/guacamole/
RUN chmod -R 644 /etc/guacamole/* && chmod 755 /etc/guacamole

# 4) Set environment variables
ENV LANG=en_US.UTF-8
ENV GUACAMOLE_HOME=/etc/guacamole
ENV USER=guacuser

# 5) Configure VNC and set final ownership and permissions
COPY xstartup /home/guacuser/.vnc/xstartup
RUN mkdir -p /home/guacuser/.vnc \
    && echo "o4Zt2TtRh8GmD3gxv" | vncpasswd -f > /home/guacuser/.vnc/passwd \
    && chmod 600 /home/guacuser/.vnc/passwd \
    && chmod 755 /home/guacuser/.vnc/xstartup \
    && chown -R guacuser:guacuser /opt/tomcat /config /home/guacuser

# 6) Expose Tomcat's port
EXPOSE 8080

# 7) Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 8) Switch to non-root user for runtime security
USER 10001
ENTRYPOINT ["/entrypoint.sh"]

