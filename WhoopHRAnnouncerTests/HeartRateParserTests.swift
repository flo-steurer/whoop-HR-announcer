import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import WhoopHRAnnouncerCore
#else
@testable import HR_Announcer
#endif

struct HeartRateParserTests {
    @Test func parsesEightBitHeartRate() {
        #expect(HeartRatePacketParser.parse(Data([0x00, 145])) == 145)
    }

    @Test func parsesLittleEndianSixteenBitHeartRate() {
        #expect(HeartRatePacketParser.parse(Data([0x01, 0x2C, 0x01])) == 300)
    }

    @Test func rejectsTruncatedAndZeroValues() {
        #expect(HeartRatePacketParser.parse(Data()) == nil)
        #expect(HeartRatePacketParser.parse(Data([0x00])) == nil)
        #expect(HeartRatePacketParser.parse(Data([0x01, 0x90])) == nil)
        #expect(HeartRatePacketParser.parse(Data([0x00, 0x00])) == nil)
    }
}
