import Foundation

enum XMPScalarValueForm: Sendable, Equatable {
    case attribute
    case element
}

struct XMPScalarOccurrence: Sendable, Equatable {
    let scalar: XMPManagedScalar
    let value: String
    let form: XMPScalarValueForm
}

enum XMPScalarReader {
    static func read(_ scalar: XMPManagedScalar, in parsed: XMPParsedDocument) throws -> XMPScalarOccurrence? {
        try read(scalar, inRDFElement: parsed.rdfElement, targetPath: parsed.targetPath)
    }

    static func read(_ scalar: XMPManagedScalar, in document: XMLDocument) throws -> XMPScalarOccurrence? {
        guard let root = document.rootElement() else {
            throw XMPXML.sidecarError(
                code: .xmpUnsupportedRDF,
                message: "XMP document has no XML root element."
            )
        }

        let rdfElement: XMLElement?
        if XMPXML.isRDFRoot(root) {
            rdfElement = root
        } else if XMPXML.isXMPMeta(root) {
            rdfElement = XMPXML.elementDescendants(of: root).first(where: XMPXML.isRDFRoot)
        } else {
            rdfElement = nil
        }

        guard let rdfElement else {
            throw XMPXML.sidecarError(
                code: .xmpUnsupportedRDF,
                message: "XMP document does not contain a supported rdf:RDF root."
            )
        }
        return try read(scalar, inRDFElement: rdfElement, targetPath: "<memory>")
    }

    private static func read(
        _ scalar: XMPManagedScalar,
        inRDFElement rdfElement: XMLElement,
        targetPath: String
    ) throws -> XMPScalarOccurrence? {
        let descriptions = XMPXML.elementChildren(of: rdfElement).filter(XMPXML.isRDFDescription)
        var occurrences: [XMPScalarOccurrence] = []

        for description in descriptions {
            for attribute in description.attributes ?? []
            where attribute.xmlLocalName == scalar.localName && attribute.uri == scalar.namespaceURI {
                occurrences.append(
                    XMPScalarOccurrence(
                        scalar: scalar,
                        value: normalizedValue(attribute.stringValue),
                        form: .attribute
                    ))
            }

            for element in XMPXML.elementChildren(of: description)
            where element.xmlLocalName == scalar.localName && element.uri == scalar.namespaceURI {
                guard XMPXML.elementChildren(of: element).isEmpty, (element.attributes ?? []).isEmpty else {
                    throw XMPXML.sidecarError(
                        code: .xmpUnsupportedRDF,
                        message:
                            "XMP sidecar \(targetPath) has unsupported content in \(scalar.qualifiedPropertyName)."
                    )
                }
                occurrences.append(
                    XMPScalarOccurrence(
                        scalar: scalar,
                        value: normalizedValue(element.stringValue),
                        form: .element
                    ))
            }
        }

        guard let first = occurrences.first else {
            return nil
        }

        // Beyond boundary whitespace, equality stays lexical: labels are case-sensitive and numeric spellings
        // are not reinterpreted by the narrow engine.
        guard occurrences.dropFirst().allSatisfy({ $0.value == first.value }) else {
            throw XMPXML.sidecarError(
                code: .xmpUnsupportedRDF,
                message:
                    "XMP sidecar \(targetPath) has conflicting \(scalar.qualifiedPropertyName) values across rdf:Description nodes."
            )
        }
        return first
    }

    private static func normalizedValue(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
