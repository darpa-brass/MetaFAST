import Foundation
import Adapt
import HeliumLogger
import LoggerAPI

let logger = HeliumLogger(.debug)
Log.logger = logger

struct InputWithLastRLSCoefficients {
    var x : [Double] = [Double]() // input
    var d : [Double] = [Double]() // desired output
    var w : [Double] = [Double]() // filter coefficients
    var P : [[Double]] = [[Double]]() // estimated inverse covariance
}

struct InputWithLastDFTCoefficients {
    var x : [Double] = [Double]() // input
    var a : [Double] = [Double]() // real part coefficients
    var b : [Double] = [Double]() // imaginary part coefficients
}

// Recursive Least Squre
// neww consists of the filter coefficients
// newP consists of estimated inverse covariance which will be needed for the next update
func RLS(input : InputWithLastRLSCoefficients, knob : [String : KnobValue]) -> ([Double], [[Double]]) {
    var e : Double // error    
    let filterSize =  knob["filterSize"]!.value() as! Int
    let forgettingFactor = knob["forgettingFactor"]!.value() as! Double
    var neww : [Double] = [Double]()
    var newP : [[Double]] = [[Double]]()
    var Px : [Double] = [Double]() // P * x
    var k : [Double] = [Double]() // gain vector, k = P * x / (forgettingFactor + x' * P * x)
    let n = input.x.count

    // recompute all coefficients    
    if (knob["successive"]!.value() as! Int == 0) {
        var Q : [Double] = [Double]()
        for i in 0 ..< filterSize {
            for j in 0 ..< filterSize {
                for k in 0 ..< n {
                    newP[i][j] += pow(forgettingFactor, Double(n-k)) * input.x[k-i] * input.x[k-j]
                }
            }
            for k in 0 ..< n {
                Q[i] += pow(forgettingFactor, Double(n-k)) * input.x[k-i] * input.d[i]
            }
        }
        newP = inverse(newP)
        for i in 0 ..< filterSize {
            neww[i] = 0.0
            for j in 0 ..< filterSize {
                neww[i] += newP[i][j] * Q[j]
            }
        }
    // update coefficients from last DFT
    } else {
        e = input.d[filterSize]
        for i in 0 ..< filterSize {
            e -= input.x[i] * input.w[i]
        }
        var sum = forgettingFactor // sum = forgettingFactor + x' * P * x
        for i in 0 ..< filterSize {
            Px[i] = 0.0
            for j in 0 ..< filterSize {
                Px[i] += input.P[i][j] * input.x[j] 
            }
            sum += Px[i] * input.x[i]
        }
        for i in 0 ..< filterSize {
            k[i] = Px[i] / sum
            for j in 0 ..< filterSize {
                newP[i][j] = 1 / forgettingFactor * (input.P[i][j] - k[i] * Px[j]) // newP = 1 / forgettingFactor * (P - k * (Px)')
            }
            neww[i] = input.w[i] + k[i] * e // neww = w + k * e
        }
    }

    return (neww, newP)
}

// Recursive Discrete Fourier Transform
// a consists of the real parts of DFT coefficients
// b consists of the imaginary parts
func RDFT(input : InputWithLastDFTCoefficients, knob : [String : KnobValue]) -> ([Double], [Double]) {
    var a = [Double]()
    var b = [Double]()
    let period = knob["period"]!.value() as! Int

    // recompute all coefficients    
    if (knob["successive"]!.value() as! Int == 0) {
        for j in 0 ..< period {
            var sumA = 0.0
            var sumB = 0.0
            for i in 0 ..< period {
                sumA += input.x[i] * cos(Double(i * j * 2) * Double.pi / Double(period))
                sumB += input.x[i] * sin(Double(i * j * 2) * Double.pi / Double(period))
            }
            a.append(sumA)
            b.append(-sumB)
        }
    }
    // update coefficients from last DFT
    else {
        a.append(input.x[0])
        b.append(0.0)
        for j in 1 ..< period {
        a.append(input.a[j] * cos(Double(j * 2) * Double.pi / Double(period)) - input.b[j] * sin(Double(j * 2) * Double.pi / Double(period)) 
                    + input.x[period-1] * cos(Double((period-1) * j * 2) * Double.pi / Double(period)))
        b.append(input.a[j] * sin(Double(j * 2) * Double.pi / Double(period)) + input.b[j] * cos(Double(j * 2) * Double.pi / Double(period)) 
                    + input.x[period-1] * sin(Double((period-1) * j * 2) * Double.pi / Double(period)))
        }   
    }

    return (a, b)
}

func testFunction(input : Double, knob: [String : KnobValue]) -> (Double, [String : Double]) {
    var sum = input
    let step: Int = knob["step"]!.value() as! Int
    var measure = [String : Double]()
    for i in 0 ..<  (2 * step + 1) {
        sum += Double(i)
    }
    
    measure["increase"] = sum - input

    return (sum, measure)
}

// Example starts here
Log.debug("Initialize the test function.")
let controllableTestFunction: ControllableFunction<Double,Double>
do {
    Log.debug("Load intent from:" + FileManager.default.currentDirectoryPath + "/Sources/FlightTest/test.intent")
    let content = try String(contentsOfFile: FileManager.default.currentDirectoryPath + "/Sources/FlightTest/test.intent", encoding: .utf8)
    controllableTestFunction = ControllableFunction<Double,Double>(functionBody: testFunction, id: "test", intent: Compiler().compileIntentSpec(source: content)!, saveMeasureValues: true)
    let input = 0.0
    controllableTestFunction.exhaustiveProfilingWithFixedInputs(input)
    for _ in 0 ..< 100 {
        print(controllableTestFunction.execute(input: input))
    }
}
catch {Adapt.fatalError("Error: Cannot read the file.")}

controllableTestFunction.plot()
