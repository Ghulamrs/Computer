//
//  Express.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 6/6/19.
//  Copyright © 2019 Home. All rights reserved.
//

import UIKit
import Foundation

class Express : Eval {
    var statements = [String.SubSequence]()
    var variable = [String: Double]()
    var main = String()
    var fun: Function?

    init(source: String) {
        statements = source.split(separator: "\n")
        fun = Function(source: source)
    }

    public func run(times: Int, fileURL: String) throws -> String {
        let ver = Bundle.main.infoDictionary?["CFBundleVersion"] as! String
        for i in 0..<statements.count {
            var line = i
            if  statements[line].starts(with: shalimar[8]) && // test for 'fun' keyword
                statements[line].contains("[]") &&
                statements[line].contains("()") &&
                statements[line].contains("=")  {
                    main = try fun!.add(count: line)
                    fun!.register = false
                    let errors = try semantics(main: main, &line)
                    fun!.funcTable.removeAll()
                    variable.removeAll()
                    //return show_all()
                    if !errors.isEmpty { return errors }
                    main = try fun!.add(count: line)
                    fun!.register = false
                    let first = String(statements[line].dropFirst(4))
                    _ = try fun!.call(ccount: line, stt: first, symbols: variable)
                    break
                }
        }
        
        if main.isEmpty { throw ParseError(line: 1, kind: .startupFunctionError) }
        let list:[URL] = FileManager.default.urls(for: .documentDirectory)!
        for index in list.indices {
            let name = list[index].lastPathComponent
            if  name.contains(main) && !name.contains(fileURL) {
                throw ParseError(line: 1, kind: .startupFunctionNameMayUseAnother)
            }
        }
        
        let output = fun!.consoleOutput()
        var disclaimer = "©2019 Shalimar, \(ver)\u{1F1F5}\u{1F1F0}\n" + main + String("(\(times)) ")
        disclaimer += DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        disclaimer += "\n---------------------------\n"
    
        return  disclaimer + output
    }

    func show_all() -> String {
        var console = String()
        for (key,value) in fun!.funcTable {
            console.append("k: \(key) v: \(value)\n");
        }

        for (key,value) in variable {
            console.append("k: \(key) v: \(value)\n");
        }
        return console
    }
    
    public func semantics(main: String, _ err: inout Int) throws -> String {
        let charSet = CharacterSet.letters
        let delmSet = charSet.inverted
        let hello = [String]()
        var console = String()
        var values: [String]?
        var name = main
        
        var brace = 0
        var count = 0
        var skip1 = 0
        let function = Func(fun!, sline: 0, nlines: 0, arg: hello, res: hello)
        try statements.forEach { stmt in
            count++
            var line = String(stmt.trimmingCharacters(in: [" ", "\t"]))
            if  line.starts(with: "{") || line.contains("{") { brace++ }
            if  line.starts(with: "}") || line.contains("}") { brace-- }
            if  line.count < 2 { return }

            if  line.starts(with: "/*") { skip1++ }
            if  line.starts(with: "*/") { skip1--
                line = line.dropFirst(2).trimmingCharacters(in: [" ","\t"])
                if line.isEmpty { return } // last skip line
            }
            if  count==1 || skip1 > 0 || line.starts(with: "//") { return }
            values = line.components(separatedBy: delmSet)
            values!.removeAll(where: { str in return str.isEmpty })
            if values!.count == 0 { return }
            
            let ind = shalimar.firstIndex(of: values![0])
            if  ind == 8 {
                name = try fun!.add(count: count-1);
                return
            } else if ind != nil { return }
            
            name = containsFunctionName(line: line, values: values!)
            if name.count != 0 { return }
            
            for i in 0..<values!.count {
                let value = String(values![i])
                if function.isaVar(value) {
                    if  Math.math.firstIndex(of: value) == nil &&
                        variable.keys.firstIndex(of: value) == nil {
                        variable[value] = 0;
                    }
                }
                else  {
                    console.append("program error !!!\n")
                }
            }
        }
        
        if brace != 0 || skip1 != 0 {
           console.append("program error !!!")
        }
        
        return console
    }
    
    func containsFunctionName(line: String, values: [String]) -> String {
        var name: String?
        if  line.contains("=") && line.contains("(") && line.contains(")") {
            let found = find(ref: fun!.funcTable, fnd: values)
            if  found != nil {
                let index = fun!.funcTable.index(fun!.funcTable.keys.startIndex, offsetBy: found!)
                name = fun!.funcTable.keys[index]
                return name!
            }
        }
        
        return String("")
    }
    
    func find(ref: [String: Func], fnd: [String]) -> Int? {
        let ss = [String](ref.keys)
        let s = Set(ss), t = Set(fnd)
        var x = s.intersection(t)
        if x.isEmpty { return nil }
        
        return ss.firstIndex(of: String(x.popFirst()!))
    }
}
