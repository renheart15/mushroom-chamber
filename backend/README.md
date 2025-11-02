# Mushroom Chamber Backend API

Cloud backend service for the Mushroom Chamber IoT monitoring system. Built with Node.js, Express, and MongoDB.

## Features

- RESTful API for sensor data and actuator control
- Real-time WebSocket updates
- MongoDB data persistence
- Rate limiting and security with Helmet
- Automatic data retention management

## Prerequisites

- Node.js 18+
- MongoDB Atlas account (free tier works fine)
- Render account (for deployment)

## Setup Instructions

### 1. MongoDB Atlas Setup

1. Go to [MongoDB Atlas](https://www.mongodb.com/cloud/atlas/register)
2. Create a free account and sign in
3. Create a new cluster:
   - Choose **FREE** tier (M0 Sandbox)
   - Select a cloud provider and region (choose nearest to your location)
   - Name your cluster (e.g., "mushroom-cluster")
   - Click **Create Cluster** (takes 3-5 minutes)

4. Create a Database User:
   - Go to **Database Access** (left sidebar)
   - Click **Add New Database User**
   - Choose **Password** authentication
   - Username: `mushroomuser` (or any name you want)
   - Password: Generate a strong password and **save it**
   - Database User Privileges: **Read and write to any database**
   - Click **Add User**

5. Configure Network Access:
   - Go to **Network Access** (left sidebar)
   - Click **Add IP Address**
   - Click **Allow Access from Anywhere** (or add `0.0.0.0/0`)
   - Click **Confirm**

6. Get Connection String:
   - Go to **Database** (left sidebar)
   - Click **Connect** on your cluster
   - Choose **Connect your application**
   - Select **Driver: Node.js** and **Version: 5.5 or later**
   - Copy the connection string (looks like):
     ```
     mongodb+srv://mushroomuser:<password>@cluster.xxxxx.mongodb.net/?retryWrites=true&w=majority
     ```
   - Replace `<password>` with your actual database user password
   - Add database name after `.net/`: change to `...mongodb.net/mushroom_chamber?retryWrites...`

### 2. Deploy to Render

1. Go to [Render](https://render.com/) and sign up/login
2. Click **New +** → **Web Service**
3. Connect your GitHub repository (or upload code)
4. Configure the service:
   - **Name**: `mushroom-chamber` (or any name)
   - **Environment**: `Node`
   - **Build Command**: `npm install`
   - **Start Command**: `npm start`
   - **Plan**: Choose **Free**

5. Add Environment Variables:
   - Click **Advanced** → **Add Environment Variable**
   - Add these variables:
     ```
     MONGODB_URI = mongodb+srv://mushroomuser:yourpassword@cluster.xxxxx.mongodb.net/mushroom_chamber?retryWrites=true&w=majority
     PORT = 3000
     NODE_ENV = production
     ```
   - Replace the `MONGODB_URI` with your actual MongoDB connection string

6. Click **Create Web Service**
7. Wait for deployment (5-10 minutes)
8. Your backend URL will be: `https://mushroom-chamber.onrender.com` (or whatever name you chose)

### 3. Update ESP32 Code

In your Arduino code (`mushroom_sensor_esp32.ino`), update the backend URL:

```cpp
const char* cloudBackendUrl = "https://YOUR-RENDER-APP-NAME.onrender.com/api/sensors";
```

Replace `YOUR-RENDER-APP-NAME` with your actual Render app name.

### 4. Update Flutter App (Already Done!)

Your Flutter app is already configured to use:
```dart
static const String defaultBaseUrl = 'https://mushroom-chamber.onrender.com';
```

If you used a different name in Render, update this in:
`mushroom/lib/services/sensor_service.dart`

## Local Development

### Install Dependencies
```bash
cd backend
npm install
```

### Create .env File
```bash
cp .env.example .env
```

Edit `.env` and add your MongoDB connection string:
```
MONGODB_URI=mongodb+srv://your-connection-string-here
PORT=3000
NODE_ENV=development
```

### Run Development Server
```bash
npm run dev
```

Server will run at `http://localhost:3000`

### Run Production Server
```bash
npm start
```

## API Endpoints

### Sensor Endpoints
- `POST /api/sensors` - Create new sensor reading (ESP32 → Cloud)
- `GET /api/sensors/latest` - Get latest sensor reading (Flutter App)
- `GET /api/sensors` - Get sensor history with filters
- `GET /api/sensors/statistics` - Get sensor statistics
- `DELETE /api/sensors/old` - Clean old readings

### Actuator Endpoints
- `POST /api/actuators` - Control actuator
- `GET /api/actuators/states` - Get current states
- `GET /api/actuators/history` - Get actuator history

### System Endpoints
- `GET /api/system/status` - System status
- `GET /api/system/dashboard` - Dashboard data
- `POST /api/system/calibrate` - Sensor calibration

### Health Check
- `GET /health` - Check server health

## Testing the Backend

### Test with cURL (after deployment)
```bash
# Get latest sensor reading
curl https://YOUR-APP.onrender.com/api/sensors/latest

# Check health
curl https://YOUR-APP.onrender.com/health

# Post sensor data (test)
curl -X POST https://YOUR-APP.onrender.com/api/sensors \
  -H "Content-Type: application/json" \
  -d '{
    "temperature": 25.5,
    "humidity": 85.0,
    "soilMoisture": 65.0,
    "co2Level": 450,
    "lightIntensity": 250
  }'
```

## Monitoring

### Render Dashboard
- View logs in Render dashboard
- Monitor service health
- Check resource usage

### MongoDB Atlas
- View data in Collections
- Monitor database metrics
- Set up alerts

## Important Notes

⚠️ **Free Tier Limitations:**
- Render free tier: Service sleeps after 15 minutes of inactivity (first request may be slow)
- MongoDB Atlas free tier: 512MB storage (plenty for sensor data)
- First ESP32 upload after sleep may timeout - that's normal, next one will work

🔧 **Production Tips:**
- Enable MongoDB indexes for better performance (already configured)
- Set up data retention (auto-delete old readings)
- Monitor Render logs for errors
- Consider upgrading to paid tier for 24/7 uptime

🔒 **Security:**
- Never commit `.env` file to Git
- Use strong MongoDB passwords
- Enable network restrictions in MongoDB Atlas for production

## Troubleshooting

### ESP32 Can't Upload Data
1. Check WiFi connection
2. Verify backend URL in Arduino code
3. Check Render service is running (not sleeping)
4. View Serial Monitor for error messages

### Flutter App Shows No Data
1. Check backend URL in `sensor_service.dart`
2. Verify backend is deployed and running
3. Test backend endpoints with cURL
4. Check MongoDB has data

### MongoDB Connection Failed
1. Verify connection string in Render environment variables
2. Check database user credentials
3. Confirm network access allows `0.0.0.0/0`
4. Check MongoDB Atlas cluster is running

## Data Flow

```
ESP32 Sensors → WiFi → Cloud Backend (Render) → MongoDB Atlas
                             ↓
                      Flutter App (reads data)
```

## License

MIT

## Support

For issues or questions, create an issue in the GitHub repository.
