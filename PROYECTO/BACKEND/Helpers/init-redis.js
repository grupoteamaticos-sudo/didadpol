const { createClient } = require('redis');

const client = createClient({
  url: process.env.REDIS_URL,
  socket: {
    reconnectStrategy: (retries) => {
      if (retries > 5) {
        console.error('Redis reconnection limit reached.');
        return new Error('Retry limit reached');
      }
      return Math.min(retries * 100, 3000);
    }
  }
});

client.on('connect', () => {
  console.log('[REDIS] Connecting to Redis...');
});

client.on('ready', () => {
  console.log('[OK] Redis connected and ready');
});

client.on('error', (err) => {
  console.error('[ERROR] Redis error:', err.message);
});

client.on('end', () => {
  console.warn('[WARN] Redis connection closed');
});

(async () => {
  try {
    await client.connect();
  } catch (error) {
    console.error('[ERROR] Redis initial connection failed:', error.message);
  }
})();

process.on('SIGINT', async () => {
  await client.quit();
  process.exit(0);
});

module.exports = client;
