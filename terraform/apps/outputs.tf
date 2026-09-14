output "apps" {
  value = {
    donation = module.donation.wiring
    shorten  = module.shorten.wiring
  }
}
