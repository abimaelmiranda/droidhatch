import Foundation

struct AndroidApkManifestReader {
    private enum BinaryXml {
        static let fileHeaderSize = 8
        static let chunkHeaderSize = 8
        static let chunkTypeOffset = 0
        static let chunkSizeOffset = 4
        static let startElementChunkType: UInt16 = 0x0102
        static let stringPoolChunkType: UInt16 = 0x0001
        static let startElementNameOffset = 20
        static let elementHeaderSize = 16
        static let attributeStartOffset = 24
        static let attributeSizeOffset = 26
        static let attributeCountOffset = 28
        static let attributeMinimumSize = 20
        static let attributeNameOffset = 4
        static let attributeRawValueOffset = 8
        static let attributeValueTypeOffset = 15
        static let attributeValueOffset = 16
        static let stringValueType: UInt8 = 0x03
        static let noStringIndex = UInt32.max
        static let stringCountOffset = 8
        static let stringPoolFlagsOffset = 16
        static let stringDataOffset = 20
        static let stringOffsetsOffset = 28
        static let utf8Flag: UInt32 = 0x00000100
        static let utf8ContinuationMask: UInt8 = 0x80
        static let utf8LengthMask: UInt8 = 0x7F
        static let utf16ContinuationMask: UInt16 = 0x8000
        static let utf16LengthMask: UInt16 = 0x7FFF
        static let uint16ByteWidth = 2
        static let uint32ByteWidth = 4

    }

    func readPackageName(from apkURL: URL) throws -> String {
        let manifest = try readManifest(from: apkURL)
        let strings = try readStringPool(from: manifest)
        var offset = BinaryXml.fileHeaderSize

        while offset + BinaryXml.chunkHeaderSize <= manifest.count {
            let chunkType = readUInt16(manifest, at: offset + BinaryXml.chunkTypeOffset)
            let chunkSize = Int(
                readUInt32(manifest, at: offset + BinaryXml.chunkSizeOffset))
            guard chunkSize >= BinaryXml.chunkHeaderSize,
                  offset + chunkSize <= manifest.count else {
                throw error("AndroidManifest.xml contém um chunk inválido.")
            }

            if chunkType == BinaryXml.startElementChunkType {
                let elementName = try getString(
                    strings,
                    index: readUInt32(manifest, at: offset + BinaryXml.startElementNameOffset))
                if elementName == "manifest" {
                    return try readPackageAttribute(from: manifest, chunkOffset: offset, strings: strings)
                }
            }
            offset += chunkSize
        }

        throw error("O manifesto não contém o elemento manifest.")
    }

    private func readManifest(from apkURL: URL) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", apkURL.path, "AndroidManifest.xml"]
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0, !data.isEmpty else {
            let detail = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8)
            if let detail, !detail.isEmpty {
                throw error(detail)
            }
            throw error("O APK não contém AndroidManifest.xml.")
        }
        return data
    }

    private func readPackageAttribute(
        from data: Data,
        chunkOffset: Int,
        strings: [String]) throws -> String {
        let attributeStart = Int(
            readUInt16(data, at: chunkOffset + BinaryXml.attributeStartOffset))
        let attributeSize = Int(
            readUInt16(data, at: chunkOffset + BinaryXml.attributeSizeOffset))
        let attributeCount = Int(
            readUInt16(data, at: chunkOffset + BinaryXml.attributeCountOffset))
        guard attributeSize >= BinaryXml.attributeMinimumSize else {
            throw error("O manifesto contém atributos inválidos.")
        }
        let attributesOffset = chunkOffset + BinaryXml.elementHeaderSize + attributeStart

        for index in 0..<attributeCount {
            let attributeOffset = attributesOffset + index * attributeSize
            guard attributeOffset + BinaryXml.attributeMinimumSize <= data.count else {
                throw error("O manifesto contém um atributo truncado.")
            }
            let name = try getString(
                strings,
                index: readUInt32(data, at: attributeOffset + BinaryXml.attributeNameOffset))
            guard name == "package" else { continue }

            let rawValue = readUInt32(
                data,
                at: attributeOffset + BinaryXml.attributeRawValueOffset)
            if rawValue != BinaryXml.noStringIndex {
                return try getString(strings, index: rawValue)
            }

            guard data[attributeOffset + BinaryXml.attributeValueTypeOffset]
                    == BinaryXml.stringValueType else {
                throw error("O atributo package não é uma string.")
            }
            return try getString(
                strings,
                index: readUInt32(data, at: attributeOffset + BinaryXml.attributeValueOffset))
        }

        throw error("O manifesto não declara um package válido.")
    }

    private func readStringPool(from data: Data) throws -> [String] {
        var offset = BinaryXml.fileHeaderSize
        while offset + BinaryXml.chunkHeaderSize <= data.count {
            let chunkType = readUInt16(data, at: offset + BinaryXml.chunkTypeOffset)
            let chunkSize = Int(
                readUInt32(data, at: offset + BinaryXml.chunkSizeOffset))
            guard chunkSize >= BinaryXml.chunkHeaderSize,
                  offset + chunkSize <= data.count else {
                throw error("AndroidManifest.xml contém um string pool inválido.")
            }
            if chunkType == BinaryXml.stringPoolChunkType {
                return try decodeStringPool(data, offset: offset)
            }
            offset += chunkSize
        }
        throw error("AndroidManifest.xml não contém um string pool.")
    }

    private func decodeStringPool(_ data: Data, offset: Int) throws -> [String] {
        let count = Int(readUInt32(data, at: offset + BinaryXml.stringCountOffset))
        let flags = readUInt32(data, at: offset + BinaryXml.stringPoolFlagsOffset)
        let stringsStart = Int(readUInt32(data, at: offset + BinaryXml.stringDataOffset))
        let offsetsStart = offset + BinaryXml.stringOffsetsOffset
        let stringDataStart = offset + stringsStart
        let isUTF8 = flags & BinaryXml.utf8Flag != 0

        guard offsetsStart + count * BinaryXml.uint32ByteWidth <= data.count else {
            throw error("O string pool contém offsets inválidos.")
        }

        return try (0..<count).map { index in
            let relativeOffset = Int(
                readUInt32(
                    data,
                    at: offsetsStart + index * BinaryXml.uint32ByteWidth))
            let stringOffset = stringDataStart + relativeOffset
            return try isUTF8
                ? readUTF8String(data, offset: stringOffset)
                : readUTF16String(data, offset: stringOffset)
        }
    }

    private func readUTF8String(_ data: Data, offset: Int) throws -> String {
        var cursor = offset
        _ = try readUTF8Length(data, cursor: &cursor)
        let byteLength = Int(try readUTF8Length(data, cursor: &cursor))
        guard cursor + byteLength <= data.count else {
            throw error("String UTF-8 truncada no manifesto.")
        }
        guard let value = String(
            data: data.subdata(in: cursor..<(cursor + byteLength)),
            encoding: .utf8) else {
            throw error("String UTF-8 inválida no manifesto.")
        }
        return value
    }

    private func readUTF16String(_ data: Data, offset: Int) throws -> String {
        var cursor = offset
        let characterLength = Int(try readUTF16Length(data, cursor: &cursor))
        let byteLength = characterLength * 2
        guard cursor + byteLength <= data.count else {
            throw error("String UTF-16 truncada no manifesto.")
        }
        guard let value = String(
            data: data.subdata(in: cursor..<(cursor + byteLength)),
            encoding: .utf16LittleEndian) else {
            throw error("String UTF-16 inválida no manifesto.")
        }
        return value
    }

    private func readUTF8Length(_ data: Data, cursor: inout Int) throws -> UInt32 {
        guard cursor < data.count else { throw error("Comprimento UTF-8 inválido.") }
        let first = data[cursor]
        cursor += 1
        if first & BinaryXml.utf8ContinuationMask == 0 { return UInt32(first) }
        guard cursor < data.count else { throw error("Comprimento UTF-8 truncado.") }
        let second = data[cursor]
        cursor += 1
        return UInt32(first & BinaryXml.utf8LengthMask) << 8 | UInt32(second)
    }

    private func readUTF16Length(_ data: Data, cursor: inout Int) throws -> UInt32 {
        let first = try readUInt16Checked(data, at: cursor)
        cursor += 2
        if first & BinaryXml.utf16ContinuationMask == 0 { return UInt32(first) }
        let second = try readUInt16Checked(data, at: cursor)
        cursor += 2
        return UInt32(first & BinaryXml.utf16LengthMask) << 16 | UInt32(second)
    }

    private func getString(_ strings: [String], index: UInt32) throws -> String {
        guard index < UInt32(strings.count) else {
            throw error("O manifesto referencia uma string inexistente.")
        }
        return strings[Int(index)]
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
    }

    private func readUInt16Checked(_ data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + BinaryXml.uint16ByteWidth <= data.count else {
            throw error("Leitura UTF-16 fora dos limites.")
        }
        return readUInt16(data, at: offset)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }

    private func error(_ message: String) -> NSError {
        NSError(
            domain: "DroidHatchGUI.APK",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message])
    }
}
