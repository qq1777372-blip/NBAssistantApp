# 小许后台管理系统 iOS App

Capacitor iOS app with a bundled Vue frontend and remote API at https://xiaoxu666.asia.

## Local demo

Run the bundled frontend against local in-memory sample data:

```bash
npm run demo
```

Open `http://127.0.0.1:4174` and sign in with:

- Username: `demo`
- Password: `Demo@123456`

The demo server only listens on localhost. Its changes are kept in memory and are
reset whenever the server restarts. It does not call or modify the remote API.

Run the local data and interaction check with:

```bash
npm run check:demo
```

To restore all sample rows while the server is running, sign in and send a
`POST` request to `/demo/reset`, or simply restart `npm run demo`.

The Debug iOS scheme also points at this local server, so the same credentials work
in the simulator. Release builds continue to use the production API.

## Local synchronization

```powershell
# Build the native-mode snapshot from the main project first.
cd D:\PY\RuoShopAdmin\app-frontend
npm run build:native

# Copy app-frontend-native-dist into this repository's www directory,
# then synchronize the generated files into the iOS project.
cd D:\PY\NBAssistantApp
npm ci
npm run sync
```

Computer development remains in `D:\PY\RuoShopAdmin\app-frontend` and runs with
`npm run dev`. Only `build:native` targets the bundled iOS runtime and the remote
API at `https://xiaoxu666.asia`.

## Current release

- Web: `v2026.08.20.7`
- iOS: `v1.3.6 (build 58)`

The web bundle and demo API in this repository include the synchronized AI
workspace session context, daily usage data, share links, and message feedback.

## Cloud build

1. Create a private GitHub repository.
2. Push this directory to the repository.
3. Open Actions and run `Build unsigned iOS IPA`.
4. Download the `NBAssistant-unsigned-ipa` artifact.
5. Import the unsigned IPA into 全能签 and sign it with your available certificate before installation.

The workflow intentionally creates an unsigned device IPA for tools such as 全能签. It cannot be installed directly by iOS until it is signed with a certificate and provisioning profile.
