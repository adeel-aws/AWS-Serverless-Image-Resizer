const { S3Client, GetObjectCommand, PutObjectCommand } = require('@aws-sdk/client-s3');
const { GetCommand, UpdateCommand } = require('@aws-sdk/lib-dynamodb');
const Jimp = require('jimp');
const { ddb, outputTypes } = require('./common');

const s3 = new S3Client({});
const streamToBuffer = async (stream) => Buffer.concat(await stream.toArray());

exports.handler = async (event) => {
  for (const record of event.Records || []) {
    const key = decodeURIComponent(record.s3.object.key.replace(/\+/g, ' '));
    const jobId = key.split('/')[1];
    try {
      const jobResult = await ddb.send(new GetCommand({ TableName: process.env.JOBS_TABLE, Key: { id: jobId } }));
      const job = jobResult.Item;
      if (!job) throw new Error(`No job found for ${jobId}`);
      await ddb.send(new UpdateCommand({ TableName: process.env.JOBS_TABLE, Key: { id: jobId }, UpdateExpression: 'SET #status = :status', ExpressionAttributeNames: { '#status': 'processing' }, ExpressionAttributeValues: { ':status': 'processing' } }));
      const source = await s3.send(new GetObjectCommand({ Bucket: process.env.RAW_BUCKET, Key: key }));
      const image = await Jimp.read(await streamToBuffer(source.Body));
      image.resize(job.width, job.height).quality(job.quality);
      const mime = outputTypes[job.format];
      const outputKey = `downloads/${jobId}.${job.format}`;
      await s3.send(new PutObjectCommand({ Bucket: process.env.PROCESSED_BUCKET, Key: outputKey, Body: await image.getBufferAsync(mime), ContentType: mime, CacheControl: 'public, max-age=86400' }));
      await ddb.send(new UpdateCommand({ TableName: process.env.JOBS_TABLE, Key: { id: jobId }, UpdateExpression: 'SET #status = :status, outputKey = :outputKey', ExpressionAttributeNames: { '#status': 'status' }, ExpressionAttributeValues: { ':status': 'complete', ':outputKey': outputKey } }));
    } catch (error) {
      console.error('Resize failed', { key, error });
      if (jobId) await ddb.send(new UpdateCommand({ TableName: process.env.JOBS_TABLE, Key: { id: jobId }, UpdateExpression: 'SET #status = :status, #error = :error', ExpressionAttributeNames: { '#status': 'status', '#error': 'error' }, ExpressionAttributeValues: { ':status': 'failed', ':error': 'Image processing failed.' } })).catch(() => {});
    }
  }
};
