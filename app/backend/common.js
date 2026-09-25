const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient } = require('@aws-sdk/lib-dynamodb');

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const allowedTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);
const outputTypes = { jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

function response(statusCode, body) {
  return { statusCode, headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET,POST,OPTIONS' }, body: JSON.stringify(body) };
}

function clamp(value, min, max) { return Math.max(min, Math.min(max, Number(value))); }
function safeName(name) { return String(name || 'image').replace(/[^a-zA-Z0-9._-]/g, '-').slice(0, 100); }

module.exports = { ddb, allowedTypes, outputTypes, response, clamp, safeName };
