import Foundation
import Testing

@testable import MacIsland

@MainActor
struct StopwatchModelTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func runsPausesAndResumes() {
        let stopwatch = StopwatchModel()
        stopwatch.toggle(at: start)
        #expect(stopwatch.elapsed(at: start.addingTimeInterval(10)) == 10)

        stopwatch.toggle(at: start.addingTimeInterval(10))
        #expect(!stopwatch.isRunning && stopwatch.isActive)
        #expect(stopwatch.elapsed(at: start.addingTimeInterval(100)) == 10)

        stopwatch.toggle(at: start.addingTimeInterval(100))
        #expect(stopwatch.elapsed(at: start.addingTimeInterval(105)) == 15)
    }

    @Test func lapsRecordSplitDurations() {
        let stopwatch = StopwatchModel()
        stopwatch.toggle(at: start)
        stopwatch.lap(at: start.addingTimeInterval(30))
        stopwatch.lap(at: start.addingTimeInterval(45))
        #expect(stopwatch.laps == [30, 15])
        #expect(stopwatch.currentLap(at: start.addingTimeInterval(50)) == 5)

        stopwatch.reset()
        #expect(!stopwatch.isActive && stopwatch.laps.isEmpty)
    }

    @Test func formatsTenths() {
        #expect(formatStopwatch(83.47) == "1:23.4")
        #expect(formatStopwatch(0) == "0:00.0")
    }
}

struct AudioAccessoryTests {
    private let json = Data(
        """
        {"SPBluetoothDataType":[{"device_connected":[
          {"Ethan's AirPods Pro":{"device_address":"AA:BB:CC:DD:EE:FF","device_batteryLevelLeft":"80%",
            "device_batteryLevelRight":"75%","device_batteryLevelCase":"60%","device_minorType":"Headphones"}},
          {"Magic Keyboard":{"device_address":"11:22:33:44:55:66","device_batteryLevelMain":"91%"}}
        ]}]}
        """.utf8)

    @Test func readsEarbudAndCaseLevelsByAddress() {
        let accessory = AudioAccessory.parse(
            systemProfilerJSON: json, name: "Ethan's AirPods Pro", address: "aa-bb-cc-dd-ee-ff")
        #expect(accessory.left == 80)
        #expect(accessory.right == 75)
        #expect(accessory.caseLevel == 60)
        #expect(accessory.systemImage == "airpodspro")
        #expect(accessory.batterySummary == "L 80%   R 75%   Case 60%")
    }

    @Test func singleBatteryDevice() {
        let accessory = AudioAccessory.parse(
            systemProfilerJSON: json, name: "Magic Keyboard", address: "11-22-33-44-55-66")
        #expect(accessory.batterySummary == "91%")
    }

    @Test func unknownDeviceHasNoBattery() {
        let accessory = AudioAccessory.parse(systemProfilerJSON: json, name: "Speaker", address: "00-00-00-00-00-00")
        #expect(accessory.batterySummary == nil)
        #expect(accessory.systemImage == "headphones")
    }
}
