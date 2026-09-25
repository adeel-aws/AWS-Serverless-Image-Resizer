const { GetCommand } = require('@aws-sdk/lib-dynamodb');
const { ddb, response } = require('./common');

exports.handler = async (event) => {
  const id = event.pathParameters?.id;
  if (!id) return response(400, { message: 'A job id is required.' });
  try {
    const result = await ddb.send(new GetCommand({ TableName: process.env.JOBS_TABLE, Key: { id } }));
    if (!result.Item) return response(404, { message: 'Job not found.' });
    const job = result.Item;
    return response(200, { id: job.id, status: job.status, error: job.error, downloadUrl: job.status === 'complete' ? `/${job.outputKey}` : undefined });
  } catch (error) {
    console.error('Read job failed', error);
    return response(500, { message: 'Unable to read this job.' });
  }
};
