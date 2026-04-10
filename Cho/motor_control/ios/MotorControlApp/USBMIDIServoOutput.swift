import CoreMIDI
import Foundation

final class USBMIDIServoOutput {
    private let tuning: MotorControlTuning
    private var client = MIDIClientRef()
    private var outputPort = MIDIPortRef()
    private var destination: MIDIEndpointRef?
    private(set) var connectedDestinationName: String?

    init(tuning: MotorControlTuning? = nil) throws {
        self.tuning = tuning ?? MotorControlTuning()

        let clientStatus = MIDIClientCreateWithBlock("MotorControlMIDIClient" as CFString, &client) { _ in
            // Prototype app keeps notification handling simple and reconnects lazily.
        }
        guard clientStatus == noErr else {
            throw MIDIServoError.clientCreationFailed(clientStatus)
        }

        let portStatus = MIDIOutputPortCreate(client, "MotorControlMIDIOutput" as CFString, &outputPort)
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

            let displayName = Self.stringProperty(object: endpoint, property: kMIDIPropertyDisplayName)
            let endpointName = Self.stringProperty(object: endpoint, property: kMIDIPropertyName)
            let manufacturer = Self.stringProperty(object: endpoint, property: kMIDIPropertyManufacturer)
            let model = Self.stringProperty(object: endpoint, property: kMIDIPropertyModel)
            let isOffline = (Self.intProperty(object: endpoint, property: kMIDIPropertyOffline) ?? 0) != 0
            let name = Self.bestAvailableName(
                displayName: displayName,
                endpointName: endpointName,
                manufacturer: manufacturer,
                model: model
            )
            let searchText = [displayName, endpointName, manufacturer, model, name]
                .compactMap { $0 }
                .joined(separator: " ")
            let summaryParts = [displayName, endpointName, manufacturer, model]
                .compactMap { value -> String? in
                    guard let value, !value.isEmpty else {
                        return nil
                    }
                    return value
                }
            let summaryBody = summaryParts.isEmpty ? name : summaryParts.joined(separator: " / ")
            let stateLabel = isOffline ? "offline" : "online"

            return MIDIDestinationDescriptor(
                endpoint: endpoint,
                name: name,
                searchText: searchText,
                isOffline: isOffline,
                debugSummary: "[\(stateLabel)] \(summaryBody)"
            )
        }
    }

    @discardableResult
    func connect(preferredNameFragment: String? = nil) -> MIDIDestinationDescriptor? {
        let onlineDestinations = availableDestinations().filter { !$0.isOffline }
        let preferredDescriptor = onlineDestinations.first { descriptor in
            guard let preferredNameFragment, !preferredNameFragment.isEmpty else {
                return false
            }
            return descriptor.searchText.localizedCaseInsensitiveContains(preferredNameFragment)
        }

        let selectedDescriptor = preferredDescriptor ?? onlineDestinations.first
        destination = selectedDescriptor?.endpoint
        connectedDestinationName = selectedDescriptor?.name
        return selectedDescriptor
    }

    func sendManualStep(_ direction: MotionDirection) throws {
        if destination == nil {
            _ = connect(preferredNameFragment: tuning.preferredMIDIDeviceName)
        }

        guard destination != nil else {
            throw MIDIServoError.noDestinationConnected
        }

        try sendControlChange(cc: tuning.commandCC, value: direction.rawValue)
    }

    func statusText(preferredNameFragment: String) -> String {
        if let connectedDestinationName {
            return "MIDI: \(connectedDestinationName)"
        }

        let onlineDestinations = availableDestinations().filter { !$0.isOffline }

        if onlineDestinations.isEmpty {
            return "MIDI: 감지된 목적지 없음"
        }

        if onlineDestinations.contains(where: { $0.searchText.localizedCaseInsensitiveContains(preferredNameFragment) }) {
            return "MIDI: Leonardo 후보 감지됨"
        }

        return "MIDI: 다른 장치 \(onlineDestinations.count)개"
    }

    func destinationDebugLines() -> [String] {
        let destinations = availableDestinations()
        guard !destinations.isEmpty else {
            return ["감지된 MIDI 목적지 없음"]
        }

        return destinations.map(\.debugSummary)
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
                return -1
            }

            var packet = MIDIPacketListInit(packetListPointer)
            let addStatus = bytes.withUnsafeBufferPointer { buffer -> OSStatus in
                guard let bytePointer = buffer.baseAddress else {
                    return -1
                }

                packet = MIDIPacketListAdd(
                    packetListPointer,
                    rawBuffer.count,
                    packet,
                    0,
                    bytes.count,
                    bytePointer
                )
                return noErr
            }

            guard addStatus == noErr else {
                return addStatus
            }

            return MIDISend(outputPort, destination, packetListPointer)
        }

        guard sendStatus == noErr else {
            if sendStatus == -1 {
                throw MIDIServoError.packetListCreationFailed
            }
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

    private static func bestAvailableName(
        displayName: String?,
        endpointName: String?,
        manufacturer: String?,
        model: String?
    ) -> String {
        let directName = [displayName, endpointName]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }
            .first

        if let directName {
            return directName
        }

        let composedName = [manufacturer, model]
            .compactMap { value -> String? in
                guard let value, !value.isEmpty else {
                    return nil
                }
                return value
            }
            .joined(separator: " ")

        return composedName.isEmpty ? "Unknown MIDI Device" : composedName
    }
}
