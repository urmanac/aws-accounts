talm template -e 10.10.1.101 --nodes 10.10.1.101 -t templates/controlplane.yaml -i > nodes/node1.yaml
talm template -e 10.10.1.102 --nodes 10.10.1.102 -t templates/worker.yaml -i > nodes/node2.yaml
talm template -e 10.10.1.103 --nodes 10.10.1.103 -t templates/worker.yaml -i > nodes/node3.yaml
