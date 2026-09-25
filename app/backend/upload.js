const { randomUUID } = require('crypto');
const { S3Client, PutObjectCommand } = require('@aws-sdk/client-s3');
const { getSignedUrl } = require('@aws-sdk/s3-request-presigner');
const { PutCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb, allowedTypes, outputTypes, response, clamp, safeName } = require('./common');

const s3 = new S3Client({});

exports.handler = async (event) => {
  try {
    const payload = JSON.parse(event.body || '{}');
    const { filename, contentType, format } = payload;
    const width = clamp(payload.width, 32, 4000);
    const height = clamp(payload.height, 32, 4000);
    const quality = clamp(payload.quality || 85, 50, 100);
    if (!allowedTypes.has(contentType) || !outputTypes[format] || !Number.isFinite(width) || !Number.isFinite(height)) {
      return response(400, { message: 'Use a JPEG, PNG, or WebP image and dimensions from 32 to 4000 pixels.' });
    }
    const jobId = randomUUID();
    const key = `uploads/${jobId}/${safeName(filename)}`;
    const now = Math.floor(Date.now() / 1000);
    await ddb.send(new PutCommand({ TableName: process.env.JOBS_TABLE, Item: { id: jobId, status: 'waiting', inputKey: key, originalName: safeName(filename), contentType, format, width, height, quality, createdAt: now, expiresAt: now + 86400 } }));
    const uploadUrl = await getSignedUrl(s3, new PutObjectCommand({ Bucket: process.env.RAW_BUCKET, Key: key, ContentType: contentType }), { expiresIn: 300 });
    return response(201, { jobId, uploadUrl });
  } catch (error) {
    console.error('Create upload job failed', error);
    return response(500, { message: 'Unable to create an upload job.' });
  }
};
