import Foundation

/// A settings form of a source, in sections. An action of the user can change the form,
/// so the source gives the form again after each action.
public struct SourceForm: Sendable, Equatable, Decodable {
    public struct Section: Sendable, Equatable, Decodable, Identifiable {
        public var id: String
        public var header: String?
        public var footer: String?
        public var rows: [Row]

        public init(id: String, header: String? = nil, footer: String? = nil, rows: [Row]) {
            self.id = id; self.header = header; self.footer = footer; self.rows = rows
        }
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
            /// A number between `minimum` and `maximum`, in steps of `step`.
            case stepper
            /// A row that opens the web page `url`.
            case web
            /// A sign-in of the kind of `login`.
            case login
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
        /// The text of an input is hidden, such as a password.
        public var secure: Bool?
        /// The question to ask before a button does its action.
        public var confirm: String?
        public var destructive: Bool?
        public var number: Double?
        public var minimum: Double?
        public var maximum: Double?
        public var step: Double?
        public var url: String?
        public var login: Login?

        public init(id: String, type: String, title: String, subtitle: String? = nil, value: String? = nil, mark: String? = nil,
                    selectable: Bool? = nil, on: Bool? = nil, form: String? = nil, secure: Bool? = nil, confirm: String? = nil,
                    destructive: Bool? = nil, number: Double? = nil, minimum: Double? = nil, maximum: Double? = nil, step: Double? = nil,
                    url: String? = nil, login: Login? = nil) {
            self.id = id; self.type = type; self.title = title; self.subtitle = subtitle; self.value = value; self.mark = mark
            self.selectable = selectable; self.on = on; self.form = form; self.secure = secure; self.confirm = confirm
            self.destructive = destructive; self.number = number; self.minimum = minimum; self.maximum = maximum; self.step = step
            self.url = url; self.login = login
        }

        public var kind: Kind {
            switch type {
            case "labelRow": .label
            case "inputRow": .input
            case "toggleRow": .toggle
            case "buttonRow": .button
            case "navigationRow": form == nil ? .label : .link
            case "stepperRow": .stepper
            case "linkRow": .web
            case "loginRow": login == nil ? .unsupported : .login
            default: .unsupported
            }
        }
    }

    /// What the app must do for a sign-in row.
    public struct Login: Sendable, Equatable, Decodable {
        /// "basic" for a user name and a password, "web" for a page in a web view, and "oauth" for a web sign-in that
        /// ends at `callbackScheme`.
        public var method: String
        public var url: String?
        public var callbackScheme: String?
        public var useEmail: Bool?
        public var signedIn: Bool
        public var username: String?
        /// The app removes the cookies of the site at the sign-out.
        public var clearsCookies: Bool?
        /// The keys of the local storage of the page that the source reads after a web sign-in.
        public var storageKeys: [String]?

        public init(method: String, url: String? = nil, callbackScheme: String? = nil, useEmail: Bool? = nil, signedIn: Bool,
                    username: String? = nil, clearsCookies: Bool? = nil, storageKeys: [String]? = nil) {
            self.method = method; self.url = url; self.callbackScheme = callbackScheme; self.useEmail = useEmail
            self.signedIn = signedIn; self.username = username; self.clearsCookies = clearsCookies; self.storageKeys = storageKeys
        }
    }

    public var id: String
    /// True when the user must save the form. The changes then go to the source only with `submitForm`.
    public var submit: Bool
    public var sections: [Section]

    public init(id: String, submit: Bool = false, sections: [Section]) {
        self.id = id; self.submit = submit; self.sections = sections
    }
}


/// What the user does to a row of a form.
public enum FormInput: Sendable, Equatable {
    case tap
    case text(String)
    case toggle(Bool)
    case number(Double)
    /// A sign-in with a user name and a password.
    case login(username: String, password: String)
    /// The end of a sign-in in a web view: the cookies of the site and the values of its local storage.
    case web(cookies: [String: String], storage: [String: String])
    /// The end of an OAuth sign-in: the URL of the callback.
    case callback(URL)
    case logout
}

public enum SourceFormError: Error, Equatable, LocalizedError {
    case noForm
    case refused
    case unknownRow

    public var errorDescription: String? {
        switch self {
        case .noForm: "This source has no settings form."
        case .refused: "The source did not accept the sign-in."
        case .unknownRow: "The setting is not in the form."
        }
    }
}
