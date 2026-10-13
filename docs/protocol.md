# How Pique talks to the printer

Everything Pique knows about the local (LAN) protocol of Bambu Lab P1/A1 printers. Tested on a P1S, firmware 01.10.00.00, in normal cloud mode. LAN Only mode and Developer Mode are not required.

The printer exposes three things on the local network. Pique uses all three, read-only except for one command (the chamber light):

| What | Transport | Used for |
|---|---|---|
| Discovery | SSDP-style UDP multicast | Listing printers in Settings |
| Camera | TLS on TCP port 6000, custom framing | Live view, notification snapshots |
| Status | MQTT 3.1.1 over TLS on port 8883 | Progress, temperatures, AMS, notifications |

Credentials for camera and status: user `bblp`, password = the printer's 8-character **access code** (printer screen: Settings > WLAN, below the IP address).

## Discovery

Printers announce themselves with an SSDP `NOTIFY` every ~10 seconds, multicast to `239.255.255.250` port **1990** (the `HOST` header says 1900, but packets arrive on 1990):

```
NOTIFY * HTTP/1.1
HOST: 239.255.255.250:1900
Location: <printer IP>
NT: urn:bambulab-com:device:3dprinter:1
USN: <serial number>
DevModel.bambu.com: C12
DevName.bambu.com: <name set by the user>
DevConnect.bambu.com: cloud
DevVersion.bambu.com: 01.10.00.00
DevSignal.bambu.com: -44
```

- Model codes: `C11` P1P, `C12` P1S, `N1` A1 mini, `N2S` A1, `BL-P001` X1C, `BL-P002` X1, `C13` X1E.
- The printers also broadcast on UDP port 2021, but Bambu Studio binds that port exclusively while it runs, so Pique listens on the 1990 multicast group instead (`NWConnectionGroup` with `allowLocalEndpointReuse`).
- A unicast or multicast `M-SEARCH` got no reply in our tests: just wait for the next `NOTIFY`.

Code: [`Discovery.swift`](../Sources/Pique/Discovery.swift). Try it: `swift run Pique --discover`.

## Camera (port 6000)

Bambu printers use one of two camera protocols. According to [ha-bambulab](https://github.com/greghesp/ha-bambulab/blob/main/custom_components/bambu_lab/pybambu/models.py), P1P, P1S, A1, A1 mini and A2L use the image protocol below, while X1, X1C, X1E, P2S, H2D, H2S, H2C and X2D stream RTSPS on port 322 (`rtsps://bblp:<access code>@<ip>:322/streaming/live/1`, H.264), which Pique does not support yet. The image protocol was first documented by [ha-bambulab](https://github.com/greghesp/ha-bambulab/blob/main/custom_components/bambu_lab/pybambu/bambu_client.py):

1. Open TCP to `<ip>:6000` and start TLS 1.2. The printer certificate is signed by Bambu's own CA ("BBL CA"), not a public one, so default verification fails: verify the chain against the Bambu CA instead (see [Verifying the printer](#verifying-the-printer)).
2. Send one 80-byte authentication packet:

   | Bytes | Content |
   |---|---|
   | 0–15 | four little-endian `uint32`: `0x40`, `0x3000`, `0`, `0` |
   | 16–47 | `bblp`, zero-padded to 32 bytes |
   | 48–79 | access code, zero-padded to 32 bytes |

3. Read frames in a loop: a 16-byte header whose first 3 bytes are the payload size (little-endian), then the payload, a complete JPEG (`FF D8` … `FF D9`). Example header: `4e250100 00000000 01000000 00000000` → 0x01254E = 75,086 bytes.

Observations:

- About **1 frame per second**, 1280×720, 60–90 KB each (~75 KB/s while streaming). This is the P1 camera's limit, not the protocol's.
- A wrong access code makes the printer close the connection.
- The camera seems to check only the first 8 characters of the code: a code with extra characters appended was accepted. MQTT does check the whole code, so validate the length (exactly 8) before saving.
- The stream can stall without the socket closing (printer asleep, Wi-Fi drop). Pique reconnects when no frame arrives for 10 s.
- Grabbing a single frame (connect, authenticate, read one frame, disconnect) takes about a second. Pique uses that for notifications instead of streaming in the background.

Code: [`Camera.swift`](../Sources/Pique/Camera.swift). Try it: `swift run Pique --snapshot frame.jpg`.

## Status (MQTT on port 8883)

- TLS 1.2 to `<ip>:8883`, MQTT 3.1.1, username `bblp`, password = access code, any client id.
- Subscribe to `device/<serial>/report`. The broker **closes the connection** on a wildcard subscription (`device/+/report`), so the serial is required.
- The serial number is the **common name of the printer's TLS certificate** (issuer `BBL CA`), so it can be read during the handshake without asking the user. It is also the `USN` of the discovery packet.
- Publish `{"pushing":{"sequence_id":"0","command":"pushall"}}` to `device/<serial>/request` to get a full report right away. Without it, P1 printers only send **deltas** (changed fields), so the client must merge every report into the previous state.
- A wrong access code: the broker closes the socket **without a CONNACK**. Pique shows this as "check the access code".
- Keepalive: send `PINGREQ` regularly (Pique: every 30 s, keepalive 60 s); treat 90 s of silence as a dead connection.

Useful fields of the `print` object in the report:

| Field | Meaning |
|---|---|
| `gcode_state` | `IDLE`, `PREPARE`, `RUNNING`, `PAUSE`, `FINISH`, `FAILED` (also `SLICING`) |
| `subtask_name` | Name of the file being printed |
| `mc_percent` | Progress, 0–100 |
| `mc_remaining_time` | Remaining time, in minutes |
| `layer_num` / `total_layer_num` | Current / total layer |
| `nozzle_temper` / `nozzle_target_temper` | Nozzle temperature / target, °C |
| `bed_temper` / `bed_target_temper` | Bed temperature / target, °C |
| `spd_lvl` / `spd_mag` | Speed profile (1 silent, 2 standard, 3 sport, 4 ludicrous) / percent |
| `cooling_fan_speed`, `big_fan1_speed`, `big_fan2_speed` | Part, aux and chamber fans, as a 0–15 "gear" (strings) |
| `lights_report` | `[{"node": "chamber_light", "mode": "on"}]` |
| `wifi_signal` | e.g. `"-45dBm"` |
| `nozzle_diameter`, `nozzle_type` | e.g. `"0.4"`, `"hardened_steel"` |
| `ams.ams[].tray[]` | Spools: `tray_type` (`PLA`…), `tray_color` (`RRGGBBAA`), `remain` (%) |
| `ams.tray_now` | Index of the spool in use |
| `print_error` | Error code; `0x0300400C` (50348044) = "task canceled" |
| `hms` | List of health-management alerts |

A canceled print is reported as `FAILED` with `print_error = 0x0300400C`; that is how Pique tells "canceled" from "failed". `chamber_temper` is meaningless on a P1S, which has no chamber sensor.

Code: [`Status.swift`](../Sources/Pique/Status.swift). Try it: `swift run Pique --status`.

## Verifying the printer

Both TLS services present the same certificate chain: a leaf whose common name is the printer serial, issued by `BBL CA` (`C=CN, O=BBL Technologies Co., Ltd`; SHA-256 `03:0B:CA:81:CE:CE:18:B7:EF:F3:CF:D2:B7:5D:09:D3:EF:CA:89:3B:C0:69:60:9E:37:FA:04:25:7F:E4:D8:40`, valid until 2032). The printer sends the CA too. Newer models use `BBL CA2` (RSA and ECC variants); [ha-bambulab ships all of them](https://github.com/greghesp/ha-bambulab/tree/main/custom_components/bambu_lab/pybambu/certs).

Pique ([`Trust.swift`](../Sources/Pique/Trust.swift)) accepts the connection only if:

1. the chain validates against the bundled Bambu CAs alone (`SecTrustSetAnchorCertificatesOnly`), with the basic X.509 policy (printers are reached by IP, so there is no host name to match). The evaluation date is capped at March 2032 because `BBL CA` expires before the printer certificates it signed;
2. the leaf's common name equals the serial recorded on the first successful connection (trust on first use). Saving the settings forgets it.

A device with any other certificate gets a TLS alert before the access code is sent.

## Commands

Commands are published as JSON to `device/<serial>/request`. The printer echoes the command on the report topic with a `result`, then sends the new state in a later `print` report.

Chamber light (the only command Pique sends, when the user clicks the light button):

```json
{"system": {"sequence_id": "1", "command": "ledctrl", "led_node": "chamber_light", "led_mode": "on",
            "led_on_time": 500, "led_off_time": 500, "loop_times": 0, "interval_time": 0}}
```

Reply: the same object plus `"result": "success", "reason": "success"`, then `lights_report` changes in the next report. Tested on a P1S, firmware 01.10.00.00, cloud mode, Developer Mode off: accepted. Try it: `swift run Pique --light off`.

## Authorization Control

Since P-series firmware 01.08.02.00 (June 2025), printers reject **control** commands (start a print, heat, move) from unofficial software ([All3DP](https://all3dp.com/4/bambu-lab-limits-third-party-printer-control-with-new-security-update/)). The read paths Pique uses (camera, MQTT subscribe, `pushall`) still work as of firmware 01.10.00.00. The chamber light command (above) is accepted; other commands have not been tried.

## Out of scope: remote access

Outside the LAN, Bambu Studio and Bambu Handy go through Bambu's cloud with a closed-source network plugin that appears to use ThroughTek TUTK peer-to-peer video ([BambuSource2Raw](https://github.com/hisptoot/BambuSource2Raw) reuses that plugin on Windows/Linux). Reimplementing it would be fragile and against Bambu's terms of use. For remote viewing, put the Mac on the printer's network through a VPN (e.g. Tailscale).

## Prior art

No native macOS menu bar app did this when the project started (October 2026). Related tools:

| Tool | What it is |
|---|---|
| [Bambu Handy](https://apps.apple.com/us/app/bambu-handy/id1625671285) | Official iPhone/iPad app, cloud live view |
| Bambu Studio | Official slicer, has a camera tab |
| [ha-bambulab](https://github.com/greghesp/ha-bambulab) | Home Assistant integration; reference for the camera protocol |
| [BambuP1Streamer](https://github.com/slynn1324/BambuP1Streamer) | Docker service that turns the P1 stream into MJPEG over HTTP |
| [BambuCAM](https://github.com/BangerTech/BambuCAM) | Self-hosted web app for several printers |
| [BambuFarm](https://bambufarm.app/) | Paid iOS app + desktop bridge for print farms |
| [OctoEverywhere Bambu Connect](https://blog.octoeverywhere.com/full-frame-rate-webcam-streaming-for-bambu-lab-3d-printers/) | Remote access and external webcam, runs on a Raspberry Pi |

## Sources

- [ha-bambulab `bambu_client.py`](https://github.com/greghesp/ha-bambulab/blob/main/custom_components/bambu_lab/pybambu/bambu_client.py)
- [Bambu forum: camera access on LAN](https://forum.bambulab.com/t/how-to-access-camera-on-lan-firmware-01-06/23500)
- [Bambu forum: P1P camera module communication](https://forum.bambulab.com/t/p1p-camera-module-communication-standard/6829)
- [All3DP: Authorization Control on P/A series](https://all3dp.com/4/bambu-labs-controversial-authorization-control-hits-budget-3d-printers/)
- Everything else on this page was observed directly on a P1S.
