# LÖVE 2D Hello World

This repository is a minimal LÖVE 2D project that opens an 800×600 window and draws a centered 600×400 outlined box containing the message “Hello World”.

## Run the project

```bash
love .
```

If LÖVE is not on your `PATH`, replace `love` with the absolute path to the LÖVE executable.

## Debug the project

- Launch with a console so `print` statements appear:

  ```bash
  love --console .
  ```

- Hot reload code (LÖVE automatically reloads changed `main.lua` on restart). Keep a terminal open and press `Cmd+R` in the LÖVE window to restart the game after edits.

- Use `love.window.setTitle` (in `main.lua`) to show build metadata while iterating.

## LÖVE 2D at a glance

- **Engine basics:** LÖVE (aka Love2D) is a Lua framework for 2D games. Every project typically defines `love.load`, `love.update`, and `love.draw` callbacks in `main.lua`.
- **Project layout:** A `main.lua` file is mandatory; optional files like `conf.lua` customize the window and system behavior before the game starts.
- **Coordinates:** The default coordinate system starts at the top-left corner of the window (0,0), with `x` increasing to the right and `y` increasing downward.
- **Assets:** Put images, audio, and fonts alongside your Lua scripts and load them with `love.graphics.newImage`, `love.audio.newSource`, etc.
- **Packaging:** Distribute games either as a folder (requiring LÖVE installed) or by zipping the contents and renaming to `.love`; combine with platform-specific executables for stand-alone releases.
