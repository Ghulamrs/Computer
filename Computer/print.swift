//
//  print.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 7/27/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation

extension Function {
    
    func print(count: Int, line: String, symbols: [String: Double]) throws {
        if  line.isEmpty {
            throw ParseError(line: count, kind: .invalidStatement)
        }
        if  line.contains("'") {
            let x = line.split(separator: "'", maxSplits: 10, omittingEmptySubsequences: true)
            if  x.count == 1 {
                self.console.append("\(x[0]) ")
            } else {
                var first = line.starts(with: "'")
                for fmt in x {
                    if first { self.console.append(String(fmt)+" "); first = !first }
                    else {
                        let x = try eval(table: symbols, rhs: String(fmt.trimmingCharacters(in: [" ","\t",","])))
                        self.console.append(String(x)+" "); first = !first
                    }
                }
                self.console.append(" ")
            }
        } else if line.contains(",") {
            var start = true
            let valus = line.components(separatedBy: [",", " "])
            for valu in valus {
                if !valu.isEmpty {
                    if valu.contains(":") {
                        try printLoops(count: count, line: valu, symbols: symbols)
                    } else {
                        let value = try eval(table: symbols, rhs: valu)
                        let sval1 = String(format: "%.02f", value)
                        if start { self.console.append("\(sval1)"); start = false }
                        else { self.console.append(", \(sval1)") }
                    }
                }
            }
            self.console.append(" ")
        }
        else if line.contains(":") {
            try printLoops(count: count, line: line, symbols: symbols)
            self.console.append(" ")
        } else {
            let value = try eval(table: symbols, rhs: line)
            let sval1 = String(format: "%.02f", value)
            self.console.append("\(sval1) ")
        }
    }
    
    func printLoops(count: Int, line: String, symbols: [String: Double]) throws {
        var k, k1, k2: Int
        let valus = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: true)
        let kx = Int(valus[0])
        if  kx == nil {
            k = Int(try eval(table: symbols, rhs: String(valus[0])))
        } else { k = kx! }
        if valus.count > 2 {
            let  k1x = Int(valus[1])
            if   k1x == nil {
                k1 = Int(try eval(table: symbols, rhs: String(valus[1])))
            } else {
                k1 = k1x!
            }
            if k1 < 1 {
                throw ParseError(line: count, kind: .printLoopIncrementError)
            }
            let k2x = Int(valus[2])
            if  k2x == nil {
                k2 = Int(try eval(table: symbols, rhs: String(valus[2])))
            } else {
                k2 = k2x!
            }
        } else {
            k1 = 1
            let k2x = Int(valus[1])
            if  k2x == nil {
                k2 = Int(try eval(table: symbols, rhs: String(valus[1])))
            } else {
                k2 = k2x!
            }
        }
        while k < k2 {
            self.console.append(" \(k)")
            k += k1
        }
        if k <= k2 { self.console.append(" \(k)") }
    }

    func printn(count: Int, line: String, symbols: [String: Double]) throws {
        if line.isEmpty {
            self.console.append("\n")
        }
        else if  line.contains("'") {
            let x = line.split(separator: "'", maxSplits: 10, omittingEmptySubsequences: true)
            if  x.count == 1 {
                self.console.append("\(x[0])\n")
            } else {
                var first = line.starts(with: "'")
                for fmt in x {
                    if first { self.console.append(String(fmt)+" "); first = !first }
                    else {
                        let x = try eval(table: symbols, rhs: String(fmt.trimmingCharacters(in: [" ","\t",","])))
                        self.console.append(String(x)+" "); first = !first
                    }
                }
                self.console.append("\n")
            }
        } else if line.contains(",") {
            var start = true
            let valus = line.components(separatedBy: [",", " "])
            for valu in valus {
                if !valu.isEmpty {
                    if valu.contains(":") {
                        try printLoops(count: count, line: valu, symbols: symbols)
                    } else {
                        let value = try eval(table: symbols, rhs: valu)
                        let sval1 = String(format: "%.02f", value)
                        if start { self.console.append("\(sval1)"); start = false }
                        else { self.console.append(", \(sval1)") }
                    }
                }
            }
            self.console.append("\n")
        }
        else if line.contains(":") {
            try printLoops(count: count, line: line, symbols: symbols)
            self.console.append("\n")
        } else {
            let value = try eval(table: symbols, rhs: line)
            let sval1 = String(format: "%.02f", value)
            self.console.append("\(sval1)\n")
        }
    }
    
    func printnLoops(count: Int, line: String, symbols: [String: Double]) throws {
        var k, k1, k2: Int
        let valus = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: true)
        let kx = Int(valus[0])
        if  kx == nil {
            k = Int(try eval(table: symbols, rhs: String(valus[0])))
        } else { k = kx! }
        if valus.count > 2 {
            let  k1x = Int(valus[1])
            if   k1x == nil {
                k1 = Int(try eval(table: symbols, rhs: String(valus[1])))
            } else {
                k1 = k1x!
            }
            if k1 < 1 {
                throw ParseError(line: count, kind: .printLoopIncrementError)
            }
            let k2x = Int(valus[2])
            if  k2x == nil {
                k2 = Int(try eval(table: symbols, rhs: String(valus[2])))
            } else {
                k2 = k2x!
            }
        } else {
            k1 = 1
            let k2x = Int(valus[1])
            if  k2x == nil {
                k2 = Int(try eval(table: symbols, rhs: String(valus[1])))
            } else {
                k2 = k2x!
            }
        }
        while k < k2 {
            self.console.append(" \(k)")
            k += k1
        }
        if k <= k2 { self.console.append(" \(k)") }
    }
}
