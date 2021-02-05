//
//  Error.swift
//  Computer: G. R. Akhtar
//
//  Created by Home on 7/27/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation

protocol ErrorType: CustomNSError {
}

struct ParseError: ErrorType {
    enum ErrorKind {
        case invalidVariableName
        case abnormalProgramTermination
        case alreadyRegisteredFunction
        case InvalidInputNumber
        case invalidLineNumber
        case invalidStatement
        case invalidLoopNoInc
        case invalidLoopInc
        case invalidLoopDec
        case invalidLoopVariable
        case ifStackUnderflow
        case unknownStatement
        case unknownLogicalOperator
        case complexLogicalOperator
        case startupFunctionError
        case startupFunctionNameMayUseAnother
        case badKeywordOrFunctionName
        case keywordFunctionName
        case missingFunctionName
        case undeclaredVariable
        case unknownFunctionName(func: String)
        case recursiveFunctionNotAllowed(func: String)
        case unknownVariableInsideFunction(func: String)
        case wrongNumberOfInputOutputArguments(func: String)
        case returnVariableNotAssigned(func: String)
        case unterminatingLoopError(func: String)
        case unbalancedParenthesis
        case printLoopIncrementError
        case printLoopVariableError
        case unexpectedEndOfFile
        case unknownError
    }
    
    let line: Int
    let kind: ErrorKind
}
