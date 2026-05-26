provider "azurerm" {
  features {
  }
  use_cli                         = true
  resource_provider_registrations = "none"
  subscription_id                 = "11111111-1111-1111-1111-111111111111"
  environment                     = "public"
}
