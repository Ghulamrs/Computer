//
//  Eval.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 8/28/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation
extension Int { // Increment
    @discardableResult static prefix  func ++( x: inout Int) -> Int { x += 1; return x }
    @discardableResult static postfix func ++( x: inout Int) -> Int { x += 1; return (x - 1) }
    @discardableResult static prefix  func --( x: inout Int) -> Int { x -= 1; return x }
    @discardableResult static postfix func --( x: inout Int) -> Int { x -= 1; return (x - 1) }
}

class Eval {
    var line: Int = 0
    let shalimar: [String] = ["exit", "for", "}", "if", "else", "goto", "printn", "print", "fun", "return"]
    func generator() -> String { // updated on August 30, 2019
        let letterset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        return String((0..<10).map { _ in letterset.randomElement()! })
    }

    func minOp(_ rhs: String) -> Int {
        if !rhs.starts(with: "-") { return 2 }
        return conOp(String(rhs.dropFirst()))
    }

    func conOp(_ rhs: String) -> Int {
        var res: Int = 0
        // '(' updated on 29/8/2019
        if rhs.first == "(" || rhs.contains("(") && !rhs[rhs.index(before: rhs.firstIndex(of: "(")!)].isLetter { res = 7 }
        else if rhs.contains("+") { res = 1 }
        else if rhs.contains("-") { res = minOp(rhs) }
        else if rhs.contains("*") { res = 3 }
        else if rhs.contains("/") { res = 4 }
        else if rhs.contains("%") { res = 5 }
        else if rhs.contains("^") { res = 6 }

        return res
    }

    func lookup(table: [String:Double], rhs: String) throws -> Double {
        var ors = rhs
        if  rhs.starts(with: "-") { ors.removeFirst() }
        let index = table.index(forKey: ors) // a local variable
        if  index == nil {
            throw ParseError(line: line, kind: .undeclaredVariable)
        }
        
        let x1 = table[ors]!
        if  rhs.starts(with: "-") { return -x1 }
        return x1
    }

    func eval(table: [String:Double], kev: [Substring], v: inout [Double]) throws -> Int {
        for i in 0..<kev.count {
            var s = String(kev[i].trimmingCharacters(in: [" "]))
            let os = conOp(s)
            if  os > 0 {
                guard let x = try? eval(table: table, rhs: s) else {
                    throw ParseError(line: line, kind: .undeclaredVariable)
                }
                v.append(x)
            }
            else if let f = Math.mathFun(&s) {
                let dx = try? eval(table: table, rhs: s)
                let x = try Math.evalFun(f, dx!)
                v.append(x!)
            }
            else {
                guard let x = Double(s) else {
                    let x1 = try lookup(table: table, rhs: s)
                    v.append(x1)
                    continue
                }
                v.append(x)
            }
        }
        
        return v.count
    }
    
    func eval(table: [String: Double], rhs: String) throws -> Double {
        var table1:[String: Double]?
        var v1: Double = 0.0
        var v = [Double]()
        
        switch(conOp(rhs)) {
        case 1:
            let kev = rhs.split(separator: "+", maxSplits: 5, omittingEmptySubsequences: true)
            guard try eval(table: table, kev: kev, v: &v) > 0 else {
                throw ParseError(line: line, kind: .undeclaredVariable)
            }
            v1 = v[0]
            for vs in 1..<v.count {
                v1 += v[vs]
            }
        case 2:
            let kev = rhs.split(separator: "-", maxSplits: 5, omittingEmptySubsequences: true)
            guard try eval(table: table, kev: kev, v: &v) > 0 else {
                throw ParseError(line: line, kind: .undeclaredVariable)
            }
            v1 = rhs.starts(with: "-") ? -v[0] : v[0]
            for vs in 1..<v.count {
                v1 -= v[vs]
            }
        case 3:
            let kev = rhs.split(separator: "*", maxSplits: 5, omittingEmptySubsequences: true)
            guard try eval(table: table, kev: kev, v: &v) > 0 else {
                throw ParseError(line: line, kind: .undeclaredVariable)
            }
            v1 = v[0]
            for vs in 1..<v.count  {
                v1 *= v[vs]
            }
        case 4:
            let kev = rhs.split(separator: "/", maxSplits: 4, omittingEmptySubsequences: true)
            guard try eval(table: table, kev: kev, v: &v) > 0 else {
                throw ParseError(line: line, kind: .undeclaredVariable)
            }
            v1 = v[0]
            for vs in 1..<v.count  {
                v1 /= v[vs]
            }
        case 5:
            let kev = rhs.split(separator: "%", maxSplits: 2, omittingEmptySubsequences: true)
            guard try eval(table: table, kev: kev, v: &v) > 0 else {
                throw ParseError(line: line, kind: .undeclaredVariable)
            }
            v1 = v[0]
            for vs in 1..<v.count  {
                v1 = v1.truncatingRemainder(dividingBy: v[vs])
            }
        case 6:
            let kev = rhs.split(separator: "^", maxSplits: 2, omittingEmptySubsequences: true)
            guard try eval(table: table, kev: kev, v: &v) > 0 else {
                throw ParseError(line: line, kind: .undeclaredVariable)
            }
            v1 = v[0]
            for _ in 1..<Int(v[1])  {
                v1 *= v[0]
            }
        case 7: // updated on August 27, 2019
            var _rhs = rhs
            let vals = rhs.exprs // class expression - extention of String ( file parenthesis.swift )
            table1 = table // temporary table copy, to add temp vars
            for val in vals {
                let rep = "(" + val.string + ")"
                let key = generator()
                _rhs = _rhs.replacingOccurrences(of: rep, with: key)
                table1![key] = try! eval(table: table, rhs: val.string)
            }
            v1 = try! eval(table: table1!, rhs: _rhs)
        default:
            guard let x = Double(rhs) else {
                return try lookup(table: table, rhs: rhs)
            }
            return x
        }
        return v1
    }
}
