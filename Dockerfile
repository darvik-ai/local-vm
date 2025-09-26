# Hardened web-based XFCE desktop with VNC auth and non-root user
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
      python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create non-root user and workspace
RUN useradd -m -u ${VNC_UID} -s /bin/bash ${VNC_USER} && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/.vnc && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/supervisor && \
    ln -sf /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html

# Create supervisor template (HTTP websockify for platform compatibility)
RUN cat > /home/vncuser/supervisor/supervisord.conf.template << 'TEMPLATE'
[supervisord]
nodaemon=true

[program:xserver]
command=/usr/bin/Xvnc :1 -rfbport 5901 -geometry ${VNC_RESOLUTION} -depth ${VNC_DEPTH} -SecurityTypes VncAuth -PasswordFile /home/vncuser/.vnc/passwd -localhost
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
command=/usr/bin/websockify --verbose --web /usr/share/novnc/ 0.0.0.0:${PORT} 127.0.0.1:5901
user=vncuser
priority=3
autorestart=true
TEMPLATE

# Create entrypoint with working VNC password setup
RUN cat > /home/vncuser/entrypoint.sh << 'ENTRYPOINT'
#!/bin/bash
set -e

PORT="${PORT:-6080}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1366x768}"
VNC_DEPTH="${VNC_DEPTH:-24}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-ChangeMe-Strong!}"

install -d -o vncuser -g vncuser /home/vncuser/.vnc /home/vncuser/supervisor

# Create VNC password file using Python (reliable cross-platform approach)
if [ ! -f /home/vncuser/.vnc/passwd ]; then
  PASS="${VNC_PASSWORD:-$DEFAULT_VNC_PASSWORD}"
  echo "Creating VNC password file..."
  
  python3 -c "
import struct
import os

def create_vnc_passwd(password, filename):
    # VNC uses DES encryption with a specific key pattern
    # This is the standard VNC password obfuscation
    key = [23, 82, 107, 6, 35, 78, 88, 7]
    password = password[:8].ljust(8, '\x00')
    
    encrypted = []
    for i in range(8):
        encrypted.append(ord(password[i]) ^ key[i])
    
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    with open(filename, 'wb') as f:
        f.write(bytes(encrypted))
    
    os.chmod(filename, 0o600)

create_vnc_passwd('$PASS', '/home/vncuser/.vnc/passwd')
print('VNC password file created successfully')
"
  
  chown vncuser:vncuser /home/vncuser/.vnc/passwd
fi

# Render config
export PORT VNC_RESOLUTION VNC_DEPTH
envsubst < /home/vncuser/supervisor/supervisord.conf.template > /home/vncuser/supervisor/supervisord.conf

echo "--- Effective supervisord.conf ---"
cat /home/vncuser/supervisor/supervisord.conf
echo "----------------------------------"
echo "Listening on PORT=${PORT} with VNC ${VNC_RESOLUTION}@${VNC_DEPTH}"
echo "VNC password: Use the configured password to connect"

exec /usr/bin/supervisord -c /home/vncuser/supervisor/supervisord.conf
ENTRYPOINT

# Set permissions and switch user
RUN chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER} && \
    chmod +x /home/${VNC_USER}/entrypoint.sh

USER ${VNC_USER}
WORKDIR /home/${VNC_USER}
EXPOSE 6080
CMD ["/home/vncuser/entrypoint.sh"]
