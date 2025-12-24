#!/usr/bin/env node

// Test script for MCP request history endpoint
const http = require('http');
const https = require('https');

const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';
const API_KEY = process.argv[2];

if (!API_KEY) {
    console.log('Usage: node test-access-logs.js <API_KEY>');
    console.log('Example: node test-access-logs.js fletch_sk_abc123...');
    process.exit(1);
}

async function testAccessLogs() {
    console.log('Testing MCP Access Logs endpoint...\n');

    const url = new URL('/api/access-logs', BASE_URL);
    url.searchParams.append('limit', '10');
    url.searchParams.append('offset', '0');

    const options = {
        method: 'GET',
        headers: {
            'Authorization': `Bearer ${API_KEY}`,
            'Content-Type': 'application/json'
        }
    };

    const protocol = url.protocol === 'https:' ? https : http;

    return new Promise((resolve, reject) => {
        const req = protocol.request(url, options, (res) => {
            let data = '';

            res.on('data', chunk => data += chunk);

            res.on('end', () => {
                console.log(`Status: ${res.statusCode}`);
                console.log(`Headers:`, res.headers);

                if (res.statusCode === 200) {
                    try {
                        const json = JSON.parse(data);
                        console.log('\nSuccess! Response:');
                        console.log(JSON.stringify(json, null, 2));
                        resolve(json);
                    } catch (e) {
                        console.error('Failed to parse JSON:', e);
                        console.log('Raw response:', data);
                        reject(e);
                    }
                } else {
                    console.error(`\nError: ${res.statusCode}`);
                    console.log('Response:', data);
                    reject(new Error(`HTTP ${res.statusCode}`));
                }
            });
        });

        req.on('error', (e) => {
            console.error('Request failed:', e);
            reject(e);
        });

        req.end();
    });
}

testAccessLogs()
    .then(() => {
        console.log('\n✓ Test passed!');
        process.exit(0);
    })
    .catch((err) => {
        console.error('\n✗ Test failed:', err.message);
        process.exit(1);
    });
