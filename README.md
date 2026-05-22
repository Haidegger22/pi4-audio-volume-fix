# Pi4 Audio Volume Fix

Решение проблемы с ползунком громкости на Raspberry Pi 4 (Wayland, labwc, PipeWire, Bluetooth-наушники).

## Проблема

Ползунок громкости (виджет `volumepulse` в `wf-panel-pi`) не менял громкость — двигался, а звук оставался на месте.

## Причина

На Pi4 было несколько аудиоустройств:

```bash
$ pactl list short sinks
0  alsa_output.platform-fe00b840.mailbox.stereo-fallback  PipeWire  SUSPENDED
1  bluez_output.18_B9_6E_02_E1_09.1                      PipeWire  RUNNING    # Bluetooth (Haylou-T15)
2  alsa_output.platform-fef00700.hdmi.stereo-fallback     PipeWire  SUSPENDED
```

Default sink — Bluetooth, а пользователь слушал через HDMI. `volumepulse` честно менял громкость Bluetooth, а она ни на что не влияла.

**Диагностика:**
```bash
pactl get-default-sink
# → bluez_output.18_B9_6E_02_E1_09.1
```

## Фикс

### Runtime (проверка)
```bash
pactl set-default-sink bluez_output.18_B9_6E_02_E1_09.1
```

### Персистентно (через перезагрузки)

WirePlumber-конфиг, который задаёт Bluetooth-выходам приоритет выше остальных:

```lua
-- Файл: ~/.config/wireplumber/main.lua.d/51-default-bluetooth-sink.lua
rule = {
  matches = {
    {
      { "node.name", "matches", "bluez_output.*" },
    },
  },
  apply_properties = {
    ["priority.session"] = 3000,
  },
}
table.insert(alsa_monitor.rules, rule)
```

WirePlumber при старте сканирует устройства. Bluetooth получает `priority.session = 3000` (выше стандартных 1000–2000) → PipeWire делает его default sink'ом.

### Временный (если ползунок снова мёртвый)

Перезапуск панели восстанавливает связь `volumepulse` с PipeWire:

```bash
kill -HUP $(pgrep -f "wf-panel-pi")
# или
pkill -f "wf-panel-pi"
# watchdog перезапустит автоматически
```

## Сопутствующая проблема: панели перезапускались каждые 30-60 сек

### Причина

`volumepulse` дёргал PulseAudio → HDMI-аудио генерировала DRM property change → `udevadm monitor` ловил слово "change" → `panel-watchdog.sh` убивал и перезапускал панели → новый `volumepulse` снова триггерил цикл.

### Фиксы в panel-watchdog.sh

**1. Дебаунс 10 секунд:**
```bash
# Глобальная переменная
LAST_RESTART=0

# В начало restart_panels()
local now=$(date +%s)
if [ $((now - LAST_RESTART)) -lt 10 ]; then
    log "restart ($cause) — пропущен, интервал < 10с"
    return
fi
LAST_RESTART=$now
```

**2. RESTART_LOCK — защита от параллельных вызовов:**
```bash
RESTART_LOCK=/tmp/panel-restart.lock
if ! mkdir "$RESTART_LOCK" 2>/dev/null; then
    log "restart ($cause) — пропущен, уже выполняется"
    return
fi
# ... restart logic ...
rmdir "$RESTART_LOCK"
```

**3. mkdir-блокировка от дубликатов watchdog:**
```bash
LOCK_DIR=/tmp/panel-watchdog.lock
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    OLD_PID=$(cat "$LOCK_DIR/pid")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        log "WARN: watchdog уже запущен (PID $OLD_PID)"
        exit 0
    fi
    rmdir "$LOCK_DIR"
    mkdir "$LOCK_DIR"
fi
echo $$ > "$LOCK_DIR/pid"
```

**4. Удалён `updater` из виджетов панели** — он крашил `wf-panel-pi` после проверки обновлений.

## Используемые файлы

| Файл | Назначение |
|------|-----------|
| `~/.config/wireplumber/main.lua.d/51-default-bluetooth-sink.lua` | Фиксация default sink на BT |
| `~/.local/bin/panel-watchdog.sh` | Watchdog панелей с дебаунсом |
| `~/.local/bin/panel-watchdog.sh.bak` | Оригинал watchdog до фиксов |

## Стек

- Raspberry Pi 4 (8GB), Debian 13 (trixie)
- Wayland (labwc), wf-panel-pi
- PipeWire 1.4.2 + WirePlumber
- PulseAudio-совместимость через PipeWire
- Bluetooth-наушники Haylou-T15

## Ссылки

- Репозиторий pi-dual-display: https://github.com/Haidegger22/pi-dual-display
- WirePlumber docs: https://pipewire.pages.freedesktop.org/wireplumber/
