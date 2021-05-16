import Foundation
import Adapt
import FlightTestUtils
import HeliumLogger
import LoggerAPI

let logger = HeliumLogger(.debug)
Log.logger = logger

struct InputWithLastRLSCoefficients {
    var x : [Double] = [Double]() // input
    var d : [Double] = [Double]() // desired output
    var w : [Double] = [Double]() // filter coefficients
    var P : [[Double]] = [[Double]]() // estimated inverse covariance

    init(x: [Double], d: [Double], w: [Double], P: [[Double]]) {
        self.x = x
        self.d = d
        self.w = w
        self.P = P
    }

    init(x: [Double], d: [Double]) {
        self.x = x
        self.d = d
    }
}

struct InputWithLastDFTCoefficients {
    var x : [Double] = [Double]() // input
    var a : [Double] = [Double]() // real part coefficients
    var b : [Double] = [Double]() // imaginary part coefficients
}

// Recursive Least Squre
// neww consists of the filter coefficients
// newP consists of estimated inverse covariance which will be needed for the next update
func RLS(input : InputWithLastRLSCoefficients, knob : [String : KnobValue]) -> (([Double], [[Double]]), [String : Double]) {
    var e : Double // error    
    let filterSize =  knob["filterSize"]!.value() as! Int
    let forgettingFactor = knob["forgettingFactor"]!.value() as! Double
    var measure = [String : Double]()
    var neww : [Double] = [Double]()
    var newP : [[Double]] = [[Double]]()
    var Px : [Double] = [Double]() // P * x
    var k : [Double] = [Double]() // gain vector, k = P * x / (forgettingFactor + x' * P * x)
    let n = input.x.count
    let baseFilterSize = 7 
    
    // recompute all coefficients    
    if (knob["successive"]!.value() as! Int == 0) {

        var Q : [Double] = [Double](repeating: 0.0, count: filterSize)
        for i in 0 ..< filterSize {
            newP.append([Double](repeating: 0.0, count: filterSize))
        }
        for i in 0 ..< filterSize {
            for j in 0 ..< filterSize {
                for k in 0 ..< n {
                    if ((k + i >= filterSize - 1) && (k + j >= filterSize - 1)) {
                        newP[i][j] += pow(forgettingFactor, Double(n-1-k)) * input.x[k-filterSize+1+i] * input.x[k-filterSize+1+j]
                    }
                }
            }
            for k in 0 ..< n {
                if (k + i >= filterSize - 1) {
                    Q[i] += pow(forgettingFactor, Double(n-1-k)) * input.x[k-filterSize+1+i] * input.d[k]
                }
            }
        }
        newP = inverse(newP)
        neww = [Double](repeating: 0.0, count: filterSize)
        for i in 0 ..< filterSize {
            neww[i] = 0.0
            for j in 0 ..< filterSize {
                neww[i] += newP[i][j] * Q[j]
            }
        }
    // update coefficients from last RLS
    } else {
        e = input.d[n - 1]
        for i in 0 ..< filterSize {
            e -= input.x[n - filterSize + i] * input.w[i]
        }
        var sum = forgettingFactor // sum = forgettingFactor + x' * P * x
        Px = [Double](repeating: 0.0, count: filterSize)
        for i in 0 ..< filterSize {
            for j in 0 ..< filterSize {
                Px[i] += input.P[i][j] * input.x[n-filterSize+j] 
            }
            sum += Px[i] * input.x[n-filterSize+i]
        }
        k = [Double](repeating: 0.0, count: filterSize)
        neww = [Double](repeating: 0.0, count: filterSize)
        for i in 0 ..< filterSize {
            newP.append([Double](repeating: 0.0, count: filterSize))
            k[i] = Px[i] / sum
            for j in 0 ..< filterSize {
                newP[i][j] = 1 / forgettingFactor * (input.P[i][j] - k[i] * Px[j]) // newP = 1 / forgettingFactor * (P - k * (Px)')
            }
            neww[i] = input.w[i] + k[i] * e // neww = w + k * e
        }
    }

    var sumOfRE = 0.0
    for j in 0 ..< baseFilterSize {
        var RE = input.d[n - 1 - j]
        for i in 0 ..< filterSize {
            if (n - filterSize + i - j >= 0) {
                RE -= input.x[n - filterSize + i - j] * neww[i]
            }
        }
        sumOfRE += pow(RE, 2.0) * pow(forgettingFactor, Double(j))
    }

    measure["RE"] = sumOfRE

    return ((neww, newP), measure)
}

func LS(rawInput : [Double], rawOutput : [Double]) -> InputWithLastRLSCoefficients  {
    var knob = [String : KnobValue]()
    knob["filterSize"] = KnobValue.integer(7)
    knob["forgettingFactor"] = KnobValue.double(5.0)
    knob["successive"] = KnobValue.integer(0)

    let coefficients = RLS(input: InputWithLastRLSCoefficients(x: rawInput, d: rawOutput), knob: knob)
    return InputWithLastRLSCoefficients(x: rawInput, d: rawOutput, w: coefficients.0.0, P: coefficients.0.1)
}

// Recursive Discrete Fourier Transform
// a consists of the real parts of DFT coefficients
// b consists of the imaginary parts
func RDFT(input : InputWithLastDFTCoefficients, knob : [String : KnobValue]) -> (([Double], [Double]), [String : Double]) {
    var a = [Double]()
    var b = [Double]()
    let period = knob["period"]!.value() as! Int
    var measure = [String : Double]()
    let basePeriod = 25
    let last = input.x.count

    // recompute all coefficients    
    if (knob["successive"]!.value() as! Int == 0) {
        for j in 0 ..< period {
            var sumA = 0.0
            var sumB = 0.0
            for i in (last - period) ..< (last - 1) {
                sumA += input.x[i] * cos(Double(i * j * 2) * Double.pi / Double(period))
                sumB += input.x[i] * sin(Double(i * j * 2) * Double.pi / Double(period))
            }
            a.append(sumA)
            b.append(-sumB)
        }
    }
    // update coefficients from last DFT
    else {
        for i in 0 ..< period {
        a.append((input.a[i] + input.x[last - 1] - input.x[last - period]) * cos(Double(i * 2) * Double.pi / Double(period))
                    - input.b[i] * sin(Double(i * 2) * Double.pi / Double(period)))
        b.append(input.b[i] * cos(Double(i * 2) * Double.pi / Double(period))
                    + (input.a[i] + input.x[last - 1] - input.x[last - period]) * sin(Double(i * 2) * Double.pi / Double(period)))
        }   
    }

    var MSE: Double = 0.0
    if (input.x.count >= basePeriod) {
        for i in (last - basePeriod) ..< (last - 1) {
            // use basePeriod inverse dft to reconstruct signal at i
            var y : Double = 0.0
            for j in 0 ..< period {
                y += (a[j] * cos(Double(i * j * 2) * Double.pi / Double(period)) - b[j] * sin(Double(i * j * 2) * Double.pi / Double(period)))
            }
            y = y / Double(period)
            MSE += pow(y - input.x[i], 2)
        }
    }
    measure["MSE"] = MSE

    return ((a, b), measure)
}

func DFT(rawInput : [Double]) -> InputWithLastDFTCoefficients  {
    var knob = [String : KnobValue]()
    knob["period"] = KnobValue.integer(rawInput.count)
    knob["successive"] = KnobValue.integer(0)
    
    let coefficients = RDFT(input: InputWithLastDFTCoefficients(x: rawInput, a: [Double](), b: [Double]()), knob: knob)
    return InputWithLastDFTCoefficients(x: rawInput, a: coefficients.0.0, b: coefficients.0.1)
}

func testFunction(input : Double, knob: [String : KnobValue]) -> (Double, [String : Double]) {
    var sum = input
    let step: Int = knob["step"]!.value() as! Int
    let scale: Double = knob["scale"]!.value() as! Double
    var measure = [String : Double]()
    for i in 0 ..<  (2 * step + 1) {
        sum += Double(i)
    }
    
    measure["increase"] = (sum - input) / scale

    return (sum, measure)
}

// Example starts here

//Log.debug("Initialize RDFT function.")
//let controllableRDFT: ControllableFunction<InputWithLastDFTCoefficients,([Double],[Double])>
//let controllableLPF: ControllableFunction<InputWithLastDFTCoefficients,Double>
//do {
//    var lastDFTInput : InputWithLastDFTCoefficients
//
//    // load intent for RDFT with intent MSE <= 100
//    Log.debug("Load intent from:" + FileManager.default.currentDirectoryPath + "/Sources/FlightTest/RDFT.intent")
//    let content = try String(contentsOfFile: FileManager.default.currentDirectoryPath + "/Sources/FlightTest/RDFT.intent", encoding: .utf8)
//    controllableRDFT = ControllableFunction<InputWithLastDFTCoefficients,([Double],[Double])>(functionBody: RDFT, id: "RDFT", intent: Compiler().compileIntentSpec(source: content)!, saveMeasureValues: true)
//
//
//    // run DFT for the first 100 inputs
//    var voiceInput : [Double] = getCSVData(contentsOfFile: "/home/yhyang/Adapt/voice.csv")
//    var voiceIndex = 4000 
//
//    var rawInput = [Double]()
//    for _ in 0..<99 {
//        rawInput.append(voiceInput[voiceIndex])
//        voiceIndex += 1
//    }
//    lastDFTInput = DFT(rawInput: rawInput)
//    lastDFTInput.x.append(voiceInput[voiceIndex])
//    voiceIndex += 1
//
//    // profile RDFT
//    controllableRDFT.exhaustiveProfilingWithFixedInputs(lastDFTInput, 10)
//
//    func lowpassFilter(input : InputWithLastDFTCoefficients, knob : [String : KnobValue]) -> (Double, [String : Double]) {
//        let cutoffFrequency = knob["cutoffFrequency"]!.value() as! Int
//        var measure = [String : Double]()
//        let basePeriod = 25
//        let last = input.x.count
//        var a = [Double]()
//        var b = [Double]()
//
//        (a, b) = controllableRDFT.execute(input: input)
//
//        var MSE: Double = 0.0
//        var newx : Double = 0.0
//        if (input.x.count >= basePeriod) {
//            for i in (last - basePeriod) ..< (last - 1) {
//                // use basePeriod inverse dft to reconstruct signal at i
//                var y : Double = 0.0
//                for j in 0 ..< cutoffFrequency {
//                    if (j < a.count) {
//                        y += (a[j] * cos(Double(i * j * 2) * Double.pi / Double(a.count)) - b[j] * sin(Double(i * j * 2) * Double.pi / Double(a.count)))
//                    }
//                }
//                y = y / Double(a.count)
//                if (i == last - 1) {
//                    newx = y
//                }
//                MSE += pow(y - input.x[i], 2)
//            }
//        }
//        measure["MSE"] = MSE
//
//        return (newx, measure)
//    }
//     
//    // load intent for LPF with intent RE <= 1
//    Log.debug("Load intent from:" + FileManager.default.currentDirectoryPath + "/Sources/FlightTest/LPF.intent")
//    let content2 = try String(contentsOfFile: FileManager.default.currentDirectoryPath + "/Sources/FlightTest/LPF.intent", encoding: .utf8)
//    controllableLPF = ControllableFunction<InputWithLastDFTCoefficients,Double>(functionBody: lowpassFilter, id: "LPF", intent: Compiler().compileIntentSpec(source: content2)!, saveMeasureValues: true)
//    controllableLPF.exhaustiveProfilingWithFixedInputs(lastDFTInput, 10)
//
//    // control RDFT/RLS for another 1000 inputs
//    for _ in 0 ..< 10000 {
//        lastDFTInput.x.append(voiceInput[voiceIndex])
//        voiceIndex += 1
//        print(controllableLPF.execute(input: lastDFTInput))
//    }
//
//}
//catch {Adapt.fatalError("Error: Cannot read the file.")}
//
//controllableRDFT.plot()
//controllableLPF.plot()

Log.debug("Initialize RLS function.")
let controllableRLS: ControllableFunction<InputWithLastRLSCoefficients,([Double],[[Double]])>
do {
    var rawInput = [Double]()
    var rawOutput = [Double]()
    var lastRLSInput : InputWithLastRLSCoefficients

    // load intent for RDFT with intent MSE <= 100
    Log.debug("Load intent from:" + FileManager.default.currentDirectoryPath + "/Sources/FlightTest/RLS.intent")
    let content = try String(contentsOfFile: FileManager.default.currentDirectoryPath + "/Sources/FlightTest/RLS.intent", encoding: .utf8)
    controllableRLS = ControllableFunction<InputWithLastRLSCoefficients,([Double],[[Double]])>(functionBody: RLS, id: "RLS", intent: Compiler().compileIntentSpec(source: content)!, saveMeasureValues: true)

    // run DFT for the first 100 inputs
    for _ in 0..<99 {
        var randomValue = drand48()
        rawInput.append(randomValue * 10.0)
        rawOutput.append(randomValue * 5.0 + drand48())
    }
    lastRLSInput = LS(rawInput: rawInput, rawOutput: rawOutput)
    var randomValue = drand48()
    lastRLSInput.x.append(randomValue * 10.0)
    lastRLSInput.d.append(randomValue * 5.0 + drand48())

    // profile RDFT
    controllableRLS.exhaustiveProfilingWithFixedInputs(lastRLSInput, 10)

    // control RDFT for another 1000 inputs
    for _ in 0 ..< 1000 {
        var randomValue = drand48()
        lastRLSInput.x.append(randomValue * 10.0)
        lastRLSInput.d.append(randomValue * 5.0 + drand48())
        print(controllableRLS.execute(input: lastRLSInput))
    }

}
catch {Adapt.fatalError("Error: Cannot read the file.")}

controllableRLS.plot()
