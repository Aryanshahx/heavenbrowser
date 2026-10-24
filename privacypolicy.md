# Privacy Policy for Heaven Browser

**Effective Date:** October 23, 2026  
**Application Name:** Heaven Browser  
**Package Identifier:** `com.hypertechlabs.heavenbrowser`  
**Developer:** HyperTech Labs  
**Support & Privacy Contact:** [techlabs.hyper@gmail.com](mailto:techlabs.hyper@gmail.com)

---

## 1. Overview & Our Privacy Commitment

Heaven Browser is a fast, privacy-first mobile web browser built by **HyperTech Labs**. Our core principle is simple: **your browsing activity belongs strictly to you**.

- We **do not** operate tracking servers, analytics SDKs, advertising profiles, or cloud telemetry pipelines.
- We **do not** sell, rent, upload, or share your browsing history, open tabs, search queries, bookmarks, downloads, or site permissions with any third party.
- All personal browser state is stored **locally on your Android device** inside your private app sandbox and remains under your direct control.

---

## 2. Information Stored Locally on Your Device

To deliver a responsive browsing experience, Heaven Browser stores the following data locally on your device only:

1. **Persistent Open Tabs, Tab Previews & Tab Groups:** Your open normal tabs, tab preview thumbnails, tab groups, and active tab position are saved locally so your workspace is restored when you reopen the app. You can close tabs individually or wipe all sessions at any time using **Burn All Tabs & Site Data**.
2. **Bookmarks, History & Quick-Launch Sites:** Pages you visit or bookmark outside Incognito Mode are saved locally on your device. Incognito Mode never records browsing history, search queries, or site usage, and scrubs session cookies and WebView storage when Incognito tabs are closed.
3. **Per-Site Permissions:** Your site-by-site decisions (Allow, Block, or Ask) for Location, Camera, Microphone, JavaScript, Pop-ups, Protected Media, and Web Notifications are stored locally and can be revoked in one tap from the **Per-Site Permission Dashboard**.
4. **Downloaded Files & Media Streams:** Files, videos, and audio streams you choose to download are saved directly to your chosen local Downloads folder on your device and managed inside the built-in **Downloads** tab.

---

## 3. Search Engines & Direct Website Connections

- **Default Search Engine:** Heaven uses **Google Search** (`https://www.google.com`) as the default search engine, and lets you switch at any time to **Perplexity**, **DuckDuckGo**, **Brave Search**, **Bing**, or **Startpage**.
- When you submit a search query, load a webpage, or request search autocomplete suggestions, your device connects directly to that search engine or website. Your interaction with external websites is governed by each destination site's own privacy policy.
- When **HTTPS Upgrade** and **Do Not Track / GPC** are enabled, Heaven upgrades eligible `http://` navigations to encrypted `https://` and sets standard `DNT` and `GPC` privacy signals.

---

## 4. Android Device Permissions Explained

Heaven Browser requests only the Android permissions required for features you actively use:

- **Internet & Network State (`INTERNET`, `ACCESS_NETWORK_STATE`):** Required to load websites, download files, and check network connectivity.
- **Notifications (`POST_NOTIFICATIONS`):** Requested when opening the app so Heaven Browser can display live download progress alerts, offline media stream completion alerts, and background audio playback controls. You can customize or disable notification categories at any time in **Settings -> Notifications** or Android System Settings.
- **Biometric Authentication (`USE_BIOMETRIC`, `USE_FINGERPRINT`):** Used solely to unlock **Incognito Tabs** or the **Heaven Browser App Lock** via Android's native `BiometricPrompt` (fingerprint or face unlock). Heaven Browser never reads, stores, or transmits raw biometric data; verification is handled entirely by the Android operating system hardware keystore.
- **Camera, Microphone & Location (`CAMERA`, `RECORD_AUDIO`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`):** Never accessed in the background by Heaven Browser itself. These permissions are requested **only** when a website you are visiting explicitly asks to use your camera, microphone, or location **and** you approve that site in Heaven Browser's permission prompt. You can revoke access for any site in a single tap via the **Per-Site Permission Dashboard**.
- **Foreground Media Playback & Wake Lock (`FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`):** Used only while you play background audio/video with the screen locked or in Picture-in-Picture (PiP) mode so Android does not interrupt active playback.
- **Home Screen Shortcuts (`INSTALL_SHORTCUT`):** Used only when you tap **Create shortcut** to pin a website icon to your Android launcher.
- **VPN Tunnel Service (`VpnService`):** Used only when you explicitly turn on the built-in VPN inside Heaven Browser to route traffic through your selected tunnel. Heaven Browser posts no tracking logs of VPN traffic.

---

## 5. Native Brave-Style Shields & Multi-Country VPN

- **On-Device Native Shields:** Heaven runs its ad, tracker, CNAME-uncloaking, cosmetic filtering, SugarCoat surrogate replacement, and anti-fingerprinting ("Farbling") engine **100% locally on your Android device**. Filter rules from public EasyList and EasyPrivacy lists are cached locally on your device without sending any browsing URLs externally.
- **Optional Built-In VPN:** When you explicitly connect a country in **Heaven VPN**, traffic is encrypted via OpenVPN or WireGuard using either Browser-Only Split Tunneling (so only Heaven uses the VPN) or Full-Device mode. Heaven never logs, inspects, or stores your VPN traffic.

---

## 6. Personalized News Feed

The optional Discover news feed on the Start Page fetches public RSS news headlines directly from news publishers and ranking feeds. Topic preferences are computed **100% locally on your device** and can be reset or cleared at any time. Incognito tabs never display or update personalized news interests.

---

## 7. Data Deletion & User Controls

You have immediate, complete control over all local data inside Heaven Browser:

- **One-Tap Burn:** Open **Settings -> Burn All Tabs, Cookies & Storage** (or enable **Auto-Burn When App Backgrounded**) to permanently erase open tabs, cookies, DOM storage, cache, and browsing history.
- **Per-Site Cleanup:** Open **Site Controls / Permissions** on any webpage to revoke permissions or clear cookies and storage for that specific domain.
- **Uninstalling the App:** Uninstalling Heaven Browser from your Android device immediately deletes all data stored inside the app's private storage directory.

---

## 8. Children's Privacy

Heaven Browser does not knowingly collect personal information from anyone, including children under the age of 13.

---

## 9. Changes to This Privacy Policy

If we introduce new browser capabilities that affect how permissions or local data operate, we will update this document in our public GitHub repository at:  
`https://github.com/Aryanshahx/heavenbrowser/blob/main/privacypolicy.md`

---

## 10. Contact Us

If you have any questions, privacy inquiries, or security reports regarding Heaven Browser, please contact **HyperTech Labs** at:

- **Email:** [techlabs.hyper@gmail.com](mailto:techlabs.hyper@gmail.com)
- **Repository:** [https://github.com/Aryanshahx/heavenbrowser](https://github.com/Aryanshahx/heavenbrowser)
