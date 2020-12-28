# Decisions

This file exists to provide a historical record of the motivation for important technical decisions in the project. It's inspired by Architectural Decision Records, but the implementation is intentionally simpler than usual. When a new decision is made, append it to the end of the file with a header. Decisions can be changed later. This is a reflection of real life, not a contract that has to be followed.

## Why Make Xcodes.app?

[xcodes](https://github.com/RobotsAndPencils/xcodes) has been well-received within and outside of Robots and Pencils as an easy way to manage Xcode versions. A command line tool can have a familiar interface for developers, and is also easier to automate than most GUI apps.

Not everyone wants to use a command line tool though, and there's an opportunity to create an even better developer experience with an app. This is also an opportunity for contributors to get more familiar with SwiftUI and Combine on macOS. 

## Code Organization

To begin, we will intentionally not attempt to share code between xcodes and Xcodes.app. In the future, once we have a better idea of the two tools' functionality, we can revisit this decision. An example of code that could be shared are the two AppleAPI libraries which will likely be very similar.

While the intent of xcodes' XcodesKit library was to potentially reuse it in a GUI context, it still makes a lot of assumptions about how the UI works that would prevent that happening immediately. As we reuse that code (by copying and pasting) and tweak it to work in Xcodes.app, we may end up with something that can work in both contexts. 

## Asynchrony

Xcodes.app uses Combine to model asynchronous work. This is different than xcodes, which uses PromiseKit because it began prior to Combine's existence. This means that there is a migration of the existing code that has to happen, but the result is easier to use with a SwiftUI app.

## Dependency Injection

xcodes used Point Free's Environment type, and I'm happy with how that turned out. It looks a lot simpler to implement and grow with a codebase, but still allows setting up test double for tests.

- https://www.pointfree.co/episodes/ep16-dependency-injection-made-easy
- https://www.pointfree.co/episodes/ep18-dependency-injection-made-comfortable
- https://vimeo.com/291588126

## State Management

While I'm curious and eager to try Point Free's [Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture), I'm going to avoid it at first in favour of a simpler AppState ObservableObject. My motivation for this is to try to have something more familiar to a contributor that was also new to SwiftUI, so that the codebase doesn't have too many new or unfamiliar things. If we run into performance or correctness issues in the future I think TCA should be a candidate to reconsider.

## Privilege Escalation

Unlike [xcodes](https://github.com/RobotsAndPencils/xcodes/blob/master/DECISIONS.md#privilege-escalation), there is a better option than running sudo in a Process when we need to escalate privileges in Xcodes.app, namely a privileged helper.

A separate, bundle executable is installed as a privileged helper using SMJobBless and communicates with the main app (the client) over XPC. This helper performs the post-install and xcode-select tasks that would require sudo from the command line. The helper and main app validate each other's bundle ID, version and code signing certificate chain. Validation of the connection is done using the private audit token API. An alternative is to validate the code signature of the client based on the PID from a first "handshake" message. DTS [seems to say](https://developer.apple.com/forums/thread/72881#420409022) that this would also be safe against an attacker PID-wrapping. Because the SMJobBless + XPC examples I found online all use the audit token instead, I decided to go with that. The tradeoff is that this is private API.

Uninstallation is not provided yet. I had this partially implemented (one attempt was based on [DoNotDisturb's approach](https://github.com/objective-see/DoNotDisturb/blob/237b19800fa356f830d1c02715a9a75be08b8924/configure/Helper/HelperInterface.m#L123)) but an issue that I kept hitting was that despite the helper not being installed or running I was able to get a remote object proxy over the connection. Adding a timeout to getVersion might be sufficient as a workaround, as it should return the string immediately.

- [Apple Developer: Creating XPC Services](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html)
- [Objective Development: The Story Behind CVE-2019-13013](https://blog.obdev.at/what-we-have-learned-from-a-vulnerability/)
- [Apple Developer Forums: How to and When to uninstall a privileged helper](https://developer.apple.com/forums/thread/66821)
- [Apple Developer Forums: XPC restricted to processes with the same code signing?](https://developer.apple.com/forums/thread/72881#419817)
- [Wojciech Reguła: Learn XPC exploitation - Part 1: Broken cryptography](https://wojciechregula.blog/post/learn-xpc-exploitation-part-1-broken-cryptography/)
- [Wojciech Reguła: Learn XPC exploitation - Part 2: Say no to the PID!](https://wojciechregula.blog/post/learn-xpc-exploitation-part-2-say-no-to-the-pid/)
- [Wojciech Reguła: Learn XPC exploitation - Part 3: Code injections](https://wojciechregula.blog/post/learn-xpc-exploitation-part-3-code-injections/)
- [Apple Developer: EvenBetterAuthorizationSample](https://developer.apple.com/library/archive/samplecode/EvenBetterAuthorizationSample/Introduction/Intro.html)
- [erikberglund/SwiftPrivilegedHelper](https://github.com/erikberglund/SwiftPrivilegedHelper)
- [aronskaya/smjobbless](https://github.com/aronskaya/smjobbless)
- [securing/SimpleXPCApp](https://github.com/securing/SimpleXPCApp)
