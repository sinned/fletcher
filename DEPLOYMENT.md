# Deploying Fletcher Server to Render

This guide outlines how to deploy the Fletcher Server to Render.com.

## Prerequisites
- A GitHub repository with the server code in a `server/` directory (or root).
- A Render account (https://render.com).
- A PostgreSQL database (Render provides a managed Postgres).

## Step 1: Push Code to GitHub
Ensure all your changes are committed and pushed to your GitHub repository.

## Step 2: Create a Web Service on Render
1.  **New Web Service**: In Render Dashboard, click "New +" -> "Web Service".
2.  **Connect Repo**: Select your Fletcher repository.
3.  **Configure Service**:
    *   **Name**: `fletcher-server` (or similar)
    *   **Root Directory**: `server` (Important since our code is in a subdirectory)
    *   **Environment**: `Node`
    *   **Build Command**: `npm install && npm run build`
        *   *Note*: Our `build` script compiles TS to `dist/` and copies schema.
    *   **Start Command**: `npm start`
        *   *Note*: Runs `node dist/index.js`.

## Step 3: Create a Database
1.  **New PostgreSQL**: In Render Dashboard, click "New +" -> "PostgreSQL".
2.  **Name**: `fletcher-db`.
3.  **Region**: Same as Web Service (e.g., Oregon/Frankfurt).
4.  **Create**: Wait for it to become available.
5.  **Copy Internal URL**: Copy the `Internal Database URL` (starts with `postgres://...`).

## Step 4: Configure Environment Variables
Go to your Web Service -> **Environment**. Add the following:

| Key | Value | Description |
| :--- | :--- | :--- |
| `DATABASE_URL` | `postgres://...` | Paste the **Internal Database URL** from Step 3. |
| `NODE_ENV` | `production` | Required — enables HTTPS-only CORS and the production base URL. |
| `BASE_URL` | `https://fletcher.to` | Optional — base URL shown in MCP connection instructions. Falls back to `https://fletcher.to` when `NODE_ENV=production`. |
| `PORT` | `3000` | Render expects the app to listen on a port (usually defaults to 10000, but we can set specific one). Fastify listens on 0.0.0.0. |

## Step 5: Initialize Database
Fletcher Server v2.1 requires the database tables to be created.
Since we don't have an auto-migration script in `npm start` (to prevent accidental data loss), you need to run the schema manually once.

**Option A: Connect via External URL**
1.  Get the **External Database URL** from Render Postgres dashboard.
2.  Run locally: `psql "EXTERNAL_URL" -f src/db/schema.sql`

**Option B: Parse Schema in Shell (Advanced)**
Render Shell doesn't always have `psql`. Best to use Option A or a GUI like TablePlus.

## Step 6: Verify Deployment
1.  **Deploy**: Click "Manual Deploy" -> "Deploy latest commit" if not auto-started.
2.  **Wait**: Wait for "Live" status.
3.  **Test**: Visit `https://<your-app>.onrender.com/health` (should return `{"status":"ok"}`).

## Step 7: Update iOS App
1.  Copy your new server URL: `https://<your-app>.onrender.com`
2.  Open iOS App -> Settings -> Manage Connections.
3.  Update **Server URL**.
