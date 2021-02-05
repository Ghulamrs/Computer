//
//  Expr.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 8/27/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation

struct Expression {
    enum Parenthesis { case left, right }
    
    let type: Parenthesis
    var string: String
}

extension Expression {
    static func start(_ string: String) -> Expression {
        return Expression(type: .left, string: string)
    }
    
    static func end(_ string: String) -> Expression {
        return Expression(type: .right, string: string)
    }
}

extension String {
    var exprs: [Expression] {
        var partialExpr: Expression?
        var exprs = [Expression]()
        var counter = 0
        
        func parse(_ character: Character) {
            if var expr = partialExpr {
                if character == "("  { counter++ }
                if character == ")"  { counter-- }
                guard character != ")" || counter != 0 else {
                    if !expr.string.isEmpty {
                        exprs.append(expr)
                    }
                    
                    partialExpr = nil
                    return parse(character)
                }
                
                expr.string.append(character)
                partialExpr = expr
            } else {
                switch character {
                case "(":
                    partialExpr = .start("")
                    counter = 1
//              case ")":
//                  partialExpr = .end("")
                default:
                    break
                }
            }
        }
        
        forEach(parse)
        
        if let lastExpr = partialExpr, !lastExpr.string.isEmpty {
            exprs.append(lastExpr)
        }
        
        return exprs
    }
}
