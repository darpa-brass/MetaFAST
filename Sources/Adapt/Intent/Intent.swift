/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Representation of an intent specification
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import LoggerAPI
import MulticonstrainedOptimizer

//---------------------------------------

public protocol IntentSpec {


  var name: String { get }

  var knobs: [String : ([KnobValue], KnobValue)]  { get }

  var measures: [String]  { get }

  var constraints: [String : (Double, ConstraintType)] { get }

  var costOrValue: ([Double]) -> Double { get }

  var optimizationType: OptimizationType  { get }

  var trainingSet: [String]  { get }

  var objectiveFunctionRawString: String? { get }
  
  var knobConstraintsRawString: String? { get }

}

extension IntentSpec {
    func knobSpace() -> [[String : KnobValue]] {
        func getKnobValues(for name: String) -> [KnobValue] {
            let (exhaustiveKnobValues, _) = knobs[name]!
            return  exhaustiveKnobValues
        }

        /** Builds up the space by extending it with the elements of
         *  successive elements of remainingKnobs. */
        func build(space: [[String : KnobValue]], remainingKnobs: [String]) -> ([[String : KnobValue]]) {
            if remainingKnobs.isEmpty {
                return space
            }
            else {
                let knobName = remainingKnobs.first!
                let knobValues = getKnobValues(for: knobName)
                var extendedSpace = [[String : KnobValue]]()
                if space.isEmpty {
                    extendedSpace = knobValues.map{ [knobName: $0] }
                }
                else {
                    for knobValue in knobValues {
                        for partialConfiguration in space {
                            var extendedPartialConfiguration = partialConfiguration
                            extendedPartialConfiguration[knobName] = knobValue
                            extendedSpace.append(extendedPartialConfiguration)
                        }
                    }
                }
                return build(space: extendedSpace, remainingKnobs: Array(remainingKnobs.dropFirst(1)))
            }
        }
    
        let knobNames = Array(knobs.keys).sorted()
        return build(space: [[String : KnobValue]](), remainingKnobs: knobNames)
    }
}

public enum KnobValue : Equatable {
    case integer(Int)
    case double(Double)
    case string(String)

    public func value() -> Any {
        switch self {
        case let .integer(int):
            return int
        case let .double(dou):
            return dou
        case let .string(str):
            return str
        }
    }
}

public func ==(lhs: KnobValue, rhs: KnobValue) -> Bool {
    switch (lhs, rhs) {
    case (let .integer(int1), let .integer(int2)):
        return int1 == int2
    case (let .double(dou1), let .double(dou2)):
        return dou1 == dou2
    case (let .string(str1), let .string(str2)):
        return str1 == str2
    default:
        return false
    }
}

public enum ConstraintType : String {
  case lessOrEqualTo = "<=", equalTo = "==", greaterOrEqualTo = ">="
}
