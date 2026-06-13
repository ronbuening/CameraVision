import Foundation

enum XMPNamespace {
    static let x = "adobe:ns:meta/"
    static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    static let dc = "http://purl.org/dc/elements/1.1/"
    static let lr = "http://ns.adobe.com/lightroom/1.0/"
}

enum XMPManagedField: CaseIterable {
    case flat
    case hierarchical

    var namespaceURI: String {
        switch self {
        case .flat: XMPNamespace.dc
        case .hierarchical: XMPNamespace.lr
        }
    }

    var propertyLocalName: String {
        switch self {
        case .flat: "subject"
        case .hierarchical: "hierarchicalSubject"
        }
    }

    var qualifiedPropertyName: String {
        switch self {
        case .flat: "dc:subject"
        case .hierarchical: "lr:hierarchicalSubject"
        }
    }
}

final class XMPParsedDocument {
    let document: XMLDocument
    let rdfElement: XMLElement
    let descriptionElement: XMLElement
    let targetPath: String

    init(document: XMLDocument, rdfElement: XMLElement, descriptionElement: XMLElement, targetPath: String) {
        self.document = document
        self.rdfElement = rdfElement
        self.descriptionElement = descriptionElement
        self.targetPath = targetPath
    }
}

enum XMPXML {
    static let diagnosticLimit = 240

    static func isXMPMeta(_ element: XMLElement) -> Bool {
        element.xmlLocalName == "xmpmeta" && element.uri == XMPNamespace.x
    }

    static func isRDFRoot(_ element: XMLElement) -> Bool {
        element.xmlLocalName == "RDF" && element.uri == XMPNamespace.rdf
    }

    static func isRDFDescription(_ element: XMLElement) -> Bool {
        element.xmlLocalName == "Description" && element.uri == XMPNamespace.rdf
    }

    static func isRDFBag(_ element: XMLElement) -> Bool {
        element.xmlLocalName == "Bag" && element.uri == XMPNamespace.rdf
    }

    static func isRDFListItem(_ element: XMLElement) -> Bool {
        element.xmlLocalName == "li" && element.uri == XMPNamespace.rdf
    }

    static func isManagedProperty(_ element: XMLElement) -> Bool {
        XMPManagedField.allCases.contains {
            element.xmlLocalName == $0.propertyLocalName && element.uri == $0.namespaceURI
        }
    }

    static func isManagedAttribute(_ attribute: XMLNode) -> Bool {
        XMPManagedField.allCases.contains {
            attribute.xmlLocalName == $0.propertyLocalName && attribute.uri == $0.namespaceURI
        }
    }

    static func elementChildren(of element: XMLElement) -> [XMLElement] {
        (element.children ?? []).compactMap { $0 as? XMLElement }
    }

    static func elementDescendants(of element: XMLElement) -> [XMLElement] {
        elementChildren(of: element).flatMap { child in
            [child] + elementDescendants(of: child)
        }
    }

    static func firstAttributeValue(on element: XMLElement, namespaceURI: String, localName: String) -> String? {
        (element.attributes ?? []).first {
            $0.xmlLocalName == localName && $0.uri == namespaceURI
        }?.stringValue
    }

    static func addNamespace(prefix: String, uri: String, to element: XMLElement) {
        element.addNamespace(XMLNode.namespace(withName: prefix, stringValue: uri) as! XMLNode)
    }

    static func addAttribute(name: String, value: String, to element: XMLElement) {
        element.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }

    static func sidecarError(
        code: SidecarErrorCode,
        message: String,
        diagnostic: String? = nil,
        recoverable: Bool = true
    ) -> SidecarError {
        let boundedDiagnostic = diagnostic.map(bounded)
        let fullMessage = boundedDiagnostic.map { "\(message) Diagnostic: \($0)" } ?? message
        return SidecarError(code: code, stage: .write, message: fullMessage, recoverable: recoverable)
    }

    static func bounded(_ value: String) -> String {
        let normalized = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        if normalized.count <= diagnosticLimit {
            return normalized
        }
        return "\(normalized.prefix(diagnosticLimit))..."
    }
}

extension XMLNode {
    var xmlLocalName: String {
        if let localName, !localName.isEmpty {
            return localName
        }
        guard let name else {
            return ""
        }
        return name.split(separator: ":").last.map(String.init) ?? name
    }
}
