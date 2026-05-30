//
//  LinkLabel.swift
//  mercantis core
//
//  Display-label resolution for FieldType.link fields. (ADR-030 follow-up)
//
//  Link fields persist the target document's ID as the single source of
//  truth — no denormalised display string is stored, so labels never go
//  stale when the linked record is renamed. The human-facing label is
//  resolved here, at render time, driven by each DocType's declared
//  `titleField`. Centralising this (rather than guessing per-app or
//  per-view) means every link field across every app renders consistently.
//

#if canImport(MercantisCore)
import MercantisCore
#endif

/// Resolves the human-facing display label for a linked document.
public enum LinkLabel {

    /// Display title for `doc`, preferring the target DocType's declared
    /// `titleField`. Falls back to a small set of conventional title keys
    /// (for targets whose meta wasn't resolved), then to the first non-empty
    /// string field, then to the raw id as a last resort.
    public static func title(for doc: Document, meta: DocType?) -> String {
        // 1. Metadata-declared title field — the authoritative choice.
        if let titleField = meta?.titleField,
           let value = string(doc.fields[titleField]), !value.isEmpty {
            return value
        }
        // 2. Conventional title keys — covers targets whose meta wasn't
        //    resolved (e.g. no childDocTypeProvider wired).
        let candidateKeys = ["customer_name", "supplier_name", "item_name",
                             "lead_name", "first_name", "title", "name",
                             "address_title", "label"]
        for key in candidateKeys {
            if let value = string(doc.fields[key]), !value.isEmpty {
                return value
            }
        }
        // 3. First non-empty string field that isn't the id itself.
        for (_, value) in doc.fields {
            if let s = string(value), !s.isEmpty, s != doc.id {
                return s
            }
        }
        // 4. Last resort: the raw id.
        return doc.id
    }

    private static func string(_ value: FieldValue?) -> String? {
        if case .string(let s)? = value { return s }
        return nil
    }
}
