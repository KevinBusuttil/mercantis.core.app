import Foundation

/// Friendly presentation of a DocType's `module` for end users. The raw module
/// keys are mostly real words ("Selling", "Accounting"), but a couple read as
/// jargon ("CRM", "Capture") — those get a plain-language label. The shared
/// hint demystifies the module chip itself, which would otherwise be an
/// unexplained badge to someone new to the product.
enum ModuleDisplay {

    static func label(_ module: String) -> String {
        switch module {
        case "CRM":     return "Contacts & CRM"
        case "Capture": return "Document Capture"
        default:        return module
        }
    }

    static let hint = "Shows which part of your business this record belongs to."
}
