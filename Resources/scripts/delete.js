#!/usr/bin/env node

const { ZVecOpen } = require('@zvec/zvec');
const fs = require('fs');

const args = process.argv.slice(2);
const params = {};
for (let i = 0; i < args.length; i += 2) {
    if (args[i].startsWith('--')) {
        params[args[i].slice(2)] = args[i + 1];
    }
}

const { 'kb-path': kbPath, 'ids-file': idsFile } = params;

if (!kbPath || !idsFile) {
    console.error(JSON.stringify({ success: false, error: 'Missing required parameters: --kb-path and --ids-file' }));
    process.exit(1);
}

let ids;
try {
    ids = JSON.parse(fs.readFileSync(idsFile, 'utf-8'));
} catch (err) {
    console.error(JSON.stringify({ success: false, error: `Failed to read ids file: ${err.message}` }));
    process.exit(1);
}

try {
    const collection = ZVecOpen(kbPath);
    let deletedCount = 0;

    for (const id of ids) {
        try {
            collection.deleteSync(id);
            deletedCount += 1;
        } catch (err) {
            console.error(`Failed to delete id ${id}: ${err.message}`);
        }
    }

    collection.closeSync();

    console.log(JSON.stringify({ success: true, deleted: deletedCount, total: ids.length }));
} catch (err) {
    console.error(JSON.stringify({ success: false, error: err.message }));
    process.exit(1);
}
