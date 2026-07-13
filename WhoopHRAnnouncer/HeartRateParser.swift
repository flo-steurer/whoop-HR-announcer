import Foundation

enum HeartRatePacketParser {
    static func parse(_ data: Data) -> Int? {
        guard data.count >= 2 else { return nil }

        let flags = data[data.startIndex]
        let usesUInt16 = flags & 0x01 != 0
        let valueIndex = data.index(after: data.startIndex)

        if usesUInt16 {
            guard data.distance(from: valueIndex, to: data.endIndex) >= 2 else { return nil }
            let low = UInt16(data[valueIndex])
            let highIndex = data.index(after: valueIndex)
            let high = UInt16(data[highIndex]) << 8
            let value = Int(low | high)
            return value > 0 ? value : nil
        }

        let value = Int(data[valueIndex])
        return value > 0 ? value : nil
    }
}
