import {
    saveLocations,
    getLocationHistory,
    getLocationHistoryWithRadius,
    getFrequentLocations,
    getRecentTrajectory,
    getTotalLocationCount
} from './src/models/location';
import { query } from './src/db';

const USER_ID = '11111111-1111-1111-1111-111111111111';

// Helpers
const log = (msg: string) => console.log(`[TEST] ${msg}`);

async function run() {
    try {
        log('Starting Verification...');

        // 1. Setup Data
        const centerLat = 37.33182;
        const centerLon = -121.8900;

        // Approx 0.00045 deg is ~50m
        const nearbyLat = centerLat + 0.00045;
        const farLat = centerLat + 0.1; // ~11km away

        const now = new Date();
        const yesterday = new Date(now.getTime() - 24 * 60 * 60 * 1000);

        const testLocations = [
            {
                latitude: centerLat,
                longitude: centerLon,
                accuracy: 5,
                timestamp: now
            },
            {
                latitude: nearbyLat, // ~50m North
                longitude: centerLon,
                accuracy: 10,
                timestamp: new Date(now.getTime() - 1000 * 60) // 1 min ago
            },
            {
                latitude: farLat, // Far away
                longitude: centerLon,
                accuracy: 20,
                timestamp: new Date(now.getTime() - 1000 * 60 * 60) // 1 hour ago
            },
            {
                latitude: centerLat, // Repeat visit
                longitude: centerLon,
                accuracy: 5,
                timestamp: yesterday
            }
        ];

        log('Ensuring Test User...');
        // Create user if not exists
        await query(`INSERT INTO users (id, api_key, created_at) VALUES ($1, 'test_key', NOW()) ON CONFLICT (id) DO NOTHING`, [USER_ID]);

        log('Seeding data...');
        await saveLocations(USER_ID, testLocations);
        log('Data seeded.');

        // 2. Test Pagination
        log('Testing Pagination...');
        const allLocs = await getLocationHistory(USER_ID, { limit: 100 });
        const p1 = await getLocationHistory(USER_ID, { limit: 1, offset: 0 });
        const p2 = await getLocationHistory(USER_ID, { limit: 1, offset: 1 });

        console.log(`Total fetched: ${allLocs.length}`);
        if (p1.length === 1 && p2.length === 1 && p1[0].timestamp !== p2[0].timestamp) {
            log('PASS: Pagination works (distinct records returned)');
        } else {
            console.error('FAIL: Pagination issue', { p1, p2 });
        }

        // 3. Test Radius
        log('Testing Radius Filter...');
        // Radius 100m should include center and nearby, exclude far
        const radiusPoints = await getLocationHistoryWithRadius(USER_ID, centerLat, centerLon, 100, { limit: 100 });

        // Use a time filter to verify our specific seeded points clearer if DB is noisy, but here we check existence.

        const recentRadius = await getLocationHistoryWithRadius(USER_ID, centerLat, centerLon, 100, { start: yesterday });
        // Should have 3 points: center(now), nearby(now-1m), center(yesterday)
        // Far point (now-1h) is far.

        // Check if far point is present (should not be)
        const hasFar = recentRadius.find((l: any) => Math.abs(l.latitude - farLat) < 0.0001);

        if (!hasFar && recentRadius.length >= 3) {
            log(`PASS: Radius filter returned ${recentRadius.length} points, excluded far point.`);
        } else {
            console.error('FAIL: Radius filter included far point or missed points. Count:', recentRadius.length);
            // Log latitudes for debug
            console.log('Latitudes returned:', recentRadius.map((l: any) => l.latitude));
            console.log('Target Far Lat:', farLat);
        }

        // 4. Test Trajectory
        log('Testing Recent Trajectory...');
        const traj = await getRecentTrajectory(USER_ID, 2);
        // Should be last 2 points chronologically (oldest to newest among the limit set).

        if (traj.length === 2 && new Date(traj[1].timestamp).getTime() >= new Date(traj[0].timestamp).getTime()) {
            log('PASS: Trajectory returns chronological order.');
        } else {
            console.error('FAIL: Trajectory order or count', traj);
        }

        // 5. Test Frequent Locations
        log('Testing Frequent Locations...');
        const freq = await getFrequentLocations(USER_ID, 5, 2); // 2 days lookback

        console.log('Top Frequent Locations:', freq.map((f: any) => ({ lat: f.latitude, lon: f.longitude, count: f.visit_count })));
        if (freq.length > 0 && parseInt(freq[0].visit_count) >= 1) {
            log('PASS: Frequent locations returned clusters.');
        } else {
            console.error('FAIL: No frequent locations found.');
        }

        log('VERIFICATION COMPLETE');
        process.exit(0);

    } catch (err) {
        console.error('Verification Failed:', err);
        process.exit(1);
    }
}

run();
