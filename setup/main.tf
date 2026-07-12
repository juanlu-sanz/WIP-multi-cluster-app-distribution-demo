resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

locals {
  pull_secret = file(pathexpand(var.pull_secret_path))
  name_suffix = random_string.suffix.result
}
