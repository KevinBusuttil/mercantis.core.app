//
//  MetaComposer.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 19/04/2026.
//

import Foundation

/// Composes a `ResolvedMeta` object by merging three layers. (ADR-021)
///
/// 1. **Base definition** — the `DocType` as declared in the app manifest or `doctypes` table.
/// 2. **Custom fields** — user-added `CustomField` records, appended at their declared
///    `insertAfter` position.
/// 3. **Property overrides** — `PropertySetter` records applied to matching fields to
///    override individual properties (label, hidden, readOnly, default, options, etc.).
///
/// The result is a `ResolvedMeta` — the authoritative runtime representation of the DocType.
/// `ResolvedMeta` is cached in-memory (keyed by docType name) and invalidated when any of
/// the three layers changes.
///
/// **All runtime consumers use `ResolvedMeta`, not raw `DocType`.**
public final class MetaComposer {

    private let registry: MetadataRegistry
    private var cache: [String: ResolvedMeta] = [:]
    private var cacheGeneration: [String: Int] = [:]
    private var globalGeneration: Int = 0

    /// Externally supplied custom fields, keyed by DocType name.
    private var customFieldsByDocType: [String: [CustomField]] = [:]

    /// Externally supplied property setters, keyed by DocType name.
    private var propertySettersByDocType: [String: [PropertySetter]] = [:]

    public init(registry: MetadataRegistry) {
        self.registry = registry
    }

    // MARK: - Custom Field / Property Setter Management

    /// Set the custom fields for a given DocType. Invalidates the cache for that DocType.
    public func setCustomFields(_ fields: [CustomField], for docType: String) {
        customFieldsByDocType[docType] = fields
        invalidateCache(for: docType)
    }

    /// Set the property setters for a given DocType. Invalidates the cache for that DocType.
    public func setPropertySetters(_ setters: [PropertySetter], for docType: String) {
        propertySettersByDocType[docType] = setters
        invalidateCache(for: docType)
    }

    // MARK: - Resolution

    /// Resolve the effective runtime metadata for a DocType.
    ///
    /// Returns a cached `ResolvedMeta` if available and still valid; otherwise
    /// composes a fresh one from the three layers.
    public func resolve(docType docTypeName: String) -> ResolvedMeta? {
        // Return cached if valid.
        if let cached = cache[docTypeName],
           cacheGeneration[docTypeName] == globalGeneration {
            return cached
        }

        guard let baseDocType = registry.get(docTypeName) else {
            return nil
        }

        let resolved = compose(base: baseDocType)
        cache[docTypeName] = resolved
        cacheGeneration[docTypeName] = globalGeneration
        return resolved
    }

    /// Resolve all registered DocTypes into their `ResolvedMeta` representations.
    public func resolveAll() -> [ResolvedMeta] {
        registry.all().compactMap { resolve(docType: $0.id) }
    }

    // MARK: - Cache Invalidation

    /// Invalidate the cached `ResolvedMeta` for a specific DocType.
    public func invalidateCache(for docType: String) {
        cache.removeValue(forKey: docType)
        cacheGeneration.removeValue(forKey: docType)
    }

    /// Invalidate the entire cache (e.g. after a schema change).
    public func invalidateAll() {
        cache.removeAll()
        cacheGeneration.removeAll()
        globalGeneration += 1
    }

    // MARK: - Composition

    private func compose(base: DocType) -> ResolvedMeta {
        // Step 1: Convert base fields to resolved fields.
        var resolvedFields = base.fields.map { resolveField($0, isCustom: false) }

        // Step 2: Merge custom fields at their insertAfter positions.
        let customFields = customFieldsByDocType[base.id] ?? []
        for customField in customFields {
            let resolved = resolveField(customField.fieldDefinition, isCustom: true)
            if let insertAfter = customField.insertAfter,
               !insertAfter.isEmpty,
               let index = resolvedFields.firstIndex(where: { $0.key == insertAfter }) {
                resolvedFields.insert(resolved, at: resolvedFields.index(after: index))
            } else {
                resolvedFields.append(resolved)
            }
        }

        // Step 3: Apply property setters.
        let setters = propertySettersByDocType[base.id] ?? []
        for setter in setters {
            if let index = resolvedFields.firstIndex(where: { $0.key == setter.fieldKey }) {
                resolvedFields[index] = applyPropertySetter(setter, to: resolvedFields[index])
            }
        }

        return ResolvedMeta(
            docTypeName: base.id,
            displayName: base.name,
            module: base.module,
            appId: base.appId,
            fields: resolvedFields,
            permissionRules: base.permissions,
            syncPolicy: base.syncPolicy,
            indexDefinitions: base.indexes,
            workflowId: base.workflowId,
            isSubmittable: base.isSubmittable,
            isSingle: base.isSingle,
            isChildTable: base.isChildTable,
            isCustom: base.isCustom,
            titleField: base.titleField,
            searchFields: base.searchFields,
            autoname: base.autoname
        )
    }

    private func resolveField(_ field: FieldDefinition, isCustom: Bool) -> ResolvedFieldDefinition {
        ResolvedFieldDefinition(
            key: field.key,
            label: field.label,
            type: field.type,
            isRequired: field.isRequired,
            defaultValue: field.defaultValue,
            options: field.options,
            linkedDocType: field.linkedDocType,
            childDocType: field.childDocType,
            validationRules: field.validationRules,
            visibilityExpression: field.visibilityExpression,
            readOnlyExpression: field.readOnlyExpression,
            formulaExpression: field.formulaExpression,
            permissions: field.permissions,
            isSearchable: field.isSearchable,
            isSynced: field.isSynced,
            allowOnSubmit: field.allowOnSubmit,
            isCustom: isCustom,
            section: field.section,
            column: field.column
        )
    }

    private func applyPropertySetter(
        _ setter: PropertySetter,
        to field: ResolvedFieldDefinition
    ) -> ResolvedFieldDefinition {
        var label = field.label
        var defaultValue = field.defaultValue
        var options = field.options
        var visibilityExpression = field.visibilityExpression
        var readOnlyExpression = field.readOnlyExpression

        switch setter.property {
        case "label":
            label = setter.value
        case "default":
            defaultValue = .string(setter.value)
        case "options":
            options = setter.value.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
        case "hidden":
            // "hidden" = "true" means visibilityExpression = "false"
            if setter.value.lowercased() == "true" {
                visibilityExpression = "false"
            } else {
                visibilityExpression = nil
            }
        case "readOnly", "read_only":
            if setter.value.lowercased() == "true" {
                readOnlyExpression = "true"
            } else {
                readOnlyExpression = nil
            }
        default:
            break
        }

        return ResolvedFieldDefinition(
            key: field.key,
            label: label,
            type: field.type,
            isRequired: field.isRequired,
            defaultValue: defaultValue,
            options: options,
            linkedDocType: field.linkedDocType,
            childDocType: field.childDocType,
            validationRules: field.validationRules,
            visibilityExpression: visibilityExpression,
            readOnlyExpression: readOnlyExpression,
            formulaExpression: field.formulaExpression,
            permissions: field.permissions,
            isSearchable: field.isSearchable,
            isSynced: field.isSynced,
            allowOnSubmit: field.allowOnSubmit,
            isCustom: field.isCustom,
            section: field.section,
            column: field.column
        )
    }
}
