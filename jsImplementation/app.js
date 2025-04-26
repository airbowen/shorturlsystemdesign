// app.js - Main application file
const express = require('express');
const bodyParser = require('body-parser');
const AWS = require('aws-sdk');
const Redis = require('ioredis');
const crypto = require('crypto');
const app = express();

// Configure AWS
AWS.config.update({ 
  region: process.env.AWS_REGION || 'us-east-1',
  accessKeyId: process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
});

const dynamodb = new AWS.DynamoDB.DocumentClient();
const TABLE_NAME = process.env.DYNAMODB_TABLE || 'URLMapping';

// Setup Redis client
const redis = new Redis({
  host: process.env.REDIS_HOST || 'localhost',
  port: process.env.REDIS_PORT || 6379,
  password: process.env.REDIS_PASSWORD
});

// Middleware
app.use(bodyParser.json());

// Generate a short code
function generateShortCode() {
  // Generate a random string and take first 9 chars
  return crypto.randomBytes(6)
    .toString('base64')
    .replace(/[+/=]/g, '')
    .substring(0, 9);
}

// URL submission endpoint
app.post('/newurl', async (req, res) => {
  try {
    const { domain, url } = req.body;
    
    if (!domain || !url) {
      return res.status(400).json({ error: 'Missing required parameters' });
    }
    
    // Validate URL format
    try {
      new URL(url);
    } catch (err) {
      return res.status(400).json({ error: 'Invalid URL format' });
    }
    
    // Generate a unique short code
    let shortCode;
    let isUnique = false;
    let retries = 0;
    const MAX_RETRIES = 5;
    
    while (!isUnique && retries < MAX_RETRIES) {
      shortCode = generateShortCode();
      
      // Check if code already exists
      const existingItem = await dynamodb.get({
        TableName: TABLE_NAME,
        Key: { shortCode }
      }).promise();
      
      if (!existingItem.Item) {
        isUnique = true;
      } else {
        retries++;
      }
    }
    
    if (!isUnique) {
      return res.status(500).json({ error: 'Could not generate unique code, please try again' });
    }
    
    // Store in DynamoDB
    const timestamp = new Date().toISOString();
    const item = {
      shortCode,
      originalUrl: url,
      domain,
      createdAt: timestamp,
      hitCount: 0
    };
    
    await dynamodb.put({
      TableName: TABLE_NAME,
      Item: item
    }).promise();
    
    // Store in Redis cache
    await redis.set(shortCode, url, 'EX', 86400); // Cache for 24 hours
    
    // Return the shortened URL
    const shortenUrl = `https://${domain}/${shortCode}`;
    return res.status(201).json({
      url,
      shortenUrl
    });
    
  } catch (error) {
    console.error('Error creating short URL:', error);
    return res.status(500).json({ error: 'Server error' });
  }
});

// Redirect endpoint
app.get('/:shortCode([a-zA-Z0-9]{9})', async (req, res) => {
  try {
    const { shortCode } = req.params;
    
    // First check Redis cache
    const cachedUrl = await redis.get(shortCode);
    
    if (cachedUrl) {
      // Update hit count asynchronously
      updateHitCount(shortCode).catch(err => 
        console.error('Failed to update hit count:', err));
      
      // Redirect to the original URL
      return res.redirect(302, cachedUrl);
    }
    
    // If not in cache, check DynamoDB
    const result = await dynamodb.get({
      TableName: TABLE_NAME,
      Key: { shortCode }
    }).promise();
    
    if (!result.Item) {
      return res.status(404).json({ error: 'Short URL not found' });
    }
    
    const originalUrl = result.Item.originalUrl;
    
    // Cache the result for future requests
    await redis.set(shortCode, originalUrl, 'EX', 86400); // Cache for 24 hours
    
    // Update hit count asynchronously
    updateHitCount(shortCode).catch(err => 
      console.error('Failed to update hit count:', err));
    
    // Redirect to the original URL
    return res.redirect(302, originalUrl);
    
  } catch (error) {
    console.error('Error redirecting:', error);
    return res.status(500).json({ error: 'Server error' });
  }
});

// Health check endpoint for load balancer
app.get('/health', (req, res) => {
  // Check Redis connection
  const redisStatus = redis.status === 'ready' ? 'OK' : 'ERROR';
  
  // Basic health check - can be enhanced to check DynamoDB too
  const status = {
    service: 'URL Shortener',
    redis: redisStatus,
    timestamp: new Date().toISOString()
  };
  
  const isHealthy = redisStatus === 'OK';
  
  res.status(isHealthy ? 200 : 500).json(status);
});

// Function to update hit count
async function updateHitCount(shortCode) {
  await dynamodb.update({
    TableName: TABLE_NAME,
    Key: { shortCode },
    UpdateExpression: 'ADD hitCount :inc',
    ExpressionAttributeValues: {
      ':inc': 1
    }
  }).promise();
}

// Start the server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});

module.exports = app; // For testing