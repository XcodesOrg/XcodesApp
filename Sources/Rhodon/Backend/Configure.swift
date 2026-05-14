public func configure<Subject>(_ subject: Subject, configuration: (inout Subject) -> Void) -> Subject {
    var copy = subject
    configuration(&copy)
    return copy
}
