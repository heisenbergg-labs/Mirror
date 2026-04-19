<p align="center">
  <img src="assets/mirror-icon.png" alt="Mirror" width="160">
</p>

<h1 align="center">Mirror</h1>

<p align="justify">I built this for myself. When my Android phone is on a tripod, I wanted to see the framing on my Mac without picking it up.</p>

<p align="justify">It's a spinoff of <a href="https://github.com/Genymobile/scrcpy">scrcpy</a> — same engine, wrapped in a one-click Mac app so I never think about adb, ports, or flags. Open it, the phone appears, and Back / Home / Recents sit in a small bar under the window for gesture-nav phones. It remembers the Wi-Fi address, so after the first time I don't plug in again.</p>

<p align="center"><em>Android only — scrcpy doesn't speak to iPhones.</em></p>

<p align="justify">Streams at native resolution with a high bitrate, so framing and fine detail come through clean. Clipboard syncs both ways — copy on your Mac, paste on the phone, and vice versa. Videos recorded on the phone are automatically pulled to <code>~/Movies/Mirror/</code> while connected, so your editing app's watch folder picks them up without any manual transfer.</p>

<h3 align="center">Download</h3>

<p align="center"><a href="https://github.com/heisenbergg-labs/Mirror/releases/latest/download/Mirror.dmg">Mirror.dmg</a></p>

<p align="center">Open the DMG, drag <b>Mirror</b> into Applications.</p>

<h3 align="center">First run</h3>

<p align="justify">Plug the phone in once over USB, allow debugging when prompted, open Mirror. It switches to Wi-Fi and remembers the phone — after that, the cable stays in the drawer. If your phone has Wireless Debugging enabled (Android 11+), Mirror can find it automatically over the network without USB at all.</p>

<h3 align="center">Credit</h3>

<p align="justify">All the real work is <a href="https://github.com/Genymobile/scrcpy">scrcpy</a> by Genymobile. Mirror is a thin Mac shell around it.</p>
