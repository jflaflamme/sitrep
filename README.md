# SITREP

A Connect IQ watch face that shows one screen of status: an arc over the top and one under
the bottom, a line of data above and below two rows of two, and the time in the middle.
What every place shows is a setting you choose from a computer over USB, with no phone
app and no account.

Written for the tactix 7 Pro (Connect IQ device `fenix7x`, 280 x 280 memory-in-pixel
screen): Garmin's own bold system fonts, only full-strength colours, and an optional light
theme (black on white), which reads best on a reflective screen in daylight.
Do Not Disturb blanks the face. A sun under the time shows while the solar panel gets
light (`solar_icon=false` hides it).

## No Garmin cloud

SITREP is built, installed and configured without Garmin Connect, the Connect IQ app or
the Connect IQ Store, and without a Garmin account:

- **Install:** the `.prg` is copied to the watch over USB (sideloading).
- **Settings:** changed over USB with `tools/garmin-sitrep`, not through the Connect IQ
  phone app, so your layout never passes through Garmin's servers.
- **No network access:** the face asks only for position, sensor history and user
  profile (heart rate zones), never the Communications permission, so it cannot send
  anything anywhere.
- **Tested with an open-source phone companion:** [Pulse](https://github.com/zoop-dev/pulse),
  a fork of [Gadgetbridge](https://codeberg.org/Freeyourgadget/Gadgetbridge). Weather,
  notifications and time come from the phone over Bluetooth; nothing about the watch
  or its wearer reaches Garmin or the Connect IQ cloud.

Weather on Garmin watches through Gadgetbridge needs its "Send fake OAuth responses"
setting (device settings > Authentication); without it the watch never asks the phone
for weather and the weather fields stay empty.

## Install a release

Each [release](https://github.com/jflaflamme/sitrep/releases) has `SITREP.prg`, built for
Connect IQ device `fenix7x` (fēnix 7X, tactix 7, quatix 7X Solar, Enduro 2). Either:

- **Bluetooth:** on the phone, share `SITREP.prg` to [Gadgetbridge](https://gadgetbridge.org)
  or [Pulse](https://github.com/zoop-dev/pulse); it uploads the face to the watch.
- **USB:** copy it into `GARMIN/Apps` on the watch, then unplug.

Then choose SITREP as the watch face. Updates keep your layout; the face's Customize menu
on the watch shows the installed version. After a
recent Garmin firmware change a `.prg` only runs on the model it was built for; for other
watches build it yourself.

## Build and install

    ./build.sh                     # builds bin/SITREP.prg, copies it if the watch is connected
    tools/garmin-eject             # then unplug; the watch installs it

Needs Linux (the watch is reached through GNOME's gvfs/gio over MTP), Python 3, the
Connect IQ SDK and a developer key at `~/.config/garmin-ciq/developer_key.der`
(`KEY=... ./build.sh` for another path). Another watch: `DEVICE=<connect iq id> ./build.sh`,
though the layout is designed for a 280 x 280 screen.

## Tools

- `tools/garmin-sitrep`: choose what the face shows (below). Its settings file format
  code is in `tools/sitrep_settings.py`.
- `tools/garmin-eject`: unmount the watch so it can be unplugged.

Every change backs up the watch's settings file first, to
`~/.local/share/garmin-watch/backups` (`$XDG_DATA_HOME`, or set `GARMIN_BACKUP_DIR`).

## Choose what it shows

    tools/garmin-sitrep options                        # everything a slot can show
    tools/garmin-sitrep show                           # current layout on the watch
    tools/garmin-sitrep set top=sunrise row1=steps,heart_rate arc_top=solar
    tools/garmin-sitrep set accent_color=#00AAFF seconds=false
    tools/garmin-sitrep set light=true                 # black on white
    tools/garmin-sitrep reset

The watch has to be plugged in (USB, file access allowed) to read or change the layout.

Slots: `top`, `left1`, `right1`, `left2`, `right2`, `bottom`, `arc_top`, `arc_bottom`.
Arcs take only options that are a fraction of something (battery, body battery, stress,
solar, steps / floors / active minutes against their goals).

The option list lives in one place, `source/Fields.mc`: the face draws from it and the CLI
reads it. Rows are append-only, because a saved setting is the row number.

## Easter eggs

On by default; `tools/garmin-sitrep set easter_eggs=false` turns them all off.

| Icon | Where | When |
|---|---|---|
| UFO | over the top arc | 11:11, 22:22, 3:33 and 15:33, for that minute |
| Alien | replaces the heart | heart rate exactly 111, or in your top heart rate zone |
| Skull | centre under the time, and the battery icon | battery below 10 % |
| Ghost | left under the time, instead of the message count | phone not connected |
| Moon and stars | centre under the time | between sunset and sunrise (18:00 to 06:00 without a position) |
| Rocket | replaces the shoe | step goal reached |
| Satellite | replaces the mountain | a usable GPS fix under 10 minutes old |

## Notes

- Seconds stay on in low-power mode (`seconds_always`): only the two digits are redrawn
  each second, inside the power budget the watch allows. If the watch reports the budget
  exceeded, seconds show only while the watch is awake. `seconds_always=false` saves battery.
- A value too wide for its place (the side columns are the narrowest) is fitted rather
  than run into its neighbour: steps and calories first show as thousands (`12.3K`,
  `123K`), then the value drops to a smaller font, then loses its icon. A number that
  fits is shown in full.
- Sunrise and sunset need Connect IQ API 3.3 and a last known position.
- Temperature comes from the weather service when available, otherwise from the watch's
  own sensor, which reads warm on the wrist.

## Licence

GPL-3.0-or-later, see [LICENSE](LICENSE).

Icons: [Tabler Icons](https://tabler.io/icons), MIT licence, see
`resources/fonts/TABLER-LICENSE`; `make_icons.py` rebuilds the icon font from the Tabler
webfont.
