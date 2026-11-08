**Cloudex Shield** is a kill switch for single apps: when your VPN drops, reconnects or switches servers, or Wi-Fi changes, the apps you choose pause — and resume exactly where they stopped once the address is the one you expect. It is not a VPN and never changes or routes your traffic.

**1.0.0 — first release**
- **Your country in the menu bar**, as claude.ai sees it (🇺🇸 US), ⚠︎ when the address is not in your allowed list, a red ❄︎ when apps are paused. Warnings for split routing, a second IP service seeing another address, apps that ignore the system proxy, and IPv6 bypassing the VPN.
- **Pause, don't kill.** Pick apps and allowed countries under **Network guard**. On an unexpected address the apps and everything they started are paused (`SIGSTOP`) and resume (`SIGCONT`) when the address is allowed again. On a network change or wake they are paused right away, until the new address checks out.
- **How others see us** — what claude.ai, the Claude API, chatgpt.com, Cloudflare and IP services see; IPv6, DNS and time zone checks.
- **Speed test** — download, upload and latency in one menu line, on demand.
- **Safe by design** — system apps, VPN clients and Cloudex Shield itself can never be paused; quitting resumes everything; the login item restarts it within a minute after a crash and it resumes what it had paused; nothing is paused until you pick at least one country and one app.
- **Built by GitHub, verifiable by you.** This release is built by GitHub Actions from the public source, with a signed build provenance attestation for every file. Check your download:
  `gh attestation verify CloudexShield.dmg --repo trapastnik/cloudex-shield`

**Coming from Cloudex Guard 1.1**: Cloudex Shield is the network guard that used to be part of [Cloudex Guard](https://github.com/trapastnik/cloudex-guard). On first launch it takes your allowed countries and guarded apps from Cloudex Guard 1.1 and resumes anything 1.1 left paused. Update Cloudex Guard to 1.2, which no longer has the network guard.

**Files**: `CloudexShield.dmg` (recommended), `CloudexShield-macos.zip` (used by `install.sh`), `SHA256SUMS.txt`. Universal (Apple Silicon and Intel), macOS 13+. Not notarized by Apple: the first time, allow it in System Settings → Privacy & Security → Open Anyway — see the [README](https://github.com/trapastnik/cloudex-shield#install).

Cloudex Shield is an independent project, not affiliated with Anthropic or OpenAI.
