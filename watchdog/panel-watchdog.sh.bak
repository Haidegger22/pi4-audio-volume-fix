#!/bin/bash
# panel-watchdog.sh — следит за подключением дисплеев и перезапускает панели
# Запускается из autostart labwc

CONFIG_DIR=/home/pi/.config/wfpanel
LOG_FILE=/tmp/panel-watchdog.log
LOCK_DIR=/tmp/panel-watchdog.lock

log() {
    echo "[$(date '+%H:%M:%S')] $*" >> "$LOG_FILE"
}

# Защита от множественных запусков — атомарный mkdir (работает с async &)
log "PID=$$, lock=$LOCK_DIR"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    OLD_PID=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        log "WARN: watchdog уже запущен (PID $OLD_PID), выхожу"
        exit 0
    fi
    log "PID $OLD_PID — мёртв, перезапуск"
    rmdir "$LOCK_DIR" 2>/dev/null
    mkdir "$LOCK_DIR" || { log "ERROR: не могу создать lock"; exit 1; }
fi
echo $$ > "$LOCK_DIR/pid"
trap 'rm -rf "$LOCK_DIR"' EXIT

RESTART_LOCK=/tmp/panel-restart.lock

restart_panels() {
    local cause="$1"

    # Защита от параллельных вызовов (inotify + udev + health — все дёргают restart)
    if ! mkdir "$RESTART_LOCK" 2>/dev/null; then
        log "restart ($cause) — пропущен, уже выполняется"
        return
    fi

    # Ждём готовности PulseAudio до 10с (volumepulse плагину нужен PA)
    local pa_waited=0
    while [ "$pa_waited" -lt 10 ]; do
        if pactl info >/dev/null 2>&1; then
            break
        fi
        sleep 1
        pa_waited=$((pa_waited + 1))
    done
    if [ "$pa_waited" -ge 10 ]; then
        log "WARN: PulseAudio не ответил за 10с, запускаю панели всё равно"
    elif [ "$pa_waited" -gt 0 ]; then
        log "PA готов (ждал ${pa_waited}с)"
    fi

    local displays
    displays=$(wlr-randr 2>/dev/null | grep -E "^[A-Z]" | awk '{print $1}')

    log "===== restart ($cause) — дисплеи: $displays ====="

    # Убиваем старые панели по PID (быстрее pkill)
    for pid in $(pgrep -f "wf-panel-pi" 2>/dev/null); do
        kill "$pid" 2>/dev/null
    done
    sleep 0.3

    for disp in $displays; do
        local ini
        if [ "$disp" = "DSI-1" ]; then
            ini="$CONFIG_DIR/wfpanel-dsi.ini"
        else
            ini="/tmp/wfpanel-${disp}.ini"
            cat > "$ini" << EOF
[panel]
monitor=${disp}
position=top
height=36
widgets_left=smenu spacing0 spacing4 launchers spacing8 window-list 
widgets_right=tray power ejecter spacing2 connect spacing2 bluetooth spacing2 netman spacing2 volumepulse spacing2 clock spacing2 cputemp spacing2 batt
EOF
        fi

        if [ -f "$ini" ]; then
            /usr/bin/wf-panel-pi -c "$ini" &
            log "  → $disp ($ini)"
        fi
    done

    # Снимаем блокировку перезапуска
    rmdir "$RESTART_LOCK" 2>/dev/null
}

# === Мониторинг: inotify + udev ===
watch_displays() {
    log "=== watchdog запущен ==="

    # inotify: следим за статусными файлами DRM
    while true; do
        inotifywait -q -e modify \
            /sys/class/drm/card1-DSI-1/status \
            /sys/class/drm/card1-HDMI-A-2/status \
            /sys/class/drm/card1-HDMI-A-1/status 2>/dev/null
        sleep 0.5
        restart_panels "inotify"
    done &

    # udev: дополнительный канал
    udevadm monitor --subsystem-match=drm --property --udev 2>/dev/null | \
    while IFS= read -r line; do
        if echo "$line" | grep -qiE "(change|bind|unbind|connected|disconnected)"; then
            sleep 0.5
            restart_panels "udev"
        fi
    done &

    # Проверка здоровья панелей: если упали — перезапустить
    while true; do
        sleep 15

        # Если сейчас идёт перезапуск — пропускаем проверку
        if [ -d "$RESTART_LOCK" ]; then
            continue
        fi

        # Даём панелям 2 секунды на запуск после старта
        sleep 2

        local expected
        expected=$(wlr-randr 2>/dev/null | grep -cE "^[A-Z]")
        local running
        running=$(pgrep -f "wf-panel-pi" 2>/dev/null | wc -l)
        if [ "$running" -lt "$expected" ] && [ "$expected" -gt 0 ]; then
            log "health: панели упали ($running/$expected), перезапуск"
            restart_panels "health"
        fi
    done &

    wait
}

# === Первичный запуск ===
restart_panels "startup"

# Запускаем мониторинг
watch_displays
