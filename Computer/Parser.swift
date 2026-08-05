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
    case printNotAtLineStart(String)

    // The error without its "Parse error: " prefix, so a line number can be inserted between the
    // two by LocatedParseError rather than spliced into a finished string.
    var message: String {
        switch self {
        case .unexpectedToken(let tok): return "Unexpected token '\(tok)'"
        case .printNotAtLineStart(let cmd): return "'\(cmd)' must be the first thing on its line"
        case .invalidAssignmentOperator(let tok): return "Invalid assignment operator '\(tok)'. Use ':' instead."
        case .missingOpeningBrace: return "Missing '{' to start block"
        case .missingClosingBrace: return "Missing '}' to close block"
        }
    }

    var description: String { "Parse error: \(message)" }
}

// A ParseError plus the line it was raised on. Parsing stops at the first error, and `parseProgram`
// is the one place that records it, so the line is attached there once instead of at each of the
// ten-odd throw sites - none of which would otherwise need to know a line number exists.
struct LocatedParseError: Error, CustomStringConvertible {
    let error: ParseError
    let line: Int

    var description: String { "Parse error: line \(line): \(error.message)" }
}

// =======================
// AST Node Definitions
// =======================

protocol ASTNode {}

// Statements record the source line they begin on; expressions deliberately do not. A runtime
// error is reported against the statement being executed, which is the granularity the language
// needs and keeps a line number off every NumberNode. `Interpreter.evaluate` updates its notion of
// the current line whenever it is handed one of these - see §10.3.
protocol StatementNode: ASTNode {
    var line: Int { get }
}

struct NumberNode: ASTNode { let value: Double }
struct StringNode: ASTNode { let value: String }
struct VariableNode: ASTNode { let name: String }

struct AssignmentNode: StatementNode {
    let variable: String
    let expr: ASTNode
    let line: Int
}

struct CompoundAssignNode: StatementNode {
    enum Op { case plus, minus }
    let variable: String
    let op: Op
    let expr: ASTNode
    let line: Int
}

struct MultiAssignNode: StatementNode {
    let variables: [String]
    let call: FunctionCallNode
    let line: Int
}

struct ReturnNode: StatementNode {
    let exprs: [ASTNode]
    let line: Int
}

struct FunctionDefNode: StatementNode {
    let name: String
    let inputs: [String]
    let outputs: [String]
    let body: [ASTNode]
    let line: Int
}

// Both an expression and a statement: `f(1)` on its own line is a legal statement (§7.1), so it
// carries a line like any other - otherwise a bad bare call would be reported against whatever
// statement happened to run before it.
struct FunctionCallNode: StatementNode {
    let name: String
    let args: [ASTNode]
    let line: Int
}

struct IfElseChainNode: StatementNode {
    let branches: [(ASTNode, [ASTNode])]
    let elseBranch: [ASTNode]?
    let line: Int
}

struct WhileNode: StatementNode {
    let condition: ASTNode
    let body: [ASTNode]
    let line: Int
}

struct ForLoopNode: StatementNode {
    let variable: String
    let startExpr: ASTNode
    let endExpr: ASTNode
    let stepExpr: ASTNode
    let body: [ASTNode]
    let line: Int
}

struct PrintNode: StatementNode {
    let items: [ASTNode]
    let newline: Bool
    let line: Int
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
    private var currentIndex: Int = 0
    private(set) var parseError: Error?

    init(tokens: [Token]) {
        self.tokens = tokens
    }

    // EOF is virtual: `Lexer.tokenize()` never appends a `.eof` token, so `tokens` contains
    // only real ones and `.eof` is manufactured here on demand once the index runs past the
    // end. That is what lets `consume`/`match` report a clean "Unexpected token 'eof'" at
    // end of input instead of indexing out of bounds.
    //
    // Two consequences worth knowing before changing this:
    //  - `currentToken.type == .eof` is exactly equivalent to `currentIndex >= tokens.count`,
    //    so pairing the two in one condition is redundant - test either, not both.
    //  - Loops that stop on end of input by checking `currentIndex < tokens.count` (parseBlock,
    //    for one) depend on there being no terminator token. Emitting a real `.eof` would make
    //    that guard stop firing and downgrade "Missing '}' to close block" to a generic
    //    unexpected-token error.
    private var currentToken: Token {
        // The synthetic eof borrows the last real token's line so an end-of-input error ("Missing
        // '}' to close block") is reported against the end of the program rather than line 0.
        return currentIndex < tokens.count ? tokens[currentIndex]
                                           : Token(type: .eof, line: tokens.last?.line ?? 1)
    }

    private func advance() {
        currentIndex += 1
    }

    private func match(_ type: TokenType) -> Bool {
        if currentToken.type == type {
            advance()
            return true
        }
        return false
    }

    private func consume(_ expected: TokenType) throws -> Token {
        guard currentToken.type == expected else {
            throw ParseError.unexpectedToken("\(currentToken.type)")
        }
        let tok = currentToken
        advance()
        return tok
    }

    private func consumeIdentifier() throws -> String {
        guard case .identifier(let name) = currentToken.type else {
            throw ParseError.unexpectedToken("\(currentToken.type)")
        }
        advance()
        return name
    }

    func parseProgram() -> [ASTNode] {
        var nodes: [ASTNode] = []
        while currentIndex < tokens.count {
            do {
                nodes.append(try parseExpression())
            } catch let error as ParseError {
                // Must be recorded, not just printed: ComputeViewController checks
                // parser.parseError to decide whether to show the error and stop. A bare
                // print() only reaches Xcode's console, leaving the app to run a truncated
                // AST and report a misleading "No main() function defined" instead.
                //
                // `currentIndex` still sits on the token that failed - throwing unwinds without
                // advancing - so the current token's line is the line to report.
                parseError = LocatedParseError(error: error, line: currentToken.line)
                break
            } catch {
                parseError = error
                break
            }
        }
        return nodes
    }

    func parseExpression() throws -> ASTNode {
        return try parseStatement()
    }

    func parseStatement() throws -> ASTNode {
        // Captured before anything is consumed, so every statement is attributed to the line it
        // opens on rather than the line its last token happens to fall on.
        let line = currentToken.line
        switch currentToken.type {
        case .identifier(let name):
            advance()
            switch currentToken.type {
            case .assignColon:
                _ = try consume(.assignColon)
                let expr = try parseExpr()
                return AssignmentNode(variable: name, expr: expr, line: line)
            case .plusAssign:
                _ = try consume(.plusAssign)
                let expr = try parseExpr()
                return CompoundAssignNode(variable: name, op: .plus, expr: expr, line: line)
            case .minusAssign:
                _ = try consume(.minusAssign)
                let expr = try parseExpr()
                return CompoundAssignNode(variable: name, op: .minus, expr: expr, line: line)
            case .equal:
                // Fallback assignment, per SHALIMAR_LANGUAGE.md §2.5. Deliberately a bare
                // print() and not `output`, so this warning reaches Xcode's console only -
                // see §10.4, which documents that asymmetry.
                print("Warning: '=' used for assignment. Use ':' instead.")
                _ = try consume(.equal)
                let expr = try parseExpr()
                return AssignmentNode(variable: name, expr: expr, line: line)
            default:
                // Not an assignment of any kind, so this identifier begins an expression
                // statement - most importantly a bare call like `f(4)`, which §7.1 requires
                // to be legal. Rewind over the identifier and let the expression parser
                // handle it; throwing here would reject documented programs.
                currentIndex -= 1
                return try parseExpr()
            }

        case .lAngle:
            if looksLikeMultiAssignHeader(at: currentIndex) {
                _ = try consume(.lAngle)
                var vars: [String] = []
                while true {
                    if case .identifier(let v) = currentToken.type {
                        vars.append(v); advance()
                    } else if match(.comma) {
                        continue
                    } else if match(.rAngle) {
                        break
                    } else {
                        throw ParseError.unexpectedToken("\(currentToken.type)")
                    }
                }
                _ = try consume(.assignColon)
                let fname = try consumeIdentifier()
                let call = try parseFunctionCall(name: fname)
                return MultiAssignNode(variables: vars, call: call, line: line)
            }
            throw ParseError.unexpectedToken("Unexpected '<'")

        case .returnKeyword:
            _ = try consume(.returnKeyword)
            var exprs: [ASTNode] = []
            // `}` and end-of-input must stop the item list as well as a new-statement
            // lookalike: looksLikeNewStatement only recognizes assignment shapes and
            // multi-assign headers, so without these guards `return x }` tries to parse
            // the closing brace as an expression and every function fails to parse.
            // (End of input is the `currentIndex` test - see the note on `currentToken`.)
            while currentIndex < tokens.count,
                  currentToken.type != .rBrace,
                  !looksLikeNewStatement(at: currentIndex) {
                exprs.append(try parseExpr())
            }
            return ReturnNode(exprs: exprs, line: line)

        case .printLine:
            try requireLineStart("?")
            _ = try consume(.printLine)
            return try parsePrint(newline: true, line: line)
        case .printInline:
            try requireLineStart("??")
            _ = try consume(.printInline)
            return try parsePrint(newline: false, line: line)

        case .ifKeyword:
            return try parseIfElseChain()
        case .whileKeyword:
            return try parseWhile()
        case .forKeyword:
            return try parseForLoop()
        case .funKeyword:
            return try parseFunctionDef()

        default:
            return try parseExpr()
        }
    }
    
    func parseBlock() throws -> [ASTNode] {
        _ = try consume(.lBrace)
        var stmts: [ASTNode] = []
        while currentToken.type != .rBrace {
            guard currentIndex < tokens.count else {
                throw ParseError.missingClosingBrace
            }
            stmts.append(try parseExpression())
        }
        _ = try consume(.rBrace)
        return stmts
    }
    
    func parseIfElseChain() throws -> ASTNode {
        let line = currentToken.line
        _ = try consume(.ifKeyword)
        let cond = try parseExpr()
        let body = try parseBlock()
        var branches: [(ASTNode, [ASTNode])] = [(cond, body)]

        while match(.elseifKeyword) {
            let cond = try parseExpr()
            let body = try parseBlock()
            branches.append((cond, body))
        }

        var elseBranch: [ASTNode]? = nil
        if match(.elseKeyword) {
            elseBranch = try parseBlock()
        }
        return IfElseChainNode(branches: branches, elseBranch: elseBranch, line: line)
    }

    func parseWhile() throws -> ASTNode {
        let line = currentToken.line
        _ = try consume(.whileKeyword)
        let cond = try parseExpr()
        let body = try parseBlock()
        return WhileNode(condition: cond, body: body, line: line)
    }

    func parseForLoop() throws -> ASTNode {
        let line = currentToken.line
        _ = try consume(.forKeyword)
        let varName = try consumeIdentifier()
        _ = try consume(.assignColon)
        let startExpr = try parseExpr()
        _ = try consume(.toKeyword)
        let endExpr = try parseExpr()

        var stepExpr: ASTNode = NumberNode(value: 1.0)
        if match(.stepKeyword) {
            stepExpr = try parseExpr()
        }

        let body = try parseBlock()
        return ForLoopNode(variable:  varName,
                           startExpr: startExpr,
                           endExpr:   endExpr,
                           stepExpr:  stepExpr,
                           body:      body,
                           line:      line)
    }

    func parseFunctionDef() throws -> ASTNode {
        let line = currentToken.line
        _ = try consume(.funKeyword)

        var outputs: [String] = []
        if match(.lAngle) {
            while true {
                switch currentToken.type {
                case .identifier(let outName):
                    outputs.append(outName); advance()
                case .comma:
                    advance()
                case .rAngle:
                    advance(); break
                default:
                    throw ParseError.unexpectedToken("\(currentToken.type)")
                }
                if currentToken.type == .equal { break }
            }
        }

        _ = try consume(.equal)
        let name = try consumeIdentifier()
        _ = try consume(.lParen)

        var inputs: [String] = []
        while currentToken.type != .rParen {
            switch currentToken.type {
            case .identifier(let arg):
                inputs.append(arg); advance()
            case .comma:
                advance()
            default:
                throw ParseError.unexpectedToken("\(currentToken.type)")
            }
        }
        _ = try consume(.rParen)

        let body = try parseBlock()
        return FunctionDefNode(name: name, inputs: inputs, outputs: outputs, body: body, line: line)
    }

    // `line` is the print command's own line, passed in because the caller has already consumed it.
    func parsePrint(newline: Bool, line: Int) throws -> ASTNode {
        var items: [ASTNode] = []
        while currentIndex < tokens.count,
              startsTerm(currentToken.type),
              !looksLikeNewStatement(at: currentIndex) {
            items.append(try parseExpr())
        }
        return PrintNode(items: items, newline: newline, line: line)
    }
    
    func parseTerm() throws -> ASTNode {
        let token = currentToken
        advance()
        switch token.type {
        case .number(let value):
            return NumberNode(value: value)
        case .stringLiteral(let str):
            return StringNode(value: str)
        case .identifier(let name):
            if currentToken.type == .lParen {
                return try parseFunctionCall(name: name)
            }
            return VariableNode(name: name)
        case .minus:
            let operand = try parseTerm()
            if let num = operand as? NumberNode {
                return NumberNode(value: -num.value)
            }
            return BinaryOpNode(left: NumberNode(value: 0), right: operand, op: .minus)
        case .lParen:
            let expr = try parseExpr()
            _ = try consume(.rParen)
            return expr
        default:
            throw ParseError.unexpectedToken("\(token.type)")
        }
    }


    // --- Expression, by precedence (lowest to highest binding):
    //     "|"  <  "&"  <  "=" "!=" "<" ">"  <  "+" "-"  <  "*" "/" "%"  <  Term
    func parseExpr() throws -> ASTNode {
        return try parseOr()
    }

    private func parseOr() throws -> ASTNode {
        var left = try parseAnd()
        while match(.or) {
            let right = try parseAnd()
            left = BinaryOpNode(left: left, right: right, op: .or)
        }
        return left
    }

    private func parseAnd() throws -> ASTNode {
        var left = try parseComparison()
        while match(.and) {
            let right = try parseComparison()
            left = BinaryOpNode(left: left, right: right, op: .and)
        }
        return left
    }

    private func parseComparison() throws -> ASTNode {
        var left = try parseAdditive()
        while true {
            if currentToken.type == .lAngle,
               looksLikeMultiAssignHeader(at: currentIndex) {
                break
            }
            guard let op = comparisonOperator(for: currentToken.type) else { break }
            advance()
            let right = try parseAdditive()
            left = BinaryOpNode(left: left, right: right, op: op)
        }
        return left
    }

    func parseAdditive() throws -> ASTNode {
        var left = try parseMultiplicative()
        while let op = additiveOperator(for: currentToken.type) {
            advance()
            let right = try parseMultiplicative()
            left = BinaryOpNode(left: left, right: right, op: op)
        }
        return left
    }

    func parseMultiplicative() throws -> ASTNode {
        var left = try parsePower()
        while let op = multiplicativeOperator(for: currentToken.type) {
            advance()
            let right = try parsePower()
            left = BinaryOpNode(left: left, right: right, op: op)
        }
        return left
    }

    func parsePower() throws -> ASTNode {
        let left = try parseTerm()
        if currentToken.type == .caret {
            advance()
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
    // A print command must open its own line (§5.10). This is the only rule in the language that
    // consults source layout at all - everywhere else newlines are plain whitespace - so it is the
    // only reason `Token` carries a line number.
    //
    // It is also what makes "one print command per line" enforceable. `? x ?? y` parses as two
    // statements, exactly as it would on two lines, because `?`/`??` cannot begin a print *item*
    // and so end the first item list; without this check the two forms are indistinguishable and
    // both run. Here the second command fails, since a token preceded on the same line by another
    // token does not start that line.
    private func requireLineStart(_ command: String) throws {
        guard startsLine(at: currentIndex) else {
            throw ParseError.printNotAtLineStart(command)
        }
    }

    // The first token of the program starts a line by definition; any other token does so only if
    // the token before it belongs to an earlier line. Leading indentation is irrelevant - the lexer
    // has already dropped it, which is what makes an indented `? x` inside a block legal.
    private func startsLine(at index: Int) -> Bool {
        guard index < tokens.count else { return false }
        guard index > 0 else { return true }
        return tokens[index - 1].line < tokens[index].line
    }

    private func looksLikeNewStatement(at start: Int) -> Bool {
        if start < tokens.count, case .identifier = tokens[start].type, start + 1 < tokens.count {
            switch tokens[start + 1].type {
            case .assignColon, .equal, .plusAssign, .minusAssign: return true
            default: break
            }
        }
        if start < tokens.count, case .lAngle = tokens[start].type,
           looksLikeMultiAssignHeader(at: start) {
            return true
        }
        return false
    }

    private func startsTerm(_ type: TokenType) -> Bool {
        switch type {
        // .minus and .lParen matter for print item lists: without them `? -2^2` and
        // `? (1+2)` collect zero items and print a blank line, because parsePrint stops
        // as soon as the next token doesn't look like the start of a term.
        case .number, .stringLiteral, .identifier, .minus, .lParen: return true
        default: return false
        }
    }

    // --- FunctionCall ::= Identifier "(" [ Expression { "," Expression } ] ")" ---
    // `name` has already been consumed by the caller; position is expected at "(".
    func parseFunctionCall(name: String) throws -> FunctionCallNode {
        // The "(" line, not the identifier's - the identifier is already consumed, and the two are
        // on the same line in anything but pathological formatting.
        let line = currentToken.line
        _ = try consume(.lParen)
        var args: [ASTNode] = []
        if match(.rParen) {
            return FunctionCallNode(name: name, args: args, line: line)
        }
        while true {
            args.append(try parseExpr())
            if match(.comma) { continue }
            break
        }
        _ = try consume(.rParen)
        return FunctionCallNode(name: name, args: args, line: line)
    }
}
