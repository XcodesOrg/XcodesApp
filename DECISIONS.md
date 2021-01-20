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

## Selecting the active version of Xcode

This isn't a technical decision, but we spent enough time talking about this that it's probably worth sharing. When a user has more than one version of Xcode installed, a specific version of the developer tools can be selected with the `xcode-select` tool. The selected version of tools like xcodebuild or xcrun will be used unless the DEVELOPER_DIR environment variable has been set to a different path. You can read more about this in the `xcode-select` man pages. Notably, the man pages and [some notarization documentation](https://developer.apple.com/documentation/xcode/notarizing_macos_software_before_distribution) use the term "active" to indicate the Xcode version that's been selected. [This](https://developer.apple.com/library/archive/technotes/tn2339/_index.html#//apple_ref/doc/uid/DTS40014588-CH1-HOW_DO_I_SELECT_THE_DEFAULT_VERSION_OF_XCODE_TO_USE_FOR_MY_COMMAND_LINE_TOOLS_) older tech note uses the term "default". And of course, the `xcode-select` tool has the term "select" in its name. xcodes used the terms "select" and "selected" for this functionality, intending to match the xcode-select tool.

Here are the descriptions of these terms from [Apple's Style Guide](https://books.apple.com/ca/book/apple-style-guide/id1161855204):

> active: Use to refer to the app or window currently being used. Preferred to in front.  
> default: OK to use to describe the state of settings before the user changes them. See also preset.  
> preset: Use to refer to a group of customized settings an app provides or the user saves for reuse.  
> select: Use select, not choose, to refer to the action users perform when they select among multiple objects.  

Xcodes.app has this same functionality as xcodes, which still uses `xcode-select` under the hood, but because the main UI is a list of selectable rows, there _may_ be some ambiguity about the meaning of "selected". "Default" has a less clear connection to `xcode-select`'s name, but does accurately describe the behaviour that results. In Xcode 11 Launch Services also uses the selected Xcode version when opening a (GUI) developer tool bundled with Xcode, like Instruments. We could also try to follow Apple's lead by using the term "active" from the `xcode-select` man pages and notarization documentation. According to the style guide "active" already has a clear meaning in a GUI context.

Ultimately, we've decided to align with Apple's usage of "active" and "make active" in this specific context, despite possible confusion with the definition in the style guide. 

## Software Updates

We're familiar with using GitHub releases to distribute pre-built, code signed and notarized versions of `xcodes` via direct download and Homebrew. Ideally we could use GitHub releases here too with an update mechanism more suitable for an app bundle. For distribution outside the Mac App Store, the most popular choice for updates is [Sparkle](https://sparkle-project.org). The v2 branch has been in beta for a long time, but since Xcodes.app isn't (currently) sandboxed, we can use the production-ready v1 releases.

Based on [this blog post](https://yiqiu.me/2015/11/19/sparkle-update-on-github/), we can use GitHub Pages to generate the appcast for Sparkle to point at releases in our repo. We've made a few changes, like putting the source for the Jekyll site on the main branch, and including the EdDSA signature in the appcast. Generating the appcast file manually would be more straightforward, but we can always edit the files on the gh_pages branch manually if we need to, and it's one less step for a release manager to perform when they're already creating the release in the repo.

We're deliberately not capturing system profile data with Sparkle right now, because we don't want it and because it would require additional infrastructure.

We also considered https://github.com/mxcl/AppUpdater, but decided aganist it because it seemed less battle-tested than Sparkle and currently lacks an open source license.
