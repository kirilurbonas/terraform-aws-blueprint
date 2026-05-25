mock_provider "aws" {}

variables {
  environment     = "dev"
  project         = "blueprint-tests"
  bucket_name     = "blueprint-test-tfstate-111122223333"
  lock_table_name = "blueprint-test-tfstate-locks"
}

run "defaults_plan_cleanly" {
  command = plan
}

run "rejects_bad_bucket" {
  command         = plan
  expect_failures = [var.bucket_name]

  variables {
    bucket_name = "Bad_Bucket_Name"
  }
}
