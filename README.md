# 小许后台管理系统 iOS App

Capacitor iOS shell for https://xiaoxu666.asia/app/.

## Local synchronization

```powershell
npm ci
npm run sync
```

## Cloud build

1. Create a private GitHub repository.
2. Push this directory to the repository.
3. Open Actions and run `Build unsigned iOS IPA`.
4. Download the `NBAssistant-unsigned-ipa` artifact.
5. Import the unsigned IPA into 全能签 and sign it with your available certificate before installation.

The workflow intentionally creates an unsigned device IPA for tools such as 全能签. It cannot be installed directly by iOS until it is signed with a certificate and provisioning profile.
