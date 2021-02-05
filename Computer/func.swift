//
//  func.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 6/19/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation
struct Ifs {
    var onlyif: Bool
    var blockif: Bool
    var blockifline: Int
    var blockiflinecount: Int
    var blockelse: Bool
    var blockelselinecount: Int
    var passif: Bool?
    init(_ oi: Bool, _ bi: Bool, _ bil: Int, _ bilc: Int, _ be: Bool, _ belc: Int) {
        self.onlyif = oi
        self.blockif = bi
        self.blockifline = bil
        self.blockiflinecount = bilc
        self.blockelse = be
        self.blockelselinecount = belc
    }
}

struct Stack<Element> {
    var items = [Element]()
    mutating func push(_ item: Element) {
        items.append(item)
    }
    mutating func pop(_ count: Int) throws -> Element {
        if items.count > 0 {
            return items.removeLast()
        } else {
            throw ParseError(line: count, kind: .ifStackUnderflow)
        }
    }
}

class Func: Eval {
    var lineStart: Int
    var lineCount: Int
    var argNames = [Int: String]()
    var resNames = [Int: String]()
    var variable = [String: Double]()
    var history  = [Int: Ifs]() // history[line: ifs] - record of if registered
    var ifstack = Stack<Ifs>()
    var parent: Function?
    var loops = [Int: looooooop]()
    var loop: Loop?
    var mask: Int?
    var ifs: Ifs

    let ifc: [Character] = ["|", "&", "!", "<", "=", ">"]
    init(_ funp: Function, sline: Int, nlines: Int, arg: [String], res: [String]) {
        self.parent = funp
        
        self.lineStart = sline
        self.lineCount = nlines
        for i in 0..<arg.count { self.argNames[i] = arg[i] }
        for i in 0..<res.count { self.resNames[i] = res[i] }
        self.mask = 0
        
        self.loop = Loop()
        self.ifs = Ifs(false, false, 0, 0, false, 0)
    }

    func isaVar(_ v: String) -> Bool {
        var u: String = v
        if  u.starts(with: "-") { u = String(u.dropFirst()) } // -ve value, ok
        var charSet = CharacterSet.letters
            charSet.formUnion(CharacterSet.decimalDigits) // digits
            charSet.formUnion(CharacterSet(["_"])) // underscore
        let delimiterSet = charSet.inverted
        return u == u.components(separatedBy: delimiterSet)[0]
    }
    
    func gotose(ikey: Int, stt: String) throws {
        let sline = String(stt.dropFirst(1+shalimar[ikey].count))
        guard let x = Int(sline) else {
            throw ParseError(line: line, kind: .invalidLineNumber)
        }
        
        let countx = line + x
        if  countx == line || countx < lineStart || countx >= lineStart+lineCount {
            throw ParseError(line: line, kind: .invalidLineNumber)
        }
        line = countx
    }
    
    func proc(ikey: Int, stt: String) throws {
        switch(ikey) {
        case 0: if  stt.count == shalimar[ikey].count { line = parent!.statements!.count } // exit
        case 1: let (_,len) = parent!.find_len(count: line);
                try loop!.setup(stt: stt, symbol: &variable, loops: &loops, count: line, length: len)
        case 2: try loop!.exec(stt: stt, symbol: &variable, loops: &loops, count: &line)
        case 3: try anif(ikey: ikey, stt: stt) // setup if block
                try doif( ikey: ikey, stt: stt)  // if
        case 4: try doelse(ikey: ikey, stt: stt) // else
        case 5: try gotose(ikey: ikey, stt: stt) // goto
        case 6: let st1 = String(stt.dropFirst(1+shalimar[ikey].count))
                try parent!.printn(count: line, line: st1, symbols: variable)
        case 7: let st1 = String(stt.dropFirst(1+shalimar[ikey].count))
                try parent!.print(count: line, line: st1, symbols: variable)
        case 8: _ = try parent!.add(count: line)// func registeration
        case 9: if stt.count == shalimar[ikey].count { line = lineStart+lineCount }
        default: // func call
            let x = try parent!.call(ccount: line, stt: stt, symbols: variable)
            for v in x { variable[v.key] = v.value } // copy returned values
        }
    }

    func set(key: String, value: Double) throws {
        if isaVar(key) == false {
            throw ParseError(line: line, kind: .invalidVariableName)
        } else {
            variable[key] = value
        }
    }

    public func parse(_ stmt: String, _ aline: Int) throws {
        line = aline
        var word = stmt.split(separator: "=")
        if  word.count < 2 {
            word = stmt.split(separator: " ")
        }

        guard let ik = parent!.isaKey(stmt)         else {
            guard try parent!.isaFunc(stmt) != nil      else {

                if word.count < 2 {
                    throw ParseError(line: line, kind: .invalidStatement)
                }
                let key   = word[0].trimmingCharacters(in: [" "])
                var value = word[1].trimmingCharacters(in: [" "])

                guard let fn = Math.mathFun(&value) else {
                    guard let x = Double(value)     else {

                        let el = try eval(table: variable, rhs: value)
                        try set(key: key, value: el)
                        return
                    }

                    try set(key: key, value: x) // variable[key] = value
                    return
                }

                let dx = try? eval(table: variable, rhs: value)
                if  dx == nil { throw ParseError(line: line, kind: .undeclaredVariable) }
                let ef = try? Math.evalFun(fn, dx!)
                if  ef == nil { throw ParseError(line: line, kind: .undeclaredVariable) }
                try set(key: key, value: ef!)
                return
            }
            
            try proc(ikey: 10, stt: String(stmt)) // to call case default
            return
        }
        
        try proc(ikey: ik, stt: String(stmt))
    }

    public func parseall(stmts: [String.SubSequence], fun: String, from: Int, many: Int) throws -> Int {
        var hung = 0
        var skip1 = 0
        var kount = -1
        while(++kount < many) {
            let count = from + kount
            if  count == stmts.count {
                throw ParseError(line: count, kind: .unexpectedEndOfFile)
            }
            var sline = String(stmts[count].trimmingCharacters(in: [" ", "\t"]))
            if  sline.starts(with: "//") { continue }
            if  sline.contains("//") {
                let stmt = sline.components(separatedBy: "//")
                sline = stmt[0].trimmingCharacters(in: [" ", "\t"])
            }

            if !parent!.register && sline=="}" { 
                let ifclosed = try closeif(count: count, line: sline)
                if  ifclosed { continue }
            }
            if (parent!.register && sline.contains("{")) || sline.starts(with: "/*") { skip1+=1 }
            if (parent!.register && sline.contains("}")) || sline.starts(with: "*/") { skip1-=1
                sline = sline.dropFirst(2).trimmingCharacters(in: [" ","\t"])
                if skip1 <= 0  { parent!.register = false }
                if sline.isEmpty { continue } // last skip line
            }
            if  skip1 > 0 { continue }
            hung += 1
            try parse(sline, count)
            if  line != count {
                let delta = count - line
                if kount >= delta { kount -= delta+1 }
            }
            if hung==10000 { break }
        }
        
        return hung
    }
}

class Function : Eval {
    var console: String
    var register = false
    var funcTable = [String: Func]()
    var statements: [String.SubSequence]?

    init(source: String) {
        statements = source.split(separator: "\n")
        self.console = ""
    }
    
    func isaKey(_ f: String) -> Int? {
        if f.trimmingCharacters(in: [" "]).isEmpty { return nil }
        var words = f.components(separatedBy: ["+","-","*","/","%","^", "(",")"," "])
        words.removeAll(where: { str in return str.isEmpty })
        return shalimar.firstIndex(of: words[0])
    }

    public func consoleOutput() -> String {
        return console
    }
    
    func add(count: Int) throws -> String {
        let stt = String(statements![count]).trimmingCharacters(in: [" "])
        let cmd = stt.dropFirst(1+shalimar[8].count) // fun - case 8 of proc
        var (arg, res) = arg_fun(cmd: String(cmd))!
        if  arg.count == 0 {
            throw ParseError(line: count, kind: .missingFunctionName)
        }
        
        let fun = arg.remove(at: 0)
        if  shalimar.firstIndex(of: fun) != nil {
            throw ParseError(line: count, kind: .keywordFunctionName)
        }
        
        let index = funcTable.index(forKey: fun)
        if  index != nil {
            throw ParseError(line: count, kind: .alreadyRegisteredFunction)
        }
        let (s,c) = find_len(count: count)
        funcTable[fun] = Func(self, sline: s, nlines: c, arg: arg, res: res)
        register = true
        
        return fun
    }
    
    func isaFunc(_ f: String) throws -> Bool? {
        if  f.contains("(") && f.count > 2 &&
            !(f[f.index(before: f.firstIndex(of: "(")!)].isMathSymbol ||
              f[f.index(before: f.firstIndex(of: "(")!)].isPunctuation) {
            let comp = f.components(separatedBy: "(")
            let comq = comp[0].components(separatedBy: "=")
            if  comq.count < 2 {
                throw ParseError(line: line, kind: .badKeywordOrFunctionName)
            }
            let fun1 = comq[1].trimmingCharacters(in: [" "])
            if  funcTable.index(forKey: fun1) != nil {
                return true
            }
        }
        
        return nil
    }
    
    func find_len(count:Int) -> (Int, Int) {
        var start = 0
        var level = 0
        var howmany = 1
        var kount = count - 1
        
        while(++kount < statements!.count) {
            let line = statements![kount]
            if line.contains("{") {
                level++
                if start == 0 { start = kount+1 }
            }
            if line.contains("}") {
                level--
                if level == 0 { howmany = kount-start; break }
            }
        }
        return (start, howmany)
    }
    
    func call(ccount: Int, stt: String, symbols: [String: Double]) throws -> [String: Double] {
        var (arg, res) = arg_fun(cmd: stt)!

        let fun = arg.remove(at: 0)
        let index = funcTable.index(forKey: fun)
        if  index == nil {
            throw ParseError(line: ccount, kind: .unknownFunctionName(func: fun))
        }
        
        if arg.count != funcTable[fun]!.argNames.count || res.count != funcTable[fun]!.resNames.count {
            throw ParseError(line: ccount, kind: .wrongNumberOfInputOutputArguments(func: fun))
        }
        
        if funcTable[fun]!.mask! > 0 {
            throw ParseError(line: ccount, kind: .recursiveFunctionNotAllowed(func: fun))
        } else { funcTable[fun]!.mask! = 1 }
        
        for i in 0..<arg.count {
            let key = funcTable[fun]!.argNames[i]!
            guard let value = try? eval(table: symbols, rhs: arg[i]) else {
                throw ParseError(line: funcTable[fun]!.lineStart, kind: .unknownVariableInsideFunction(func: fun))
            }
            funcTable[fun]!.variable[key] = value
        }
    
        let hung = try funcTable[fun]!.parseall(stmts: statements!, fun: fun,
                       from: funcTable[fun]!.lineStart, many: funcTable[fun]!.lineCount)
        if(hung >= 100000) { throw ParseError(line: line, kind: .unterminatingLoopError(func: fun)) }
        funcTable[fun]!.mask! = 0

        var r = [String: Double]()
        for i in 0..<res.count {
            let key = funcTable[fun]!.resNames[i]!
            guard let v = funcTable[fun]!.variable[key] else {
                let number = funcTable[fun]!.lineStart+funcTable[fun]!.lineCount
                throw ParseError(line: number, kind: .returnVariableNotAssigned(func: fun))
            }
            
            r[res[i]] = v
        }

        return r
    }
    
    func arg_fun(cmd: String) -> ([String], [String])? {
        let comp = cmd.components(separatedBy: ["="])
        if  comp.count < 2 { return nil }
        
        var arg = comp[1].components(separatedBy: [",", "(", ")", " "])
        var res = comp[0].components(separatedBy: [",", "[", "]", " "])
        arg.removeAll(where: { str in return str.isEmpty })
        res.removeAll(where: { str in return str.isEmpty })
        
        return (arg, res)
    }
}
