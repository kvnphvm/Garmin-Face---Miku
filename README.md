# Garmin-Face---Miku
# Miku Face

A watch face for the fēnix 8 Solar 47mm showing time, date, steps, temperature,
weather, sunrise/sunset, battery, and a pixel-art Miku who animates when you
look at the watch.

![the face running in the simulator](preview.png)

## Prerequisites

- **Java 21** — the Connect IQ toolchain runs on the JVM.
  `brew install openjdk@21`
- **Connect IQ SDK 9.x** and the **fenix8solar47mm** device profile, both
  installed through the SDK Manager (`brew install --cask connectiq-sdk-manager`).
  The profile is not bundled with the SDK; you have to sign in with a Garmin
  account and download it from the Devices tab.
- **A developer key** at `../developer_key.der` (i.e. next to this project, in
  `Garmin Face/`). Every build is signed with it, and the watch rejects
  unsigned apps:

  ```bash
  openssl genrsa -out /tmp/key.pem 4096
  openssl pkcs8 -topk8 -inform PEM -outform DER -in /tmp/key.pem \
      -out ../developer_key.der -nocrypt
  rm /tmp/key.pem
  ```

Install the SDK through the SDK Manager, not `brew install --cask connectiq`.
The cask relocates `ConnectIQ.app` into `/Applications`, and the simulator
resolves several of its own files relative to the app bundle — once moved it
fails at startup complaining it cannot open `/Applications/Version.txt`.

## Build and run

```bash
tools/build.sh
```

Compiles a debug build, starts the simulator if it isn't already running, and
loads the face. The command then stays attached as the app's console —
`println` output and stack traces appear there, so leave it open and press
Ctrl-C when you're done.

To see the face under different conditions, use the simulator's menus:

| What to test | Where |
| --- | --- |
| Steps and the daily goal | Simulation → Activity Monitoring → Set Activity Monitor Info |
| Battery (at or below 20% the icon fills red) | Settings → Set Battery Status |
| Temperature, conditions, and the no-data path | Settings → Set Weather |
| Sunrise/sunset | Settings → Set Position |
| 12h/24h and °C/°F | Settings → Time Display, Settings → Units Display |

`tools/capture_sim.sh` saves the watch screen to `build/sim_screen.png` at 1:1
and `build/sim_screen_2x.png` magnified. The simulator's own File → Save Screen
Capture does the same thing through a save dialog.

Two things about the simulator are worth knowing before you trust what you see.
It renders the transflective panel's appearance rather than the framebuffer, so
every colour comes back shifted — pure black reads as `(1,1,1)` and the hair's
`(0,85,85)` as `(34,83,84)`. Comparing a capture against a source bitmap will
show most pixels "differing" even when the app is drawing it exactly. And it
gets wedged after repeated `monkeydo` loads, showing a blank white screen or a
frozen image of the previous build; when that happens, kill both `MonkeyDoDeux`
and the simulator and start over rather than trusting the picture.

## Install on the watch

```bash
tools/build.sh --device
```

Then connect the watch over USB, wait for it to mount as `GARMIN`, and:

```bash
cp bin/MikuFace.prg /Volumes/GARMIN/GARMIN/APPS/
```

Eject the watch and it will restart. The face appears at the end of the watch
face list under Watch Face → the last entry, or via Connect IQ → Watch Faces.

Sideloaded apps survive reboots but are wiped by a factory reset, and Garmin
Express will not sync them, so keep the `.prg`.

## The animation

Miku only moves while the watch is awake, and that is a firmware rule rather
than something the code can work around. A watch face runs in high power mode
for about ten seconds after a wrist raise, and during that window it gets
`onUpdate` every second and access to animations. Then the system calls
`onEnterSleep`, and from that point it has neither timers nor animations and
redraws once a minute. So she animates exactly while you are looking at her,
and holds a still pose the rest of the time.

The two states are separate resources. `resources/animations/` holds the loop,
played through a `WatchUi.AnimationLayer` positioned over the sprite's
rectangle; `resources/drawables/miku.png` is the still, drawn straight to the
device context whenever the layer is hidden. `onEnterSleep` hides the layer and
`onExitSleep` shows it again. `IdleLoop` also hides it if playback ends for any
reason other than finishing the clip, because a stopped layer keeps showing its
last frame and would otherwise freeze her mid-motion.

The loop resource costs nothing at runtime: the layer streams it rather than
loading it, so the face sits at 11.9 kB of its 123.8 kB budget with the
animation playing, against 10.0 kB before it existed.

## Regenerating the art

Both the still and the animation are generated, not hand-edited:

```bash
tools/generate_animation.sh    # needs Pillow and the SDK
```

That runs `tools/generate_miku.py` to produce `resources/drawables/miku.png`
and `build/miku-idle.gif`, then hands the GIF to Monkey Motion, the encoder
shipped inside the SDK's `MonkeyMotion.app`. Monkey Motion emits one `.mm` per
target resolution plus a manifest keyed by device part number — ours is
`006-B4532-00` — and it writes them into a directory named after the output
file, which the script flattens back into `resources/animations/`.

Run `python3 tools/generate_miku.py` alone if you only want the still.

The fiddly part is colour. The panel is ARGB2222, so every channel has to land
on one of four values and the entire palette is 64 colours. Nearest-colour
rounding is almost right; its one bad call is dragging the lightest skin tone
to a sickly yellow. Fixing those six warm tones by hand in `WARM_TONES` is
enough, and it beats dithering twice over — error diffusion speckles a face
that is only twelve pixels tall, and because the pattern is recomputed per
frame it crawls when the animation plays.

The source GIF holds the loop twice; frames 10-19 are pixel-identical to 0-9,
so only the first ten are encoded. Its 10 fps is also Monkey Motion's ceiling.

## Layout

`source/MikuFaceView.mc` holds the geometry as named constants at the top of
the class — the sprite's origin, the centreline the readouts stack on, and a Y
for each row.

Four things stack down the 260x260 screen: the sunrise/sunset row, Miku with
her column of readouts, steps, and battery. Miku is placed first and everything
else follows her, because she is what the face is for. Her drawn pixels run
y=68..191, centred on the screen, and steps and battery hang below at a 13px
pitch. The sun row keeps its place at the top, so the gap beneath it is wider
than the rest — the cost of anchoring her to the middle instead of spacing all
four evenly.

Horizontally, Miku and her column count as one group: `SPRITE_X` and
`COLUMN_CENTER` are chosen together so her leftmost drawn pixel and the widest
readout straddle the centre evenly. The clock sits level with her head, the rows
below it centre under the clock, and steps and battery clear her feet so they
span the full width instead.

Rows whose contents change width are measured at draw time rather than placed
at fixed coordinates. The sun row holds two times, the steps row pairs a count
with a goal, and the battery pairs an icon with a percentage; each is laid out
from its measured total so it stays centred whatever it says. The clock also
drops a font size if the time would overrun `COLUMN_WIDTH`.

Sunrise and sunset pad the hour to two digits. Measuring the row keeps its outer
edges centred, but with an unpadded `4:14` against `18:37` the two halves come
out different widths, which puts the gap between them off to one side and reads
as crooked. Equal halves make the row symmetric and centred at once.

`source/WatchData.mc` collects everything the face draws into one snapshot per
update, so the drawing code never has to decide whether a value exists.
Sunrise and sunset need a position, which normally arrives with the weather
data; when the watch hasn't synced, the last known fix is read back from
storage so those two readouts stay populated.

Colours are written as literals on the display's lattice (`0x55AAAA` and
friends) rather than `Graphics.COLOR_*`, so nothing gets approximated at draw
time and the simulator matches the watch.

## Credit

The Miku sprite comes from *Miku 'n Pop* (see `assets/`). It is fan art of a
Crypton Future Media character — fine for a face on your own wrist, not for
publishing to the Connect IQ store.

