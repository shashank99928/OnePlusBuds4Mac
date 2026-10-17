// Recon logger for the OPPO/realme/OnePlus TWS vendor RFCOMM channels.
// Opens each channel READ-ONLY and hex-dumps every inbound frame with a timestamp.
// Writes nothing to the buds.
//
// Run:  swift Tools/sniff.swift [channel …]      (default: 12 15 17)
//
// Channel 13 is BESOTA, the firmware OTA service. Never open it.

import Foundation
import IOBluetooth

setvbuf(stdout, nil, _IOLBF, 0)

let besotaChannel: BluetoothRFCOMMChannelID = 13

/// SDP service names, for labelling the trace.
let serviceNames: [BluetoothRFCOMMChannelID: String] = [
    12: "Realme Pearl", 15: "oppointeraction", 17: "RFCOMM COM", 29: "WATCH",
]

/// The device is discovered the same way the app finds it — by the `oppointeraction`
/// control service — so no one's Bluetooth address is baked into the source.
/// `BUDSBAR_ADDRESS` overrides it when several matching devices are paired.
func discoverDevice() -> IOBluetoothDevice? {
    if let forced = ProcessInfo.processInfo.environment["BUDSBAR_ADDRESS"], !forced.isEmpty {
        return IOBluetoothDevice(addressString: forced)
    }
    let uuid = IOBluetoothSDPUUID(bytes: [
        0x00, 0x00, 0x07, 0x9a, 0xd1, 0x02, 0x11, 0xe1,
        0x9b, 0x23, 0x00, 0x02, 0x5b, 0x00, 0xa5, 0xa5,
    ], length: 16)
    return (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?
        .first { $0.getServiceRecord(for: uuid) != nil }
}

let requested: [BluetoothRFCOMMChannelID] = CommandLine.arguments.count > 1
    ? CommandLine.arguments.dropFirst().compactMap { BluetoothRFCOMMChannelID($0) }
    : [12, 15, 17]

let channels = requested.filter { $0 != besotaChannel }
if channels.count != requested.count {
    print("refusing channel \(besotaChannel) (BESOTA firmware OTA)")
}

let start = Date()
func stamp() -> String { String(format: "%8.3f", Date().timeIntervalSince(start)) }
func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

final class Sniffer: NSObject, IOBluetoothRFCOMMChannelDelegate {
    /// Ask the channel which one it is rather than trusting the id we requested.
    private func label(_ channel: IOBluetoothRFCOMMChannel!) -> String {
        let id = channel?.getID() ?? 0
        return "ch\(id) \(serviceNames[id] ?? "?")"
    }

    func rfcommChannelOpenComplete(_ channel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        print("[\(stamp())] \(label(channel)): \(error == kIOReturnSuccess ? "open" : "FAILED (\(error))")")
    }

    func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let bytes = Array(UnsafeBufferPointer(
            start: dataPointer.assumingMemoryBound(to: UInt8.self), count: dataLength))
        print("[\(stamp())] \(label(channel)): \(hex(bytes))")
    }

    func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        print("[\(stamp())] \(label(channel)): closed")
    }
}

guard let device = discoverDevice() else {
    print("no paired device advertises the control service — pair your buds first, "
        + "or set BUDSBAR_ADDRESS to a Bluetooth address")
    exit(1)
}
print("[\(stamp())] \(device.name ?? "?") connected: \(device.isConnected())")
guard device.isConnected() else {
    print("buds are not connected — connect them first"); exit(1)
}

// The channel open silently never completes unless the device's SDP records have been
// fetched in this process first.
device.performSDPQuery(nil)
RunLoop.current.run(until: Date().addingTimeInterval(3))

var openChannels: [IOBluetoothRFCOMMChannel?] = []
var delegates: [Sniffer] = []          // keep alive; the channel does not retain them

for id in channels {
    let sniffer = Sniffer()
    delegates.append(sniffer)
    var channel: IOBluetoothRFCOMMChannel?
    let result = device.openRFCOMMChannelAsync(&channel, withChannelID: id, delegate: sniffer)
    if result == kIOReturnSuccess {
        openChannels.append(channel)
    } else {
        print("[\(stamp())] ch\(id): open failed (\(result))")
    }
}

print("[\(stamp())] listening — change the noise mode on the iPhone now")
RunLoop.current.run()
