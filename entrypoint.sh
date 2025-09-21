#!/bin/bash
set -e

# Start VNC Server on display :1 (which corresponds to TCP port 5901)
# The '-localhost no' flag was removed as it was causing an error.
# The server will listen on all interfaces by default.
echo "Starting VNC server on :1..."
vncserver :1 -geometry 1280x800 -depth 24

# Start guacd (the Guacamole proxy daemon) in the background as root
echo "Starting guacd..."
sudo /usr/local/sbin/guacd -b 0.0.0.0 -L info -f &

# Wait until guacd is listening on its port
while ! nc -z 127.0.0.1 4822; do
  echo "Waiting for guacd to be ready..."
  sleep 1
done
echo "guacd is ready."

# Start Tomcat in the foreground. This keeps the container running.
echo "Starting Tomcat..."
/opt/tomcat/bin/catalina.sh run

