#!/bin/bash
set -e

# Set the USER environment variable for VNC
export USER=guacuser

# Clean up old VNC locks in case of a container restart
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Set Java environment for Tomcat
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export JRE_HOME=$JAVA_HOME
export PATH=$JAVA_HOME/bin:$PATH

# Start VNC Server as a background process
echo "Starting VNC server on :1..."
vncserver :1 -geometry 1280x800 -depth 24 &

# Start Guacamole daemon (guacd) listening only on localhost for security and reliability.
# Log level is increased to debug for better diagnostics.
echo "Starting guacd..."
/usr/local/sbin/guacd -b 127.0.0.1 -L debug &

# Wait for guacd to be ready before starting Tomcat
echo "Waiting for guacd to be ready..."
while ! nc -z localhost 4822; do
  sleep 1
done

# Add a small delay to allow guacd to fully initialize
sleep 2
echo "guacd is ready."

# Start Tomcat in the foreground
# This will keep the container running
echo "Starting Tomcat..."
/opt/tomcat/bin/catalina.sh run

