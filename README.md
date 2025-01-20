# Cloud NGFW demo with TLS inspection and goodies

## Sample config

```
organization_id      = "1234567890"
tag_parent           = "organizations/1234567890"
bootstrap_project_id = "my-bootstrap-project"
host_project = {
  project_id         = "my-shared-vpc-host-project"
  create             = true
  billing_account_id = "123457-123457-23456"
  parent             = null
}
regions = ["europe-north1", "europe-west4"]
service_projects = [{
  billing_account_id = "123457-123457-23456"
  create             = true
  parent             = null
  project_id         = "my-service-project-1"
  secure_tag         = "workload1"
  subnetworks = {
    "europe-north1" = {
      "workload1-eun1" = "172.20.40.0/24"
    }
  }
  },
  {
    billing_account_id = "123457-123457-23456"
    create             = true
    parent             = null
    project_id         = "my-service-project-2"
    secure_tag         = "workload2"
    subnetworks = {
      "europe-north1" = {
        "workload2-eun1" = "172.20.80.0/24"
      }
    }
}]
vpc_config = {
  network = "testorg-svpc"
  proxy_only_range = {
    europe-north1 = [{
      subnet_cidr = "172.20.30.0/24"
      subnet_name = "testorg-svpc-proxyonly-eun1"
      active      = true
    }]
  }
}
```