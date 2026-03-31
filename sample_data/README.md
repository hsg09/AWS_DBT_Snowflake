# Sample Data Files

Realistic sample data for testing the ELT pipeline locally or in a dev Snowflake environment.

## Files

| File | Format | Records | Notes |
|---|---|---|---|
| `orders.csv` | CSV | 30 | All 6 statuses, 13 countries, 7 payment methods |
| `customers.json` | JSON Array | 26 | Full JSON payload matching `RAW_PAYLOAD` VARIANT schema |
| `order_items.csv` | CSV | 52 | 1–3 items per order, varied discounts (0–75%) |
| `products.csv` | CSV | 30 | 10 categories, realistic cost/price margins |

## Upload to S3

```bash
# Set your bucket name
BUCKET="your-data-lake-bucket"

# Upload each file to the correct S3 path matching the external stages
aws s3 cp orders.csv      s3://${BUCKET}/raw/ecommerce/orders/orders_2024_01.csv
aws s3 cp customers.json  s3://${BUCKET}/raw/ecommerce/customers/customers_2024_01.json
aws s3 cp order_items.csv s3://${BUCKET}/raw/ecommerce/order_items/order_items_2024_01.csv
aws s3 cp products.csv    s3://${BUCKET}/raw/ecommerce/products/products_2024_01.csv
```

## Load Directly into Snowflake (bypass S3 — for local testing)

```sql
-- If you want to skip S3 and load directly for dev testing:

USE ROLE LOADER;
USE WAREHOUSE LOADER_WH;

-- 1. Load orders
COPY INTO RAW.ECOMMERCE.ORDERS
FROM @RAW.ECOMMERCE.S3_ORDERS_STAGE/orders_2024_01.csv
FILE_FORMAT = (FORMAT_NAME = 'RAW.ECOMMERCE.FF_CSV')
ON_ERROR = 'CONTINUE';

-- 2. Load customers (JSON)
COPY INTO RAW.ECOMMERCE.CUSTOMERS (RAW_PAYLOAD)
FROM @RAW.ECOMMERCE.S3_CUSTOMERS_STAGE/customers_2024_01.json
FILE_FORMAT = (FORMAT_NAME = 'RAW.ECOMMERCE.FF_JSON')
ON_ERROR = 'CONTINUE';

-- 3. Load order_items
COPY INTO RAW.ECOMMERCE.ORDER_ITEMS
FROM @RAW.ECOMMERCE.S3_ORDER_ITEMS_STAGE/order_items_2024_01.csv
FILE_FORMAT = (FORMAT_NAME = 'RAW.ECOMMERCE.FF_CSV')
ON_ERROR = 'CONTINUE';

-- 4. Load products
COPY INTO RAW.ECOMMERCE.PRODUCTS
FROM @RAW.ECOMMERCE.S3_PRODUCTS_STAGE/products_2024_01.csv
FILE_FORMAT = (FORMAT_NAME = 'RAW.ECOMMERCE.FF_CSV')
ON_ERROR = 'CONTINUE';
```

## Data Design Notes

### orders.csv
- Covers all statuses: `completed`, `shipped`, `processing`, `pending`, `cancelled`, `refunded`
- `CUST-001` and `CUST-002` appear multiple times — exercises deduplication and LTV aggregation
- `CUST-003` has orders in both Jan and Feb — exercises `customer_type_at_order` logic
- 3 orders have no `SHIPPED_DATE` (status = pending/processing/cancelled) — exercises null handling

### customers.json
- Loaded as a JSON array — matches `FF_JSON` with `STRIP_OUTER_ARRAY = TRUE`
- All 5 customer segments represented: `bronze`, `silver`, `gold`, `platinum`, `vip`
- 3 customers have `is_email_verified = false` — tests accepted_values and quality flags
- All 26 customers have unique `customer_id` matching references in `orders.csv`

### order_items.csv
- `ITEM-0002` has `DISCOUNT_PCT = 75` — tests discount clamping in staging model
- Multiple products per order (e.g. ORD-00018 has 3 line items) — tests aggregation
- `ITEM-0035` on cancelled order `ORD-00020` — tests that revenue reconciliation test handles accordingly
- Some items reference high-margin products (PROD-020 chair at 47% margin) and low-margin (PROD-030 charger at 67% margin)

### products.csv
- `PROD-025` (PlayStation 5) has `IS_ACTIVE = FALSE` — tests `is_active` flag handling
- Wide range of margins: 33% (Kindle) to 87% (Anker charger) — exercises `margin_tier` logic
- All product categories match entries in `seeds/product_categories.csv`
