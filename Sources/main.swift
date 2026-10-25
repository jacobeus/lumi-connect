// Lumi Connect: asks macOS's Bluetooth MIDI driver to connect a ROLI LUMI Keys or Piano M, then quits.
//
// The Lumi does not support Bluetooth pairing, so macOS never reconnects it on its
// own ("not paired - No AutoConnect" in bluetoothd's log). Audio MIDI Setup's Connect
// button works by setting the "BLE MIDI Remote Peripheral" property on the driver's
// "null device" to {"BLE MIDI Device UUID": <peripheral UUID>, name: <device name>}.
// The driver (AppleMIDIBluetoothDriver, NullDevicePropertyChanged) only reacts to that
// key, "BLE MIDI Local Peripheral" and "disconnect device"; it reads the dictionary,
// removes it, and connects the peripheral itself. Core MIDI then owns
// the connection, so this app can quit.
//
// With --quiet (how the Ableton remote script starts it) the app shows no Dock icon,
// dialog or sound, and simply exits on failure.
//
// The UUID comes from the Bluetooth MIDI device Core MIDI already remembers from a
// past connection; a Bluetooth scan is the fallback when there is none.

import AppKit
import CoreBluetooth
import CoreMIDI
import os

let log = Logger(subsystem: "io.github.jacobeus.lumi-connect", category: "connect")

// LUMI Keys was renamed Piano M in 2024; either name may be advertised.
let nameMatches = ["lumi", "piano m"]
let bluetoothDriver = "com.apple.AppleMIDIBluetoothDriver"
let uuidKey = "BLE MIDI Device UUID"
let activationKey = "BLE MIDI Remote Peripheral"
let midiService = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
let scanTimeout: TimeInterval = 20
let connectTimeout: TimeInterval = 15
let hardDeadline: TimeInterval = 45
let quiet = CommandLine.arguments.contains("--quiet")

final class Connector: NSObject, NSApplicationDelegate, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private var scanTimer: Timer?
    private var requested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Whatever happens, the app never outlives this deadline.
        DispatchQueue.main.asyncAfter(deadline: .now() + hardDeadline) {
            log.error("hard deadline reached, exiting")
            exit(1)
        }
        if let device = bluetoothDevice(), isOnline(device) {
            log.info("already online")
            return finish()
        }
        if let device = bluetoothDevice(), let uuid = stringProperty(device, uuidKey) {
            return requestConnection(uuid: uuid, name: stringProperty(device, kMIDIPropertyName as String) ?? "LUMI")
        }
        log.info("no remembered Lumi in Core MIDI, scanning")
        if !quiet { NSApp.dockTile.badgeLabel = "…" }
        central = CBCentralManager(delegate: self, queue: .main)
        scanTimer = Timer.scheduledTimer(withTimeInterval: scanTimeout, repeats: false) { [weak self] _ in
            self?.fail("No Lumi found within \(Int(scanTimeout)) seconds. Switch it on and try again.")
        }
    }

    // MARK: Bluetooth scan (fallback when Core MIDI has never seen the Lumi)

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.info("bluetooth state \(central.state.rawValue)")
        switch central.state {
        case .poweredOn:
            central.scanForPeripherals(withServices: [midiService])
        case .unauthorized:
            fail("Lumi Connect needs Bluetooth access: System Settings > Privacy & Security > Bluetooth.")
        case .poweredOff:
            fail("Bluetooth is off.")
        case .unsupported:
            fail("This Mac does not support Bluetooth LE.")
        default:
            break
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        guard let name, matchesName(name), !requested else { return }
        central.stopScan()
        scanTimer?.invalidate()
        requestConnection(uuid: peripheral.identifier.uuidString, name: name)
    }

    // MARK: Driver request

    private func requestConnection(uuid: String, name: String) {
        requested = true
        guard let nullDevice = nullDevice() else {
            return fail("macOS's Bluetooth MIDI driver is not running.")
        }
        let request = [uuidKey: uuid, kMIDIPropertyName as String: name] as CFDictionary
        let status = MIDIObjectSetDictionaryProperty(nullDevice, activationKey as CFString, request)
        log.info("requested connection to \(name, privacy: .public) (\(uuid, privacy: .public)): \(status)")
        guard status == noErr else { return fail("The Bluetooth MIDI driver refused the request (error \(status)).") }
        if !quiet { NSApp.dockTile.badgeLabel = "…" }
        waitUntilOnline(deadline: Date().addingTimeInterval(connectTimeout))
    }

    private func waitUntilOnline(deadline: Date) {
        if let device = bluetoothDevice(), isOnline(device) {
            log.info("online in Core MIDI")
            if quiet { return finish() }
            NSSound(named: "Pop")?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.finish() }
        } else if Date() > deadline {
            fail("The Lumi did not connect within \(Int(connectTimeout)) seconds. Is it switched on?")
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.waitUntilOnline(deadline: deadline) }
        }
    }

    // MARK: Exit

    private func fail(_ message: String) {
        log.error("\(message, privacy: .public)")
        scanTimer?.invalidate()
        central?.stopScan()
        if quiet { return finish() }
        NSApp.dockTile.badgeLabel = nil
        let alert = NSAlert()
        alert.messageText = "Lumi not connected"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
        finish()
    }

    // exit rather than NSApp.terminate: nothing here needs a graceful shutdown.
    private func finish() {
        log.info("exiting")
        exit(0)
    }
}

// MARK: Core MIDI lookups

func devices() -> [MIDIDeviceRef] {
    (0..<MIDIGetNumberOfDevices()).map { MIDIGetDevice($0) }
}

func stringProperty(_ object: MIDIObjectRef, _ key: String) -> String? {
    var value: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(object, key as CFString, &value) == noErr else { return nil }
    return value?.takeRetainedValue() as String?
}

func integerProperty(_ object: MIDIObjectRef, _ key: String) -> Int32? {
    var value: Int32 = 0
    guard MIDIObjectGetIntegerProperty(object, key as CFString, &value) == noErr else { return nil }
    return value
}

func isOnline(_ device: MIDIDeviceRef) -> Bool {
    integerProperty(device, kMIDIPropertyOffline as String) == 0
}

// A Bluetooth-driver device only: a USB entry left from cable use carries the same name.
func bluetoothDevice() -> MIDIDeviceRef? {
    devices().first {
        stringProperty($0, kMIDIPropertyDriverOwner as String) == bluetoothDriver
            && stringProperty($0, kMIDIPropertyName as String).map(matchesName) == true
            && stringProperty($0, uuidKey) != nil
    }
}

func matchesName(_ name: String) -> Bool {
    nameMatches.contains { name.lowercased().contains($0) }
}

func nullDevice() -> MIDIDeviceRef? {
    devices().first { integerProperty($0, "is BLE MIDI null device") == 1 }
}

// A client connection keeps this process's view of Core MIDI devices current.
var midiClient = MIDIClientRef()
MIDIClientCreate("Lumi Connect" as CFString, nil, nil, &midiClient)

let app = NSApplication.shared
let connector = Connector()
app.delegate = connector
app.setActivationPolicy(quiet ? .accessory : .regular)
app.run()
