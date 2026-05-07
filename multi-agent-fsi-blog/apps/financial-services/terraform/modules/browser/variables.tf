variable "name" {
  description = "Name for the browser resource"
  type        = string
}

variable "description" {
  description = "Description for the browser resource"
  type        = string
  default     = "Agent Core Browser for web browsing"
}

variable "network_mode" {
  description = "Network mode (PUBLIC, VPC, or SANDBOX)"
  type        = string
  default     = "PUBLIC"
}

variable "tags" {
  description = "Tags to apply to the browser resource"
  type        = map(string)
  default     = {}
}
