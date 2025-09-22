# ──────────────────────────────────────────────────────────────────────────────
# Stage 1: Builder
#
# This stage compiles the guacd daemon with only the VNC plugin enabled.
# It uses Debian 12 (Bookworm) as the base.
# ──────────────────────────────────────────────────────────────────────────────
FROM debian:12-slim AS builder

# Set versions for Guacamole and Tomcat
ARG GUAC_VERSION=1.5.5
ARG TOMCAT_VERSION=9.0.89
ENV DEBIAN_FRONTEND=noninteractive

# Install build dependencies for Guacamole server
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

# Download and compile Guacamole server
RUN git clone --depth 1 --branch ${GUAC_VERSION} https://github.com/apache/guacamole-server.git /tmp/guacamole-server \
    && cd /tmp/guacamole-server \
    && autoreconf -fi \
    && ./configure --disable-rdp \
    && make \
    && make install \
    && ldconfig \
    && rm -rf /tmp/guacamole-server

# ──────────────────────────────────────────────────────────────────────────────
# Stage 2: Final Image
#
# This stage uses a more robust installation method to ensure stability.
# It prioritizes a working build over minimal image size.
# ──────────────────────────────────────────────────────────────────────────────
FROM debian:12-slim

ARG GUAC_VERSION=1.5.5
ARG TOMCAT_VERSION=9.0.89
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8

# Copy compiled guacd and libraries from the builder stage
COPY --from=builder /usr/local/sbin/guacd /usr/local/sbin/guacd
COPY --from=builder /usr/local/lib/libguac* /usr/local/lib/
COPY --from=builder /usr/local/include/guacamole /usr/local/include/guacamole
RUN ldconfig

# == INSTALLATION STAGE ==
# Install all dependencies in a single layer for stability.
# Using standard metapackages is more reliable than cherry-picking.
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Full XFCE Desktop & Goodies for stability
    xfce4 \
    xfce4-goodies \
    # Modern VNC Server (this package includes all necessary tools)
    tigervnc-standalone-server \
    # Runtime libraries for guacd
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
    # Java 17 JDK for Tomcat
    openjdk-17-jdk-headless \
    # Utilities needed for setup
    sudo \
    netcat-openbsd \
    locales \
    wget \
    && rm -rf /var/lib/apt/lists/*

# == CONFIGURATION STAGE ==
# Set up locale, user, VNC, and install Tomcat/Guacamole in one layer.
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen \
    && useradd -m -u 10001 -s /bin/bash guacuser \
    # Using the SAME 8-character password for both OS and VNC to avoid confusion
    && echo "guacuser:o4Zt2Tt" | chpasswd \
    && usermod -aG sudo,video guacuser \
    && echo "guacuser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && mkdir -p /home/guacuser/Desktop \
    # VNC Setup (run as root, for the user)
    && mkdir -p /home/guacuser/.vnc \
    && echo "o4Zt2Tt" | vncpasswd -f > /home/guacuser/.vnc/passwd \
    && chmod 600 /home/guacuser/.vnc/passwd \
    # Install Tomcat
    && mkdir /opt/tomcat \
    && wget -q https://archive.apache.org/dist/tomcat/tomcat-9/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz -O /tmp/tomcat.tar.gz \
    && tar xzf /tmp/tomcat.tar.gz -C /opt/tomcat --strip-components=1 \
    # Install Guacamole client
    && mkdir -p /config \
    && wget -q -O /config/guacamole.war https://downloads.apache.org/guacamole/${GUAC_VERSION}/binary/guacamole-${GUAC_VERSION}.war \
    && ln -s /config/guacamole.war /opt/tomcat/webapps/ \
    # Clean up temp files
    && rm -rf /tmp/*

# Configure Guacamole
COPY guacamole.properties user-mapping.xml logback.xml /etc/guacamole/
RUN chown -R root:root /etc/guacamole \
    && find /etc/guacamole -type d -exec chmod 755 {} \; \
    && find /etc/guacamole -type f -exec chmod 644 {} \;

# Copy VNC startup script
COPY xstartup /home/guacuser/.vnc/xstartup
RUN chmod 755 /home/guacuser/.vnc/xstartup

# Final ownership changes
RUN chown -R guacuser:guacuser /opt/tomcat /config /home/guacuser

# Expose only Tomcat's port
EXPOSE 8080

# Copy and prepare the entrypoint script as root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Switch to non-root user and set final entrypoint
USER guacuser
ENTRYPOINT ["/entrypoint.sh"]

