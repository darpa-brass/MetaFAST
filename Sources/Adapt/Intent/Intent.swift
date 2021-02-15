/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Representation of an intent specification
 *
 *  author: Adam Duracz and Yao-Hsiang Yang
 */

//---------------------------------------

import LoggerAPI
import MulticonstrainedOptimizer

//---------------------------------------

public protocol IntentSpec {

  var name: String { get }

  var knobs: [String : KnobRange]  { get }

  var quantizedKnobs: [String : ([KnobValue], KnobValue)]  { get set }

  var measures: [String]  { get }

  var constraints: [String : (Double, ConstraintType)] { get }

  var costOrValue: ([Double]) -> Double { get }

  var optimizationType: OptimizationType  { get }

  var trainingSet: [String]  { get }

  var objectiveFunctionRawString: String? { get }
  
  var knobConstraintsRawString: String? { get }

}

public enum KnobRange {
    case list([KnobValue], KnobValue)
    case interval(Double, Double, Double)
} 

extension IntentSpec {
    // change quantization level for continuous knobs
    public mutating func quantization(_ quantizationLevel: Int = 2) {
        self.quantizedKnobs = knobs.mapValues { value in
            switch value {
                case let .list(knobValues, referenceValue):
                    return (knobValues, referenceValue)
                case let .interval(leftBound, rightBound, referenceValue):
                    var quantizedInterval: [Double] = [Double](stride(from: leftBound, to: rightBound, by: (rightBound - leftBound) / Double(quantizationLevel - 1)))
                    // when floating point roundoff error makes right bound outside the stride sequence
                    if quantizedInterval.count < quantizationLevel {
                        quantizedInterval.append(rightBound)
                    }
                    print(quantizedInterval)
                    if quantizedInterval.contains(referenceValue) {
                        return (quantizedInterval.map { .double($0) }, .double(referenceValue))
                    }
                    else {
                        quantizedInterval.append(referenceValue)
                        return (quantizedInterval.map { .double($0) }, .double(referenceValue))
                    }
                default: 
                    Adapt.fatalError("Unsupported knob range: \(value).")
             }
        }
    }

    // generate the array of all possibleconfigurations
    func knobSpace() -> [[String : KnobValue]] {
        func getKnobValues(for name: String) -> [KnobValue] {
            let (exhaustiveKnobValues, _) = quantizedKnobs[name]!
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
    
        let knobNames = Array(quantizedKnobs.keys).sorted()
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
