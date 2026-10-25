# Ableton Live control surface for a ROLI Lumi over Bluetooth.
#
# - Keeps the Lumi connected: a topology request runs every few seconds, and when the
#   Lumi does not answer, the script starts Lumi Connect in --quiet mode.
# - Learns the Lumi's topology index from the answer. The index is assigned per
#   connection, and config messages addressed to any other index are ignored.
# - Lights the song's scale on the Lumi: Live's root_note and scale_name (set from the
#   clip Scale choosers) are pushed as the Lumi's key and scale settings.
#
# The LUMI SysEx protocol is described in docs/PROTOCOL.md. The messages were recorded
# from ROLI Dashboard in https://github.com/benob/LUMI-lights (SYSEX.txt).

import subprocess

from _Framework.ControlSurface import ControlSurface

ROLI_HEADER = (0xF0, 0x00, 0x21, 0x10)
BLOCK_MESSAGE = 0x77
TOPOLOGY_REQUEST = ROLI_HEADER + (BLOCK_MESSAGE, 0x00, 0x01, 0x01, 0x00, 0x5D, 0xF7)
FROM_DEVICE = 0x40  # set on the index byte of messages the Lumi sends

# Live scale name -> Lumi scale index. Live scales the Lumi lacks light every key.
LUMI_SCALES = {
    "major": 0,
    "minor": 1,
    "harmonic minor": 2,
    "major pentatonic": 4,
    "minor pentatonic": 5,
    "minor blues": 6,
    "dorian": 7,
    "phrygian": 8,
    "lydian": 9,
    "mixolydian": 10,
    "locrian": 11,
    "whole tone": 12,
}
CHROMATIC = 18
SINGLE_COLOUR_SCALE_MODE = 1

PROBE_INTERVAL_TICKS = 50   # Live ticks are about 100 ms: a probe every ~5 s
LAUNCH_EVERY_N_MISSES = 4   # start Lumi Connect every ~20 s while the Lumi is silent


def checksum(command):
    c = len(command)
    for b in command:
        c = (c * 3 + b) & 0xFF
    return c & 0x7F


def key_message(device, root_note):
    return lumi_command(device, 0x30, root_note * 32 + 3)


def scale_message(device, scale_index):
    return lumi_command(device, 0x60, scale_index * 32 + 2)


def colour_mode_message(device, mode):
    return lumi_command(device, 0x40, mode * 32 + 2)


def lumi_command(device, group, packed):
    command = (0x10, group, packed & 0x7F, (packed >> 7) & 0x7F, 0, 0, 0, 0)
    return ROLI_HEADER + (BLOCK_MESSAGE, device) + command + (checksum(command), 0xF7)


class Lumi(ControlSurface):

    def __init__(self, c_instance):
        super(Lumi, self).__init__(c_instance)
        self._alive = False
        self._misses = 0
        self._device = None
        song = self.song()
        song.add_root_note_listener(self._send_scale)
        song.add_scale_name_listener(self._send_scale)
        if hasattr(song, "add_scale_mode_listener"):
            song.add_scale_mode_listener(self._send_scale)
        self.log_message("Lumi: started")
        self._launch_lumi_connect()
        self.schedule_message(PROBE_INTERVAL_TICKS, self._probe)

    def disconnect(self):
        song = self.song()
        song.remove_root_note_listener(self._send_scale)
        song.remove_scale_name_listener(self._send_scale)
        if hasattr(song, "remove_scale_mode_listener"):
            song.remove_scale_mode_listener(self._send_scale)
        super(Lumi, self).disconnect()

    # Connection

    def _probe(self):
        if self._alive:
            self._misses = 0
        else:
            self._misses += 1
            if self._misses % LAUNCH_EVERY_N_MISSES == 0:
                self._launch_lumi_connect()
        self._alive = False
        self._send_midi(TOPOLOGY_REQUEST)
        self.schedule_message(PROBE_INTERVAL_TICKS, self._probe)

    def handle_sysex(self, midi_bytes):
        if tuple(midi_bytes[:4]) != ROLI_HEADER:
            return
        came_back = not self._alive and self._misses > 0
        self._alive = True
        if len(midi_bytes) > 5 and midi_bytes[4] == BLOCK_MESSAGE and midi_bytes[5] & FROM_DEVICE:
            device = midi_bytes[5] & 0x3F
            if device != self._device:
                self.log_message("Lumi: topology index %d" % device)
                self._device = device
                return self._send_scale()
        if came_back:
            self.log_message("Lumi: answering again")
            self._send_scale()

    def refresh_state(self):
        super(Lumi, self).refresh_state()
        self._send_scale()

    def _launch_lumi_connect(self):
        self.log_message("Lumi: starting Lumi Connect")
        try:
            subprocess.Popen(["/usr/bin/open", "-g", "-a", "Lumi Connect", "--args", "--quiet"])
        except Exception as e:
            self.log_message("Lumi: could not start Lumi Connect: %s" % e)

    # Scale

    def _send_scale(self):
        if self._device is None:
            return
        song = self.song()
        scale_on = getattr(song, "scale_mode", True)
        index = LUMI_SCALES.get(song.scale_name.lower(), CHROMATIC) if scale_on else CHROMATIC
        self.log_message("Lumi: key %d, %s -> Lumi scale %d" % (song.root_note, song.scale_name, index))
        self._send_midi(colour_mode_message(self._device, SINGLE_COLOUR_SCALE_MODE))
        self._send_midi(key_message(self._device, song.root_note))
        self._send_midi(scale_message(self._device, index))
