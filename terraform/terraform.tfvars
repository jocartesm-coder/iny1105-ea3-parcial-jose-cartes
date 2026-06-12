# Valores para el Learner Lab — ajusta según tu entorno
region        = "us-east-1"
cluster_name  = "iny1105-ea3-cluster"
node_type     = "t3.small"
nodes_desired = 2
nodes_min     = 1
nodes_max     = 3

ecr_repo_name = "prometheus-healthtrack"
image_tag     = "1.0.0"

namespace      = "monitoring"
nodeport_act31 = 30090
nodeport_act32 = 30092
