#!/bin/sh

if [ "$DECONZ_START_VERBOSE" = 1 ]; then
    set -x
fi

echo "[deconzcommunity/deconz] Starting deCONZ..."
echo "[deconzcommunity/deconz] Current deCONZ version: $DECONZ_VERSION"
echo "[deconzcommunity/deconz] Web UI port: $DECONZ_WEB_PORT"
echo "[deconzcommunity/deconz] Websockets port: $DECONZ_WS_PORT"

DECONZ_OPTS="--auto-connect=1 \
        --appdata=/opt/deCONZ \
        --dbg-info=$DEBUG_INFO \
        --dbg-aps=$DEBUG_APS \
        --dbg-zcl=$DEBUG_ZCL \
        --dbg-ddf=$DEBUG_DDF \
        --dbg-dev=$DEBUG_DEV \
        --dbg-zdp=$DEBUG_ZDP \
        --dbg-ota=$DEBUG_OTA \
        --dbg-error=$DEBUG_ERROR \
        --http-port=$DECONZ_WEB_PORT \
        --ws-port=$DECONZ_WS_PORT"

echo "[deconzcommunity/deconz] Using options $DECONZ_OPTS"

echo "[deconzcommunity/deconz] Modifying user and group ID"
if [ "$DECONZ_UID" != 1000 ]; then
    DECONZ_UID=${DECONZ_UID:-1000}
    usermod -o -u "$DECONZ_UID" deconz
fi

if [ "$DECONZ_GID" != 1000 ]; then
    DECONZ_GID=${DECONZ_GID:-1000}
    groupmod -o -g "$DECONZ_GID" deconz
fi

echo "[deconzcommunity/deconz] Checking device group ID"
if [ "$DECONZ_DEVICE" != 0 ]; then
    DEVICE=$DECONZ_DEVICE
else
    if [ -e /dev/ttyACM0 ]; then
        DEVICE=/dev/ttyACM0
    elif [ -e /dev/ttyAMA0 ]; then
        DEVICE=/dev/ttyAMA0
    elif [ -e /dev/ttyS0 ]; then
        DEVICE=/dev/ttyS0
    elif [ -e /dev/ttyUSB0 ]; then
        DEVICE=/dev/ttyUSB0
    fi
fi

DIALOUTGROUPID=$(stat --printf='%g' $DEVICE)
DIALOUTGROUPID=${DIALOUTGROUPID:-20}
if [ "$DIALOUTGROUPID" != 20 ]; then
  groupmod -o -g "$DIALOUTGROUPID" dialout
fi

# workaround if the group of the device doesn't have any permissions
GROUPPERMISSIONS=$(stat -c "%A" $DEVICE | cut -c 5-7)
if [ "$GROUPPERMISSIONS" = "---" ]; then
  chmod g+rw $DEVICE
fi

# start Xvfb
Xvfb :0 -screen 0 1024x768x16 -listen tcp -ac &

# start x11vnc
x11vnc -forever -shared

if [ "$DECONZ_VNC_MODE" != 0 ]; then
    if [ "$DECONZ_VNC_PORT" -lt 5900 ]; then
        echo "[deconzcommunity/deconz] ERROR - VNC port must be 5900 or greater!"
        exit 1
    fi

    DECONZ_VNC_DISPLAY=:$(($DECONZ_VNC_PORT - 5900))
    echo "[deconzcommunity/deconz] VNC port: $DECONZ_VNC_PORT"

    if [ ! -e /opt/deCONZ/vnc ]; then
        mkdir -p /opt/deCONZ/vnc
    fi

    ln -sfT /opt/deCONZ/vnc /home/deconz/.vnc
    chown deconz:deconz /home/deconz/.vnc
    chown -R deconz:deconz /opt/deCONZ

    # Set VNC password
    if [ "$DECONZ_VNC_PASSWORD_FILE" != 0 ] && [ -f "$DECONZ_VNC_PASSWORD_FILE" ]; then
        DECONZ_VNC_PASSWORD=$(cat $DECONZ_VNC_PASSWORD_FILE)
    fi

#    echo "$DECONZ_VNC_PASSWORD" | tigervncpasswd -f > /opt/deCONZ/vnc/passwd
#    chmod 600 /opt/deCONZ/vnc/passwd
#    chown deconz:deconz /opt/deCONZ/vnc/passwd

    # Cleanup previous VNC session data
#    gosu deconz tigervncserver -kill ':*'
#    gosu deconz tigervncserver -list ':*' -cleanstale
#    for lock in "/tmp/.X${DECONZ_VNC_DISPLAY#:}-lock" "/tmp/.X11-unix/X${DECONZ_VNC_DISPLAY#:}"; do
#        [ -e "$lock" ] || continue
#        echo "[deconzcommunity/deconz] WARN - VNC-lock found. Deleting: $lock"
#        rm "$lock"
#    done

    # Set VNC security
#    gosu deconz tigervncserver -SecurityTypes VncAuth,TLSVnc "$DECONZ_VNC_DISPLAY"

    # Export VNC display variable
    export DISPLAY=$DECONZ_VNC_DISPLAY

    if [ "$DECONZ_NOVNC_PORT" = 0 ]; then
        echo "[deconzcommunity/deconz] noVNC Disabled"
    elif [ "$DECONZ_NOVNC_PORT" -lt 6080 ]; then
        echo "[deconzcommunity/deconz] ERROR - NOVNC port must be 6080 or greater!"
        exit 1
    fi

    # Assert valid SSL certificate
    NOVNC_CERT="/opt/deCONZ/vnc/novnc.pem"
    if [ -f "$NOVNC_CERT" ]; then
        openssl x509 -noout -in "$NOVNC_CERT" -checkend 0 > /dev/null
        if [ $? != 0 ]; then
            echo "[deconzcommunity/deconz] The noVNC SSL cert has expired; generating a new certificate."
            rm "$NOVNC_CERT"
        fi
    fi

    if [ ! -f "$NOVNC_CERT" ]; then
      openssl req -x509 -nodes -newkey rsa:2048 -keyout "$NOVNC_CERT" -out "$NOVNC_CERT" -days 365 -subj "/CN=deconz"
    fi

    chown deconz:deconz $NOVNC_CERT

    #Start noVNC
    gosu deconz websockify -D --web=/usr/share/novnc/ --cert="$NOVNC_CERT" $DECONZ_NOVNC_PORT localhost:$DECONZ_VNC_PORT
    echo "[deconzcommunity/deconz] NOVNC port: $DECONZ_NOVNC_PORT"
else
    echo "[deconzcommunity/deconz] VNC Disabled"
    DECONZ_OPTS="$DECONZ_OPTS -platform minimal"
fi

if [ "$DECONZ_DEVICE" != 0 ]; then
    DECONZ_OPTS="$DECONZ_OPTS --dev=$DECONZ_DEVICE"
fi

if [ "$DECONZ_UPNP" != 1 ]; then
    DECONZ_OPTS="$DECONZ_OPTS --upnp=0"
fi

mkdir -p /opt/deCONZ/otau
ln -sfT /opt/deCONZ/otau /home/deconz/otau
chown deconz:deconz /home/deconz/otau
chown -R deconz:deconz /opt/deCONZ

exec gosu deconz /usr/bin/deCONZ $DECONZ_OPTS
