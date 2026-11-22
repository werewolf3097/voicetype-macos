import CoreAudio
import Foundation

struct AudioInputDevice: Identifiable, Equatable, Hashable, Sendable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let isBuiltIn: Bool
    let isBluetooth: Bool
    let isDefault: Bool
}

enum AudioInputDeviceManager {
    static func availableInputDevices() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceIDs
        ) == noErr else {
            return []
        }

        var devices: [AudioInputDevice] = []
        for id in deviceIDs where hasInputChannels(deviceID: id) {
            guard let uid = stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceUID),
                  let name = stringProperty(deviceID: id, selector: kAudioDevicePropertyDeviceNameCFString) else {
                continue
            }
            let transport = transportType(deviceID: id)
            let isBuiltIn = transport == kAudioDeviceTransportTypeBuiltIn
            let isBluetooth = transport == kAudioDeviceTransportTypeBluetooth
                || transport == kAudioDeviceTransportTypeBluetoothLE
            devices.append(
                AudioInputDevice(
                    id: id,
                    uid: uid,
                    name: name,
                    isBuiltIn: isBuiltIn,
                    isBluetooth: isBluetooth,
                    isDefault: id == defaultID
                )
            )
        }

        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
            if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func resolveTargetDevice(
        from devices: [AudioInputDevice],
        selectedUID: String,
        preferBuiltInOverBluetooth: Bool
    ) -> AudioInputDevice? {
        let explicit = selectedUID.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen: AudioInputDevice?
        if !explicit.isEmpty, let match = devices.first(where: { $0.uid == explicit }) {
            chosen = match
        } else {
            chosen = devices.first(where: { $0.isDefault }) ?? devices.first
        }

        if preferBuiltInOverBluetooth,
           let current = chosen,
           current.isBluetooth,
           let builtIn = devices.first(where: { $0.isBuiltIn }) {
            return builtIn
        }
        return chosen
    }

    static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != 0 else {
            return nil
        }
        return deviceID
    }

    private static func hasInputChannels(deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(size),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawBuffer) == noErr else {
            return false
        }
        let bufferList = UnsafeMutableAudioBufferListPointer(rawBuffer.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func transportType(deviceID: AudioDeviceID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var transport: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &transport) == noErr else {
            return 0
        }
        return transport
    }

    private static func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr,
              let cfString = value?.takeRetainedValue() else {
            return nil
        }
        return cfString as String
    }
}
