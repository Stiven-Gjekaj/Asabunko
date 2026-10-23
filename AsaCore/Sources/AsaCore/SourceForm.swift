import Foundation

/// A settings form of a source, in sections. An action of the user can change the form,
/// so the source gives the form again after each action.
public struct SourceForm: Sendable, Equatable, Decodable {
    public struct Section: Sendable, Equatable, Decodable, Identifiable {
        public var id: String
        public var header: String?
        public var footer: String?
        public var rows: [Row]
    }

    public struct Row: Sendable, Equatable, Decodable, Identifiable {
        public enum Kind: Sendable, Equatable {
            /// A text, with a value or a mark. With `selectable`, a tap does the action of the row.
            case label
            case input
            case toggle
            case button
            /// A row that opens the form with the ID `form`.
            case link
            /// A row that the app cannot do, such as a sign-in with OAuth.
            case unsupported
        }

        public var id: String
        public var type: String
        public var title: String
        public var subtitle: String?
        /// The text of a label, a link, or an input.
        public var value: String?
        /// "included" or "excluded" for a choice of a list.
        public var mark: String?
        public var selectable: Bool?
        /// The value of a toggle.
        public var on: Bool?
        public var form: String?

        public var kind: Kind {
            switch type {
            case "labelRow": .label
            case "inputRow": .input
            case "toggleRow": .toggle
            case "buttonRow": .button
            case "navigationRow": form == nil ? .label : .link
            default: .unsupported
            }
        }
    }

    public var id: String
    /// True when the user must save the form. The changes then go to the source only with `submitForm`.
    public var submit: Bool
    public var sections: [Section]
}

/// What the user does to a row of a form.
public enum FormInput: Sendable, Equatable {
    case tap
    case text(String)
    case toggle(Bool)
}

public enum SourceFormError: Error, Equatable, LocalizedError {
    case noForm

    public var errorDescription: String? { "This source has no settings form." }
}
