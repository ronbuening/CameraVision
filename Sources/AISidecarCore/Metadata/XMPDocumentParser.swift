import Foundation

/// Parses the narrow XMP/RDF sidecar shapes supported by the owned Phase 2 engine.
struct XMPDocumentParser {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func parseFile(at targetXMPPath: String, sourceFileNames: [String] = []) throws -> XMPParsedDocument {
        let url = URL(fileURLWithPath: targetXMPPath)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw XMPXML.sidecarError(
                code: .xmpParseFailed,
                message: "Unable to read XMP sidecar \(url.standardizedFileURL.path): \(error.localizedDescription)"
            )
        }
        return try parse(
            data: data,
            targetPath: url.standardizedFileURL.path,
            sourceFileNames: sourceFileNames
        )
    }

    func parse(data: Data, targetPath: String, sourceFileNames: [String] = []) throws -> XMPParsedDocument {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [.nodePreserveAll])
        } catch {
            throw XMPXML.sidecarError(
                code: .xmpParseFailed,
                message: "Unable to parse XMP sidecar \(targetPath): \(error.localizedDescription)",
                diagnostic: String(data: data.prefix(XMPXML.diagnosticLimit), encoding: .utf8)
            )
        }

        return try parse(document: document, targetPath: targetPath, sourceFileNames: sourceFileNames)
    }

    func copy(_ parsed: XMPParsedDocument, sourceFileNames: [String] = []) throws -> XMPParsedDocument {
        guard let document = parsed.document.copy() as? XMLDocument else {
            throw XMPXML.sidecarError(
                code: .xmpParseFailed,
                message: "Unable to copy parsed XMP sidecar \(parsed.targetPath)."
            )
        }
        return try parse(
            document: document,
            targetPath: parsed.targetPath,
            sourceFileNames: sourceFileNames
        )
    }

    private func parse(
        document: XMLDocument,
        targetPath: String,
        sourceFileNames: [String]
    ) throws -> XMPParsedDocument {
        guard let root = document.rootElement() else {
            throw XMPXML.sidecarError(
                code: .xmpParseFailed,
                message: "XMP sidecar \(targetPath) has no XML root element."
            )
        }

        let rdfElement = try locateRDFElement(root: root, targetPath: targetPath)
        try validateManagedRDFShapes(in: rdfElement, targetPath: targetPath)
        let descriptionElement = try locateOrCreateWritableDescription(
            in: rdfElement,
            targetPath: targetPath,
            sourceFileNames: sourceFileNames
        )
        return XMPParsedDocument(
            document: document,
            rdfElement: rdfElement,
            descriptionElement: descriptionElement,
            targetPath: targetPath
        )
    }

    private func locateRDFElement(root: XMLElement, targetPath: String) throws -> XMLElement {
        if XMPXML.isRDFRoot(root) {
            return root
        }
        if XMPXML.isXMPMeta(root),
            let rdf = XMPXML.elementDescendants(of: root).first(where: XMPXML.isRDFRoot)
        {
            return rdf
        }
        throw XMPXML.sidecarError(
            code: .xmpUnsupportedRDF,
            message: "XMP sidecar \(targetPath) does not contain a supported rdf:RDF root."
        )
    }

    private func validateManagedRDFShapes(in rdfElement: XMLElement, targetPath: String) throws {
        let descriptions = directDescriptions(in: rdfElement)
        var descriptionsWithManagedFields: [XMLElement] = []

        for description in descriptions {
            // Managed keyword attributes require RDF shorthand expansion this
            // narrow engine deliberately does not perform in Phase 2.
            if (description.attributes ?? []).contains(where: XMPXML.isManagedAttribute) {
                throw XMPXML.sidecarError(
                    code: .xmpUnsupportedRDF,
                    message: "XMP sidecar \(targetPath) stores a managed keyword field as an RDF attribute."
                )
            }

            let managedChildren = XMPXML.elementChildren(of: description).filter(XMPXML.isManagedProperty)
            if !managedChildren.isEmpty {
                descriptionsWithManagedFields.append(description)
            }
            try validateManagedChildren(managedChildren, targetPath: targetPath)
        }

        if descriptionsWithManagedFields.count > 1 {
            throw XMPXML.sidecarError(
                code: .xmpUnsupportedRDF,
                message: "XMP sidecar \(targetPath) has managed keyword fields in multiple rdf:Description nodes."
            )
        }

        // Managed fields nested away from direct rdf:Description children are
        // treated as unsafe because merging them could rewrite unintended RDF.
        let directManaged = Set(managedChildrenIdentity(in: descriptions))
        for managed in XMPXML.elementDescendants(of: rdfElement).filter(XMPXML.isManagedProperty) {
            if !directManaged.contains(ObjectIdentifier(managed)) {
                throw XMPXML.sidecarError(
                    code: .xmpUnsupportedRDF,
                    message:
                        "XMP sidecar \(targetPath) has a managed keyword field outside a direct rdf:Description child."
                )
            }
        }
    }

    private func validateManagedChildren(_ managedChildren: [XMLElement], targetPath: String) throws {
        for field in XMPManagedField.allCases {
            let properties = managedChildren.filter {
                $0.xmlLocalName == field.propertyLocalName && $0.uri == field.namespaceURI
            }
            if properties.count > 1 {
                throw XMPXML.sidecarError(
                    code: .xmpUnsupportedRDF,
                    message: "XMP sidecar \(targetPath) has multiple \(field.qualifiedPropertyName) properties."
                )
            }
            if let property = properties.first {
                try validateManagedBag(property: property, field: field, targetPath: targetPath)
            }
        }
    }

    private func validateManagedBag(property: XMLElement, field: XMPManagedField, targetPath: String) throws {
        let elementChildren = XMPXML.elementChildren(of: property)
        guard elementChildren.count == 1, let bag = elementChildren.first, XMPXML.isRDFBag(bag) else {
            throw XMPXML.sidecarError(
                code: .xmpUnsupportedRDF,
                message: "XMP sidecar \(targetPath) has unsupported \(field.qualifiedPropertyName) content."
            )
        }

        let nonWhitespaceText = (property.children ?? []).contains { child in
            guard child.kind == .text else {
                return false
            }
            return child.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        if nonWhitespaceText {
            throw XMPXML.sidecarError(
                code: .xmpUnsupportedRDF,
                message: "XMP sidecar \(targetPath) has unsupported text inside \(field.qualifiedPropertyName)."
            )
        }

        for child in XMPXML.elementChildren(of: bag) {
            guard XMPXML.isRDFListItem(child),
                XMPXML.elementChildren(of: child).isEmpty,
                (child.attributes ?? []).isEmpty
            else {
                throw XMPXML.sidecarError(
                    code: .xmpUnsupportedRDF,
                    message:
                        "XMP sidecar \(targetPath) has unsupported rdf:li content in \(field.qualifiedPropertyName)."
                )
            }
        }
    }

    private func locateOrCreateWritableDescription(
        in rdfElement: XMLElement,
        targetPath: String,
        sourceFileNames: [String]
    ) throws -> XMLElement {
        let descriptions = directDescriptions(in: rdfElement)
        if let withManaged = descriptions.first(where: containsManagedChild) {
            return withManaged
        }
        if let sourceMatch = descriptions.first(where: { description in
            guard let about = rdfAboutValue(description) else {
                return false
            }
            return sourceFileNames.contains { sourceFileName in
                rdfAbout(about, namesSourceFile: sourceFileName)
            }
        }) {
            return sourceMatch
        }
        if let aboutEmpty = descriptions.first(where: { rdfAboutValue($0) == "" }) {
            return aboutEmpty
        }
        if let first = descriptions.first {
            return first
        }

        let description = XMLElement(name: "rdf:Description")
        XMPXML.addAttribute(name: "rdf:about", value: "", to: description)
        rdfElement.addChild(description)
        return description
    }

    private func directDescriptions(in rdfElement: XMLElement) -> [XMLElement] {
        XMPXML.elementChildren(of: rdfElement).filter(XMPXML.isRDFDescription)
    }

    private func containsManagedChild(_ description: XMLElement) -> Bool {
        XMPXML.elementChildren(of: description).contains(where: XMPXML.isManagedProperty)
    }

    private func rdfAboutValue(_ description: XMLElement) -> String? {
        XMPXML.firstAttributeValue(on: description, namespaceURI: XMPNamespace.rdf, localName: "about")
    }

    private func rdfAbout(_ value: String, namesSourceFile sourceFileName: String) -> Bool {
        // Literal comparison first: a plain (non-URI) about value may contain
        // characters URL parsing would percent-decode or truncate (%, #, ?).
        let literalComponent = value.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init)
        if literalComponent == sourceFileName {
            return true
        }
        if let component = URL(string: value)?.lastPathComponent, !component.isEmpty {
            if component == sourceFileName {
                return true
            }
        }

        // Some third-party packets carry Windows paths rather than URI syntax.
        // Compare their terminal component without accepting suffix lookalikes.
        guard value.contains("\\") else {
            return false
        }
        let path = value.replacingOccurrences(of: "\\", with: "/")
        return path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) == sourceFileName
    }

    private func managedChildrenIdentity(in descriptions: [XMLElement]) -> [ObjectIdentifier] {
        descriptions
            .flatMap { XMPXML.elementChildren(of: $0).filter(XMPXML.isManagedProperty) }
            .map(ObjectIdentifier.init)
    }
}
