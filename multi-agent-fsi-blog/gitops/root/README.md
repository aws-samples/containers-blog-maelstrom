# App-of-apps root
# ArgoCD applies every *.yaml here (directory source, recurse=true). Each file
# is one Application pointing at an addon chart or manifest path.
# Sync waves drive ordering:
#   -1  CRDs (Gateway API, agentgateway CRDs)
#    0  auto-mode-defaults (default StorageClass + IngressClass)
#    1  agentcore-rgds (kro ResourceGraphDefinitions for the AgentCore composite
#        kinds; the ACK + kro controllers are installed by the EKS Capabilities
#        created in terraform/cluster)
#    2  Agent Gateway + agent-gateway-config (needs CRDs)
#    3  LiteLLM (independent)
#    4  financial-services stack (needs Agent Gateway + AgentCore RGDs + LiteLLM)
