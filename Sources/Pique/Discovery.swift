import Foundation
import Network

/// Finds Bambu printers on the LAN. They multicast an SSDP NOTIFY to 239.255.255.250:1990
/// every ~10 s (port 2021 broadcast is usually taken by Bambu Studio, so we skip it).
final class Discovery: ObservableObject {
    struct Printer: Equatable {
        let ip: String
        let name: String
        let model: String
    }

    @Published var printers: [Printer] = []
    private var group: NWConnectionGroup?

    func start() {
        guard group == nil,
              let multicast = try? NWMulticastGroup(for: [.hostPort(host: "239.255.255.250", port: 1990)]) else { return }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        let group = NWConnectionGroup(with: multicast, using: params)
        group.setReceiveHandler(maximumMessageSize: 4096, rejectOversizedMessages: true) { [weak self] _, data, _ in
            // Anyone on the LAN can multicast this: cap the list (a flood must not grow it forever).
            guard let self, let data, self.printers.count < 16,
                  let printer = Self.parse(String(decoding: data, as: UTF8.self)),
                  !self.printers.contains(where: { $0.ip == printer.ip }) else { return }
            self.printers.append(printer)
        }
        group.start(queue: .main)
        self.group = group
    }

    func stop() {
        group?.cancel()
        group = nil
    }

    static func parse(_ message: String) -> Printer? {
        var headers: [String: String] = [:]
        for line in message.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        guard headers["nt"]?.contains("bambulab") == true, let ip = headers["location"], IPv4Address(ip) != nil else { return nil }
        let code = headers["devmodel.bambu.com"] ?? "?"
        return Printer(ip: ip, name: headers["devname.bambu.com"] ?? ip, model: models[code] ?? code)
    }

    private static let models = [
        "C11": "P1P", "C12": "P1S", "N1": "A1 mini", "N2S": "A1",
        "BL-P001": "X1C", "BL-P002": "X1", "C13": "X1E",
    ]
}
