import Foundation

struct Diagnostic: CustomStringConvertible {
    enum Severity: String { case error = "Error", warning = "Warning" }
    let severity: Severity
    let message: String
    let line: Int

    var description: String {
        severity == .error ? "Error: line \(line): \(message)"
                           : "Warning: line \(line): \(message)"
    }
}

final class Checker {
    private(set) var diagnostics: [Diagnostic] = []

    private var prototypes: [String: PrototypeNode] = [:]
    private var globals: [String: ShalimarType] = [:]
    private var scopes: [[String: ShalimarType]] = []
    private var currentPrototype: PrototypeNode?

    var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }

    private var seen: Set<String> = []

    private func report(_ severity: Diagnostic.Severity, _ message: String, _ line: Int) {
        let key = "\(severity.rawValue)\u{1}\(line)\u{1}\(message)"
        guard seen.insert(key).inserted else { return }
        diagnostics.append(Diagnostic(severity: severity, message: message, line: line))
    }

    private func error(_ message: String, _ line: Int) { report(.error, message, line) }
    private func warn(_ message: String, _ line: Int) { report(.warning, message, line) }

    private struct Builtin {
        let inputs: [ShalimarType]
        let output: ShalimarType
        let generic: Bool
    }

    private static let unary  = Builtin(inputs: [.real], output: .real, generic: false)
    private static let binary = Builtin(inputs: [.real, .real], output: .real, generic: false)

    private static let builtins: [String: Builtin] = [
        "abs": unary, "sqrt": unary, "log": unary,
        "sin": unary, "cos": unary, "tan": unary,
        "asin": unary, "acos": unary, "atan": unary,
        "round": unary, "ceil": unary, "floor": unary,
        "atan2": binary, "pow": binary,
        "max": Builtin(inputs: [.real, .real], output: .real, generic: true),
        "min": Builtin(inputs: [.real, .real], output: .real, generic: true),
        "len": Builtin(inputs: [.array(.real)], output: .int, generic: true),
        "int":  Builtin(inputs: [.real], output: .int, generic: false),
        "real": Builtin(inputs: [.int], output: .real, generic: false),
        "char": Builtin(inputs: [.int], output: .char, generic: false),
    ]

    // Read-only and reserved: 'pi' cannot be declared, assigned, or taken as a parameter
    // name. 2.x resolved constants last, behind locals and globals, so a variable of the
    // same name shadowed them - but with a checker that defines on first assignment, that
    // arrangement means 'pi : 3' silently overwrites the constant instead of shadowing it.
    // One name, one meaning, and a diagnostic that says so.
    private static let constants: [String: ShalimarType] = ["pi": .real]

    // The three conversions are handled as a group: each takes any scalar and produces
    // the type it is named for. Their declared input types above exist only to give the
    // arity check something to count - checkBuiltinCall never coerces to them.
    private static let conversions: [String: ShalimarType] = [
        "int": .int, "real": .real, "char": .char,
    ]

    func check(_ program: [Node]) -> [Node] {
        collectPrototypes(program)
        collectGlobals(program)

        guard let main = prototypes["main"] else {
            error("No main() function defined", program.last.flatMap { ($0 as? StmtNode)?.line } ?? 1)
            return program
        }
        if !main.inputs.isEmpty {
            error("main() must take no inputs", main.line)
        }

        let called = collectCalledNames(program)
        for name in prototypes.keys.sorted() where name != "main" && !called.contains(name) {
            warn("'\(name)' is never called", prototypes[name]?.line ?? 1)
        }

        return program.map { node in
            guard let function = node as? FunctionNode else { return node }
            return checkFunction(function)
        }
    }

    private func collectPrototypes(_ program: [Node]) {
        for case let function as FunctionNode in program {
            let name = function.prototype.name
            if let existing = prototypes[name] {
                error("Function '\(name)' already defined (line \(existing.line))", function.line)
                continue
            }
            if Checker.builtins[name] != nil {
                error("'\(name)' is a built-in name", function.line)
                continue
            }
            // The parser reads 'prec(' in a print list as the precision directive before
            // it could ever resolve to this function, so the definition would be silently
            // unreachable there. Refuse it rather than let the two spellings diverge.
            if name.lowercased() == "prec" {
                error("'prec' is reserved for '? prec(n)'", function.line)
                continue
            }
            prototypes[name] = function.prototype
        }
    }

    private func collectGlobals(_ program: [Node]) {
        for case let declaration as DeclareNode in program {
            if refuseConstant(declaration.name, "declared", declaration.line) { continue }
            if globals[declaration.name] != nil {
                error("Variable '\(declaration.name)' already defined", declaration.line)
                continue
            }
            checkDeclaredType(declaration)
            globals[declaration.name] = declaration.type
        }
    }

    private func collectCalledNames(_ program: [Node]) -> Set<String> {
        var names: Set<String> = []
        func walk(_ node: Node?) {
            switch node {
            case let n as FunctionNode:       n.body.forEach(walk)
            case let n as CallNode:           names.insert(n.callee); n.arguments.forEach(walk)
            case let n as AssignNode:         walk(n.expr)
            case let n as CompoundAssignNode: walk(n.expr)
            case let n as MultiAssignNode:    walk(n.call)
            case let n as DeclareNode:        n.sizes.forEach(walk); walk(n.initial)
            case let n as ReturnNode:         n.exprs.forEach(walk)
            case let n as PrintNode:          n.items.forEach(walk)
            case let n as IfNode:
                n.branches.forEach { walk($0.condition); $0.body.forEach(walk) }
                n.elseBody?.forEach(walk)
            case let n as WhileNode:          walk(n.condition); n.body.forEach(walk)
            case let n as ForNode:
                walk(n.start); walk(n.end); walk(n.step); n.body.forEach(walk)
            case let n as BinaryOpNode:       walk(n.lhs); walk(n.rhs)
            case let n as IndexNode:          walk(n.base); walk(n.index)
            case let n as DimNode:            walk(n.base); walk(n.axis)
            case let n as PrecisionNode:      walk(n.places)
            case let n as ArrayLiteralNode:   n.elements.forEach(walk)
            default: break
            }
        }
        program.forEach(walk)
        return names
    }

    private func lookup(_ name: String) -> ShalimarType? {
        for scope in scopes.reversed() {
            if let type = scope[name] { return type }
        }
        return globals[name] ?? Checker.constants[name]
    }

    // Returns true (having reported) when a name is a constant being reused as a variable.
    private func refuseConstant(_ name: String, _ role: String, _ line: Int) -> Bool {
        guard Checker.constants[name] != nil else { return false }
        error("'\(name)' is a constant", line)
        return true
    }

    private func isLocal(_ name: String) -> Bool {
        scopes.contains { $0[name] != nil }
    }

    private func define(_ name: String, _ type: ShalimarType) {
        guard !scopes.isEmpty else { globals[name] = type; return }
        scopes[scopes.count - 1][name] = type
    }

    private func checkDeclaredType(_ declaration: DeclareNode) {
        guard declaration.type.isWellFormed else {
            error("'\(declaration.name)': \(declaration.type)"
                  + (declaration.type.scalar == .char ? " - strings are 1-D" : " is not a legal type"),
                  declaration.line)
            return
        }
    }

    private func checkFunction(_ function: FunctionNode) -> FunctionNode {
        currentPrototype = function.prototype
        scopes = [[:]]
        defer { currentPrototype = nil; scopes = [] }

        for parameter in function.prototype.inputs {
            _ = refuseConstant(parameter.name, "used as a parameter name", function.line)
            if scopes[0][parameter.name] != nil {
                error("Parameter '\(parameter.name)' already defined", function.line)
            }
            if !parameter.type.isWellFormed {
                error("'\(parameter.name)': \(parameter.type) is not a legal type", function.line)
            }
            scopes[0][parameter.name] = parameter.type
        }

        let body = function.body.map { checkStatement($0) }

        if !function.prototype.outputs.isEmpty && !alwaysReturns(body) {
            error("'\(function.prototype.name)' can finish without a return", function.line)
        }

        return FunctionNode(prototype: function.prototype, body: body)
    }

    private func alwaysReturns(_ body: [StmtNode]) -> Bool {
        for statement in body {
            if statement is ReturnNode { return true }
            if let ifNode = statement as? IfNode,
               let elseBody = ifNode.elseBody,
               ifNode.branches.allSatisfy({ alwaysReturns($0.body) }),
               alwaysReturns(elseBody) {
                return true
            }
        }
        return false
    }

    private func checkStatement(_ statement: StmtNode) -> StmtNode {
        switch statement {
        case let node as DeclareNode:        return checkDeclaration(node)
        case let node as AssignNode:         return checkAssign(node)
        case let node as CompoundAssignNode: return checkCompoundAssign(node)
        case let node as MultiAssignNode:    return checkMultiAssign(node)
        case let node as ReturnNode:         return checkReturn(node)
        case let node as PrintNode:          return checkPrint(node)
        case let node as CallNode:           return checkCall(node, line: node.line).call
        case let node as IfNode:             return checkIf(node)
        case let node as WhileNode:          return checkWhile(node)
        case let node as ForNode:            return checkFor(node)
        default:                             return statement
        }
    }

    private func checkDeclaration(_ node: DeclareNode) -> StmtNode {
        checkDeclaredType(node)

        if refuseConstant(node.name, "declared", node.line) {
            return node
        }
        if isLocal(node.name) {
            error("Variable '\(node.name)' already defined", node.line)
        } else if globals[node.name] != nil {
            warn("'\(node.name)' hides a global", node.line)
        }

        let sizes = node.sizes.map { checkSize($0, of: node.name, line: node.line) }
        var initial = node.initial
        if let value = initial {
            initial = coerce(value, to: node.type, line: node.line)
        }
        define(node.name, node.type)

        return DeclareNode(type: node.type, name: node.name, sizes: sizes,
                           initial: initial, line: node.line)
    }

    private func checkSize(_ expr: ExprNode, of name: String, line: Int) -> ExprNode {
        let inferred = infer(expr, line: line)
        guard inferred == .int else {
            error("'\(name)': size must be int, not \(inferred)", line)
            return rewrite(expr, line: line)
        }

        let checked = rewrite(expr, line: line)
        if let constant = constantInt(checked), constant < 1 {
            error("'\(name)': size must be 1 or more, got \(constant)", line)
        }
        return checked
    }

    private func constantInt(_ expr: ExprNode) -> Int? {
        if let int = expr as? IntNode { return int.value }
        guard let binary = expr as? BinaryOpNode,
              let lhs = constantInt(binary.lhs),
              let rhs = constantInt(binary.rhs) else { return nil }
        switch binary.op {
        case .add:      return lhs + rhs
        case .subtract: return lhs - rhs
        case .multiply: return lhs * rhs
        default:        return nil
        }
    }

    private func checkAssign(_ node: AssignNode) -> StmtNode {
        let target = resolveTarget(node.target, line: node.line)
        if refuseConstant(target.root, "assigned to", node.line) { return node }

        guard let targetType = target.type else {
            let type = infer(node.expr, line: node.line)
            if type.rank > 0 && type.scalar != .char {
                error("Declare the array '\(target.root)' first", node.line)
            }
            define(target.root, type)
            return AssignNode(target: node.target, op: node.op,
                              expr: coerce(node.expr, to: type, line: node.line), line: node.line)
        }

        return AssignNode(target: node.target, op: node.op,
                          expr: coerce(node.expr, to: targetType, line: node.line), line: node.line)
    }

    private func checkCompoundAssign(_ node: CompoundAssignNode) -> StmtNode {
        let target = resolveTarget(node.target, line: node.line)
        if refuseConstant(target.root, "assigned to", node.line) { return node }
        guard let targetType = target.type else {
            error("Undefined variable '\(target.root)'", node.line)
            return node
        }
        // '+:' on a string appends, which is how one gets built in a loop. '-:' has no
        // meaning there, and neither does either operator on any other array.
        if targetType == .array(.char) {
            guard node.op == .add else {
                error("'\(node.op.rawValue)' does not apply to strings", node.line)
                return node
            }
            return CompoundAssignNode(target: node.target, op: node.op,
                                      expr: coerce(node.expr, to: .array(.char), line: node.line),
                                      line: node.line)
        }

        if targetType.rank > 0 {
            error("'\(node.op.rawValue)' needs a single value", node.line)
        }
        return CompoundAssignNode(target: node.target, op: node.op,
                                  expr: coerce(node.expr, to: targetType, line: node.line),
                                  line: node.line)
    }

    private func checkMultiAssign(_ node: MultiAssignNode) -> StmtNode {
        let (call, callType) = checkCall(node.call, line: node.line)

        guard let prototype = prototypes[node.call.callee] else {
            // A builtin has no PrototypeNode, but it still returns exactly one value, and
            // '<s> : sqrt(16.)' still has to define 's'. Falling straight through here left
            // the target undeclared and the next line reporting it as undefined.
            if Checker.builtins[node.call.callee] != nil {
                if node.targets.count != 1 {
                    error("'\(node.call.callee)' returns 1, not \(node.targets.count)", node.line)
                }
                if let first = node.targets.first {
                    let resolved = resolveTarget(first, line: node.line)
                    if resolved.type == nil { define(resolved.root, callType) }
                }
            }
            return MultiAssignNode(targets: node.targets, call: call, line: node.line)
        }
        if prototype.returnCount != node.targets.count {
            error("'\(prototype.name)' returns \(prototype.returnCount), not \(node.targets.count)", node.line)
        }
        for (i, target) in node.targets.enumerated() where i < prototype.outputs.count {
            let resolved = resolveTarget(target, line: node.line)
            if let existing = resolved.type {
                if existing != prototype.outputs[i] {
                    error("'\(resolved.root)' is \(existing), not \(prototype.outputs[i])", node.line)
                }
            } else {
                define(resolved.root, prototype.outputs[i])
            }
        }
        return MultiAssignNode(targets: node.targets, call: call, line: node.line)
    }

    private func checkReturn(_ node: ReturnNode) -> StmtNode {
        let prototype = node.prototype

        guard node.exprs.count == prototype.returnCount else {
            error("'\(prototype.name)' returns \(prototype.returnCount) values, not \(node.exprs.count)",
                  node.line)
            return node
        }
        let exprs = zip(node.exprs, prototype.outputs).map { coerce($0, to: $1, line: node.line) }
        return ReturnNode(prototype: prototype, exprs: exprs, line: node.line)
    }

    private func checkPrint(_ node: PrintNode) -> StmtNode {
        let items = node.items.map { item -> ExprNode in
            _ = infer(item, line: node.line)
            return rewrite(item, line: node.line)
        }
        return PrintNode(items: items, newline: node.newline, line: node.line)
    }

    private func checkIf(_ node: IfNode) -> StmtNode {
        let branches = node.branches.map { branch -> IfNode.Branch in
            let condition = checkCondition(branch.condition, line: node.line)
            return IfNode.Branch(condition: condition, body: checkSubScope(branch.body))
        }
        let elseBody = node.elseBody.map { checkSubScope($0) }
        return IfNode(branches: branches, elseBody: elseBody, line: node.line)
    }

    private func checkWhile(_ node: WhileNode) -> StmtNode {
        return WhileNode(condition: checkCondition(node.condition, line: node.line),
                         body: checkSubScope(node.body), line: node.line)
    }

    private func checkFor(_ node: ForNode) -> StmtNode {
        var counterType = widest(infer(node.start, line: node.line), infer(node.end, line: node.line))
        if let step = node.step {
            counterType = widest(counterType, infer(step, line: node.line))
        }
        if counterType.rank > 0 {
            error("Loop counter cannot be \(counterType)", node.line)
            counterType = .int
        }

        let start = coerce(node.start, to: counterType, line: node.line)
        let end = coerce(node.end, to: counterType, line: node.line)
        let step = node.step.map { coerce($0, to: counterType, line: node.line) }

        _ = refuseConstant(node.variable, "used as a loop counter", node.line)
        scopes.append([node.variable: counterType])
        let body = node.body.map { checkStatement($0) }
        scopes.removeLast()

        return ForNode(variable: node.variable, start: start, end: end, step: step,
                       body: body, line: node.line)
    }

    private func checkSubScope(_ body: [StmtNode]) -> [StmtNode] {
        scopes.append([:])
        defer { scopes.removeLast() }
        return body.map { checkStatement($0) }
    }

    private func checkCondition(_ expr: ExprNode, line: Int) -> ExprNode {
        let type = infer(expr, line: line)
        if type.rank > 0 {
            error("Condition cannot be \(type)", line)
        }
        return rewrite(expr, line: line)
    }

    private struct ResolvedTarget {
        let root: String
        let type: ShalimarType?
    }

    private func resolveTarget(_ target: LValue, line: Int) -> ResolvedTarget {
        switch target {
        case .variable(let name):
            return ResolvedTarget(root: name, type: lookup(name))
        case .element(let base, let index):
            _ = coerce(index, to: .int, line: line)
            let parent = resolveTarget(base, line: line)
            guard let parentType = parent.type else { return parent }
            guard case .array(let element) = parentType else {
                error("'\(parent.root)' is \(parentType) and cannot be indexed", line)
                return ResolvedTarget(root: parent.root, type: nil)
            }
            return ResolvedTarget(root: parent.root, type: element)
        }
    }

    private func widest(_ a: ShalimarType, _ b: ShalimarType) -> ShalimarType {
        if a == b { return a }
        if a == .real && b == .int { return .real }
        if a == .int && b == .real { return .real }
        return a
    }

    private func isWidening(from: ShalimarType, to: ShalimarType) -> Bool {
        return from == .int && to == .real
    }

    private func infer(_ expr: ExprNode, line: Int) -> ShalimarType {
        switch expr {
        case is IntNode:    return .int
        case is RealNode:   return .real
        case is StringNode: return .array(.char)
        case let node as ConvertNode: return node.to

        case let node as VariableNode:
            guard let type = lookup(node.name) else {
                error("Undefined variable '\(node.name)'", line)
                return .int
            }
            return type

        case let node as IndexNode:
            let baseType = infer(node.base, line: line)
            let indexType = infer(node.index, line: line)
            if indexType != .int {
                error("An index must be int, not \(indexType)", line)
            }
            guard case .array(let element) = baseType else {
                error("\(baseType) cannot be indexed", line)
                return baseType
            }
            return element

        // Always int, whatever the array holds. An axis the array does not have answers
        // -1 rather than failing, so '.col' is a usable question to ask of a vector; only
        // asking a *scalar* for its dimensions is an error, because that is a type confusion
        // and not a rank one.
        case let node as DimNode:
            let baseType = infer(node.base, line: line)
            if baseType.rank == 0 {
                error("'.\(node.spelling)' needs an array, not \(baseType)", line)
            }
            let axisType = infer(node.axis, line: line)
            if axisType != .int {
                error("Axis must be int, not \(axisType)", line)
            }
            return .int

        // Carries no value of its own - it is a directive that happens to sit in the
        // item list. The int is what the print statement reads; nothing consumes a result.
        case let node as PrecisionNode:
            let places = infer(node.places, line: line)
            if places != .int {
                error("prec() needs an int, not \(places)", line)
            }
            return .int

        case let node as BinaryOpNode:
            let lhs = infer(node.lhs, line: line)
            let rhs = infer(node.rhs, line: line)

            // Two strings are the one array pairing the operators accept. Comparison
            // reads the text up to the terminator, never the declared capacity, so a
            // name in a char[20] equals the same name in a char[128]. '+' joins them
            // into a fresh string sized to the result.
            if lhs == .array(.char) && rhs == .array(.char) {
                switch node.op {
                case .equal, .notEqual, .less, .greater: return .int
                case .add: return .array(.char)
                default:
                    error("'\(node.op.rawValue)' does not apply to strings", line)
                    return .int
                }
            }

            if lhs.rank > 0 || rhs.rank > 0 {
                error("'\(node.op.rawValue)' needs scalars, got \(lhs) and \(rhs)", line)
                return .int
            }
            switch node.op {
            case .equal, .notEqual, .less, .greater, .and, .or: return .int
            default: return widest(lhs, rhs)
            }

        case let node as CallNode:
            return checkCall(node, line: line).type

        case let node as ArrayLiteralNode:
            guard let first = node.elements.first else { return .array(.int) }
            return .array(infer(first, line: line))

        default:
            return .int
        }
    }

    private func coerce(_ expr: ExprNode, to target: ShalimarType, line: Int) -> ExprNode {
        let inferred = infer(expr, line: line)
        if inferred == target { return rewrite(expr, line: line) }

        if isWidening(from: inferred, to: target) {
            return pushDown(expr, to: target, line: line)
        }
        if isWidening(from: target, to: inferred) {
            return ConvertNode(expr: rewrite(expr, line: line), to: target)
        }

        if case .array = target, let literal = expr as? ArrayLiteralNode {
            return pushDown(literal, to: target, line: line)
        }
        if inferred.rank == 0 && target.rank == 0 && inferred != target {
            error("Cannot use \(inferred) where \(target) is required", line)
        } else if inferred != target {
            error("Cannot use \(inferred) where \(target) is required", line)
        }
        return rewrite(expr, line: line)
    }

    private func pushDown(_ expr: ExprNode, to target: ShalimarType, line: Int) -> ExprNode {
        switch expr {
        case let node as BinaryOpNode:
            switch node.op {
            case .equal, .notEqual, .less, .greater, .and, .or:
                return ConvertNode(expr: rewrite(node, line: line), to: target)
            default:
                return BinaryOpNode(op: node.op,
                                    lhs: pushDown(node.lhs, to: target, line: line),
                                    rhs: pushDown(node.rhs, to: target, line: line))
            }

        case let node as ArrayLiteralNode:
            guard case .array(let element) = target else { break }
            return ArrayLiteralNode(elements: node.elements.map { pushDown($0, to: element, line: line) })

        default:
            break
        }

        let inferred = infer(expr, line: line)
        if inferred == target { return rewrite(expr, line: line) }
        return ConvertNode(expr: rewrite(expr, line: line), to: target)
    }

    private func rewrite(_ expr: ExprNode, line: Int) -> ExprNode {
        switch expr {
        case let node as CallNode:
            return checkCall(node, line: line).call
        case let node as IndexNode:
            return IndexNode(base: rewrite(node.base, line: line),
                             index: coerce(node.index, to: .int, line: line))
        case let node as DimNode:
            return DimNode(base: rewrite(node.base, line: line),
                           axis: coerce(node.axis, to: .int, line: line),
                           spelling: node.spelling)
        case let node as PrecisionNode:
            return PrecisionNode(places: coerce(node.places, to: .int, line: line))
        case let node as BinaryOpNode:
            let lhs = infer(node.lhs, line: line)
            let rhs = infer(node.rhs, line: line)
            let operandType = widest(lhs, rhs)
            return BinaryOpNode(op: node.op,
                                lhs: coerce(node.lhs, to: operandType, line: line),
                                rhs: coerce(node.rhs, to: operandType, line: line))
        case let node as ArrayLiteralNode:
            return ArrayLiteralNode(elements: node.elements.map { rewrite($0, line: line) })
        default:
            return expr
        }
    }

    private func checkCall(_ node: CallNode, line: Int) -> (call: CallNode, type: ShalimarType) {
        if let builtin = Checker.builtins[node.callee] {
            return checkBuiltinCall(node, builtin, line: line)
        }
        guard let prototype = prototypes[node.callee] else {
            if node.callee.lowercased() == "prec" {
                error("'prec' belongs after '?'", node.line)
            } else {
                error("Unknown function '\(node.callee)'", node.line)
            }
            return (node, .int)
        }

        if node.arguments.count != prototype.arity {
            error("'\(prototype.name)' takes \(prototype.arity), got \(node.arguments.count)", node.line)
        }

        var arguments: [ExprNode] = []
        for (i, argument) in node.arguments.enumerated() {
            guard i < prototype.inputs.count else {
                arguments.append(rewrite(argument, line: node.line))
                continue
            }
            let parameter = prototype.inputs[i]

            if parameter.byReference {
                if !argument.isAddressable {
                    error("Argument \(i + 1) of '\(prototype.name)' needs a variable", node.line)
                }
                let actual = infer(argument, line: node.line)
                if actual != parameter.type {
                    error("Argument \(i + 1) of '\(prototype.name)' must be \(parameter.type)", node.line)
                }
                arguments.append(rewrite(argument, line: node.line))
            } else {
                arguments.append(coerce(argument, to: parameter.type, line: node.line))
            }
        }

        let call = CallNode(callee: node.callee, arguments: arguments, line: node.line)
        return (call, prototype.outputs.first ?? .int)
    }

    private func checkBuiltinCall(_ node: CallNode, _ builtin: Builtin, line: Int) -> (call: CallNode, type: ShalimarType) {
        if node.arguments.count != builtin.inputs.count {
            error("'\(node.callee)' takes \(builtin.inputs.count), got \(node.arguments.count)", node.line)
            guard node.arguments.count > builtin.inputs.count else { return (node, builtin.output) }
        }

        if node.callee == "len" {
            let actual = infer(node.arguments[0], line: node.line)
            if actual.rank == 0 {
                error("len() needs an array, got \(actual)", node.line)
            }
            return (CallNode(callee: node.callee,
                             arguments: [rewrite(node.arguments[0], line: node.line)],
                             line: node.line), .int)
        }

        // The conversions carry their own target, so the argument must reach them
        // untouched. Coercing it to the declared input type first would run it through
        // the opposite conversion on the way in - 'real(2.7)' would be narrowed to 2 and
        // then widened back to 2.0, truncating the value the call exists to preserve.
        if let target = Checker.conversions[node.callee] {
            let actual = infer(node.arguments[0], line: node.line)
            guard actual.rank == 0 else {
                error("\(node.callee)() needs one value, not \(actual)", node.line)
                return (node, target)
            }
            return (CallNode(callee: node.callee,
                             arguments: [rewrite(node.arguments[0], line: node.line)],
                             line: node.line),
                    target)
        }

        if builtin.generic {
            let types = node.arguments.prefix(builtin.inputs.count).map { infer($0, line: node.line) }
            let result = types.dropFirst().reduce(types.first ?? .real) { widest($0, $1) }
            let arguments = node.arguments.prefix(builtin.inputs.count).map {
                coerce($0, to: result, line: node.line)
            }
            return (CallNode(callee: node.callee, arguments: Array(arguments), line: node.line), result)
        }

        let arguments = zip(node.arguments.prefix(builtin.inputs.count), builtin.inputs).map {
            coerce($0, to: $1, line: node.line)
        }
        return (CallNode(callee: node.callee, arguments: Array(arguments), line: node.line), builtin.output)
    }
}
