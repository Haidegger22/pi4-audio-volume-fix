# Pi4 Audio Volume Fix

Управление громкостью Bluetooth-наушников на Raspberry Pi 4 (Wayland, labwc, PipeWire).

## Проблема

Ползунок громкости в панели wf-panel-pi не регулирует звук на Bluetooth-наушниках, либо дефолтный аудиовыход не совпадает с ожидаемым.

## Состав

### 1. Default sink на Bluetooth (WirePlumber)

Приоритет Bluetooth-выхода выше остальных:

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

```bash
cp wireplumber-conf/51-default-bluetooth-sink.lua ~/.config/wireplumber/main.lua.d/
```

### 2. Горячие клавиши (labwc)

Работают с текущим default sink через `@DEFAULT_SINK@`:

| Клавиша | Действие |
|---------|----------|
| `Shift+F5` | Громче (+5%) |
| `Shift+F4` | Тише (-5%) |
| `Shift+F3` | Mute |

Конфиг: `configs/labwc/rc.xml` (в [pi-dual-display](https://github.com/Haidegger22/pi-dual-display))

### 3. Combine-sink для программной регулировки

Если BT-наушники не поддерживают аппаратную регулировку громкости:

```bash
pactl load-module module-combine-sink \
  sink_name=bt-combine \
  slaves=$(pactl get-default-sink)
pactl set-default-sink bt-combine
```

**Автоматизация** — systemd path-unit:

```bash
cp scripts/bt-combine.sh ~/.local/bin/
cp scripts/bt-panel-restart.sh ~/.local/bin/
chmod +x ~/.local/bin/bt-combine.sh ~/.local/bin/bt-panel-restart.sh

cp systemd/bt-audio.* ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now bt-audio.path
```

Схема работы:
1. `bt-combine.sh` создаёт combined-sink при подключении BT и touch'ает `/tmp/bt-sink-trigger`
2. `bt-audio.path` ловит изменение файла → `bt-audio.service`
3. `bt-panel-restart.sh` перезапускает панели (обновление списка аудиовыходов)

### 4. Команды для терминала

```bash
# Громкость +/- 5%
pactl set-sink-volume @DEFAULT_SINK@ +5%
pactl set-sink-volume @DEFAULT_SINK@ -5%

# Mute
pactl set-sink-mute @DEFAULT_SINK@ toggle

# Информация
pactl get-default-sink
pactl list sinks short
pactl get-sink-volume @DEFAULT_SINK@
```

## Быстрая диагностика

```bash
# Какой sink сейчас дефолтный
pactl get-default-sink

# Список всех аудиовыходов
pactl list sinks short

# Громкость в процентах
pactl get-sink-volume @DEFAULT_SINK@
```

## Файлы репозитория

```
scripts/
├── bt-combine.sh           # combine-sink + триггер
└── bt-panel-restart.sh     # перезапуск панелей

systemd/
├── bt-audio.path           # path-unit
└── bt-audio.service        # сервис

wireplumber-conf/
└── 51-default-bluetooth-sink.lua  # приоритет BT
```

## Стек

- Raspberry Pi 4, Debian 13 (trixie)
- Wayland (labwc), wf-panel-pi
- PipeWire + WirePlumber
