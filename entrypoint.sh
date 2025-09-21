#!/bin/bash
set -e

# Clean up any stale VNC lock files that might prevent the server from starting.
# This makes the script more resilient to unclean shutdowns or container restarts.
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Start VNC Server on display :1 (which corresponds to TCP port 5901)
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

# Set the JRE_HOME environment variable for Tomcat
# This path must match the Java installation location from the Dockerfile.
export JRE_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Start Tomcat in the foreground. This keeps the container running.
echo "Starting Tomcat..."
/opt/tomcat/bin/catalina.sh run

