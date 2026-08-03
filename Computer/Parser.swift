//
//  Parser.swift
//  Computer
//
//  Created by G. R. Akhtar on 02/08/2026.
//  Copyright © 2026 Home. All rights reserved.
//

enum ParseError: Error, CustomStringConvertible {
    case unexpectedToken(String)
    case invalidAssignmentOperator(String)
    case missingOpeningBrace
    case missingClosingBrace
    
    var description: String {
        switch self {
        case .unexpectedToken(let tok): return "Parse error: Unexpected token '\(tok)'"
        case .invalidAssignmentOperator(let tok): return "Parse error: Invalid assignment operator '\(tok)'. Use ':' instead."
        case .missingOpeningBrace: return "Parse error: Missing '{' to start block"
        case .missingClosingBrace: return "Parse error: Missing '}' to close block"
        }
    }
}

// =======================
// AST Node Definitions
// =======================

protocol ASTNode {}

struct NumberNode: ASTNode { let value: Double }
struct StringNode: ASTNode { let value: String }
struct VariableNode: ASTNode { let name: String }

struct AssignmentNode: ASTNode {
    let variable: String
    let expr: ASTNode
}

struct CompoundAssignNode: ASTNode {
    enum Op { case plus, minus }
    let variable: String
    let op: Op
    let expr: ASTNode
}

struct MultiAssignNode: ASTNode {
    let variables: [String]
    let call: FunctionCallNode
}

struct ReturnNode: ASTNode {
    let exprs: [ASTNode]
}

struct FunctionDefNode: ASTNode {
    let name: String
    let inputs: [String]
    let outputs: [String]
    let body: [ASTNode]
}

struct FunctionCallNode: ASTNode {
    let name: String
    let args: [ASTNode]
}

struct IfElseChainNode: ASTNode {
    let branches: [(ASTNode, [ASTNode])]
    let elseBranch: [ASTNode]?
}

struct WhileNode: ASTNode {
    let condition: ASTNode
    let body: [ASTNode]
}

struct ForLoopNode: ASTNode {
    let variable: String
    let startExpr: ASTNode
    let endExpr: ASTNode
    let stepExpr: ASTNode
    let body: [ASTNode]
}

struct PrintNode: ASTNode {
    let items: [ASTNode]
    let newline: Bool
}

struct BinaryOpNode: ASTNode {
    enum Op {
        case plus, minus, multiply, divide, modulus, power
        case equal, notEqual, less, greater
        case and, or
    }
    let left: ASTNode
    let right: ASTNode
    let op: Op
}

class Parser {
    private var tokens: [Token]
    private var position: Int = 0
    private(set) var parseError: Error?

    init(tokens: [Token]) { self.tokens = tokens }

    func parseProgram() -> [ASTNode] {
        var nodes: [ASTNode] = []
        while position < tokens.count {
            do { nodes.append(try parseExpression()) }
            catch { parseError = error; break }
        }
        return nodes
    }
    
    private func parseExpression() throws -> ASTNode {
        if position < tokens.count {
            switch tokens[position].type {
            case .ifKeyword: return try parseIfElseChain()
            case .whileKeyword: return try parseWhile()
            case .forKeyword: return try parseForLoop()
            case .funKeyword: return try parseFunctionDef()
            case .printLine: return try parsePrint(newline: true)
            case .printInline: return try parsePrint(newline: false)
            case .returnKeyword: return try parseReturn()
            default: break
            }
        }
        return try parseAssignmentOrTerm()
    }
    
    // --- Return ---
    private func parseReturn() throws -> ASTNode {
        position += 1
        var exprs: [ASTNode] = []
        while position < tokens.count {
            if case .rBrace = tokens[position].type { break }
            if looksLikeNewStatement(at: position) { break }
            exprs.append(try parseExpr())
        }
        return ReturnNode(exprs: exprs)
    }
    
    // --- Assignment / MultiAssign / CompoundAssign ---
    private func parseAssignmentOrTerm() throws -> ASTNode {
        // Multi-assign <a,b> : func(...)
        if position < tokens.count, case .lAngle = tokens[position].type {
            position += 1
            var vars: [String] = []
            while position < tokens.count {
                if case .identifier(let name) = tokens[position].type {
                    vars.append(name); position += 1
                } else if case .comma = tokens[position].type { position += 1 }
                else if case .rAngle = tokens[position].type { position += 1; break }
                else { throw ParseError.unexpectedToken("Unexpected in multi‑assign") }
            }
            guard case .assignColon = tokens[position].type else {
                throw ParseError.unexpectedToken("Expected ':' after multi‑assign")
            }
            position += 1
            guard case .identifier(let fname) = tokens[position].type else {
                throw ParseError.unexpectedToken("Expected function call")
            }
            position += 1
            let call = try parseFunctionCall(name: fname)
            return MultiAssignNode(variables: vars, call: call)
        }
        
        // Normal assignment / compound assignment
        if position < tokens.count, case .identifier(let name) = tokens[position].type {
            if position + 1 < tokens.count {
                switch tokens[position + 1].type {
                case .assignColon:
                    position += 2; let expr = try parseExpr()
                    return AssignmentNode(variable: name, expr: expr)
                case .equal:
                    print("Warning: '=' used for assignment. Use ':' instead.")
                    position += 2; let expr = try parseExpr()
                    return AssignmentNode(variable: name, expr: expr)
                case .plusAssign:
                    position += 2; let expr = try parseExpr()
                    return CompoundAssignNode(variable: name, op: .plus, expr: expr)
                case .minusAssign:
                    position += 2; let expr = try parseExpr()
                    return CompoundAssignNode(variable: name, op: .minus, expr: expr)
                default: break
                }
            }
        }
        return try parseTerm()
    }
    
    // --- Block ---
    private func parseBlock() throws -> [ASTNode] {
        guard position < tokens.count else { throw ParseError.missingOpeningBrace }
        guard case .lBrace = tokens[position].type else { throw ParseError.missingOpeningBrace }
        position += 1
        
        var stmts: [ASTNode] = []
        while position < tokens.count {
            if case .rBrace = tokens[position].type {
                position += 1
                return stmts
            }
            stmts.append(try parseExpression())
        }
        throw ParseError.missingClosingBrace
    }
    
    // --- IfElse ---
    private func parseIfElseChain() throws -> ASTNode {
        position += 1
        let cond = try parseExpr()
        let body = try parseBlock()
        var branches: [(ASTNode, [ASTNode])] = [(cond, body)]

        while position < tokens.count {
            if case .elseifKeyword = tokens[position].type {
                position += 1
                let cond = try parseExpr()
                let body = try parseBlock()
                branches.append((cond, body))
            } else { break }
        }
        
        var elseBranch: [ASTNode]? = nil
        if position < tokens.count, case .elseKeyword = tokens[position].type {
            position += 1
            elseBranch = try parseBlock()
        }
        return IfElseChainNode(branches: branches, elseBranch: elseBranch)
    }
    
    // --- While ---
    private func parseWhile() throws -> ASTNode {
        position += 1
        let cond = try parseExpr()
        let body = try parseBlock()
        return WhileNode(condition: cond, body: body)
    }

    // --- For with optional step ---
    private func parseForLoop() throws -> ASTNode {
        position += 1
        guard case .identifier(let name) = tokens[position].type else {
            throw ParseError.unexpectedToken("Expected loop variable")
        }
        position += 1
        guard case .assignColon = tokens[position].type else {
            throw ParseError.unexpectedToken("Expected ':' after loop variable")
        }
        position += 1
        let startExpr = try parseExpr()
        guard case .toKeyword = tokens[position].type else {
            throw ParseError.unexpectedToken("Expected 'to' in for loop")
        }
        position += 1
        let endExpr = try parseExpr()

        var stepExpr: ASTNode = NumberNode(value: 1.0)
        if position < tokens.count, case .stepKeyword = tokens[position].type {
            position += 1
            stepExpr = try parseExpr()
        }
        
        let body = try parseBlock()
        return ForLoopNode(variable: name, startExpr: startExpr, endExpr: endExpr, stepExpr: stepExpr, body: body)
    }
    
    // --- Function Definition ---
    private func parseFunctionDef() throws -> ASTNode {
        position += 1
        var outputs: [String] = []
        if case .lAngle = tokens[position].type {
            position += 1
            while position < tokens.count {
                if case .identifier(let outName) = tokens[position].type {
                    outputs.append(outName); position += 1
                } else if case .comma = tokens[position].type { position += 1 }
                else if case .rAngle = tokens[position].type { position += 1; break }
                else { throw ParseError.unexpectedToken("Unexpected in function outputs") }
            }
        }
        guard case .equal = tokens[position].type else {
            throw ParseError.unexpectedToken("Expected '=' after output list")
        }
        position += 1
        guard case .identifier(let name) = tokens[position].type else {
            throw ParseError.unexpectedToken("Expected function name")
        }
        position += 1
        guard case .lParen = tokens[position].type else {
            throw ParseError.unexpectedToken("Expected '(' after function name")
        }
        position += 1
        var inputs: [String] = []
        while position < tokens.count {
            if case .identifier(let arg) = tokens[position].type {
                inputs.append(arg); position += 1
            } else if case .comma = tokens[position].type { position += 1 }
            else if case .rParen = tokens[position].type { position += 1; break }
            else { throw ParseError.unexpectedToken("Unexpected token in function inputs") }
        }
        let body = try parseBlock()
        return FunctionDefNode(name: name, inputs: inputs, outputs: outputs, body: body)
    }
    // --- Print ---
    private func parsePrint(newline: Bool) throws -> ASTNode {
        position += 1
        var items: [ASTNode] = []
        while position < tokens.count, startsTerm(tokens[position].type), !looksLikeNewStatement(at: position) {
            items.append(try parseExpr())
        }
        return PrintNode(items: items, newline: newline)
    }
    
    // --- Term ---
    private func parseTerm() throws -> ASTNode {
        guard position < tokens.count else {
            throw ParseError.unexpectedToken("Unexpected end of input")
        }
        let token = tokens[position]
        position += 1
        switch token.type {
        case .number(let value): return NumberNode(value: value)
        case .stringLiteral(let str): return StringNode(value: str)
        case .identifier(let name):
            if position < tokens.count, case .lParen = tokens[position].type {
                return try parseFunctionCall(name: name)
            }
            return VariableNode(name: name)
        case .minus:
            // Unary minus: "-Term", e.g. a negative literal or "-sqrt(4)".
            let operand = try parseTerm()
            if let num = operand as? NumberNode {
                return NumberNode(value: -num.value)
            }
            return BinaryOpNode(left: NumberNode(value: 0), right: operand, op: .minus)
        case .lParen:
            // Grouping: "(" Expression ")" — controls order only, no precedence change.
            let expr = try parseExpr()
            guard position < tokens.count, case .rParen = tokens[position].type else {
                throw ParseError.unexpectedToken("Expected ')' to close grouped expression")
            }
            position += 1
            return expr
        default:
            throw ParseError.unexpectedToken("\(token.type)")
        }
    }

    // --- Expression, by precedence (lowest to highest binding):
    //     "|"  <  "&"  <  "=" "!=" "<" ">"  <  "+" "-"  <  "*" "/" "%"  <  Term
    private func parseExpr() throws -> ASTNode {
        return try parseOr()
    }

    private func parseOr() throws -> ASTNode {
        var left = try parseAnd()
        while position < tokens.count, case .or = tokens[position].type {
            position += 1
            let right = try parseAnd()
            left = BinaryOpNode(left: left, right: right, op: .or)
        }
        return left
    }

    private func parseAnd() throws -> ASTNode {
        var left = try parseComparison()
        while position < tokens.count, case .and = tokens[position].type {
            position += 1
            let right = try parseComparison()
            left = BinaryOpNode(left: left, right: right, op: .and)
        }
        return left
    }

    private func parseComparison() throws -> ASTNode {
        var left = try parseAdditive()
        while position < tokens.count {
            if case .lAngle = tokens[position].type, looksLikeMultiAssignHeader(at: position) {
                // A new "<a,b> : f(...)" statement starts here, not a "<" comparison.
                break
            }
            guard let op = comparisonOperator(for: tokens[position].type) else { break }
            position += 1
            let right = try parseAdditive()
            left = BinaryOpNode(left: left, right: right, op: op)
        }
        return left
    }

    private func parseAdditive() throws -> ASTNode {
        var left = try parseMultiplicative()
        while position < tokens.count, let op = additiveOperator(for: tokens[position].type) {
            position += 1
            let right = try parseMultiplicative()
            left = BinaryOpNode(left: left, right: right, op: op)
        }
        return left
    }

    private func parseMultiplicative() throws -> ASTNode {
        var left = try parsePower()
        while position < tokens.count, let op = multiplicativeOperator(for: tokens[position].type) {
            position += 1
            let right = try parsePower()
            left = BinaryOpNode(left: left, right: right, op: op)
        }
        return left
    }

    // Right-associative: "2 ^ 3 ^ 2" is "2 ^ (3 ^ 2)".
    private func parsePower() throws -> ASTNode {
        let left = try parseTerm()
        if position < tokens.count, case .caret = tokens[position].type {
            position += 1
            let right = try parsePower()
            return BinaryOpNode(left: left, right: right, op: .power)
        }
        return left
    }

    private func multiplicativeOperator(for type: TokenType) -> BinaryOpNode.Op? {
        switch type {
        case .multiply: return .multiply
        case .divide: return .divide
        case .modulus: return .modulus
        default: return nil
        }
    }

    private func additiveOperator(for type: TokenType) -> BinaryOpNode.Op? {
        switch type {
        case .plus: return .plus
        case .minus: return .minus
        default: return nil
        }
    }

    private func comparisonOperator(for type: TokenType) -> BinaryOpNode.Op? {
        switch type {
        case .equal: return .equal
        case .notEqual: return .notEqual
        case .lAngle: return .less
        case .rAngle: return .greater
        default: return nil
        }
    }

    // Distinguishes "<" as MultiAssign's opener from "<" as a "less than" operator:
    // MultiAssign ::= "<" Identifier { "," Identifier } ">" ":" FunctionCall
    private func looksLikeMultiAssignHeader(at start: Int) -> Bool {
        var i = start + 1
        guard i < tokens.count, case .identifier = tokens[i].type else { return false }
        i += 1
        while i < tokens.count, case .comma = tokens[i].type {
            i += 1
            guard i < tokens.count, case .identifier = tokens[i].type else { return false }
            i += 1
        }
        guard i < tokens.count, case .rAngle = tokens[i].type else { return false }
        i += 1
        guard i < tokens.count, case .assignColon = tokens[i].type else { return false }
        return true
    }

    // True when the tokens at `start` look like the start of a brand new
    // Assignment/CompoundAssign/MultiAssign statement, rather than one more
    // item in a no-separator Expression list (PrintItems, ReturnStmt's exprs).
    // Without this, "? x" immediately followed by "x -: 1" would greedily eat
    // that second "x" as another print item, desyncing the rest of the parse.
    private func looksLikeNewStatement(at start: Int) -> Bool {
        if start < tokens.count, case .identifier = tokens[start].type, start + 1 < tokens.count {
            switch tokens[start + 1].type {
            case .assignColon, .equal, .plusAssign, .minusAssign: return true
            default: break
            }
        }
        if start < tokens.count, case .lAngle = tokens[start].type, looksLikeMultiAssignHeader(at: start) {
            return true
        }
        return false
    }

    private func startsTerm(_ type: TokenType) -> Bool {
        switch type {
        case .number, .stringLiteral, .identifier: return true
        default: return false
        }
    }

    // --- FunctionCall ::= Identifier "(" [ Expression { "," Expression } ] ")" ---
    // `name` has already been consumed by the caller; position is expected at "(".
    private func parseFunctionCall(name: String) throws -> FunctionCallNode {
        guard position < tokens.count, case .lParen = tokens[position].type else {
            throw ParseError.unexpectedToken("Expected '(' after function name '\(name)'")
        }
        position += 1
        var args: [ASTNode] = []
        if position < tokens.count, case .rParen = tokens[position].type {
            position += 1
            return FunctionCallNode(name: name, args: args)
        }
        while true {
            args.append(try parseExpr())
            if position < tokens.count, case .comma = tokens[position].type {
                position += 1
                continue
            }
            break
        }
        guard position < tokens.count, case .rParen = tokens[position].type else {
            throw ParseError.unexpectedToken("Expected ')' after arguments to '\(name)'")
        }
        position += 1
        return FunctionCallNode(name: name, args: args)
    }
}
