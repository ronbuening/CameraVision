import Foundation

/// Reads the Phase 2 managed keyword bags from a parsed XMP document.
struct XMPKeywordReader {
    func flatKeywords(in parsed: XMPParsedDocument) -> [String] {
        keywords(field: .flat, in: parsed.descriptionElement)
    }

    func hierarchicalKeywords(in parsed: XMPParsedDocument) -> [String] {
        keywords(field: .hierarchical, in: parsed.descriptionElement)
    }

    func keywords(field: XMPManagedField, in description: XMLElement) -> [String] {
        guard let bag = keywordBag(field: field, in: description) else {
            return []
        }
        return XMPXML.elementChildren(of: bag)
            .filter(XMPXML.isRDFListItem)
            .compactMap(\.stringValue)
    }

    func keywordProperty(field: XMPManagedField, in description: XMLElement) -> XMLElement? {
        XMPXML.elementChildren(of: description).first {
            $0.xmlLocalName == field.propertyLocalName && $0.uri == field.namespaceURI
        }
    }

    func keywordBag(field: XMPManagedField, in description: XMLElement) -> XMLElement? {
        guard let property = keywordProperty(field: field, in: description) else {
            return nil
        }
        return XMPXML.elementChildren(of: property).first(where: XMPXML.isRDFBag)
    }
}
