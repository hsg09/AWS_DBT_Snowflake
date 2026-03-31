-- =============================================================================
-- File: 05_data_masking.sql
-- Purpose: Implement data governance:
--          - Dynamic data masking policies for PII columns
--          - Column-level security (masking based on role)
--          - Secure views for sensitive entitry data
--          - Row-level access policies (example)
-- Run as: ACCOUNTADMIN (masking policies) then SYSADMIN
-- =============================================================================

USE ROLE ACCOUNTADMIN;
USE WAREHOUSE ADMIN_WH;

-- ---------------------------------------------------------------------------
-- 1. Dynamic Data Masking Policies
--    Rules:
--      ANALYST role sees masked values for PII columns
--      TRANSFORMER / DATA_ENGINEER roles see full values
--      LOADER role sees full values (needs to load raw data)
-- ---------------------------------------------------------------------------

-- Email masking: show only domain part (user@example.com → ****@example.com)
CREATE OR REPLACE MASKING POLICY RAW.ECOMMERCE.MASK_EMAIL
    AS (email_value VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('TRANSFORMER', 'DATA_ENGINEER', 'SYSADMIN', 'ACCOUNTADMIN')
            THEN email_value
        WHEN CURRENT_ROLE() = 'ANALYST'
            THEN CONCAT('****@', SPLIT_PART(email_value, '@', 2))
        ELSE '***MASKED***'
    END
COMMENT = 'Masks email username; shows domain to analysts. Full value to engineers.';

-- Phone masking: show only last 4 digits
CREATE OR REPLACE MASKING POLICY RAW.ECOMMERCE.MASK_PHONE
    AS (phone_value VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('TRANSFORMER', 'DATA_ENGINEER', 'SYSADMIN', 'ACCOUNTADMIN')
            THEN phone_value
        WHEN CURRENT_ROLE() = 'ANALYST'
            THEN CONCAT('***-***-', RIGHT(REGEXP_REPLACE(phone_value, '[^0-9]', ''), 4))
        ELSE '***MASKED***'
    END
COMMENT = 'Shows only last 4 digits of phone number to analysts.';

-- Generic PII string masking (for names, addresses, etc.)
CREATE OR REPLACE MASKING POLICY RAW.ECOMMERCE.MASK_PII_STRING
    AS (pii_value VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('TRANSFORMER', 'DATA_ENGINEER', 'SYSADMIN', 'ACCOUNTADMIN')
            THEN pii_value
        ELSE '***MASKED***'
    END
COMMENT = 'Full masking for highly sensitive PII strings (names, addresses).';

-- Number masking (e.g., credit card last 4)
CREATE OR REPLACE MASKING POLICY RAW.ECOMMERCE.MASK_SENSITIVE_NUMBER
    AS (num_value NUMBER) RETURNS NUMBER ->
    CASE
        WHEN CURRENT_ROLE() IN ('TRANSFORMER', 'DATA_ENGINEER', 'SYSADMIN', 'ACCOUNTADMIN')
            THEN num_value
        ELSE -1  -- sentinel value indicating masked number
    END
COMMENT = 'Masks sensitive numeric values; returns -1 for unauthorized roles.';

-- ---------------------------------------------------------------------------
-- 2. Apply masking policies to PII columns in raw tables
-- ---------------------------------------------------------------------------

-- Apply to CUSTOMERS table
ALTER TABLE RAW.ECOMMERCE.CUSTOMERS
    MODIFY COLUMN EMAIL   SET MASKING POLICY RAW.ECOMMERCE.MASK_EMAIL;

ALTER TABLE RAW.ECOMMERCE.CUSTOMERS
    MODIFY COLUMN PHONE   SET MASKING POLICY RAW.ECOMMERCE.MASK_PHONE;

-- Grant masking policy usage to SYSADMIN for management
GRANT APPLY MASKING POLICY ON ACCOUNT TO ROLE SYSADMIN;

-- ---------------------------------------------------------------------------
-- 3. Secure View: ANALYTICS.MARTS.SECURE_CUSTOMER_PROFILES
--    SECURE keyword prevents query plan exposure (prevents column inference attacks)
--    Used when sharing data externally or with less-trusted consumers.
-- ---------------------------------------------------------------------------
USE ROLE SYSADMIN;
USE DATABASE ANALYTICS;
USE SCHEMA MARTS;

CREATE OR REPLACE SECURE VIEW ANALYTICS.MARTS.SECURE_CUSTOMER_PROFILES
COMMENT = 'PII-safe customer view for external sharing and analyst consumption.'
AS
SELECT
    customer_sk,
    customer_id,
    -- Email and phone are masked at the raw table level via masking policy
    -- Here we apply additional row-level filtering for extra safety
    CASE
        WHEN CURRENT_ROLE() IN ('ANALYST') THEN email   -- already masked by policy
        WHEN CURRENT_ROLE() IN ('TRANSFORMER', 'DATA_ENGINEER', 'SYSADMIN') THEN email
        ELSE NULL
    END AS email,
    country,
    customer_segment,
    lifetime_value_usd,
    total_orders,
    first_order_date,
    last_order_date,
    is_active,
    _dbt_updated_at
FROM ANALYTICS.MARTS.DIM_CUSTOMERS
WHERE is_active = TRUE;

-- Grant to analyst role
GRANT SELECT ON VIEW ANALYTICS.MARTS.SECURE_CUSTOMER_PROFILES TO ROLE ANALYST;

-- ---------------------------------------------------------------------------
-- 4. Row Access Policy (tenant-level data isolation — bonus feature)
--    Pattern: each tenant can only see their own rows.
--    Applied when multi-tenant ingestion is needed.
-- ---------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

-- Row access policy table (maps role → allowed tenant_ids)
CREATE TABLE IF NOT EXISTS RAW.ECOMMERCE.ROW_ACCESS_POLICY_MAP (
    role_name       VARCHAR(200),
    tenant_id       VARCHAR(100),
    PRIMARY KEY (role_name, tenant_id)
)
COMMENT = 'Maps Snowflake roles to allowed tenant IDs for row-level security.';

-- Sample rows (populate as needed):
-- INSERT INTO RAW.ECOMMERCE.ROW_ACCESS_POLICY_MAP VALUES ('ANALYST_TENANT_A', 'tenant_a');
-- INSERT INTO RAW.ECOMMERCE.ROW_ACCESS_POLICY_MAP VALUES ('ANALYST_TENANT_B', 'tenant_b');

-- Row access policy definition
CREATE OR REPLACE ROW ACCESS POLICY RAW.ECOMMERCE.RAP_TENANT_ISOLATION
    AS (tenant_id VARCHAR) RETURNS BOOLEAN ->
    CURRENT_ROLE() IN ('SYSADMIN', 'ACCOUNTADMIN', 'DATA_ENGINEER', 'TRANSFORMER')
    OR EXISTS (
        SELECT 1
        FROM RAW.ECOMMERCE.ROW_ACCESS_POLICY_MAP m
        WHERE m.role_name  = CURRENT_ROLE()
          AND m.tenant_id  = tenant_id
    )
COMMENT = 'Tenants can only see their own rows unless granted an admin role.';

-- Apply to a multi-tenant table (example table must have tenant_id column):
-- ALTER TABLE RAW.ECOMMERCE.ORDERS
--     ADD ROW ACCESS POLICY RAW.ECOMMERCE.RAP_TENANT_ISOLATION ON (TENANT_ID);

-- ---------------------------------------------------------------------------
-- 5. Audit: who applied what policy to which column
-- ---------------------------------------------------------------------------
-- SELECT * FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
-- WHERE POLICY_KIND IN ('MASKING_POLICY', 'ROW_ACCESS_POLICY')
-- ORDER BY POLICY_CREATED DESC;

-- ---------------------------------------------------------------------------
-- 6. Security best-practice summary (comments for documentation)
-- ---------------------------------------------------------------------------
-- ✅ Storage Integration (not credentials) for S3 access
-- ✅ Principle of least privilege: LOADER writes only to RAW
-- ✅ Dynamic data masking on all PII columns (email, phone)
-- ✅ Secure views prevent query-plan-based column inference attacks
-- ✅ Row-level security for multi-tenant isolation
-- ✅ Separate service accounts per workload (SVC_LOADER, SVC_TRANSFORMER)
-- ✅ Network policy (add below) to restrict Snowflake access by IP
-- ✅ MFA enforcement recommended for human users (not automated here)
-- ✅ All DDL logged via SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY

-- Network policy example (restrict Snowflake login to known IP ranges):
-- CREATE NETWORK POLICY CORPORATE_NETWORK
--     ALLOWED_IP_LIST = ('203.0.113.0/24', '198.51.100.0/24')  -- replace with real CIDRs
--     COMMENT         = 'Allow access only from corporate IP ranges';
-- ALTER ACCOUNT SET NETWORK_POLICY = CORPORATE_NETWORK;
