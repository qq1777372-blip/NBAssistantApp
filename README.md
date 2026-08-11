# 小许后台管理系统 iOS App

Capacitor iOS app with a bundled Vue frontend and remote API at https://xiaoxu666.asia.

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

## Cloud build

1. Create a private GitHub repository.
2. Push this directory to the repository.
3. Open Actions and run `Build unsigned iOS IPA`.
4. Download the `NBAssistant-unsigned-ipa` artifact.
5. Import the unsigned IPA into 全能签 and sign it with your available certificate before installation.

The workflow intentionally creates an unsigned device IPA for tools such as 全能签. It cannot be installed directly by iOS until it is signed with a certificate and provisioning profile.
