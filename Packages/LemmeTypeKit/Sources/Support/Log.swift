import os

/// The only sanctioned way to log in LemmeType.
///
/// Interpolated values are private by default in `os.Logger`. Mark a value
/// `.public` only when it is an enum case, identifier, count, or duration —
/// never audio, transcript, clipboard, or text from another application.
public enum Log {
    public static let subsystem = "com.lemmetype.LemmeType"

    public static let lifecycle = Logger(subsystem: subsystem, category: "lifecycle")
    public static let permissions = Logger(subsystem: subsystem, category: "permissions")
    public static let audio = Logger(subsystem: subsystem, category: "audio")
    public static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
    public static let recognition = Logger(subsystem: subsystem, category: "recognition")
}
