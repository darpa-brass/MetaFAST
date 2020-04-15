import Foundation
import LoggerAPI

public func fatalError(_ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) -> Never {
    let m = message()
    Log.error(m)
    Swift.fatalError(m, file: file, line: line)
}


func readFile( withName name: String, ofType type: String
             , fromBundle bundle: Bundle = Bundle.main ) -> String? {

    if let path = bundle.path(forResource: name, ofType: type) {
        do {
            let contents = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
              .split(separator: "\n").filter({ !String($0).hasPrefix("#") }).joined(separator: "\n")
            Log.verbose("Loaded file '\(path)'.")
            return contents
        }
        catch let error {
            Log.warning("Unable to load file '\(path)'. \(error)")
            return nil
        }
    }
    else {
        Log.warning("No file '\(name).\(type)' in \(bundle).")
        return nil
    }

}
