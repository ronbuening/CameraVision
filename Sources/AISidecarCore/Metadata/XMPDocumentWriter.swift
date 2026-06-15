import Foundation

/// Serializes new and updated XMP documents for the owned sidecar engine.
struct XMPDocumentWriter {
    func makeNewDocument(targetPath: String, includeHierarchicalBag: Bool) -> XMPParsedDocument {
        let xmpMeta = XMLElement(name: "x:xmpmeta", uri: XMPNamespace.x)
        XMPXML.addNamespace(prefix: "x", uri: XMPNamespace.x, to: xmpMeta)

        let rdf = XMLElement(name: "rdf:RDF", uri: XMPNamespace.rdf)
        XMPXML.addNamespace(prefix: "rdf", uri: XMPNamespace.rdf, to: rdf)
        XMPXML.addNamespace(prefix: "dc", uri: XMPNamespace.dc, to: rdf)
        XMPXML.addNamespace(prefix: "lr", uri: XMPNamespace.lr, to: rdf)

        let description = XMLElement(name: "rdf:Description", uri: XMPNamespace.rdf)
        XMPXML.addAttribute(name: "rdf:about", value: "", to: description)
        rdf.addChild(description)
        xmpMeta.addChild(rdf)

        ensureKeywordBag(field: .flat, in: description)
        if includeHierarchicalBag {
            ensureKeywordBag(field: .hierarchical, in: description)
        }

        let document = XMLDocument(rootElement: xmpMeta)
        document.version = "1.0"
        document.characterEncoding = "UTF-8"
        return XMPParsedDocument(
            document: document,
            rdfElement: rdf,
            descriptionElement: description,
            targetPath: targetPath
        )
    }

    func data(for parsed: XMPParsedDocument) throws -> Data {
        parsed.document.xmlData(options: [.nodePrettyPrint])
    }

    @discardableResult
    private func ensureKeywordBag(field: XMPManagedField, in description: XMLElement) -> XMLElement {
        let property = XMLElement(name: field.qualifiedPropertyName, uri: field.namespaceURI)
        let bag = XMLElement(name: "rdf:Bag", uri: XMPNamespace.rdf)
        property.addChild(bag)
        description.addChild(property)
        return bag
    }
}
