//
//  ifel.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 8/2/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation

extension Func {
    func removeComment(_ line: Substring) -> Substring {
        var x = line.components(separatedBy: "//")
        x.removeAll(where: { str in return str.isEmpty }) // remove nil components
        return Substring(x[0].trimmingCharacters(in: [" ", "\t"]))
    }
    
    func test(ic: Int, left: Double, right: Double) -> Bool {
        var passed: Bool = false
        switch(ic) {
        case 1: if left  < right { passed = true }
        case 2: if left == right { passed = true }
        case 3: if left  > right { passed = true }
        default:if left != right { passed = true }
        }
        
        return passed
    }

    func check(rhs: String) throws -> (Int?, Any, Any) {
        var i: Int = 0
        let rhx = rhs.unicodeScalars
        for c in ifc { // * ifc vector is declared in evalue.swift
            if rhx.filter({Character($0) == c}).count > 0 { break }
            i++
        }
        
        if  i > 5 { throw ParseError(line: line, kind: .unknownLogicalOperator) }
        let con = rhs.split(separator: String.Element(String(ifc[i])), maxSplits: 2, omittingEmptySubsequences: true)
        if  con.count > 2 { throw ParseError(line: line, kind: .complexLogicalOperator) }
        else if i < 2 {
            let c0 = con[0].trimmingCharacters(in: [" "])
            let c1 = con[1].trimmingCharacters(in: [" "])
            return (i, c0, c1)
        }
        
        let left = try eval(table: variable, rhs: String(con[0].trimmingCharacters(in: [" "])))
        let right = try eval(table: variable, rhs: String(con[1].trimmingCharacters(in: [" "])))
        return (i,left,right)
    }

    func anif(ikey: Int, stt: String) throws {
        ifstack.push(self.ifs) // push current if state
        if  history.index(forKey: line) != nil { // history of registered ifs
            ifs = history[line]!
            return
        }
        
        ifs = try registerif(ikey: ikey, stt: stt)
        history[line] = ifs // Store the if in history with line No as key
    }
    
    func registerif(ikey: Int, stt: String) throws -> Ifs {
        var ifs = Ifs(false, false, line, 0, false, 0)
        var x1 = stt.dropFirst(shalimar[ikey].count) // assumed if
        x1 = removeComment(x1)
        var y = x1.components(separatedBy: ["(",")"])
        y.removeAll(where: { str in return str.isEmpty }) // remove nil components
        
        if  y.count != 2 {
            throw ParseError(line: line, kind: .invalidStatement)
        }

        ifs.onlyif = true
        let y1 = y[1].trimmingCharacters(in: [" "])
        if  y1.contains("{") && y1.contains("}") {
            throw ParseError(line: line, kind: .invalidStatement)
        }

        ifs.blockif = (y1 == "{")

        var skip1 = 1
        var kount = line
        if  ifs.blockif {
            while(++kount < parent!.statements!.count) {
                let sline = Substring(parent!.statements![kount])
                x1 = removeComment(sline)
                if x1 == "{" || x1.contains("{") { skip1++ }
                if x1 == "}" || x1.contains("}") { skip1-- }
                if(x1 == "}" && skip1 == 0) { // excluding ending brace!
                    ifs.blockiflinecount = kount - line
                    break
                }
            }
        }
        
        if(++kount < parent!.statements!.count) {
            let sline = Substring(parent!.statements![kount])
            x1 = removeComment(sline)
            ifs.onlyif = !x1.starts(with: "else")
        }
        
        if(!ifs.onlyif) {
            x1 = x1.dropFirst(1+shalimar[1+ikey].count)
            ifs.blockelse = (x1 == "{")
            if ifs.blockelse {
                skip1 = 1
                while(++kount < parent!.statements!.count) {
                    let sline = Substring(parent!.statements![kount])
                    let y1 = removeComment(sline)
                    if y1 == "{" || y1.contains("{") { skip1++ }
                    if y1 == "}" || y1.contains("}") { skip1-- }
                    if(y1 == "}" && skip1==0) { // excluding starting else and ending brace lines
                        ifs.blockelselinecount = kount - (ifs.blockiflinecount + line + 1)
                        break
                    }
                }
            }
        }
        
        return ifs
    }
    
    func doif(ikey: Int, stt: String) throws {        
        var x = stt.dropFirst(shalimar[ikey].count)
        x = removeComment(x)
        var y = x.components(separatedBy: ["(",")"])
        y.removeAll(where: { str in return str.isEmpty }) // remove nil components
        if  y.count != 2 {
            throw ParseError(line: line, kind: .invalidStatement)
        }

        let (ic,left,right) = try check(rhs: y[0])
        let y1 = y[1].trimmingCharacters(in: [" "])
        if ic! > 1 {
            ifs.passif = test(ic: ic!-2, left: left as! Double, right: right as! Double)
            if ifs.passif! {
                if !ifs.blockif {
                    try parse(String(y1), line)
                    if ifs.onlyif { self.ifs = try self.ifstack.pop(line) }
                }
            } else {
                if ifs.blockif { line += ifs.blockiflinecount }
                else if ifs.onlyif {
                    self.ifs = try self.ifstack.pop(line)
                } // do nothing
            }
            return
        }
        
        let (ic0,left0,right0) = try check(rhs: left as! String)
        if ic0! <= 1 {
            throw ParseError(line: line, kind: .complexLogicalOperator)
        }
        
        ifs.passif = test(ic: ic0!-2, left: left0 as! Double, right: right0 as! Double)
        if ic==0 { // logical 'or' operator
            if ifs.passif! { // 1st cond passed so do the action
                if !ifs.blockif {
                    try parse(String(y1), line)
                    if ifs.onlyif { self.ifs = try self.ifstack.pop(line) }
                }
            } else {  // now check the 2nd cond
                let (ic1,left1,right1) = try check(rhs: right as! String)
                if ic1! <= 1 { throw ParseError(line: line, kind: .complexLogicalOperator) }
                
                ifs.passif = test(ic: ic1!-2, left: left1 as! Double, right: right1 as! Double)
                if ifs.passif! {
                    if !ifs.blockif {
                        try parse(String(y1), line)
                        if ifs.onlyif { self.ifs = try self.ifstack.pop(line) }
                    }
                } else {
                    if ifs.blockif  { line += ifs.blockiflinecount }
                    else if ifs.onlyif {
                        self.ifs = try self.ifstack.pop(line)
                    } // do nothing - one liner failed if with no else
                }
            }
            return
        }
        
        // logical 'and' operator
        if ifs.passif! { // 1st cond passed now check the 2nd cond
            let (ic1,left1,right1) = try check(rhs: right as! String)
            if ic1! <= 1 { throw ParseError(line: line, kind: .complexLogicalOperator) }
            
            ifs.passif = test(ic: ic1!-2, left: left1 as! Double, right: right1 as! Double)
            if ifs.passif! {
                if !ifs.blockif {
                    try parse(String(y1), line)
                    if ifs.onlyif { self.ifs = try self.ifstack.pop(line) }
                }
            } else {
                if ifs.blockif  { line += ifs.blockiflinecount }
                else if ifs.onlyif {
                    self.ifs = try self.ifstack.pop(line)
                } // do nothing
            }
        } else {
            if ifs.blockif  { line += ifs.blockiflinecount }
            else if ifs.onlyif {
                self.ifs = try self.ifstack.pop(line)
            } // do nothing
        }
    }

    func doelse(ikey: Int, stt: String) throws {
        if !ifs.onlyif {
            var x = stt.dropFirst(1+shalimar[ikey].count)
            x = removeComment(x)
            let y1 = x.trimmingCharacters(in: [" "])
            if !ifs.passif! { // is there an else statement - if so process it
                if !ifs.blockelse {
                    try parse(String(y1), line)
                    self.ifs = try self.ifstack.pop(line)
                }
            }
            else if ifs.blockelse {
                line += ifs.blockelselinecount
            }
            else {
                self.ifs = try self.ifstack.pop(line)
            } // do nothing - one liner failed else
        } else {
            throw ParseError(line: line, kind: .invalidStatement)
        }
    }

    func closeif(count: Int, line: String) throws -> Bool {
        if(ifs.blockif) {  // nested if block handling
            if(count == ifs.blockifline + ifs.blockiflinecount) {
                if ifs.onlyif { self.ifs = try self.ifstack.pop(count) }
                else { ifs.blockif = false }
                return true
            }
        }  // nesting if block handling
        else if(ifs.blockelse) {
            if(count == ifs.blockifline + ifs.blockiflinecount + ifs.blockelselinecount + 1) {
                self.ifs = try self.ifstack.pop(count)
                return true
            }
        }
        
        return false
    }
}
