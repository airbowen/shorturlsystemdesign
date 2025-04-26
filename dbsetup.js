// dynamodb-setup.js - Script to create DynamoDB table
const AWS = require('aws-sdk');

// Configure AWS
AWS.config.update({ region: 'us-east-1' });
const dynamodb = new AWS.DynamoDB();

const params = {
  TableName: 'URLMapping',
  KeySchema: [
    { AttributeName: 'shortCode', KeyType: 'HASH' }  // Partition key
  ],
  AttributeDefinitions: [
    { AttributeName: 'shortCode', AttributeType: 'S' }
  ],
  ProvisionedThroughput: {
    ReadCapacityUnits: 10,
    WriteCapacityUnits: 10
  }
};

// Create the table
dynamodb.createTable(params, (err, data) => {
  if (err) {
    console.error('Error creating table:', err);
  } else {
    console.log('Table created successfully:', data);
  }
});