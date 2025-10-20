# Mushroom Monitoring System - Deployment Guide

This guide will walk you through deploying the backend to Render and building the mobile app.

## Architecture Overview

```
Mobile App (Flutter)
       ↓
Backend API (Node.js/Express on Render)
       ↓
MongoDB Atlas (Database)
       ↑
ESP32 Sensors → Backend API
```

## Part 1: Deploy Backend to Render

### Prerequisites
- GitHub account
- Render account (free tier available at https://render.com)

### Step 1: Prepare Git Repository

1. Initialize git if not already done:
```bash
git init
git add .
git commit -m "Initial commit with backend"
```

2. Create a GitHub repository and push:
```bash
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git branch -M main
git push -u origin main
```

### Step 2: Deploy to Render

#### Option A: Using Render Dashboard (Recommended)

1. Go to https://render.com and sign in
2. Click **"New"** → **"Web Service"**
3. Connect your GitHub account and select your repository
4. Configure the service:
   - **Name**: `mushroom-monitoring-api` (or your preferred name)
   - **Environment**: `Node`
   - **Region**: Choose closest to your location
   - **Branch**: `main`
   - **Root Directory**: `backend`
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Instance Type**: `Free`

5. Add Environment Variables:
   Click **"Advanced"** → **"Add Environment Variable"**
   - **MONGODB_URI**: `mongodb+srv://ralfanta0112_db_user:mushroom123@cluster0.3pbqkyk.mongodb.net/mushroom_monitoring?retryWrites=true&w=majority`
   - **NODE_ENV**: `production`

6. Click **"Create Web Service"**

7. Wait for deployment (5-10 minutes). You'll see build logs.

8. Once deployed, you'll get a URL like: `https://mushroom-monitoring-api.onrender.com`

#### Option B: Using render.yaml (Infrastructure as Code)

1. The `backend/render.yaml` file is already configured
2. Go to Render Dashboard → **"New"** → **"Blueprint"**
3. Connect your repository
4. Render will auto-detect the `render.yaml`
5. Add the `MONGODB_URI` environment variable in the dashboard
6. Click **"Apply"**

### Step 3: Verify Backend Deployment

Test the API endpoints:

```bash
# Health check
curl https://your-app-name.onrender.com/api/health

# Get sensor data
curl https://your-app-name.onrender.com/api/sensors/latest

# System status
curl https://your-app-name.onrender.com/api/system/status
```

You should receive JSON responses.

### Step 4: Update Flutter App Configuration

1. Open `lib/config/api_config.dart`

2. Update the URLs with your Render deployment URL:
```dart
static const String baseUrl = 'https://your-app-name.onrender.com';
static const String wsUrl = 'wss://your-app-name.onrender.com';
```

3. Save the file

## Part 2: Build Mobile App

### Prerequisites
- Flutter SDK installed (https://flutter.dev/docs/get-started/install)
- Android Studio (for Android) or Xcode (for iOS)

### Step 1: Update Dependencies

```bash
cd mushroom
flutter pub get
```

### Step 2: Build for Android

#### Debug Build (Testing)
```bash
flutter build apk --debug
```

The APK will be at: `build/app/outputs/flutter-apk/app-debug.apk`

Transfer to your Android device and install.

#### Release Build (Production)

1. Generate a signing key:
```bash
keytool -genkey -v -keystore mushroom-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias mushroom
```

2. Create `android/key.properties`:
```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=mushroom
storeFile=../mushroom-key.jks
```

3. Update `android/app/build.gradle` (add before `android {`):
```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

4. Update the `buildTypes` section:
```gradle
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
        storePassword keystoreProperties['storePassword']
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
    }
}
```

5. Build the release APK:
```bash
flutter build apk --release
```

The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

#### Build App Bundle (for Google Play Store)
```bash
flutter build appbundle --release
```

The bundle will be at: `build/app/outputs/bundle/release/app-release.aab`

### Step 3: Build for iOS

**Note**: Requires a Mac with Xcode installed

1. Open the iOS project:
```bash
open ios/Runner.xcworkspace
```

2. In Xcode:
   - Select your development team
   - Configure bundle identifier
   - Update version and build number

3. Build for testing:
```bash
flutter build ios --debug
```

4. Build for release:
```bash
flutter build ios --release
```

5. Archive and upload via Xcode for App Store submission

### Step 4: Testing the Mobile App

1. Install the debug APK on your Android device
2. Open the app
3. The app should connect to your backend API
4. Check sensor data is loading
5. Test actuator controls

## Part 3: Configure ESP32 to Use Backend

Your ESP32 firmware needs to send data to the backend:

### ESP32 Configuration

```cpp
// Update your ESP32 code to use the Render URL
const char* serverUrl = "https://your-app-name.onrender.com";

// POST sensor data
void sendSensorData() {
  HTTPClient http;
  http.begin(String(serverUrl) + "/api/sensors");
  http.addHeader("Content-Type", "application/json");

  String payload = "{";
  payload += "\"temperature\":" + String(temperature) + ",";
  payload += "\"humidity\":" + String(humidity) + ",";
  payload += "\"co2\":" + String(co2) + ",";
  payload += "\"light\":" + String(light) + ",";
  payload += "\"soilMoisture\":" + String(soilMoisture);
  payload += "}";

  int httpCode = http.POST(payload);
  http.end();
}

// Poll for actuator commands
void checkCommands() {
  HTTPClient http;
  http.begin(String(serverUrl) + "/api/actuators/pending");
  int httpCode = http.GET();

  if (httpCode == 200) {
    String response = http.getString();
    // Parse and execute commands
  }
  http.end();
}
```

## Troubleshooting

### Backend Issues

**Render free tier sleeps after 15 minutes of inactivity:**
- First request after sleep will be slow (cold start)
- Consider upgrading to paid tier for always-on service
- Or implement a keep-alive ping from the mobile app

**MongoDB connection issues:**
- Verify MONGODB_URI is correct in Render environment variables
- Check MongoDB Atlas allows connections from anywhere (0.0.0.0/0)
- Or whitelist Render's IP addresses

### Mobile App Issues

**Cannot connect to backend:**
- Verify `api_config.dart` has correct URL
- Check your device has internet connection
- Ensure backend is deployed and running

**WebSocket not connecting:**
- Free tier Render may have WebSocket limitations
- HTTP fallback will still work (polling)
- Consider upgrading for better WebSocket support

## Publishing Apps

### Google Play Store
1. Create a Google Play Developer account ($25 one-time fee)
2. Build app bundle: `flutter build appbundle --release`
3. Upload to Play Console
4. Fill in store listing details
5. Submit for review

### Apple App Store
1. Create Apple Developer account ($99/year)
2. Build in Xcode
3. Archive and validate
4. Upload to App Store Connect
5. Fill in app information
6. Submit for review

## Security Recommendations

**Before going to production:**

1. **Change MongoDB credentials**
   - Create a new MongoDB user with a strong password
   - Update MONGODB_URI in Render

2. **Add API authentication**
   - Implement JWT or API keys
   - Add authentication middleware

3. **Enable HTTPS only**
   - Render provides free SSL
   - Disable HTTP endpoints

4. **Add rate limiting**
   - Already included in backend
   - Configure limits in `server.js`

5. **Environment variables**
   - Never commit `.env` file
   - Use Render's environment variable feature

## Monitoring

### Render Dashboard
- View logs in real-time
- Monitor CPU/memory usage
- Check deploy history

### MongoDB Atlas
- Monitor database operations
- View connection statistics
- Set up alerts

## Next Steps

- [ ] Deploy backend to Render
- [ ] Test backend API endpoints
- [ ] Update Flutter app with backend URL
- [ ] Build and test mobile app
- [ ] Configure ESP32 to use backend
- [ ] Test end-to-end system
- [ ] Publish to app stores (optional)

## Support

For issues:
- Backend: Check Render logs
- Mobile: Use `flutter doctor` to check setup
- General: Review this guide

## Cost Summary

| Service | Tier | Cost |
|---------|------|------|
| Render (Backend) | Free | $0/month (with limitations) |
| MongoDB Atlas | Free | $0/month (512MB storage) |
| Google Play Developer | One-time | $25 |
| Apple Developer | Annual | $99/year |

**Free tier limitations:**
- Render: Sleeps after 15 min inactivity, 750 hrs/month
- MongoDB: 512MB storage, shared clusters

Upgrade when you need:
- Always-on backend
- More storage
- Better performance
