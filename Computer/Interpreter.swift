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
    
    var description: String {
        switch self {
        case .undefinedVariable(let v): return "Error: Undefined variable '\(v)'"
        case .unknownFunction(let f): return "Error: Unknown function '\(f)'"
        case .wrongArgCount(let f, let e, let g):
            return "Error: Function '\(f)' expects \(e) arguments, got \(g)"
        case .wrongArgType(let f, let pos, let got):
            return "Error: Function '\(f)' argument \(pos) must be a number, got '\(got)'"
        case .runtime(let msg): return "Runtime error: \(msg)"
        }
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
    private var builtins: [String: ([Double]) -> Double] = [
        "abs":   { args in fabs(args[0]) },
        "log":   { args in log(args[0]) },
        "asin":  { args in asin(args[0]) },
        "sin":   { args in sin(args[0])  },
        "acos":  { args in acos(args[0]) },
        "cos":   { args in cos(args[0])  },
        "atan":  { args in atan(args[0]) },
        "tan":   { args in tan(args[0])  },
        "atan2": { args in atan2(args[0], args[1]) },
        "pow":   { args in pow(args[0], args[1]) },
        "max":   { args in max(args[0], args[1]) },
        "min":   { args in min(args[0], args[1]) },
        "round": { args in round(args[0]) },
        "sqrt":  { args in sqrt(args[0]) },
        "ceil":  { args in ceil(args[0]) },
        "floor": { args in floor(args[0]) }
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

    private func executeFunction(_ def: FunctionDefNode, args: [Double]) throws -> [Double] {
        if args.count > def.inputs.count {
            // Over-supply stays permissive - the surplus is dropped and the call still runs -
            // but silently discarding arguments hides a real mistake, so say so. Under-supply
            // is still a hard error, thrown by the binding loop below.
            output("Warning: '\(def.name)' extra args provided - ignoring\n")
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

    private func evaluate(node: ASTNode, symbols: inout [String: Double]) throws -> EvalControl {
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
            default: throw EvalError.runtime("Unsupported operator")
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
                return .normal(builtin(argVals))
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

            var i = Int(startValDouble)
            let endVal = Int(endValDouble)
            let stepVal = Int(stepValDouble)

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
