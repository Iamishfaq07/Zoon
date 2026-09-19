import Foundation

/// Clock times rendered as standalone values, in columns that may be too
/// narrow for them.
enum ClockText {

    /// A short clock time that cannot be broken across lines.
    ///
    /// `formatted(time: .shortened)` returns "10:22 PM" with an ordinary
    /// space, and an ordinary space is a line-break opportunity. Put that in
    /// a column too narrow for eight characters and the layout takes it: the
    /// AX5 capture of Tomorrow shows "10:22 P" on one line above a lone "M".
    ///
    /// A non-breaking space makes the time a single token, so a column that
    /// cannot hold it moves the whole time to the next line instead of
    /// splitting it. Locale-independent in the way that matters -- it
    /// replaces whatever spaces the locale's short time contains, and a
    /// locale whose format has none is unaffected.
    ///
    /// **Where this belongs, and where it does not.** Use it for a time drawn
    /// as its own value in a layout that can squeeze it. Do not use it inside
    /// prose, in an `accessibilityLabel`, or in anything a coach tool emits
    /// as text: those are read or spoken rather than laid out, and a
    /// non-breaking space is a surprise in a string that was never going to
    /// wrap in a narrow column anyway.
    static func atomic(_ date: Date) -> String {
        atomic(date.formatted(date: .omitted, time: .shortened))
    }

    /// The same guarantee for a time that has already been formatted.
    ///
    /// A no-op on most Apple platforms now, and correctly so: the short-time
    /// formatter emits U+202F, a narrow no-break space, before the meridiem,
    /// so there is no ordinary space to replace and the time could never have
    /// broken there. This still matters for the locales and formats that do
    /// use one, and for a string assembled by hand rather than by the
    /// formatter. A test that demanded U+00A0 specifically failed on exactly
    /// this -- the property to hold is that the time cannot break, not which
    /// character achieves it.
    static func atomic(_ formatted: String) -> String {
        formatted.replacingOccurrences(of: " ", with: "\u{00A0}")
    }
}
