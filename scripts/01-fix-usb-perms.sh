#!/usr/bin/env bash
# One-time host setup: let a non-root user open the AURIX miniWiggler
# (058b:0043) via raw libusb (needed by tas_server/D2XX), and free its UART
# channel (1-4:1.1, /dev/ttyUSB0) from the kernel's ftdi_sio driver so TAS
# can claim it instead. Needs sudo; safe to re-run.
set -euo pipefail

RULE=/etc/udev/rules.d/99-infineon-tas.rules
if [ ! -f "$RULE" ]; then
    echo 'SUBSYSTEM=="usb", ATTR{idVendor}=="058b", ATTR{idProduct}=="0043", MODE="0666"' | sudo tee "$RULE" > /dev/null
    sudo udevadm control --reload-rules
    sudo udevadm trigger
    echo "installed $RULE"
else
    echo "$RULE already present"
fi

# Only touch the interface that's actually bound to ftdi_sio right now --
# there may be an unrelated FT232 cable plugged in too (1-1:1.0 in one
# observed case), and unbinding that would be someone else's UART.
target=""
for dev in /sys/bus/usb/devices/*; do
    [ -f "$dev/idVendor" ] || continue
    [ "$(cat "$dev/idVendor" 2>/dev/null)" = "058b" ] || continue
    [ "$(cat "$dev/idProduct" 2>/dev/null)" = "0043" ] || continue
    for iface in "$dev":*; do
        if [ -e "$iface/driver" ] && [ "$(basename "$(readlink -f "$iface/driver")")" = "ftdi_sio" ]; then
            target=$(basename "$iface")
        fi
    done
done

if [ -n "$target" ]; then
    echo -n "$target" | sudo tee /sys/bus/usb/drivers/ftdi_sio/unbind > /dev/null
    echo "unbound ftdi_sio from $target (this kills /dev/ttyUSB0 for the AURIX board while TAS is in use)"
else
    echo "ftdi_sio not bound to the AURIX board's UART channel -- nothing to unbind"
fi
