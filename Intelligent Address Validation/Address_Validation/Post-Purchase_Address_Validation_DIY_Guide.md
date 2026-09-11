# DIY Guide: Post-Purchase Address Validation Workflow

## Overview

This workflow validates customer shipping addresses immediately after an order is paid, stores both the original and corrected addresses, determines whether manual review is required, and sends validated orders to the warehouse.

## Prerequisites

- n8n
- Shopify store
- PostgreSQL
- Google Address Validation API
- Slack
- Warehouse API (or webhook endpoint)

---

# Database

## orders

Stores the latest state of every order.

Important fields:

- order_id
- customer_name
- customer_email
- customer_phone
- address1
- address2
- city
- state
- postal_code
- country
- validation_status
- warehouse_status
- warehouse_order_id

## address_validation_log

Stores validation results.

Important fields:

- order_id
- original_address (JSONB)
- corrected_address (JSONB)
- google_response (JSONB)
- confidence_score
- validation_status
- latitude
- longitude
- place_id
- formatted_address

---

# Workflow

## Step 1 — Shopify Trigger

Event:

```
orders/paid
```

Every paid order starts the workflow.

---

## Step 2 — Extract Order Details

A Code node extracts:

- Customer information
- Shipping address
- Order metadata

The workflow initializes:

```
validation_status = PENDING
```

---

## Step 3 — Save Order

Insert or update the order in PostgreSQL using an UPSERT.

Purpose:

- Avoid duplicate orders
- Keep customer information current

---

## Step 4 — Validate Address

Send the shipping address to the Google Address Validation API.

Google returns:

- standardized address
- verdict
- geocode
- formatted address
- place id

---

## Step 5 — Determine Validation Status

Business rules:

READY

- Address complete
- No inferred components

READY_WITH_CORRECTIONS

- Google corrected part of the address
- Address is still deliverable

REVIEW_REQUIRED

- Address incomplete
- Manual verification required

A confidence score is also calculated.

---

## Step 6 — Log Validation

Insert a row into:

```
address_validation_log
```

Store:

- original address
- corrected address
- full Google response
- confidence score
- geocode
- place id
- formatted address

This creates an audit trail.

---

## Step 7 — Update Order Status

Update the main orders table.

Example:

```
validation_status = READY
```

---

## Step 8 — Decision

If

```
requires_review == true
```

Send a Slack notification.

Otherwise continue to warehouse processing.

---

## Step 9 — Warehouse Integration

POST validated order to the warehouse endpoint.

Payload contains:

- order_id
- customer
- validated address
- coordinates
- confidence score

---

## Step 10 — Save Warehouse Response

Update:

- warehouse_order_id
- warehouse_status
- warehouse_name
- estimated_pick_time

---

## Step 11 — Notify Slack

Send confirmation including:

- warehouse order id
- warehouse
- status
- estimated pick time

---

# Dashboard Endpoint

A second webhook executes:

1. SQL JOIN
2. Summary calculations
3. Returns JSON

Returned structure:

```json
{
  "summary": {},
  "orders": []
}
```

The dashboard displays:

- Total Orders
- Ready
- Ready With Corrections
- Review Required
- Average Confidence
- Order list
- Original vs Corrected address
- Warehouse status

---

# Workflow Diagram

```
Shopify Paid Order
        │
        ▼
Extract Order Details
        │
        ▼
Insert Order
        │
        ▼
Google Address Validation
        │
        ▼
Determine Status
        │
        ├──────────────┐
        │              │
        ▼              ▼
Review Needed?      Ready
        │              │
        ▼              ▼
Slack Alert     Warehouse API
                       │
                       ▼
              Update Warehouse Status
                       │
                       ▼
               Slack Confirmation
```

---

# Benefits

- Eliminates invalid shipping addresses
- Creates a complete validation audit trail
- Reduces warehouse failures
- Automates fulfillment decisions
- Provides real-time dashboard reporting
- Preserves Google's complete validation response for future analysis
