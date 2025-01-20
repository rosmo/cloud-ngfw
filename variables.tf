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

variable "organization_id" {
  type        = number
  description = "Organization ID"
}

variable "tag_parent" {
  type        = string
  description = "Tag parent"
}

variable "bootstrap_project_id" {
  type        = string
  description = "Bootstrap project for some data sources"
}

variable "onprem_cidrs" {
  type        = list(string)
  description = "List of on-premise CIDRs"
  default     = ["192.168.0.0/16"]
}

variable "host_project" {
  type = object({
    project_id         = string
    create             = optional(bool, true)
    billing_account_id = optional(string)
    parent             = optional(string)
  })
  description = "Shared VPC host project"
}

variable "regions" {
  type        = list(string)
  description = "List of regions to deploy into"
}

variable "service_projects" {
  type = list(object({
    project_id         = string
    create             = optional(bool, true)
    billing_account_id = optional(string)
    secure_tag         = string
    parent             = optional(string)
    subnetworks        = map(map(string)) # region => { subnetwork_name => subnetwork_cidr }
  }))
  description = "Shared VPC service project(s)"
}

variable "vpc_config" {
  type = object({
    network           = string
    proxy_only_ranges = optional(map(string), {})
    # proxy_only_subnet_cidr = optional(string, "172.20.30.0/24")
    create = optional(bool, true)
  })
  description = "Settings for VPC (keyed by region)."
}
