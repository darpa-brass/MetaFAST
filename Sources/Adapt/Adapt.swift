import Foundation
import MulticonstrainedOptimizer
import HeliumLogger
import LoggerAPI

public class ControllableFunction<Input, Output> {
    let functionBody : (Input, [String : KnobValue]) -> (Output, [String : Double])
    var controller : MultilinearController
    var predictor : NaivePredictor
    var intent : IntentSpec?
    let id : String
    var saveMeasureValues : Bool
    private var recordedMeasureValues : [[String : Double]] = []

    public init(functionBody : @escaping (Input, [String : KnobValue]) -> (Output, [String : Double]), id : String, intent : IntentSpec, saveMeasureValues : Bool = false) {
        Log.debug("Initialize the controllable function \(id)...")
        self.functionBody = functionBody
        self.id = id
        self.intent = intent
        self.saveMeasureValues = saveMeasureValues
        predictor = NaivePredictor(id, intent)
        controller = MultilinearController(id, intent, predictor)
        Log.debug("Initialize the controllable function \(id) successfully.")
    }
    
    func loadIntent(intent : IntentSpec) { 
        self.intent = intent
        predictor = NaivePredictor(id, intent)
        controller = MultilinearController(id, intent, predictor)
    }

    public func execute(input : Input) -> Output {
        let start = NSDate().timeIntervalSince1970
        let nextKnobValues = controller.getNextKnobValues()
        var (output, measureValues) = functionBody(input, nextKnobValues)
        let end = NSDate().timeIntervalSince1970
        if intent!.measures.contains("latency") {
            measureValues["latency"] = end - start
        }
        controller.updateStatistics(knobValues: nextKnobValues, measureValues: measureValues, time: (end + start)/2)
        if saveMeasureValues {
           // Write the measure values
           recordedMeasureValues.append(measureValues)
        }
        return output
    }

    public func exhaustiveProfilingWithFixedInputs(_ sampleInput: Input, _ runs : Int = 1) -> Void {
        Log.debug("Exhaustively proflie the controllable function \(id)...")
        let domain = intent!.knobSpace()
        for knobValues in domain {
            Log.debug("Proflie the controllable function \(id) with knob \(knobValues)...")
            var averageMeasureValues : [String : Double] = [:]
            for _ in 0 ..< runs {
                let start = NSDate().timeIntervalSince1970
                var (_, measureValues) = functionBody(sampleInput, knobValues)
                let end = NSDate().timeIntervalSince1970
                if intent!.measures.contains("latency") {
                    measureValues["latency"] = end - start
                }
                for (key, value) in measureValues {
                    if let averageMeasureValue = averageMeasureValues[key] {
                        averageMeasureValues[key] = averageMeasureValue + value
                    }
                    else {
                        averageMeasureValues[key] = value
                    }
                }
            }
            averageMeasureValues.compactMap {$0.1 / Double(runs)}
            predictor.initializeStatistics(knobValues, averageMeasureValues, NSDate().timeIntervalSince1970)
            Log.debug("Proflie the controllable function \(id) with knob \(knobValues) successfully.")
        }
        Log.debug("Exhaustively proflie the controllable function \(id) successfully.")
    }

    public func plot(_ gnuplotPath : String = "/usr/bin/gnuplot", _ userSpecifiedOutputPath : String? = nil) -> Void {        
        var outputPath : String
        var iteration = 0
        var csvdata : [String : String] = [:]

        if (userSpecifiedOutputPath == nil) {
            do{
                try FileManager().createDirectory(atPath: "Plots", withIntermediateDirectories: true)
            }
            catch {Adapt.fatalError("Error: Cannot creat directory 'Plots'.")}
            outputPath = FileManager().currentDirectoryPath + "/Plots"
        }
        else {
            outputPath = userSpecifiedOutputPath!
        }

        for measureName in intent!.measures {
            csvdata[measureName] = "# X Y\n"
        }
        for measureValues in recordedMeasureValues {
            iteration = iteration + 1
            for (measureName, measureValue) in measureValues {
                csvdata[measureName]!.append("\(iteration) \(measureValue)\n")
            }
        }

        do {
            for measureName in intent!.measures {
                try csvdata[measureName]!.write(toFile: outputPath + "/" + id + "_" + measureName + ".data", atomically: false, encoding: .utf8)
            }
        } catch {
            Adapt.fatalError("Failed to create data files for plotting.")
        }

        let task = Process()
        task.launchPath = gnuplotPath
        task.currentDirectoryPath = outputPath
        let pipeIn = Pipe()
        task.standardInput = pipeIn
        task.launch()

        var plotCommand : String =  "set term png\n"
        for measureName in intent!.measures {
            plotCommand = plotCommand +
              "set title \"Measure " + measureName + " for intent " + id + "\"\n" +
              "set xlabel \"runs\"\n" +
              "set ylabel \"" + measureName + "\"\n" +
              "set output \"" + id + "_" + measureName + ".png\"\n" +
              "plot \"" + id + "_" + measureName + ".data\"\n"
              
        }
        plotCommand = plotCommand + "q\n"
      
        pipeIn.fileHandleForWriting.write(plotCommand.data(using: String.Encoding.utf8)!)
    }
}

protocol Predictor {
    associatedtype Knob
    associatedtype Measure
    func readDataFromFile() -> Void
    func writeDataToFile() -> Void
    func updateStatistics(_ knobValues : Knob, _ measureValues : Measure, _ time: TimeInterval) -> Void
    func predict(_ knobValues : Knob) -> Measure
}

// Naive predictor based on kernel smoothing
//
//   Assume m(x, t) estimated measure values of knob configuration x at time t
//   We further assume m(x, t) / m0(x) ~ o(t) + noise
//   Now o(t) can be estimated from the sample {(x_i, m_i, t_i)}:
//     estimated_o(t) = Sum_i {(m_i / m0(x_i)) * K_h(t-t_i)} / Sum_i {K_h(t-t_i)}
//   where h > 0 is the bandwidth and K is an exponential kernel function
class NaivePredictor : Predictor {
    let intent : IntentSpec
    let id : String
    var domain : [[String : KnobValue]]
    var baselineMeasure : [[String : Double]] = [] // m0
    var sizeOfConfigurations : Int

    // intermediate estimates update whenever a new sample is received
    var lastSampleTime: TimeInterval // t_last, the time when we received the last sample 
    var overload: [String : Double] = [:] // o(t_last)
    var overloadDenominator : [String : Double] = [:] // Sum_i {K_h(t-t_i)}
    var overloadNominator: [String : Double] = [:]// Sum_i {(m_i / m0(x_i)) * K_h(t-t_i)}

    // hyperparameters for estimation
    var bandwidth : Double = 10.0

    init(_ id : String, _ intent : IntentSpec) {
        Log.debug("Initialize a naive predictor for the function \(id)...")
	    self.intent = intent
        self.id = id
        domain = intent.knobSpace()
        Log.debug("Domain: \(intent.knobSpace()).")
        sizeOfConfigurations = domain.count
        for measureName in intent.measures {        
            overload[measureName] = 1.0
            overloadDenominator[measureName] = 1.0
            overloadNominator[measureName] = 1.0
        }
        for _ in domain {
            var measureValues: [String:Double] = [:]
            for measureName in intent.measures {
                measureValues[measureName] = 1.0
            }
            baselineMeasure.append(measureValues)
        }
        lastSampleTime = NSDate().timeIntervalSince1970
        Log.debug("Initialize the naive predictor successfully.")
    }   

    func readDataFromFile() -> Void {
        let tableSuffix = "table"
        if let measureCSV = readFile(withName: id, ofType: "measure\(tableSuffix)") {
//                estimate = Dictionary(uniqueKeysWithValues: zip(knobCSV, measureCSV))
        }
        else {
            Adapt.fatalError("Unable to read measure table \(id).measure\(tableSuffix).")
        }
    }
    
    func writeDataToFile() -> Void {
        let tableSuffix = "table"
        if let measureCSV = readFile(withName: id, ofType: "measure\(tableSuffix)") {
//                estimate = Dictionary(uniqueKeysWithValues: zip(knobCSV, measureCSV))
        }
        else {
            Adapt.fatalError("Unable to read measure table \(id).measure\(tableSuffix).")
        } 
    }
    
    func initializeStatistics(_ knobValues : [String : KnobValue], _ measureValues : [String : Double], _ time : TimeInterval) -> Void {    
        baselineMeasure[domain.index(of: knobValues)!] = measureValues
        for (measureName, measureValue) in measureValues {
            Log.debug("Initialize \(measureName) of \(knobValues) with value \(measureValue)")
        }
        lastSampleTime = time
    }
    
    func updateStatistics(_ knobValues : [String : KnobValue], _ measureValues : [String : Double], _ time: TimeInterval) -> Void {    
        for (measureName, measureValue) in measureValues {
            overloadDenominator[measureName] = overloadDenominator[measureName]! * exp((lastSampleTime - time) / bandwidth)
            overloadNominator[measureName] = overloadNominator[measureName]! * exp((lastSampleTime - time) / bandwidth)
            overloadDenominator[measureName] = overloadDenominator[measureName]! + 1.0
            overloadNominator[measureName] = overloadDenominator[measureName]! + (measureValue / baselineMeasure[domain.index(of: knobValues)!][measureName]!)
            overload[measureName] = overloadNominator[measureName]! / overloadDenominator[measureName]!
            Log.debug("Update \(measureName) with overload factor \(overload[measureName])")
        }
        lastSampleTime = time
    }

    func predictCoefficient(_ knobValues : [String : KnobValue], _ measureName: String) -> Double {
        return baselineMeasure[domain.index(of: knobValues)!][measureName]! * overload[measureName]!
    }

    func predictCoefficientById(_ knobId : UInt32, _ measureName: String) -> Double {
        return baselineMeasure[Int(knobId)][measureName]! * overload[measureName]!
    }
    
    func predictValuesById(_ knobId : UInt32) -> [Double] {
        return baselineMeasure[Int(knobId)].map {key, value in (value * overload[key]!)}
    }
    
    func predict(_ knobValues : [String : KnobValue]) -> [String : Double] {
        return Dictionary(uniqueKeysWithValues: baselineMeasure[domain.index(of: knobValues)!].map {key, value in (key, value * overload[key]!)})
    }

    func getSizeOfConfigurations() -> Int {
        return sizeOfConfigurations
    }

    func getDomain() -> IndexingIterator<Array<UInt32>> {
        return Array(0...UInt32(sizeOfConfigurations-1)).makeIterator()
    }

    func getConfigurationById(_ knobId : UInt32) -> [String : KnobValue] {
        return domain[Int(knobId)]
    }
}

protocol Controller {
    associatedtype Knob
    associatedtype Measure
    associatedtype PredictorForControl : Predictor where PredictorForControl.Measure == Measure, PredictorForControl.Knob == Knob
    var predictor : PredictorForControl {get set}
    func updateStatistics(knobValues : Knob, measureValues : Measure, time: TimeInterval) -> Void
    func getNextKnobValues() -> Knob
}

class MultilinearController : Controller {
    var scheduleSize : UInt32 = 20
    var currentScheduleIndex = 0
    var schedule : [[String : KnobValue]]
    var multiconstrainedLinearOptimizer : MulticonstrainedLinearOptimizer<Double>
    var predictor : NaivePredictor

    let intent : IntentSpec
    let constraintsLessOrEqualTo: [String : (Double, ConstraintType)]
    let constraintsGreaterOrEqualTo: [String : (Double, ConstraintType)]
    let constraintsEqualTo: [String : (Double, ConstraintType)]
    let constraintMeasureIdsLEQ: [String]
    let constraintMeasureIdsGEQ: [String]
    let constraintMeasureIdsEQ: [String]
    let constraintBoundsLessOrEqualTo: [Double]
    let constraintBoundsGreaterOrEqualTo: [Double]
    var constraintBoundsEqualTo: [Double]
    var constraintCoefficientsLessOrEqualTo: [[Double]]
    var constraintCoefficientsGreaterOrEqualTo: [[Double]]
    var constraintCoefficientsEqualTo: [[Double]]
    let sizeOfConfigurations: Int
    let domain : IndexingIterator<Array<UInt32>>

    init(_ id : String, _ intent : IntentSpec, _ predictor : NaivePredictor) {
        Log.debug("Initialize multilinear controller...")
        self.intent = intent
        self.predictor = predictor
        let domain = predictor.getDomain()
        self.domain = domain
        sizeOfConfigurations = predictor.getSizeOfConfigurations()

        constraintsLessOrEqualTo = intent.constraints.filter {$0.1.1 == .lessOrEqualTo}
        constraintsGreaterOrEqualTo = intent.constraints.filter {$0.1.1 == .greaterOrEqualTo}
        constraintsEqualTo = intent.constraints.filter {$0.1.1 == .equalTo}

        constraintMeasureIdsLEQ = [String](constraintsLessOrEqualTo.keys)
        constraintMeasureIdsGEQ = [String](constraintsGreaterOrEqualTo.keys)
        constraintMeasureIdsEQ = [String](constraintsEqualTo.keys)

        constraintBoundsLessOrEqualTo =  [Double](constraintsLessOrEqualTo.values.map { $0.0 })
        constraintBoundsGreaterOrEqualTo =  [Double](constraintsGreaterOrEqualTo.values.map { $0.0 })
        constraintBoundsEqualTo =  [Double](constraintsEqualTo.values.map { $0.0 })
        constraintBoundsEqualTo.append(Double(1.0))

        constraintCoefficientsLessOrEqualTo = (constraintMeasureIdsLEQ.map { c in domain.map { k in predictor.predictCoefficientById(k, c) } })
        constraintCoefficientsGreaterOrEqualTo = (constraintMeasureIdsGEQ.map { c in domain.map { k in predictor.predictCoefficientById(k, c) } })
        constraintCoefficientsEqualTo = (constraintMeasureIdsEQ.map { c in domain.map { k in predictor.predictCoefficientById(k, c) } })
        constraintCoefficientsEqualTo.append([Double](repeating: 1.0, count: sizeOfConfigurations))  

        switch intent.optimizationType { 
        case .maximize:
            self.multiconstrainedLinearOptimizer =
                MulticonstrainedLinearOptimizer<Double>( 
                    objectiveFunction: {(id: UInt32) -> Double in intent.costOrValue(predictor.predictValuesById(id))},
                    domain: domain,
                    optimizationType: .maximize,
                    constraintBoundslt: constraintBoundsLessOrEqualTo,
                    constraintBoundsgt: constraintBoundsGreaterOrEqualTo,
                    constraintBoundseq: constraintBoundsEqualTo,
                    constraintCoefficientslt: constraintCoefficientsLessOrEqualTo,
                    constraintCoefficientsgt: constraintCoefficientsGreaterOrEqualTo,
                    constraintCoefficientseq: constraintCoefficientsEqualTo
                    )
        case .minimize:
            self.multiconstrainedLinearOptimizer =
                MulticonstrainedLinearOptimizer<Double>( 
                    objectiveFunction: {(id: UInt32) -> Double in -(intent.costOrValue(predictor.predictValuesById(id)))},
                    domain: domain,
                    optimizationType: .maximize,
                    constraintBoundslt: constraintBoundsLessOrEqualTo,
                    constraintBoundsgt: constraintBoundsGreaterOrEqualTo,
                    constraintBoundseq: constraintBoundsEqualTo,
                    constraintCoefficientslt: constraintCoefficientsLessOrEqualTo,
                    constraintCoefficientsgt: constraintCoefficientsGreaterOrEqualTo,
                    constraintCoefficientseq: constraintCoefficientsEqualTo
                    )
        }	
        Log.debug("Initialize multilinear controller successfully.")
        schedule = (multiconstrainedLinearOptimizer.computeSchedule(window: scheduleSize)).map {predictor.getConfigurationById($0)}
        Log.debug("Compute a schedule. Schedule: \(schedule)")
    }

    func updateOptimizer() {
        Log.debug("Update multilinear controller...")
        constraintCoefficientsLessOrEqualTo = (constraintMeasureIdsLEQ.map { c in domain.map { k in predictor.predictCoefficientById(k, c) } })
        constraintCoefficientsGreaterOrEqualTo = (constraintMeasureIdsGEQ.map { c in domain.map { k in predictor.predictCoefficientById(k, c) } })
        constraintCoefficientsEqualTo = (constraintMeasureIdsEQ.map { c in domain.map { k in predictor.predictCoefficientById(k, c) } })
        constraintCoefficientsEqualTo.append([Double](repeating: 1.0, count: sizeOfConfigurations))  

        switch intent.optimizationType { 
        case .maximize:
	    self.multiconstrainedLinearOptimizer =
                MulticonstrainedLinearOptimizer<Double>( 
                    objectiveFunction: {(id: UInt32) -> Double in self.intent.costOrValue(self.predictor.predictValuesById(id))},
                    domain: domain,
                    optimizationType: .maximize,
                    constraintBoundslt: constraintBoundsLessOrEqualTo,
                    constraintBoundsgt: constraintBoundsGreaterOrEqualTo,
                    constraintBoundseq: constraintBoundsEqualTo,
                    constraintCoefficientslt: constraintCoefficientsLessOrEqualTo,
                    constraintCoefficientsgt: constraintCoefficientsGreaterOrEqualTo,
                    constraintCoefficientseq: constraintCoefficientsEqualTo
                    )
        case .minimize:
            self.multiconstrainedLinearOptimizer =
                MulticonstrainedLinearOptimizer<Double>( 
                    objectiveFunction: {(id: UInt32) -> Double in -(self.intent.costOrValue(self.predictor.predictValuesById(id)))},
                    domain: domain,
                    optimizationType: .maximize,
                    constraintBoundslt: constraintBoundsLessOrEqualTo,
                    constraintBoundsgt: constraintBoundsGreaterOrEqualTo,
                    constraintBoundseq: constraintBoundsEqualTo,
                    constraintCoefficientslt: constraintCoefficientsLessOrEqualTo,
                    constraintCoefficientsgt: constraintCoefficientsGreaterOrEqualTo,
                    constraintCoefficientseq: constraintCoefficientsEqualTo
                    )
        }        
    }

    func computeSchedule() {
        schedule = (multiconstrainedLinearOptimizer.computeSchedule(window: scheduleSize)).map {predictor.getConfigurationById($0)}
        Log.debug("Compute a schedule. Schedule: \(schedule).")
    }	

    func updateStatistics(knobValues : [String : KnobValue], measureValues : [String : Double], time: TimeInterval) -> Void {        
        predictor.updateStatistics(knobValues, measureValues, time)
    }

    func getNextKnobValues() -> [String : KnobValue] {
        let nextKnobValues: [String : KnobValue] = schedule[currentScheduleIndex]
        
        if currentScheduleIndex < scheduleSize - 1 {
            currentScheduleIndex += 1
        }
        else {
            computeSchedule()
            currentScheduleIndex = 0
        }

        return nextKnobValues
    }
}
