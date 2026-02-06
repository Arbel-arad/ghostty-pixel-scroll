<!-- LOGO -->
<h1>
<p align="center">
  <img src="https://github.com/user-attachments/assets/fe853809-ba8b-400b-83ab-a9a0da25be8a" alt="Logo" width="128">
  <br>Ghostty
</h1>
  <p align="center">
    Fast, native, feature-rich terminal emulator pushing modern features.
    <br />
    <a href="#about">About</a>
    ·
    <a href="https://ghostty.org/download">Download</a>
    ·
    <a href="https://ghostty.org/docs">Documentation</a>
    ·
    <a href="CONTRIBUTING.md">Contributing</a>
    ·
    <a href="HACKING.md">Developing</a>
  </p>
</p>

## Ghostty Pixel Scroll Fork

A fork of [Ghostty](https://github.com/ghostty-org/ghostty) with smooth pixel-level scrolling, velocity-adaptive scroll animation, animated cursors, and an embedded Neovim GUI mode. Everything runs on Ghostty's existing GPU renderer (Metal/OpenGL) -- no external dependencies.

This is a drop-in replacement for stock Ghostty. Scroll animation is on by default. Everything else is opt-in.

### Quick Start

Add to `~/.config/ghostty/config` -- full recommended settings:

```
# Smooth pixel scrolling
pixel-scroll = true

# Animated cursor (spring-based movement)
cursor-animation-duration = 0.06

# Matte ink rendering
matte-rendering = 0.5
```

Scroll animation is already on by default (`scroll-animation-duration = 0.15`). Content arrival is velocity-adaptive -- single lines glide in, large dumps get a spring drop, streaming output auto-adapts with no page jerk.

For Neovim GUI mode, just type `nvim-gui` in the terminal -- no config needed.

---

### Terminal Mode

Terminal mode is your normal shell. These options add smooth scrolling and animation on top of stock Ghostty behavior.

#### Scrolling

| Option                        | Default | What it does                                                                                                                                                    |
| ----------------------------- | ------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pixel-scroll`                | `false` | Pixel-level mouse/trackpad scrolling. Viewport offset is rounded to whole pixels -- text stays crisp at any refresh rate (tested at 165hz), no blur or shimmer. |
| `scroll-animation-duration`   | `0.15`  | Content arrival animation duration (seconds). 0 = instant snap. Controls velocity-adaptive glide -- see below.                                                  |
| `scroll-animation-bounciness` | `0.0`   | Scroll spring bounce for large one-shot jumps (0.0 = critically damped, 1.0 = max bounce).                                                                      |

**Velocity-adaptive scroll animation:** When new output appears and the viewport is pinned to the bottom, it animates into view. The animation automatically adapts to output speed:

| Output type                             | What happens                                               |
| --------------------------------------- | ---------------------------------------------------------- |
| Single line (echo, prompt)              | ~80ms ease-out glide -- content slides in smoothly         |
| Few lines (git status)                  | ~50-80ms glide -- smooth flow                              |
| Streaming (docker logs, builds, CI)     | ~8-15ms micro-glide -- subtle conveyor belt, no earthquake |
| Large one-shot dump (ls, cat) 10+ lines | Spring drop -- satisfying physics bounce                   |

No configuration needed. The glide duration scales automatically via an exponential moving average of the output rate.

#### Cursor

| Option                        | Default | What it does                                                             |
| ----------------------------- | ------- | ------------------------------------------------------------------------ |
| `cursor-animation-duration`   | `0.0`   | Cursor move animation speed (seconds). 0 = instant. Recommended: `0.06`. |
| `cursor-animation-bounciness` | `0.0`   | Cursor spring bounce (0.0 = critically damped).                          |

The cursor animation is a spring-based system -- the cursor glides to its new position when it moves. Works in both terminal mode and Neovim GUI mode.

#### Visual

| Option            | Default | What it does                                                                                                                           |
| ----------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| `matte-rendering` | `0.0`   | Ink/matte color post-processing (0.0 = off, 1.0 = full). Slight desaturation, shadow lift, and cool-tinted shadows for a refined look. |
| `text-gamma`      | `0.0`   | Text weight adjustment. Positive = thicker, negative = thinner.                                                                        |
| `text-contrast`   | `0.0`   | Text edge sharpness. Higher = crisper glyphs.                                                                                          |

---

### Neovim GUI Mode

Type `nvim-gui` in the terminal to switch Ghostty into a native Neovim GUI on the fly. The shell function (available in zsh via Ghostty's shell integration) sends OSC 1338 which transforms the current terminal session into a full Neovim GUI renderer.

Ghostty connects to Neovim over msgpack-rpc using the multigrid UI protocol. This is a completely separate rendering path from terminal mode -- it has its own scroll system, cursor animation, and window management.

**Features:**

- True pixel-by-pixel smooth scrolling with per-window independent springs
- Scroll region awareness -- status bars, winbars, and command line stay fixed while content scrolls
- Stretchy 4-corner cursor animation (Neovide-style)
- Proper floating window rendering with clipping and z-ordering
- Sonicboom VFX ring on cursor mode changes
- All your Neovim plugins and config work normally

#### Config

| Option                 | Default                                                                       | What it does                                                        |
| ---------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `neovim-gui`           | `""` (keeps gui as command so you can have reg ghostty terminal on raw spawn) | Set to `spawn`, `embed`, or a socket path. Empty = normal terminal. |
| `neovim-corner-radius` | `0.0`                                                                         | Rounded SDF corners on Neovim windows (pixels).                     |
| `neovim-gap-color`     | `#0a0a0a`                                                                     | Color between windows (visible with rounded corners).               |

> **You don't need to set `neovim-gui` in your config.** The `nvim-gui` command works at any time, even with no config -- it switches the current terminal into GUI mode on the fly via OSC 1338. Only set `neovim-gui = spawn` if you want Ghostty to always launch as a Neovim GUI.

> **Auto-defaults:** When Neovim GUI is active and animation/corner values are at 0, Neovide-like defaults apply automatically (cursor = 0.06s, scroll = 0.2s, corners = 8px). Your explicit values always win.

Pass extra args to Neovim via `GHOSTTY_NVIM_ARGS="--clean"` environment variable.

---

### Shared Features

These work in **both** terminal mode and Neovim GUI mode:

- **Cursor animation** (`cursor-animation-duration`) -- spring-based cursor movement
- **Scroll animation** (`scroll-animation-duration`) -- velocity-adaptive in terminal, per-window springs in GUI
- **Matte rendering** (`matte-rendering`) -- ink/matte color post-processing
- **Text gamma / contrast** (`text-gamma`, `text-contrast`) -- glyph tuning

Neovim GUI mode only:

- **Sonicboom VFX** -- expanding ring effect on cursor mode changes
- **Rounded corners** (`neovim-corner-radius`) -- SDF rounded window corners

The draw timer only runs while something is actually animating. When everything settles, it stops and CPU/GPU usage drops to zero.

### How It Actually Works

This isn't a fake smooth scroll where you slap a CSS transition on a div. The terminal grid is actually moving pixel by pixel.

**Terminal pixel scrolling:** Normal terminals scroll by jumping whole lines -- you flick your trackpad and the text teleports one or more rows. This fork tracks your scroll input as raw pixel deltas and maintains a sub-line offset. The renderer always loads one extra row from the scrollback buffer above what's visible. As you scroll, that offset shifts the entire grid up or down by actual pixels. When the offset crosses a full cell height, the viewport advances one line in the scrollback and the offset wraps back. The result is every frame shows the grid at a real intermediate position between lines -- not interpolated, not faked, just shifted.

On the GPU side, both the background fragment shader and the text vertex shader receive the same `pixel_scroll_offset_y` uniform. The offset is rounded to whole pixels so text glyphs stay on integer boundaries (glyph atlases are rasterized at integer positions, so sub-pixel offsets cause blur). At 165hz with ~20px tall cells you get about 20 distinct positions per line of scroll -- looks completely smooth, no shimmer.

**Content arrival animation:** When new output pushes the viewport down (like running a command), the renderer doesn't just snap to the new position. It records how many lines jumped, picks an animation style (ease-out glide for small output, spring for big dumps), and interpolates the offset from "old position" to "new position" over a few frames. The velocity-adaptive part just adjusts how long that interpolation takes based on how fast output is coming in -- fast streaming gets a near-instant glide so the page doesn't bounce around.

**Neovim GUI scrolling:** Completely different system. Neovim sends scroll region info over the UI protocol. Each window gets its own spring animation. The shader applies per-cell Y offsets only to cells inside the scroll region, so your statusline and winbar don't move. Floating windows have their own z-order and clipping. It's basically what Neovide does, but running inside Ghostty's renderer instead of a separate app.

**Low idle cost:** The animation timer only ticks while something is moving. Once all springs and glides settle, the timer stops. Ghostty goes back to pure event-driven rendering with normalish CPU/GPU overhead.

### Linux Refresh Rate

On macOS, the animation timer auto-detects your display refresh rate via CVDisplayLink. On Linux there's no equivalent, so the timer defaults to **~165hz** (hardcoded in `src/renderer/generic.zig` as `display_refresh_ns`). There's no config option for this yet. (Not tested but prolly will work.)

**If you're on a 60hz monitor:** Animation duration and timing are correct -- a 0.15s glide takes 0.15s regardless of refresh rate. But pixel scrolling will be less smooth because you have fewer frames to show the movement (~7 frames per cell at 60hz vs ~19 at 165hz). Still way smoother than stock Ghostty's line-jumping, just not as buttery. The timer also ticks more often than your display refreshes, which wastes a few CPU cycles. If this bothers you, change `display_refresh_ns` in the source to match your monitor (e.g. `16_666_666` for 60hz, `6_944_444` for 144hz).

### Platform Support

Currently tested on **Linux (OpenGL)**. The Metal shader changes (macOS) have not been tested yet -- they mirror the OpenGL implementation but may have issues. If you're on macOS and run into problems, please open an issue.

### Known Issues / TODO

- [ ] **Pasting in Neovim GUI mode** -- paste doesn't work correctly in nvim-gui
- [ ] **Cursor scroll direction in Neovim GUI** -- mouse scroll direction is inverted (natural scrolling goes the wrong way)
- [ ] **Linux emoji/unicode rendering** -- characters like `✅ 📡 🚀` don't render correctly (works fine in stock Ghostty)
- [ ] **Linux vsync** -- animation timer is hardcoded to ~165hz. Works fine on any refresh rate (timing is wall-clock based) but wastes cycles on lower-hz displays. No config option yet -- needs auto-detection or a config field
- [ ] **macOS Metal shaders** -- untested, may have issues since all development has been on Linux/OpenGL

Contributions welcome -- if you fix something or make it cooler, open a PR.

### Extras

The Pokemon terminal splash seen in the demo video is [pokemon-colorscripts](https://gitlab.com/phoneybadger/pokemon-colorscripts).

### Building

**With Nix (easiest):**

```bash
cd ghostty-pixel-scroll
nix-shell --run "zig build -Doptimize=ReleaseFast"
```

**Without Nix:**

You need Zig 0.15+ and the same dependencies as stock Ghostty (GTK4, libadwaita, etc). See Ghostty's [build from source docs](https://ghostty.org/docs/install/build) for your distro's package list, then:

```bash
cd ghostty-pixel-scroll
zig build -Doptimize=ReleaseFast
```

Binary lands in `zig-out/bin/ghostty`. Run it directly or point your WM/DE at it:

```bash
# Hyprland
bind = SUPER, Return, exec, /path/to/ghostty-pixel-scroll/zig-out/bin/ghostty

# Sway
bindsym $mod+Return exec /path/to/ghostty-pixel-scroll/zig-out/bin/ghostty

# Or just run it
./zig-out/bin/ghostty
```

---

## About

Ghostty is a terminal emulator that differentiates itself by being
fast, feature-rich, and native. While there are many excellent terminal
emulators available, they all force you to choose between speed,
features, or native UIs. Ghostty provides all three.

In all categories, I am not trying to claim that Ghostty is the
best (i.e. the fastest, most feature-rich, or most native). But
Ghostty is competitive in all three categories and Ghostty
doesn't make you choose between them.

Ghostty also intends to push the boundaries of what is possible with a
terminal emulator by exposing modern, opt-in features that enable CLI tool
developers to build more feature rich, interactive applications.

While aiming for this ambitious goal, our first step is to make Ghostty
one of the best fully standards compliant terminal emulator, remaining
compatible with all existing shells and software while supporting all of
the latest terminal innovations in the ecosystem. You can use Ghostty
as a drop-in replacement for your existing terminal emulator.

For more details, see [About Ghostty](https://ghostty.org/docs/about).

## Download

See the [download page](https://ghostty.org/download) on the Ghostty website.

## Documentation

See the [documentation](https://ghostty.org/docs) on the Ghostty website.

## Contributing and Developing

If you have any ideas, issues, etc. regarding Ghostty, or would like to
contribute to Ghostty through pull requests, please check out our
["Contributing to Ghostty"](CONTRIBUTING.md) document. Those who would like
to get involved with Ghostty's development as well should also read the
["Developing Ghostty"](HACKING.md) document for more technical details.

## Roadmap and Status

The high-level ambitious plan for the project, in order:

|  #  | Step                                                      | Status |
| :-: | --------------------------------------------------------- | :----: |
|  1  | Standards-compliant terminal emulation                    |   ✅   |
|  2  | Competitive performance                                   |   ✅   |
|  3  | Basic customizability -- fonts, bg colors, etc.           |   ✅   |
|  4  | Richer windowing features -- multi-window, tabbing, panes |   ✅   |
|  5  | Native Platform Experiences (i.e. Mac Preference Panel)   |   ⚠️   |
|  6  | Cross-platform `libghostty` for Embeddable Terminals      |   ⚠️   |
|  7  | Windows Terminals (including PowerShell, Cmd, WSL)        |   ❌   |
|  N  | Fancy features (to be expanded upon later)                |   ❌   |

Additional details for each step in the big roadmap below:

#### Standards-Compliant Terminal Emulation

Ghostty implements enough control sequences to be used by hundreds of
testers daily for over the past year. Further, we've done a
[comprehensive xterm audit](https://github.com/ghostty-org/ghostty/issues/632)
comparing Ghostty's behavior to xterm and building a set of conformance
test cases.

We believe Ghostty is one of the most compliant terminal emulators available.

Terminal behavior is partially a de jure standard
(i.e. [ECMA-48](https://ecma-international.org/publications-and-standards/standards/ecma-48/))
but mostly a de facto standard as defined by popular terminal emulators
worldwide. Ghostty takes the approach that our behavior is defined by
(1) standards, if available, (2) xterm, if the feature exists, (3)
other popular terminals, in that order. This defines what the Ghostty project
views as a "standard."

#### Competitive Performance

We need better benchmarks to continuously verify this, but Ghostty is
generally in the same performance category as the other highest performing
terminal emulators.

For rendering, we have a multi-renderer architecture that uses OpenGL on
Linux and Metal on macOS. As far as I'm aware, we're the only terminal
emulator other than iTerm that uses Metal directly. And we're the only
terminal emulator that has a Metal renderer that supports ligatures (iTerm
uses a CPU renderer if ligatures are enabled). We can maintain around 60fps
under heavy load and much more generally -- though the terminal is
usually rendering much lower due to little screen changes.

For IO, we have a dedicated IO thread that maintains very little jitter
under heavy IO load (i.e. `cat <big file>.txt`). On benchmarks for IO,
we're usually within a small margin of other fast terminal emulators.
For example, reading a dump of plain text is 4x faster compared to iTerm and
Kitty, and 2x faster than Terminal.app. Alacritty is very fast but we're still
around the same speed (give or take) and our app experience is much more
feature rich.

> [!NOTE]
> Despite being _very fast_, there is a lot of room for improvement here.

#### Richer Windowing Features

The Mac and Linux (build with GTK) apps support multi-window, tabbing, and
splits.

#### Native Platform Experiences

Ghostty is a cross-platform terminal emulator but we don't aim for a
least-common-denominator experience. There is a large, shared core written
in Zig but we do a lot of platform-native things:

- The macOS app is a true SwiftUI-based application with all the things you
  would expect such as real windowing, menu bars, a settings GUI, etc.
- macOS uses a true Metal renderer with CoreText for font discovery.
- The Linux app is built with GTK.

There are more improvements to be made. The macOS settings window is still
a work-in-progress. Similar improvements will follow with Linux.

#### Cross-platform `libghostty` for Embeddable Terminals

In addition to being a standalone terminal emulator, Ghostty is a
C-compatible library for embedding a fast, feature-rich terminal emulator
in any 3rd party project. This library is called `libghostty`.

Due to the scope of this project, we're breaking libghostty down into
separate actually libraries, starting with `libghostty-vt`. The goal of
this project is to focus on parsing terminal sequences and maintaining
terminal state. This is covered in more detail in this
[blog post](https://mitchellh.com/writing/libghostty-is-coming).

`libghostty-vt` is already available and usable today for Zig and C and
is compatible for macOS, Linux, Windows, and WebAssembly. At the time of
writing this, the API isn't stable yet and we haven't tagged an official
release, but the core logic is well proven (since Ghostty uses it) and
we're working hard on it now.

The ultimate goal is not hypothetical! The macOS app is a `libghostty` consumer.
The macOS app is a native Swift app developed in Xcode and `main()` is
within Swift. The Swift app links to `libghostty` and uses the C API to
render terminals.

## Crash Reports

Ghostty has a built-in crash reporter that will generate and save crash
reports to disk. The crash reports are saved to the `$XDG_STATE_HOME/ghostty/crash`
directory. If `$XDG_STATE_HOME` is not set, the default is `~/.local/state`.
**Crash reports are _not_ automatically sent anywhere off your machine.**

Crash reports are only generated the next time Ghostty is started after a
crash. If Ghostty crashes and you want to generate a crash report, you must
restart Ghostty at least once. You should see a message in the log that a
crash report was generated.

> [!NOTE]
>
> Use the `ghostty +crash-report` CLI command to get a list of available crash
> reports. A future version of Ghostty will make the contents of the crash
> reports more easily viewable through the CLI and GUI.

Crash reports end in the `.ghosttycrash` extension. The crash reports are in
[Sentry envelope format](https://develop.sentry.dev/sdk/envelopes/). You can
upload these to your own Sentry account to view their contents, but the format
is also publicly documented so any other available tools can also be used.
The `ghostty +crash-report` CLI command can be used to list any crash reports.
A future version of Ghostty will show you the contents of the crash report
directly in the terminal.

To send the crash report to the Ghostty project, you can use the following
CLI command using the [Sentry CLI](https://docs.sentry.io/cli/installation/):

```shell-session
SENTRY_DSN=https://e914ee84fd895c4fe324afa3e53dac76@o4507352570920960.ingest.us.sentry.io/4507850923638784 sentry-cli send-envelope --raw <path to ghostty crash>
```

> [!WARNING]
>
> The crash report can contain sensitive information. The report doesn't
> purposely contain sensitive information, but it does contain the full
> stack memory of each thread at the time of the crash. This information
> is used to rebuild the stack trace but can also contain sensitive data
> depending on when the crash occurred.
