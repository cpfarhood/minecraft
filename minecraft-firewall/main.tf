terraform {
  required_providers {
    opnsense = {
      version = "~>0.11.0"
      source  = "browningluke/opnsense"
    }
  }
}
provider "opnsense" {
  uri = var.FW_URI
  api_key = var.FW_KEY
  api_secret = var.FW_SECRET
#  uri = "https://firewall.dmz.farh.net"
#  api_key = "uqJ3YUqb8uE5qDhqieKmrfZqbYx7ugjF1ELPEMA35L5Djge6n5/BhilrhGLK+al87/9wD1dwg9ZOrPDy"
#  api_secret = "TAsh9y+30910gAxrSAsjLQogHR70Rb0muVcHy5Y9pZ1f8Ajk7wutxXoDGAhPBshzSAqeFZFRlLjbaVTn"
}

resource "opnsense_firewall_filter" "traefik-external-http" {
  action = "pass"
  interface = [ "wan", "opt1" ]
  direction = "in"
  protocol  = "TCP"
  source = { net = "any" }
  destination = {
    net  = var.RULE_IP
    port = var.RULE_HTTPPORT
  }
  description = "traefik-external-http"
}
resource "opnsense_firewall_filter" "traefik-external-https" {
  action = "pass"
  interface = [ "wan", "opt1"]
  direction = "in"
  protocol  = "TCP"
  source = { net = "any" }
  destination = {
    net  = var.RULE_IP
    port = var.RULE_HTTPSPORT
  }
  description = "traefik-external-https"
}
