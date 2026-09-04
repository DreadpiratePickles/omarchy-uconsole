-- ClockworkPi uConsole CM4.
-- The 5" DSI panel is natively 720x1280 (portrait) but physically mounted
-- landscape, so the output needs a rotation transform. transform 3 = 270 deg.
-- If the image comes up upside down, change this to 1 (90 deg).
hl.monitor({
  output = "DSI-1",
  mode = "720x1280@60",
  position = "0x0",
  scale = 1,
  transform = 3,
})

-- Panel is small; keep XWayland apps unscaled.
hl.env("GDK_SCALE", "1")
