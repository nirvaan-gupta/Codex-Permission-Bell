import Foundation

enum ApprovalDetection {
    static func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func isApprovalButton(_ text: String) -> Bool {
        let s = normalized(text)
        let exact = ["allow once", "allow this time", "allow for this session", "allow for session", "allow always", "always allow", "approve", "approve once", "approve session", "approve for this session", "approve and run", "allow and run", "yes, proceed", "yes, run", "run command", "grant permission"]
        return exact.contains(s) || s.hasPrefix("yes, and don't ask again") || s.hasPrefix("yes, and don’t ask again") || s.hasPrefix("allow for this ")
    }
    static func isGenericApproval(_ text: String) -> Bool {
        ["allow", "yes", "continue", "run", "confirm"].contains(normalized(text))
    }
    static func hasRequestContext(_ text: String) -> Bool {
        let s = normalized(text)
        return ["requires approval", "approval required", "requesting approval", "needs your approval", "permission required", "requesting permission", "allow chatgpt", "allow codex", "would you like to run", "do you want to run", "allow this command", "allow this action", "allow this tool", "wants to", "requires your permission", "do you approve", "allow access", "grant access"].contains { s.contains($0) }
    }
}
