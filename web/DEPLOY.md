# Shipping RoboChess

Two things ship separately: the landing site (Vercel) and the Android build
(GitHub Release, or Google Play). Neither depends on the other.

---

# Part 1: The site on Vercel

## The one setting people get wrong

The Next.js app is **not** at the repository root, it is in `web/`. So in
Vercel:

**Project Settings → General → Root Directory → `web`**

Everything else auto-detects: framework Next.js, build `next build`, install
`npm install`. No build command overrides, no output directory override.

## Steps

1. Push the repo to GitHub.
2. Vercel → **Add New → Project** → import `rayyanshaikh123/robochess`.
3. Set **Root Directory** to `web` (see above).
4. Add the environment variable below if you are hosting the APK off-site.
5. **Deploy.**

## Environment variables

| Name | Needed? | What it does |
| --- | --- | --- |
| `NEXT_PUBLIC_APK_URL` | Recommended | Where the Download for Android button points. Unset, it serves `public/downloads/robochess.apk` from the deployment. Set it to a GitHub Release asset URL to keep a 54 MB binary out of git and off the CDN. |

## Before the first deploy, do these two things

### 1. Move the APK out of the repository

`web/public/downloads/robochess.apk` is 54 MB. Git keeps every version of it
forever, GitHub warns above 50 MB, and it is re-uploaded on every deploy. The
fix, once you have made a release (Part 2):

```bash
git rm --cached web/public/downloads/robochess.apk
echo "public/downloads/*.apk" >> web/.gitignore
```

Then set `NEXT_PUBLIC_APK_URL` in Vercel to the release asset URL, for example
`https://github.com/rayyanshaikh123/robochess/releases/download/v1.0.0/robochess-1.0.0.apk`.

The button, the footer link and the closing call to action all read that one
variable, so nothing else changes.

### 2. Rebuild the Flutter web app for its real home

The copy in `web/public/app/` was built for a laptop on your Wi-Fi. Two things
are baked into it that break once it is on the internet:

- **The base path.** A Flutter web build hardcodes `<base href="/">`, but the
  app is served from `/app/`. I have patched the committed build to
  `<base href="/app/">`, which is exactly what the build flag does, so it works
  today. **Any rebuild overwrites that and breaks it again**, so always pass the
  flag.
- **The backend address.** The build currently has `192.168.0.107:8000`,
  `192.168.1.42:8000` and `172.20.10.2:8765` compiled into it. Those are private
  addresses on your network. A visitor on the internet cannot reach them, so the
  hosted app will load its shell and then fail to sign in or play online.

Rebuild it like this, pointing at a backend that is actually reachable:

```bash
cd frontend
flutter build web --release \
  --base-href /app/ \
  --dart-define=API_BASE_URL=https://your-backend.example.com \
  --dart-define=WS_BASE_URL=wss://your-backend.example.com/ws

rm -rf ../web/public/app
cp -r build/web ../web/public/app
```

Until there is a public backend, the honest options are to leave the button
pointing at the APK only, or to say plainly on the page that the web build needs
a local server. Do not ship a button that silently fails.

## What is already handled

- `/app` and `/app/` both resolve to the Flutter app, and its own routes fall
  through to its `index.html`. This is a rewrite in `next.config.ts` using
  `afterFiles`, so every real asset under `/app/` is still served directly and
  only unmatched routes hit the fallback. Without it `/app` returns a 404, which
  is what it did before.
- Cache headers for `/app`, `/screens` and `/downloads`.
- 79 files and about 98 MB of static assets, which is comfortably inside
  Vercel's per-deployment limits once the APK moves out.

## Custom domain

Vercel → Project → Settings → Domains → add the domain and follow the DNS
records it gives you. Then patch the two commented-out lines in
`app/layout.tsx` (`openGraph.url` and `openGraph.images`) with the live URL,
because Open Graph needs absolute URLs and there is no way to know them before
the domain exists. They are marked with a `DEPLOY STEP` comment.

---

# Part 2: The Android release

## Two blockers in the current project

Both are in `frontend/android/app/build.gradle.kts`, and both must be fixed
before anything reaches Google Play. The APK on the site right now is fine for
sideloading and for testers, but it is not publishable as it stands.

### Blocker 1: the package name is a placeholder

```kotlin
applicationId = "com.example.robochess_mobile"
```

Google Play **rejects** any `com.example.*` package name. Pick a real one you
control and change it. It can never be changed again after the first Play
upload, so choose carefully:

```kotlin
applicationId = "com.rayyanshaikh.robochess"
```

You also need to rename the Kotlin package directories under
`android/app/src/main/kotlin/` to match, and update `namespace` in the same
file.

### Blocker 2: the release build is signed with the debug key

```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug")   // <- this
    }
}
```

That is Flutter's default placeholder. An app signed with the debug key cannot
go on Play, and anything you sideload now cannot be upgraded later by a properly
signed build. Fix it before you distribute anything you care about.

## Creating an upload key

```bash
keytool -genkey -v -keystore %USERPROFILE%\robochess-upload.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Keep that file and its passwords safe and out of git. Losing it means losing the
ability to update the app.

Then create `frontend/android/key.properties` (already ignored by Flutter's
default `.gitignore`, but check):

```properties
storePassword=<the password you just set>
keyPassword=<the password you just set>
keyAlias=upload
storeFile=C:/Users/Admin/robochess-upload.jks
```

And wire it into `frontend/android/app/build.gradle.kts`:

```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

## Building

Bump the version in `frontend/pubspec.yaml` first. The part before `+` is what
people see, the part after is the build number Play orders releases by, and it
must increase on every upload:

```yaml
version: 1.0.0+1
```

Then:

```bash
cd frontend

# for Google Play
flutter build appbundle --release

# for sideloading and GitHub Releases
flutter build apk --release
```

Outputs land in `build/app/outputs/bundle/release/app-release.aab` and
`build/app/outputs/flutter-apk/app-release.apk`.

Sanity check what you built before shipping it:

```bash
# should print your real package name, not com.example.*
%LOCALAPPDATA%\Android\Sdk\build-tools\<version>\aapt dump badging build\app\outputs\flutter-apk\app-release.apk | findstr package
```

## Route A: GitHub Release (fastest, no review)

```bash
cd frontend
cp build/app/outputs/flutter-apk/app-release.apk robochess-1.0.0.apk

gh release create v1.0.0 robochess-1.0.0.apk \
  --title "RoboChess 1.0.0" \
  --notes "First public build. Play the engine, solve puzzles, analyse a game, and pair a physical board over Bluetooth."
```

Copy the asset URL from the release page into `NEXT_PUBLIC_APK_URL` on Vercel.

People installing this way have to allow install from unknown sources, so put
one line next to the button saying so if you take this route long term.

## Route B: Google Play

1. Pay the one-off $25 and create a developer account at
   <https://play.google.com/console>.
2. **Create app**: name, default language, app or game, free or paid.
3. Fill in **App content**: privacy policy URL (required, and it must be a real
   reachable page), ads declaration, content rating questionnaire, target
   audience, data safety form. The data safety form asks what you collect;
   RoboChess stores an account and game history, so answer it honestly.
4. **Store listing**: short description, full description, an app icon at
   512x512, a feature graphic at 1024x500, and at least two phone screenshots.
   The six screenshots in `web/public/screens/` are already the right shape.
5. **Production → Create new release**, upload the `.aab`, write release notes.
6. Let Play sign the app (App Signing) when it offers. Your upload key stays the
   key you sign with, Play holds the distribution key.
7. Submit. First review usually takes a few days.

## A note on the Connect screenshot

`connect.jpeg` shows **"Failed to load boards."** on screen. It is honest, and
on the landing page it is small enough that most people will not read it, but it
is the kind of detail a reviewer or a careful visitor notices. Worth retaking
with the backend running before you use these same shots on a Play listing.
