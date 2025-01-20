# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# Create security profile
resource "google_network_security_security_profile" "security-profile" {
  name        = "cloud-ngfw-profile"
  parent      = var.tag_parent
  description = "Custom threat prevention profile to block medium, high, & critical threats."
  type        = "THREAT_PREVENTION"

  threat_prevention_profile {
    severity_overrides {
      severity = "INFORMATIONAL"
      action   = "ALERT"
    }
    severity_overrides {
      severity = "LOW"
      action   = "ALERT"
    }
    severity_overrides {
      severity = "MEDIUM"
      action   = "ALERT"
    }

    severity_overrides {
      severity = "HIGH"
      action   = "ALERT"
    }

    severity_overrides {
      severity = "CRITICAL"
      action   = "ALERT"
    }
  }
}

resource "google_network_security_security_profile_group" "shared-vpc" {
  name                      = "cloud-ngfw-profile-group"
  parent                    = var.tag_parent
  threat_prevention_profile = google_network_security_security_profile.security-profile.id
}

# Create a firewall policy
resource "google_compute_network_firewall_policy" "shared-vpc" {
  name        = "cloud-ngfw-policy"
  description = "Global network firewall policy which uses Cloud NGFW inspection."
  project     = module.host-project.project_id
}

locals {
  inspection_cidrs       = concat(var.onprem_cidrs, flatten([for id, service_project in local.service_projects : [for region, subnetworks in service_project.subnetworks : [for subnetwork_name, subnetwork_cidr in subnetworks : subnetwork_cidr]]]))
  tls_inspect            = true
  security_profile_group = format("//networksecurity.googleapis.com/%s", google_network_security_security_profile_group.shared-vpc.id)
}

# Create default deny rule for ingress
resource "google_compute_network_firewall_policy_rule" "deny-ingress" {
  rule_name   = "cloud-ngfw-deny-ingress-rule"
  description = "Deny all ingress by default."

  project = module.host-project.project_id

  direction       = "INGRESS"
  enable_logging  = true
  disabled        = false
  firewall_policy = google_compute_network_firewall_policy.shared-vpc.name
  priority        = 2147480000
  action          = "deny"

  match {
    src_ip_ranges = ["0.0.0.0/0"]

    layer4_configs {
      ip_protocol = "all"
    }
  }
}

# Create default deny rule for egress
resource "google_compute_network_firewall_policy_rule" "deny-egress" {
  rule_name   = "cloud-ngfw-deny-egress-rule"
  description = "Deny all egress by default."

  project = module.host-project.project_id

  direction       = "EGRESS"
  enable_logging  = true
  disabled        = false
  firewall_policy = google_compute_network_firewall_policy.shared-vpc.name
  priority        = 2147480001
  action          = "deny"

  match {
    #dest_ip_ranges = ["172.16.0.0/12"]
    dest_ip_ranges = ["0.0.0.0/0"]

    layer4_configs {
      ip_protocol = "all"
    }
  }
}

# Create ingress firewall rules for the workloads
resource "google_compute_network_firewall_policy_rule" "workload-ingress" {
  for_each    = local.service_projects
  rule_name   = "cloud-ngfw-ingress-rule-%s"
  description = "Inspect workload traffic with Cloud NGFW."

  project = module.host-project.project_id

  direction       = "INGRESS"
  enable_logging  = false
  tls_inspect     = local.tls_inspect
  firewall_policy = google_compute_network_firewall_policy.shared-vpc.name
  priority        = 2000000 + index(keys(local.service_projects), each.key)

  action                 = "apply_security_profile_group"
  security_profile_group = local.security_profile_group

  target_secure_tags {
    name = google_tags_tag_value.workload-values[each.key].id
  }

  match {
    src_secure_tags {
      name = google_tags_tag_value.workload-values[each.key].id
    }

    layer4_configs {
      ip_protocol = "all"
    }
  }
}

resource "google_compute_network_firewall_policy_rule" "workload-egress" {
  for_each    = local.service_projects
  rule_name   = format("cloud-ngfw-egress-rule-%s", each.value.secure_tag)
  description = "Inspect workload egress traffic with Cloud NGFW."

  project = module.host-project.project_id

  direction       = "EGRESS"
  enable_logging  = false
  tls_inspect     = local.tls_inspect
  firewall_policy = google_compute_network_firewall_policy.shared-vpc.name
  priority        = 3000000 + index(keys(local.service_projects), each.key)

  action                 = "apply_security_profile_group"
  security_profile_group = local.security_profile_group

  target_secure_tags {
    name = google_tags_tag_value.workload-values[each.key].id
  }

  match {
    dest_ip_ranges = flatten([for region, subnetworks in each.value.subnetworks : [for subnetwork_name, subnetwork_cidr in subnetworks : subnetwork_cidr]])

    layer4_configs {
      ip_protocol = "all"
    }
  }
}

locals {
  firewall_rules_parsed = yamldecode(file(format("%s/firewall-rules.yaml", path.module)))
  firewall_rules        = { for i, v in local.firewall_rules_parsed.firewallRules : format("%08d-%s", i, v.name) => v }
}

resource "google_compute_network_firewall_policy_rule" "firewall-rules" {
  for_each    = local.firewall_rules
  rule_name   = format("cloud-ngfw-%s", each.value.name)
  description = format("Custom rule: %s", each.value.name)

  project = module.host-project.project_id

  direction       = each.value.direction
  firewall_policy = google_compute_network_firewall_policy.shared-vpc.name
  priority        = 1000000 + index(keys(local.firewall_rules), each.key)
  disabled        = lookup(each.value, "disabled", false)

  tls_inspect = lookup(each.value, "deny", false) == false && each.value.direction == "INGRESS" ? local.tls_inspect : null

  enable_logging = true

  action                 = lookup(each.value, "deny", false) == true ? "deny" : (each.value.direction == "INGRESS" ? "apply_security_profile_group" : "allow")
  security_profile_group = lookup(each.value, "deny", false) == false && each.value.direction == "INGRESS" ? local.security_profile_group : null

  dynamic "target_secure_tags" {
    for_each = toset(lookup(each.value, "targetSecureTags", []))
    content {
      name = target_secure_tags.value
    }
  }

  match {
    dest_ip_ranges = lookup(each.value, "destinationIpRanges", null)
    src_ip_ranges  = lookup(each.value, "sourceIpRanges", null)

    dest_fqdns = lookup(each.value, "destinationFQDNs", null)

    dynamic "src_secure_tags" {
      for_each = lookup(each.value, "sourceSecureTags", [])
      content {
        name = src_secure_tags.value
      }
    }

    dynamic "layer4_configs" {
      for_each = lookup(each.value, "layer4Configs", [])
      content {
        ip_protocol = lookup(layer4_configs.value, "ipProtocol", "all")
        ports       = lookup(layer4_configs.value, "ports", null)
      }
    }
  }
}
