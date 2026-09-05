import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("Native authentication bridge")
struct NativeAuthenticationBridgeTests {
    private let requestID = "2a8adad0-e2e3-43a0-882f-82f64d691c86"
    private let challenge = String(repeating: "ab", count: 32)
    private let guestID = String(repeating: "ef", count: 32)

    @Test("sudo requests use a strict versioned context")
    func sudoRequestSchema() throws {
        let line = Data(
            #"{"challenge":"\#(challenge)","guestId":"\#(guestID)","operation":"sudo","requestId":"\#(requestID)","requestingUser":"test","service":"sudo","tty":"/dev/pts/4","type":"authorize","user":"test","version":2}"#.utf8
        )
        #expect(
            try NativeAuthenticationRequest.decode(line)
                == NativeAuthenticationRequest(
                    operation: .sudo,
                    guestID: guestID,
                    requestID: requestID,
                    challenge: challenge,
                    user: "test",
                    requestingUser: "test",
                    service: "sudo",
                    tty: "/dev/pts/4"
                )
        )
    }

    @Test("enrollment cannot smuggle sudo context")
    func enrollmentSchema() throws {
        let valid = Data(
            #"{"challenge":"\#(challenge)","guestId":"\#(guestID)","operation":"enroll","requestId":"\#(requestID)","requestingUser":"","service":"sudo","tty":"","type":"authorize","user":"","version":2}"#.utf8
        )
        #expect(try NativeAuthenticationRequest.decode(valid).operation == .enroll)

        let invalid = Data(
            #"{"challenge":"\#(challenge)","guestId":"\#(guestID)","operation":"enroll","requestId":"\#(requestID)","requestingUser":"test","service":"sudo","tty":"","type":"authorize","user":"test","version":2}"#.utf8
        )
        #expect(throws: HelperError.self) {
            try NativeAuthenticationRequest.decode(invalid)
        }
    }

    @Test("malformed or extensible authorization requests are rejected")
    func invalidRequests() {
        for line in [
            "not json",
            #"{"challenge":"short","guestId":"\#(guestID)","operation":"sudo","requestId":"\#(requestID)","requestingUser":"test","service":"sudo","tty":"/dev/pts/1","type":"authorize","user":"test","version":2}"#,
            #"{"challenge":"\#(challenge)","guestId":"short","operation":"sudo","requestId":"\#(requestID)","requestingUser":"test","service":"sudo","tty":"/dev/pts/1","type":"authorize","user":"test","version":2}"#,
            #"{"challenge":"\#(challenge)","guestId":"\#(guestID)","operation":"sudo","requestId":"not-a-uuid","requestingUser":"test","service":"sudo","tty":"/dev/pts/1","type":"authorize","user":"test","version":2}"#,
            #"{"challenge":"\#(challenge)","guestId":"\#(guestID)","operation":"sudo","requestId":"\#(requestID)","requestingUser":"test","service":"login","tty":"/dev/pts/1","type":"authorize","user":"test","version":2}"#,
            #"{"challenge":"\#(challenge)","guestId":"\#(guestID)","operation":"sudo","requestId":"\#(requestID)","requestingUser":"test","service":"sudo","tty":"unknown","type":"authorize","user":"test","version":2}"#,
            #"{"challenge":"\#(challenge)","extra":true,"guestId":"\#(guestID)","operation":"sudo","requestId":"\#(requestID)","requestingUser":"test","service":"sudo","tty":"/dev/pts/1","type":"authorize","user":"test","version":2}"#,
        ] {
            #expect(throws: HelperError.self) {
                try NativeAuthenticationRequest.decode(Data(line.utf8))
            }
        }
    }

    @Test("signature payload binds every sudo context field")
    func signaturePayload() {
        let request = NativeAuthenticationRequest(
            operation: .sudo,
            guestID: guestID,
            requestID: requestID,
            challenge: challenge,
            user: "root",
            requestingUser: "test",
            service: "sudo",
            tty: "/dev/pts/7"
        )
        #expect(
            request.signaturePayload(
                issuedAt: 1_788_623_100,
                expiresAt: 1_788_623_115,
                keyID: String(repeating: "cd", count: 32)
            )
                == Data(
                    [
                        "try-omarchy-native-authentication-v2",
                        guestID,
                        "sudo",
                        requestID,
                        challenge,
                        "root",
                        "test",
                        "sudo",
                        "/dev/pts/7",
                        "1788623100",
                        "1788623115",
                        String(repeating: "cd", count: 32),
                    ].joined(separator: "\0").utf8
                )
        )
    }

    @Test("approved responses carry signed material and denials carry none")
    func responseSchema() throws {
        let request = NativeAuthenticationRequest(
            operation: .sudo,
            guestID: guestID,
            requestID: requestID,
            challenge: challenge,
            user: "test",
            requestingUser: "test",
            service: "sudo",
            tty: "/dev/pts/2"
        )
        let publicKey = Data([0x04] + Array(repeating: UInt8(0x11), count: 64))
        let signature = Data([0x30, 0x02, 0x01, 0x01])
        let encoded = try NativeAuthenticationResponse(
            request: request,
            approval: NativeAuthenticationApproval(
                issuedAt: 1_788_623_100,
                expiresAt: 1_788_623_115,
                keyID: String(repeating: "cd", count: 32),
                publicKey: publicKey,
                signature: signature
            )
        ).encode()
        let object = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        #expect(object.keys.sorted() == [
            "approved", "challenge", "expiresAt", "guestId", "issuedAt", "keyId",
            "operation", "publicKey", "requestId", "requestingUser", "service",
            "signature", "tty", "type", "user", "version",
        ])
        #expect(object["approved"] as? Bool == true)
        #expect(object["publicKey"] as? String == publicKey.base64EncodedString())
        #expect(object["signature"] as? String == signature.base64EncodedString())
        #expect(encoded.last == 0x0A)

        let denied = try NativeAuthenticationResponse(request: request, approval: nil).encode()
        let deniedObject = try #require(
            JSONSerialization.jsonObject(with: denied) as? [String: Any]
        )
        #expect(deniedObject["approved"] as? Bool == false)
        #expect(deniedObject["issuedAt"] as? Int == 0)
        #expect(deniedObject["keyId"] as? String == "")
    }

    @Test("prompt text is fixed by operation and approvals are short-lived")
    func promptPolicy() {
        #expect(NativeAuthenticationOperation.enroll.localizedReason.contains("Pair"))
        #expect(NativeAuthenticationOperation.sudo.localizedReason.contains("sudo"))
        #expect(SecureEnclaveAuthorizationSigner.approvalLifetimeSeconds == 15)
    }
}
