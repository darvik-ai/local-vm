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
set -ex

# Create /tmp/.X11-unix with correct permissions for X server
mkdir -p /tmp/.X11-unix
chmod 1777 /tmp/.X11-unix

# Environment variables with defaults
PORT="${PORT:-6080}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1366x768}"
VNC_DEPTH="${VNC_DEPTH:-24}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-ChangeMe-Strong!}"

# Create necessary directories with proper ownership
mkdir -p /home/vncuser/.vnc /home/vncuser/.ssl
chown vncuser:vncuser /home/vncuser/.vnc /home/vncuser/.ssl

# Create VNC password file if missing
if [ ! -f /home/vncuser/.vnc/passwd ]; then
  echo "Creating VNC password file..."
  echo "${VNC_PASSWORD:-$DEFAULT_VNC_PASSWORD}" | /usr/bin/vncpasswd -f > /home/vncuser/.vnc/passwd
  chown vncuser:vncuser /home/vncuser/.vnc/passwd
  chmod 600 /home/vncuser/.vnc/passwd
  echo "VNC password file created"
fi

# Generate self-signed TLS certificate if missing
if [ ! -f /home/vncuser/.ssl/novnc.crt ] || [ ! -f /home/vncuser/.ssl/novnc.key ]; then
  echo "Generating self-signed TLS certificate..."
  openssl req -new -x509 -days 365 -nodes -subj "/CN=localhost" \
    -keyout /home/vncuser/.ssl/novnc.key -out /home/vncuser/.ssl/novnc.crt
  chown vncuser:vncuser /home/vncuser/.ssl/*
  chmod 600 /home/vncuser/.ssl/novnc.key
  echo "TLS certificate generated"
fi

# Start Xvnc server with verbose logging
echo "Starting Xvnc..."
/usr/bin/Xvnc :1 -rfbport 5901 -geometry "${VNC_RESOLUTION}" -depth "${VNC_DEPTH}" \
  -PasswordFile /home/vncuser/.vnc/passwd -SecurityTypes VncAuth -AlwaysShared \
  -BlacklistThreshold=0 -MaxConnectionTime=0 -MaxIdleTime=0 -MaxDisconnectionTime=0 \
  -AcceptCutText=0 -SendCutText=0 2>&1 &
XVNC_PID=$!

# Wait for Xvnc startup
sleep 5

# Start XFCE session
echo "Starting XFCE desktop..."
dbus-launch startxfce4 2>&1 &
XFCE_PID=$!

# Start noVNC & websockify with TLS only and verbose logging
echo "Starting noVNC/websockify..."
/usr/bin/websockify --verbose --web /usr/share/novnc/ --ssl-only \
  --cert /home/vncuser/.ssl/novnc.crt --key /home/vncuser/.ssl/novnc.key \
  0.0.0.0:${PORT} 127.0.0.1:5901 2>&1 &
NOVNC_PID=$!

# Handle termination signals and cleanup
trap "echo 'Stopping services...'; kill -TERM $XVNC_PID $XFCE_PID $NOVNC_PID; wait; exit 0" SIGINT SIGTERM

echo "Services started. Listening on port ${PORT} with resolution ${VNC_RESOLUTION}@${VNC_DEPTH}"
echo "Connect using VNC password."

# Wait for any process to exit
wait -n $XVNC_PID $XFCE_PID $NOVNC_PID

echo "One of the services exited, shutting down."
kill -TERM $XVNC_PID $XFCE_PID $NOVNC_PID
wait

exit 0

EOF

RUN chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER} && chmod +x /home/${VNC_USER}/entrypoint.sh

USER ${VNC_USER}
WORKDIR /home/${VNC_USER}

EXPOSE 6080
CMD ["/home/vncuser/entrypoint.sh"]
