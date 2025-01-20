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

module "tls-ca" {
  for_each = toset(var.regions)
  source   = "github.com/GoogleCloudPlatform/cloud-foundation-fabric//modules/certificate-authority-service?ref=v37.0.0-rc2"

  project_id = module.host-project.project_id
  location   = each.key
  ca_pool_config = {
    create_pool = {
      name = format("cloud-ngfw-tls-ca-%s", each.key)
      tier = "DEVOPS"
    }
  }
  ca_configs = {
    root_ca_1 = {
      key_spec_algorithm = "RSA_PKCS1_4096_SHA256"
      key_usage = {
        client_auth = true
        server_auth = true
      }
    }
  }
  iam_bindings_additive = {
    cert-manager = {
      member = module.host-project.service_agents["networksecurity"].iam_email
      role   = "roles/privateca.certificateRequester"
    }
  }
}

resource "google_network_security_tls_inspection_policy" "tls-inspection" {
  for_each = toset(var.regions)

  project               = module.host-project.project_id
  name                  = format("cloud-ngfw-tls-inspect-%s", each.key)
  location              = each.key
  ca_pool               = module.tls-ca[each.key].ca_pool_id
  exclude_public_ca_set = false
}
