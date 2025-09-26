# Hardened web-based XFCE desktop with VNC auth, TLS, and non-root user
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DEFAULT_VNC_PASSWORD="ChangeMe-Strong!"

# Core runtime settings (override at run time if desired)
ENV DISPLAY=":1" \
    PORT="6080" \
    VNC_RESOLUTION="1366x768" \
    VNC_DEPTH="24" \
    VNC_USER="vncuser" \
    VNC_UID="1000" \
    VNC_GID="1000" \
    NOVNC_CERT="/home/vncuser/.ssl/novnc.crt" \
    NOVNC_KEY="/home/vncuser/.ssl/novnc.key"

# Packages: include tigervnc-common to provide vncpasswd
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

# Supervisor template (programs run as non-root)
COPY <<'EOF' /home/vncuser/supervisor/supervisord.conf.template
[supervisord]
nodaemon=true

[program:xserver]
command=/usr/bin/Xvnc :1 -rfbport 5901 -geometry ${VNC_RESOLUTION} -depth ${VNC_DEPTH} -SecurityTypes TLSVnc,VncAuth -PasswordFile /home/vncuser/.vnc/passwd -localhost
user=vncuser
priority=1
autorestart=true

[program:xfce]
command=/bin/sh -c "dbus-launch startxfce4"
environment=DISPLAY=":1"
user=vncuser
priority=2
autorestart=true

[program:novnc]
command=/usr/bin/websockify --verbose --ssl-only --cert ${NOVNC_CERT} --key ${NOVNC_KEY} --web /usr/share/novnc/ 0.0.0.0:${PORT} 127.0.0.1:5901
user=vncuser
priority=3
autorestart=true
EOF

# Entrypoint
COPY <<'EOF' /home/vncuser/entrypoint.sh
#!/bin/sh
set -e
umask 077

PORT="${PORT:-6080}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1366x768}"
VNC_DEPTH="${VNC_DEPTH:-24}"
NOVNC_CERT="${NOVNC_CERT:-/home/vncuser/.ssl/novnc.crt}"
NOVNC_KEY="${NOVNC_KEY:-/home/vncuser/.ssl/novnc.key}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-ChangeMe-Strong!}"

install -d -o vncuser -g vncuser /home/vncuser/.vnc /home/vncuser/.ssl /home/vncuser/supervisor

# Create or re-use VNC password file; prefer VNC_PASSWORD, else default
if [ ! -f /home/vncuser/.vnc/passwd ]; then
  PASS="${
