-- ClockworkPi uConsole input tuning.
--
-- The Super key remap lives OUTSIDE Hyprland, in /etc/keyd/default.conf, so it
-- applies system wide (console included) rather than only in this compositor.
-- Left Alt is delivered to Hyprland as Super, so every Omarchy SUPER binding
-- works by pressing Left Alt. Do not also set altwin:* here; it would cancel it.

hl.config({
  input = {
    -- Small keyboard, keys close together: calm the repeat rate down.
    repeat_rate = 35,
    repeat_delay = 300,
  },
})
