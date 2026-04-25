//
//  ExpressionEvaluator.swift
//  mercantis core
//
//  Created by Kevin Busuttil on 12/04/2026.
//
//  AST-based public façade for the sandboxed expression engine.
//  (ADR-017, P2.1)
//
//  The evaluator is now a two-phase design:
//    1. `ExpressionParser` (string → typed `ExpressionNode` AST)
//    2. The interpreter in this file (AST → `RuntimeValue`)
//
//  Callers continue to use `evaluateBool(expression:context:)` and
//  `evaluateFormula(expression:context:)` exactly as before — those
//  methods now parse, fold constants, cache, and walk the AST. New
//  call sites that want parse-once / evaluate-many behaviour can use
//  `parse(_:)` + `evaluateBool(parsed:context:)` directly.
//

import Foundation

/// Sandboxed expression evaluator for automation rules, visibility
/// conditions, formula fields, and `DocumentEngine.list`'s
/// `whereExpression`. (ADR-004, ADR-008, ADR-017, P2.1)
///
/// Expressions are parsed into a typed `ExpressionNode` AST first and
/// evaluated against a `[String: FieldValue]` context. The AST allows:
///   - **Static field-reference analysis** via `referencedFields(in:)`.
///     `SchemaValidator` uses this to reject DocType installs that
///     reference undeclared fields.
///   - **Constant folding** at parse time, so `2 + 3 * 4` is materialised
///     as `14` once and not re-walked per row.
///   - **Cached parses** — `evaluateBool(expression:context:)` keeps a
///     bounded LRU of recently-seen source strings. Hot paths
///     (`whereExpression` over many rows, automation conditions
///     evaluated on every save) parse the source once.
///   - **Caret-style error messages** — parse errors carry a 0-based
///     source position; `EvaluatorError.parseError` renders them with a
///     pointer.
///
/// The evaluator runs with NO access to the file system, network, or
/// arbitrary Swift APIs. Only the supplied context — and, if a
/// `DocumentLookupResolver` is injected, cross-document `lookup(...)`
/// calls (ADR-029, P2.2) — are in scope. (ADR-008)
///
/// Supported syntax:
///   - Field comparisons: `field == "value"`, `field > 100` …
///   - Boolean operators: `&&`, `||`, `!`
///   - Parentheses for grouping
///   - Arithmetic: `+`, `-`, `*`, `/`, unary `-` / `+`
///   - Literals: `"…"`, numbers, `true`, `false`, `null`
///   - `lookup("DocType", id, "field")` — only when constructed with a
///     `DocumentLookupResolver`; otherwise the call throws.
public final class ExpressionEvaluator: @unchecked Sendable {

    public init(
        parseCacheLimit: Int = 256,
        lookupResolver: DocumentLookupResolver? = nil,
        lookupBudget: Int = 32
    ) {
        self.parseCacheLimit = max(0, parseCacheLimit)
        self.lookupResolver = lookupResolver
        self.lookupBudget = max(0, lookupBudget)
    }

    /// Cross-document resolver for `lookup(...)`. `nil` makes every
    /// `lookup` call throw — the same behaviour as before P2.2.
    public let lookupResolver: DocumentLookupResolver?

    /// Maximum number of `lookup(...)` calls a single top-level
    /// evaluation may make. (ADR-008) Excess calls throw
    /// `EvaluatorError.lookupBudgetExceeded` so a runaway expression
    /// cannot use lookup as an unbounded read amplifier.
    public let lookupBudget: Int

    // MARK: - Public errors

    public enum EvaluatorError: Error, Sendable {
        case unexpectedToken(String)
        case undefinedField(String)
        case typeMismatch(expected: String, got: String)
        case divisionByZero
        /// Source-position-aware parse error. Use `.parseError(_).description`
        /// to render a multi-line caret pointer suitable for log output.
        case parseError(ExpressionParseError)
        /// A `lookup(...)` call was made past the per-evaluation budget
        /// (ADR-008, ADR-029). The cap protects against expressions that
        /// would otherwise issue an unbounded number of cross-document
        /// reads per evaluation.
        case lookupBudgetExceeded(limit: Int)
    }

    // MARK: - Boolean evaluation

    /// Evaluate a boolean expression against a document's field values.
    public func evaluateBool(expression: String, context: [String: FieldValue]) throws -> Bool {
        // Empty / whitespace-only expressions evaluate to `false` — same
        // contract the legacy implementation exposed (matched by the
        // existing test `testEmptyExpressionEvaluatesToFalse`).
        if expression.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return false
        }
        let node = try parsedAndCached(expression)
        return try evaluateBool(parsed: node, context: context)
    }

    /// Evaluate an already-parsed boolean expression.
    public func evaluateBool(parsed: ExpressionNode, context: [String: FieldValue]) throws -> Bool {
        var remaining = lookupBudget
        let result = try walk(parsed, context: context, lookupsRemaining: &remaining)
        return result.asBool
    }

    // MARK: - Formula evaluation

    /// Evaluate a numeric formula expression and return its `FieldValue`.
    /// Numeric results are returned as `.double`. Other result types
    /// throw `typeMismatch` to match the legacy contract — formula
    /// fields are numeric in today's `FieldType` taxonomy.
    public func evaluateFormula(expression: String, context: [String: FieldValue]) throws -> FieldValue {
        let node = try parsedAndCached(expression)
        return try evaluateFormula(parsed: node, context: context)
    }

    /// Evaluate an already-parsed formula expression.
    public func evaluateFormula(parsed: ExpressionNode, context: [String: FieldValue]) throws -> FieldValue {
        var remaining = lookupBudget
        let result = try walk(parsed, context: context, lookupsRemaining: &remaining)
        switch result {
        case .number(let n): return .double(n)
        case .bool(let b):   return .double(b ? 1 : 0)
        case .null:          return .double(0)
        case .string(let s):
            throw EvaluatorError.typeMismatch(expected: "number", got: "string(\"\(s)\")")
        case .undefined(let name):
            // Legacy `parseFactor` threw `undefinedField` whenever an
            // identifier in arithmetic context was missing — preserve
            // that contract for top-level identifier formulas too.
            throw EvaluatorError.undefinedField(name)
        }
    }

    // MARK: - Static analysis (P2.1)

    /// Parse `expression` and return the set of field names it references.
    /// Used by `SchemaValidator` to reject DocTypes whose
    /// `visibilityExpression` / `readOnlyExpression` / `formulaExpression`
    /// (or workflow / automation condition) reference an undeclared field
    /// at install time.
    public func referencedFields(in expression: String) throws -> Set<String> {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let node = try parsedAndCached(expression)
        return node.referencedFields()
    }

    // MARK: - Parsing

    /// Parse `expression` into a reusable AST. Callers that evaluate the
    /// same expression repeatedly (e.g. `whereExpression` over many
    /// rows) should keep the returned node and pass it to the
    /// `parsed:`-based evaluation methods to skip the parse phase.
    ///
    /// Parsed nodes are also cached internally — calling `parse` (or any
    /// of the `expression:` methods) twice with the same source string
    /// hits the cache on the second call.
    public func parse(_ expression: String) throws -> ExpressionNode {
        try parsedAndCached(expression)
    }

    // MARK: - Internal: parse + cache

    private var parseCache: [String: ExpressionNode] = [:]
    private var parseCacheOrder: [String] = []
    private let parseCacheLimit: Int
    private let parseCacheLock = NSLock()

    private func parsedAndCached(_ expression: String) throws -> ExpressionNode {
        if parseCacheLimit > 0 {
            parseCacheLock.lock()
            if let hit = parseCache[expression] {
                parseCacheLock.unlock()
                return hit
            }
            parseCacheLock.unlock()
        }

        var parser = ExpressionParser(source: expression)
        let node: ExpressionNode
        do {
            node = try parser.parse()
        } catch let error as ExpressionParseError {
            // Surface the first unexpected-character / unexpected-token
            // case via `unexpectedToken` for backward-compatibility with
            // existing call sites that match on it (e.g. the
            // `DocumentEngine.list` `whereExpression` regression test).
            // Other parse errors lift through the new `.parseError` case.
            if error.message.hasPrefix("unexpected") {
                throw EvaluatorError.unexpectedToken(error.message)
            }
            throw EvaluatorError.parseError(error)
        }
        let folded = constantFold(node)

        if parseCacheLimit > 0 {
            parseCacheLock.lock()
            // Re-check after acquiring — another thread may have populated.
            if parseCache[expression] == nil {
                parseCache[expression] = folded
                parseCacheOrder.append(expression)
                if parseCacheOrder.count > parseCacheLimit {
                    let evict = parseCacheOrder.removeFirst()
                    parseCache.removeValue(forKey: evict)
                }
            }
            parseCacheLock.unlock()
        }

        return folded
    }

    // MARK: - Constant folding

    /// Walk the AST and replace any subtree that references no fields
    /// with the literal it evaluates to. `2 + 3 * 4` becomes a single
    /// `.literal(.number(14))` node; `status == "Submitted" || true`
    /// becomes `.literal(.bool(true))`. Errors during folding (e.g.
    /// division by zero) are deliberately *not* surfaced at parse time —
    /// they would change the error contract for callers that catch at
    /// evaluation time. We only fold subtrees that succeed.
    private func constantFold(_ node: ExpressionNode) -> ExpressionNode {
        switch node {
        case .literal, .fieldRef:
            return node
        case .unary(let op, let inner, let range):
            let foldedInner = constantFold(inner)
            // `.isConstant` excludes `.call`, so folding never walks a
            // `lookup(...)` — passing a zero budget is safe.
            var unused = 0
            if foldedInner.isConstant,
               let value = try? walk(foldedInner, context: [:], lookupsRemaining: &unused) {
                if let folded = applyUnary(op, value) {
                    return .literal(folded, range)
                }
            }
            return .unary(op, foldedInner, range)
        case .binary(let op, let l, let r, let range):
            let fl = constantFold(l)
            let fr = constantFold(r)
            var unusedL = 0, unusedR = 0
            if fl.isConstant, fr.isConstant,
               let lv = try? walk(fl, context: [:], lookupsRemaining: &unusedL),
               let rv = try? walk(fr, context: [:], lookupsRemaining: &unusedR),
               let folded = applyBinary(op, lv, rv) {
                return .literal(folded, range)
            }
            return .binary(op, fl, fr, range)
        case .call(let name, let args, let range):
            return .call(name: name, args: args.map { constantFold($0) }, range)
        }
    }

    private func applyUnary(_ op: UnaryOperator, _ value: RuntimeValue) -> LiteralValue? {
        switch (op, value) {
        case (.not, _):            return .bool(!value.asBool)
        case (.minus, .number(let n)): return .number(-n)
        case (.plus,  .number(let n)): return .number(n)
        default: return nil
        }
    }

    private func applyBinary(_ op: BinaryOperator, _ l: RuntimeValue, _ r: RuntimeValue) -> LiteralValue? {
        switch op {
        case .add, .sub, .mul, .div:
            // Arithmetic that throws (e.g. division by zero, type
            // mismatch) is preserved as a runtime error — leave the AST
            // unfolded so the same exception raises at evaluation time.
            return (try? performArithmetic(op, l, r)).map { .number($0) }
        case .eq, .ne, .gt, .lt, .ge, .le:
            return (try? performComparison(op, l, r)).map { .bool($0) }
        case .and, .or:
            return (try? performLogical(op, l, r)).map { .bool($0) }
        }
    }

    // MARK: - Interpreter

    /// Internal value type used while walking the AST. Distinct from
    /// `LiteralValue` so we can carry coerced numerics (e.g. dates as
    /// epoch seconds) and preserve the legacy contextual behaviour for
    /// missing fields: a `.fieldRef` whose name is not in the context
    /// resolves to `.undefined(name)` rather than `.null`. The
    /// distinction matters because the legacy evaluator threw
    /// `undefinedField` from the *arithmetic* path but silently returned
    /// `.null` from the *boolean comparison* path. Carrying the name
    /// lets us reproduce both contracts: arithmetic operators detect
    /// `.undefined` and throw, comparisons / truthiness treat it as
    /// indistinguishable from `.null`.
    enum RuntimeValue: Equatable {
        case string(String)
        case number(Double)
        case bool(Bool)
        case null
        case undefined(String)

        var asBool: Bool {
            switch self {
            case .bool(let b):     return b
            case .string(let s):   return !s.isEmpty
            case .number(let n):   return n != 0
            case .null, .undefined: return false
            }
        }
    }

    private func walk(
        _ node: ExpressionNode,
        context: [String: FieldValue],
        lookupsRemaining: inout Int
    ) throws -> RuntimeValue {
        switch node {
        case .literal(let lit, _):
            return literalToRuntime(lit)

        case .fieldRef(let name, _):
            // Dotted identifiers (`user.id`, `user.roles`) are looked up
            // by full key; the permission engine pre-flattens those into
            // the context. Missing fields resolve to `.undefined(name)`
            // — comparisons treat that like `.null`, but arithmetic
            // operators detect it and throw `undefinedField`, matching
            // the legacy contextual behaviour.
            guard let fv = context[name] else { return .undefined(name) }
            return fieldValueToRuntime(fv)

        case .unary(let op, let inner, _):
            let v = try walk(inner, context: context, lookupsRemaining: &lookupsRemaining)
            switch op {
            case .not:
                return .bool(!v.asBool)
            case .minus:
                if case .undefined(let name) = v { throw EvaluatorError.undefinedField(name) }
                guard case .number(let n) = v else {
                    throw EvaluatorError.typeMismatch(expected: "number", got: describe(v))
                }
                return .number(-n)
            case .plus:
                if case .undefined(let name) = v { throw EvaluatorError.undefinedField(name) }
                guard case .number(let n) = v else {
                    throw EvaluatorError.typeMismatch(expected: "number", got: describe(v))
                }
                return .number(n)
            }

        case .binary(let op, let l, let r, _):
            switch op {
            case .and:
                // Short-circuit — matches the legacy behaviour where the
                // RHS of `false && undefinedField` is never evaluated.
                let lv = try walk(l, context: context, lookupsRemaining: &lookupsRemaining)
                if !lv.asBool { return .bool(false) }
                let rv = try walk(r, context: context, lookupsRemaining: &lookupsRemaining)
                return .bool(rv.asBool)
            case .or:
                let lv = try walk(l, context: context, lookupsRemaining: &lookupsRemaining)
                if lv.asBool { return .bool(true) }
                let rv = try walk(r, context: context, lookupsRemaining: &lookupsRemaining)
                return .bool(rv.asBool)
            case .add, .sub, .mul, .div:
                let lv = try walk(l, context: context, lookupsRemaining: &lookupsRemaining)
                let rv = try walk(r, context: context, lookupsRemaining: &lookupsRemaining)
                return .number(try performArithmetic(op, lv, rv))
            case .eq, .ne, .gt, .lt, .ge, .le:
                let lv = try walk(l, context: context, lookupsRemaining: &lookupsRemaining)
                let rv = try walk(r, context: context, lookupsRemaining: &lookupsRemaining)
                return .bool(try performComparison(op, lv, rv))
            }

        case .call(let name, let args, _):
            return try evaluateCall(
                name: name,
                args: args,
                context: context,
                lookupsRemaining: &lookupsRemaining
            )
        }
    }

    // MARK: - Call dispatch (ADR-029, P2.2)

    /// Interpret a `.call` AST node. Only `lookup` is currently
    /// recognised; every other identifier-call pair throws
    /// `unexpectedToken` so unknown calls fail loudly instead of being
    /// silently dropped.
    private func evaluateCall(
        name: String,
        args: [ExpressionNode],
        context: [String: FieldValue],
        lookupsRemaining: inout Int
    ) throws -> RuntimeValue {
        switch name {
        case "lookup":
            guard let resolver = lookupResolver else {
                throw EvaluatorError.unexpectedToken(
                    "call to 'lookup' is not supported in this evaluator"
                )
            }
            guard args.count == 3 else {
                throw EvaluatorError.unexpectedToken(
                    "lookup() requires exactly 3 arguments (docType, name, field)"
                )
            }
            if lookupsRemaining <= 0 {
                throw EvaluatorError.lookupBudgetExceeded(limit: lookupBudget)
            }
            lookupsRemaining -= 1

            let docTypeVal = try walk(args[0], context: context, lookupsRemaining: &lookupsRemaining)
            let nameVal = try walk(args[1], context: context, lookupsRemaining: &lookupsRemaining)
            let fieldVal = try walk(args[2], context: context, lookupsRemaining: &lookupsRemaining)

            guard case .string(let docType) = docTypeVal, !docType.isEmpty else {
                throw EvaluatorError.typeMismatch(
                    expected: "non-empty string for lookup docType",
                    got: describe(docTypeVal)
                )
            }
            // The name argument is the only one that's idiomatically a
            // field reference — `lookup("Item", item_code, "rate")`. A
            // missing or null name resolves to `.null` rather than
            // throwing, so `lookup("Item", optional_link, "rate")` is
            // safe to use in expressions over draft documents.
            let documentName: String
            switch nameVal {
            case .string(let s): documentName = s
            case .null, .undefined: return .null
            default:
                throw EvaluatorError.typeMismatch(
                    expected: "string for lookup name",
                    got: describe(nameVal)
                )
            }
            if documentName.isEmpty { return .null }

            guard case .string(let fieldKey) = fieldVal, !fieldKey.isEmpty else {
                throw EvaluatorError.typeMismatch(
                    expected: "non-empty string for lookup field",
                    got: describe(fieldVal)
                )
            }

            do {
                if let value = try resolver.lookup(docType: docType, name: documentName, field: fieldKey) {
                    return fieldValueToRuntime(value)
                }
                return .null
            } catch {
                // Storage-layer failure is treated as "fail closed →
                // null" so a transient read error doesn't crash an
                // entire form's expression evaluation. Permission /
                // budget decisions surface as their own typed throws
                // above; only the resolver's own errors land here.
                return .null
            }

        default:
            throw EvaluatorError.unexpectedToken("call to '\(name)' is not supported")
        }
    }

    // MARK: - Operators

    private func performArithmetic(_ op: BinaryOperator, _ l: RuntimeValue, _ r: RuntimeValue) throws -> Double {
        // Undefined fields blow up at the arithmetic boundary, matching
        // the legacy `parseFactor` contract (`testUndefinedFieldInFormulaThrows`).
        if case .undefined(let name) = l { throw EvaluatorError.undefinedField(name) }
        if case .undefined(let name) = r { throw EvaluatorError.undefinedField(name) }
        guard case .number(let ln) = numericCoerce(l) else {
            throw EvaluatorError.typeMismatch(expected: "number", got: describe(l))
        }
        guard case .number(let rn) = numericCoerce(r) else {
            throw EvaluatorError.typeMismatch(expected: "number", got: describe(r))
        }
        switch op {
        case .add: return ln + rn
        case .sub: return ln - rn
        case .mul: return ln * rn
        case .div:
            if rn == 0 { throw EvaluatorError.divisionByZero }
            return ln / rn
        default:
            throw EvaluatorError.unexpectedToken(op.rawValue)
        }
    }

    private func performComparison(_ op: BinaryOperator, _ l: RuntimeValue, _ r: RuntimeValue) throws -> Bool {
        switch (l, r) {
        case (.string(let a), .string(let b)):
            switch op {
            case .eq: return a == b
            case .ne: return a != b
            case .gt: return a > b
            case .lt: return a < b
            case .ge: return a >= b
            case .le: return a <= b
            default:  throw EvaluatorError.unexpectedToken(op.rawValue)
            }
        case (.number(let a), .number(let b)):
            switch op {
            case .eq: return a == b
            case .ne: return a != b
            case .gt: return a > b
            case .lt: return a < b
            case .ge: return a >= b
            case .le: return a <= b
            default:  throw EvaluatorError.unexpectedToken(op.rawValue)
            }
        case (.bool(let a), .bool(let b)):
            switch op {
            case .eq: return a == b
            case .ne: return a != b
            default:  throw EvaluatorError.unexpectedToken(op.rawValue)
            }
        case (.null, .null),
             (.null, .undefined),
             (.undefined, .null),
             (.undefined, .undefined):
            return op == .eq
        default:
            // Mixed types: legacy evaluator treats them as not-equal /
            // not-comparable. Preserve `!=` returning true and every
            // other comparison returning false.
            return op == .ne
        }
    }

    private func performLogical(_ op: BinaryOperator, _ l: RuntimeValue, _ r: RuntimeValue) throws -> Bool {
        switch op {
        case .and: return l.asBool && r.asBool
        case .or:  return l.asBool || r.asBool
        default:   throw EvaluatorError.unexpectedToken(op.rawValue)
        }
    }

    // MARK: - Coercion helpers

    private func literalToRuntime(_ lit: LiteralValue) -> RuntimeValue {
        switch lit {
        case .string(let s): return .string(s)
        case .number(let n): return .number(n)
        case .bool(let b):   return .bool(b)
        case .null:          return .null
        }
    }

    /// Map a `FieldValue` into the interpreter's RuntimeValue. The
    /// tagged P1.6 cases (`.date`, `.dateTime`) compare/order as epoch
    /// seconds so `created > 0` and `created < deadline` work without a
    /// dedicated date AST. `.data` and `.array` map to `.null` — they
    /// don't have a meaningful arithmetic / comparison projection.
    private func fieldValueToRuntime(_ value: FieldValue) -> RuntimeValue {
        switch value {
        case .string(let s):       return .string(s)
        case .int(let i):          return .number(Double(i))
        case .double(let d):       return .number(d)
        case .bool(let b):         return .bool(b)
        case .null:                return .null
        case .date(let d), .dateTime(let d):
            return .number(d.timeIntervalSince1970)
        case .data, .array:        return .null
        }
    }

    private func numericCoerce(_ value: RuntimeValue) -> RuntimeValue {
        switch value {
        case .number:        return value
        case .bool(let b):   return .number(b ? 1 : 0)
        case .null:          return .number(0)
        case .string(let s): return .number(Double(s) ?? 0)
        case .undefined:     return value   // surfaces as undefinedField in performArithmetic
        }
    }

    private func describe(_ value: RuntimeValue) -> String {
        switch value {
        case .string(let s):     return "string(\"\(s)\")"
        case .number(let n):     return "number(\(n))"
        case .bool(let b):       return "bool(\(b))"
        case .null:              return "null"
        case .undefined(let n):  return "undefined(\(n))"
        }
    }
}
