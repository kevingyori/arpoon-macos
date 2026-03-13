# Arpoon for macOS

Built in an evening and a morning with Codex after watching [Theo talk about his own window manager setup](https://www.youtube.com/watch?v=EUE8N6mqtGg) and realizing I didn’t actually want a window manager.

I’d already done the usual tour: Amethyst, yabai, AeroSpace, and i3 on Linux. They’re all good tools. But after enough time with them, I had to admit something obvious: I never really took advantage of the tiling part.

I didn’t want automatic layouts. I didn’t care about packing every window into a neat grid. I didn’t need workspaces to model my life.

What I wanted was much simpler:

* bind a key to the thing I’m using right now
* jump back to it instantly
* keep a small working set of apps and windows close at hand
* optimize for **focus**, not layout

That’s basically [ThePrimeagen's Harpoon](https://github.com/ThePrimeagen/harpoon), but for macOS apps and windows.

## What it is

Arpoon is a small native macOS utility for binding live apps or windows to shortcuts so you can jump back to them instantly.

<img src="images/Screenshot_1.png" height="400" alt="Menu bar popup">

You can use it to:

* bind a running app or specific window to a shortcut
* jump back to it with one keystroke
* keep a compact working set of live targets
* treat windows as things you return to, not things you constantly rearrange

It works with normal macOS windowing. It does not try to replace your desktop with a new philosophy.

## Why

A lot of window managers assume the main problem is arranging windows.

For me, it wasn’t.

My problem was usually: **I have a few things I care about right now. How do I get back to them instantly without thinking?**

I don’t mind overlapping windows. I don’t mind floating windows. I don’t need my desktop to look like a perfect demo screenshot.

What I care about is:

* bringing the right thing to the front
* doing it fast
* not having to mentally track where it lives

## What it is not

Arpoon is **not** a full window manager.

It is not:

* a tiling manager like Amethyst, yabai, or AeroSpace
* an auto-layout engine
* a workspace or virtual desktop system
* a tool for preventing overlap
* a system for micromanaging window geometry

If you want perfect tiling, this is the wrong tool.

If you want **this window is mine, and I want it on a key**, this is the right tool.

## Features

### Dynamic hotkeys

Assign hotkeys to specific targets on the fly.

* **Add dynamic hotkey:** `Alt + A`

### Static slots

Bind a specific window to a numbered slot and jump back to it instantly.

* **Bind to slot 1–9:** `Cmd + Shift + 1–9`
* **Jump to slot 1–9:** `Cmd + 1–9`

### Directional focus

I included this because I didn’t want a second app for something this simple.

Jump between visible applications based on where they are on screen.

* **Focus app left:** `Alt + H`
* **Focus app right:** `Alt + L`
* **Focus app up:** `Alt + K`
* **Focus app down:** `Alt + J`

## Install

Arpoon is currently distributed unsigned and not notarized.

### Download the app

Download `Arpoon-macOS.zip` from the latest GitHub Release, then unzip it.

On first launch, macOS will likely warn that it cannot verify the app. To open it:

1. Right-click `Arpoon.app` and choose **Open**
2. Click **Open** again in the system prompt
3. If macOS still blocks it, go to **System Settings -> Privacy & Security** and allow it there

This is a rougher install flow than a signed app, but the app should run normally once opened.

### Build locally

For local development:

```bash
./scripts/install-dev.sh
```

This will:

* build a `Debug` version of `Arpoon.app`
* install it to `/Applications/Arpoon.app`
* launch it automatically

To create the distributable `Release` ZIP for GitHub Releases:

```bash
./scripts/package-release.sh
```

This builds a `Release` app bundle and packages `Arpoon-macOS.zip` with `ditto`.

## Roadmap
