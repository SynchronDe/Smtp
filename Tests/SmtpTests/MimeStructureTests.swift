//
//  Regressionstest fuer den schliessenden MIME-Delimiter.
//

import XCTest
import NIO
@testable import Smtp

final class MimeStructureTests: XCTestCase {

    private func render(attachments: Int, isBodyHtml: Bool) throws -> String {
        var email = try Email(from: EmailAddress(address: "absender@synchron.de", name: "ELGA Service"),
                              to: [EmailAddress(address: "empfaenger@example.com", name: "Test")],
                              subject: "Rechteabtretung",
                              body: isBodyHtml ? "<p>Anbei das Dokument.</p>" : "Anbei das Dokument.",
                              isBodyHtml: isBodyHtml)
        for i in 0..<attachments {
            email.addAttachment(Attachment(name: "Dokument_\(i).pdf",
                                           contentType: "application/pdf",
                                           data: Attachments.text()))
        }
        var buffer = ByteBufferAllocator().buffer(capacity: 4096)
        email.write(to: &buffer)
        return buffer.getString(at: 0, length: buffer.readableBytes) ?? ""
    }

    private func boundary(of mime: String) -> String {
        guard let r = mime.range(of: "boundary=\"") else { return "" }
        let rest = mime[r.upperBound...]
        return String(rest.prefix(while: { $0 != "\"" }))
    }

    /// Die Nachricht endet mit dem schliessenden Delimiter --boundary--.
    func testClosingDelimiterIsPresent() throws {
        for count in 1...3 {
            for html in [true, false] {
                let mime = try render(attachments: count, isBodyHtml: html)
                let b = boundary(of: mime)
                XCTAssertFalse(b.isEmpty, "Boundary nicht gefunden")
                XCTAssertTrue(mime.contains("--\(b)--\r\n"),
                              "Schliessender Delimiter fehlt (attachments=\(count), html=\(html))")
            }
        }
    }

    /// Genau ein Delimiter je Part plus genau ein schliessender.
    func testDelimiterCount() throws {
        for count in 1...3 {
            let mime = try render(attachments: count, isBodyHtml: false)
            let b = boundary(of: mime)
            let closing = mime.components(separatedBy: "--\(b)--").count - 1
            // Alle Vorkommen von --boundary (inkl. der schliessenden)
            let all = mime.components(separatedBy: "--\(b)").count - 1
            // Erwartet: 1 Body-Part + count Anhaenge + 1 schliessender.
            // Der schliessende zaehlt bei "all" doppelt (--b--  enthaelt --b und das Suffix --),
            // deshalb: all == 1 + count + 1
            XCTAssertEqual(closing, 1, "Genau ein schliessender Delimiter erwartet (attachments=\(count))")
            XCTAssertEqual(all, count + 2,
                           "Erwartet \(count + 2) Delimiter-Vorkommen, gefunden \(all) (attachments=\(count))")
        }
    }

    /// Kein oeffnender Delimiter unmittelbar vor dem Nachrichtenende.
    func testNoDanglingOpeningDelimiter() throws {
        let mime = try render(attachments: 2, isBodyHtml: true)
        let b = boundary(of: mime)
        XCTAssertFalse(mime.hasSuffix("--\(b)\r\n\r\n."),
                       "Nachricht endet mit einem oeffnenden Delimiter, der keinen Part mehr ankuendigt")
    }

    /// Ausgabe zur externen Gegenpruefung.
    func testDumpForExternalParser() throws {
        let mime = try render(attachments: 2, isBodyHtml: true)
        try mime.write(toFile: "/tmp/mime_after.txt", atomically: true, encoding: .utf8)
        XCTAssertFalse(mime.isEmpty)
    }
}
