# How Lumi Connect works

## Bluetooth: why the LUMI does not reconnect

macOS reconnects a Bluetooth LE (Low Energy) MIDI device automatically only if the device supports pairing. The LUMI does not. The Bluetooth daemon's log lists it as `not paired - No AutoConnect`, so each session it has to be connected again by hand from Audio MIDI Setup.

## What Audio MIDI Setup's Connect button does

Bluetooth MIDI on macOS is handled by `AppleMIDIBluetoothDriver`, which runs inside `MIDIServer`. Among its devices it keeps a hidden **null device**, marked with the integer property `is BLE MIDI null device` = 1.

Connect sets one dictionary property on that null device:

| Property | Value |
|---|---|
| `BLE MIDI Remote Peripheral` | `{"BLE MIDI Device UUID": <CoreBluetooth peripheral UUID>, "name": <device name>}` |

The driver watches only three keys on the null device: `BLE MIDI Remote Peripheral`, `BLE MIDI Local Peripheral` and `disconnect device`. When the first one is set, the driver reads the dictionary, removes it, and connects the peripheral itself. Core MIDI then owns the connection, so the process that asked can quit.

Lumi Connect does exactly that through the public `MIDIObjectSetDictionaryProperty` call:

1. It finds the LUMI's UUID on the Bluetooth MIDI device Core MIDI remembers from an earlier connection. If there is none, it scans for the Bluetooth MIDI service (`03B80E5A-EDE8-4B33-A751-6CE34EC4C700`) and takes the first device whose name contains "lumi" or "piano m".
2. It sets the property on the null device.
3. It waits up to 15 seconds for the device to come online, then exits.

`MIDIBluetoothDriverActivateAllConnections`, the documented API in `CoreMIDI/MIDIBluetoothConnection.h`, does not help here. It only promotes peripherals the calling app has already connected through CoreBluetooth, and it did not make the LUMI appear as a MIDI device.

These property names are undocumented. A macOS update could change them.

## LUMI SysEx

The LUMI speaks ROLI's BLOCKS protocol. Every message starts with ROLI's manufacturer ID, `F0 00 21 10`.

### Topology index

Messages to a block carry the block's **topology index**, and the LUMI ignores configuration messages sent to any other index. The index is assigned per connection, so it cannot be hardcoded: one LUMI answered as `0x37` in benob's recording and as `0x2B` on Bluetooth here.

The remote script asks for the topology every 5 seconds:

```
F0 00 21 10 77 00 01 01 00 5D F7
```

Messages from the block carry the index with bit `0x40` set. In a reply starting `F0 00 21 10 77 6B`, the index is `0x6B & 0x3F` = `0x2B`. The same request doubles as the liveness check: when no reply arrives, the script starts Lumi Connect.

### Configuration messages

```
F0 00 21 10 77 <index> 10 <group> <v0> <v1> 00 00 00 00 <checksum> F7
```

`10` is the BLOCKS config message type. The value is packed into 7-bit bytes: `v0 = value & 0x7F` and `v1 = (value >> 7) & 0x7F`.

| Setting | Group | Value |
|---|---|---|
| Colour mode | `40` | `mode * 32 + 2`. Rainbow 0, single colour scale 1, piano 2, night 3 |
| Key | `30` | `root * 32 + 3`, root 0 = C to 11 = B |
| Scale | `60` | `scale * 32 + 2` |

Scale numbers: major 0, minor 1, harmonic minor 2, pentatonic neutral 3, pentatonic major 4, pentatonic minor 5, blues 6, dorian 7, phrygian 8, lydian 9, mixolydian 10, locrian 11, whole tone 12, arabic a 13, arabic b 14, japanese 15, ryukyu 16, 8-tone spanish 17, chromatic 18.

The checksum covers the eight bytes after the index:

```python
def checksum(command):
    c = len(command)
    for b in command:
        c = (c * 3 + b) & 0xFF
    return c & 0x7F
```

Example: key E (root 4) on index `0x2B` is `F0 00 21 10 77 2B 10 30 03 01 00 00 00 00 12 F7`.

The group byte and the first value byte share bits, so the same group number appears with different meanings in benob's notes: `30` also sets the root key colour, and `40` also sets brightness and octave. The table above lists only the values this project sends and has tested.

## LittleFoot programs

The LUMI runs a program written in ROLI's [LittleFoot](https://github.com/WeAreROLI/roli_blocks_basics/blob/main/roli_LittleFootFunctions.dox) language, which draws the key lights and can play the keys. `LightShow/` replaces it with its own through ROLI's BLOCKS SDK (`roli_blocks_basics`):

| Fact | Detail |
|---|---|
| **Finding the LUMI** | The SDK accepts any MIDI port whose name contains `" BLOCK"` (`roli_BlockNameController.h`), so the Bluetooth port works. It reports the LUMI as `ROLI Piano M` |
| **Temporary load** | `Block::setProgram` defaults to `ProgramPersistency::setAsTemp`. `resetProgramToDefault()` puts the LUMI's own program back |
| **Saving to flash** | `setAsDefault` survives power-off, but only a factory reset undoes it, and that also wipes the LUMI's settings. Lumi Connect never saves |
| **Key handling** | With `setUseDefaultKeyHandler (true, false)` the firmware plays the keys but never calls the program's `keyStrike`, so a program that reacts to keys has to play them itself |
| **Callbacks to implement** | `keyStrike` (note on), `keyPress` (aftertouch), `keyMove` (pitch bend, 0 to 16383, 8192 at rest), `keyLift` (note off), `handleButtonDown` (button 1 octave down, 2 octave up) |
| **Settings it reads** | `getLocalConfig (4)` is the saved octave, `getLocalConfig (11)` the glide (pitch bend) sensitivity |
| **Debugging** | `sendMessageToHost (a, b, c)` reaches the host as a program event (`Block::addProgramEventListener`) |

## Ableton

The remote script follows the song-level properties `Song.root_note`, `Song.scale_name` and, where it exists, `Song.scale_mode`. In Live 11, setting a clip's Scale updates these. Live loads remote scripts once at startup, so it needs a restart after the script changes.
