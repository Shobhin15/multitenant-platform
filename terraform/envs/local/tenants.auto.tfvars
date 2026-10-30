tenants = {
  acme = {
    tier        = "premium"
    admin_group = "tenant-acme-admins"
    labels = {
      "platform.example.io/cost-center" = "cc-1001"
    }
  }

  globex = {
    tier        = "standard"
    admin_group = "tenant-globex-admins"
    labels = {
      "platform.example.io/cost-center" = "cc-2002"
    }
  }
}
