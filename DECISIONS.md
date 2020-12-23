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
