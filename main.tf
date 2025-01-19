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

# Project for hosting the Shared VPC
module "host-project" {
  source          = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v37.0.0-rc2"
  billing_account = var.host_project.billing_account_id
  name            = var.host_project.project_id
  parent          = var.host_project.parent
  prefix          = null
  shared_vpc_host_config = {
    enabled = true
  }
}

# Service projects, which each get a project and corresponding subnet(s) in the
# Shared VPC, alongside with the Secure Tags to isolate their workloads
module "service-projects" {
  for_each        = { for service_project in var.service_projects : service_project.project_id => service_project }
  source          = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/project?ref=v37.0.0-rc2"
  billing_account = each.value.billing_account_id
  name            = each.value.project_id
  parent          = each.value.parent
  prefix          = null
  services = [
    "compute.googleapis.com",
    "networksecurity.googleapis.com",
  ]
  shared_vpc_service_config = {
    host_project = module.host-project.project_id
    service_agent_iam = {
      "roles/compute.networkUser" = [
        "cloudservices", "container-engine"
      ]
    }
  }
}

module "vpc" {
  source     = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/net-vpc?ref=v37.0.0-rc2"
  project_id = module.host-project.project_id
  name       = var.vpc_config.network

  subnets = flatten([for k, v in module.service-projects :
    [for region, subnetworks in var.service_projects[k].subnetworks :
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

  vpc_create = var.vpc_config.create
}

data "google_compute_zones" "available" {
  for_each = toset(var.regions)
  project  = module.host-project.project_id
  region   = each.value
}

locals {
  ngfw_zones = distinct(flatten([for region in var.regions : data.google_compute_zones.available[region].names]))
}

resource "google_network_security_firewall_endpoint" "main" {
  for_each           = toset(local.ngfw_zones)
  name               = "cloud-ngfw-endpoint"
  parent             = format("organizations/%d", var.organization_id)
  location           = each.value
  billing_project_id = var.host_project.billing_account_id
}
