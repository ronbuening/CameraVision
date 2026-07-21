import Foundation

/// Shared encoding, atomic-write, and error-wrapping behavior for report artifacts.
enum WriterSupport {
    typealias DataWriter = (Data, URL, FileManager) throws -> Void

    static func writeAndWrap<Value: Encodable>(
        _ value: Value,
        to path: String,
        encoder: JSONEncoder,
        typeName: String,
        fileManager: FileManager,
        dataWriter: DataWriter = atomicWrite
    ) throws {
        try writeAndWrap(
            to: path,
            typeName: typeName,
            fileManager: fileManager,
            dataWriter: dataWriter
        ) {
            try encoder.encode(value)
        }
    }

    static func writeAndWrap(
        _ data: @autoclosure () throws -> Data,
        to path: String,
        typeName: String,
        fileManager: FileManager,
        dataWriter: DataWriter = atomicWrite
    ) throws {
        try writeAndWrap(
            to: path,
            typeName: typeName,
            fileManager: fileManager,
            dataWriter: dataWriter,
            makeData: data
        )
    }

    static func atomicWrite(_ data: Data, to destination: URL, fileManager: FileManager) throws {
        try AtomicFileWriter.write(data, to: destination, fileManager: fileManager)
    }

    private static func writeAndWrap(
        to path: String,
        typeName: String,
        fileManager: FileManager,
        dataWriter: DataWriter,
        makeData: () throws -> Data
    ) throws {
        do {
            try dataWriter(try makeData(), URL(fileURLWithPath: path), fileManager)
        } catch let error as SidecarError {
            throw error
        } catch {
            throw SidecarError(
                code: .writeFailed,
                stage: .write,
                message: "Unable to \(typeName) \(path): \(error.localizedDescription)",
                recoverable: true
            )
        }
    }
}
