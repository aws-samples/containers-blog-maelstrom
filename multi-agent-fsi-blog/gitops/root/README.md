# App-of-apps root
# ArgoCD applies every *.yaml here (directory source, recurse=true). Each file
# is one Application pointing at an addon chart or manifest path.
# Sync waves drive ordering:
#   -1  CRDs (Gateway API, agentgateway CRDs)
#    0  Flux (source-controller, notification-controller)
#    1  Tofu Controller (needs Flux)
#    2  Agent Gateway (needs CRDs)
#    3  LiteLLM (independent)
#    4  financial-services stack (needs Agent Gateway + Tofu Controller + LiteLLM)
