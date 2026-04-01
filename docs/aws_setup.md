# ☁️ AWS Cloud Infrastructure: S3 & IAM Specification

This technical manual details the setup of the AWS foundation required for the Snowflake-S3 data bridge. As a **Principal Data Engineer**, you must ensure the following configurations are implemented with strict adherence to **Least Privilege** security principles.

---

## 🏗️ 1. S3 Data Lake Partitioning

Create an S3 bucket (e.g., `s3://your-company-datalake/`) in your primary region (e.g., `us-east-1`). 

### Prefix Strategy:
The pipeline expects a hierarchical "Object Discovery" partition strategy. 

```bash
# Bucket Root: s3://your-company-datalake/
└── raw/ 
    └── ecommerce/
        ├── orders/       # CSV Files
        ├── customers/    # JSON Files
        ├── order_items/  # CSV Files
        └── products/     # CSV Files
```

> [!CAUTION]
> **S3 Public Access**: Ensure "Block all public access" is **ENABLED**. Snowflake access is handled exclusively via IAM role assumption, never through bucket policies with `Principal: "*"`.

---

## 🔒 2. IAM Policy: `SnowflakeS3Access`

Create an IAM policy with the following JSON definition. This policy restricts Snowflake to only `LIST` and `GET` objects within the `raw/` prefix.

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:DeleteObject",
                "s3:DeleteObjectVersion"
            ],
            "Resource": "arn:aws:s3:::your-company-datalake/raw/*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:GetBucketLocation"
            ],
            "Resource": "arn:aws:s3:::your-company-datalake",
            "Condition": {
                "StringLike": {
                    "s3:prefix": [
                        "raw/*"
                    ]
                }
            }
        }
    ]
}
```

---

## 👥 3. IAM Role: `SnowflakeS3ReaderRole`

1. **Trusted Entity**: Select "AWS Account."
2. **Account ID**: Use your own AWS Account ID for now (This is a placeholder that you will replace in the next step).
3. **Attach Policy**: Attach the `SnowflakeS3Access` policy created in Step 2.
4. **Role Name**: `SnowflakeS3ReaderRole`.

---

## 🤝 4. The Cloud Handshake (Critical)

To move from "Provisioned" to "Integrated," you must complete the 2-way trust handshake.

### Step A: Snowflake Storage Integration
Run this SQL as **ACCOUNTADMIN** in Snowflake:
```sql
CREATE STORAGE INTEGRATION S3_ECOMMERCE_INT
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<YOUR_AWS_ACCOUNT_ID>:role/SnowflakeS3ReaderRole'
    STORAGE_ALLOWED_LOCATIONS = ('s3://your-company-datalake/raw/')
    COMMENT = 'Secure, credential-free S3 integration';
```

### Step B: Retrieve Snowflake's AWS Identity
```sql
DESCRIBE INTEGRATION S3_ECOMMERCE_INT;
```
Capture the **Value** for:
- `STORAGE_AWS_IAM_USER_ARN`  (e.g., `arn:aws:iam::123456789012:user/abc1-s-xyz2`)
- `STORAGE_AWS_EXTERNAL_ID`  (e.g., `SF_ACCOUNT_SFCR_123`)

### Step C: Update IAM Trust Relationship
In the AWS Console, edit the **Trust relationship** of `SnowflakeS3ReaderRole` with this JSON:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "AWS": "<STORAGE_AWS_IAM_USER_ARN>"
      },
      "Action": "sts:AssumeRole",
      "Condition": {
        "StringEquals": {
          "sts:ExternalId": "<STORAGE_AWS_EXTERNAL_ID>"
        }
      }
    }
  ]
}
```

---

## ✅ 5. Verification Benchmark

Verify that Snowflake can physically see the AWS bucket before proceeding to the local setup:

```sql
-- Role: SYSADMIN
LS @RAW.ECOMMERCE.S3_RAW_STAGE;
```

> [!NOTE]
> If you receive an `Access Denied` error, double-check that the `STORAGE_AWS_EXTERNAL_ID` in the Role Trust Policy matches perfectly with the `DESC INTEGRATION` output.
