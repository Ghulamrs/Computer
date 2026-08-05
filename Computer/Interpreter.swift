//
//  Interpreter.swift
//  Computer
//
//  Created by G. R. Akhtar on 02/08/2026.
//  Copyright © 2026 Home. All rights reserved.
//

import Foundation

enum EvalError: Error, CustomStringConvertible {
    case undefinedVariable(String)
    case unknownFunction(String)
    case wrongArgCount(String, expected: Int, got: Int)
    case wrongArgType(String, position: Int, got: String)
    case runtime(String)
    
    // Split from `description` so a line number can be inserted between the prefix and the text.
    var prefix: String {
        if case .runtime = self { return "Runtime error" }
        return "Error"
    }

    var message: String {
        switch self {
        case .undefinedVariable(let v): return "Undefined variable '\(v)'"
        case .unknownFunction(let f): return "Unknown function '\(f)'"
        case .wrongArgCount(let f, let e, let g):
            return "Function '\(f)' expects \(e) arguments, got \(g)"
        case .wrongArgType(let f, let pos, let got):
            return "Function '\(f)' argument \(pos) must be a number, got '\(got)'"
        case .runtime(let msg): return msg
        }
    }

    var description: String { "\(prefix): \(message)" }

    // Line 0 means "no statement was executing" - `No main() function defined` is the case that
    // reaches this, and inventing a line for it would be worse than leaving it off.
    func described(atLine line: Int) -> String {
        line > 0 ? "\(prefix): line \(line): \(message)" : description
    }
}

enum EvalControl {
    case normal(Double)
    case returnValues([Double])
}

// Reduces either form of a call's result to a single number by taking the first return
// value (0 if none) - so "x : f()", "1 + f()", "? f()", etc. all work with a user-defined
// function the same way they already do with a builtin, instead of silently dropping the
// value or erroring. Full multi-value capture still requires MultiAssign ("<a,b> : f(...)").
private func numericValue(_ control: EvalControl) -> Double {
    switch control {
    case .normal(let v): return v
    case .returnValues(let vals): return vals.first ?? 0.0
    }
}

class Interpreter {
    var output: (String) -> Void = { text in print(text, terminator: "") }
    private var globalSymbols: [String: Double] = [:]
    private var userFunctions: [String: FunctionDefNode] = [:]
    // Source line of the statement currently executing, for error messages. 0 until the first
    // statement runs. See `evaluate` and `EvalError.described(atLine:)`.
    private var currentLine = 0
    // Each builtin carries its own arity so the call site can check it before invoking the
    // closure. The closures index args[0]/args[1] directly, so an under-supplied call used to
    // trap on an array bound - killing the whole app, since a Swift bounds violation is not a
    // catchable Swift error and never reached runProgram's do/catch. The arity lives here,
    // next to the closure that relies on it, so the two cannot drift apart.
    private struct Builtin {
        let arity: Int
        let apply: ([Double]) -> Double
    }
    private var builtins: [String: Builtin] = [
        "abs":   Builtin(arity: 1) { args in fabs(args[0]) },
        "log":   Builtin(arity: 1) { args in log(args[0]) },
        "asin":  Builtin(arity: 1) { args in asin(args[0]) },
        "sin":   Builtin(arity: 1) { args in sin(args[0])  },
        "acos":  Builtin(arity: 1) { args in acos(args[0]) },
        "cos":   Builtin(arity: 1) { args in cos(args[0])  },
        "atan":  Builtin(arity: 1) { args in atan(args[0]) },
        "tan":   Builtin(arity: 1) { args in tan(args[0])  },
        "atan2": Builtin(arity: 2) { args in atan2(args[0], args[1]) },
        "pow":   Builtin(arity: 2) { args in pow(args[0], args[1]) },
        "max":   Builtin(arity: 2) { args in max(args[0], args[1]) },
        "min":   Builtin(arity: 2) { args in min(args[0], args[1]) },
        "round": Builtin(arity: 1) { args in round(args[0]) },
        "sqrt":  Builtin(arity: 1) { args in sqrt(args[0]) },
        "ceil":  Builtin(arity: 1) { args in ceil(args[0]) },
        "floor": Builtin(arity: 1) { args in floor(args[0]) }
    ]
    private let constants: [String: Double] = [
        "pi": Double.pi,
        "e": M_E
    ]

    func runProgram(_ nodes: [ASTNode]) {
        do {
            for node in nodes {
                if let def = node as? FunctionDefNode {
                    guard userFunctions[def.name] == nil else {
                        // Set explicitly: this runs before any statement executes, so nothing has
                        // put a line in `currentLine` yet, and the redefinition is the thing to
                        // point at rather than the original.
                        currentLine = def.line
                        throw EvalError.runtime("Function '\(def.name)' already defined")
                    }
                    userFunctions[def.name] = def
                }
            }
            guard let mainDef = userFunctions["main"] else {
                throw EvalError.runtime("No main() function defined")
            }
            let calledNames = collectCalledFunctionNames(nodes)
            for name in userFunctions.keys.sorted() where name != "main" && !calledNames.contains(name) {
                output("Warning: function '\(name)' is defined but never called\n")
            }
            _ = try executeFunction(mainDef, args: [])
        } catch let error as EvalError {
            output("\(error.described(atLine: currentLine))\n")
        } catch {
            output("\(error)\n")
        }
    }

    // Every FunctionCallNode name referenced anywhere in the program, including
    // calls made from inside other function bodies — used to flag dead functions.
    private func collectCalledFunctionNames(_ nodes: [ASTNode]) -> Set<String> {
        var names: Set<String> = []
        for node in nodes {
            collectCalledFunctionNames(node, into: &names)
        }
        return names
    }

    private func collectCalledFunctionNames(_ node: ASTNode, into names: inout Set<String>) {
        switch node {
        case let n as AssignmentNode:
            collectCalledFunctionNames(n.expr, into: &names)
        case let n as CompoundAssignNode:
            collectCalledFunctionNames(n.expr, into: &names)
        case let n as MultiAssignNode:
            collectCalledFunctionNames(n.call, into: &names)
        case let n as ReturnNode:
            n.exprs.forEach { collectCalledFunctionNames($0, into: &names) }
        case let n as FunctionDefNode:
            n.body.forEach { collectCalledFunctionNames($0, into: &names) }
        case let n as FunctionCallNode:
            names.insert(n.name)
            n.args.forEach { collectCalledFunctionNames($0, into: &names) }
        case let n as IfElseChainNode:
            for (cond, body) in n.branches {
                collectCalledFunctionNames(cond, into: &names)
                body.forEach { collectCalledFunctionNames($0, into: &names) }
            }
            n.elseBranch?.forEach { collectCalledFunctionNames($0, into: &names) }
        case let n as WhileNode:
            collectCalledFunctionNames(n.condition, into: &names)
            n.body.forEach { collectCalledFunctionNames($0, into: &names) }
        case let n as ForLoopNode:
            collectCalledFunctionNames(n.startExpr, into: &names)
            collectCalledFunctionNames(n.endExpr, into: &names)
            collectCalledFunctionNames(n.stepExpr, into: &names)
            n.body.forEach { collectCalledFunctionNames($0, into: &names) }
        case let n as PrintNode:
            n.items.forEach { collectCalledFunctionNames($0, into: &names) }
        case let n as BinaryOpNode:
            collectCalledFunctionNames(n.left, into: &names)
            collectCalledFunctionNames(n.right, into: &names)
        default:
            break // NumberNode, StringNode, VariableNode: leaves, nothing to collect
        }
    }

    // How deep each user function is currently nested inside itself. Unbounded recursion
    // overflows the native stack, which is a SIGSEGV rather than a Swift error - so, like a
    // trap, it cannot be caught and would kill the app with an empty console. Counting the
    // frames ourselves turns it into an ordinary EvalError the UI can show.
    private var callDepth: [String: Int] = [:]
    private var totalCallDepth = 0

    // Budget per function: 256 / (declared inputs + 1), so wider functions - whose frames
    // carry more bound locals - get proportionally less room. 0 inputs allows 256 deep,
    // 1 input 128, 2 inputs 85. Integer division, so the cap is always at least 1.
    private func recursionLimit(_ def: FunctionDefNode) -> Int {
        return max(1, 256 / (def.inputs.count + 1))
    }

    // Backstop for the case the per-function limit cannot see: mutual recursion. In a cycle
    // f0 -> f1 -> ... -> f0, no single function approaches its own cap, yet the frames still
    // accumulate - measured, 40 zero-argument functions in a cycle (up to 10,240 frames)
    // still overflowed the native stack and died with SIGSEGV. This bounds the sum instead.
    // 1024 sits deliberately between the two: 4x the largest per-function limit, so ordinary
    // nesting never reaches it, and well under the ~2,500 frames measured as survivable.
    private static let totalDepthLimit = 1024

    private func executeFunction(_ def: FunctionDefNode, args: [Double]) throws -> [Double] {
        if args.count > def.inputs.count {
            // Over-supply stays permissive - the surplus is dropped and the call still runs -
            // but silently discarding arguments hides a real mistake, so say so. Under-supply
            // is still a hard error, thrown by the binding loop below.
            output("Warning: '\(def.name)' extra args provided - ignoring\n")
        }

        // Depth, not a call tally: this counts frames currently on the stack, so a loop that
        // calls the same function a thousand times in sequence is unaffected - each call has
        // returned, and decremented, before the next begins. The defer runs on the throwing
        // path too, so an error raised deep in a call chain doesn't leave the count stuck high.
        let limit = recursionLimit(def)
        let depth = (callDepth[def.name] ?? 0) + 1
        guard depth <= limit else {
            throw EvalError.runtime("Recursion too deep in '\(def.name)' (limit \(limit))")
        }
        guard totalCallDepth < Interpreter.totalDepthLimit else {
            throw EvalError.runtime("Call stack too deep (limit \(Interpreter.totalDepthLimit))")
        }
        callDepth[def.name] = depth
        totalCallDepth += 1
        defer {
            callDepth[def.name] = depth - 1
            totalCallDepth -= 1
        }

        var localSymbols: [String: Double] = [:]
        for (i, inputName) in def.inputs.enumerated() {
            if i < args.count {
                localSymbols[inputName] = args[i]
            } else {
                throw EvalError.wrongArgCount(def.name, expected: def.inputs.count, got: args.count)
            }
        }
        if case .returnValues(let vals) = try executeBlock(def.body, symbols: &localSymbols) {
            return vals
        }
        return def.outputs.map { localSymbols[$0] ?? 0.0 }
    }
    
    // Runs a block's statements in order, stopping and propagating as soon as one of them
    // returns (including a return nested inside its own if/while/for). Only statement kinds
    // that can structurally contain/forward an explicit "return" are allowed to end the block
    // this way - a bare call statement like "f()" also evaluates to .returnValues (so
    // MultiAssign can capture it elsewhere), but on its own it's just an expression statement
    // whose value is discarded, not a return.
    private func executeBlock(_ stmts: [ASTNode], symbols: inout [String: Double]) throws -> EvalControl {
        for stmt in stmts {
            let result = try evaluate(node: stmt, symbols: &symbols)
            switch stmt {
            case is ReturnNode, is IfElseChainNode, is WhileNode, is ForLoopNode:
                if case .returnValues = result { return result }
            default:
                break
            }
        }
        return .normal(0.0)
    }

    // A for loop truncates its bounds to Int (see SHALIMAR_LANGUAGE.md 5.9), but a bare
    // Int(Double) *traps* rather than throwing on NaN, on either infinity, and on any
    // magnitude past Int's range - and a trap is not a catchable Swift Error, so it walks
    // past runProgram's do/catch and kills the app with an empty console. That is reachable
    // from ordinary arithmetic: "for i : 1 to sqrt(0-1)" or "to 1/0" both produce a bound
    // no Int can hold. Int(exactly:) on the already-truncated value returns nil for exactly
    // those cases and preserves toward-zero truncation for everything else.
    private func loopBound(_ value: Double, _ role: String) throws -> Int {
        guard let bound = Int(exactly: value.rounded(.towardZero)) else {
            throw EvalError.runtime("Loop \(role) out of range: \(value)")
        }
        return bound
    }

    private func evaluate(node: ASTNode, symbols: inout [String: Double]) throws -> EvalControl {
        // Every statement in the program passes through here, so this one line keeps `currentLine`
        // pointing at whatever is executing - including inside a called function, where the
        // callee's lines take over until it returns. Expressions leave it alone, which is why an
        // error inside one is reported against its enclosing statement.
        if let stmt = node as? StatementNode { currentLine = stmt.line }
        if let numNode = node as? NumberNode { return .normal(numNode.value) }
        // Load-bearing despite looking like a no-op: a StringNode reaching the generic
        // evaluator must degrade to 0.0, per SHALIMAR_LANGUAGE.md §6 ("x : "hello"" makes
        // x 0.0). Print items and the builtin-argument check special-case StringNode before
        // reaching here; every *other* context - assignment, arithmetic, conditions, user
        // function arguments, return - relies on this line. Without it they all fall through
        // to the "Unknown node type" throw at the end of this function.
        if node is StringNode { return .normal(0.0) }
        if let varNode = node as? VariableNode {
            guard let val = symbols[varNode.name] ?? globalSymbols[varNode.name] ?? constants[varNode.name] else {
                throw EvalError.undefinedVariable(varNode.name)
            }
            return .normal(val)
        }
        
        if let assignNode = node as? AssignmentNode {
            let val = try evaluate(node: assignNode.expr, symbols: &symbols)
            let v = numericValue(val)
            symbols[assignNode.variable] = v
            return .normal(v)
        }

        if let compAssign = node as? CompoundAssignNode {
            guard let current = symbols[compAssign.variable] ?? globalSymbols[compAssign.variable] ?? constants[compAssign.variable] else {
                throw EvalError.undefinedVariable(compAssign.variable)
            }
            let val = try evaluate(node: compAssign.expr, symbols: &symbols)
            let v = numericValue(val)
            let updated: Double
            switch compAssign.op {
            case .plus: updated = current + v
            case .minus: updated = current - v
            }
            symbols[compAssign.variable] = updated
            return .normal(updated)
        }
        
        if let multiAssign = node as? MultiAssignNode {
            let result = try evaluate(node: multiAssign.call, symbols: &symbols)
            // A builtin call yields .normal, not .returnValues (it has no return-count concept
            // of its own) - treat it as a single returned value so it can still be multi-assigned,
            // and so the count-mismatch check below applies to it uniformly.
            let vals: [Double]
            switch result {
            case .returnValues(let v): vals = v
            case .normal(let v): vals = [v]
            }
            if vals.count != multiAssign.variables.count {
                // Kept short - this prints on a narrow on-screen console, not just Xcode's.
                output("Warning: '\(multiAssign.call.name)' returned \(vals.count), expected \(multiAssign.variables.count)\n")
            }
            for (i, v) in vals.enumerated() where i < multiAssign.variables.count {
                symbols[multiAssign.variables[i]] = v
            }
            return .normal(0.0)
        }
        
        if let retNode = node as? ReturnNode {
            var vals: [Double] = []
            for expr in retNode.exprs {
                let val = try evaluate(node: expr, symbols: &symbols)
                vals.append(numericValue(val))
            }
            return .returnValues(vals)
        }

        // (continued in Part 2)
        if let binNode = node as? BinaryOpNode {
            let l = try evaluate(node: binNode.left, symbols: &symbols)
            let r = try evaluate(node: binNode.right, symbols: &symbols)
            let lv = numericValue(l)
            let rv = numericValue(r)
            switch binNode.op {
            case .plus: return .normal(lv + rv)
            case .minus: return .normal(lv - rv)
            case .multiply: return .normal(lv * rv)
            case .divide: return .normal(lv / rv)
            case .modulus: return .normal(lv.truncatingRemainder(dividingBy: rv))
            case .power: return .normal(pow(lv, rv))
            case .equal: return .normal((lv == rv) ? 1.0 : 0.0)
            case .notEqual: return .normal((lv != rv) ? 1.0 : 0.0)
            case .less: return .normal((lv < rv) ? 1.0 : 0.0)
            case .greater: return .normal((lv > rv) ? 1.0 : 0.0)
            case .and: return .normal(((lv != 0) && (rv != 0)) ? 1.0 : 0.0)
            case .or: return .normal(((lv != 0) || (rv != 0)) ? 1.0 : 0.0)
            }
        }
        
        if let callNode = node as? FunctionCallNode {
            if let builtin = builtins[callNode.name] {
                var argVals: [Double] = []
                for (i, arg) in callNode.args.enumerated() {
                    if let strNode = arg as? StringNode {
                        throw EvalError.wrongArgType(callNode.name, position: i+1, got: "\"\(strNode.value)\"")
                    }
                    let val = try evaluate(node: arg, symbols: &symbols)
                    argVals.append(numericValue(val))
                }
                // Same asymmetry user functions use (see executeFunction): too few arguments
                // leaves the closure with nothing to read and cannot proceed, too many is
                // recoverable and only warns.
                guard argVals.count >= builtin.arity else {
                    throw EvalError.wrongArgCount(callNode.name, expected: builtin.arity, got: argVals.count)
                }
                if argVals.count > builtin.arity {
                    output("Warning: '\(callNode.name)' extra args provided - ignoring\n")
                }
                return .normal(builtin.apply(argVals))
            }
            if let def = userFunctions[callNode.name] {
                var argVals: [Double] = []
                for arg in callNode.args {
                    let val = try evaluate(node: arg, symbols: &symbols)
                    argVals.append(numericValue(val))
                }
                let outs = try executeFunction(def, args: argVals)
                return .returnValues(outs)
            }
            throw EvalError.unknownFunction(callNode.name)
        }
        
        if let printNode = node as? PrintNode {
            var text = ""
            for item in printNode.items {
                if let strNode = item as? StringNode {
                    text += strNode.value + " "
                } else {
                    let val = try evaluate(node: item, symbols: &symbols)
                    text += "\(numericValue(val)) "
                }
            }
            output(text + (printNode.newline ? "\n" : ""))
            return .normal(0.0)
        }
        
        if let ifNode = node as? IfElseChainNode {
            for (cond, body) in ifNode.branches {
                let val = try evaluate(node: cond, symbols: &symbols)
                if numericValue(val) != 0 {
                    return try executeBlock(body, symbols: &symbols)
                }
            }
            if let elseBody = ifNode.elseBranch {
                return try executeBlock(elseBody, symbols: &symbols)
            }
            return .normal(0.0)
        }

        if let whileNode = node as? WhileNode {
            while true {
                let condVal = try evaluate(node: whileNode.condition, symbols: &symbols)
                if numericValue(condVal) == 0 { break }
                let result = try executeBlock(whileNode.body, symbols: &symbols)
                if case .returnValues = result { return result }
            }
            return .normal(0.0)
        }
        
        if let forNode = node as? ForLoopNode {
            let startValDouble = numericValue(try evaluate(node: forNode.startExpr, symbols: &symbols))
            let endValDouble = numericValue(try evaluate(node: forNode.endExpr, symbols: &symbols))
            let stepValDouble = numericValue(try evaluate(node: forNode.stepExpr, symbols: &symbols))

            var i = try loopBound(startValDouble, "start")
            let endVal = try loopBound(endValDouble, "end")
            let stepVal = try loopBound(stepValDouble, "step")

            if stepVal > 0 {
                while i <= endVal {
                    symbols[forNode.variable] = Double(i)
                    let result = try executeBlock(forNode.body, symbols: &symbols)
                    if case .returnValues = result { return result }
                    i += stepVal
                }
            } else if stepVal < 0 {
                while i >= endVal {
                    symbols[forNode.variable] = Double(i)
                    let result = try executeBlock(forNode.body, symbols: &symbols)
                    if case .returnValues = result { return result }
                    i += stepVal
                }
            } else {
                throw EvalError.runtime("Step value cannot be zero")
            }
            return .normal(0.0)
        }

        throw EvalError.runtime("Unknown node type")
    }
}
