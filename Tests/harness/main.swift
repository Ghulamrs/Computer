//
//  main.swift
//  Shalimar regression harness
//
//  A command-line driver for the language core, used by Tests/regression.sh.
//  The core (Lexer/Parser/Interpreter) is pure Foundation with no UIKit
//  dependency, so it compiles and runs outside the app - which is what makes a
//  fast regression suite possible without an Xcode test target.
//
//  Mirrors ComputeViewController.ComputeTapped deliberately: lex, check
//  lexError, parse, check parseError, then run. If that order ever drifts from
//  the app, this harness stops testing what the app actually does.
//
//  Usage:  shalimar <file.shm>
//  Exit:   0 on a clean run, 1 on a lex or parse error.
//

import Foundation

guard CommandLine.arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: shalimar <file.shm>\n".utf8))
    exit(2)
}

let path = CommandLine.arguments[1]
guard let source = try? String(contentsOfFile: path, encoding: .utf8) else {
    FileHandle.standardError.write(Data("cannot read \(path)\n".utf8))
    exit(2)
}

let lexer = Lexer(input: source)
let tokens = lexer.tokenize()
if let lexError = lexer.lexError {
    print(lexError)
    exit(1)
}

let parser = Parser(tokens: tokens)
let ast = parser.parseProgram()
if let parseError = parser.parseError {
    print("PARSE: \(parseError)")
    exit(1)
}

let interpreter = Interpreter()
interpreter.output = { print($0, terminator: "") }
interpreter.runProgram(ast)
