# Local Network Privacy

Source: [TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy), revised 2026-10-06, and a device test on 2026-11-22.

## What it gates

- A local network is "an IP network associated with a broadcast-capable network interface ... Wi-Fi and Ethernet, but not cellular (WWAN) or VPN."
- Outgoing TCP connects and UDP sends (unicast, broadcast, multicast) to local addresses, through every API: "Network framework, BSD Sockets, URLSession".
- Exempt: the device's DNS server and proxy even when local, WKWebView and Safari traffic, resolving non-local names.
- ICMP is not mentioned. On a device, datagram ICMP echo to the Gateway (192.168.1.1) answered in 6 ms with no prompt, and Settings showed no Local Network switch for the app. So ICMP Gateway Probes are never `denied`.

## Prompt and Settings

- The first local network operation shows the alert. The app appears in Settings > Privacy & Security > Local Network only after it attempts one; an app that only pings the Gateway never appears.
- In the background on iOS the operation is denied silently and the decision isn't recorded.
- The Simulator doesn't implement it: "Test your local network privacy behavior on a real device."
- No API reports current access or shows the alert; connecting a UDP socket to a link-local address triggers it best-effort.

## How denial shows up

- Network framework: the connection waits with `currentPath?.unsatisfiedReason == .localNetworkDenied`, and retries by itself once the user allows it.
- BSD sockets: TN3179 names no errno. The app treats EHOSTUNREACH or EPERM on a UDP send to the Gateway as `denied`, unverified.
