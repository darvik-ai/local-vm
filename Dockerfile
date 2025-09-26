FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV DEFAULT_VNC_PASSWORD="ChangeMe-Strong!"

ENV DISPLAY=":1" \
    PORT="6080" \
    VNC_RESOLUTION="1366x768" \
    VNC_DEPTH="24" \
    VNC_USER="vncuser" \
    VNC_UID="1000" \
    VNC_GID="1000"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
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

# Add non-root user and create directories
RUN useradd -m -u ${VNC_UID} -s /bin/bash ${VNC_USER} && \
    mkdir -p /home/${VNC_USER}/.vnc /home/${VNC_USER}/.ssl && \
    chown -R ${VNC_USER}:${VNC_USER} /home/${VNC_USER}

# Add inline entrypoint script
RUN echo '#!/bin/bash\n\
set -ex\n\
\n\
mkdir -p /tmp/.X11-unix\n\
chmod 1777 /tmp/.X11-unix\n\
\n\
PORT="${PORT:-6080}"\n\
VNC_RESOLUTION="${VNC_RESOLUTION:-1366x768}"\n\
VNC_DEPTH="${VNC_DEPTH:-24}"\n\
DEFAULT_VNC_PASSWORD="${DEFAULT_VNC_PASSWORD:-ChangeMe-Strong!}"\n\
\n\
mkdir -p /home/vncuser/.vnc /home/vncuser/.ssl\n\
chown vncuser:vncuser /home/vncuser/.vnc /home/vncuser/.ssl\n\
\n\
if [ ! -f /home/vncuser/.vnc/passwd ]; then\n\
  echo "Creating VNC password file..."\n\
  echo "${VNC_PASSWORD:-$DEFAULT_VNC_PASSWORD}" | vncpasswd -f > /home/vncuser/.vnc/passwd\n\
  chown vncuser:vncuser /home/vncuser/.vnc/passwd\n\
  chmod 600 /home/vncuser/.vnc/passwd\n\
  echo "VNC password file created"\n\
fi\n\
\n\
if [ ! -f /home/vncuser/.ssl/novnc.crt ] || [ ! -f /home/vncuser/.ssl/novnc.key ]; then\n\
  echo "Generating TLS certificate..."\n\
  openssl req -new -x509 -days 365 -nodes -subj "/CN=localhost" \\\n\
    -keyout /home/vncuser/.ssl/novnc.key -out /home/vncuser/.ssl/novnc.crt\n\
  chown vncuser:vncuser /home/vncuser/.ssl/*\n\
  chmod 600 /home/vncuser/.ssl/novnc.key\n\
  echo "TLS certificate generated"\n\
fi\n\
\n\
echo "Starting Xvnc..."\n\
/usr/bin/Xvnc :1 -rfbport 5901 -geometry "$VNC_RESOLUTION" -depth "$VNC_DEPTH" \\\n\
  -PasswordFile /home/vncuser/.vnc/passwd -SecurityTypes VncAuth -AlwaysShared \\\n\
  -BlacklistThreshold=0 -MaxConnectionTime=0 -MaxIdleTime=0 -MaxDisconnectionTime=0 \\\n\
  -AcceptCutText=0 -SendCutText=0 2>&1 &\n\
XVNC_PID=$!\n\
sleep 5\n\
\n\
echo "Starting XFCE desktop..."\n\
dbus-launch startxfce4 2>&1 &\n\
XFCE_PID=$!\n\
\n\
echo "Starting noVNC..."\n\
/usr/bin/websockify --verbose --web /usr/share/novnc/ --ssl-only \\\n\
  --cert /home/vncuser/.ssl/novnc.crt --key /home/vncuser/.ssl/novnc.key \\\n\
  0.0.0.0:"$PORT" 127.0.0.1:5901 2>&1 &\n\
NOVNC_PID=$!\n\
\n\
trap "echo Stopping...; kill -TERM $XVNC_PID $XFCE_PID $NOVNC_PID; wait; exit 0" SIGINT SIGTERM\n\
\necho "Listening on port $PORT, resolution $VNC_RESOLUTION@$VNC_DEPTH. Connect with your VNC password."\n\
wait -n $XVNC_PID $XFCE_PID $NOVNC_PID\n\
echo "Service exited, shutting down..."\n\
kill -TERM $XVNC_PID $XFCE_PID $NOVNC_PID\n\
wait\n\
exit 0\n' > /home/${VNC_USER}/entrypoint.sh && \
    chown ${VNC_USER}:${VNC_USER} /home/${VNC_USER}/entrypoint.sh && \
    chmod +x /home/${VNC_USER}/entrypoint.sh

USER ${VNC_USER}
WORKDIR /home/${VNC_USER}

EXPOSE 6080

ENTRYPOINT ["/home/vncuser/entrypoint.sh"]
