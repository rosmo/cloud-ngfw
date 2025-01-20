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

module "bootstrap-project" {
  source         = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v37.0.0-rc2"
  name           = var.bootstrap_project_id
  prefix         = null
  project_create = false

  services = [
    "compute.googleapis.com",
    "networksecurity.googleapis.com",
    "cloudbilling.googleapis.com"
  ]
}

# Project for hosting the Shared VPC
module "host-project" {
  source          = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v37.0.0-rc2"
  billing_account = var.host_project.billing_account_id
  name            = var.host_project.project_id
  parent          = var.host_project.parent
  prefix          = null
  project_create  = var.host_project.create

  services = [
    "compute.googleapis.com",
    "networksecurity.googleapis.com",
    "cloudbilling.googleapis.com",
    "privateca.googleapis.com",
    "certificatemanager.googleapis.com"
  ]

  shared_vpc_host_config = {
    enabled = true
  }
}

locals {
  service_projects = { for service_project in var.service_projects : service_project.project_id => service_project }
}

# Service projects, which each get a project and corresponding subnet(s) in the
# Shared VPC, alongside with the Secure Tags to isolate their workloads
module "service-projects" {
  for_each        = local.service_projects
  source          = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v37.0.0-rc2"
  billing_account = each.value.billing_account_id
  name            = each.value.project_id
  parent          = each.value.parent
  prefix          = null
  project_create  = var.host_project.create

  services = [
    "compute.googleapis.com",
  ]
  shared_vpc_service_config = {
    host_project = module.host-project.project_id
    service_agent_iam = {
      "roles/compute.networkUser" = [
        "cloudservices"
      ]
    }
  }
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v37.0.0-rc2"
  project_id = module.host-project.project_id
  name       = var.vpc_config.network

  subnets = flatten([for k, v in module.service-projects :
    [for region, subnetworks in local.service_projects[k].subnetworks :
      [for subnetwork_name, subnetwork_cidr in subnetworks :
        {
          ip_cidr_range = subnetwork_cidr
          name          = subnetwork_name
          region        = region
          iam           = {}
        }
      ]
    ]
  ])

  subnets_proxy_only = [for region, proxy_only_range in var.vpc_config.proxy_only_ranges :
    [for range in proxy_only_range :
      {
        ip_cidr_range = range.subnet_cidr
        name          = range.subnet_name
        region        = region
        active        = try(range.active, false)
      }
  ]]

  firewall_policy_enforcement_order = "BEFORE_CLASSIC_FIREWALL"

  vpc_create = var.vpc_config.create
}

data "google_compute_zones" "available" {
  for_each = toset(var.regions)
  project  = var.bootstrap_project_id
  region   = each.value
}

# Create NGFW endpoints in each zone and associate the to the Shared VPC
locals {
  ngfw_zones = distinct(flatten([for region in var.regions : data.google_compute_zones.available[region].names]))
}

resource "google_network_security_firewall_endpoint" "shared-vpc" {
  for_each           = toset(local.ngfw_zones)
  name               = "cloud-ngfw-endpoint"
  parent             = format("organizations/%d", var.organization_id)
  location           = each.value
  billing_project_id = module.host-project.project_id
}

resource "google_network_security_firewall_endpoint_association" "default_association" {
  for_each          = toset(local.ngfw_zones)
  name              = format("cloud-ngfw-endpoint-%s", each.key)
  parent            = format("projects/%s", module.host-project.project_id)
  location          = google_network_security_firewall_endpoint.shared-vpc[each.key].location
  network           = module.vpc.id
  firewall_endpoint = google_network_security_firewall_endpoint.shared-vpc[each.key].id
  disabled          = false

  tls_inspection_policy = google_network_security_tls_inspection_policy.tls-inspection[substr(each.key, 0, length(each.key) - 2)].id

  labels = {}
}

# Associate the firewall policy with the Shared VPC
resource "google_compute_network_firewall_policy_association" "shared-vpc" {
  name              = "cloud-ngfw-policy-association"
  attachment_target = module.vpc.id
  firewall_policy   = google_compute_network_firewall_policy.shared-vpc.name
  project           = module.host-project.project_id
}

# Create workload tag, value for each service projects and bind the 
# service projects to the tag
resource "google_tags_tag_key" "workload" {
  parent      = var.tag_parent
  short_name  = "workload_id"
  description = "Workload ID."

  purpose = "GCE_FIREWALL"
  purpose_data = {
    network = format("%s/%s", module.host-project.project_id, module.vpc.name)
  }
}

resource "google_tags_tag_value" "workload-values" {
  for_each    = local.service_projects
  parent      = format("tagKeys/%s", google_tags_tag_key.workload.name)
  short_name  = each.value.secure_tag
  description = format("Workload ID: %s", each.value.secure_tag)
}

#resource "google_tags_tag_binding" "binding" {
#  for_each  = local.service_projects
#  parent    = format("//cloudresourcemanager.googleapis.com/projects/%d", module.service-projects[each.key].number)
#  tag_value = format("tagValues/%s", google_tags_tag_value.workload-values[each.key].name)
#}
