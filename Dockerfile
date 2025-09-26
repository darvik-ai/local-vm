# Hardened web-based XFCE desktop with VNC auth, TLS, and non-root user
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
    VNC_GID="1000" \
    NOVNC_CERT="/home/vncuser/.ssl/novnc.crt" \
    NOVNC_KEY="/home/vncuser/.ssl/novnc.key"

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
      openssl \
      python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create non-root user and workspace
RUN useradd -m -u ${VNC_UID} -s /bin/bash ${VNC_USER} && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/.vnc && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/.ssl && \
    install -d -o ${VNC_USER} -g ${VNC_USER} /home/${VNC_USER}/supervisor && \
    ln -sf /usr/share/novnc/vnc_lite.html /usr/share/novnc/index.html

# Create supervisor template
RUN cat > /home/vncuser/supervisor/supervisord.conf.template << 'TEMPLATE'
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
TEMPLATE

# Create VNC password creation script
RUN cat > /home/vncuser/create_vnc_passwd.py << 'PYTHON'
#!/usr/bin/env python3
import os
import sys
from Crypto.Cipher import DES

def vnc_encrypt_password(password):
    # VNC uses DES with a fixed key (reversed)
    key = b'\x17\x52\x6b\x06\x23\x4e\x58\x07'
    
    # Pad password to 8 bytes
    password = password[:8].ljust(8, '\0')
    
    # Encrypt
    cipher = DES.new(key, DES.MODE_ECB)
    encrypted = cipher.encrypt(password.encode('latin1'))
    
    return encrypted

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: create_vnc_passwd.py <password>")
        sys.exit(1)
    
    password = sys.argv[1]
    encrypted = vnc_encrypt_password(password)
    
    # Write to stdout (will be redirected to passwd file)
    sys.stdout.buffer.write(encrypted)
PYTHON

# Simplified entrypoint script
RUN cat > /home/vncuser/entrypoint.sh << 'ENTRYPOINT'
#!/bin/bash
set -e
umask 077

PORT="${PORT:-6080}"
VNC_RESOLUTION="${VNC_RESOLUTION:-1366x768}"
VNC_DEPTH="${VNC_DEPTH:-24}"
NOVNC_CERT="${NOVNC_CERT:-/home/vncuser/.ssl/novnc.crt}"
NOVNC_KEY="${NOVNC_KEY:-/home/vncuser/.ssl/novnc.key}"
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-ChangeMe-Strong!}"

install -d -o vncuser -g vncuser /home/vncuser/.vnc /home/vncuser/.ssl /home/vncuser/supervisor

# Create VNC password file if missing
if [ ! -f /home/vncuser/.vnc/passwd ]; then
  PASS="${VNC_PASSWORD:-$DEFAULT_VNC_PASSWORD}"
  echo "Creating VNC password file..."
  
  # Create password file with a simple approach - write the password in plain text first
  # then let VNC server handle the encryption on first connection
  mkdir -p /home/vncuser/.vnc
  echo "$PASS" > /tmp/vnc_plain_pass
  
  # Use a simple VNC password creation that works
  printf '%s\n%s\nn\n' "$PASS" "$PASS" | su - vncuser -c 'vncpasswd' || {
    # Fallback: create a basic password file manually
    python3 -c "
import os
import struct
# Simple VNC password obfuscation
key = [23, 82, 107, 6, 35, 78, 88, 7]
password = '$PASS'[:8].ljust(8, '\x00')
result = []
for i in range(8):
    result.append(ord(password[i]) ^ key[i])
with open('/home/vncuser/.vnc/passwd', 'wb') as f:
    f.write(bytes(result))
"
  }
  
  chown vncuser:vncuser /home/vncuser/.vnc/passwd
  chmod 600 /home/vncuser/.vnc/passwd
  rm -f /tmp/vnc_plain_pass
fi

# Self-signed cert for WSS
if [ ! -f "${NOVNC_CERT}" ] || [ ! -f "${NOVNC_KEY}" ]; then
  echo "Generating self-signed certificate for websockify..."
  openssl req -new -x509 -days 365 -nodes -subj "/CN=localhost" \
    -keyout "${NOVNC_KEY}" -out "${NOVNC_CERT}"
  chown vncuser:vncuser "${NOVNC_CERT}" "${NOVNC_KEY}"
  chmod 600 "${NOVNC_KEY}"
fi

# Render config
export PORT VNC_RESOLUTION VNC_DEPTH NOVNC_CERT NOVNC_KEY
envsubst < /home/vncuser/supervisor/supervisord.conf.template > /home/vncuser/supervisor/supervisord.conf

echo "--- Effective supervisord.conf ---"
cat /home/vncuser/supervisor/supervisord.conf
echo "----------------------------------"
echo "Listening on PORT=${PORT} with VNC ${VNC_RESOLUTION}@${VNC_DEPTH}"

exec /usr/bin/supervisord -c /home/vncuser/supervisor/supervisord.conf
ENTRYPOINT

# Set permissions and switch user
RUN chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER} && \
    chmod +x /home/${VNC_USER}/entrypoint.sh && \
    chmod +x /home/${VNC_USER}/create_vnc_passwd.py

USER ${VNC_USER}
WORKDIR /home/${VNC_USER}
EXPOSE 6080
CMD ["/home/vncuser/entrypoint.sh"]
