#!/bin/bash
# Wait for any Bluetooth audio sink to appear, then create combine-sink
# for software volume control (BT speakers usually can't do hardware volume)

SINK_NAME="bt-combine"
MAX_WAIT=30

# Wait for pipewire-pulse
for i in $(seq 1 10); do
    if pactl info &>/dev/null; then break; fi
    sleep 1
done

# Wait for a Bluetooth sink
for i in $(seq 1 $MAX_WAIT); do
    BT_SINK=$(pactl list sinks short 2>/dev/null | grep "bluez_output" | awk '{print $2}')
    if [ -n "$BT_SINK" ]; then
        echo "Found BT sink: $BT_SINK"
        # Check if combine-sink already exists
        if ! pactl list sinks short 2>/dev/null | grep -q "$SINK_NAME"; then
            MOD_ID=$(pactl load-module module-combine-sink sink_name="$SINK_NAME" slaves="$BT_SINK" 2>&1)
            sleep 1
            if [ -n "$MOD_ID" ]; then
                pactl set-default-sink "$SINK_NAME" 2>/dev/null
                echo "Created combine-sink '$SINK_NAME' (module $MOD_ID) -> $BT_SINK"
            fi
        else
            pactl set-default-sink "$SINK_NAME" 2>/dev/null
            echo "Combine-sink already exists, set as default"
        fi
        touch /tmp/bt-sink-trigger 2>/dev/null || true
        exit 0
    fi
    sleep 1
done

echo "No BT sink found after ${MAX_WAIT}s, will retry via systemd path"
exit 1
