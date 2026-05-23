# Pi4 Audio Volume Fix

Решение проблемы с регулировкой громкости на Raspberry Pi 4 (Wayland, labwc, PipeWire, Bluetooth-наушники).

## Проблема

Ползунок громкости (виджет `volume` в `wf-panel-pi`) не менял громкость — двигался, а звук оставался на месте.

## Причина

На Pi4 было несколько аудиоустройств:

```bash
$ pactl list short sinks
0  alsa_output.platform-fe00b840.mailbox.stereo-fallback  PipeWire  SUSPENDED
1  bluez_output.18_B9_6E_02_E1_09.1                      PipeWire  RUNNING    # Bluetooth (Haylou-T15)
2  alsa_output.platform-fef00700.hdmi.stereo-fallback     PipeWire  SUSPENDED
```

Default sink — Bluetooth, а пользователь слушал через HDMI. `volume` честно менял громкость Bluetooth, а она ни на что не влияла.

**Диагностика:**
```bash
pactl get-default-sink
# → bluez_output.18_B9_6E_02_E1_09.1
```

## Фикс

### Default sink на Bluetooth (WirePlumber)

WirePlumber-конфиг, который задаёт Bluetooth-выходам приоритет выше остальных:

```lua
-- ~/.config/wireplumber/main.lua.d/51-default-bluetooth-sink.lua
rule = {
  matches = {
    { { "node.name", "matches", "bluez_output.*" } },
  },
  apply_properties = {
    ["priority.session"] = 3000,
  },
}
table.insert(alsa_monitor.rules, rule)
```

### Runtime (проверка)
```bash
pactl set-default-sink bluez_output.18_B9_6E_02_E1_09.1
```

### Горячие клавиши громкости

В конфиге labwc (`~/.config/labwc/rc.xml`) прописаны хоткеи, которые работают через `pactl` с `@DEFAULT_SINK@`:

| Клавиша | Действие |
|---------|----------|
| `Shift+F5` | Громче (+5%) |
| `Shift+F4` | Тише (-5%) |
| `Shift+F3` | Mute |
| `XF86AudioRaiseVolume` | Громче (+5%) |
| `XF86AudioLowerVolume` | Тише (-5%) |
| `XF86AudioMute` | Mute |

Исходник: `configs/labwc/rc.xml` (в репозитории `pi-dual-display`).

### Combine-sink для программной регулировки (если BT не поддерживает аппаратную)

Некоторые BT-наушники не имеют аппаратной регулировки громкости. В этом случае помогает `module-combine-sink`:

```bash
pactl load-module module-combine-sink sink_name=bt-combine slaves=$(pactl get-default-sink)
pactl set-default-sink bt-combine
```

**Автоматизация** — systemd path-unit и скрипты в этом репозитории:

```bash
# Установка
cp scripts/bt-combine.sh ~/.local/bin/
cp scripts/bt-panel-restart.sh ~/.local/bin/
chmod +x ~/.local/bin/bt-combine.sh ~/.local/bin/bt-panel-restart.sh

cp systemd/bt-audio.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now bt-audio.path
```

**Как работает:**
1. `bt-combine.sh` создаёт combined-sink при подключении BT-аудио и создаёт файл `/tmp/bt-sink-trigger`
2. `bt-audio.path` (systemd path-unit) отслеживает изменения этого файла
3. `bt-audio.service` запускает `bt-panel-restart.sh`, который перезапускает панели для обновления списка аудиовыходов

### Временный (если ползунок снова мёртвый)

Перезапуск панели восстанавливает связь `volume` с PipeWire:

```bash
kill -HUP $(pgrep -f "wf-panel-pi")
# или
pkill -f "wf-panel-pi"
# watchdog перезапустит автоматически
```

## Команды для терминала

```bash
# Громкость
pactl set-sink-volume @DEFAULT_SINK@ +5%
pactl set-sink-volume @DEFAULT_SINK@ -5%

# Mute
pactl set-sink-mute @DEFAULT_SINK@ toggle

# Информация
pactl get-default-sink
pactl list sinks short
pactl get-sink-volume @DEFAULT_SINK@
```

## Сопутствующая проблема: панели перезапускались каждые 30-60 сек

### Причина

`volume` дёргал PulseAudio → HDMI-аудио генерировала DRM property change → `udevadm monitor` ловил слово "change" → `panel-watchdog.sh` убивал и перезапускал панели → новый `volume` снова триггерил цикл.

### Фиксы в panel-watchdog.sh

**1. Дебаунс 10 секунд, 2. RESTART_LOCK, 3. mkdir-блокировка, 4. Удалён `updater` из виджетов панели**

Подробнее в `watchdog/panel-watchdog.sh`.

## Ещё одна причина падений панелей (исправлена)

`bt-volume-check.timer` (системный таймер) срабатывал каждые 30 секунд и вызывал `bt-panel-restart.sh`, который делал `killall wf-panel-pi`, убивая все панели. **Заменён на systemd path-unit** (см. выше), который срабатывает только при реальном подключении Bluetooth.

## Файлы в репозитории

```
scripts/
├── bt-combine.sh           # Создание combine-sink при BT + триггер
└── bt-panel-restart.sh     # Перезапуск панелей при BT

systemd/
├── bt-audio.path           # Path-unit для BT-триггера
└── bt-audio.service        # Oneshot-сервис перезапуска панелей

watchdog/
└── panel-watchdog.sh       # Watchdog панелей с дебаунсом

wireplumber-conf/
└── 51-default-bluetooth-sink.lua  # Приоритет BT-выхода

configs/labwc/rc.xml        # Хоткеи громкости (в pi-dual-display)
```

## Установка всего комплекта

```bash
# 1. WirePlumber (default BT sink)
mkdir -p ~/.config/wireplumber/main.lua.d
cp wireplumber-conf/51-default-bluetooth-sink.lua ~/.config/wireplumber/main.lua.d/

# 2. BT audio path-unit
cp scripts/bt-combine.sh ~/.local/bin/
cp scripts/bt-panel-restart.sh ~/.local/bin/
chmod +x ~/.local/bin/bt-combine.sh ~/.local/bin/bt-panel-restart.sh
cp systemd/bt-audio.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now bt-audio.path

# 3. Watchdog панелей (опционально)
cp watchdog/panel-watchdog.sh ~/.local/bin/
chmod +x ~/.local/bin/panel-watchdog.sh
```

## Стек

- Raspberry Pi 4 (8GB), Debian 13 (trixie)
- Wayland (labwc), wf-panel-pi
- PipeWire + WirePlumber
- PulseAudio-совместимость через PipeWire
- Bluetooth-наушники Haylou-T15

## Ссылки

- Репозиторий pi-dual-display: https://github.com/Haidegger22/pi-dual-display
- WirePlumber docs: https://pipewire.pages.freedesktop.org/wireplumber/
