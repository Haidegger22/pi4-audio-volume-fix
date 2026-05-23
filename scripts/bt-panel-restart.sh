#!/bin/bash
# Watch for Bluetooth audio sinks and restart wfpanel if needed
# Called by systemd path unit when /tmp/bt-sink-trigger changes

sleep 2

CURRENT=$(pactl get-default-sink 2>/dev/null)
if echo "$CURRENT" | grep -q "alsa_output"; then
    # Panel is pointing to ALSA - switch to BT combined sink
    BT_COMBINE=$(pactl list sinks short 2>/dev/null | grep "bt-combine" | awk '{print $2}')
    if [ -n "$BT_COMBINE" ]; then
        pactl set-default-sink "$BT_COMBINE" 2>/dev/null
    fi
fi

# Restart ALL wfpanel instances to refresh sink list
killall wf-panel-pi 2>/dev/null
sleep 1

# Clean trigger file to allow re-triggering
rm -f /tmp/bt-sink-trigger
