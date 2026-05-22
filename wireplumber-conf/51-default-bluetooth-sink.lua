-- Set Bluetooth headphones as default audio sink
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
