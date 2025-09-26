# Web-based XFCE desktop with VNC auth, noVNC, TLS websockify for Render/Hosted platforms
# Includes hardened VNC auth, non-root user, and automatic self-signed SSL for websockify.
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DEFAULT_VNC_PASSWORD="ChangeMe-Strong!"

# Core runtime settings (override at run time as needed)
ENV DISPLAY=":1" \
    PORT="6080" \
    VNC_RESOLUTION="1366x768" \
    VNC_DEPTH="24" \
    VNC_USER="vncuser" \
    VNC_UID="1000" \
    VNC_GID="1000"

# Install packages
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

# Create non-root user and workspace
RUN useradd -m -u ${VNC_UID} -s /bin/bash ${VNC_USER} && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/.vnc && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/.ssl && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/supervisor && \
    ln -sf /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html

# Supervisor template with TLS websockify and VNC blacklist prevention
RUN cat > /home/vncuser/supervisor/supervisord.conf.template << 'TEMPLATE'
[supervisord]
nodaemon=true

[program:xserver]
command=/usr/bin/Xvnc :1 -rfbport 5901 -geometry ${VNC_RESOLUTION} -depth ${VNC_DEPTH} -SecurityTypes VncAuth -PasswordFile /home/vncuser/.vnc/passwd -AlwaysShared -AcceptCutText=0 -SendCutText=0 -MaxConnectionTime=0 -MaxIdleTime=0 -MaxDisconnectionTime=0 -BlacklistThreshold=0
user=vncuser
priority=1
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:xfce]
command=/bin/sh -c "sleep 5 && dbus-launch startxfce4"
environment=DISPLAY=":1"
user=vncuser
priority=2
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:novnc]
command=/usr/bin/websockify --verbose --web /usr/share/novnc/ --ssl-only --cert /home/vncuser/.ssl/novnc.crt --key /home/vncuser/.ssl/novnc.key 0.0.0.0:${PORT} 127.0.0.1:5901
user=vncuser
priority=3
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
TEMPLATE

# Entrypoint with self-signed SSL and VNC hardening
RUN cat > /home/vncuser/entrypoint.sh << 'ENTRYPOINT'
#!/bin/bash
set -e

PORT="${PORT:-6080}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1366x768}"
VNC_DEPTH="${VNC_DEPTH:-24}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-ChangeMe-Strong!}"

install -d -o vncuser -g vncuser /home/vncuser/.vnc /home/vncuser/.ssl /home/vncuser/supervisor

# Create VNC password file if missing
if [ ! -f /home/vncuser/.vnc/passwd ]; then
  PASS="${VNC_PASSWORD:-$DEFAULT_VNC_PASSWORD}"
  echo "Creating VNC password file..."
  echo "$PASS" | /usr/bin/vncpasswd -f > /home/vncuser/.vnc/passwd
  chown vncuser:vncuser /home/vncuser/.vnc/passwd
  chmod 600 /home/vncuser/.vnc/passwd
  echo "VNC password file created successfully"
fi

# Create VNC config to prevent blacklisting
cat > /home/vncuser/.vnc/config << 'VNCCONF'
# Disable blacklisting to prevent connection issues
BlacklistThreshold=0
MaxConnectionTime=0
MaxIdleTime=0
MaxDisconnectionTime=0
AcceptCutText=0
SendCutText=0
VNCCONF

chown vncuser:vncuser /home/vncuser/.vnc/config

# Generate self-signed SSL cert if missing
if [ ! -f /home/vncuser/.ssl/novnc.crt ] || [ ! -f /home/vncuser/.ssl/novnc.key ]; then
  echo "Generating self-signed certificate for websockify..."
  openssl req -new -x509 -days 365 -nodes -subj "/CN=localhost" \
    -keyout /home/vncuser/.ssl/novnc.key -out /home/vncuser/.ssl/novnc.crt
  chown vncuser:vncuser /home/vncuser/.ssl/*
  chmod 600 /home/vncuser/.ssl/novnc.key
fi

# Render supervisor config
export PORT VNC_RESOLUTION VNC_DEPTH
envsubst < /home/vncuser/supervisor/supervisord.conf.template > /home/vncuser/supervisor/supervisord.conf

echo "--- Starting services ---"
echo "PORT=${PORT}, Resolution=${VNC_RESOLUTION}@${VNC_DEPTH}"
echo "VNC password configured (${#PASS} chars)"
echo "Use your configured password in the noVNC interface"
echo "Connecting via: https://your-url (TLS at platform edge, wss:// inside)"

exec /usr/bin/supervisord -c /home/vncuser/supervisor/supervisord.conf
ENTRYPOINT

# Set permissions and switch user
RUN chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER} && \
    chmod +x /home/${VNC_USER}/entrypoint.sh

USER ${VNC_USER}
WORKDIR /home/${VNC_USER}
EXPOSE 6080
CMD ["/home/vncuser/entrypoint.sh"]
