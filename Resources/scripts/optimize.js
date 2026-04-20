#!/usr/bin/env node

const { ZVecOpen } = require('@zvec/zvec');

const args = process.argv.slice(2);
const params = {};
for (let i = 0; i < args.length; i += 2) {
    if (args[i].startsWith('--')) {
        params[args[i].slice(2)] = args[i + 1];
    }
}

if (!params['kb-path']) {
    console.error(JSON.stringify({ success: false, error: 'Missing required parameter: --kb-path' }));
    process.exit(1);
}

const kbPath = params['kb-path'];

try {
    const collection = ZVecOpen(kbPath);
    collection.optimizeSync();
    collection.closeSync();
    console.log(JSON.stringify({ success: true }));
} catch (err) {
    console.error(JSON.stringify({ success: false, error: err.message }));
    process.exit(1);
}
