# Arpoon for macOS

Arpoon is a native macOS utility designed for dynamically binding live applications or specific windows to shortcuts, allowing you to jump back to them instantly. 

Inspired by [ThePrimeagen's Harpoon](https://github.com/ThePrimeagen/harpoon) for text editors, this tool adapts the philosophy of "fast recall for a small working set" to the macOS desktop environment. It's essentially Arpoon, but for your macOS apps and windows.

## What It Is

Arpoon is a focus-and-recall tool optimized for speed and minimal mental overhead. 

- **Quickly bind** a specific running app or window to a shortcut.
- **Instantly focus** it again with a single keystroke.
- **Treat windows as working targets**, rather than clutter to be managed.
- **Standalone macOS utility**, operating independently and natively.
- **Optimized for focus and z-index**, prioritizing bringing the right window to the front over rearranging your screen.

## What It Is Not

Arpoon is **not** a full window manager.

- Not a tiling manager (like Amethyst or Yabai).
- Not an auto-layout engine.
- Not a workspace/virtual desktop system.
- Not a tool to prevent overlapping windows.

Window overlap is expected and acceptable. The primary goal is getting the exact window or app you need to the front as quickly and predictably as possible.

## Features & Default Shortcuts

Arpoon supports two primary routing schemes: **Static Slots** and **Dynamic Windows**, along with directional focus.

### 1. Static Slots (Default)
Bind a specific window to a numbered slot and recall it instantly.

- **Bind to Slot 1-9:** `Cmd + Shift + 1-9`
- **Jump to Slot 1-9:** `Cmd + 1-9`

### 2. Dynamic Hotkeys
Assign on-the-fly hotkeys to specific targets without relying on predefined slots.

- **Add Dynamic Hotkey:** `Cmd + Shift + 0`

### 3. Directional Focus
Quickly jump between visible applications on your screen based on their spatial arrangement.

- **Focus App Left:** `Cmd + Option + Left Arrow`
- **Focus App Right:** `Cmd + Option + Right Arrow`
- **Focus App Up:** `Cmd + Option + Up Arrow`
- **Focus App Down:** `Cmd + Option + Down Arrow`

### 4. HUD (Heads-Up Display)
View your current bindings and active working set at a glance.

- **Show HUD:** `Cmd + 0`
- *(Optional)* Show HUD by holding the `Option` key (configurable in settings).

## Development

Build and install the development version of the app using the provided script:

```bash
./scripts/install-dev.sh
```

This script will build `Arpoon.app`, install it directly into `/Applications/Arpoon.app`, and automatically launch it.
