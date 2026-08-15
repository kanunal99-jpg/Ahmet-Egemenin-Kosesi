-- ============================================================================
-- Migration: 20260815000009_pgcrypto_schema_qualification.sql
-- Description: Historical Pgcrypto Extension Schema Qualification
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;
