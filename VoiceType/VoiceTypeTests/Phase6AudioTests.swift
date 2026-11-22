import XCTest
@testable import VoiceTypeTests

final class Phase6AudioTests: XCTestCase {
    func testResolveTargetDevicePrefersBuiltInWhenBluetoothSelectedAndToggleEnabled() {
        let bt = AudioInputDevice(id: 10, uid: "bt-1", name: "AirPods", isBuiltIn: false, isBluetooth: true, isDefault: true)
        let mac = AudioInputDevice(id: 20, uid: "mac-1", name: "MacBook Pro Mic", isBuiltIn: true, isBluetooth: false, isDefault: false)
        let devices = [bt, mac]

        let resolvedWithToggleOff = AudioInputDeviceManager.resolveTargetDevice(
            from: devices,
            selectedUID: "",
            preferBuiltInOverBluetooth: false
        )
        XCTAssertEqual(resolvedWithToggleOff?.uid, "bt-1")

        let resolvedWithToggleOn = AudioInputDeviceManager.resolveTargetDevice(
            from: devices,
            selectedUID: "",
            preferBuiltInOverBluetooth: true
        )
        XCTAssertEqual(resolvedWithToggleOn?.uid, "mac-1")
    }

    func testResolveTargetDeviceKeepsExplicitUSBOverBuiltInEvenWhenToggleEnabled() {
        let bt = AudioInputDevice(id: 10, uid: "bt-1", name: "AirPods", isBuiltIn: false, isBluetooth: true, isDefault: true)
        let usb = AudioInputDevice(id: 30, uid: "usb-1", name: "Shure MV7", isBuiltIn: false, isBluetooth: false, isDefault: false)
        let mac = AudioInputDevice(id: 20, uid: "mac-1", name: "MacBook Pro Mic", isBuiltIn: true, isBluetooth: false, isDefault: false)

        let resolved = AudioInputDeviceManager.resolveTargetDevice(
            from: [bt, usb, mac],
            selectedUID: "usb-1",
            preferBuiltInOverBluetooth: true
        )
        XCTAssertEqual(resolved?.uid, "usb-1")
    }

    func testSoundCueBuildsValidRIFFWaveHeader() {
        let data = SoundCuePlayer.buildToneWAV(frequencies: [520, 660], duration: 0.05)
        XCTAssertGreaterThan(data.count, 44)
        XCTAssertEqual(String(data: data.prefix(4), encoding: .ascii), "RIFF")
        XCTAssertEqual(String(data: data[8..<12], encoding: .ascii), "WAVE")
    }
}
