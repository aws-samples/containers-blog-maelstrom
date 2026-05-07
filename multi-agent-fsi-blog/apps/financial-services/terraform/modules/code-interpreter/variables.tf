variable "name" {
  description = "Name for the code interpreter resource"
  type        = string
}

variable "description" {
  description = "Description for the code interpreter resource"
  type        = string
  default     = "Agent Core Code Interpreter for Python execution"
}

variable "network_mode" {
  description = "Network mode (PUBLIC, VPC, or SANDBOX)"
  type        = string
  default     = "PUBLIC"
}

variable "tags" {
  description = "Tags to apply to the code interpreter resource"
  type        = map(string)
  default     = {}
}
