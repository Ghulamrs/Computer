//
//  loop.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 7/3/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation

struct looooooop {
    var stop: Double
    var step: Double
    var star: Double
    var iter: String
    
    var loft: Int
    var count: Int // first line inside loop
    var length: Int // no of lines inside loop
    init(it: String, stop: Double, step: Double, start: Double, loft: Int, count: Int, length: Int) {
        self.iter = it
        self.stop = stop
        self.step = step
        self.star = start
        
        self.loft = loft
        self.count = count
        self.length = length
    }
}

class Loop : Eval {
    var loop : looooooop?
    func find_lop(rhs: String, chk: [String]) -> Int? {
        var i: Int = 0
        let rhx = rhs.unicodeScalars
        for c in chk {
            if rhx.filter({$0 == Unicode.Scalar(c)}).count > 0 { break }
            i++
        }
        if i < 3 { return i }
        return nil
    }
    
    func setup(stt: String, symbol: inout [String: Double], loops: inout [Int: looooooop], count: Int, length: Int) throws {
        let key = count+1 + length
        let index = loops.index(forKey: key)
        if  index != nil {
            loop = loops[key]!
            symbol[loop!.iter] = loop!.star
            return
        }
        var iter: String?
        var star: Double = 0
        var step: Double = 1
        var stop: Double = 10
        let test = ["<", "=", ">"]
        var par  = stt.components(separatedBy: [";",","," ","(",")"])
        par.removeAll(where: { str in return str.isEmpty })
        if  par.count > 4 { // for(i=0; i<10; i+=1)
            let par1 = par[1].components(separatedBy: ["=", " ", "\t"])
            if  par1.count > 1 {
                star = try eval(table: symbol, rhs: par1[1])
                iter = par1[0]
                symbol[iter!] = star
            }
            let par2 = par[2].components(separatedBy: ["<", "=", ">"])
            if  par2.count > 1 {
                stop = try eval(table: symbol, rhs: par2[1])
            }
            let par3 = par[3].components(separatedBy: ["="])
            if  par3.count > 1 {
                step = Double(par3[1])!
            }
            if  par3[0].contains("-") { step = -step }
            
            // step sign is consistant with the condition statement direction
            if(par2.contains("<") && step < 0) || (par2.contains(">") && step > 0) {
                throw ParseError(line: count, kind: .invalidStatement)
            }
            // variable name is strictly followed
            if(par1[0].first != par2[0].first || par2[0].first != par3[0].first) {
                throw ParseError(line: count, kind: .invalidStatement)
            }
        }
        else {
            throw ParseError(line: count, kind: .invalidStatement)
        }

        let lop = find_lop(rhs: par[2], chk: test)
        if  lop == nil { throw ParseError(line: count, kind: .invalidStatement) }
        
        if (step > 0 || lop == 0) && stop < star {
            throw ParseError(line: count, kind: .invalidLoopDec)
        }
        if (step < 0 || lop == 2) && stop > star {
            throw ParseError(line: count, kind: .invalidLoopInc)
        }
        if iter != nil {
        loops[key] = looooooop(it: iter!, stop: stop, step: step, start: star,
                               loft: lop!, count: count+1, length: length)
        }
    }
    
    func exec(stt: String, symbol: inout [String: Double], loops: inout [Int: looooooop], count: inout Int) throws {
        let index = loops.index(forKey: count)
        if  index == nil {
            throw ParseError(line: count, kind: .invalidStatement)
        }
        
        let it  = loops[count]!.iter as String
        var value = symbol[it]!
        value  += Double(loops[count]!.step)
        symbol[it] = value
        
        let key = count
        if loops[key]!.step > 0 {
            if symbol[it]! < Double(loops[key]!.stop) {
                count = loops[key]!.count
            }
            else if loops[key]!.loft == 1 {
                count = loops[key]!.count
                loops[key]!.loft = 0
            }
            else {
                symbol.removeValue(forKey: it) // unregister loop variable
                loops.remove(at: index!)
            }
        } else {
            if symbol[it]! > Double(loops[key]!.stop) {
                count = loops[key]!.count
            }
            else if loops[key]!.loft == 1 {
                count = loops[key]!.count
                loops[key]!.loft = 2
            }
            else {
                symbol.removeValue(forKey: it) // unregister loop variable
                loops.remove(at: index!)
            }
        }
    }
}
