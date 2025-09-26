# Hardened web-based XFCE desktop with VNC auth and debugging
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DEFAULT_VNC_PASSWORD="ChangeMe-Strong!"

# Core runtime settings
ENV DISPLAY=":1" \
    PORT="6080" \
    VNC_RESOLUTION="1366x768" \
    VNC_DEPTH="24" \
    VNC_USER="vncuser" \
    VNC_UID="1000" \
    VNC_GID="1000"

# Install packages including debugging tools
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
      net-tools \
      procps \
      netcat && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create non-root user and workspace
RUN useradd -m -u ${VNC_UID} -s /bin/bash ${VNC_USER} && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/.vnc && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/supervisor && \
    ln -sf /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html

# Create supervisor template (removed -localhost for debugging)
RUN cat > /home/vncuser/supervisor/supervisord.conf.template << 'TEMPLATE'
[supervisord]
nodaemon=true

[program:xserver]
command=/usr/bin/Xvnc :1 -rfbport 5901 -geometry ${VNC_RESOLUTION} -depth ${VNC_DEPTH} -SecurityTypes VncAuth -PasswordFile /home/vncuser/.vnc/passwd -AlwaysShared
user=vncuser
priority=1
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:xfce]
command=/bin/sh -c "sleep 3 && dbus-launch startxfce4"
environment=DISPLAY=":1"
user=vncuser
priority=2
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:novnc]
command=/usr/bin/websockify --verbose --web /usr/share/novnc/ 0.0.0.0:${PORT} 127.0.0.1:5901
user=vncuser
priority=3
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
TEMPLATE

# Create entrypoint with debugging
RUN cat > /home/vncuser/entrypoint.sh << 'ENTRYPOINT'
#!/bin/bash
set -e

PORT="${PORT:-6080}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1366x768}"
VNC_DEPTH="${VNC_DEPTH:-24}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-ChangeMe-Strong!}"

install -d -o vncuser -g vncuser /home/vncuser/.vnc /home/vncuser/supervisor

# Create VNC password file
if [ ! -f /home/vncuser/.vnc/passwd ]; then
  PASS="${VNC_PASSWORD:-$DEFAULT_VNC_PASSWORD}"
  echo "Creating VNC password file..."
  
  echo "$PASS" | /usr/bin/vncpasswd -f > /home/vncuser/.vnc/passwd
  chown vncuser:vncuser /home/vncuser/.vnc/passwd
  chmod 600 /home/vncuser/.vnc/passwd
  
  # Debug: verify password file was created
  echo "Password file created, size: $(wc -c < /home/vncuser/.vnc/passwd) bytes"
  echo "VNC password file created successfully"
fi

# Render config
export PORT VNC_RESOLUTION VNC_DEPTH
envsubst < /home/vncuser/supervisor/supervisord.conf.template > /home/vncuser/supervisor/supervisord.conf

echo "--- Effective supervisord.conf ---"
cat /home/vncuser/supervisor/supervisord.conf
echo "----------------------------------"
echo "Starting services..."
echo "Listening on PORT=${PORT} with VNC ${VNC_RESOLUTION}@${VNC_DEPTH}"
echo "Password configured: ${#PASS} characters"

# Start supervisor in background to allow debugging
/usr/bin/supervisord -c /home/vncuser/supervisor/supervisord.conf &
SUPERVISOR_PID=$!

# Give services time to start
sleep 10

# Debug information
echo "=== DEBUGGING INFORMATION ==="
echo "Processes running:"
ps aux | grep -E "(Xvnc|websockify|startxfce4)" | grep -v grep

echo ""
echo "Network ports listening:"
netstat -tlnp 2>/dev/null | grep -E "(590|${PORT})" || echo "No VNC/websockify ports found"

echo ""
echo "Testing VNC connection locally:"
nc -z 127.0.0.1 5901 && echo "VNC port 5901 is accessible" || echo "VNC port 5901 is NOT accessible"

echo ""
echo "Testing websockify port:"
nc -z 127.0.0.1 ${PORT} && echo "Websockify port ${PORT} is accessible" || echo "Websockify port ${PORT} is NOT accessible"

echo ""
echo "VNC password file check:"
ls -la /home/vncuser/.vnc/passwd 2>/dev/null && echo "Password file exists" || echo "Password file missing"

echo "=== END DEBUG INFO ==="

# Wait for supervisor to finish
wait $SUPERVISOR_PID
ENTRYPOINT

# Set permissions and switch user
RUN chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER} && \
    chmod +x /home/${VNC_USER}/entrypoint.sh

USER ${VNC_USER}
WORKDIR /home/${VNC_USER}
EXPOSE 6080
CMD ["/home/vncuser/entrypoint.sh"]
