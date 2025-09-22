#!/bin/bash
set -e

# Set environment variables required for services to run
export USER=guacuser
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
export JRE_HOME=$JAVA_HOME
export PATH=$JAVA_HOME/bin:$PATH

# Clean up old VNC locks in case of a messy container restart
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

# Start VNC Server and guacd as background processes
echo "Starting VNC server on :1..."
vncserver :1 -geometry 1280x800 -depth 24 &

echo "Starting guacd..."
/usr/local/sbin/guacd -b 0.0.0.0 -L info &

# Give the services a moment to initialize fully before starting Tomcat
sleep 3

# Start Tomcat in the background using the 'start' command
echo "Starting Tomcat..."
/opt/tomcat/bin/catalina.sh start

# Tail the main Tomcat log file. This will stream the logs to the container's
# output and, most importantly, keep the script running in the foreground,
# which prevents the container from exiting.
echo "Streaming Tomcat logs to keep container alive..."
tail -f /opt/tomcat/logs/catalina.out

