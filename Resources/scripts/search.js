#!/usr/bin/env node

/**
 * Zvec Legal Knowledge - 搜索脚本
 *
 * 功能：接收查询文本，生成 Query Embedding，在 Zvec Collection 中搜索相似文档
 *
 * 用法：
 *   node search.js --kb-path <路径> --query <文本> --topk <数量> --api-key <Key> --base-url <URL> --model <模型>
 */

const { ZVecOpen } = require('@zvec/zvec');
const fs = require('fs');

// 命令行参数解析
const args = process.argv.slice(2);
const params = {};
for (let i = 0; i < args.length; i += 2) {
    if (args[i].startsWith('--')) {
        params[args[i].slice(2)] = args[i + 1];
    }
}

// 验证必需参数
const requiredParams = ['kb-path', 'api-key', 'base-url', 'model', 'dimension'];
for (const param of requiredParams) {
    if (!params[param]) {
        console.error(JSON.stringify({ success: false, error: `Missing required parameter: --${param}` }));
        process.exit(1);
    }
}
if (!params.query && !params['query-file']) {
    console.error(JSON.stringify({ success: false, error: 'Missing required parameter: --query or --query-file' }));
    process.exit(1);
}

const kbPath = params['kb-path'];
let queryText;
if (params['query-file']) {
    queryText = fs.readFileSync(params['query-file'], 'utf-8').trim();
} else {
    queryText = params.query;
}
const topk = parseInt(params.topk || '10', 10);
const dimension = parseInt(params.dimension || '1024', 10);
const apiKey = params['api-key'];
const baseUrl = params['base-url'];
const model = params.model;

const EMBEDDING_FIELD = 'embedding';

/**
 * 调用 SiliconFlow API 生成单个文本的 Embedding
 * @param {string} text - 输入文本
 * @returns {Promise<number[]>} - Embedding 向量
 */
async function generateQueryEmbedding(text) {
    const body = {
        model: model,
        input: text,
        encoding_format: 'float'
    };
    if (model.startsWith('Qwen/Qwen3-Embedding')) {
        body.dimensions = dimension;
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
    return result.data[0].embedding;
}

/**
 * 执行向量搜索
 */
async function search() {
    const result = {
        success: false,
        query: queryText,
        results: []
    };

    try {
        // 生成查询向量
        const queryVector = await generateQueryEmbedding(queryText);

        // 打开 Collection
        const collection = ZVecOpen(kbPath);

        // 执行向量搜索
        const searchResults = collection.querySync({
            fieldName: EMBEDDING_FIELD,
            vector: queryVector,
            topk: topk,
            outputFields: ['text', 'doc_type', 'source', 'title']
        });

        // 格式化结果
        result.results = searchResults.map(doc => ({
            id: doc.id,
            text: doc.fields.text,
            doc_type: doc.fields.doc_type,
            source: doc.fields.source,
            title: doc.fields.title,
            score: doc.score
        }));

        result.success = true;

        collection.closeSync();

    } catch (err) {
        result.error = err.message;
    }

    console.log(JSON.stringify(result, null, 2));
}

search().catch(err => {
    console.error(JSON.stringify({ success: false, error: err.message }));
    process.exit(1);
});
