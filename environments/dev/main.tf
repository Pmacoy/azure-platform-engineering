locals {
  prefix = "azpe-dev"

  tags = {
    project     = "azure-platform-engineering"
    environment = "dev"
    managed_by  = "terraform"
  }
}

module "landing_zone" {
  source = "../../modules/landing-zone"

  prefix   = local.prefix
  location = var.location
  tags     = local.tags
}
