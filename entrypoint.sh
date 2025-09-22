#!/bin/bash
set -e

# Set environment variables for services
export USER=guacuser
export HOME=/home/guacuser
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

# Clean up old VNC locks to ensure a clean start
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Start the TigerVNC server in the background
# It will automatically find and use the ~/.vnc/xstartup script
echo "Starting TigerVNC server on :1..."
vncserver :1 -localhost no -geometry 1280x800 -depth 24 &

# Start the Guacamole daemon in the background
echo "Starting guacd..."
/usr/local/sbin/guacd -b 0.0.0.0 -L info &

# Wait for services to initialize before starting Tomcat
echo "Waiting for services to settle..."
sleep 3

# Start Tomcat as a background daemon
echo "Starting Tomcat..."
/opt/tomcat/bin/catalina.sh start

# Keep the container alive by tailing the Tomcat log file
echo "Streaming Tomcat logs..."
tail -f /opt/tomcat/logs/catalina.out

