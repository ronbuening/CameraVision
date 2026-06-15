import Foundation

struct XMPKeywordMergeOutcome: Equatable {
    var addedFlatKeywords: [String]
    var addedHierarchicalKeywords: [String]
    var resultingFlatKeywords: [String]
    var resultingHierarchicalKeywords: [String]
}

/// Merges planned Phase 2 keywords into managed XMP keyword bags.
struct XMPKeywordMerger {
    private let reader = XMPKeywordReader()

    func preview(plan: XMPChangePlan, snapshot: XMPMetadataSnapshot) -> XMPKeywordMergeOutcome {
        let flat = merge(existing: snapshot.flatKeywords, planned: plan.flatKeywordsToAdd)
        let hierarchical = merge(existing: snapshot.hierarchicalKeywords, planned: plan.hierarchicalKeywordsToAdd)
        return XMPKeywordMergeOutcome(
            addedFlatKeywords: flat.added,
            addedHierarchicalKeywords: hierarchical.added,
            resultingFlatKeywords: flat.resulting,
            resultingHierarchicalKeywords: hierarchical.resulting
        )
    }

    func merge(plan: XMPChangePlan, into parsed: XMPParsedDocument) throws -> XMPKeywordMergeOutcome {
        let flat = merge(
            field: .flat,
            planned: plan.flatKeywordsToAdd,
            into: parsed.descriptionElement
        )
        let hierarchical = merge(
            field: .hierarchical,
            planned: plan.hierarchicalKeywordsToAdd,
            into: parsed.descriptionElement
        )
        return XMPKeywordMergeOutcome(
            addedFlatKeywords: flat.added,
            addedHierarchicalKeywords: hierarchical.added,
            resultingFlatKeywords: flat.resulting,
            resultingHierarchicalKeywords: hierarchical.resulting
        )
    }

    private func merge(
        field: XMPManagedField,
        planned: [PlannedKeyword],
        into description: XMLElement
    ) -> (added: [String], resulting: [String]) {
        let existing = reader.keywords(field: field, in: description)
        let plannedTerms = planned.map(\.term)
        let mergeResult = merge(existing: existing, plannedTerms: plannedTerms)

        guard !mergeResult.added.isEmpty else {
            return mergeResult
        }

        let bag = ensureKeywordBag(field: field, in: description)
        for term in mergeResult.added {
            let item = XMLElement(name: "rdf:li", stringValue: term)
            bag.addChild(item)
        }
        return mergeResult
    }

    private func merge(existing: [String], planned: [PlannedKeyword]) -> (added: [String], resulting: [String]) {
        merge(existing: existing, plannedTerms: planned.map(\.term))
    }

    private func merge(existing: [String], plannedTerms: [String]) -> (added: [String], resulting: [String]) {
        var seen = Set(existing.map { KeywordTextNormalizer.deduplicationKey(for: KeywordTextNormalizer.normalize($0)) })
        var added: [String] = []
        var resulting = existing

        for term in plannedTerms {
            let normalized = KeywordTextNormalizer.normalize(term)
            let key = KeywordTextNormalizer.deduplicationKey(for: normalized)
            guard !key.isEmpty, !seen.contains(key) else {
                continue
            }
            seen.insert(key)
            added.append(term)
            resulting.append(term)
        }

        return (added, resulting)
    }

    private func ensureKeywordBag(field: XMPManagedField, in description: XMLElement) -> XMLElement {
        if let bag = reader.keywordBag(field: field, in: description) {
            return bag
        }

        let property = reader.keywordProperty(field: field, in: description) ?? {
            let property = XMLElement(name: field.qualifiedPropertyName)
            switch field {
            case .flat:
                XMPXML.addNamespace(prefix: "dc", uri: XMPNamespace.dc, to: property)
            case .hierarchical:
                XMPXML.addNamespace(prefix: "lr", uri: XMPNamespace.lr, to: property)
            }
            description.addChild(property)
            return property
        }()

        let bag = XMLElement(name: "rdf:Bag")
        XMPXML.addNamespace(prefix: "rdf", uri: XMPNamespace.rdf, to: bag)
        property.addChild(bag)
        return bag
    }
}
