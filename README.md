# Lumi Connect

Play a ROLI LUMI Keys (now sold as ROLI Piano M) over Bluetooth on a Mac without pairing it by hand, and have its lit keys follow the scale of your Ableton Live clips. No ROLI software involved.

It has two parts:

| Part | What it does |
|---|---|
| **Lumi Connect.app** | Asks macOS to connect the LUMI over Bluetooth MIDI, then quits. It replaces opening Audio MIDI Setup and clicking Connect every session |
| **Lumi remote script** for Ableton Live | Starts Lumi Connect whenever the LUMI is not answering, and sends the clip's root note and scale to the LUMI each time they change |

Not affiliated with or endorsed by ROLI or Ableton.

## Requirements

- macOS 13 or later, with the Xcode Command Line Tools (`xcode-select --install`)
- Ableton Live 11 or later, for the clip Scale setting (tested on Live 11.3)
- A LUMI Keys block (tested on firmware 1.3.9)

**Untested:** Live 12, ROLI Piano M units sold under the new name, and macOS versions other than 26. Reports are welcome.

## Install

```sh
git clone https://github.com/jacobeus/lumi-connect.git
cd lumi-connect
./install.sh
```

The script builds the app, copies it to `/Applications`, and copies the remote script into your Live User Library. It finds the User Library from Live's own settings. If that fails, pass the path: `./install.sh "/path/to/User Library"`.

There is no prebuilt download: the app is signed ad hoc on your machine, so macOS does not flag it.

## Set up Ableton Live

1. Switch the LUMI on and restart Live.
2. Open **Preferences > Link, Tempo & MIDI**.
3. In a free Control Surface row, choose **Lumi**, and set Input and Output to the LUMI's Bluetooth port.
4. Make sure no other row uses the LUMI port or the **BLOCKS** control surface. Live's built-in ROLI script sends its own messages to the LUMI and conflicts with this one.
5. Under MIDI Ports, switch on **Track** for the LUMI's input so its notes reach your tracks. Switch on **MPE** too if you play MPE instruments.

Now switch on **Scale** in a MIDI clip and pick a root and scale: the LUMI lights it.

## Use

- **Switching the LUMI on with Live open:** it connects within about 20 seconds.
- **Without Live:** open Lumi Connect from Applications. You hear a short sound when the LUMI is connected.
- **On first use:** if macOS has never connected the LUMI before, Lumi Connect scans for it and asks for Bluetooth permission.

## What it changes on the LUMI

| Setting | Value |
|---|---|
| Colour mode | Single colour scale, so the scale is visible |
| Key | The clip's root note |
| Scale | The clip's scale, from the table below. Clips with Scale off light every key |

| Live scale | LUMI scale |
|---|---|
| Major, Minor, Harmonic Minor | Same |
| Major Pentatonic, Minor Pentatonic | Pentatonic Major, Pentatonic Minor |
| Minor Blues | Blues |
| Dorian, Phrygian, Lydian, Mixolydian, Locrian, Whole Tone | Same |
| Anything else | Chromatic (every key lit) |

The settings are written to the LUMI's current configuration, as ROLI Dashboard would write them.

## Troubleshooting

| Symptom | Check |
|---|---|
| The LUMI port is missing from Live's MIDI lists | The LUMI is not connected. Open Lumi Connect by hand: its message says why |
| The keys flash blue and never connect | Another device may hold the LUMI, for example a phone running the ROLI app |
| The scale does not follow | Restart Live after installing or updating the script. Then look for lines starting with `Lumi:` in Live's `Log.txt` (`~/Library/Preferences/Ableton/Live <version>/Log.txt`) |
| Lumi Connect fails silently when Live starts it | `log show --last 10m --predicate 'subsystem == "io.github.jacobeus.lumi-connect"'` |

## How it works

[docs/PROTOCOL.md](docs/PROTOCOL.md) explains why macOS will not reconnect the LUMI on its own, how Lumi Connect gets it connected, and the SysEx (system exclusive MIDI) messages the remote script sends.

## Credits

The LUMI SysEx messages come from [benob/LUMI-lights](https://github.com/benob/LUMI-lights), which recorded what ROLI Dashboard sends.

## License

[MIT](LICENSE)
