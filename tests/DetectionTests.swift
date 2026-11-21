import Foundation
@main struct Tests {
    static func main() {
        let positive = ["Allow once", "Approve", "Allow for this session", "Yes, proceed", "Yes, and don’t ask again for this command", "  ALLOW   ONCE  "]
        let negative = ["Continue", "Yes", "Run", "Allow", "Copy", "Send", "Stop generating", "Request permission", "Tell me how to approve", "Disallow"]
        for text in positive { precondition(ApprovalDetection.isApprovalButton(text), text) }
        for text in negative { precondition(!ApprovalDetection.isApprovalButton(text), text) }
        precondition(ApprovalDetection.hasRequestContext("Codex requires approval to run this command"))
        precondition(!ApprovalDetection.hasRequestContext("Please explain permissions to me"))
        print("Native detection: 18 positive/negative cases passed")
    }
}
