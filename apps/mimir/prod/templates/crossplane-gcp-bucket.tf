terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = "my-gcp-project"
  region  = "europe-west3"
}

resource "google_storage_bucket" "mimir" {
  name                        = "mimir-gcs-bucket"
  location                    = "europe-west3"
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true

  public_access_prevention = "enforced"

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 365
    }
  }
}
