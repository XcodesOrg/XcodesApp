import Foundation

let listener = NSXPCListener.init(machServiceName: machServiceName)
let delegate = XPCDelegate()

listener.delegate = delegate
listener.resume()

RunLoop.main.run()
