#!/usr/bin/env node

const { ZVecCreateAndOpen, ZVecOpen, ZVecCollectionSchema, ZVecDataType, ZVecIndexType, ZVecMetricType } = require('@zvec/zvec');
const fs = require('fs');

const args = process.argv.slice(2);
const params = {};
for (let i = 0; i < args.length; i += 2) {
    if (args[i].startsWith('--')) {
        params[args[i].slice(2)] = args[i + 1];
    }
}

const requiredParams = ['kb-path', 'docs-file', 'api-key', 'base-url', 'model'];
for (const param of requiredParams) {
    if (!params[param]) {
        console.error(JSON.stringify({ success: false, error: `Missing required parameter: --${param}` }));
        process.exit(1);
    }
}

const kbPath = params['kb-path'];
const docsFilePath = params['docs-file'];
const apiKey = params['api-key'];
const baseUrl = params['base-url'];
const model = params.model;

let docs;
try {
    docs = JSON.parse(fs.readFileSync(docsFilePath, 'utf-8'));
} catch (err) {
    console.error(JSON.stringify({ success: false, error: `Failed to read docs file: ${err.message}` }));
    process.exit(1);
}

const KB_SCHEMA_NAME = 'legal_kb';
const EMBEDDING_FIELD = 'embedding';
const BATCH_SIZE = 32;

let detectedDimension = null;

async function generateEmbeddings(texts) {
    const body = {
        model: model,
        input: texts,
        encoding_format: 'float'
    };
    if (model.startsWith('Qwen/Qwen3-Embedding')) {
        body.dimensions = detectedDimension || 1024;
    }

    const response = await fetch(`${baseUrl}/embeddings`, {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${apiKey}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify(body)
    });

    if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`API Error ${response.status}: ${errorText}`);
    }

    const result = await response.json();
    const embeddings = result.data.map(item => item.embedding);

    if (detectedDimension === null && embeddings.length > 0) {
        detectedDimension = embeddings[0].length;
    }

    return embeddings;
}

async function importDocuments() {
    const result = {
        success: true,
        imported: 0,
        failed: 0,
        dimension: null,
        documents: []
    };

    try {
        const docsByTitle = {};
        for (const doc of docs) {
            const title = doc.title || doc.source || 'unknown';
            if (!docsByTitle[title]) {
                docsByTitle[title] = [];
            }
            docsByTitle[title].push(doc);
        }

        let collection;
        let needCreate = true;

        try {
            collection = ZVecOpen(kbPath);
            needCreate = false;
        } catch {}

        let isFirstBatch = true;

        for (const [title, chunks] of Object.entries(docsByTitle)) {
            try {
                const texts = chunks.map(c => c.text);

                const allEmbeddings = [];
                for (let i = 0; i < texts.length; i += BATCH_SIZE) {
                    const batch = texts.slice(i, i + BATCH_SIZE);
                    const embeddings = await generateEmbeddings(batch);
                    allEmbeddings.push(...embeddings);
                }

                if (isFirstBatch && needCreate) {
                    const dimension = detectedDimension;
                    result.dimension = dimension;

                    const schema = new ZVecCollectionSchema({
                        name: KB_SCHEMA_NAME,
                        vectors: {
                            name: EMBEDDING_FIELD,
                            dataType: ZVecDataType.VECTOR_FP32,
                            dimension: dimension,
                            indexParams: {
                                indexType: ZVecIndexType.HNSW,
                                metricType: ZVecMetricType.COSINE,
                                m: 16,
                                efConstruction: 200
                            }
                        },
                        fields: [
                            { name: 'text', dataType: ZVecDataType.STRING },
                            { name: 'doc_type', dataType: ZVecDataType.STRING },
                            { name: 'source', dataType: ZVecDataType.STRING },
                            { name: 'title', dataType: ZVecDataType.STRING }
                        ]
                    });

                    collection = ZVecCreateAndOpen(kbPath, schema);
                    needCreate = false;
                }

                isFirstBatch = false;

                const zvecDocs = chunks.map((chunk, idx) => ({
                    id: chunk.id,
                    vectors: { [EMBEDDING_FIELD]: allEmbeddings[idx] },
                    fields: {
                        text: chunk.text,
                        doc_type: chunk.type,
                        source: chunk.source,
                        title: title
                    }
                }));

                const INSERT_BATCH_SIZE = 32;
                for (let i = 0; i < zvecDocs.length; i += INSERT_BATCH_SIZE) {
                    const batch = zvecDocs.slice(i, i + INSERT_BATCH_SIZE);
                    collection.insertSync(batch);
                }

                result.imported += chunks.length;
                result.documents.push({
                    title: title,
                    chunks: chunks.length,
                    status: 'success'
                });
            } catch (err) {
                result.failed += chunks.length;
                result.documents.push({
                    title: title,
                    chunks: chunks.length,
                    status: 'failed',
                    error: err.message
                });
            }
        }

        if (collection) {
            collection.closeSync();
        }
        result.dimension = detectedDimension;
        result.success = true;

    } catch (err) {
        result.success = false;
        result.error = err.message;
    }

    console.log(JSON.stringify(result, null, 2));
}

importDocuments().catch(err => {
    console.error(JSON.stringify({ success: false, error: err.message }));
    process.exit(1);
});
