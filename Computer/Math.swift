//
//  math.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 6/20/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation
class Math {
    static let math: [String] = ["fabs","acos","asin","atan","ceil","cos","exp","floor","log","sin","sqrt","tan"]
    static func mathFun(_ f: inout String) -> Int? {
        var res: Int?
        var comp = f.components(separatedBy: ["(", ")"])
        if  comp.count > 1 {
            comp.removeAll(where: { str in return str.isEmpty })
            res = math.firstIndex(of: String(comp[0]))
            if res != nil { f = comp[1] }
        }
        
        return res
    }
    
    static func evalFun(_ idf: Int, _ value: Double) throws -> Double? {
        let d2r: Double = 3.141592653589793/180.0
        switch(idf) {
        case 1: return  acos(value)/d2r
        case 2: return  asin(value)/d2r
        case 3: return atan2(value,1)/d2r
        case 4: return  ceil(value)
        case 5: return   cos(value * d2r)
        case 6: return   exp(value)
        case 7: return floor(value)
        case 8: return   log(value)
        case 9: return   sin(value * d2r)
        case 10:return  sqrt(value)
        case 11:return   tan(value * d2r)
        default:return  fabs(value)
        }
    }
}
