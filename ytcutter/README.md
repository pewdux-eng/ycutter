# 🎵 YT Audio Cutter — Android App

Cut and compress YouTube audio clips, then share directly to WhatsApp.

---

## 📱 What it does
1. Paste a YouTube link
2. Enter start time (e.g. `29.25` or `29:25`)
3. Enter end time (e.g. `1.12.03` or `1:12:03`)
4. Tap **Download & Cut**
5. Tap **Share to WhatsApp**

Works anywhere in the world. No PC needed. All processing is on your phone.

---

## 🛠️ How to build the APK (one time only)

### Step 1 — Install Flutter
1. Go to https://docs.flutter.dev/get-started/install/windows/mobile
2. Download Flutter SDK and extract to `C:\flutter`
3. Add `C:\flutter\bin` to your Windows PATH
4. Open a new terminal and run: `flutter doctor`
5. Fix any issues it shows (mainly Android Studio)

### Step 2 — Install Android Studio
1. Download from https://developer.android.com/studio
2. Install it, open it, go through the setup wizard
3. In Android Studio: Tools → SDK Manager → install **Android SDK Platform 34**
4. In Android Studio: Tools → SDK Manager → SDK Tools tab → install **Android SDK Command-line Tools**

### Step 3 — Accept Android licenses
Open a terminal and run:
```
flutter doctor --android-licenses
```
Press `y` to accept everything.

### Step 4 — Build the APK
1. Copy the `ytcutter` folder to `C:\ytcutter`
2. Open a terminal in that folder:
   ```
   cd C:\ytcutter
   flutter pub get
   flutter build apk --release
   ```
3. Wait 5-10 minutes for first build
4. The APK will be at:
   ```
   C:\ytcutter\build\app\outputs\flutter-apk\app-release.apk
   ```

### Step 5 — Install on your phone
1. Copy `app-release.apk` to your phone (USB, Google Drive, email, etc.)
2. On your phone: Settings → Security → Enable **Install unknown apps**
3. Tap the APK file to install

---

## 📋 Requirements
- Windows PC (just for the one-time build)
- Android phone running Android 7.0 or newer
- Internet connection on the phone when using the app

---

## ❓ Troubleshooting

| Problem | Fix |
|---|---|
| `flutter: command not found` | Restart terminal after adding Flutter to PATH |
| `Android SDK not found` | Run `flutter doctor` and follow the instructions |
| APK won't install | Enable "Install unknown apps" in phone settings |
| "Could not get audio stream" | YouTube link may be restricted or try again |
| App crashes on open | Make sure phone is Android 7.0+ |

---

## 📁 Project structure
```
ytcutter/
├── lib/
│   └── main.dart        ← Entire app (UI + logic)
├── android/
│   └── app/
│       ├── build.gradle
│       └── src/main/AndroidManifest.xml
├── pubspec.yaml         ← Dependencies
└── README.md
```
