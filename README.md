# NBAssistantApp

Capacitor iOS shell for https://xiaoxu666.asia/ui/dashboard.

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
5. Re-sign the IPA with a valid certificate before installation.

The workflow intentionally creates an unsigned device IPA. It cannot be installed directly by iOS until a signing tool signs it with a certificate and provisioning profile.
