# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


### GKE NodeSet
locals {
  manifest_path = "${path.module}/templates/nodeset-general.yaml.tftpl"

  cluster_id_parts = split("/", var.cluster_id)
  cluster_name     = local.cluster_id_parts[5]
  cluster_location = local.cluster_id_parts[3]
  project_id       = var.project_id != null ? var.project_id : local.cluster_id_parts[1]
}

data "google_client_config" "default" {}

data "google_container_cluster" "gke_cluster" {
  project  = local.project_id
  name     = local.cluster_name
  location = local.cluster_location
}

resource "helm_release" "gke_nodesets" {
  name      = "gke-nodesets"
  provider  = helm
  version     = "0.7.0"
  chart     = "${path.module}/helm-charts/gke-nodesets"
  namespace = var.slurm_namespace
  create_namespace = true

  set {
    name = "nodeset.name"
    value = "${var.slurm_cluster_name}-${var.nodeset_name}"
  }

  set {
    name = "nodeset.replicas"
    value = var.node_count_static
  }

  set {
    name = "nodeset.nodePool"
    value = "${var.slurm_cluster_name}-${var.nodeset_name}"
  }

  set {
    name = "nodeset.configPvc"
    value = "slurm-key-pvc"
  }

  set {
    name = "filestore.location"
    value = local.cluster_location
  }

  set {
    name = "filestore.ipAddress"
    value = var.slurm_controller_instance.network_interface[0].network_ip
  }

  set {
    name = "filestore.instanceName"
    value = "slurm-key"
  }

  set {
    name = "slurmdImage"
    value = var.image
  }

  set {
    name = "slurm.controllerName"
    value = "${var.slurm_cluster_name}-controller"
  }

  depends_on = [ null_resource.dependency_waiter ]
}

data "google_storage_bucket" "this" {
  name = var.slurm_bucket[0].name

  depends_on = [var.slurm_bucket]
}

### Slurm NodeSet
locals {
  nodeset = {
    gke_nodepool      = var.node_pool_names[0]
    nodeset_name      = var.nodeset_name
    node_count_static = var.node_count_static
    subnetwork        = "https://www.googleapis.com/compute/v1/projects/${var.project_id}/regions/${var.subnetwork.region}/subnetworks/${var.subnetwork.name}"
    instance_template = var.instance_templates[0]
  }
}

resource "google_storage_bucket_object" "gke_nodeset_config" {
  bucket  = data.google_storage_bucket.this.name
  name    = "${var.slurm_bucket_dir}/nodeset_configs/${var.nodeset_name}.yaml"
  content = yamlencode(local.nodeset)
}

resource "null_resource" "dependency_waiter" {
  # The triggers map is the key. When the value of the slurm_operator_chart_dependency
  # variable changes, this resource will be replaced. More importantly, Terraform
  # sees that this resource cannot be created until it receives this value.
  triggers = {
    chart_name = var.slurm_operator_chart
  }
}