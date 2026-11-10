import os

/// `log stream --predicate 'subsystem == "dev.victorzhu.Kanpe"' --level debug`
enum Log {
    static let trigger = Logger(subsystem: "dev.victorzhu.Kanpe", category: "trigger")
    static let app = Logger(subsystem: "dev.victorzhu.Kanpe", category: "app")
}
