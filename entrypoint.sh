#!/bin/bash
set -e

# Start guacd as root in the background
echo "Starting guacd..."
sudo /usr/local/sbin/guacd -b 0.0.0.0 -l 4822 &

# Start xrdp services as root in the background
echo "Starting xrdp..."
sudo service xrdp start &

# Wait until guacd is listening on its port
echo "Waiting for guacd to be ready..."
while ! nc -z 127.0.0.1 4822; do
  sleep 1
done
echo "guacd is running."

# Start Tomcat in the foreground.
# This will keep the container running and display Tomcat logs.
echo "Starting Tomcat..."
/opt/tomcat/bin/catalina.sh run
