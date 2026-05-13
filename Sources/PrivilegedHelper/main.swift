import Foundation

let listener = NSXPCListener(machServiceName: machServiceName)
let delegate = XPCDelegate()

listener.delegate = delegate
listener.resume()

RunLoop.main.run()
