# SVAGA+ builds

The application uses a build-time backend URL. Local builds default to staging so
they cannot accidentally connect to production.

```powershell
# staging
flutter build windows --release `
  --dart-define=SVAGAPLUS_ENV=staging `
  --dart-define=SVAGAPLUS_BASE_URL=https://svaga-staging.nekittop4ik.qzz.io

# production
flutter build windows --release `
  --dart-define=SVAGAPLUS_ENV=production `
  --dart-define=SVAGAPLUS_BASE_URL=https://svagaplus.com
```

`SVAGAPLUS_BASE_URL` is used for pairing, HTTP replay/history, and the `/timer`
Socket.IO namespace. Do not put device tokens or credentials in the URL.
