# Universal Dockerfile for a Lightweight Web-Based Desktop
#
# Description:
# This Dockerfile creates a self-contained, lightweight desktop environment
# running on Debian. It includes the Openbox window manager, a file manager,
# a terminal, and the Firefox web browser. The entire desktop is accessible
# through a standard web browser using noVNC.
#
# Author: Gemini
# Version: 2.2 (Added dynamic PORT support for PaaS deployment)
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
    # Install all necessary packages, including gettext-base for envsubst
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
    gettext-base && \
    # Clean up apt caches to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* && \
    # Create VNC directory for the root user
    mkdir -p /root/.vnc && \
    # Create the VNC startup script
    echo '#!/bin/sh' > /root/.vnc/xstartup && \
    echo 'unset SESSION_MANAGER' >> /root/.vnc/xstartup && \
    echo 'unset DBUS_SESSION_BUS_ADDRESS' >> /root/.vnc/xstartup && \
    echo 'openbox-session &' >> /root/.vnc/xstartup && \
    echo 'pcmanfm --desktop &' >> /root/.vnc/xstartup && \
    echo 'xterm' >> /root/.vnc/xstartup && \
    # Make the startup script executable
    chmod 755 /root/.vnc/xstartup && \
    # Force create a symlink to the correct VNC client page
    ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html && \
    # Create the Supervisor configuration file template
    echo '[supervisord]' > /etc/supervisor/supervisord.conf.template && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf.template && \
    echo '' >> /etc/supervisor/supervisord.conf.template && \
    echo '[program:vncserver]' >> /etc/supervisor/supervisord.conf.template && \
    echo "command=vncserver :1 -fg -geometry \${VNC_RESOLUTION} -depth \${VNC_DEPTH} -SecurityTypes None" >> /etc/supervisor/supervisord.conf.template && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf.template && \
    echo 'autorestart=true' >> /etc/supervisor/supervisord.conf.template && \
    echo '' >> /etc/supervisor/supervisord.conf.template && \
    echo '[program:novnc]' >> /etc/supervisor/supervisord.conf.template && \
    echo 'command=/usr/bin/websockify --web /usr/share/novnc/ 0.0.0.0:\${PORT:-6080} localhost:5901' >> /etc/supervisor/supervisord.conf.template && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf.template && \
    echo 'autorestart=true' >> /etc/supervisor/supervisord.conf.template

# Create and add the entrypoint script to handle dynamic port assignment
COPY <<'EOF' /entrypoint.sh
#!/bin/sh
set -e
# Substitute environment variables in the supervisor template to create the final config
envsubst < /etc/supervisor/supervisord.conf.template > /etc/supervisor/conf.d/supervisord.conf
# Start supervisor
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
EOF
RUN chmod +x /entrypoint.sh

# Expose the default port (Render will override this)
EXPOSE 6080

# Set the working directory for the container
WORKDIR /root

# Use the entrypoint script to start the services
CMD ["/entrypoint.sh"]

