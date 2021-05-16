import Foundation

public func getCSVData(contentsOfFile: String) -> [Double] {
    do {
        let content = try String(contentsOfFile: contentsOfFile)
        let parsedCSV: [Double] = content.components(
            separatedBy: "\n"
        ).map{ Double($0) ?? 0.0 }
        return parsedCSV
    }
    catch {
        return []
    }
}

// Below is the naive matrix inversion adapted Jaden Geller's impementation (https://gist.github.com/JadenGeller/8c758cbb218a9c4615dd#file-matrix-swift)
func determinant(_ matrix: [[Double]]) -> Double { 
    // Base case
    if matrix.count == 1 { return matrix[0][0] }
    else {
        // Recursive case
        var sum: Double = 0.0 
        var multiplier: Double = 1.0

        let topRow = matrix[0]
        for (column, num) in topRow.enumerated() {
            var subMatrix = matrix
            subMatrix.remove(at: 0)
            subMatrix = subMatrix.map({ row in
                var newRow = row
                newRow.remove(at: column)
                return newRow })
            sum += num * multiplier * determinant(subMatrix)
            
            multiplier *= (-1.0)
        }
        
        return sum
    }
}

func cofactor(_ matrix: [[Double]]) ->[[Double]] {
    return matrix.enumerated().map({ (r: Int, row: [Double]) in row.enumerated().map({ (c: Int, element: Double) in
        var subMatrix = matrix
        subMatrix.remove(at: r)
        subMatrix = subMatrix.map({ row in
            var newRow = row
            newRow.remove(at: c)
            return newRow })
        return determinant(subMatrix) * (((r + c) % 2 == 0) ? 1.0 : (-1.0))
    })})
}

public func inverse(_ matrix: [[Double]]) -> [[Double]] {
    var newMatrix = [[Double]]()
    let multiplier = 1.0 / determinant(matrix) 
    let cofactorMatrix = cofactor(matrix)
    for c in 0 ..< matrix[0].count {
        newMatrix.append(matrix.enumerated().map({ (r: Int, row: [Double]) in cofactorMatrix[r][c] * multiplier }))
    }
    return newMatrix
}
