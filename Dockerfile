# Hardened web-based XFCE desktop with VNC auth, TLS, and non-root user
FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

# Core runtime settings (can override at run time)
ENV DISPLAY=":1" \
    PORT="6080" \
    VNC_RESOLUTION="1366x768" \
    VNC_DEPTH="24" \
    # Files live in the non-root user's home so Supervisor can run unprivileged
    VNC_USER="vncuser" \
    VNC_UID="1000" \
    VNC_GID="1000" \
    NOVNC_CERT="/home/vncuser/.ssl/novnc.crt" \
    NOVNC_KEY="/home/vncuser/.ssl/novnc.key"

# Packages: desktop, VNC, noVNC, proxy, TLS tooling, supervisor
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      supervisor \
      xfce4 \
      xfce4-goodies \
      xorg \
      dbus-x11 \
      tigervnc-standalone-server \
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
    # Use the lightweight noVNC client
    ln -sf /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html

# Supervisor template (programs run as non-root)
COPY <<'EOF' /home/vncuser/supervisor/supervisord.conf.template
[supervisord]
nodaemon=true

[program:xserver]
# Bind VNC to localhost only; require auth; enable TLS on the VNC layer
# Note: Password file created at runtime under /home/vncuser/.vnc/passwd
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
# Terminate TLS at websockify for wss://, and proxy to 127.0.0.1:5901
command=/usr/bin/websockify --verbose --ssl-only --cert ${NOVNC_CERT} --key ${NOVNC_KEY} --web /usr/share/novnc/ 0.0.0.0:${PORT} 127.0.0.1:5901
user=vncuser
priority=3
autorestart=true
EOF

# Entrypoint: create VNC password file, self-signed cert (if missing), render supervisor conf, start services
COPY <<'EOF' /home/vncuser/entrypoint.sh
#!/bin/sh
set -e

umask 077

# Defaults (can be overridden at run time)
PORT="${PORT:-6080}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1366x768}"
VNC_DEPTH="${VNC_DEPTH:-24}"
NOVNC_CERT="${NOVNC_CERT:-/home/vncuser/.ssl/novnc.crt}"
NOVNC_KEY="${NOVNC_KEY:-/home/vncuser/.ssl/novnc.key}"

# Ensure expected dirs exist and are owned by the non-root user
install -d -o vncuser -g vncuser /home/vncuser/.vnc /home/vncuser/.ssl /home/vncuser/supervisor

# Create VNC password file if missing and env VNC_PASSWORD provided
if [ ! -f /home/vncuser/.vnc/passwd ]; then
  if [ -n "${VNC_PASSWORD}" ]; then
    # vncpasswd -f reads password from stdin and writes the obfuscated hash to stdout
    # store at ~/.vnc/passwd with owner-only permissions
    printf "%s\n" "${VNC_PASSWORD}" | vncpasswd -f > /home/vncuser/.vnc/passwd
    chown vncuser:vncuser /home/vncuser/.vnc/passwd
    chmod 600 /home/vncuser/.vnc/passwd
  else
    echo "ERROR: VNC_PASSWORD not set and no existing password file at /home/vncuser/.vnc/passwd"
    echo "Set VNC_PASSWORD to a strong value at 'docker run' time."
    exit 1
  fi
fi

# Create self-signed cert for wss:// if none provided/mounted
if [ ! -f "${NOVNC_CERT}" ] || [ ! -f "${NOVNC_KEY}" ]; then
  echo "Generating self-signed certificate for websockify (dev use) ..."
  openssl req -new -x509 -days 365 -nodes -subj "/CN=localhost" \
    -keyout "${NOVNC_KEY}" -out "${NOVNC_CERT}"
  chown vncuser:vncuser "${NOVNC_CERT}" "${NOVNC_KEY}"
  chmod 600 "${NOVNC_KEY}"
fi

# Render supervisor config with runtime values
VARS_TO_SUBSTITUTE='${PORT} ${VNC_RESOLUTION} ${VNC_DEPTH} ${NOVNC_CERT} ${NOVNC_KEY}'
envsubst "${VARS_TO_SUBSTITUTE}" < /home/vncuser/supervisor/supervisord.conf.template > /home/vncuser/supervisor/supervisord.conf

echo "--- Effective supervisord.conf ---"
cat /home/vncuser/supervisor/supervisord.conf
echo "----------------------------------"
echo "Listening on PORT=${PORT} with VNC ${VNC_RESOLUTION}@${VNC_DEPTH}"

# Start Supervisor as non-root
exec /usr/bin/supervisord -c /home/vncuser/supervisor/supervisord.conf
EOF

# Permissions
RUN chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER} && \
    chmod +x /home/${VNC_USER}/entrypoint.sh

# Drop privileges: run everything as vncuser, including Supervisor
USER ${VNC_USER}

WORKDIR /home/${VNC_USER}

EXPOSE 6080

CMD ["/home/vncuser/entrypoint.sh"]
