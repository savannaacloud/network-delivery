terraform {
  required_version = ">= 1.5"

  required_providers {
    sws = {
      source  = "savannaacloud/sws"
      version = "~> 0.4"
    }
  }
}

provider "sws" {
  # Authenticated by SWS_API_URL + SWS_API_KEY env vars.
}
