# Quick Start Guide - 15 Minutes Setup

Follow these steps to get your Mushroom Chamber backend running in the cloud!

## Step 1: MongoDB Atlas (5 minutes)

1. **Sign up**: Go to https://www.mongodb.com/cloud/atlas/register
2. **Create Cluster**:
   - Click "Build a Database"
   - Choose **FREE** (M0 Sandbox)
   - Pick a region closest to you
   - Click "Create Cluster"
3. **Create User**:
   - Click "Database Access" (left menu)
   - Click "Add New Database User"
   - Username: `mushroomuser`
   - Password: Click "Autogenerate Secure Password" and **COPY IT!**
   - Click "Add User"
4. **Allow Access**:
   - Click "Network Access" (left menu)
   - Click "Add IP Address"
   - Click "Allow Access from Anywhere"
   - Click "Confirm"
5. **Get Connection String**:
   - Click "Database" (left menu)
   - Click "Connect" button
   - Click "Connect your application"
   - Copy the connection string
   - Replace `<password>` with your actual password
   - Add database name: change `...mongodb.net/` to `...mongodb.net/mushroom_chamber`
   - **SAVE THIS STRING!** You'll need it in Step 2

Example connection string:
```
mongodb+srv://mushroomuser:ABC123xyz@cluster0.xxxxx.mongodb.net/mushroom_chamber?retryWrites=true&w=majority
```

## Step 2: Deploy to Render (5 minutes)

### Option A: Deploy from GitHub (Recommended)

1. Push your code to GitHub:
   ```bash
   cd backend
   git init
   git add .
   git commit -m "Initial backend setup"
   git remote add origin YOUR-GITHUB-REPO-URL
   git push -u origin main
   ```

2. **Sign up**: Go to https://render.com and sign up (use GitHub login)
3. **Create Service**:
   - Click "New +" → "Web Service"
   - Connect your GitHub repository
   - Select your repository
4. **Configure**:
   - Name: `mushroom-chamber`
   - Environment: `Node`
   - Build Command: `npm install`
   - Start Command: `npm start`
   - Instance Type: **Free**
5. **Environment Variables** (Click "Advanced"):
   - Add variable:
     - Key: `MONGODB_URI`
     - Value: Paste your MongoDB connection string from Step 1
   - Add variable:
     - Key: `NODE_ENV`
     - Value: `production`
6. **Create Web Service** and wait (5-10 minutes)

### Option B: Deploy Manually

1. **Sign up**: Go to https://render.com
2. In your backend folder, create a Git repository:
   ```bash
   cd backend
   git init
   git add .
   git commit -m "Initial commit"
   ```
3. Follow Option A steps 3-6

## Step 3: Get Your Backend URL

After deployment completes:
- Your URL will be: `https://mushroom-chamber.onrender.com`
- Or: `https://YOUR-CHOSEN-NAME.onrender.com`
- **COPY THIS URL!**

Test it:
```bash
curl https://YOUR-APP.onrender.com/health
```

You should see:
```json
{"status":"ok","timestamp":"...","mongodb":"connected"}
```

## Step 4: Update ESP32 (2 minutes)

Open `arduino/mushroom_sensor_esp32/mushroom_sensor_esp32.ino`

Find this line (around line 16):
```cpp
const char* cloudBackendUrl = "https://mushroom-chamber.onrender.com/api/sensors";
```

Replace with YOUR Render URL:
```cpp
const char* cloudBackendUrl = "https://YOUR-APP-NAME.onrender.com/api/sensors";
```

**Upload to ESP32!**

## Step 5: Verify Everything Works (3 minutes)

### Check ESP32 Serial Monitor
You should see:
```
=== Uploading to Cloud ===
{"temperature":25.5,"humidity":85.0,...}
Cloud upload success! Response code: 201
```

### Check Backend Has Data
```bash
curl https://YOUR-APP.onrender.com/api/sensors/latest
```

Should return sensor data!

### Check Flutter App
Open your Flutter app - you should now see real sensor data! 🎉

## Troubleshooting

### ❌ ESP32 says "Cloud upload failed! Error code: -1"
- **Cause**: Backend is sleeping (Render free tier)
- **Solution**: Wait 30 seconds and try again. First request wakes it up.

### ❌ Flutter app shows "No data"
- **Cause**: Backend URL not updated or backend sleeping
- **Solution**: Check URL in `mushroom/lib/services/sensor_service.dart`

### ❌ MongoDB connection error in Render logs
- **Cause**: Wrong connection string or network access blocked
- **Solution**: Double-check:
  1. Connection string has correct password
  2. Database name is added: `...mongodb.net/mushroom_chamber?...`
  3. Network access allows `0.0.0.0/0`

### 🔥 Quick Test Command
```bash
# Test POST (should work from anywhere)
curl -X POST https://YOUR-APP.onrender.com/api/sensors \
  -H "Content-Type: application/json" \
  -d '{"temperature":25,"humidity":80,"soilMoisture":65,"co2Level":450,"lightIntensity":250}'

# Test GET (should return data)
curl https://YOUR-APP.onrender.com/api/sensors/latest
```

## What's Next?

✅ Your system is now fully operational!

**Data Flow:**
```
ESP32 → Cloud (Render) → MongoDB → Flutter App
```

**Monitoring:**
- Render logs: https://dashboard.render.com
- MongoDB data: https://cloud.mongodb.com

**Important Notes:**
- ⏰ Free tier sleeps after 15 min idle (first request wakes it)
- 💾 Free MongoDB: 512MB storage (enough for years of data)
- 🔄 ESP32 uploads every 5 minutes
- 📱 Flutter app shows real-time data

## Need Help?

- Check full README.md for detailed documentation
- View Render logs for backend errors
- Check ESP32 Serial Monitor for upload status
- Test endpoints with cURL commands above

Enjoy your cloud-connected mushroom monitoring system! 🍄
