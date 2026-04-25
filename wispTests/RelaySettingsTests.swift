import Testing
import Foundation
@testable import wisp

struct RelaySettingsTests {

    // MARK: - URL normalisation

    @Test func normalizeRejectsInvalid() {
        #expect(Nip51Lists.normalize("") == nil)
        #expect(Nip51Lists.normalize("relay.damus.io") == nil)        // no scheme
        #expect(Nip51Lists.normalize("https://relay.damus.io") == nil) // wrong scheme
        #expect(Nip51Lists.normalize("ftp://x") == nil)
    }

    @Test func normalizeAcceptsValid() {
        #expect(Nip51Lists.normalize("wss://Relay.Damus.IO/") == "wss://relay.damus.io")
        #expect(Nip51Lists.normalize("ws://localhost:7777") == "ws://localhost:7777")
        #expect(Nip51Lists.normalize(" wss://relay.example.com ") == "wss://relay.example.com")
    }

    // MARK: - kind 10002 (NIP-65 general relays)

    @Test func parseGeneralRelayList_bothMarker() {
        let event = makeEvent(kind: 10002, tags: [
            ["r", "wss://relay.damus.io"],                  // both
            ["r", "wss://relay.primal.net", "read"],        // read only
            ["r", "wss://nos.lol", "write"]                 // write only
        ])
        let parsed = Nip51Lists.parseGeneralRelayList(event)
        #expect(parsed.count == 3)
        #expect(parsed[0] == GeneralRelay(url: "wss://relay.damus.io", read: true,  write: true))
        #expect(parsed[1] == GeneralRelay(url: "wss://relay.primal.net", read: true, write: false))
        #expect(parsed[2] == GeneralRelay(url: "wss://nos.lol", read: false, write: true))
    }

    @Test func buildGeneralRelayTags_roundTrip() {
        let input = [
            GeneralRelay(url: "wss://relay.damus.io", read: true, write: true),
            GeneralRelay(url: "wss://primal.net", read: true, write: false),
            GeneralRelay(url: "wss://nos.lol", read: false, write: true)
        ]
        let tags = Nip51Lists.buildGeneralRelayTags(input)
        #expect(tags == [
            ["r", "wss://relay.damus.io"],
            ["r", "wss://primal.net", "read"],
            ["r", "wss://nos.lol", "write"]
        ])
        // Round-trip through a synthesised event.
        let event = makeEvent(kind: 10002, tags: tags)
        let parsed = Nip51Lists.parseGeneralRelayList(event)
        #expect(parsed == input)
    }

    @Test func buildGeneralRelayTags_skipsEmptyRelay() {
        let input = [GeneralRelay(url: "wss://relay.damus.io", read: false, write: false)]
        #expect(Nip51Lists.buildGeneralRelayTags(input).isEmpty)
    }

    // MARK: - kind 10050 / 10007 / 10006 (simple relay-set lists)

    @Test func parseRelaySetList_relayTag() {
        let event = makeEvent(kind: 10050, tags: [
            ["relay", "wss://inbox.example.com"],
            ["relay", "wss://Inbox.Example.com"],   // duplicate after normalize
            ["d", "junk"],                           // unrelated tag, ignored
            ["r", "wss://second.example"]            // accepts "r" alias too
        ])
        let parsed = Nip51Lists.parseRelaySetList(event)
        #expect(parsed == ["wss://inbox.example.com", "wss://second.example"])
    }

    @Test func buildRelaySetListTags_normalises() {
        let urls = ["wss://A.example/", "ws://localhost:7777", "garbage"]
        let tags = Nip51Lists.buildRelaySetListTags(urls)
        #expect(tags == [["relay", "wss://a.example"], ["relay", "ws://localhost:7777"]])
    }

    // MARK: - Helpers

    private func makeEvent(kind: Int, tags: [[String]]) -> NostrEvent {
        NostrEvent(
            id: String(repeating: "0", count: 64),
            pubkey: String(repeating: "1", count: 64),
            kind: kind,
            createdAt: 1700000000,
            tags: tags,
            content: "",
            sig: String(repeating: "2", count: 128)
        )
    }
}
