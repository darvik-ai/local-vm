# Hardened web-based XFCE desktop with TLS websockify and VNC auth
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DEFAULT_VNC_PASSWORD="ChangeMe-Strong!"

# Core runtime variables
ENV DISPLAY=":1" \
    PORT="6080" \
    VNC_RESOLUTION="1366x768" \
    VNC_DEPTH="24" \
    VNC_USER="vncuser" \
    VNC_UID="1000" \
    VNC_GID="1000"

# Install required packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      supervisor \
      xfce4 \
      xfce4-goodies \
      xorg \
      dbus-x11 \
      tigervnc-standalone-server \
      tigervnc-common \
      novnc \
      websockify \
      firefox \
      curl \
      gettext-base \
      openssl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Add non-root user and create needed directories
RUN useradd -m -u ${VNC_UID} -s /bin/bash ${VNC_USER} && \
    mkdir -p /home/${VNC_USER}/.vnc /home/${VNC_USER}/.ssl /home/${VNC_USER}/supervisor && \
    chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER} && \
    ln -sf /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html

# Supervisor config template
RUN cat > /home/vncuser/supervisor/supervisord.conf.template << 'EOF'
[supervisord]
nodaemon=true

[program:xserver]
command=/usr/bin/Xvnc :1 -rfbport 5901 -geometry ${VNC_RESOLUTION} -depth ${VNC_DEPTH} -PasswordFile /home/vncuser/.vnc/passwd -SecurityTypes VncAuth -AlwaysShared -BlacklistThreshold=0 -MaxConnectionTime=0 -MaxIdleTime=0 -MaxDisconnectionTime=0 -AcceptCutText=0 -SendCutText=0
user=vncuser
autorestart=true
priority=1
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr

[program:xfce]
command=/bin/sh -c "sleep 5 && dbus-launch startxfce4"
environment=DISPLAY=":1"
user=vncuser
autorestart=true
priority=2
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr

[program:novnc]
command=/usr/bin/websockify --verbose --web /usr/share/novnc/ --ssl-only --cert /home/vncuser/.ssl/novnc.crt --key /home/vncuser/.ssl/novnc.key 0.0.0.0:${PORT} 127.0.0.1:5901
user=vncuser
autorestart=true
priority=3
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
EOF

# Entrypoint script
RUN cat > /home/vncuser/entrypoint.sh << 'EOF'
#!/bin/bash
set -e
umask 077

PORT="${PORT:-6080}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1366x768}"
VNC_DEPTH="${VNC_DEPTH:-24}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-ChangeMe-Strong!}"

mkdir -p /home/vncuser/.vnc /home/vncuser/.ssl /home/vncuser/supervisor
chown vncuser:vncuser /home/vncuser/.vnc /home/vncuser/.ssl /home/vncuser/supervisor

# Create VNC password file if it doesn't exist
if [ ! -f /home/vncuser/.vnc/passwd ]; then
  PASS="${VNC_PASSWORD:-$DEFAULT_VNC_PASSWORD}"
  echo "Creating VNC password file..."
  echo "$PASS" | /usr/bin/vncpasswd -f > /home/vncuser/.vnc/passwd
  chown vncuser:vncuser /home/vncuser/.vnc/passwd
  chmod 600 /home/vncuser/.vnc/passwd
  echo "VNC password file created"
fi

# Self-signed SSL cert creation
if [ ! -f /home/vncuser/.ssl/novnc.crt ] || [ ! -f /home/vncuser/.ssl/novnc.key ]; then
  echo "Generating self-signed TLS cert for noVNC..."
  openssl req -new -x509 -days 365 -nodes -subj "/CN=localhost" \
          -keyout /home/vncuser/.ssl/novnc.key -out /home/vncuser/.ssl/novnc.crt
  chown vncuser:vncuser /home/vncuser/.ssl/*
  chmod 600 /home/vncuser/.ssl/novnc.key
fi

# Render supervisord config
export PORT VNC_RESOLUTION VNC_DEPTH
envsubst < /home/vncuser/supervisor/supervisord.conf.template > /home/vncuser/supervisor/supervisord.conf

echo "--- Starting services ---"
echo "Listening on PORT=${PORT}, Resolution=${VNC_RESOLUTION}@${VNC_DEPTH}"
echo "Use your VNC password to connect."

exec /usr/bin/supervisord -c /home/vncuser/supervisor/supervisord.conf
EOF

RUN chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER} && chmod +x /home/${VNC_USER}/entrypoint.sh

USER ${VNC_USER}
WORKDIR /home/${VNC_USER}

EXPOSE 6080
CMD ["/home/vncuser/entrypoint.sh"]
