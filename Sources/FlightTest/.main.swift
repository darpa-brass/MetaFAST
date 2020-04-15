import Foundation
import Adapt

// Input data from the plane
let rawInput : Stream

// Recursive Discrete Fourier Transformation
let intentRDFT = """
intent RDFT
  min(latency) 
  such that PSNR <= 0.1
measures
  latency: Double
  energy: Double
  PSNR : Double
knobs
  harmonicNumber = [1,2,3,4,5]
  coreFrequency = [300,1200]
"""

func RDFT(input : (InputStream?, Double) = (nil, 10.0), harmonicNumber : Int) -> ([Double], Double) {
    var timeSeries: [Double]
    let rawInput = input.0!
    let period = input.1
    let PSNR = 0.0

    for i in 0 ..<  2 * harmonicNumber + 1{
        timeSeries[i] = rawInput.read()
    }
    
    // Transform the times series
    
    // Calculate PSNR

    // return frequency domain coefficients
    return (timeSeries, PSNR)
}

let controllableRDFT = ControllableFunction<(Stream?, Double),[Double],Double>(RDFT, IntentSpec(intentRDFT))

// Recursive Least Squares
let intentRLS = """
intent RLS
  min(residual) 
  such that latency <= 0.1
measures
  latency: Double
  energy: Double
  residual : Double
knobs
  forgettingFactor = [0.1,0.3,0.5,0.7,0.9]
  coreFrequency = [300,1200]
"""

func RLS(input : (Stream?, Int) = (nil, 10), forgettingFactor : Double) -> ([Double], Double) {
    var sample : Double[]
    let rawInput = input.0!
    let sampleSize = input.1
    let residual = 0.0

    for i in 0 ..< samplesize{
        timeSeries[i] = rawInput.read()
    }

    // Solve the least square problem

    // Calculate the residual

    // return desired responses 
    return (sample, residual)
}

let controllableRLS = ControllableFunction(RLS, IntentSpec(intentRLS))

func main() -> Void {
    var outputRDFT = controllableRDFT.execute(rawInput)
    var outputRLS = controllableRLS.execute(rawInput)
}
