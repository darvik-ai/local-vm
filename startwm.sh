#!/bin/sh
#
# This script is executed by xrdp to start the user's desktop environment.
# This is configured to start an XFCE4 session.

# Unset variables that might interfere with the session
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

# Load system-wide environment variables
. /etc/profile

# Start the XFCE4 desktop environment
startxfce4
