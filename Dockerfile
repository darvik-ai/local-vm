# Universal Dockerfile for a Lightweight Web-Based Desktop
#
# Description:
# This Dockerfile creates a self-contained, stable desktop environment
# running on Debian. It now includes the XFCE desktop environment, a terminal,
# and the Firefox web browser. The entire desktop is accessible
# through a standard web browser using noVNC.
#
# Author: Gemini
# Version: 3.1 (Added xorg and dbus-x11 for X server stability)
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
    # Install XFCE desktop environment and other necessary packages
    apt-get install -y --no-install-recommends \
    supervisor \
    xfce4 \
    xfce4-goodies \
    xorg \
    dbus-x11 \
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
    # Create the VNC startup script to launch the XFCE session
    echo '#!/bin/sh' > /root/.vnc/xstartup && \
    echo 'unset SESSION_MANAGER' >> /root/.vnc/xstartup && \
    echo 'unset DBUS_SESSION_BUS_ADDRESS' >> /root/.vnc/xstartup && \
    echo 'startxfce4 &' >> /root/.vnc/xstartup && \
    # Make the startup script executable
    chmod 755 /root/.vnc/xstartup && \
    # Force create a symlink to the correct VNC client page
    ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html && \
    # Create the Supervisor configuration file template
    echo '[supervisord]' > /etc/supervisor/supervisord.conf.template && \
    echo 'nodaemon=true' >> /etc/supervisor/supervisord.conf.template && \
    echo '' >> /etc/supervisor/supervisord.conf.template && \
    echo '[program:vncserver]' >> /etc/supervisor/supervisord.conf.template && \
    echo 'command=vncserver :1 -fg -geometry ${VNC_RESOLUTION} -depth ${VNC_DEPTH} -SecurityTypes None' >> /etc/supervisor/supervisord.conf.template && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf.template && \
    echo 'autorestart=true' >> /etc/supervisor/supervisord.conf.template && \
    echo '' >> /etc/supervisor/supervisord.conf.template && \
    echo '[program:novnc]' >> /etc/supervisor/supervisord.conf.template && \
    echo 'command=/usr/bin/websockify --web /usr/share/novnc/ 0.0.0.0:${PORT} localhost:5901' >> /etc/supervisor/supervisord.conf.template && \
    echo 'user=root' >> /etc/supervisor/supervisord.conf.template && \
    echo 'autorestart=true' >> /etc/supervisor/supervisord.conf.template

# Create and add the entrypoint script to handle dynamic port assignment and cleanup
COPY <<'EOF' /entrypoint.sh
#!/bin/sh
set -e

# Export all environment variables to be available for substitution
export PORT=${PORT:-6080}
export VNC_RESOLUTION=${VNC_RESOLUTION:-1366x768}
export VNC_DEPTH=${VNC_DEPTH:-24}

# Clean up VNC lock files for a clean start
rm -f /tmp/.X*-lock /tmp/.X11-unix/X*
echo "Starting container. Services will listen on PORT: ${PORT}"
echo "Desktop resolution set to: ${VNC_RESOLUTION}"

# Define the variables to be substituted to avoid issues
VARS_TO_SUBSTITUTE='${PORT} ${VNC_RESOLUTION} ${VNC_DEPTH}'

# Substitute all relevant environment variables into the template
envsubst "$VARS_TO_SUBSTITUTE" < /etc/supervisor/supervisord.conf.template > /etc/supervisor/conf.d/supervisord.conf

echo "--- Generated supervisord.conf ---"
cat /etc/supervisor/conf.d/supervisord.conf
echo "------------------------------------"

# Start supervisor
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
EOF
RUN chmod +x /entrypoint.sh

# Expose the default port (platform will override this)
EXPOSE 6080

# Set the working directory for the container
WORKDIR /root

# Use the entrypoint script to start the services
CMD ["/entrypoint.sh"]

