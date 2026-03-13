# Harpoon

Harpoon is a native macOS utility for dynamically binding live apps or windows to shortcuts and jumping back to them instantly.

The product direction is explicitly inspired by [ThePrimeagen's Harpoon](https://github.com/ThePrimeagen/harpoon): fast recall for a small working set, adapted here from editor buffers into macOS apps and windows.

I realized this is just Harpoon for apps.

## What It Is

Harpoon is a focus-and-recall tool for macOS.

- Quickly bind a key to a specific running app or window.
- Press that bound key with the super key to focus it again.
- Treat windows as working targets, not clutter.
- Operate as a standalone macOS utility, not something embedded inside another app.
- Optimize for focus and z-index, not layout.

## What It Is Not

Harpoon is not trying to be a full window manager.

- Not a tiling manager.
- Not an auto-layout engine.
- Not a workspace system.
- Not a tool that tries to prevent overlapping windows.
- Not a product where screen geometry is the main abstraction.

Window overlap is acceptable here. What matters is getting the right thing to the front quickly and predictably.

## Shape Of The Product

The intended experience is closer to a small Rectangle-like utility in delivery, but for focus routing instead of resizing.

- Bind the current app or window to a shortcut.
- Jump back to it immediately.
- Avoid ceremony.
- Keep the mental model small.

## Possible Extensions

These are intentionally secondary to the core bind-and-focus flow.

- Deep binds for app-specific targets like browser tabs.

## Development

Build and install the app with:

```bash
./scripts/install-dev.sh
```

That builds `Harpoon.app`, installs it to `/Applications/Harpoon.app`, and opens it.
