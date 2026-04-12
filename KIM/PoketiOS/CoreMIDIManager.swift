import Foundation
import CoreMIDI

enum CoreMIDIManagerError: Error {
    case noMIDIDestination
}

final class CoreMIDIManager {
    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()
    private var destination = MIDIEndpointRef()

    private let channel: UInt8
    private let controlNumber: UInt8
    private let throttleSeconds: CFAbsoluteTime = 0.2
    private var lastSendTime: CFAbsoluteTime = 0

    init(channel: UInt8 = 0, controlNumber: UInt8 = 20) {
        self.channel = channel & 0x0F
        self.controlNumber = controlNumber

        MIDIClientCreate("PoketCoachMIDIClient" as CFString, nil, nil, &client)
        MIDIOutputPortCreate(client, "PoketCoachMIDIPort" as CFString, &outPort)
        destination = resolveDestination()
    }

    deinit {
        MIDIPortDispose(outPort)
        MIDIClientDispose(client)
    }

    func sendDeltaAngle(_ delta: Int) {
        guard delta != 0 else { return }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastSendTime >= throttleSeconds else { return }

        let midiValue = max(0, min(127, 64 + delta))
        sendControlChange(value: UInt8(midiValue))
        lastSendTime = now
    }

    private func resolveDestination() -> MIDIEndpointRef {
        let destinationCount = MIDIGetNumberOfDestinations()
        guard destinationCount > 0 else {
            return MIDIEndpointRef()
        }

        for index in 0..<destinationCount {
            let endpoint = MIDIGetDestination(index)
            if endpoint != MIDIEndpointRef() {
                return endpoint
            }
        }

        return MIDIEndpointRef()
    }

    private func sendControlChange(value: UInt8) {
        guard destination != MIDIEndpointRef() else {
            destination = resolveDestination()
            guard destination != MIDIEndpointRef() else { return }
        }

        let status: UInt8 = 0xB0 | channel
        let data: [UInt8] = [status, controlNumber, value]

        var packetList = MIDIPacketList(numPackets: 1, packet: MIDIPacket())
        withUnsafeMutablePointer(to: &packetList) { packetListPtr in
            let packet = MIDIPacketListInit(packetListPtr)
            _ = MIDIPacketListAdd(packetListPtr, 1024, packet, 0, data.count, data)
            MIDISend(outPort, destination, packetListPtr)
        }
    }
}
