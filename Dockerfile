# Universal Dockerfile for a Lightweight Web-Based Desktop
#
# Description:
# This Dockerfile creates a self-contained, lightweight desktop environment
# running on Debian. It includes the Openbox window manager, a file manager,
# a terminal, and the Firefox web browser. The entire desktop is accessible
# through a standard web browser using noVNC.
#
# Author: Gemini
#
# --- VERY IMPORTANT SECURITY WARNING ---
# This configuration is designed for ease of use in a trusted, local environment ONLY.
# It has NO PASSWORD and NO VNC AUTHENTICATION.
# DO NOT expose the port from this container to the public internet.
# Anyone who can access the port will have full control over the container.
#
FROM debian:bullseye-slim

# Set environment variables for non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive \
    DISPLAY=:1 \
    VNC_RESOLUTION=1366x768 \
    VNC_DEPTH=24

# Set up the container
RUN apt-get update && \
    # Install all necessary packages
    apt-get install -y --no-install-recommends \
    supervisor \
    openbox \
    pcmanfm \
    xterm \
    tigervnc-standalone-server \
    novnc \
    websockify \
    firefox-esr \
    curl \
    sudo && \
    # Clean up apt caches to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Create a non-root user to run applications
    useradd -m -s /bin/bash -G sudo dockeruser && \
    echo "dockeruser:dockeruser" | chpasswd && \
    echo "dockeruser ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    # Create VNC and application directories for the new user
    mkdir -p /home/dockeruser/.vnc && \
    # Create the VNC startup script
    echo '#!/bin/sh' > /home/dockeruser/.vnc/xstartup && \
    echo 'unset SESSION_MANAGER' >> /home/dockeruser/.vnc/xstartup && \
    echo 'unset DBUS_SESSION_BUS_ADDRESS' >> /home/dockeruser/.vnc/xstartup && \
    echo 'openbox-session &' >> /home/dockeruser/.vnc/xstartup && \
    echo 'pcmanfm --desktop &' >> /home/dockeruser/.vnc/xstartup && \
    echo 'xterm' >> /home/dockeruser/.vnc/xstartup && \
    # Make the startup script executable
    chmod 755 /home/dockeruser/.vnc/xstartup && \
    # Set correct ownership for the user's home directory
    chown -R dockeruser:dockeruser /home/dockeruser && \
    # Create the Supervisor configuration file to manage VNC and noVNC services
    echo '[supervisord]' > /etc/supervisor/conf.d/supervisord.conf && \
    echo 'nodaemon=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '[program:vncserver]' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo "command=vncserver :1 -fg -geometry ${VNC_RESOLUTION} -depth ${VNC_DEPTH} -SecurityTypes None" >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'user=dockeruser' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo '[program:novnc]' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'command=/usr/bin/websockify --web /usr/share/novnc/ 6080 localhost:5901' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'user=dockeruser' >> /etc/supervisor/conf.d/supervisord.conf && \
    echo 'autorestart=true' >> /etc/supervisor/conf.d/supervisord.conf

# Expose the noVNC web port
EXPOSE 6080

# Set the working directory for the container
WORKDIR /home/dockeruser

# Start Supervisor to run VNC and noVNC services
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
