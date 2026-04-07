import CoreMIDI
import Foundation

struct MIDIDestinationDescriptor {
    let endpoint: MIDIEndpointRef
    let name: String
    let isOffline: Bool
}

enum MIDIServoError: Error {
    case clientCreationFailed(OSStatus)
    case outputPortCreationFailed(OSStatus)
    case noDestinationConnected
    case packetListCreationFailed
    case sendFailed(OSStatus)
}

final class USBMIDIServoOutput {
    private let tuning: TrackingTuning
    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var destination: MIDIEndpointRef?
    private(set) var connectedDestinationName: String?

    init(tuning: TrackingTuning = TrackingTuning()) throws {
        self.tuning = tuning

        let clientStatus = MIDIClientCreateWithBlock("FinalTrackingMIDIServoClient" as CFString, &client) { _ in
            // Notification handling is intentionally minimal for the prototype.
        }
        guard clientStatus == noErr else {
            throw MIDIServoError.clientCreationFailed(clientStatus)
        }

        let portStatus = MIDIOutputPortCreate(client, "FinalTrackingMIDIServoOutput" as CFString, &outputPort)
        guard portStatus == noErr else {
            throw MIDIServoError.outputPortCreationFailed(portStatus)
        }
    }

    deinit {
        if outputPort != 0 {
            MIDIPortDispose(outputPort)
        }
        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    func availableDestinations() -> [MIDIDestinationDescriptor] {
        let destinationCount = MIDIGetNumberOfDestinations()
        guard destinationCount > 0 else {
            return []
        }

        return (0..<destinationCount).compactMap { index in
            let endpoint = MIDIGetDestination(index)
            guard endpoint != 0 else {
                return nil
            }

            let name = Self.stringProperty(object: endpoint, property: kMIDIPropertyDisplayName) ?? "Unknown MIDI Device"
            let isOffline = (Self.intProperty(object: endpoint, property: kMIDIPropertyOffline) ?? 0) != 0
            return MIDIDestinationDescriptor(endpoint: endpoint, name: name, isOffline: isOffline)
        }
    }

    @discardableResult
    func connect(preferredNameFragment: String? = nil) -> MIDIDestinationDescriptor? {
        let onlineDestinations = availableDestinations().filter { !$0.isOffline }
        let preferredDescriptor = onlineDestinations.first { descriptor in
            guard let preferredNameFragment, !preferredNameFragment.isEmpty else {
                return false
            }
            return descriptor.name.localizedCaseInsensitiveContains(preferredNameFragment)
        }

        let selectedDescriptor = preferredDescriptor ?? onlineDestinations.first
        destination = selectedDescriptor?.endpoint
        connectedDestinationName = selectedDescriptor?.name
        return selectedDescriptor
    }

    func send(direction: MotionDirection, strength: UInt8) throws {
        if direction == .stop {
            try sendControlChange(cc: tuning.commandCC, value: MotionDirection.stop.rawValue)
            return
        }

        try sendControlChange(cc: tuning.strengthCC, value: strength)
        try sendControlChange(cc: tuning.commandCC, value: direction.rawValue)
    }

    func sendStop() throws {
        try send(direction: .stop, strength: 0)
    }

    func statusText(preferredNameFragment: String) -> String {
        if let connectedDestinationName {
            return "MIDI: \(connectedDestinationName)"
        }

        let destinationNames = availableDestinations()
            .filter { !$0.isOffline }
            .map(\.name)

        if destinationNames.isEmpty {
            return "MIDI: not connected"
        }

        if destinationNames.contains(where: { $0.localizedCaseInsensitiveContains(preferredNameFragment) }) {
            return "MIDI: Leonardo available"
        }

        return "MIDI: using fallback destination"
    }

    private func sendControlChange(cc: UInt8, value: UInt8) throws {
        guard let destination else {
            throw MIDIServoError.noDestinationConnected
        }

        let statusByte = UInt8(0xB0 | ((tuning.midiChannel - 1) & 0x0F))
        let bytes = [statusByte, cc, value]
        var packetBuffer = [UInt8](repeating: 0, count: 256)

        let sendStatus = packetBuffer.withUnsafeMutableBytes { rawBuffer -> OSStatus in
            guard let packetListPointer = rawBuffer.baseAddress?.assumingMemoryBound(to: MIDIPacketList.self) else {
                return MIDIServoError.packetListCreationFailed.osStatus
            }

            var packet = MIDIPacketListInit(packetListPointer)
            let addStatus = bytes.withUnsafeBufferPointer { buffer -> OSStatus in
                guard let bytePointer = buffer.baseAddress else {
                    return MIDIServoError.packetListCreationFailed.osStatus
                }

                guard let nextPacket = MIDIPacketListAdd(
                    packetListPointer,
                    rawBuffer.count,
                    packet,
                    0,
                    bytes.count,
                    bytePointer
                ) else {
                    return MIDIServoError.packetListCreationFailed.osStatus
                }

                packet = nextPacket
                return noErr
            }

            guard addStatus == noErr else {
                return addStatus
            }

            return MIDISend(outputPort, destination, packetListPointer)
        }

        guard sendStatus == noErr else {
            throw MIDIServoError.sendFailed(sendStatus)
        }
    }

    private static func stringProperty(object: MIDIObjectRef, property: CFString) -> String? {
        var unmanagedString: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, property, &unmanagedString)
        guard status == noErr, let unmanagedString else {
            return nil
        }
        return unmanagedString.takeRetainedValue() as String
    }

    private static func intProperty(object: MIDIObjectRef, property: CFString) -> Int32? {
        var value: Int32 = 0
        let status = MIDIObjectGetIntegerProperty(object, property, &value)
        guard status == noErr else {
            return nil
        }
        return value
    }
}

private extension MIDIServoError {
    var osStatus: OSStatus {
        switch self {
        case .clientCreationFailed(let status):
            return status
        case .outputPortCreationFailed(let status):
            return status
        case .sendFailed(let status):
            return status
        case .noDestinationConnected:
            return kMIDIUnknownEndpoint
        case .packetListCreationFailed:
            return -1
        }
    }
}
