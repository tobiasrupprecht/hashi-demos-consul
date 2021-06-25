# Learn Guide for reference:
# https://learn.hashicorp.com/tutorials/consul/kubernetes-minikube

# Start Minikube (increase docker memory if needed)
minikube start --memory 4096

# Add helm repo
helm repo add hashicorp https://helm.releases.hashicorp.com

# Create config.yaml for Consul based on helm values
cat > config.yaml <<EOF
global:
  name: consul
  datacenter: t-dc
server:
  replicas: 1
  securityContext:
    runAsNonRoot: false
    runAsGroup: 0
    runAsUser: 0
    fsGroup: 0
ui:
  enabled: true
  service:
    type: 'NodePort'
connectInject:
  enabled: true
controller:
  enabled: true
EOF

# Deploy Consul
helm install -f config.yaml consul hashicorp/consul

# List minikube services
minikube service list

# Access UI - use additional terminal
# kubectl port-forward consul-server-0 8500:8500
minikube service consul-ui

# Access the Consul Container (Server) directly
kubectl exec -it consul-server-0 -- /bin/sh

# Check the version and consul members inside the Container
consul version
consul members

# Create a deployment definition for the Counting Service
cat > counting.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: counting
---
apiVersion: v1
kind: Service
metadata:
  name: counting
spec:
  selector:
    app: counting
  ports:
  - port: 9001
    targetPort: 9001
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: counting
  name: counting
spec:
  replicas: 1
  selector:
    matchLabels:
      app: counting
  template:
    metadata:
      annotations:
        'consul.hashicorp.com/connect-inject': 'true'
      labels:
        app: counting
    spec:
      containers:
      - name: counting
        image: hashicorp/counting-service:0.0.2
        ports:
        - containerPort: 9001
EOF

# Create a deployment definition for the Dashboard Service

cat > dashboard.yaml <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard
---
apiVersion: v1
kind: Service
metadata:
  name: dashboard
spec:
  selector:
    app: dashboard
  ports:
  - port: 9002
    targetPort: 9002
---
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: dashboard
  name: dashboard
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dashboard
  template:
    metadata:
      annotations:
        'consul.hashicorp.com/connect-inject': 'true'
        'consul.hashicorp.com/connect-service-upstreams': 'counting:9001'
      labels:
        app: dashboard
    spec:
      containers:
      - name: dashboard
        image: hashicorp/dashboard-service:0.0.4
        ports:
        - containerPort: 9002
        env:
        - name: COUNTING_SERVICE_URL
          value: 'http://localhost:9001'
EOF

# Deploy the Counting & Dashboard Service
kubectl apply -f counting.yaml
kubectl apply -f dashboard.yaml

# List the Services again
minikube service list

# If stopped running, bring the UI back - use additional terminal
# kubectl port-forward consul-server-0 8500:8500
minikube service consul-ui

# Check out the Dashboard that we've deployed - new terminal window
# Check the UI on localhost:9002
kubectl port-forward deploy/dashboard 9002:9002

# Create Service Intention to deny traffic between Dashboard & Counting (can also be done in the UI)
cat > deny.yaml <<EOF
apiVersion: consul.hashicorp.com/v1alpha1
kind: ServiceIntentions
metadata:
  name: dashboard-to-counting
spec:
  destination:
    name: counting
  sources:
    - name: dashboard
      action: deny
EOF

# Apply the created definition 
kubectl apply -f deny.yaml

# Check the UI on localhost:9002 and you'll see that the counting Service is not reachable anymore
# Also check the Intentions in the Consul UI

# Delete the intention to allow traffic again
kubectl delete -f deny.yaml

#############################################################

# You could add a connectInject.default setting and set to true. When this setting is present and set to true,
# the injector will inject the Consul service mesh sidecars into all pods by default.
# If the default is set to true, pods can still use the same annotation to explicitly opt-out of injection.

# Add the following o the config.yml
connectInject:
  enabled: true
  default: true

# Use helm upgrade to enable the new default
helm upgrade consul -f config.yaml hashicorp/consul

# You can use helm upgrade to increase the number of agents, enable additional features,
# upgrade the Consul version, or change your configuration.