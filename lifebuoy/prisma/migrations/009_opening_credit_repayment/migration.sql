ALTER TABLE time_opening_credits
  ADD COLUMN repaid_minutes SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  ADD CONSTRAINT time_opening_credits_repayment_limit CHECK (repaid_minutes <= minutes);

ALTER TABLE time_journals
  ADD COLUMN opening_credit_repayment SMALLINT UNSIGNED NOT NULL DEFAULT 0,
  ADD CONSTRAINT time_journals_repayment_limit CHECK (opening_credit_repayment <= 5);
