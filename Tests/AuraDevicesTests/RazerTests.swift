import AuraCore
import Foundation
import Testing
@testable import AuraDevices

final class FakeTransport: ReportTransport, @unchecked Sendable {
    private(set) var sent: [[UInt8]] = []
    var reply: [UInt8]?

    func send(_ report: [UInt8], index: UInt16) throws {
        sent.append(report)
    }

    func receive(length: Int, index: UInt16) throws -> [UInt8] {
        if let reply { return reply }
        // Echo the last request back with status "success".
        var echo = sent.last ?? [UInt8](repeating: 0, count: length)
        echo[0] = RazerPacket.Status.success.rawValue
        return echo
    }
}

@Suite struct RazerPacketTests {
    @Test func layoutAndChecksum() {
        let report = RazerPacket.make(transactionID: 0x1F, commandClass: 0x0F, commandID: 0x04, dataSize: 0x03,
                                      arguments: [0x01, 0x05, 0xFF])
        #expect(report.count == 90)
        #expect(Array(report[0..<11]) == [0x00, 0x1F, 0x00, 0x00, 0x00, 0x03, 0x0F, 0x04, 0x01, 0x05, 0xFF])
        // Known values from OpenRazer: brightness 01 05 FF → crc 0xF3; custom effect → 0x09; firmware → 0x83.
        #expect(report[88] == 0xF3)
        #expect(RazerPacket.customFrameEffect(transactionID: 0x1F)[88] == 0x09)
        #expect(RazerPacket.firmwareVersion(transactionID: 0x1F)[88] == 0x83)
        #expect(report[89] == 0)
    }

    @Test func checksumIgnoresStatusAndTransactionID() {
        var a = RazerPacket.spectrumEffect(transactionID: 0x1F, led: 0x05)
        let crc = a[88]
        a[0] = 0x02
        a[1] = 0x3F
        #expect(RazerPacket.crc(a) == crc)
    }

    @Test func customFrameRowForAFullKeyboardRow() {
        let colors = (0..<22).map { RGB8(UInt8($0), 0x80, 0xFF) }
        let report = RazerPacket.customFrameRow(transactionID: 0x1F, row: 3, startColumn: 0, colors: colors[...])
        #expect(report[5] == 0x47)
        #expect(Array(report[6..<13]) == [0x0F, 0x03, 0x00, 0x00, 0x03, 0x00, 0x15])
        #expect(Array(report[13..<16]) == [0x00, 0x80, 0xFF])
        #expect(Array(report[13 + 21 * 3..<16 + 21 * 3]) == [21, 0x80, 0xFF])
    }

    @Test func spectrumMatchesOpenRazerBytes() {
        let report = RazerPacket.spectrumEffect(transactionID: 0x1F, led: 0x05)
        #expect(Array(report[0..<14]) == [0x00, 0x1F, 0x00, 0x00, 0x00, 0x06, 0x0F, 0x02, 0x01, 0x05, 0x03, 0x00, 0x00, 0x00])
        #expect(report[88] == 0x0C)
    }

    @Test func responseMatching() throws {
        let request = RazerPacket.firmwareVersion(transactionID: 0x1F)
        var bytes = request
        bytes[0] = 0x02
        bytes[8] = 1
        bytes[9] = 4
        let response = try #require(RazerResponse(bytes))
        #expect(response.answers(request))
        #expect(!response.answers(RazerPacket.customFrameEffect(transactionID: 0x1F)))
        #expect(RazerResponse([0x00]) == nil)
    }
}

@Suite struct RazerCatalogTests {
    @Test func builtInModelsHaveTheRightLayouts() {
        let byID = Dictionary(uniqueKeysWithValues: RazerCatalog.builtIn.map { ($0.productID, $0) })
        #expect(byID[0x025E]?.makeLayout().frameLength == 132)
        #expect(byID[0x0085]?.makeLayout().frameLength == 2)
        #expect(byID[0x0C04]?.makeLayout().frameLength == 19)
        #expect(byID[0x0C04]?.transactionID == 0x3F)
        #expect(byID[0x025E]?.controlIndex == 0x01)
    }

    @Test func keyboardMapHasNoDuplicates() {
        let keys = RazerKeyboardMap.fullSize
        #expect(Set(keys.map(\.keyCode)).count == keys.count)
        #expect(Set(keys.map { $0.row * 22 + $0.column }).count == keys.count)
        #expect(keys.allSatisfy { $0.row < 6 && $0.column >= 1 && $0.column < 22 })
        let layout = RazerLayouts.keyboard(rows: 6, columns: 22)
        #expect(layout.leds.compactMap(\.keyCode).count == keys.count)
        // Esc top-left, Space on the bottom row.
        #expect(layout.leds.first { $0.keyCode == 53 }?.slot == 1)
        #expect(layout.leds.first { $0.keyCode == 49 }?.slot == 5 * 22 + 7)
    }

    @Test func fireflyLEDsSitOnTheEdgeStartingTopRightOfCentre() {
        let layout = RazerLayouts.fireflyV2()
        let first = layout.leds[0].position
        #expect(first.y == 0 && first.x > layout.size.x / 2)
        // Counter-clockwise: the next LED is further left along the top edge.
        #expect(layout.leds[1].position.x < first.x)
        for led in layout.leds {
            #expect(led.perimeter! >= 0 && led.perimeter! < 1)
        }
    }

    @Test func perimeterParameterRoundTrips() {
        let size = SIMD2<Float>(355, 255)
        for t in stride(from: Float(0.01), to: 1, by: 0.07) {
            let p = DeviceLayout.pointOnPerimeter(t, size: size)
            #expect(abs(RazerLayouts.perimeterParameter(p, size: size) - t) < 0.001)
        }
    }

    @Test func userDescriptorsLoadFromJSON() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let json = """
        {"productID": 4660, "name": "Razer Test Strip", "kind": "strip", "rows": 1, "columns": 12,
         "transactionID": 31, "controlIndex": 0, "ledIDs": [0], "driverMode": false, "layoutStyle": "matrix"}
        """
        try Data(json.utf8).write(to: directory.appendingPathComponent("strip.json"))
        let catalog = RazerCatalog.load(userDirectory: directory)
        #expect(catalog[0x1234]?.name == "Razer Test Strip")
        #expect(catalog[0x025E] != nil)
    }
}

@Suite struct RazerDeviceTests {
    func makeKeyboard() -> (RazerDevice, FakeTransport) {
        let transport = FakeTransport()
        let descriptor = RazerCatalog.builtIn.first { $0.productID == 0x025E }!
        return (RazerDevice(descriptor: descriptor, transport: transport, id: "kb", detail: ""), transport)
    }

    @Test func writesOnlyChangedRowsThenTheEffect() throws {
        let (device, transport) = makeKeyboard()
        var frame = [RGB8](repeating: RGB8(10, 0, 0), count: 132)
        try device.write(frame)
        #expect(transport.sent.count == 7) // 6 rows + custom-frame effect
        #expect(transport.sent.last == RazerPacket.customFrameEffect(transactionID: 0x1F))

        try device.write(frame)
        #expect(transport.sent.count == 7) // nothing changed, nothing sent

        frame[2 * 22 + 5] = RGB8(0, 255, 0)
        try device.write(frame)
        #expect(transport.sent.count == 9) // row 2 + effect
        #expect(transport.sent[7][10] == 2)
    }

    @Test func prepareResetsDiffAndSetsBrightness() throws {
        let (device, transport) = makeKeyboard()
        let frame = [RGB8](repeating: .black, count: 132)
        try device.write(frame)
        try device.prepare()
        #expect(transport.sent.last == RazerPacket.brightness(transactionID: 0x1F, led: 0x05, value: 0xFF))
        try device.write(frame)
        #expect(transport.sent.count == 7 + 1 + 7)
    }

    @Test func fireflyUsesDriverModeAndRestoresIt() throws {
        let transport = FakeTransport()
        let descriptor = RazerCatalog.builtIn.first { $0.productID == 0x0C04 }!
        let device = RazerDevice(descriptor: descriptor, transport: transport, id: "mat", detail: "")
        try device.prepare()
        #expect(transport.sent.first == RazerPacket.deviceMode(transactionID: 0x3F, mode: 0x03))
        device.shutdown(.staticColor, color: RGB8(1, 2, 3))
        #expect(transport.sent.suffix(2) == [
            RazerPacket.staticEffect(transactionID: 0x3F, led: 0x00, color: RGB8(1, 2, 3)),
            RazerPacket.deviceMode(transactionID: 0x3F, mode: 0x00),
        ])
    }

    @Test func mouseShutdownTouchesBothZones() {
        let transport = FakeTransport()
        let descriptor = RazerCatalog.builtIn.first { $0.productID == 0x0085 }!
        let device = RazerDevice(descriptor: descriptor, transport: transport, id: "mouse", detail: "")
        device.shutdown(.spectrum, color: .black)
        #expect(transport.sent == [
            RazerPacket.spectrumEffect(transactionID: 0x1F, led: 0x01),
            RazerPacket.spectrumEffect(transactionID: 0x1F, led: 0x04),
        ])
    }

    @Test func firmwareVersionParsesReply() throws {
        let (device, transport) = makeKeyboard()
        var reply = RazerPacket.firmwareVersion(transactionID: 0x1F)
        reply[0] = 0x02
        reply[8] = 1
        reply[9] = 4
        transport.reply = reply
        #expect(try device.firmwareVersion() == "1.4")
    }
}
