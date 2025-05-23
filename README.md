# URL Shortener Service Design

## System Architecture Design

```
                                   ┌─────────────────┐
                                   │   Route 53      │
                                   │  (DNS Service)  │
                                   └────────┬────────┘
                                            │
                                            ▼
┌─────────────────┐                ┌────────────────┐
│  CloudFront     │◄───────────────┤  Application   │
│  (CDN)          │                │  Load Balancer │
└────────┬────────┘                └────────┬───────┘
         │                                  │
         │                          ┌───────┴───────┐
         │                          │               │
         │                    ┌─────▼─────┐   ┌─────▼─────┐
         │                    │  EC2/ECS  │   │  EC2/ECS  │  (Auto Scaling)
         └────────────────────►  Web App  │   │  Web App  │
                              │ Instances │   │ Instances │
                              └─────┬─────┘   └─────┬─────┘
                                    │               │
                                    └───────┬───────┘
                                            │
                   ┌────────────────────────┼────────────────────────┐
                   │                        │                        │
             ┌─────▼─────┐           ┌──────▼───────┐         ┌──────▼───────┐
             │ ElastiCache│           │  DynamoDB   │         │  CloudWatch  │
             │  (Redis)   │           │(URL Storage)│         │ (Monitoring) │
             └───────────┘           └──────────────┘         └──────────────┘
```

## Technology Stack

| Component       | Service |
| :-------------- | :------ |
| Frontend/CDN     | AWS CloudFront |
| Load Balancing   | AWS Application Load Balancer (ALB) |
| Application Servers | EC2 instances in Auto Scaling Group or ECS |
| Database         | Amazon DynamoDB |
| Caching          | Amazon ElastiCache (Redis) |
| Programming Language | Node.js |
| DNS              | Amazon Route 53 |
| Monitoring       | AWS CloudWatch, AWS X-Ray |
| CI/CD            | AWS CodePipeline, CodeBuild, CodeDeploy |

## API Design

### 1. URL Submission Endpoint

**Request:**

```http
POST /newurl
Content-Type: application/json

{
  "domain": "shortenurl.org",
  "url": "https://www.google.com"
}
```

**Response:**

```http
HTTP/1.1 201 Created
Content-Type: application/json

{
  "url": "https://www.google.com",
  "shortenUrl": "https://shortenurl.org/g20hi3k9Z"
}
```

### 2. Redirect Endpoint

**Request:**

```http
GET /g20hi3k9Z
```

**Response:**

```http
HTTP/1.1 302 Found
Location: https://www.google.com
```

## Database Schema

**DynamoDB Table: `URLMapping`**

| Attribute    | Type     | Description |
| :----------- | :------- | :----------- |
| `shortCode`  | String   | Primary key, the short URL code |
| `originalUrl`| String   | The original long URL |
| `createdAt`  | Timestamp | When the mapping was created |
| `hitCount`   | Number   | Number of times the URL was accessed |
| `domain`     | String   | Domain used for the short URL |

## CI/CD Design

- **Source Control:** GitHub repository
- **CI/CD Pipeline:** AWS CodePipeline
  - **Source:** GitHub repository
  - **Build:** AWS CodeBuild
  - **Test:** Automated tests (e.g., Jest)
  - **Deploy:** AWS CodeDeploy

### CI/CD Workflow

```text
Code Change → GitHub → CodePipeline → CodeBuild (lint, test, build) → CodeDeploy (staging) → Manual Approval → Production
```

## Scaling Strategy

- **Application Layer:** Auto Scaling Groups for EC2/ECS based on CPU/memory metrics
- **Database Layer:** DynamoDB auto-scaling for read/write capacity
- **Cache Layer:** Redis Cluster with read replicas

## High Availability Features

- **Multi-AZ Deployment:** Application servers across multiple Availability Zones
- **Database Redundancy:** DynamoDB replication across AZs
- **Load Balancing:** Traffic distributed across healthy instances
- **CDN:** CloudFront reduces origin load and improves global response times
- **Redis Cluster:** Multi-AZ deployment with automatic failover

## Design Rationale

- **Node.js:** Efficient for I/O-heavy applications like URL shorteners
- **DynamoDB:** Single-digit millisecond latency, serverless, auto-scaling
- **Redis (ElastiCache):** High-performance caching for frequent lookups
- **CloudFront:** Lowers latency, improves user experience globally
- **Auto Scaling:** Dynamically adjusts resources to meet traffic demand

## Assumptions and Limitations

**Assumptions:**
- Read-heavy workload (reads >> writes)
- Each short URL is accessed multiple times
- Traffic spikes expected at certain times

**Limitations:**
- 9-character codes (~13.5 trillion unique URLs)
- No analytics dashboard
- No user management/authentication
- No custom short URL aliases (only random codes)

## Meeting Scaling Target (1000+ Requests/Second)

This design can support 1000+ requests/second with:
- CloudFront absorbing most read traffic
- Redis caching frequent lookups
- DynamoDB auto-scaling for database operations
- Auto Scaling Groups for application servers
- Load Balancer distributing traffic evenly