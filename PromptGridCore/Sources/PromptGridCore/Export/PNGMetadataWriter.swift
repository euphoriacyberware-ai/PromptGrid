//
//  PNGMetadataWriter.swift
//  PromptGridCore
//
//  Embeds XMP metadata into a PNG, matching Draw Things' own convention
//  (Specification §11.1): a PNG `iTXt` chunk with keyword `XML:com.adobe.xmp`,
//  written through `CGImageMetadata` / ImageIO — not a hand-rolled tEXt chunk.
//  We reuse the container shape but populate it with our own fields.
//
//  `CGImageDestinationCopyImageSource` copies the original image bytes verbatim
//  and merges the metadata, so the pixels are never recompressed.
//

import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum PNGMetadataWriter {

    public struct Payload: Sendable, Equatable {
        /// `xmp:CreatorTool` — this app (not "Draw Things"; we didn't generate
        /// the pixels through their export path).
        public var creatorTool: String
        /// `dc:description` — resolved prompt + a human-readable settings line.
        public var description: String
        /// `exif:UserComment` — our own JSON blob.
        public var userComment: String

        public init(creatorTool: String, description: String, userComment: String) {
            self.creatorTool = creatorTool
            self.description = description
            self.userComment = userComment
        }
    }

    public enum WriterError: Swift.Error, Equatable {
        case unreadableImage
        case metadataFailed(String)
        case destinationFailed
    }

    private static let xmpNamespace = "http://ns.adobe.com/xap/1.0/"
    private static let dcNamespace = "http://purl.org/dc/elements/1.1/"
    private static let exifNamespace = "http://ns.adobe.com/exif/1.0/"

    /// Return a copy of `pngData` with the XMP metadata embedded.
    public static func embedding(_ payload: Payload, into pngData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw WriterError.unreadableImage
        }

        let metadata = CGImageMetadataCreateMutable()
        try set(metadata, prefix: "xmp", namespace: xmpNamespace, tag: "CreatorTool", value: payload.creatorTool)
        try set(metadata, prefix: "dc", namespace: dcNamespace, tag: "description", value: payload.description)
        try set(metadata, prefix: "exif", namespace: exifNamespace, tag: "UserComment", value: payload.userComment)

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else { throw WriterError.destinationFailed }

        // The API §11.1 names — writes XMP into a PNG iTXt chunk (lossless re-encode).
        CGImageDestinationAddImageAndMetadata(destination, image, metadata, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw WriterError.destinationFailed
        }
        return output as Data
    }

    private static func set(_ metadata: CGMutableImageMetadata, prefix: String,
                            namespace: String, tag: String, value: String) throws {
        CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, prefix as CFString, nil)
        guard CGImageMetadataSetValueWithPath(metadata, nil, "\(prefix):\(tag)" as CFString, value as CFString) else {
            throw WriterError.metadataFailed(tag)
        }
    }

    /// Read an XMP value back (round-trip helper; the reader is a near-free
    /// follow-on to the writer per §11.1, useful for tests).
    public static func readValue(prefix: String, tag: String, from pngData: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil),
              let value = CGImageMetadataCopyStringValueWithPath(metadata, nil, "\(prefix):\(tag)" as CFString)
        else { return nil }
        return value as String
    }
}
