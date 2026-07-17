import Foundation

/// Updates managed scalar properties without changing their existing RDF storage form.
struct XMPScalarMerger {
    func setScalar(_ scalar: XMPManagedScalar, to value: String, in parsed: XMPParsedDocument) throws {
        if try XMPScalarReader.read(scalar, in: parsed) != nil {
            for node in matchingNodes(for: scalar, in: parsed.rdfElement) {
                node.stringValue = value
            }
            return
        }

        try ensurePreferredNamespace(for: scalar, in: parsed)
        XMPXML.addAttribute(name: scalar.qualifiedPropertyName, value: value, to: parsed.descriptionElement)
    }

    private func matchingNodes(for scalar: XMPManagedScalar, in rdfElement: XMLElement) -> [XMLNode] {
        let descriptions = XMPXML.elementChildren(of: rdfElement).filter(XMPXML.isRDFDescription)
        return descriptions.flatMap { description in
            let attributes = (description.attributes ?? []).filter {
                $0.xmlLocalName == scalar.localName && $0.uri == scalar.namespaceURI
            }
            let elements: [XMLNode] = XMPXML.elementChildren(of: description).filter {
                $0.xmlLocalName == scalar.localName && $0.uri == scalar.namespaceURI
            }
            return attributes + elements
        }
    }

    private func ensurePreferredNamespace(for scalar: XMPManagedScalar, in parsed: XMPParsedDocument) throws {
        if let boundURI = namespaceURI(for: scalar.preferredPrefix, inScopeOf: parsed.descriptionElement) {
            guard boundURI == scalar.namespaceURI else {
                throw XMPXML.sidecarError(
                    code: .xmpUnsupportedRDF,
                    message:
                        "XMP sidecar \(parsed.targetPath) binds the \(scalar.preferredPrefix) prefix to an incompatible namespace."
                )
            }
            return
        }

        XMPXML.addNamespace(prefix: scalar.preferredPrefix, uri: scalar.namespaceURI, to: parsed.rdfElement)
    }

    private func namespaceURI(for prefix: String, inScopeOf element: XMLElement) -> String? {
        var current: XMLNode? = element
        while let candidate = current as? XMLElement {
            if let namespace = (candidate.namespaces ?? []).last(where: { $0.name == prefix }) {
                return namespace.stringValue
            }
            current = candidate.parent
        }
        return nil
    }
}
