variable "name" {
  description = "Name for the memory resource"
  type        = string
}

variable "description" {
  description = "Description for the memory resource"
  type        = string
  default     = "Agent Core Memory for conversation context"
}

variable "event_expiry_duration" {
  description = "Event expiry duration in days"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags to apply to the memory resource"
  type        = map(string)
  default     = {}
}
